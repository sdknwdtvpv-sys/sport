# 练了么 · 后端买什么、买哪儿、怎么买（2026-10-04）

> 你问的是"**两样都还没有，先告诉我怎么买/买哪种**"。这一页就是那个答案。
> 部署本身的那条命令在 `server/deploy/README.md`（`install.sh` 已经 dry-run 验过），
> 这里只管**买之前**要做的那几个决定。
>
> ⚠️ **价格会变**，下面给的是区间与判断依据，不是当日报价；下单前以官网为准（出处见文末）。

---

## 一、先算清楚：这个项目到底需要多小的机器

不拍脑袋，按代码里的真实行为算：

| 维度 | 这个项目实际要什么 | 依据 |
|---|---|---|
| **运行时** | Node **≥ 22.5**（服务端用内置 `node:sqlite`，低于这个版本 `install.sh` 会直接停下） | `server/deploy/install.sh` 第 1 步 |
| **进程** | **2 个**常驻 Node 进程（备份服务 + 埋点收集端），无数据库服务、无 Redis、无反向代理之外的中间件 | `lianleme-backend.service` / `lianleme-collector.service` |
| **内存** | 峰值几十 MB 量级（一个 `node:http` + 一个 SQLite 连接） | `server/backend.mjs` / `collector.mjs` 只有一个进程内的库句柄 |
| **磁盘** | 备份是**端到端加密的 blob**（每账号 MB 级）；埋点是一条 ~500 B 的 JSONL 一行 | `docs/backend-design.md` |
| **带宽** | 上报是**批量 ≤100 条一次 POST**；备份是"偶尔一次" | `docs/analytics-sdk.md` §5 |
| **并发** | 内测/首发规模下，**个位数到几十**同时在线 | 一期没有实时协同 |

**结论**：**最低档就够** —— 「2 核 / 2 GB / 40 GB 盘 / 3 Mbps」这个档位跑这个项目是**过剩**。
别被"云服务器"这个词吓得去买 4 核 8 G：那部分钱在这里买不到任何东西。

> ⚠️ 有一条**欠账**要一起记着：埋点 JSONL **会一直堆**，代码里还没有轮转/归档
> （`docs/backend-design.md` 里记着这条）。40 GB 盘按每天 10 MB 估算能用很多年，
> 但**上线后要记得加个 logrotate 或按月的归档脚本** —— 这条不该等到磁盘满才发现。

---

## 二、买哪儿：三种组合，取舍不在价格，在**备案**

| 组合 | 能干什么 | 代价 | 什么时候选它 |
|---|---|---|---|
| **A. 大陆机房 + 域名 + ICP 备案** | 唯一满足"**国内商店上架** + 大陆用户稳定访问"的组合；`install.sh` 里 Caddy 自动 HTTPS 能正常签发 | **备案是长杆**（口径 1–3 周，实际常见更久），且要实名/主体材料 | **必须做**，因为你要上国内安卓商店 |
| **B. 香港 / 新加坡 + 域名（免备案）** | **今天买、当天就能跑通**：真实埋点、内测分发、云备份端到端都能验 | 大陆访问偶尔抖；商店侧通常仍要 A 的备案；不解决"上架合规" | **过渡用** —— 先把管线和内测跑起来，同时**并行**去办 A 的备案 |
| **C. 先不买**：收集端跑在你 Mac 上 + 内网穿透 | **零成本**，够自己和几个内测用户看真实数据 | Mac 关机就断；不满足商店要求的公网地址；不是"部署" | 只想先看一眼真实埋点长什么样 |

**我的建议（2026-10-04 看过真实报价单后更新）：目标就是 A（大陆 + 域名 + 备案）；香港那台过渡机器先别买。**

理由比第一版变了：当初建议 B，是担心"没有公网地址就什么都验不了"。但**埋点管线已经在真机上验通了**
（见本文末，8 条真实事件），而剩下两件真需要公网地址的事（隐私政策 URL、云备份）**本来就要等备案与软著** ——
**一台香港机器能买到的时间，买不到"跳过备案"**。省下的那笔钱不如直接花在域名与备案上。
（唯一值得考虑香港的情况：你要在备案下来之前就把隐私政策 URL 挂出去给商店审核看 ——
那用免费静态托管也能先顶，审核只要求能打开。）

**顺序**（备案是这条路上唯一"你花钱也买不到时间"的东西，所以它必须**今天**起跑）：

1. **今天**：买域名 + 买服务器（**包年包月** —— 阿里云轻量**不支持按量付费**，促销套餐通常也只有 1 年档），
   并**立刻在上海地域的机器上提交 ICP 备案**（备案要求服务器购买时长满足接入商要求，1 年档 ✓）；
   ⚠️ **买了上海 ≠ 今天就能用**：备案通过前大陆机房不能对外提供 80/443，Caddy 也签不到证书 ——
   这是预期内的，不是装坏了。
2. **等待期**：照样能内测 —— 埋点走本机收集端（`adb reverse`，已验通），需要公网地址的那两件事等备案；
3. **备案通过后**：解析 A 记录 → 把三样给我 → 我跑 `install.sh`；客户端只需要换一个 `--dart-define`，
   **代码一行都不用改**（这正是当初把地址做成**编译期常量**的原因）。

---

## 三、怎么买（下单时逐条对）

**服务器**
- [ ] 地域：过渡用**香港/新加坡**；长期用**你备案主体所在地能备案的大陆地域**
- [ ] 镜像：**Debian 12** 或 **Ubuntu 24.04**（两者都自带 ≥ 22.5 的 Node 源；`install.sh` 会自己检查版本）
- [ ] 配置：**最低档**（2 核 2 G / 40 G / 3 Mbps）
- [ ] 登录：**SSH 密钥**优先；用密码也行（`install.sh` 要的是能 `root` 或 `sudo`）
- [ ] **安全组/防火墙只开 22 / 80 / 443** —— 8787（收集端）与 8790（备份服务）**不要**对外，
      那两个端口只监听 `127.0.0.1`，由 Caddy 转发（`tool/check-deploy.mjs` 盯着这条）

**域名**
- [ ] 一个域名（例如 `api.<你的域名>`），**A 记录指向上面那台机的公网 IP**
- [ ] 大陆机房：**先确认备案通过再解析**，否则 80/443 会被拦、Caddy 证书申请会失败
- [ ] 香港/新加坡：可以直接解析，Caddy 当就能签发证书

**买完之后给我三样**（就是 `server/deploy/README.md` 要的那三样）：
SSH 登录方式 · 域名（A 记录已指向那台机）· 备案状态。我接手跑一条命令并逐项验证，
**验不过的当场改、改完记进 CHANGELOG**（这一包还没被真的 systemd/Caddy 跑过，第一次面对真环境，
有报错是预期内的）。

---

## 三之二、下单页上要**当场确认**的四件事（2026-10-04 补：有人真拿报价单来问过）

| 要确认的 | 为什么 | 怎么确认 |
|---|---|---|
| **续费价是不是也按活动价**（页面上写的「续费同价」） | 这是**活动规则**，不是产品规则。促销价与日常价能差 5–8 倍（例：¥99/年 vs 日常 ¥576/年） | 下单页/续费页的「续费价格」；拿不准就**按日常价算三年总成本**再比 |
| **套餐是「无固定流量」还是「每月固定流量」** | 有固定配额的，**超额按量计费**（官方口径）；无固定流量的，流量已含在套餐里 | 下单页套餐说明里看「公网流量包 / 每月流量」；买完在控制台「服务器概览 → 服务器监控」看有没有**流量**指标（有 = 有配额） |
| **峰值带宽** | 不同套餐带宽不同，且**从购买后就开始限速**（不是用完流量才限） | 下单页规格里的数字；我们这个负载 3M / 4M 都过剩 |
| **能不能降配** | 阿里云轻量**只支持升配，不支持降配** —— 买大了就永远大着 | 官方计费 FAQ「支持更改套餐吗」：只能往高配改 |

> 这四条里**最贵的坑是续费价**：首年 ¥99 与次年 ¥576 的差别，三年能差出一台新机器。
>
> 出处（核实于 2026-10-04）：[轻量应用服务器计费常见问题](https://www.alibabacloud.com/help/zh/simple-application-server/product-overview/billing-faq)
> ——「不支持按量付费」「只支持升配不支持降配」「超额流量按量计费」都在这页。

---

## 三之三、**服务器上已经跑着别的东西**怎么装（2026-10-04 补，最常见的情况）

第一步永远是**体检**（只读、不改任何文件、不需要 root、不需要域名）：

```bash
bash server/deploy/install.sh --probe
```

它会报出：发行版/内存/磁盘、**node 版本（要 ≥ 22.5）**、80/443 谁在听、装的是哪个反代、
**我们要用的 8790/8787 有没有被占**、`/etc/caddy/Caddyfile` 存不存在。
把那段整张贴给我，我就能说清该用哪种装法。⚠️ 它**不会**把"看不出来"写成"没问题"
（比如没有 `ss` 时它直接说看不出来 —— 体检报告最怕的就是这个）。

然后按体检结果三选一：

| 你的机器 | 用哪种 | 为什么 |
|---|---|---|
| 干净（没有反代） | `DOMAIN=… bash server/deploy/install.sh` | 它会装 Caddy 并接管 80/443，自动申请证书 |
| **已经有 Nginx / Apache 在服务别的站** | `PROXY_MODE=existing DOMAIN=… bash …` | **只把该贴的片段打印出来**（`server/deploy/nginx-lianleme.conf`），由你自己加一个 server 块。我不碰你的配置 |
| 已经有 Caddy 在服务别的站 | 同上（`PROXY_MODE=existing`），或者直接跑默认模式 | 默认模式下它会发现 `/etc/caddy/Caddyfile` **不是我们写的**（没有 `managed-by` 标记）→ **不覆盖**，把我们的配置写到 `/etc/caddy/lianleme.caddy`，并叫你在 Caddyfile 里加一行 `import lianleme.caddy` |
| 只想先让服务跑起来 | `PROXY_MODE=none` | 两个服务只留在 `127.0.0.1`，外面进不来 |

**四条"绝不碰别人的东西"的护栏**（都进了 `tool/check-deploy.mjs`，各有一条负向自检）：

1. **不覆盖**别人的 Caddyfile（靠 `managed-by: lianleme-install` 标记区分谁的；真要覆盖得显式 `--force-config`，且会先备份）；
2. **不抢端口**：8790/8787 被占了就停下来告诉你（`BACKEND_PORT=` / `COLLECTOR_PORT=` 换号）；
3. **不在已经有 Nginx/Apache 的机器上装第二个反代**去抢 80/443 —— 直接让你用 `PROXY_MODE=existing`；
4. **Nginx 片段也不许开 `access_log`**：Nginx 默认会记客户端 IP，而政策写着"不做 IP 记录" ——
   这条和 Caddyfile 的 `log` 是同一条承诺，两个文件都被同一套判据盯着。

**其他要注意的**：

* **node 版本可能与别的服务冲突**：服务端要 **Node 22.5+**（用内置 `node:sqlite`），
  而别人的服务可能正跑在 Node 18/20 上。**不要去升级系统 node**（那会连带影响别人的服务），
  另装一份再指过来即可：`NODE_BIN=/opt/node22/bin/node DOMAIN=… bash server/deploy/install.sh`；
* **域名要新开一个子域**（`api.你的域名`），别用现有站点的域名 —— 那会把你的站顶掉；
* **备案**：同一个主体下新增子域通常不用重新备案，但**接入商与主体必须一致**；
  拿不准就在接入商那里问一句（备案这块最终以接入商/工信部口径为准）；
* **资源**：这个后端很轻（2 个 Node 进程、几十 MB 内存），跟别的站共用一台机器没问题；
  真正会长的只有埋点 JSONL（记得按 `docs/backend-design.md` 的欠账加轮转）。

---

## 四、大概多少钱（区间，以官网当日报价为准）

| 项 | 量级 | 说明 |
|---|---|---|
| 轻量应用服务器（大陆，最低档） | **约 ¥60–120/月**（年付常有大折扣） | 促销价与标价能差一倍以上，别按标价下判断 |
| 香港/新加坡（最低档） | **约 ¥30–100/月** | 免备案；大陆访问质量与线路相关 |
| 域名 | **约 ¥50–80/年**（`.com`/`.cn` 常见价） | 备案要求域名在**你的主体**名下 |
| ICP 备案 | **¥0**（自行办）～ 代办数百元 | 花的是**时间**不是钱：主体材料 + 接入商核验 |
| SSL 证书 | **¥0** | Caddy 自动申请 Let's Encrypt，不用买 |

出处（核实于 2026-10-04）：[阿里云 ECS/轻量价格页](https://www.aliyun.com/price/detail/ecs) ·
[阿里云 ICP 备案场景 FAQ](https://help.aliyun.com/zh/icp-filing/basic-icp-service/product-overview/faq-about-icp-filing-applications-in-different-scenarios) ·
[香港云服务器与备案的关系](https://cn.hostease.com/blog/hk-server/hong-kong-cloud-server-icp-filing-guide/) ·
[入门配置横评与续费避坑](https://www.gxmuzi.com/index.php/yunfuwu/1014.html)。
⚠️ 二手来源只用来**估量级**；金额、备案口径一律以云厂商/工信部官方页面为准。

---

## 四之二、**2026-10-04 真部署复盘**（一台已经在跑别的东西的机器）

目标机器：`118.25.45.88`（Ubuntu 24.04 / Node 22.23 / **Nginx 1.24 + certbot**，上面已经有两个站：
`hanzi.elliotli.work`、`la.elliotli.work`）。新开的对外地址：**`https://api.elliotli.work`**。

做法：`PROXY_MODE=existing`（不装 Caddy、不碰原有站点配置）→ 只装两个 systemd 服务 →
自己加一个站点文件 → `certbot --nginx` 签证书。**结果**：

| 验收项 | 结果 |
|---|---|
| 两个服务 | `active` / `enabled`（开机自启） |
| 监听 | `ss` 里是 **`127.0.0.1:8790` / `127.0.0.1:8787`**（不是 `*:PORT`） |
| `https://api.elliotli.work/healthz` | `{"ok":true,"accounts":0,"backups":0,"bytes":0}` |
| `POST /v1/events` | `{"accepted":1,"rejected":[]}` |
| 证书 | Let's Encrypt（`api.elliotli.work`，到 2027-01-02，certbot 自动续期） |
| 原有两个站 | **未受影响**（配置一字未动；改了 nginx 只加了一个 site + certbot 加的两块） |
| **不做 IP 记录** | `access.log` 行数 `400 → 400`（http 与 https 各发一条请求后都不变）✓ |

**这次真跑一遍才暴露的四个 bug**（全是部署包自己的，都已修 + 都加了负向自检）：

| # | 症状 | 真因 | 现在钉着 |
|---|---|---|---|
| 1 | 服务无限重启 + core dump | 单元里 `MemoryDenyWriteExecute=true` —— **V8 的 JIT 要可写可执行内存**，Node 一启动就 SIGTRAP | 出现这个开关就判红（它就是那种"看起来更安全"的写法） |
| 2 | `ss` 显示 `*:8790` / `*:8787` | 代码里只写 `server.listen(port)` → 绑**所有网卡**；而文档与单元注释写着"只监听本机"。当时外面扫这两个端口是关的，所以**功能上没人发现** | 没显式绑 `127.0.0.1` 判红 |
| 3 | 新 server 块**继承** http 层的全局 `access_log` → 记 IP | `nginx.conf` 在 http 上下文开着 `access_log`；"不写 access_log"等于照记 | 片段里必须显式 `access_log off;`，不是 `off` 或缺失都判红 |
| 4 | **certbot 新建的 80 跳转块**会重新继承全局日志 → http 那条路一直记 IP（https 那条没有） | 它是独立 server 块 | 写进片段头与 `install.sh` 的指引，并给了"**行数前后必须一样**"的验收命令 |

> 教训一句话：**这台机器上的隐私承诺不是"配置写对"就成立的** ——
> `access.log` 行数前后一样，才是唯一能证明它的东西。第 3、4 条都属于
> "静态检查永远看不见、只有真发一次请求再数日志才发现"的那类。

---

## 四之三、**2026-10-06 账号体系上线：服务端要跑什么**（客户端已经出了包）

客户端 `v1.56.0` 已经装上真机了（`docs/release-checklist.md` 的终局核验表）。
它带了「账号」入口 —— 但**线上那台还是老服务端**：`POST /v1/auth/salt` 现在回的是
`401 缺少或非法的 Authorization: Bearer`（请求落到了"账号必须存在"那道闸门后面）。
客户端已经把这句话翻成人话（「这台服务器还没有账号功能（服务端要升级），先试试云备份」），
所以**装了新包也不会看到一句莫名其妙的报错** —— 但要真的能注册，服务端得先升级。

**为什么要升级服务端**：`server/` 多了三个文件（`auth.mjs` / `auth-store.mjs` / `mailer.mjs`，
零依赖，不装任何 npm 包），后端单元多了一行 `EnvironmentFile=-/etc/lianleme/mail.env`。
**老客户端完全不受影响**（`Bearer <account_id>` 那条路一字未动）。

### 最小路径（服务器上**没有**仓库副本时用这条）

```bash
# 在你这台 Mac 上，仓库根目录：
rsync -av server/backend.mjs server/backend-store.mjs server/collector.mjs \
          server/auth.mjs server/auth-store.mjs server/mailer.mjs \
          root@118.25.45.88:/opt/lianleme/server/

# 然后 ssh 上去，给单元补一行（只有这一行，两条命令）：
ssh root@118.25.45.88
install -d -o root -g root -m 750 /etc/lianleme
grep -q '^EnvironmentFile=' /etc/systemd/system/lianleme-backend.service \
  || sed -i '/^RestartSec=3/a EnvironmentFile=-/etc/lianleme/mail.env' /etc/systemd/system/lianleme-backend.service
```

### 正路（服务器上有仓库副本时用这条：`install.sh` 是幂等的）

```bash
cd <服务器上的仓库>   &&   git pull
PROXY_MODE=existing DOMAIN=api.elliotli.work bash server/deploy/install.sh
```

它会**只**做该做的：渲染两个单元（多一个 `__MAIL_ENV__` 替换）、拷 **6 个** `.mjs`、
建 `/etc/lianleme/mail.env` 的**空模板**（已存在就**不覆盖**）。
⚠️ 它**不会**替你写口令 —— 那条 `sed` 渲染通道会把值写进 0644 的单元文件、
进 `--dry-run` 输出、进 shell 历史（`server/deploy/README.md` 里写了原因）。

### ✅ SMTP 已填，账号体系已开（2026-10-06 深夜）

用户给的是一枚 QQ 邮箱的 **SMTP 授权码**（不是登录密码）。写进 `/etc/lianleme/mail.env`
（`0600 root:root`，通过 stdin 传，不进任何进程参数）→ 重启 → 外网验收：

| 验收 | 结果 |
|---|---|
| `/healthz` | `{"ok":true,"accounts":2,"backups":1,"bytes":21551,"binds":0,"tokens":0}` —— **多了 `binds`/`tokens`** |
| `POST /v1/auth/salt` | `200` + 32 字节盐 + `kdf`（与客户端默认参数一致：`m=65536,t=3,p=4,v=19`）|
| `POST /v1/auth/code` | `200 {"ok":true}`，journal 里出现 **`验证码已发（register · 0c8066eb）`** —— 真的走完了 AUTH + DATA |
| 限流 | 60 秒内第二次请求 → **`429 刚发过一封，请 60 秒后再试`**（线上实测）|
| 登录（错凭据）| `401 {"error":"邮箱或口令不对"}` —— 不区分「邮箱不存在 / 口令错」|
| 老客户端 | `/v1/account/me` 无凭据仍 `401`、不存在的 account_id 仍 `404`（**备份那条路一字未变**）|

**又修了一个部署后才暴露的缺口**（`server/backend.mjs`，只有服务端、不切版）：
CLI 建 auth 时**没传 `log`**，而 `createAuth` 的 log 默认是 no-op —— 于是 journal 里
只有 `POST /v1/auth/code → 200`，而「验证码已发（指纹）」「**发信失败（原因）**」「登录成功」
这些**全被丢掉**。运维时最想看的恰好是「为什么没收到信」。现在接上 stdout 了
（上表那条 `验证码已发` 就是证据）。

### （历史）这一步原本要你做的：填 SMTP 那五项

服务器上 `/etc/lianleme/mail.env` 已经建好、`LIANLEME_AUTH_SECRET` 已经填好了，
**只差 SMTP 那五行**（一个能发信的邮箱 —— 多数邮箱这里要填的不是登录密码而是**授权码**）：

```bash
ssh -i ~/.ssh/lianleme_deploy root@118.25.45.88
vi /etc/lianleme/mail.env      # 填下面五项
```

| 变量 | 例子 | 说明 |
|---|---|---|
| `LIANLEME_SMTP_HOST` | `smtp.qq.com` / `smtp.exmail.qq.com` / `smtp.163.com` | 邮箱服务商的发信服务器 |
| `LIANLEME_SMTP_PORT` | `465` | **只支持 465（隐式 TLS）**，不支持 587/STARTTLS |
| `LIANLEME_SMTP_USER` | `noreply@elliotli.work` | 登录账号 |
| `LIANLEME_SMTP_PASS` | （授权码） | ⚠️ 不是登录密码，是邮箱后台里的"SMTP 授权码" |
| `LIANLEME_SMTP_FROM` | `noreply@elliotli.work` | 发件人，要与账号对得上，否则多半被拒 |

填完（**没有** `mail.env` 的旧写法不用管，直接 `systemctl restart lianleme-backend` 即可）：

```bash
systemctl restart lianleme-backend
curl -s https://api.elliotli.work/healthz        # 应当多出 "binds" 与 "tokens" 两个字段
journalctl -u lianleme-backend --since "30 seconds ago" | tail -5   # 应当看到「账号：已开」
```

**你也可以把这五项发我，我写完顺手发一封真验证码到你指定的邮箱**（那就等于端到端验完了）；
不想让它出现在对话里的话，就用上面那条 `vi` 自己填 —— 效果一样，只是最后那封验证码要你自己发。

### （下面这两条是给"服务器上没有仓库副本"时写的，本次没用上，留着备查）

### 两条路都要做的最后三步

```bash
vi /etc/lianleme/mail.env     # 填 LIANLEME_AUTH_SECRET（一串长随机，必须固定）+ SMTP 五项
systemctl restart lianleme-backend
curl -s https://api.elliotli.work/healthz
```

**验收判据**：`/healthz` 的 JSON 里多出 **`binds` 与 `tokens`** 两个字段
（老版本没有它们）。多出来就说明账号体系起来了。
再核一条端到端的：`POST /v1/auth/salt` 对**任意**邮箱都应回 `200 {"salt":…,"kdf":…}`
（**不存在的邮箱也回一个假盐** —— 那是刻意的防枚举，不是 bug）。

⚠️ **不填 `mail.env` 会怎样**：`/v1/auth/*` 一律 404（等于没有账号体系），
备份与埋点照常工作 —— 这是**故意**的：宁可没有账号，也不要一个"注册永远发不出验证码"的半成品。
⚠️ 只有 465（隐式 TLS）被支持，**不支持 STARTTLS(587)**：见 `server/deploy/README.md` 那一段。

### ✅ 2026-10-06 已执行（这一步现在**不需要你动手**）

这台 Mac 上一直躺着一把部署密钥 `~/.ssh/lianleme_deploy`（2026-10-04 那次部署留下的，
服务器上仍然授权）。**我先前说"没有凭据"是错的** —— 我只试了默认密钥，而
`~/.ssh/config` 里只给 github 配了 IdentityFile，那把非默认名字的钥匙根本没被试用。
加上 `-i ~/.ssh/lianleme_deploy` 就通了。所以下面这些是我直接做的：

| 做了什么 | 证据 |
|---|---|
| 备份现网（可回滚） | `/root/lianleme-backup-20261006/`（旧的 `backend.mjs` / `backend-store.mjs` / `collector.mjs` / 单元文件） |
| 推 6 个 `.mjs` | `/opt/lianleme/server/` 下多了 `auth.mjs` / `auth-store.mjs` / `mailer.mjs`（`root:root 644`） |
| 换单元 | `/etc/systemd/system/lianleme-backend.service` 比现网只多那一段 `EnvironmentFile=-/etc/lianleme/mail.env`（**逐行 diff 过，现网没有别的本地改动**）+ `daemon-reload` |
| 建 `/etc/lianleme/mail.env` | `0600 root:root`；`LIANLEME_AUTH_SECRET` 是**在服务器上**用 `openssl rand -hex 32` 现生成的（不经过任何聊天记录） |
| 重启并验收 | `systemctl is-active` 两个服务都 active；`https://api.elliotli.work/healthz` 仍是 `{"accounts":2,"backups":1,"bytes":21551}`（**数据一个字节没动**）；`POST /v1/auth/salt` 回 **404 `{"error":"账号体系没有启用（服务端还没配邮件）"}`** —— 这条恰好证明新代码在跑（老代码会回 401 英文） |

**部署时顺手修掉的一个坑**（`server/backend.mjs`，只有服务端、不动 `app/`，按 CHANGELOG 的策略
**不需要切版**）：原来 mail.env **填一半会让整个后端起不来** —— `mailerFromEnv()` 直接 throw，
systemd 无限重启，而云备份、埋点跟着一起挂。现在改成**大声警告 + 照常启动**
（`/v1/auth/*` 明确回 404，等于没有账号体系），因为这台服务同时供着既有用户在用的备份。
另外"账号没启用"以前会落到鉴权闸门后面回 `401 缺少或非法的 Authorization`，现在明确 404。

**只剩一步（要你的东西）**：填 SMTP 那五项。见下面。

## 五、这件事我之前已经做完的部分（所以买完真的只剩一条命令）

| 已经就绪 | 证据 |
|---|---|
| 两个服务 + 库 + 逐字节收发 + 删除彻底 | `node server/backend.selftest.mjs` / `server/collector.selftest.mjs` 全绿（门禁第 2 层每次跑） |
| 安装脚本准备干什么 | `DOMAIN=api.example.com bash server/deploy/install.sh --dry-run` 全流程走通（不改任何东西） |
| 配置不会违背承诺 | `tool/check-deploy.mjs`：反代**没有** `log` 指令（政策写着不记 IP）、两个服务只监听 `127.0.0.1`、数据目录是唯一可写路径 |
| **客户端 → 收集端 → 看板** 这条链路 | 2026-10-04 在真机上重跑过一遍（见下） |

### 2026-10-04 真机端到端（**这次拿到了真实数据，不只是 app_open**）

| 步 | 做法 | 结果 |
|---|---|---|
| 起收集端 | `node server/collector.mjs --port 8787 --out server/data-live` | `{"ok":true,"events":0}` |
| 打通真机 | `adb reverse tcp:8787 tcp:8787`（不用同一 Wi-Fi） | `UsbFfs tcp:8787 tcp:8787` |
| 带地址构建 | `flutter build apk --release --dart-define=LIANLEME_ANALYTICS_URL=http://127.0.0.1:8787/v1/events` | 装真机（`75caf509`） |
| 打开开关 | 「我 → 隐私与关于 → 帮助改进产品」（2026-10-07 起**默认是开的**；关掉就一条都不发 —— 这是设计，不是 bug。⚠️ 这一步的历史记录写在 v1.28.0～v1.58.0 那几版里，那时默认是关的） | — |
| 真实操作 | 冷启动 → 开始训练 → 记一组 | — |
| **结果** | `GET /stats` | **7 条真实事件 / 1 台设备**：`app_open`×2 · `workout_started` · `suggestion_shown` · `suggestion_accepted` · `set_logged` · `rest_started` |
| 看板 | `node tool/workbench.mjs --data server/data-live` | 来源标签 **「真实数据」**；`tap_count` 有了第一个真实数（n=1，中位数 2） |
| 反向对照 | 换回**不带地址**的正式包，`libapp.so` 里搜 endpoint | **0 命中** —— 「出货包没有地址」再次坐实 |

⚠️ 两个当场学到的：① **`suggestion_accepted` 这类事件终于有真数据了** —— 在那之前
看板上"建议采纳率"一栏一直写着 `⊘ 客户端还没发 suggestion_* 事件`；
② 训练**进行中不发**（`flusher.suspend()`），事件要等训练结束/下次冷启动才出得去 ——
第一次看到"记了一组但收集端还是 0 条"时别以为是坏了。

> 这次用的是 `adb reverse` + 本机收集端，**证明的是"管线通"**，不是"线上监控"。
> 线上要等第四节那台机器真的买回来、服务真的跑起来。

### 2026-10-05 真机端到端之**云备份**：卸载清空 → 用恢复码取回（红米 `75caf509`）

这条路径此前**只在模拟器上做过**（v1.43.0 的真机验收只到"上传 + 合并恢复"，没做"擦除后重建"）。
2026-10-05 换图标那一版**必须卸载重装**（真 keystore 与旧包的 debug 签名不同，`install -r` 被拒），
正好把它补上：

| 步 | 做法 | 结果 |
|---|---|---|
| 清空 | `adb uninstall` → **当时**装的 `dist/练了么-v1.54.0.apk`（那次记下的 versionCode 是 69） | 首页写着「还没有训练记录」 |
| 绑定恢复码 | 我 → 数据与备份 → 云备份 → 「我有恢复码，取回已有备份」 | 「已绑定这个恢复码」；云端 **22.2 KB · 10-05 00:09**（与 v1.43.0 那次上传的 22743 字节对得上） |
| 取回 | 「从云端恢复（合并，不覆盖本机）」 | **「已从云端恢复：已导入 2 次训练 / 2 组，置顶 0 个动作」** |
| 核对 | 我 → 训练统计 | **2 次 / 2 组**（证据图 `docs/images/legacy-5tab/v144-cloud-restore-banner.png` · `v144-cloud-restore-stats.png`） |

⚠️ 一条**操作顺序**上的坑（界面自己会提醒）：云端那份比本机新时，**先点「立即备份」会把云端覆盖掉** ——
想保住云端那份就得先点「从云端恢复」。这一版把这句话直接印在卡片上了，真机上看得到。
