# 账号体系 · 邮箱 + 口令登录（P1-3）方案

> 2026-10-06 用户拍板：**做**，而且是「**必须先登录才能用**」。
> 这一页是施工前的方案（照 `docs/plan-scene-and-return.md` / `docs/plan-stage3-5.md` 的先例：
> 先写清"动什么、动哪几处、怎么验"，再动代码）。
>
> 这一页**取代** `docs/feature-backlog.md` §〇之二 里那条「账号体系：推迟到有盈利之后」。

## 〇、这条拍板撤销了什么（先说清楚，免得两个说法都在）

| 时间 | 说法 | 出处 | 现在的状态 |
|---|---|---|---|
| 2026-10-05 | 账号体系「放待办」（不删不做） | `docs/feature-backlog.md` §三；`docs/wechat-login-feasibility.md` | ❌ 已被覆盖 |
| 2026-10-06 | 「如果要花钱的话，就先不做，等项目有了盈利之后再做」+ 明确写「**别在它被重新提起之前提前做**」 | `docs/feature-backlog.md` §〇之二（commit `b97af0e`） | ❌ **已被 2026-10-06 的新拍板覆盖** |
| **2026-10-06（本轮）** | **做，且是「必须先登录才能用」**；先做邮箱 + 口令（¥0 那条），Apple / 微信登录仍不动 | 本轮用户点单 | ✅ **当前口径** |

**为什么值得单独记一笔**：`b97af0e` 那条拍板是"有意留白"，还专门写了"别提前做"。
撤销它的代价不是一句"改主意"——它同时是**三件事**：① 隐私定位从"没有账号系统"改成"有账号"；
② 服务端从"只存密文、不认识身份"变成"要认人、要发邮件、要存邮箱"；
③ 现有 15 处写给用户的承诺全部要改。所以这一页把这三件事逐条摊开。

## 一、形态（本期的边界）

**做**：

* 邮箱 + 口令**注册 / 登录**，且**必须先登录才能用**（登录是启动闸门）；
* **应用内注销**（中国法规硬要求；Apple 5.1.1(v) 同样要求）；
* 口令在**客户端**派生密钥 —— **服务端仍然读不到训练数据**（底线，见 §三）；
* 保留**恢复码**作为唯一找回路径（它是账号主密钥本身，不是口令的替代品）。

**不做**（本期明确不做，别顺手做）：

* 手机号 + 短信、微信登录、Sign in with Apple（各自要钱/要资质，`docs/wechat-login-feasibility.md` 已算过）；
* 多端**实时协同**、增量同步（一期仍只有快照式备份）；
* 服务端任何"顺手看一眼"用户数据的能力（永不）。

## 二、⚠️ 两条正面冲突（必须由用户知晓，不是我能替你消化的）

### ②-1 与仓库的**总判据**冲突

`docs/screens.md` 写死两条：

* S1（冷启动第一屏）的规则是「**无注册、无引导页、无授权请求**」（`docs/screens.md:61`）；
* 全项目的总判据是「**它能否让"第一次训练"更快发生？不能的，一期都不做**」
  （`docs/screens.md` 末尾；`PRODUCT.md` §1 的红线是"超过 3 次点击判负"）。

**"必须先登录才能用"= 在第一次训练之前插一道注册墙**，而注册要联网、要收验证码、要起密码。
它与这两条正面冲突，也与项目的北极星（**首练完成率**）冲突：多一道墙，首练分母就会掉。

同一份文档里还留着先例：S13 首次引导本来"拦启动"，最后**改成非阻塞**，理由就是这条总判据
（`docs/screens.md:641` 那一段）。所以这不是新问题，是同一个问题的第二次出现。

**我按拍板实现"必须先登录"**，但把"闸门放在哪一步"做成**一个常量**
（`AuthGate.mode`，见 §六），这样"改成首练之后才拦"是一行改动、不是一次重构。

### ②-2 与"离线优先"冲突

`docs/store-listing-ios.md:61` 的原话是「**完全离线**：健身房没信号也能记」，
`PRODUCT.md:73` 也写着「全局离线可用……健身房地下层没有信号」。
"必须先登录才能用"意味着**首次使用必须联网**。本期按下面这条口径落地，并把承诺改成准确的话：

* **首次登录需要联网**（一次性）；
* 登录后会话与本机数据都留在设备上，**之后长期离线可用**；
* **服务端不可达 / 服务器挂了，不许把已登录的用户挡在门外**（不阻塞启动，本机照用）；
* 会话有效期按"设备令牌"处理：**不做定时强制重登**；注销、改口令、在别处注销本设备时才失效。

### ②-3 与 **Apple 5.1.1(v)** 冲突（这条是**上架**级的，不是观感问题）

`docs/wechat-login-feasibility.md:93-94` 已经把这个指南抄回仓库了：
「**5.1.1(v)**：核心功能与社交网络无关时，**必须允许不登录使用**；只要提供了账号创建，
就必须提供 App 内账号删除」。

"必须先登录才能用"正撞在前半句上：这是一个**本地优先、核心功能（记录训练）不需要账号**的工具，
Apple 审核时最可能的结论就是"请允许用户不登录使用"。后半句（App 内注销）本期已经做了。

**处置**：① 这一条**不改变本期的实现**（闸门形态做成一个常量，见 §六），
② 但它是"提交前必须再看一眼"的硬风险，所以同时在 §八 风险表单列一行；
③ 真机/审核前若决定改成"可选"，代价是 `AuthGate.mode` 一个常量 + 少一处启动守卫，
**不是重构**。


## 三、密码学（这是本方案的核心，别改坏）

现有链路（`docs/backend-design.md` §三、§四；`app/lib/backup/`）：

```
随机 16 字节 account key
  ├─ SHA-256 → account_id                    （发给服务端当账号标识）
  ├─ HKDF-SHA256(info="lianleme/backup/v1") → DEK → AES-256-GCM 加密整包备份
  └─ Crockford-Base32 + 1 位校验 = 27 字符恢复码（给用户抄）
```

**改动只有一处：account key 从哪来。** 新的派生：

```
口令 + 每账号随机盐（服务端发放，32 字节）
  └─Argon2id→ KEK（只在设备上存在）
       ├─ 解包服务端存的 `wrapped_master`（AEAD(account key, KEK)）→ account key
       └─ HKDF(info="lianleme/auth/v1") → authVerifier（登录凭据；服务端只存它的 scrypt 值）
```

为什么这样切：

| 设计 | 理由 |
|---|---|
| **domain separation**：认证凭据与数据密钥出自不同 info | 服务端拿到 `authVerifier` 也**推不出** account key（HKDF 单向）。否则"服务端认证用户"就等于"服务端能解密数据" |
| **account key 由服务端"包着"存**（wrapped_master），不是口令直接算出来 | ① 改口令 = 重新包一次，**不用重加密备份、不会丢数据**；② 恢复码（= account key 本身）**永远有效**，所以忘口令不等于丢数据 |
| **account_id / DEK / 密文格式全部不变** | 云备份整条链路（`cloud_backup.dart`、`backup_crypto.dart`、`backend-store.mjs`、端到端测试、`check-ciphertext.mjs`）**不用改语义**；老账号（已有随机 key）也能原样"升级绑定邮箱" |
| 口令**永不出设备**；服务端只见 `authVerifier`、`wrapped_master`、盐 | 与"服务端只存密文"的既有承诺同源，政策里那句话可以只改主语、不改结论 |

### 诚实写下来的残余风险（不许含糊）

1. **拿到库的一方可以离线爆破口令**：`authVerifier` 与 `wrapped_master` 都是口令派生的，
   口令要是很弱，离线爆破成功 = 拿到 account key = 解密备份。
   缓解：Argon2id 参数按"最慢可接受的设备时间"定（见 §七的基准测试），
   口令最短 8 位 + 拒绝常见弱口令表（本地一份，不联网）。
   **一期的选择是不上 PAKE（SRP/OPAQUE）**：它能把这条风险也消掉，但代价是一套自研协议、
   两端都要写、还没法用现成库验证 —— 与"宁可引入可验证的依赖，也不写没跑过的原生代码"
   （`app/pubspec.yaml` 里那条纪律）同一条道理。**这条留在这里，不装作没有。**
2. 服务端**仍然**不认识"你是谁"以外的东西：备份依旧是原样收、原样还（`backend.mjs` 三条安全纪律不变）。
3. 邮箱本身是可识别信息 —— 它一定会出现在政策、收集清单、两张商店表单里（§五逐处列出）。

## 四、服务端（零依赖不变）

现有接口（`server/backend.mjs`）：`POST /v1/account`、`GET /v1/account/me`、`PUT|GET /v1/backup`、
`DELETE /v1/account`、`GET /healthz`；鉴权是 `Authorization: Bearer <account_id>`。

**新增**（全部在 `server/`，继续零依赖：`node:http` + `node:sqlite` + `node:crypto`）：

| 接口 | 作用 | 备注 |
|---|---|---|
| `POST /v1/auth/salt` | 拿这个邮箱的 KDF 盐 | **防枚举**：邮箱不存在时返回 HMAC(服务端密钥, 邮箱) 算出的**假盐**，形状完全一样 |
| `POST /v1/auth/code` | 发注册/找回验证码（6 位，10 分钟有效） | 限流：同一邮箱 **60 秒 1 条**、**24 小时 10 条**；同一 IP 也限 |
| `POST /v1/auth/register` | 邮箱 + 验证码 + `authVerifier` + `wrapped_master` + 盐 → 建号 | 幂等：同邮箱重复注册不覆盖已存在的号 |
| `POST /v1/auth/login` | 邮箱 + `authVerifier` → 会话令牌 | 失败限流（防在线爆破）；**响应不区分"邮箱不存在"与"口令错"** |
| `POST /v1/auth/logout` | 吊销**当前**令牌 | |
| `POST /v1/auth/change-password` | 旧口令验过 → 覆盖 `wrapped_master` 与 `authVerifier` | 恢复码那条路也能改口令（见 §六） |
| `DELETE /v1/account` | 注销（**应用内**，二次确认） | 账号 + 设备 + 备份 + 令牌全删，复用现有语义 |

* **令牌**：随机 32 字节，**服务端只存 scrypt 值**；`Authorization: Bearer <token>`。
  `account_id` 从此**不再**当凭据用（它是标识，不是凭据）。这条要写进 `backend-design.md`。
* **邮件发送**：在 `server/` 下新增邮件模块（`mailer.mjs`），用 `node:net`/`node:tls` 写一个**最小 SMTP 客户端**
  （AUTH LOGIN + 发信），配置走环境变量；**自检与本地跑**用 `--mail-out <文件>` 把验证码写文件，
  这样 `backend.selftest.mjs` **不需要真 SMTP** 就能端到端跑通。
* **日志纪律不变**：不打印 `Authorization`、不打印邮箱明文（只打 `sha256(email)[:8]` 这种指纹）、不记 IP。
* **限流状态**：落 sqlite（重启不丢），不引入 Redis。

## 五、政策与商店材料的改写清单

> 2026-10-06 侦察结果（逐处核过当前工作树）。**"没有账号系统"这句话的落点不是 15 处、
> 是 22 处源 + 7 份生成物**（`docs/feature-backlog.md` §〇之二 里那个数偏小，改的时候要一起更正）。
> ⚠️ 生成物的**行号会随重出漂**，施工时按**原文串**定位，不要按行号。

### 5.1 源（手写，人手改）

| 文件 | 位置 | 现在写的是 | 要改成 |
|---|---|---|---|
| `docs/privacy-facts.json` | `:208` | `device_id` 的 why「与账号无关」 | 「与账号无关」不再成立 → 改写 |
| 同上 | `:216` | `user_id` why「**恒为 null** —— 没有账号系统」 | 改 why；**它同时是 `check-store-forms` 的判据来源**（见 5.3） |
| 同上 | `:303` | `neverCollected`「姓名、手机号、**邮箱**、身份证」 | 邮箱**移出**这一列（它进收集清单） |
| `docs/privacy-policy.md` | `:48` | 「我们不要求注册、不要你的手机号…」 | 删「不要求注册」，补邮箱收集与用途 |
| 同上 | `:129` | `user_id` 行「恒为 null」 | 改写字段语义（**埋点仍然不带账号身份**，这句要留） |
| 同上 | `:147` | 「❌ 姓名、手机号、**邮箱**、身份证」 | 邮箱移出"不收集" |
| 同上 | `:392` | 附录 A「无账号系统 \| 全仓库无登录/注册代码」 | 整行改写（否则是假话） |
| 同上 | `:182`、`:202`(en) | 「§2.3 的 7 个公共字段」**交叉引用本身写错了** | 7 个公共字段在 §2.2；顺手修 |
| 同上新增 | §五（`:314-342` 一带） | 只有「删除全部数据」 | 新增**独立的「注销账号」**一行（`docs/screens.md:478` 早就写明"关闭 ≠ 注销"） |
| `docs/privacy-policy.en.md` | `:45 / :142 / :159 / :431` | 与中文四处一一对应 | 同中文；⚠️ **中英结构对账**（`tool/privacy-audit.mjs:590-639`）要求 h2/h3 数量与编号逐一对应 → 新增章节必须中英**同一次**改 |
| `docs/store-listing.md` | `:48`（短描述）、`:69-70`（长描述）、`:102`、`:112`、`:158` | 「没有账号、没有广告，数据只在你手机上」等 | 短/长描述重写；加「个人信息 → 邮箱」行；截图 9 文案跟着改 |
| `docs/store-listing-ios.md` | `:61` | 「完全离线……**没有账号**、没有广告、没有推送」 | 改成"登录后完全离线"+ 去掉"没有账号" |
| 同上 | `:91` | App Privacy 表 Device ID 行「否（匿名随机 id，**无账号**）」 | 三/四列如实改（邮箱**关联身份**）+ 新增 Email 行 |
| 同上 | `:176` | 审核备注「这个 App 不需要登录，也没有账号系统」 | **整段重写**：还要写明审核员怎么登录（否则审核直接卡住） |
| `同上` | `:78, :83, :184` | 变体 A「Data Not Collected」/「云备份在当前版本不可用」 | 与 `privacy-facts.json` 当前口径对齐（这两处疑似**既有漂移**，顺手定掉） |
| `PRODUCT.md` | `:32`（游客模式全功能可用）、`:47`（0 次注册）、`:73`（全局离线） | 与"必须先登录"直接矛盾 | 逐条改写 |
| `docs/screens.md` | `:61` | S1 规则「**无注册**、无引导页、无授权请求」 | 第一条作废（`:641-645` 的 S13 先例可引） |
| `docs/copyright-manual.md` | `:27` | 「软件不要求注册、不索取手机号…」 | **这是交给版权局的材料**，必须改；改完重出 `dist/copyright/` |
| `docs/copy.md` | `:88` | 「训练数据只存在这台设备上」文案决策 | 跟着改 |
| `docs/monetization-plan.md` / `docs/plan-vi-migration.md` | `:26` / `:29,:64` | 「不建议做账号体系」「账号层 P0 不做」 | 标注**已被覆盖**（别留两个说法） |
| `app/ios/Runner/PrivacyInfo.xcprivacy` | `:53` | `NSPrivacyCollectedDataTypes` 是**空数组** | 必须非空（Email Address）；⚠️ **没有守卫核它**（`check-ios-app` 只核 tracking=false） |
| `app/lib/features/today/today_screen.dart` | `:329` | 注释「没有账号，所以不写"下午好，某某"」 | 注释也是事实陈述，改掉 |
| `app/lib/backup/cloud_backup.dart` / `recovery_code.dart` | `:5` / `:3` | 「没有手机号、没有邮箱、没有密码」 | 改 |

### 5.2 生成物（**不许手改**，改源后跑 `node tool/gen-privacy-page.mjs` 重出）

`store-assets/privacy/index.html` · `store-assets/privacy/en.html` ·
`app/assets/privacy-policy.txt` · `app/assets/collection-list.txt`；
另有 `dist/copyright/*`（← `docs/copyright-manual.md`）与 `练了么-工作台.html`（← 文档）。
守卫：`tool/gen-privacy-page.mjs --check`（`verify.sh:370`）逐字节比对。

### 5.3 会被门禁咬到的判据（**必须一起改，否则要么红要么变假话**）

| 守卫 | 它现在怎么判 | 加账号后必须做什么 |
|---|---|---|
| `tool/check-store-forms.mjs` | `:194-196` 从 `privacy-facts.json` 的 `user_id.why` 里**按字面**匹配「恒为 null / 没有账号」推出 `noAccount`，再据此要求两张表单的"是否关联身份/是否共享"全是「否」（`:203-211`） | **这条判据本身要重写**：写成"看 facts 里 `collected` 有没有邮箱"之类的事实，而不是匹配一句人话；同时把 App Privacy 表新邮箱行如实填"是" |
| 同上 | `:113-123` 变体 A/B 结构（按"云备份地址配没配"分） | 账号与编译期开关**无关** → 变体的定义要重新想清楚（否则"两个都没配"不再是变体 A 的判据） |
| `tool/privacy-audit.mjs` | ⑮ 中英 h2/h3 数量与编号逐一对应（`:590-639`）；⑥ 文档里的"22 类事件"必须等于 `facts.events.length`（`:216-231`）；④ facts 里每个名字都要在中英正文出现（`:190-211`） | 新章节中英成对；若给登录加埋点，事件数、两版政策数字、收集清单**一起**动 |
| `tool/check-user-text.mjs` | `app/lib/**/*.dart` 的**字符串字面量**不许含 `**` / `开发者` / `号文` / `待填` 等（`:43-59`） | 新五屏每一句文案都受它管 |
| `tool/check-guards-wired.mjs` | 每个 `server/*.selftest.mjs` 必须在 `verify.sh` 里真的跑 | 本轮已加 `mailer` / `auth` 两条 |
| `tool/check-deploy.mjs` | 新 dart-define 要"客户端代码含 `fromEnvironment` + README 写名字"；模板新增 `__占位符__` 要双向覆盖（`:304-321`、`:338-351`） | 加 SMTP 配置时**必须**照这两条走 |
| `tool/check-doc-facts.mjs` | 「N 类事件 / N 个公共字段」在**全部文档**里必须等于事实 | ⚠️ **它只有自检在跑，真检查从未接线**（`verify.sh` 里只有 `selfcheck`）—— 这一期顺手补上，否则数字漂了没人拦 |
| `app/test/delete_all_test.dart` | 表清单守门（`:126-158`）+ 删除后逐表 0 行（`:114-121`） | 新表 `auth_session`：① 加进硬编码清单 ② **必须在 `seedEveryUserTable()`（`:56-104`）里塞一行**，否则"删没删"根本测不出来（计划早先漏了这一步） |
| `app/test/widget_test.dart` | `:63-64` 断言第一屏**没有**「登录」「注册」 | 加闸门后会红 —— 要按新事实重写，**不许悄悄放宽** |


## 六、客户端改动面

* **闸门位置（2026-10-06 按代码核实后改正）**：不是"插在 `main()` 里"—— `main()`
  （`app/lib/main.dart:82-85`）只有字体许可登记 + `runApp`，**建库 / 埋点冷启动 / 种子导入 /
  reminder 同步全在 `_HomeShellState.initState()` 的三个并发分支里**。真正的缝是 `build()` 的三道门
  （`main.dart:1374-1397`）：新增登录门插在**政策同意门之后、首启引导之前**
  （先讲清政策、再要身份），照 `:1377-1379` 的先例：状态没读出来时给空屏，**不许闪一下主界面**。
* ⚠️ **只插 `build()` 那道门是不够的**：另外五处并发动作必须同时加判据，否则"未登录"时也会
  干活 —— `:408-411` / `:439-440`（埋点与种子导入）、`:549-555`（`_purgeLegacyOutboxOnce`，
  **它会删数据**）、`:562-609`（`_refreshHome`，**它会写库**）、`:637-639`（会排系统通知）、
  `:497-498`（把上次未结束的训练读进内存）。
* **闸门形态是一个常量**：`AuthGate.mode = 'required' | 'optional'`（见 §二-1、§二-3），
  "必须先登录"与"首练之后才拦/不拦"之间是一次改动，不是一次重构。
* **会话存哪**：**存本机 drift 库**（新表 `auth_session`：令牌、邮箱、登录时间、设备名），
  **不引入 `flutter_secure_storage`** —— 那是一个新的原生依赖（Keychain/Keystore 两套原生代码），
  而本机数据本来就是设备沙箱内的明文库（今天的恢复码就是明文存在 `backup_account.recovery_code`）；
  理由写进 `docs/tech-decisions.md`。
  ⚠️ 注销/删除时这张表**必须**一起清（见 §5.3 的 `delete_all_test` 两条）。
* **界面**：`vi/auth-setup.html` 已有一版登录/注册视觉（**手机号+验证码**），按邮箱+口令改一遍，
  落到 Flutter（登录 / 注册 / 验证码 / 找回 / 注销确认，五屏）。
* **老用户**：本机已有随机 account key 的安装 —— 走「**给这个账号绑一个邮箱**」，
  **不重建密钥**（数据、恢复码、云备份都不断）；这是唯一不作废历史的路径。
* **找回**：入口是"用恢复码登录" → 登录后可选"设一个新口令"（重新包一次 account key）。
  也就是说：**恢复码是口令的上一级**，这也是 §二里"忘口令怎么办"的答案。
* **密钥从哪来**：`app/lib/backup/` 里**要吃改动的只有四个入口**
  （`accountIdFromRecoveryCode` / `deriveBackupKey` / `encryptBackup` / `decryptBackup` —— 它们把
  "恢复码字符串"当密钥来源）；`accountIdFromKey`、`deriveBackupKeyFromKey`、AAD、信封格式、
  整个 `backup_transport.dart`、**以及整个服务端的备份接口**都**不用动**。
  `cryptography ^2.9.0` 已含 `Pbkdf2` 与 `Argon2id` → **不新增依赖**。


## 七、分期与验收（每期都要能独立站住）

| 期 | 内容 | 验收 |
|---|---|---|
| **A** ✅ **已完成（2026-10-06）** | 服务端身份层：`server/` 下新增 `mailer.mjs`（零依赖 SMTP）+ `auth-store.mjs`（邮箱/凭据/令牌/验证码/限流）+ `auth.mjs`（七个接口）+ `backend.mjs` 接线（**新接口写在"账号必须存在"那道闸门之前**，凭据"先当令牌、再当 account_id"）+ `server/auth.selftest.mjs`（38 项）+ `server/mailer.selftest.mjs`（19 项）+ `install.sh` 拷贝白名单 3 → 6 个文件 | ✅ `node server/auth.selftest.mjs` / `node server/mailer.selftest.mjs` / `node server/backend.selftest.mjs` 三条全绿；`check-guards-wired` / `check-deploy` 绿。**这条路上没有一行客户端代码**，所以"账号体系"与"必须先登录"可以在这一期之后分开推进 |
| **B** ✅ **已完成（2026-10-06）** | 客户端密码学：`app/lib/backup/account_login.dart`（口令 → KEK → 包裹/解开账号密钥；纯 Dart、**不 import flutter**）+ `app/test/account_login_test.dart`（15 项）。**KDF 参数按实测定**（见下面那段） | ✅ 真 Flutter 测试跑过 15/15（**在无撇号的跑道副本里**，见下）；`dart analyze --fatal-infos` 干净。**老用户路径也验了**：拿本机恢复码对应的密钥去"绑邮箱"，解出来还是同一把密钥、同一串恢复码、能直接解密既有云备份 |
| **C** | 客户端闸门与五屏界面 + 会话表 + 老用户绑邮箱 | widget 测试（跑道里能跑，不必等 CI）+ 模拟器走查（`docs/images/`）+ `delete_all_test.dart` 表清单与种子 + **离线仍可用**要有一条测试（服务端不可达时已登录用户能进） |
| **D** | 政策 / 事实表 / 收集清单 / 两张商店表单 / 公网政策页**同步**改写（清单见 §五） | §五 那张表逐条勾掉；`privacy-audit`、`check-store-forms`（判据要重写）、`gen-privacy-page --check`、中英结构对账全绿；顺手把 `check-doc-facts.mjs` 真检查接进 `verify.sh` |
| **E** | 部署包与守卫：`server/deploy/` 加 SMTP 配置（**不要把口令塞进 systemd 单元**，见下）、`check-deploy.mjs` 跟上、软著数字重算 | `./verify.sh` 全绿；`tool/copyright-pdf.mjs --check-docs` 绿（改了 `server/**` 的 `.mjs` 会影响源程序量） |

> ⚠️ **KDF 参数是量出来的，不是猜的**（2026-10-06，B 期）：
> 纯 Dart 的 `Argon2id(m=64MB, t=3, p=4)` 在这台开发机上 **5 次中位 174 ms**
> （152/163/174/175/220；JIT，手机 AOT 会慢一些但仍在可接受区间），
> OWASP 最低档 `m=19MB, t=2, p=1` 是 62 ms。
> 所以**按原计划取 m=64MB / t=3 / p=4**（`kDefaultLoginKdf`）——
> 参数越高，拿到库的一方离线爆破弱口令的代价越大；降低它不是优化，是降低攻击成本。
>
> ⚠️ **另一条更正（我先前说错了一句）**：Flutter 测试**不是"本机跑不了"** ——
> 仓库早就有无撇号的**跑道副本** `~/HARNESS/lianleme/sport` 与同步脚本
> `~/HARNESS/lianleme/sync-and-verify.sh`（`verify.sh` 文件头与 `tool/dev-env.sh` 都写了）。
> SSD 上那份是唯一真源，**跑 Flutter 层要走跑道**。B 期的 15 项就是那么跑出来的。

> ⚠️ **E 期的一条坑（侦察到的，别踩）**：`install.sh` 的 `render()` 用 `sed` 把值写进
> `/etc/systemd/system/*.service` —— SMTP 口令走这条路就是**明文落盘 + 进 `--dry-run` 输出 +
> 进 shell 历史**，而且口令里带 `#`/`&`/`\` 会破坏替换。所以 SMTP 配置要另走一条
> （例如 root 0600 的 `EnvironmentFile=`），且在 `server/deploy/README.md` 里写清怎么放。


> ⚠️ **不许交半个账号体系**：每一期单独可提交、可回滚，且**提交时 `./verify.sh` 必须是绿的**。
> 尤其是"代码里有登录、政策里还写着没有账号系统"这种中间态 —— 政策改写与闸门开启
> 必须落在同一批里（守卫本来就会抓住它）。

## 八、风险与不可逆点

| 风险 | 说明 | 处置 |
|---|---|---|
| **首练完成率下降** | 注册墙在第一次训练之前（§二-1） | 用常量做出可回退的缝；上线后按首练漏斗看真实代价 |
| **Apple 5.1.1(v)：可能被判"必须允许不登录使用"** | 核心功能与社交网络无关（§二-3）；`docs/wechat-login-feasibility.md:93-94` 是这个说法的出处 | 提交前必须再看一眼：退路是 `AuthGate.mode = 'optional'`（一个常量 + 少一处启动守卫） |
| **离线承诺被改写** | 原话"完全离线"不再字面成立（`store-listing-ios.md:61`、`PRODUCT.md:73`） | §二-2 的口径写进政策与商店描述，**不留下过期承诺** |
| **口令弱 = 备份可被爆破** | §三残余风险 1 | Argon2id 参数 + 弱口令表 + 基准测试 |
| **邮箱是 PII** | 政策、收集清单、商店表单、注销时限 | §五逐处改；注销走 15 个工作日口径（`wechat-login-feasibility.md` 已记） |
| **审核 4.8** | 只要**不出现**第三方登录，就不触发"等价登录方式"要求 | 本期只做邮箱+口令 → 4.8 不适用；将来加微信时再一起处理 |
| **老用户** | 已安装的随机 key 账号 | 绑邮箱（不重建），并保留恢复码 |
| **服务端成本** | SMTP 复用现有邮箱、验证码量极小 | `feature-backlog.md` 已算过：¥0 |

## 九、这一页还没定的（施工中要回来补的）

* Argon2id 的具体参数（内存/迭代/并行度）—— **等 §七 B 期的基准测试**，不猜；
  服务端为此只保管客户端报上来的 `kdf` 字符串（`docs/privacy-facts.json` 里注明它不参与上报）；
* 验证码的最终参数（现在是 **6 位 / 10 分钟 / 60 秒一条 / 每邮箱每天 10 条 / 全局每天 200 条 /
  每条最多试 6 次**）—— 上线前按真实发信量再核一遍；
* SMTP 配置**走哪条通道**进 systemd（见 §七 E 期的坑：不能走 `render()` 的 sed）；
* 注销时**是否**同时清空云端备份（本期倾向：注销 = 全删，另有"只删账号保留备份"不做）；
* `docs/store-listing.md:19` 与 `privacy-facts.json:312`、`store-listing-ios.md:184` 之间那两处
  **疑似既有漂移**（"云备份配没配/可不可用"）—— D 期顺手定性并改掉。

### B 期留下的两件小事（下一轮补，不阻塞）

1. **线格式的"金向量"测试**：现在验的是"同输入同输出"（确定性），还没有把某个固定
   `(口令, 盐, nonce)` 的 `authVerifier` / `wrapped` 字节**钉死**。加一条的价值是：
   将来 `package:cryptography` 升级如果改了 Argon2id/HKDF 的细节，老用户的 `wrapped`
   会**当场解不开** —— 金向量能在测试里先红，而不是在用户手机上才发现。B 期没加是因为
   每次加测试都会动"门禁条数"这个事实源（`docs/release-checklist.md` 唯一那一格），
   想跟 C 期那批一起改，一次跑完门禁。
2. **门禁条数这条账**：本轮从 **1233 → 1248**（+15 = 这一批的客户端用例）。
   C 期继续加用例时要一起改（`verify.sh` 第 5 层会拿实测数比它）。

## 十、A 期落地了什么（2026-10-06，供下一轮直接接）

| 文件 | 作用 |
|---|---|
| `server/mailer.mjs` | 零依赖 SMTP（隐式 TLS 465；明文必须显式允许，只给自检）+ `LIANLEME_MAIL_OUT` 文件模式 |
| `server/auth-store.mjs` | `auth_accounts` / `auth_tokens` / `auth_codes` / `auth_events` 四张表；一个 `account_id` 只能绑一个邮箱 |
| `server/auth.mjs` | 七个接口 + 反枚举（假盐 / 同一句话 / 假 scrypt）+ 限流（**不按 IP**）+ scrypt 存凭据 + sha256 存令牌 |
| `server/backend.mjs` | 认证接口接在闸门**之前**；凭据"先令牌、后 account_id"（老客户端不被弄坏）；注销连邮箱绑定一起删 |
| `server/auth.selftest.mjs` · `server/mailer.selftest.mjs` | 38 项 + 19 项，已接进 `verify.sh` |
| `server/deploy/install.sh` | 拷贝白名单 3 → **6** 个 `.mjs`（漏一个的症状是"启用账号后第一次请求 500"） |

**这一期刻意没碰客户端**：服务端先把"邮箱 → account_id → 密文"这条链立住并验完，
客户端（B/C 期）才有东西可对。**旧接口一个字节没改语义**，所以正式包不受影响。

### B 期落地了什么（同日）

| 文件 | 作用 |
|---|---|
| `app/lib/backup/account_login.dart` | 口令 → KEK（Argon2id）→ 认证凭据 / 包裹密钥；`wrapAccountKey` / `unwrapAccountKey`（信封 AAD 绑 account_id，解开后再核一次 `SHA-256(密钥) == account_id`，防服务端把别人的包裹塞过来）；`prepareAccount` / `unlockAccountKey` 两个一站式入口；`PasswordPolicy`（本地弱口令与长度门槛）。**纯 Dart、不 import flutter** |
| `app/test/account_login_test.dart` | 15 项：确定性、盐/口令/KDF 参数变一处的后果、改一个 bit、A 的包裹挪给 B、信封里无明文、恢复码仍有效、解出的密钥能直接解密既有云备份、KDF 编解码回落、口令策略 |

**没有改的地方**（这是 B 期最重要的一条）：`accountIdFromKey` / `deriveBackupKeyFromKey` /
`encryptBackupWithKey` / `decryptBackupWithKey` / 整个 `backup_transport.dart` / 服务端备份接口
**一行都没动**。唯一改的是 `backup_crypto.dart` 文件头那句"不需要被包裹的密钥这一层"——
加了口令之后它不再成立，已在原处加注并指向 `account_login.dart`。


