#!/usr/bin/env bash
# 练了么 · 后端一键部署（阶段 4）
#
# 跑法（在服务器上，root）：
#     DOMAIN=api.example.com bash server/deploy/install.sh
#     DOMAIN=api.example.com bash server/deploy/install.sh --dry-run   # 只看它打算做什么
#
# **这台机器上已经跑着别的东西？先跑这个**（只体检、不改任何文件、不需要 root、不需要域名）：
#     bash server/deploy/install.sh --probe
#
# 然后按体检结果选一种：
#     PROXY_MODE=existing DOMAIN=api.example.com bash server/deploy/install.sh
#         → 我不碰你的反代配置，只把该贴的片段打印给你（Nginx / 已有 Caddy 都行）；
#     PROXY_MODE=none     DOMAIN=… bash server/deploy/install.sh
#         → 连片段都不要，两个服务只留在 127.0.0.1 上。
#
# 五条纪律（改这个脚本时别破坏）：
#   1. **幂等**：能重复跑。第二次跑不该报错，也不该把数据抹了；
#   2. **失败就停**：`set -euo pipefail`，任何一步不过就别往下走；
#   3. **不猜域名**：没给 DOMAIN 直接退出 —— 猜错的证书会把 HTTPS 弄成一半；
#   4. **绝不碰别人的东西**（2026-10-04 加）：这台机器上可能已经跑着别的服务 ——
#      **不覆盖**已有的反代配置、**不抢**已占用的端口、**不擅自装第二个反代**。
#      要改别人的配置，只能把片段打印给你、由你自己改（`PROXY_MODE=existing`）；
#   5. **端口可换**：默认 8790/8787 被占了就 `BACKEND_PORT=` / `COLLECTOR_PORT=` 覆盖，
#      脚本会把该改的地方一起改（包括打印给你的反代片段）。
#
# 它**不做**的事：买服务器、解析域名、备案、装 Node（只检查版本）。
set -euo pipefail

DOMAIN="${DOMAIN:-}"
APP_DIR="${APP_DIR:-/opt/lianleme}"
DATA_DIR="${DATA_DIR:-/var/lib/lianleme}"
SVC_USER="${SVC_USER:-lianleme}"
BACKEND_PORT="${BACKEND_PORT:-8790}"
COLLECTOR_PORT="${COLLECTOR_PORT:-8787}"
PROXY_MODE="${PROXY_MODE:-caddy}"     # caddy | existing | none
NODE_BIN="${NODE_BIN:-}"              # 留空 = 用 PATH 里的 node
DRY_RUN=0
PROBE=0
FORCE_CONFIG=0

for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --probe) PROBE=1 ;;
    --no-proxy) PROXY_MODE=existing ;;
    --force-config) FORCE_CONFIG=1 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "✗ 不认识的参数：${a}（支持 --dry-run / --probe / --no-proxy / --force-config）" >&2; exit 2 ;;
  esac
done
case "$PROXY_MODE" in
  caddy|existing|none) ;;
  *) echo "✗ PROXY_MODE 只能是 caddy / existing / none，收到：$PROXY_MODE" >&2; exit 2 ;;
esac

# ⚠️ 用 `cat install.sh | bash` 喂进来时 `BASH_SOURCE[0]` 是未定义的（`set -u` 会当场报
# "unbound variable"）—— 第一版就踩到了。`:-$0` 兜底，再在下面明确拒绝这种跑法。
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo '')"
REPO_SERVER="$(cd "$HERE/.." && pwd)"     # server/
say() { printf '  %s\n' "$*"; }
step() { printf '\n▶ %s\n' "$*"; }
run() {
  if [ "$DRY_RUN" = 1 ]; then say "[dry-run] $*"; else eval "$*"; fi
}
# 端口是不是有人听着（`ss` 是 iproute2 自带，服务器上都有；没有就退化成"不知道"）
port_busy() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | grep -qE "[:.]$1\$"
}
# 我们的服务是不是已经在跑了（幂等：第二次跑时端口必然"被占"，那是我们自己）
ours_running() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-active --quiet lianleme-backend.service && return 0
  systemctl is-active --quiet lianleme-collector.service && return 0
  return 1
}

# ── 体检：只读，不改任何东西 ─────────────────────────────────────────────
# 为什么单独做一条：这个部署包是给"干净的机器"写的，而**大多数人的服务器上已经有别的东西**
# （自己的站、别的服务、另一个反代）。直接跑安装会踩三件事：覆盖 Caddyfile、抢 80/443、抢端口。
# 所以先看一眼现实，再决定怎么装。
if [ "$PROBE" = 1 ]; then
  echo "练了么 · 部署体检（只读；没改任何文件）"
  echo
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    say "系统：${PRETTY_NAME:-未知}"
  else
    say "系统：$(uname -sr)"
  fi
  say "内核：$(uname -r)　身份：$(id -un)（uid $(id -u)）"
  if [ "$(uname -s)" != "Linux" ]; then
    say "⚠️ 这不是 Linux（$(uname -s)）—— 这个部署包只支持 Linux + systemd，下面这些数字仅供参考"
  fi
  say "systemd：$(command -v systemctl >/dev/null 2>&1 && echo 有 || echo '没有 —— 这个部署包靠 systemd 拉起服务')"
  say "内存：$(free -h 2>/dev/null | awk '/^Mem:/{print $2" 总 / "$7" 可用"}' || echo 未知)"
  say "根盘：$(df -h / | awk 'NR==2{print $2" 总 / "$4" 可用 / 已用 "$5}')"
  echo
  PROBE_NODE="${NODE_BIN:-$(command -v node || true)}"
  if [ -n "$PROBE_NODE" ]; then
    say "node：$PROBE_NODE · $("$PROBE_NODE" -p 'process.versions.node' 2>/dev/null || echo '跑不起来')（要 ≥ 22.5）"
  else
    say "node：**没装** —— 服务端要 Node 22.5+（用内置 node:sqlite）"
  fi
  echo
  # ⚠️ 没有 `ss` 时**不许说"空着"** —— 那是"不知道"，不是"没占用"。
  # 体检报告最怕的就是把"看不出来"写成"没问题"（这个项目里叫"过期状态比没有状态更坏"的近亲）。
  if command -v ss >/dev/null 2>&1; then
    for p in 80 443; do
      if port_busy "$p"; then say "端口 ${p}：**有人在听**"; else say "端口 ${p}：空着"; fi
    done
    echo "    听 80/443 的是：$(ss -ltnp 2>/dev/null | awk 'NR>1 && ($4 ~ /:80$/ || $4 ~ /:443$/){print $4" "$6}' | tr '\n' ' ')"
    for p in "$BACKEND_PORT" "$COLLECTOR_PORT"; do
      if port_busy "$p"; then say "端口 ${p}（我们要用的）：**被占了** → 换个号，例如 BACKEND_PORT=18790"; else say "端口 ${p}（我们要用的）：空着 ✓"; fi
    done
  else
    say "端口占用：**看不出来**（这台机器上没有 ss）—— 到服务器上跑这一段才有意义"
  fi
  echo
  # 只有 Linux + systemd 上才判断得了"在不在跑"；判断不了就直说，别写个"未知"混过去
  if command -v systemctl >/dev/null 2>&1; then
    say "反代：$(for b in caddy nginx apache2 httpd; do command -v "$b" >/dev/null 2>&1 && printf '%s(%s) ' "$b" "$(systemctl is-active "$b" 2>/dev/null || echo 未运行)"; done)"
  else
    say "反代：$(for b in caddy nginx apache2 httpd; do command -v "$b" >/dev/null 2>&1 && printf '%s ' "$b"; done)—— 没有 systemctl，看不出在不在跑"
  fi
  if [ -f /etc/caddy/Caddyfile ]; then
    say "/etc/caddy/Caddyfile **已存在**（$(wc -l < /etc/caddy/Caddyfile) 行）→ 安装脚本默认不会覆盖它"
  else
    say "/etc/caddy/Caddyfile 不存在"
  fi
  for d in /etc/nginx/conf.d /etc/nginx/sites-enabled /etc/apache2/sites-enabled; do
    [ -d "$d" ] && say "$d 里有：$(ls "$d" 2>/dev/null | tr '\n' ' ')"
  done
  echo
  say "把上面整段贴给我就行 —— 我据它决定用哪种装法（要不要换端口 / 用 PROXY_MODE=existing）。"
  exit 0
fi

if [ -z "$DOMAIN" ]; then
  echo "✗ 必须先给域名：DOMAIN=api.example.com bash $0" >&2
  echo "  （域名要已经解析到这台机器 —— Caddy 靠它申请 HTTPS 证书）" >&2
  echo "  在这台机器上已经有别的站时，用一个**新子域**（api.example.com），别用现有站点的域名。" >&2
  exit 2
fi

# 部署包必须"整个目录"都在（要读 Caddyfile / nginx-lianleme.conf / 两个 .service）。
# 管道喂进来时 HERE 是当前目录、这些文件不在，早点说清比后面报"找不到文件"强。
if [ ! -f "$HERE/Caddyfile" ] || [ ! -f "$HERE/nginx-lianleme.conf" ]; then
  echo "✗ 找不到部署包里的模板文件（HERE='$HERE'）" >&2
  echo "  是不是用管道跑的（cat install.sh | bash）？请先把整个 server/ 目录放上去：" >&2
  echo "    scp -r server/ root@<你的机器>:/tmp/lianleme-server/" >&2
  echo "    bash /tmp/lianleme-server/deploy/install.sh --probe" >&2
  exit 2
fi

step "0/7 环境检查"
if [ "$(id -u)" != "0" ] && [ "$DRY_RUN" != 1 ]; then
  echo "✗ 要以 root 跑（要建系统用户、装 systemd 单元、写 /opt 与 /etc）" >&2
  exit 2
fi
if [ -z "$NODE_BIN" ]; then
  NODE_BIN="$(command -v node || true)"
fi
if [ -z "$NODE_BIN" ]; then
  echo "✗ 找不到 node —— 先装 Node 22.5+（服务端用内置 node:sqlite）" >&2
  echo "  这台机器上的 node 太旧或没有？可以另装一份再指过来：" >&2
  echo "    NODE_BIN=/opt/node22/bin/node bash $0 …" >&2
  exit 2
fi
NODE_VER="$("$NODE_BIN" -p 'process.versions.node')"
say "node ${NODE_VER}（${NODE_BIN}）"
"$NODE_BIN" -e '
  const [maj, min] = process.versions.node.split(".").map(Number);
  const ok = maj > 22 || (maj === 22 && min >= 5);
  if (!ok) { console.error(`✗ Node ${process.versions.node} 太旧：node:sqlite 要 22.5+`); process.exit(1); }
' || exit 2

# 端口预检：**这台机器上已经有别的东西**是最常见的情况，抢端口的表现是"服务起不来、
# systemd 一直重启"，而日志里只有 EADDRINUSE —— 不如现在就停下来把话说明白。
if ours_running && [ "$FORCE_CONFIG" != 1 ]; then
  say "检测到 lianleme 的服务已在运行（幂等重跑），跳过端口预检"
else
  for p in "$BACKEND_PORT" "$COLLECTOR_PORT"; do
    if port_busy "$p"; then
      echo "✗ 端口 $p 已经被别的东西占了 —— 我不抢别人的端口。" >&2
      echo "  换一组再跑（反代片段会跟着换）：" >&2
      echo "    BACKEND_PORT=18790 COLLECTOR_PORT=18787 DOMAIN=$DOMAIN bash $0" >&2
      exit 2
    fi
  done
  say "端口 $BACKEND_PORT / $COLLECTOR_PORT 都空着 ✓"
fi

step "1/7 建服务用户（不能登录）"
if id "$SVC_USER" >/dev/null 2>&1; then
  say "用户 $SVC_USER 已存在，跳过"
else
  run "useradd --system --home-dir '$DATA_DIR' --shell /usr/sbin/nologin '$SVC_USER'"
fi

step "2/7 建目录（数据目录是唯一可写的地方）"
run "install -d -o root -g root -m 755 '$APP_DIR'"
run "install -d -o '$SVC_USER' -g '$SVC_USER' -m 750 '$DATA_DIR'"
run "install -d -o root -g root -m 755 '$APP_DIR/server'"

step "3/7 拷代码（只拷服务端要用的 3 个文件）"
for f in backend.mjs backend-store.mjs collector.mjs; do
  run "install -o root -g root -m 644 '$REPO_SERVER/$f' '$APP_DIR/server/$f'"
done
say "库文件位置：$DATA_DIR/backend.sqlite（首次启动自动建）"

step "4/7 装 systemd 单元"
render() {  # render <模板> <目标>
  local tpl="$1" out="$2"
  if [ "$DRY_RUN" = 1 ]; then
    say "[dry-run] 渲染 $tpl → ${out}（APP_DIR/DATA_DIR/USER/PORT/NODE 逐个替换）"
    return 0
  fi
  sed -e "s#__APP_DIR__#$APP_DIR#g" \
      -e "s#__DATA_DIR__#$DATA_DIR#g" \
      -e "s#__USER__#$SVC_USER#g" \
      -e "s#__BACKEND_PORT__#$BACKEND_PORT#g" \
      -e "s#__COLLECTOR_PORT__#$COLLECTOR_PORT#g" \
      -e "s#__NODE__#$NODE_BIN#g" \
      "$tpl" > "$out"
  chmod 644 "$out"
}
render "$HERE/lianleme-backend.service" /etc/systemd/system/lianleme-backend.service
render "$HERE/lianleme-collector.service" /etc/systemd/system/lianleme-collector.service
run "systemctl daemon-reload"
run "systemctl enable --now lianleme-backend.service"
run "systemctl enable --now lianleme-collector.service"

step "5/7 反向代理（PROXY_MODE=${PROXY_MODE}）"
CADDY_CONF=/etc/caddy/Caddyfile
CADDY_MARK='# managed-by: lianleme-install'
render_proxy_snippet() {
  sed -e "s#__DOMAIN__#$DOMAIN#g" \
      -e "s#__BACKEND_PORT__#$BACKEND_PORT#g" \
      -e "s#__COLLECTOR_PORT__#$COLLECTOR_PORT#g" \
      "$1"
}

if [ "$PROXY_MODE" = "existing" ]; then
  # 最常见的情况：机器上已经有 Nginx / Caddy 在服务别的站。
  # **只打印，不改** —— 改别人的配置是只有你能承担后果的动作。
  say "按你的要求**不碰**这台机器上的任何反代配置。"
  say "把下面这段加进你现有的配置里（只加一个新的 server 块，别动别的站）："
  echo
  render_proxy_snippet "$HERE/nginx-lianleme.conf"
  echo
  say "要点：① 只 proxy 到 127.0.0.1:$BACKEND_PORT / 127.0.0.1:${COLLECTOR_PORT}；"
  say "      ② 片段里的 access_log off; **别删** —— 这台机器的 http 块开着访问日志，"
  say "         不显式关掉，我们这几条路径就会把客户端 IP 记下来（政策写着不做 IP 记录）；"
  say "      ③ reload 之后 curl https://$DOMAIN/healthz 应当返回 {\"ok\":true,…}。"
  say "      （用的是 Caddy 也可以，把这个域名块并进你的 Caddyfile。）"
  if command -v certbot >/dev/null 2>&1; then
    say "      这台机器上已经有 certbot（Let's Encrypt）—— 证书直接用它的，别另装 Caddy："
    say "        sudo certbot --nginx -d $DOMAIN"
    say "      ⚠️ 签完证书它会**新建一个 80 端口跳转块**，那个块也要加 access_log off;"
    say "         （实测：只关一个块，http 那条路的客户端 IP 照样进日志）。验收方法："
    say "         wc -l < /var/log/nginx/access.log → 发一条 http 请求 → 再看，行数必须不变。"
    say "      ⚠️ 它会**改写你的站点配置**，跑之前先备份 /etc/nginx/sites-enabled/。"
  fi
  say "      ⚠️ 如果这台机器的 nginx.conf 在 http 块里开着 access_log（你这台就是），"
  say "         ⚠️ 片段里的 access_log off; 是**承诺的一部分**，不是可选项。"
elif [ "$PROXY_MODE" = "none" ]; then
  say "跳过反代（PROXY_MODE=none）：两个服务只监听 127.0.0.1，外网进不来。"
  say "  什么时候用：只想先让服务跑起来、等域名/备案就绪再接反代。"
else
  # ── caddy 模式：三条"绝不碰别人的东西"的护栏 ───────────────────────────
  # ① 已经在跑 Nginx/Apache 的机器：不装第二个反代跟它抢 80/443；
  # ② 已有别人写的 Caddyfile：不覆盖（只写我们自己的文件 + 告诉你怎么 import）；
  # ③ 我们的 Caddyfile（带标记）：可以覆盖 —— 那是幂等重跑。
  if command -v caddy >/dev/null 2>&1; then
    say "caddy 已装"
  else
    OTHER_PROXY=""
    for b in nginx apache2 httpd; do
      if command -v "$b" >/dev/null 2>&1; then OTHER_PROXY="$b"; fi
    done
    if [ -n "$OTHER_PROXY" ]; then
      echo "✗ 这台机器上装的是 ${OTHER_PROXY}（正在服务别的站），我不装第二个反代去抢 80/443。" >&2
      echo "  用这个跑法：把片段打印出来，你自己加进 ${OTHER_PROXY}：" >&2
      echo "    PROXY_MODE=existing DOMAIN=$DOMAIN bash $0" >&2
      exit 2
    fi
    say "没有 caddy —— 按官方源装（这一步我不替你改镜像源）"
    run "apt-get update && apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl"
    run "curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    run "curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null"
    run "apt-get update && apt-get install -y caddy"
  fi
  run "install -d -o root -g root -m 755 /etc/caddy"

  if [ "$DRY_RUN" = 1 ]; then
    say "[dry-run] 渲染 Caddyfile → /etc/caddy/Caddyfile（域名 ${DOMAIN}）"
    say "[dry-run] 若 /etc/caddy/Caddyfile 已存在且不是我们写的 → 改成写 /etc/caddy/lianleme.caddy，不覆盖"
  elif [ -f "$CADDY_CONF" ] && ! grep -qF "$CADDY_MARK" "$CADDY_CONF" && [ "$FORCE_CONFIG" != 1 ]; then
    # 别人的 Caddyfile：一个字节都不动。
    render_proxy_snippet "$HERE/Caddyfile" > /etc/caddy/lianleme.caddy
    chmod 644 /etc/caddy/lianleme.caddy
    say "⚠️ /etc/caddy/Caddyfile 已经存在，而且不是我们写的 —— **没有覆盖它**。"
    say "   我们的配置写到了 /etc/caddy/lianleme.caddy，你要在 Caddyfile 里手工加一行："
    say "       import lianleme.caddy"
    say "   加完执行：systemctl reload caddy"
    say "   （确认没有冲突也可以强制覆盖：--force-config，它会先备份原文件。）"
  else
    if [ -f "$CADDY_CONF" ] && [ "$FORCE_CONFIG" = 1 ]; then
      run "cp -a '$CADDY_CONF' '$CADDY_CONF.bak.$(date +%s)'"
      say "已备份原 Caddyfile（--force-config）"
    fi
    render_proxy_snippet "$HERE/Caddyfile" > "$CADDY_CONF"
    chmod 644 "$CADDY_CONF"
  fi
  run "systemctl reload caddy || systemctl restart caddy"
fi

step "6/7 自检：两个服务都得应答 /healthz"
if [ "$DRY_RUN" = 1 ]; then
  say "[dry-run] curl -fsS http://127.0.0.1:$BACKEND_PORT/healthz"
  say "[dry-run] curl -fsS http://127.0.0.1:$COLLECTOR_PORT/healthz"
else
  sleep 2
  curl -fsS "http://127.0.0.1:$BACKEND_PORT/healthz" && echo
  curl -fsS "http://127.0.0.1:$COLLECTOR_PORT/healthz" && echo
  if [ "$PROXY_MODE" = "caddy" ]; then
    echo "  等一下让 Caddy 申请证书，然后：curl -fsS https://$DOMAIN/healthz"
  else
    echo "  反代没由我改：你加完片段、reload 之后再 curl -fsS https://$DOMAIN/healthz"
  fi
fi

step "7/7 完成"
if [ "$PROXY_MODE" = "caddy" ]; then
  say "对外地址：https://$DOMAIN"
else
  say "服务已经在 127.0.0.1:$BACKEND_PORT / 127.0.0.1:$COLLECTOR_PORT 上跑着了。"
  say "对外地址等你的反代配上：https://$DOMAIN"
fi
say "客户端要编三个常量进去（缺 LIANLEME_BACKUP_DISCLOSED，入口不会出现）：
       --dart-define=LIANLEME_BACKUP_URL=https://$DOMAIN
       --dart-define=LIANLEME_BACKUP_DISCLOSED=true
       --dart-define=LIANLEME_ANALYTICS_URL=https://$DOMAIN/v1/events
     并把 docs/privacy-facts.json 的 cloudBackup.enabledInDistributedBuild 翻成 true
     （同步改中英政策正文；privacy-audit 是硬门禁，漏了直接判红）"
say "库文件：$DATA_DIR/backend.sqlite（核密文：node tool/check-ciphertext.mjs <库>）"
say "日志：journalctl -u lianleme-backend -f"
if [ "$PROXY_MODE" != "caddy" ] || { [ -f "$CADDY_CONF" ] && ! grep -qF "$CADDY_MARK" "$CADDY_CONF" 2>/dev/null; }; then
  say "⚠️ 反代那一半要你自己动手（片段已打印/写在 /etc/caddy/lianleme.caddy）—— 这一步没做完，"
  say "   https://$DOMAIN/healthz 是不通的，云备份与埋点也就还没真正上线。"
fi
