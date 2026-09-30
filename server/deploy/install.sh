#!/usr/bin/env bash
# 练了么 · 后端一键部署（阶段 4）
#
# 跑法（在服务器上，root）：
#     DOMAIN=api.example.com bash server/deploy/install.sh
#     DOMAIN=api.example.com bash server/deploy/install.sh --dry-run   # 只看它打算做什么
#
# 三条纪律（改这个脚本时别破坏）：
#   1. **幂等**：能重复跑。第二次跑不该报错，也不该把数据抹了；
#   2. **失败就停**：`set -euo pipefail`，任何一步不过就别往下走；
#   3. **不猜域名**：没给 DOMAIN 直接退出 —— 猜错的证书会把 HTTPS 弄成一半。
#
# 它**不做**的事：买服务器、解析域名、备案、装 Node（只检查版本）。
set -euo pipefail

DOMAIN="${DOMAIN:-}"
APP_DIR="${APP_DIR:-/opt/lianleme}"
DATA_DIR="${DATA_DIR:-/var/lib/lianleme}"
SVC_USER="${SVC_USER:-lianleme}"
BACKEND_PORT="${BACKEND_PORT:-8790}"
COLLECTOR_PORT="${COLLECTOR_PORT:-8787}"
DRY_RUN=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "✗ 不认识的参数：$a（只支持 --dry-run）" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SERVER="$(cd "$HERE/.." && pwd)"     # server/
say() { printf '  %s\n' "$*"; }
step() { printf '\n▶ %s\n' "$*"; }
run() {
  if [ "$DRY_RUN" = 1 ]; then say "[dry-run] $*"; else eval "$*"; fi
}

if [ -z "$DOMAIN" ]; then
  echo "✗ 必须先给域名：DOMAIN=api.example.com bash $0" >&2
  echo "  （域名要已经解析到这台机器 —— Caddy 靠它申请 HTTPS 证书）" >&2
  exit 2
fi

step "0/7 环境检查"
if [ "$(id -u)" != "0" ] && [ "$DRY_RUN" != 1 ]; then
  echo "✗ 要以 root 跑（要建系统用户、装 systemd 单元、写 /opt 与 /etc）" >&2
  exit 2
fi
NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "✗ 找不到 node —— 先装 Node 22.5+（服务端用内置 node:sqlite）" >&2
  exit 2
fi
NODE_VER="$("$NODE_BIN" -p 'process.versions.node')"
say "node $NODE_VER（$NODE_BIN）"
"$NODE_BIN" -e '
  const [maj, min] = process.versions.node.split(".").map(Number);
  const ok = maj > 22 || (maj === 22 && min >= 5);
  if (!ok) { console.error(`✗ Node ${process.versions.node} 太旧：node:sqlite 要 22.5+`); process.exit(1); }
' || exit 2

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
    say "[dry-run] 渲染 $tpl → $out（APP_DIR/DATA_DIR/USER/PORT 逐个替换）"
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

step "5/7 装 Caddy 与反代配置（TLS 由它申请）"
if command -v caddy >/dev/null 2>&1; then
  say "caddy 已装"
else
  say "没有 caddy —— 按官方源装（这一步我不替你改镜像源）"
  run "apt-get update && apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl"
  run "curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
  run "curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null"
  run "apt-get update && apt-get install -y caddy"
fi
run "install -d -o root -g root -m 755 /etc/caddy"
if [ "$DRY_RUN" = 1 ]; then
  say "[dry-run] 渲染 Caddyfile → /etc/caddy/Caddyfile（域名 $DOMAIN）"
else
  sed -e "s#__DOMAIN__#$DOMAIN#g" \
      -e "s#__BACKEND_PORT__#$BACKEND_PORT#g" \
      -e "s#__COLLECTOR_PORT__#$COLLECTOR_PORT#g" \
      "$HERE/Caddyfile" > /etc/caddy/Caddyfile
fi
run "systemctl reload caddy || systemctl restart caddy"

step "6/7 自检：两个服务都得应答 /healthz"
if [ "$DRY_RUN" = 1 ]; then
  say "[dry-run] curl -fsS http://127.0.0.1:$BACKEND_PORT/healthz"
  say "[dry-run] curl -fsS http://127.0.0.1:$COLLECTOR_PORT/healthz"
else
  sleep 2
  curl -fsS "http://127.0.0.1:$BACKEND_PORT/healthz" && echo
  curl -fsS "http://127.0.0.1:$COLLECTOR_PORT/healthz" && echo
  echo "  等一下让 Caddy 申请证书，然后：curl -fsS https://$DOMAIN/healthz"
fi

step "7/7 完成"
say "对外地址：https://$DOMAIN"
say "客户端要编三个常量进去（缺 LIANLEME_BACKUP_DISCLOSED，入口不会出现）：
       --dart-define=LIANLEME_BACKUP_URL=https://$DOMAIN
       --dart-define=LIANLEME_BACKUP_DISCLOSED=true
       --dart-define=LIANLEME_ANALYTICS_URL=https://$DOMAIN/v1/events
     并把 docs/privacy-facts.json 的 cloudBackup.enabledInDistributedBuild 翻成 true
     （同步改中英政策正文；privacy-audit 是硬门禁，漏了直接判红）"
say "库文件：$DATA_DIR/backend.sqlite（核密文：node tool/check-ciphertext.mjs <库>）"
say "日志：journalctl -u lianleme-backend -f"
