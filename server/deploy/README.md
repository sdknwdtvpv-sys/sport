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
# 在服务器上（root）：
DOMAIN=api.example.com bash server/deploy/install.sh
# 只想看它打算做什么（不改任何东西，也不需要 root）：
DOMAIN=api.example.com bash server/deploy/install.sh --dry-run
```

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
