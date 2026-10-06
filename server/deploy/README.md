# 练了么 · 后端部署（阶段 4 的落地包）

**这一包是干什么的**：把 `server/` 那两个进程（备份服务 + 埋点收集端）从"本地能跑"
变成"一台真服务器上、带 HTTPS、开机自启、崩了会自己起来"。它**不替你买服务器**，
也不碰你的域名解析 —— 那些是你要做的事；买好之后，这一包让部署变成**一条命令**。

## 你要给我什么（三样，都是登录信息）

| # | 东西 | 用途 |
|---|---|---|
| 1 | 服务器 **IP + SSH 登录方式**（或在服务器上自己跑这一包） | 部署 |
| 2 | 一个 **域名**（例如 `api.lianleme.app`），A 记录指向上面那台机 | HTTPS 证书（Caddy 自动申请） |
| 3 | 备案状态（**大陆机房必须先备案**，否则 80/443 会被拦） | 决定能不能开 HTTPS |

> ⚠️ 如果服务器在**大陆**：域名要先 ICP 备案，否则 Caddy 申请证书会失败。
> 想先跑通用香港/新加坡节点试，备案可以晚一步（但国内商店上架要用大陆可访问的地址）。

## 装的时候发生了什么（`install.sh` 干的事）

1. 检查 Node ≥ **22.5**（服务端用内置 `node:sqlite`；低于这个版本直接停下并说明）；
2. 建一个**不能登录的系统用户** `lianleme`（服务不以 root 跑）；
3. `/opt/lianleme` 放代码、`/var/lib/lianleme` 放**数据**（库文件与埋点日志），
   后者是这个服务唯一可写的地方（systemd 里 `ProtectSystem=strict` + `ReadWritePaths`）；
4. 装两个 systemd 单元（`lianleme-backend` / `lianleme-collector`），**开机自启、崩了重启**；
5. 装 Caddy 配置：**只有一个对外域名**，`/v1/events` 走收集端、其余 `/v1/*` 走备份服务；
6. 在两个端口上各打一次 `/healthz`，**自己验一遍**再报成功。

```bash
# 0) **这台机器上已经跑着别的东西？先体检**（只读、不改文件、不需要 root、不需要域名）：
bash server/deploy/install.sh --probe

# 1) 干净机器（root）：
DOMAIN=api.example.com bash server/deploy/install.sh
#    只想看它打算做什么（不改任何东西，也不需要 root）：
DOMAIN=api.example.com bash server/deploy/install.sh --dry-run

# 2) 机器上已经有 Nginx / Caddy 在服务别的站 —— 我不碰你的配置，只打印该贴的片段：
PROXY_MODE=existing DOMAIN=api.example.com bash server/deploy/install.sh

# 3) 端口被别的服务占了 —— 换一组（反代片段会跟着换）：
BACKEND_PORT=18790 COLLECTOR_PORT=18787 DOMAIN=api.example.com bash server/deploy/install.sh
```

**四条"绝不碰别人的东西"**（2026-10-04 加，`tool/check-deploy.mjs` 盯着，各有一条负向自检）：
不覆盖别人的 Caddyfile（靠 `managed-by: lianleme-install` 标记区分；覆盖需显式 `--force-config` 且先备份）·
不抢已占用的端口 · 不在已有 Nginx/Apache 的机器上装第二个反代 · Nginx 片段同样不许开 `access_log`。

## 账号体系要用的环境变量（**口令不走单元文件**）

装了账号体系之后，服务端要读下面这些变量（代码真的会读的就是这几个；
`tool/check-deploy.mjs` 会拿这份文档与 `server/*.mjs` 逐字对账）：

| 变量 | 作用 | 不填的后果 |
|---|---|---|
| `LIANLEME_AUTH_SECRET` | 反枚举用的假盐密钥（任意一串长随机串，**必须固定**：换了它，客户端拿到的盐会漂） | 服务端**拒绝启动**（宁可起不来，也不要一套会漂的盐） |
| `LIANLEME_SMTP_HOST` | 邮件服务器（如 `smtp.qq.com`） | 没有账号体系：`/v1/auth/*` 一律 404，备份照常 |
| `LIANLEME_SMTP_PORT` | 默认 **465**（隐式 TLS）。⚠️ **不支持 STARTTLS（587）**：那要重开一次 TLS 并把后续对话换掉，而它的历史漏洞正是"剥离攻击"（中间人拦掉 STARTTLS 广告、客户端退回明文发口令）。主流邮箱都给 465 | —— |
| `LIANLEME_SMTP_USER` / `LIANLEME_SMTP_PASS` | SMTP 账号与**授权码**（不是登录密码） | 同上（没有账号体系） |
| `LIANLEME_SMTP_FROM` | 发件人地址（要与 SMTP 账号对得上，否则多半被拒） | 同上 |
| `LIANLEME_MAIL_OUT` | **只给本地与自检**：把邮件（含验证码）写到一个文件，不联网 | 生产**不要**设它 —— 那会把验证码写进服务器上的一个文件 |

**它们放在哪、为什么**：`install.sh` 会建一个 **root 0600** 的
`/etc/lianleme/mail.env`（空模板，**不覆盖已有的**），由你手工填；后端单元里是
`EnvironmentFile=-/etc/lianleme/mail.env`（前缀 `-` = 文件不存在也不阻止启动）。

**为什么不让安装脚本替你写**：`install.sh` 的 `render()` 是用 `sed` 把值渲染进
**0644 的 systemd 单元**的 —— 口令走那条路就是明文落盘、进 `--dry-run` 的输出、
还进 shell 历史（口令里带 `#`/`&`/`\` 更会直接破坏替换）。
所以这一条通道是刻意与其它配置**分开**的：路径走 sed（不是秘密），值走 0600 文件。

填完记得：`sudo systemctl restart lianleme-backend`，然后
`curl -s https://api.example.com/healthz` 应当多出 `binds` / `tokens` 两个字段
（有账号体系才会有它们）。

## 装完之后（我接手的部分）

```bash
# 1) 服务端自己活着的证据
curl -s https://api.example.com/healthz          # {"ok":true,"accounts":0,"backups":0}
# 2) 客户端指过去（三个编译期常量，缺一个都不算配好）
flutter build apk --release \
  --dart-define=LIANLEME_BACKUP_URL=https://api.example.com \
  --dart-define=LIANLEME_BACKUP_DISCLOSED=true \
  --dart-define=LIANLEME_ANALYTICS_URL=https://api.example.com/v1/events
```

⚠️ **`LIANLEME_BACKUP_DISCLOSED=true` 不是可选项**：只给地址不给这句话，
云备份入口**根本不会出现**（`app/lib/backup/backup_config.dart` 故意这么设计），
而政策正文此时还写着"本版本未提供云备份"。这是**故意让失败往"关闭"那边倒** ——
危险动作必须显式点头。

⚠️ **正式发版前还有一步不能忘**：把 `docs/privacy-facts.json` 的
`cloudBackup.enabledInDistributedBuild` 翻成 `true`，并同步改中英政策正文
（"数据会离开设备"那几句）。**这一步是硬门禁**：`tool/privacy-audit.mjs` 会拿
政策事实源与代码逐条对账，漏了直接判红。

然后我会：把地址编进正式包 → 在真机上跑一遍"备份 → 删本机 → 用恢复码恢复" →
核对服务端那份库里**只有密文**（`node tool/check-ciphertext.mjs <库>`）→ 政策与
`privacy-facts.json` 同步 → 切版。

## 三条与承诺有关的设计（不是随手写的）

1. **反向代理不开访问日志** —— 我们在政策里写着"不做 IP 记录"，而 Caddy 默认的
   access log 会把客户端 IP 写进磁盘。所以 `Caddyfile` 里**故意没有 `log` 指令**，
   `tool/check-deploy.mjs` 会盯着这件事（加了日志就判红）；
2. **两个服务只监听 `127.0.0.1`** —— 对外只有 Caddy 一个入口，端口不暴露；
3. **数据目录是唯一可写路径** —— 服务被攻破也写不到别处去。

## 这一包**没有**做的事（别误会）

* **没有被真正的 systemd / Caddy 验过** —— 开发机是 macOS，`systemd-analyze verify` 与
  `caddy validate` 都跑不了。目前验到的是：`bash -n install.sh`、`--dry-run` 全流程走通、
  以及 `tool/check-deploy.mjs` 的结构与交叉对账（端口/入口/占位符/加固/dart-define）。
  **第一次真的部署时，如果有 systemd 或 Caddy 的报错，那是这一包第一次面对真实环境** ——
  报错发我，改完再记进 CHANGELOG；
* 不买服务器、不解析域名、不备案 —— 那些只能你来做；
* 不做监控告警、不做异地备份 —— 一期只有"服务活着 + 库在磁盘上"，
  真出问题由 `install.sh` 的最后那步 healthz + systemd 重启兜底；
* 不做数据库增长治理：埋点 jsonl 会一直堆，`docs/backend-design.md` 里记了这条欠账。
