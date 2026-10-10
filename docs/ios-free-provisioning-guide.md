# 免费 Apple ID 真机测试 · 完整操作指南

> 2026-10-01 写。给"**没有付费开发者账号**、但想在**自己的真 iPhone** 上跑练了么"这条路
> 一份能照着做的指南。方案层面的取舍见 `docs/ios-device-testing.md`（本文是它的操作版）。
>
> **口径标记**：✅ = Apple 官方页面/官方报错原文；🟡 = 社区一致口径、官方没有明文数字。
> 凡是 🟡 的地方，第一次跑完我会把**实测结果**写回本文件（这个仓库的规矩：不自称确定）。

## 零、免费档到底给你什么（先知道边界，再动手）

| 项 | 免费 Personal Team | 来源 |
|---|---|---|
| 描述文件有效期 | **7 天**，到期 App 打不开，重新装一次即可 | 🟡（官方只写明付费档证书 1 年；7 天是社区一致口径） |
| 同时能装的免费签名 App | **3 个** | 🟡（Xcode 报错原文 `The maximum number of apps for free development profiles has been reached`） |
| App ID 配额 | **每 7 天最多 10 个** | ✅（Apple 报错原文 `You may create up to 10 App IDs every 7 days.`） |
| 设备 | 每产品族每年 100 台 | ✅（免费档是否另有"3 台/7 天"限制：未找到官方来源） |
| TestFlight / Ad Hoc / 上架 | **全部不可用**（需要 $99/年会员） | ✅ |
| 推送 / iCloud / App Groups / HealthKit / Associated Domains / Sign in with Apple / Apple Pay 等 entitlement | **用不了** | 🟡（官方"能力支持"清单按会员资格分档） |
| 能不能做我们要验的事 | **能**：真机跑起来、看手感/性能/后台/相册/分享面板 | —— |

> ⚠️ **两条最容易踩的**：① App ID **卸载也不释放**，7 天配额会被反复试错的 bundle id 耗光；
> ② 免费档用不了 **Associated Domains**（= 不能用 Universal Links）——
> 这意味着**微信登录**在免费档下没法完整联调（见 `docs/wechat-login-feasibility.md` §6）。

## 一、你需要的三样东西

1. 一台 **iPhone**（不需要越狱，系统 iOS 16 以上会因为"开发者模式"要走一步额外操作）；
2. 一根 **数据线**（或同一 Wi-Fi 下的无线调试，但第一次建议有线）；
3. 一个 **Apple ID**（免费的即可，**不需要**加入 Apple Developer Program）。

⚠️ **这条路上有三处"只有你能做"的图形操作**（都不能自动化，卡住时不会有报错，只会"没反应"）：

| # | 在哪里 | 做什么 | 不做的后果 |
|---|---|---|---|
| 1 | iPhone | 设置 → 隐私与安全性 → **开发者模式** → 打开 → 重启 → 输密码 | 装上去点开就闪退 |
| 2 | iPhone | 设置 → 通用 → VPN 与设备管理 → 开发者 App → **信任你的 Apple ID** | 拉起报 `profile has not been explicitly trusted by the user` |
| 3 | **Mac** | `codesign` 第一次签名时的**钥匙串授权**弹窗 → 输密码 → **始终允许** | 构建**静默卡住**（进程在、CPU 0%），像编译很慢 |

## 二、完整步骤

### 第 1 步：Xcode 里登录 Apple ID

```
Xcode → Settings（⌘,）→ Accounts → 左下角 + → Apple ID → 登录
```
登录后左边会出现 `你的名字 (Personal Team)` —— 这就是免费档的团队。

### 第 2 步：给工程选团队 + 改一个只有你能用的 bundle id

```
open app/ios/Runner.xcworkspace
```
> 练了么走的是 **SPM 路线**（没有 `Podfile`），workspace 里只有 `Runner.xcodeproj`，
> 所以打开哪个都行，但按文档用 `Runner.xcworkspace` 最稳。

在 Xcode 里：**选中 Runner target → Signing & Capabilities**
* ✅ 勾 **Automatically manage signing**；
* **Team** 选 `你的名字 (Personal Team)`；
* **Bundle Identifier** 改成**全局唯一**的一个，例如
  `com.<你的拼音>.lianleme.dev`。
  ✅ Apple 的 App ID 全平台唯一，撞了会直接报
  `An App ID with Identifier '…' is not available.`

> ⚠️ **这一步会让我们的守卫判红，而且是故意的**：`tool/check-ios-app.mjs` 要求
> 「产物里的 bundle id == `ios/Runner/Info.plist` == 安卓 `applicationId`」三处一致。
> 做真机测试时它会把这份产物标成"dev 包"——**测完请把 `Info.plist` 改回来**，
> 或者按 `docs/ios-device-testing.md` §六 那条"显式 dev 例外"处理。
> 千万别为了让守卫变绿去改 `check-ios-app`。

### 第 3 步：把 iPhone 连上并信任电脑

1. 插上线，iPhone 上会弹「**信任此电脑**」→ 信任 → 输锁屏密码；
2. Xcode 顶部设备选择器里应该能看到你的 iPhone（看不到就 `xcrun devicectl list devices`）。

### 第 4 步：打开**开发者模式**（iOS 16+ 必须）

```
iPhone → 设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启 → 解锁 → 输密码确认
```
✅ 官方说明开发者模式的目的是"防止用户无意安装有害软件"；
**关掉它，本地安装的 App 会启动不了**。重启后如果"开发者模式"菜单消失，说明还没装上任何开发版 App —— 先做第 5 步再回来开。

### 第 4.5 步：**第一次签名会弹钥匙串授权**（Mac 上，只有你能点）

`codesign` 第一次用那把新证书时，Mac 会弹一个**图形对话框**：

> "codesign" 想要使用钥匙串中「Apple Development: …」的密钥。

**输入 Mac 登录密码 → 点「始终允许」**。不点的话构建会**静默卡住**（进程还在、CPU 0%），
看起来像编译很慢 —— 2026-10-04 就这么卡了 31 分钟才发现。
选「始终允许」之后就不会再问了；系统锁屏/重启后的会话里可能再问一次。

> 这条路（`tool/ios-device-run.sh`）也走同一个授权：第一次跑时留意 Mac 屏幕。

### 第 5 步：装上去

```bash
# 方式 A：让 Flutter 编 + 签名 + 安装 + 启动（推荐第一次用）
cd app
flutter run --release -d <设备 id>      # 设备 id 用 `flutter devices` 看

# 方式 B：Xcode 里选中你的 iPhone，按 ⌘R

# 方式 C：已经编好了包，用 devicectl 装（Xcode 15+ 起取代 ios-deploy）
xcrun devicectl device install app --device <设备 UDID> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <设备 UDID> com.<你的拼音>.lianleme.dev
```

> ✅ `flutter build ios --no-codesign` 编出来的包**装不进未越狱真机**（它是给 CI/后续重签用的）。
> 真要装，必须走签名（上面 A/B/C 三种里的 A 或 B 会替你签名）。

### 第 6 步：信任开发者证书

App 装好后第一次点开，如果闪退或提示"未受信任的开发者"：

```
iPhone → 设置 → 通用 → VPN 与设备管理 → 开发者 App → 你的 Apple ID → 信任
```
✅ 路径在 iOS 26/27 上没有变化（社区文档与官方支持页一致）。

### 第 7 步：7 天后续签

描述文件 7 天到期 → App 打不开（点图标闪退/提示"App 不再可用"）。
**重跑第 5 步**即可；覆盖安装**通常不删沙盒数据**（🟡 官方没有明文保证，但我们自己的
数据都在 App 沙盒的 SQLite 里，重装同一个 bundle id 一般会保留）。
> 我这边可以把它做成一条命令（编 + 装 + 拉起 + 抓 30 秒日志），
> 等有 Apple ID 与真机时落地，并按仓库规矩"跑通了才写进文档"。

## 三、练了么特有的注意事项

| 事项 | 说明 |
|---|---|
| **相册权限** | 我们只申请「仅新增」(`NSPhotoLibraryAddUsageDescription`)。真机上要分别验"已授权"与"被拒"两条路（模拟器上逻辑验过，真机弹层文案要重看） |
| **分享面板** | 系统分享面板是系统 UI，自动化点不到 —— 只能你手动看一眼卡片长什么样 |
| **启动屏白闪** | 这是免费档也能验的一条：真机录屏逐帧看冷启动第一帧（模拟器证明不了毫秒级） |
| **云备份** | 需要配了地址的包（`--dart-define`），免费档同样能验；但**后台/Doze** 只有真机放兜里才准 |
| **性能** | `flutter run --profile -d <设备>` 比 debug 准；`--release` 最准（但没有热重载） |
| **数据** | 我们所有数据在本机 SQLite（`com.<你的拼音>.lianleme.dev` 的沙盒里）；换 bundle id 等于换一个 App，数据不互通 |

## 四、出问题时的对号入座

| 症状 | 原因 | 处理 |
|---|---|---|
| `No Provisioning Profile was found for your project's Bundle Identifier or your device` | 没选 Team，或 bundle id 不唯一 | 回到第 2 步 |
| `An App ID with Identifier '…' is not available` | bundle id 被别人占了（Flutter 模板默认 id 常撞） | 换一个更独特的 id |
| `The maximum number of apps for free development profiles has been reached` | 同一台设备上已有 3 个免费签名 App | 删掉不用的；或用付费账号 |
| `You may create up to 10 App IDs every 7 days` | 7 天内改 App ID 太多次 | 停手，等 7 天；**别再用试错法找 id** |
| App 装上了、点开就退出 | 没信任证书，或没开开发者模式 | 第 4 / 第 6 步 |
| 之前能用、今天突然打不开 | 7 天到了 | 重新跑第 5 步 |
| `error: No Accounts: Add a new account in Accounts settings.` | **Xcode 里没有登录任何 Apple ID**（免费档的 Team 就是从那儿读的）。⚠️ 本机账号列表为空时，`tool/ios-device-run.sh` 仍会往下走，直到 xcodebuild 报这一句 —— 表现是"脚本跑了两分钟才红" | 第 1 步：Xcode → Settings（⌘,）→ Accounts → 左下角 `+` → 登录 Apple ID |
| `error: Signing certificate is invalid … It may have been revoked or expired.` | 钥匙串里那几张 `Apple Development` 证书**已被吊销**（`security find-identity -v -p codesigning` 会显示 `CSSMERR_TP_CERT_REVOKED`）。免费档常见：换机/重装/别处点过 revoke 之后 | Xcode → Settings → Accounts → 选中你的团队 → **Manage Certificates…** → 左下角 `+` → **Apple Development**，新建一张；再跑第 5 步。（新建后 `security find-identity` 里那张新的应当没有 `REVOKED` 后缀） |
| 我要验"微信登录" | 免费档用不了 Associated Domains（Universal Links） | 见 `docs/wechat-login-feasibility.md` §6：这条要等付费账号 |

## 五、这份指南里哪些是"官方明确"，哪些是"社区口径"

* ✅ **官方明确**：App ID 每 7 天 10 个（报错原文）、TestFlight/Ad Hoc/上架需要付费会员、
  开发者模式必须在"设置 → 隐私与安全性"里开、证书信任路径、entitlement 按会员资格分档、
  bundle id 必须全局唯一。
* 🟡 **社区口径（官方无明文）**：7 天有效期、同时 3 个 App、免费档的 100 台设备上限、
  重装是否保留沙盒数据。
* 第一次真机跑通之后，我会把 🟡 那四条改成**实测结论**再回来更新本文件。

---

## 五点五、Xcode 27 上 Team 自动识别失效了（2026-10-06 踩到）

`tool/ios-device-run.sh` 原先从 `defaults export com.apple.dt.Xcode` 里读
`IDEProvisioningTeamByIdentifier` 拿 Team。**Xcode 27 不再写这个键了**，于是脚本报
「没找到可用的 Team」，而账号其实登录着（钥匙串里那张 `Apple Development: …` 证书就是证据）。

**现在的兜底**（脚本里已加，按顺序试）：
① 环境变量 `LIANLEME_TEAM_ID`；
② Xcode 下过的描述文件里的 `TeamIdentifier`（`~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision`，最准）；
③ 签名证书的 OU（`security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`）。
**三条都不把 Team 写进仓库**（它属于某个 Apple ID）—— 只是当场读出来用。

同一次还修了脚本的两个小坑：**没 source 环境时会一路跑到 `xcodebuild` 才报
`flutter: command not found`**（那时工程已经被临时改过）→ 现在开头就检查 `flutter`/`xcodebuild`；
另外记一笔：`LIANLEME_DEVICE` 那个 UDID **要照抄 `devicectl` 的输出**，
我手工转写时多打了一个字母，`xcodebuild` 报的是 "Unable to find a device matching …"（看起来像设备没连）。

## 六、2026-10-04 实测记（iPhone 17 Pro · iOS 27.2 · Xcode 27.0）

这一节只写**真跑过、看到过**的东西 —— 上面那些 🟡 里还没验到的，继续留在 🟡。

| 结论 | 证据 |
|---|---|
| ✅ **免费档能签 widget 扩展**（`.appex`） | `xcodebuild` 两个 target 一起 `BUILD SUCCEEDED`；`devicectl device install` 成功；设备上那款 App 的 `PlugIns` 目录里 `RestWidget.appex` 在、它自己的进程也在（`devicectl device info processes`） |
| ✅ **命令行也能把设备注册到 Apple 那边** | 第一次只传 `-allowProvisioningUpdates`（Flutter 默认只传这个）报 `Your team has no devices from which to generate a provisioning profile`；加上 **`-allowProvisioningDeviceRegistration`** 之后自动注册设备、建 App ID、建描述文件，一次过 |
| ✅ **装完必须信任证书，且这一步只能人工** | 未信任时拉起报 `invalid code signature, inadequate entitlements or its profile has not been explicitly trusted`；在 `设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任` 之后正常启动 |
| ✅ **Live Activity 在真机锁屏上正常显示** | `docs/images/legacy-5tab/v142-live-activity-lockscreen.png`（记一组后锁屏：`组间休息 1:32 · 杠铃卧推 · 下一组 40 kg × 8 · 第 2/3 组`，倒计时自己在走） |
| ⏳ 7 天到期行为 | **还没到期**（2026-10-04 装的），继续 🟡 |
| ⏳ 同时 3 个免费签名 App / 设备台数上限 | 没验，继续 🟡 |
| ⏳ 覆盖安装是否保留沙盒数据 | 没验，继续 🟡 |

**同一趟踩到的第三个坑（只影响"跑道副本"，但会让人以为工程坏了）**：
`app/ios/Flutter/Generated.xcconfig` 里缓存着 `FLUTTER_ROOT`，而它**会跟着 rsync 被覆盖**成
主仓库里的旧值（这台机器上旧值指向早就搬走的 `~/development/flutter`）。
症状是构建中途报 `<旧路径>/xcode_backend.sh: No such file or directory`。
脚本现在先跑一句 `flutter build ios --config-only --release` 重写它 —— 一行代价，省一次误判。

**一条命令的落地**：`tool/ios-device-run.sh`（2026-10-04 跑通）—— 自动从 Xcode 读出 Team、
临时换 dev bundle id、`xcodebuild` 编签装拉起、**跑完把工程改回去**（`trap`）。
它的注释里记着上面那个 `-allowProvisioningDeviceRegistration` 的坑，别删。

⚠️ **一个仍未验的点**：widget 扩展是否**真的被系统当扩展加载**这件事，我们是靠
"设备上确实起了 `RestWidget` 进程 + 锁屏上确实出现了 Live Activity"推出来的 ——
两条都指向"它是活的"，但没有更底层的证据（比如 ActivityKit 的日志）。
