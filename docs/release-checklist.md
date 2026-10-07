# 练了么 · 上架前置清单

> 本清单只记录**上架**特有的门槛。日常开发与验收看 `verify.sh` 与 `ROADMAP.md`。
> 每一条都是可执行的，不是"建议关注"。带 ⛔ 的是**硬门槛，不满足就上不了架**。

---

## 0. 先分清：上架 ≠ 打包上传

`flutter build appbundle` 能跑通，**只说明"能产出文件"**，离能上架还差下面这些。
本项目自己的 `ROADMAP.md` 也把唯一硬依赖链标为 `阶段3 → 阶段2 → 插上手机` ——
**一个从没在真实设备上跑过的 App 不该上架**，这是清单第一项的原因。

---

## 1. ⛔ 真机验证（安装已完成，交互验收待做）

- [x] ✅ 手机开启「USB 安装」权限（小米/HyperOS 必须单独开，否则 `INSTALL_FAILED_USER_RESTRICTED`）
- [x] ✅ **App 已装进真机**：**历史**上第一次装上真机时是 `com.sdknwdtvpv.lianleme` v1.0.0 / versionCode 1（那是当时，早已过时）；**现在装的是 v1.56.0 / versionCode 71**（2026-10-06 `adb install -r` 覆盖安装，数据保留）—— 见下面「终局核验」，
      设备 Redmi `flourite`（Android 16 / API 36）—— 阶段 2 的关键一步达成
- [ ] 在真机上**实际用一遍**，完成 `ROADMAP.md` 阶段 2 的 5 条完成标准，其中两条最关键：
  - [ ] **练两个动作**（卧推 → 返回 → 深蹲），两组都在
  - [ ] **杀掉 App 重开**，组一条不少；进同一动作能看到「上次 xx kg × n」
- [ ] 完成 `ROADMAP.md` 阶段 3：带手机去健身房**真的练一次**

## 2. ⛔ 发布签名

**✅ 2026-10-05：正式密钥已生成**（你本人在终端里跑的 `app/android/tool/gen-upload-keystore.sh`，
密码只在你手里）。现状：

| 项 | 值 |
|---|---|
| 签名者 DN | **`CN=李松, C=CN`**（不再是 `CN=Android Debug`） |
| 别名 | `upload` |
| keystore | `app/android/upload-keystore.p12`（PKCS12 / RSA 2048 / 10000 天，权限 600） |
| 签名 MD5 | `2227a0109f73e388ce4986033b39fd85` |
| SHA-1 / SHA-256 | `400f130031a68ef99995a68fba9f25d320955a0c` / `d27a03f3f07276bd0bb4ca3bbcdca6d159e754a717cbe98975987f70e9bdc1c3` |

⚠️ **`dist/` 里的包已经是"可上架的签名"**（此前是 debug 签名，商店必拒收）——
`node tool/check-dist.mjs` 每次仍会核版本，但**签名口径从 2026-10-05 起变了**：
想复核，跑 `apksigner verify --print-certs dist/练了么-v1.43.0.apk`，应当看到 `CN=李松`。
⚠️ 这三个指纹是**公开信息**（它们在包里、备案页上都会出现），**密码不是** —— 密码只在你的密码管理器里。

**接线验证（2026-09-29 用临时密钥走通三种情况；本节其余内容仍然有效）**：

| 情况 | 实测行为 |
|---|---|
| 有 `key.properties` | release 包由**正式密钥**签名（当时是临时密钥 `CN=LianLeMe Verify…`，现在是上面的真密钥） |
| 没有 `key.properties`、没有逃生开关 | **硬失败**，退出码 1，并打印"商店一定会拒收"的说明 |
| 没有 `key.properties`、显式 `ORG_GRADLE_PROJECT_allowDebugSigning=true` | 落到 debug 签名（`CN=Android Debug`），供性能测试这类场合 |

**2026-09-30 又补验了两件事**（同样用一次性密钥，验完即删）：

1. **生成脚本本身跑得通** —— 之前只验了 gradle 接线，从没执行过
   `tool/gen-upload-keystore.sh`。上架那一刻才发现脚本坏了是最糟的，所以提前干跑：
   密钥生成、`key.properties` 写入（权限 600）、`keytool -list` 回显填写的主体，全对。
2. **真密钥那一档的证书确实换成了我们的** —— 用一次性密钥构建 release APK，
   `apksigner verify --print-certs` 显示 `CN=DryRun Test, O=DryRun Org, C=CN`，
   而不是 `C=US, O=Android, CN=Android Debug`。

也就是说：**只差你生成并保管好那把真密钥**，接线与脚本都不会再出问题。
（干跑用的 `upload-keystore.p12` / `key.properties` 已从 `app/android/` 删除，
当前工作区里没有它们 —— 你跑生成脚本时不会撞上"已存在"的拦截。）

- [ ] 生成正式签名（**这一步必须你来做**，密码不要经过任何工具/日志）：
      ```bash
      cd app/android && ./tool/gen-upload-keystore.sh
      ```
      或复制 `key.properties.example` 为 `key.properties` 手动填写。
- [ ] **把 keystore 和密码备份到密码管理器与离线介质** —— 丢了就无法再更新已发布的应用
- [x] ✅ 确认 `key.properties` / `*.p12` / `*.jks` / `*.keystore` 都被忽略（**本来就已经忽略了 `.p12`**）：
      ```bash
      git check-ignore -v app/android/key.properties   # 应命中 app/android/.gitignore
      ```
- [ ] 构建并**验证签名者不再是 Android Debug**（接线已验证，这一步是在你的真密钥上复验）：
      ```bash
      cd app && flutter build appbundle --release
      "$JAVA_HOME/bin/keytool" -printcert -jarfile \
        build/app/outputs/bundle/release/app-release.aab | grep 所有者
      ```
      > 注意：`apksigner` / `keytool` 都**需要 Java 环境** —— 先 `source ~/HARNESS/lianleme/flutter-env.sh`，
      > 否则它们会静默失败（`exit 1` 且没有任何输出，看起来像"签名有问题"，其实是没找到 JRE）。
- [ ] 决定是否启用 **Play App Signing**（Google Play 强烈建议；上传密钥与签名密钥分离，
      上传密钥丢了还能找回）

> 本项目已把「没有签名就产出 release」改成**硬失败**：缺失 `key.properties` 时
> `flutter build appbundle --release` 会直接报错退出，而不是静默给你一个 debug 签名的包。
> 确实需要 debug 签名（如性能测试）时用
> `ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build ...`。

## 3. ⛔ 隐私合规

- [x] ✅ **隐私政策与代码的对账做成了可执行的**：`node tool/privacy-audit.mjs`
      （代码会发的事件/字段、manifest 权限 ↔ `docs/privacy-facts.json` ↔ 政策正文），已进 verify.sh。
      发布前还要再跑一次 **`--apk <包>`** —— 插件的权限只有打包后合并才会露出来
- [ ] 审核并定稿 `docs/privacy-policy.md`（**当前是草案，未经法务审核**）
- [x] ✅ 占位符已填：运营者 `Elliot.LI`（个人开发者）、联系方式为 GitHub issue 地址
- [ ] 把「生效日期」改成实际的首次发布日（当前写的是"首次上架日（未发布）"——
      这句在没上架之前是准确的，上架前必须替换成实际日期）
- [x] ✅ 英文版已成文：`docs/privacy-policy.en.md`（Google Play 用；**中英不一致以中文为准**）
- [ ] ⚠️ 隐私政策需要一个**公网可访问的 URL**（商店强制要求）。可选做法：给本仓库开
      GitHub Pages，或把 `docs/privacy-policy.md` 贴到任意静态托管上
- [x] ✅ **补上"删除全部数据"的应用内入口** —— 已完成：
      「我」→「数据」→「删除全部数据」，二次确认后硬删除训练/组记录/个人设置，
      **并一并清空还没上报的埋点事件**。动作库保留。
      代码：`profile_screen.dart` 的 `_deleteAll` + `local_store.dart` 的 `deleteAllUserData`
      （内存实现与 drift 实现同跑 2 条契约断言）。
- [ ] **在真机上点一次确认删除真的生效**（`flutter test` 只证明逻辑，销毁路径要在设备上过一遍）
- [ ] **在真机上验证分享卡**：走一遍总结页 →「分享训练卡」→「分享」（系统面板能起来）
      与「存相册」（相册里能找到图）。这两条依赖平台通道，**测试覆盖不到，只能真机跑**。
      另需确认 Android 10+ 的「应用权限」页里**看不到**存储权限（`maxSdkVersion=29` 生效）
> **行政前置（软著 / App 备案 / 隐私政策 URL / 商店材料）单独整理成
> [`docs/release-admin.md`](release-admin.md)** —— 那是"技术上能出包了、为什么还不能上架"
> 的答案，含来源与核实日期。**按周计的东西先起那一条。**

- [ ] 准备**个人信息收集清单**（国内商店要求）：可直接取 `docs/privacy-policy.md` 第 2 节
- [ ] 健康数据属**敏感个人信息**，需单独同意 —— 当前用「帮助改进产品」开关承载，
      需确认这个交互是否满足"单独同意"的形式要求（**建议咨询法务**）

## 4. ⛔ 权限

- [ ] release manifest 里只应有 `INTERNET` 一项（已配好，验证：）
      ```bash
      grep uses-permission \
        app/build/app/intermediates/merged_manifest/release/*/AndroidManifest.xml
      ```
- [ ] 若某版本决定不做任何上报，删掉 `AndroidManifest.xml` 里的 INTERNET 以收紧权限

## 4.5 ⛔ 云备份开关：一旦配上，政策**必须**同步改写

云备份是**两个**编译期开关，**缺一个就不算配**（只给地址 → 入口根本不出现、一个字节都不发，
免得出现"界面有入口、政策却说本版本未提供"的自相矛盾）：

```bash
flutter build apk --release \
  --dart-define=LIANLEME_BACKUP_URL=https://你的域名 \
  --dart-define=LIANLEME_BACKUP_DISCLOSED=true
```

- [ ] 把 `docs/privacy-facts.json` 的 `cloudBackup.enabledInDistributedBuild` 翻成 `true`
- [ ] 按下面这份**实测**清单补政策正文 —— 2026-09-30 把开关临时翻成 true 跑硬门禁，
      它报出来的就是这四句（中英各两处）：

      | 缺的那句 | 在哪份文件 |
      |---|---|
      | 「服务端只拿到密文」 | `docs/privacy-policy.md` |
      | 「删除全部数据时，会问你是否一并删除云端备份」 | `docs/privacy-policy.md` |
      | `end-to-end encrypted` | `docs/privacy-policy.en.md` |
      | `recovery code` | `docs/privacy-policy.en.md` |

- [ ] 在设备上确认这道开关真的挡得住（**不需要后端**，只看到入口为止）：
      ```bash
      # ① 只给地址 —— 期望：入口不出现（失败往关闭倒）
      cd app && flutter test integration_test/cloud_entry_gate_test.dart -d <设备> \
          --dart-define=LIANLEME_BACKUP_URL=http://127.0.0.1:8790
      # ② 两个都给 —— 期望：入口出现
      cd app && flutter test integration_test/cloud_entry_gate_test.dart -d <设备> \
          --dart-define=LIANLEME_BACKUP_URL=http://127.0.0.1:8790 \
          --dart-define=LIANLEME_BACKUP_DISCLOSED=true
      ```
      两次都跑才是证据：同一份代码、两种构建、相反的结果。
      **2026-09-30 已在 iOS 上按同样两次跑过**（iPhone 17 Pro Max 模拟器）：`entry=hidden` 与
      `entry=shown`，与安卓一致 —— 也就是说"入口跟编译期开关走"这件事两端都验过。
- [ ] 跑完云备份端到端之后，核**服务端手里只有密文**：
      `node tool/check-ciphertext.mjs <服务端的 sqlite>`（空库会判红 —— 「没有数据」不等于「没有明文」）
- [ ] `node tool/privacy-audit.mjs` 必须绿（它会逐条核对上面四句）
- [ ] 商店表单也要从"变体 A：Data Not Collected"改成"变体 B" ——
      见 `docs/store-listing.md` 与 `docs/store-listing-ios.md`

> 只想先看差多少、不想真发版：把 `enabledInDistributedBuild` 临时改成 `true`、
> 跑一次 `node tool/privacy-audit.mjs`（它会列出缺哪句）、再改回 `false`。

## 5. ⛔ 发布门禁（项目自定，且当前过不了）

`README.md` 与 `docs/analytics.md` 规定：

> `set_logged.tap_count` 中位数或 P90 **比上一版上升**，该版本不允许发布，
> 必须回退导致上升的改动。

> ⚠️ **口径已改为端到端**（2026-09-29）：周期从"用户决定练这个动作"开始，
> 导航、选动作、切换动作全部计入（见 `docs/analytics.md` §3）。
> 因此**旧目标值全部作废** —— 中位数 = 1 在端到端口径下物理上不成立（光导航就 2–3 次）。
> 这也是门禁判据从"中位数 > 1"改成"比上一版上升"的原因。

- [ ] 按 `docs/usability-test-kit.md` **§A 熟人短测**（3–5 个熟人 × 5 分钟，半天）拿 `tap_count` 分布，
      回填 `docs/analytics.md` §3 并去掉"待校准" —— **完成即可定门槛**（不再是上架前置）
- [ ] （**建议做、不卡上架**）按同一份 kit 的正式流程招 5 人测试，拿回 §8 的 7 个数字，
      用实测值校准 `docs/analytics.md` §1.1 的 55%（短测只标定 `tap_count` 那三行）
- [ ] 确认端到端中位数**不高于**上一版（首次发版则先定基线）
- [ ] 修掉"大按钮重量错误"之后再取一次分布 —— 那是当前每组多 4 次点击的根因

**在这个数字到手之前，按项目自己的规则就不能发布。**

## 6. 版本号（每次切版照做）

> 这一节原来是一份 **v1.2.0 那次的回顾**（带勾选框），混在"当前该怎么做"里 —— 下一个人
> 切版时会以为那些框是给自己的。2026-09-30 拆成两半：**上面是流程，下面才是历史**。

**流程（照这几条走）**：

- [ ] 遵守 `CHANGELOG.md` 开头的策略：**版本号只跟随 `app/` 下的代码改动**
      （只改文档/工具不切版；改了 `app/` 才切）
- [ ] `app/pubspec.yaml` 的 `version:` bump（`+N` build number 一起加一）
- [ ] `app/lib/core/app_info.dart` 的 `kAppVersion` —— **必须与 pubspec 前缀一致**
- [ ] `CHANGELOG.md` 加一节，与 commit / tag 一同落地
- [ ] `app/android/app/build.gradle.kts` 的 `versionCode/versionName` 取自 Flutter，
      **不用手改**；但**每个商店上传的 versionCode 必须递增**
- [ ] 装到真机（`dist/` 出包 → `adb install -r`），并把三处"真机装的是哪一版"改对：
      `README.md` / `ROADMAP.md` / 本文件的状态速览 —— **`verify.sh` 会拿它们与
      `app_info.dart` 对账**，改漏一处就红

**被门禁钉住的地方（所以忘了会被抓住，不用靠记性）**：

| 会漂的东西 | 谁在守 |
|---|---|
| `pubspec.version` ↔ `kAppVersion` | `app/test/app_version_test.dart`（读 pubspec 核对，第 5 层跑） |
| README 顶部 `**vX.Y.Z**` | `verify.sh` **第 2 层** |
| `docs/your-todo.md` 顶部时间戳 | 同上（第 2 层，一条命令级的守卫） |
| 三处"真机装的是哪一版" | 同上（第 2 层，三处逐个点名） |
| CHANGELOG 小节降序 + 不许粘行 | 同上（第 2 层） |
| 软著材料里的版本 / 模式版本 / 源程序**文件数·行数·全文页数** | `tool/copyright-pdf.mjs --check-docs`（第 2 层里跑；页数真源 = 行数 ÷ 每页 50 行，**不是** `dist/` 里那份 60 页鉴别材料）。这个工具自己有 5 条自检（第 2 层） |
| 门禁测试条数（本文件状态速览那一行） | `verify.sh` **第 5 层**（拿实测条数跟它比，对不上就红） |

**历史（v1.2.0 那次，留作教训）**：`app/pubspec.yaml` bump 到 `1.2.0+3`、没有升 major
（`lastSessionFor` 只多了一个可选参数、`TapKind` 是加值，按 fix/feature 升 minor）。
**那次的教训是界面上那个版本号**：`kAppVersion` 以前写死在 `profile_screen.dart` 里，
`v1.1.0` / `v1.2.0` 两次切版都没带上 —— 界面上错了两个版本，谁都没发现。
现在它由上面那张表里的第一行守着。

## 6.5 用 adb 验真机时的一个坑（2026-09-29 记）

屏幕熄灭时 Android 会把进程**冻住**：Dart 的定时器不触发、平台通道不回包，
于是任何"启动后应该发生的事"都看不到，很容易误判成代码没跑。

```bash
adb shell dumpsys deviceidle whitelist +com.sdknwdtvpv.lianleme
adb shell dumpsys deviceidle disable
# …验证完恢复：
adb shell dumpsys deviceidle enable
adb shell dumpsys deviceidle whitelist -com.sdknwdtvpv.lianleme
```

另外目标机（Redmi `flourite`）的 `input` 注入被 MIUI 禁掉
（`SecurityException: Injecting input events requires … INJECT_EVENTS`），
所以**点击类验收只能人拿手机做** —— 能自动化的只有：安装、冷启动、
把应用私有库拉下来查数据（需要 debug 包，release 包 `run-as` 会被拒）。

## 7. 商店材料（国内商店额外）

- [ ] **软件著作权登记**（软著）—— 国内主流商店必需，办理有周期，**尽早启动**
- [ ] **App 备案**（工信部）—— 部分商店已强制要求
- [x] 应用图标（2026-09-30 做完：之前一直是 **Flutter 默认图标** —— 既是商标问题也不能上架）
      `python3 tool/gen-icons.py` 生成，`tool/asset-check.mjs` 在 verify.sh 第 2 层守着
- [ ] 截图（3–8 张，必须来自真实 App）—— 已能**一条命令生成**，见 [`screenshots.md`](screenshots.md)；
      **真机装不上时可用 Android 模拟器替代**（同步文档里写了怎么起、以及它的性能坑）；
      当前已出 4 张（首页/建议卡/计划/选动作），其余等真机安装放行后重跑
- [ ] 应用描述、分类、内容分级
- [ ] Google Play：开发者账号（一次性 25 美元）、隐私政策 URL、数据安全表单
- [ ] 健康类应用在国内可能需额外资质 —— **需按目标商店的具体要求确认**

## 8. 已知功能缺口（不挡上架，但要心里有数）

| 缺口 | 说明 |
|---|---|
| ~~分享卡图片未实现~~（已完成） | 零依赖生成 + `share_plus`/`gal` 投递；测试里 `RepaintBoundary.toImage()` 必须包在 `tester.runAsync()` 里 |
| ~~体重记录未实现~~（已完成） | `body_metric` 表 + S12 录入界面 + S8 体重卡片 |
| ~~单位切换未实现~~（已完成） | `core/units.dart` 统一换算；存储/引擎/埋点仍是 kg |
| ~~默认休息时长不可配~~（已完成） | S10 加了偏好；默认「跟随动作」，用户选具体值才全局覆盖 |
| ~~S6 动作切换、S9 全部数据未做~~（已完成） | S6 修掉了死的底部条并加了左右滑动；S9 是新的二级页 |
| S3/S4/S5 未打磨 | 手感问题要等真机使用才知道 |
| **账号体系：切版时做了哪些、还剩哪些** | ✅ 已做：**CHANGELOG**（v1.56.0 那一节）、**出包**（v1.56.0，三个 define 齐全）、**装真机**（Redmi `75caf509`，冷启动干净）、**真机拍到了账号页**（`docs/images/v156-account-page-redmi.png`）。✅ 也已做：**服务端升级 + SMTP 填好**（`docs/backend-hosting.md` §四之三 有完整证据：`/healthz` 多出 `binds`/`tokens`、`/v1/auth/code` 真的发出一封验证码、限流与登录失败都实测过）；**三套商店截图已重出**（2026-10-06：三套 16/15/15 张、各 0 步失败，`check-screenshots` 绿。⚠️ 这次**带上了那三个 `--dart-define` 重出** —— 正式包是变体 B，不带 define 的图里连「云备份 / 账号」两行都没有，等于拿一个用户装不到的形态当素材，见 `docs/screenshots.md`）。⏳ 还剩：**账号流程的真机走查**（注册 → 登录 → 改口令 → 注销）—— 服务端已经能用，Redmi 上装的就是带账号入口的 v1.56.0，走一遍即可（验证码会发到 `919500973@qq.com`） —— 「我 → 数据与备份」多了一行「账号」，现在那三套里没有它（`tool/check-screenshots.mjs` 只核齐不齐/尺寸/夹带，**核不出内容过期**，所以它不会替我们拦）|
| 账号埋点还没加 | 见 `docs/plan-account-login.md` §十末：值得加（"有多少人愿意注册"），但一次要动事件数/政策/商店表单，留给下一次切版 |
| 云备份那条通道仍在用 `account_id` 当凭据 | 服务端两种都认（令牌与 `account_id`）。收紧成"只用令牌"的收益是注销后老凭据立刻失效；代价是动 `backup_transport` 的每一处调用与测试 |
| `tool/check-doc-facts.mjs` 的真检查没接进门禁 | **既有欠账**（只有 `--selftest` 在跑）：文档里的"22 类事件 / 7 个公共字段 / schemaVersion"这些数字目前**没人每次核**。补一条 `node tool/check-doc-facts.mjs` 到 `verify.sh` 即可（`check-guards-wired` 一直以为它已经在跑） |

## 9. 构建与验收命令汇总

```bash
source ~/HARNESS/lianleme/flutter-env.sh        # flutter/java/adb 上 PATH
cd "/Volumes/Elliot's SSD/HARNESS/lianleme/sport"

./verify.sh                                      # 全量自检（六层全过才算过；含变异测试 0 存活）

cd app
# ⚠️ 三处编译期常量，少一处就不是"正式包"：
#    * 前两个是云备份（缺一个入口根本不出现，一个字节都不发）；
#    * 第三个是匿名统计 —— **地址要带 `/v1/events` 路径**，因为
#      `HttpAnalyticsTransport` 是拿这个 URI 原样 `postUrl()` 的（不像云备份会自己拼路径）。
flutter build apk --release \
  --dart-define=LIANLEME_BACKUP_URL=https://api.elliotli.work \
  --dart-define=LIANLEME_BACKUP_DISCLOSED=true \
  --dart-define=LIANLEME_ANALYTICS_URL=https://api.elliotli.work/v1/events   # 旁加载用（APK）
# 同一组 define 再跑一遍 appbundle，商店用（AAB）

# ⚠️ 上面 appbundle 那条命令**会报一句假的失败**（"failed to strip debug symbols"，卷名空格坑），
#    .aab 其实已经产出。核产物必须跑这个，别看退出码：
cd .. && node tool/check-aab.mjs

# ⚠️ **再核一遍包里到底有没有那三处常量**（这一条没有任何守卫，2026-10-06 就是因为漏了它，
#   先出了一个"云备份入口根本不出现"的包 —— 而那时用户正好要靠云备份把数据取回来）：
for abi in arm64-v8a armeabi-v7a x86_64; do
  echo -n "$abi: "; unzip -p dist/练了么-v1.54.0.apk "lib/$abi/libapp.so" | strings -a \
    | grep -c "api.elliotli.work"
done          # 每个 ABI 都应该是 2（备份地址 + 统计地址/v1/events）

# 签名：2026-10-05 起走**真 keystore**（`app/android/key.properties` +
#   `app/android/upload-keystore.p12`，两个都不入库，口令在密码管理器 + 离线介质里）。
#   没有它 Gradle 会硬失败；逃生开关 ORG_GRADLE_PROJECT_allowDebugSigning=true 只用于
#   "临时装自己手机"，出的是 **debug 签名**包，商店必拒收。

# 验收 release 产物
"$JAVA_HOME/bin/keytool" -printcert -jarfile \
  build/app/outputs/bundle/release/app-release.aab | grep 所有者   # 应当看到 CN=李松
"$ANDROID_SDK_ROOT/build-tools/36.0.0/aapt2" dump badging \
  build/app/outputs/apk/release/app-release.apk | grep -E "^package|sdkVersion"
```

---

> 🧾 **"到底还差什么、哪些必须你来做"统一看 [`your-todo.md`](your-todo.md)** ——
> 这份清单以前散在 7 份文档里，谁也说不清全貌。

## 当前状态速览

**2026-09-30 重新核对过一遍**（上一版停在 v1.2.0，好几行早就过期了 —— 过期状态比没有状态更坏，
因为它会让人以为某件事已经做过了）。

| 项 | 状态 |
|---|---|
| 构建链 | ✅ **2026-10-06 在 v1.57.0 上重编重核**：release **APK 64.7 MB**（64,665,739 字节）、**AAB 62.6 MB**（62,638,979 字节）（`bundle/release/app-release.aab`；旧行写的 59.8M/55.9M 是 v1.22–1.30 那会儿的）。AAB 用 `node tool/check-aab.mjs` 核过：骨架三件套 + **三 ABI**（arm64-v8a / armeabi-v7a / x86_64，各含 libsqlite3/libflutter/libapp）+ 版本号与 `app_info.dart` 一致。⚠️ `flutter build appbundle` 会**假报失败**（卷名空格坑，见 `docs/dev-environment.md`），产物没问题 |
| 签名接线 | ✅ 接线与硬失败**已验证**（缺 `key.properties` 时构建直接失败、逃生开关有效） |
| 正式签名 | ✅ **真 keystore 已生成并接上**（2026-10-05）。DN `CN=李松, C=CN`、alias `upload`，三个指纹与备案要填的值见 `docs/release-admin.md` §二（⚠️ 安卓备案填 **MD5**、苹果填 **SHA-1**，别填反）。已用真 key 重签并当场核过：`apksigner verify --print-certs dist/练了么-v1.52.0.apk` → `CN=李松`（不再是 `Android Debug`，商店可收）。`dist/*.apk` 从此不再是"能装不能交"的那一类 |
| 权限 | ✅ 源码 manifest **三项**（INTERNET + `WRITE_EXTERNAL_STORAGE` 限 API ≤29 + `POST_NOTIFICATIONS` —— 最后这条是 v1.42 的训练提醒带来的，API 33+ 走**运行时**请求、只在用户主动打开开关时问）。打包后多一条**隐含**的 `READ_EXTERNAL_STORAGE`（≤29，系统因 WRITE 授予，不是谁声明的）—— **已在政策与 `privacy-facts.json` 里逐条披露**（`privacy-audit --apk` 每次对账）。⚠️ 这三条这个数字以前一直写着「两项/2 条」—— 加 `POST_NOTIFICATIONS` 那次**没同步改这里**，而 `privacy-audit` 只核「有没有披露」、不核「文档里数的是几条」，所以红不了。2026-10-05 对产物数出来才改 |
| 隐私政策 | 🚧 中英文已成文、占位符已填；**待法务审核 + 公网 URL + 填生效日**。⚠️ 云备份一旦上线，§3.1/§3.2 必须重写（数据**会**离机） |
| 删除数据入口 | ✅ 已实现并测试。v1.22.0 补上了**条件式的云端删除**：有云备份账号时，弹层多问一句「同时删除云端备份并注销」（默认勾选），先删云端、失败则整个中止。**v1.30.0 起另有逐表核对 + 表清单守门**（`app/test/delete_all_test.dart`）：删除后除动作库外**每张表都必须是 0 行**（负向验证：把 `body_metric` 的删除拆掉 → 立刻红，报 `body_metric=1`）；库里新增/改名一张表而没更新那份清单 → 也红。这条正是删除权的失败方式：**新表忘了接，界面上看不出任何异常** |
| 真机验证 | ✅ **iPhone 17 Pro 上跑的是 **v1.57.0**（`versionCode 72`，`tool/ios-device-run.sh` 装包，`devicectl` 读到 `1.57.0 / 72`）—— **当时 Redmi 75caf509 上是 v1.56.0**（`versionCode 71`，2026-10-06 `adb install -r dist/练了么-v1.56.0.apk` → Success、冷启动 `E/flutter` 0 条 / `overflowed` 0 条；**账号入口在真机上出现过**，证据图 `docs/images/v156-account-page-redmi.png`。⚠️ 账号**流程**没在真机上走完 —— 线上服务端还没升级（见下面那条），所以注册会如实回"这台服务器还没有账号功能"）。**iPhone 17 Pro 上也是 v1.56.0**（2026-10-06 深夜装包，`devicectl` 读到 `com.sdknwdtvpv.lianleme.dev 1.56.0 / 71`；⚠️ 免费签名 7 天后失效。历史：当时是 v1.54.0（当时 `versionCode 69`，2026-10-06 `tool/ios-device-run.sh` 装包）—— ⚠️ v1.55.0 还没装上 iPhone 过，装完要把这一句改掉，正在验收液态玻璃）**。**当时 Redmi 上装的是 v1.56.0（`versionCode 71`）** —— 2026-10-06 `adb -s 75caf509 install -r dist/练了么-v1.56.0.apk` → `Success`、冷启动 `E/flutter` 0 条 / `overflowed` 0 条：2026-10-06 重出商店截图时脚本取设备取错了（`adb devices` 的第一台就是真机），把它上面的 App **卸载了**，重装先被 MIUI 挡（`INSTALL_FAILED_USER_RESTRICTED`）；打开开发者选项里的「USB 安装」后已 `adb -s 75caf509 install -r dist/练了么-v1.54.0.apk` 装回、冷启动正常（`E/flutter` 0 条）。⚠️ 那次是**全新安装**，本机数据为空 —— 要用**恢复码从云端取回**（那条路 2026-10-05 走通过）。，**历史**上跑的是（2026-10-05）v1.53.0—— 同签名所以系统接受、数据保留；`dumpsys package` 读到 `versionName=1.52.0 / versionCode=67`，冷启动 `E/flutter` 0 条。✅ **v1.52 的界面与敏感信息同意门已在真机上走完**（详情与证据图见下面「真机 75caf509」那行）；没做的只剩「手感」那一条（只能人做）。**之前**那一版是 v1.47.0（`versionCode 66`），它**卸载重装**过一次：真 keystore 与旧包的 debug 签名不同，`install -r` 被系统直接拒（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`）；冷启动无异常，`E/flutter` 0 条 / `overflowed` 0 条）。**2026-10-05 在真机上验了这一批**：① **当时的图标**（深底 + 白「练」+ volt 哑铃 —— 那是 v1.44.0 那版；**v1.45 起换成橙色圆环**）在启动器里就是它、名字「练了么」（`docs/images/launcher-icon-verified-redmi-v1440.png`）；② **卸载清空 → 用恢复码从云端取回**（这条路径此前只在模拟器上做过）：云备份页「已绑定这个恢复码」→「从云端恢复（合并，不覆盖本机）」→ **「已从云端恢复：已导入 2 次训练 / 2 组，置顶 0 个动作」**，「我」页训练统计回到 **2 次 / 2 组**（`docs/images/v144-cloud-restore-banner.png` · `docs/images/v144-cloud-restore-stats.png`）。**2026-10-04 在真机上验了这两批**：① 选择器**置顶**（钉一个 → 顶部「置顶」区 + 星标变实心 + 不再重复出现）；② **训练提醒**：打开开关 → 系统通知权限授予（`USER_SET`）→ `dumpsys alarm` 里出现 `RTC_WAKEUP …/.ReminderReceiver`（改时间时旧的那条被记为 `alarm_cancelled`）→ 到点后系统里真的出现了那条通知（`NotificationRecord … id=4702 channel=lianleme_training_reminder`，`vis=PUBLIC`）。⚠️ 两次实测记下来：第一次晚 **2 分 26 秒**；第二次在**深度休眠**里被系统压住，直到**唤醒手机那一刻**才补发（非精确闹钟 + Doze 的真实行为）。⚠️ **锁屏上那张图没拍到**：这台 MIUI 不渲染第三方通知（系统设置都允许，见 `docs/plan-scene-and-return.md` 的验证表）。⚠️ 这一趟还**改了一处代码**：通知默认是 `VISIBILITY_PRIVATE`，安全锁屏下**整条不显示**（真机上"锁屏只有系统那条"就是这么来的）—— 提醒的价值就是"不打开 App 也看得见"，所以显式声明 `VISIBILITY_PUBLIC` 并重新出包重装。证据图 `docs/images/v142-01-reminder-permission.png` |
| **体检数据的单独同意** | ✅ v1.31.0：体重属**敏感个人信息**（医疗健康类），按 PIPL 第 29 条**单独**征求同意 —— 第一次进「身体数据」页时单独弹一次说明（只存本机/不上传/可改可删），点了才记录，点「先不用」就不进那一页；同意时刻单独落库（当时是 schema **v14**，那一列就是那一版加的）。中英政策与 `privacy-facts.json` 的 `sensitiveLocal` 同步，硬门禁**两处横查**（政策说法 ↔ 代码里那道门）|
| 匿名统计的默认值 | ✅ **默认关闭**（v1.28.0，审计 A 的后半段）。只有用户主动到「我 → 帮助改进产品」打开才会有数据发出去；off 时连队列里没发出去的也停发；硬门禁三处对账（`privacy-facts.json` ↔ 代码默认值 ↔ 中英政策正文）。**并在设备上验过两跑**：默认（关）跑完整轮训练，应用真实库里 `pending=0`；同一流程预置成开则 `pending=11` —— 证明测量本身没坏（`integration_test/analytics_outbox_e2e_test.dart`）。**iOS 上同样两跑一致**（2026-09-30，模拟器 iOS 27.0）。⚠️ 这条与下面「积压事件」那条一起，决定"配了上报地址的包"能不能发 |
| 个人信息收集清单（164 号文） | ✅ 应用内二级菜单「我 → 关于 → 个人信息收集清单」（v1.29.0）。两份清单都是**生成物**：收集清单 ← `privacy-facts.json`，共享清单 ← 政策里的第三方 SDK 表；与应用内隐私政策共用一套生成与防漂守卫（`gen-privacy-page.mjs --check`） |
| 屏幕方向 | ✅ **锁竖屏**（v1.30.0）。实测横屏下首页 `RenderFlex overflowed by 80px`，入口文字与底部导航重叠 —— 我们没有横屏设计，所以两端都锁（安卓 `screenOrientation="portrait"`、iOS 手机方向数组只留 Portrait），各有一条守卫钉着 |
| 显示配置 | ✅ 六种配置实测过（常规竖屏 / 横屏 / iPad 宽度 / 浅色模式 / 大字号 1.3× / 小屏 720×1280），矩阵与复现命令在 `docs/screenshots.md`。⚠️ 它能证明"不会坏"，**不能**替代用手指走一遍 |
| **iOS 侧** | 🟡 代码侧就绪，且**已能构建**（⚠️ 在 Xcode 里会看到 **1 条警告** —— `share_plus` 插件里 `keyWindow` 的弃用提示，有 `@available` 守卫、我们的部署目标 iOS 15 走不到那行，**不用管**：见 `docs/tech-decisions.md`「已知警告」）：**2026-09-30 已构建**（许可证接受之后的第一次）：`flutter build ios --simulator --no-codesign` → 183M 的 Runner.app；`flutter build ios --release --no-codesign` → **19M / arm64 / 最低 iOS 15.0**。产物逐项核对过：显示名「练了么」、bundle id `com.sdknwdtvpv.lianleme`、版本 `1.31.0 / 40` —— 那是首编那一次的产物）、**只有 `NSPhotoLibraryAddUsageDescription`**（没有读相册那条）、`ITSAppUsesNonExemptEncryption=false`、`UIUserInterfaceStyle=Dark`、方向数组**只有竖屏**；`Frameworks/` 里有 `sqlite3.framework` 与 `objective_c.framework`（正是守卫盯着的两个原生资源包），且**没有 Pods** —— SPM 路线由真实构建确认。 ✅ **当时（2026-10-01）在 v1.36.0 上重编重核**：`flutter build ios --release --no-codesign` → **20.9MB / arm64**，`node tool/check-ios-app.mjs` 逐项一致（身份「练了么」· `com.sdknwdtvpv.lianleme`、版本 **1.36.0 (49)**、只有仅新增相册权限、Dark、竖屏锁、应用内资产三件、`sqlite3.framework` + `objective_c.framework`、启动屏已编译进包、`Assets.car` + 2 个 AppIcon、**设备族 `[1]` = 只支持 iPhone** —— 2026-09-30 拍板，产物里含 iPad 现在会判红）。**新增第 10 条核对：应用级隐私清单**（`PrivacyInfo.xcprivacy`）必须在包里、`NSPrivacyTracking=false`、至少声明一类 required-reason API —— 2026-10-01 补的文件 + 守卫（两条负向用例）。**第 9 条核对：出口合规的"决定"必须留痕** —— 包里确实有标准算法的加密代码（AES-256-GCM + HKDF-SHA256，云备份用），所以 `docs/store-listing-ios.md` 里必须写明算法、两种口径与"谁来决定"（见该文件「出口合规」一节，负向测试：把算法名从文档里拿掉 → 真产物核对当场红）。 ✅ **2026-09-30 又进一步**：模拟器运行时（iOS 27.0，约 8G）装好后，App **第一次在 iOS 上真的跑起来** —— 同一份 `integration_test/screenshots_test.dart` 在 iPhone 17 Pro Max 上出图 **12 张 / 0 步失败 / 1320×2868**，逐屏用眼睛看过；因为 iOS 模拟器给的是 **16 位 RGBA**、而 App Store 只收 **8 位无 alpha**，新增 `tool/flatten-png.mjs` 压平（三套截图现在都由 `tool/check-screenshots.mjs` 核，含这两条硬规矩）。⚠️ 还差**签名与上传**（要 Apple Developer 账号）。⚠️ 另有一条**未定性**的观察：在那台模拟器上第一次跑这套脚本时（运行时刚装完、App 首次启动），首页刷新报过一次 drift 后台 isolate 的错（0 张图）；此后**连跑 5 次全新安装，5 次全绿 13/13** —— 像一次性环境问题，但**没定位到根因**，也没在真机上验过（那要 Apple 账号）。商店表单字段见 `docs/store-listing-ios.md`。 ✅ **2026-10-04：iOS 真机也跑通了**（**免费 Apple ID / Personal Team**，不需要付费账号）：`tool/ios-device-run.sh` 一条命令完成"读 Team → 换 dev bundle id → 编签 → 装 → 拉起 → 工程改回"，在 iPhone 17 Pro（iOS 27.2）上验到 **Live Activity 在锁屏正常显示**（证据 `docs/images/v142-live-activity-lockscreen.png`）与 widget 扩展一起签进包；坑与实测结论记在 `docs/ios-free-provisioning-guide.md` 第六节。⚠️ **仍未变的**：免费档签出来的包**只能装自己那台、7 天失效、不能 TestFlight / Ad Hoc 分发** —— "签名与上传"那一关仍然要付费账号。 |
| **CI（GitHub Actions）** | ✅ **CI 跑的就是门禁本身**（2026-09-30）：`.github/workflows/ci.yml` 只有一条 `./verify.sh`，在 `ubuntu-24.04` / node 22 / flutter 3.47.5 上跑。三次实测：`7f0ed36` → 235 秒、`997070a` → 249 秒、**`6be4a66`（v1.34.0）→ 262 秒**，都是 `success`。**关键是它绿得可证**：多了一步「门禁账目」——日志里 `[1/6]`…`[6/6]` 必须都在、**不许出现「⊘ 阻塞」**、且写着"未发现失败"，否则判红（`verify.sh` 在开发机上把"环境阻塞"当不失败，CI 上必须反过来）。失败时那几行会被抬成 `::error::` **注解**（job 日志要凭据才读得到，注解公开可读）|
| **P0-5 商店材料三边对账（2026-10-06，用真实 APK）** | ✅ **一致**。跑了 8 条守卫：`privacy-audit --apk dist/练了么-v1.56.0.apk` → 22 事件 / 7 公共字段 / manifest 声明 3 条、**打包后合并 6 条**全部已披露；`check-store-forms` → **字段决定：映射 3 / 免披露 43 / 未决定 0**，并且**邮箱那一行**按新判据核过（与身份关联 = 是），两张表都与事实源一致（"不收集"没被抄进 Play 变体、敏感字段都披露、默认关与不追踪都写了依据）；`check-screenshots` / `check-dist` / `check-aab` / `check-user-text` / `check-changelog` 全绿。⚠️ **两处只有真环境能核，不在这条里**：① `tool/check-ciphertext.mjs <服务端 sqlite 路径>` 要**在服务器上**跑（证明库里确实只有密文）；② 商店表单的**实际提交**（控制台里填一遍）。 |
| 全新克隆 | ✅ **`git clone` 之后直接 `./verify.sh` 就能跑完六层**（2026-09-30 首次实测：一份干净克隆里跑出 168 个 ✓、`未发现失败`；**2026-09-30 晚在 `2f66d40` 上又跑了一遍**：753 项测试全绿、**`未发现失败`、零阻塞**、新增的那几个守卫（CI/商店表单/交付目录/部署包/截图）自检也都在克隆里跑过 —— `dist/` 不在时的跳过路径同样验到了）。此前不是这样：第 2 层会假报「有直接依赖不支持 iOS」、第 4 层判阻塞、第 5 层自己 pub get 后因缺 `db.g.dart` 失败 —— 三层对「还没引导过」的反应互相矛盾。现在 `verify.sh` 开头有第 0 步引导（按需 pub get + 生成 drift 代码）|
| 测试 | ✅ 门禁 **1278 项全绿**、变异 24 杀 / 0 存活 = 100%。⚠️ 上面这个数字是**唯一的事实源**：`verify.sh` 第 5 层会拿实测条数跟它对比，对不上就判红（README 里那些"553 条测试"之类的抄写就是这么烂掉的）。⚠️ 这一条**只有干净克隆 / CI 才真能核**（SSD 上的撇号路径挡着第 5 层）—— 2026-10-05 因此红过两次 |
| 上报地址的"积压事件"决策 | ✅ **已定并已落地**（B 2026-10-04 + D 2026-10-05）：**B** 第一次在配了地址的包里冷启动时清掉接入前攒的那批（"谁记的谁发"）；**D** 任何事件超过 **30 天**就不再上报（入队顺手清 + 出队发送前清）。分界与理由见 `docs/analytics.md` §10，规格 `docs/analytics-sdk.md` §5，测试 `app/test/analytics_outbox_age_test.dart`。**不再阻断发布** |
| `tap_count` 门禁 | 🟡 目标值由**熟人短测**标定（`docs/usability-test-kit.md` §A，半天，**不再阻塞上架**）；未标定前只按"不得高于上一版"判（`verify.sh` 里那条相对门禁） |

### 待处理（2026-09-30 核对时发现，**第 1 条已在本版收掉**）

1. ~~**`READ_EXTERNAL_STORAGE` 不在政策里**~~ —— **已披露**（v1.21.0）。
   而且当初那个"两条路，需要你拍板"的说法**是错的**，如实记下来：
   我以为可以在 manifest 里用 `tools:node="remove"` 把它删掉，实际上
   **它根本不是一条 `<uses-permission>`** —— 它是"声明了 `WRITE_EXTERNAL_STORAGE`"之后
   Android 在 API ≤29 上**由系统隐含授予**的（`aapt2 dump badging` 里那行
   `uses-implied-permission ... reason='requested WRITE_EXTERNAL_STORAGE'`）。
   宿主要么不给 WRITE（那就等于放弃"存分享卡到相册"这条功能），要么接受这条隐含的读权限。
   所以真正可选的只有"如实写进政策"这一条，已经写了：中文 §四、英文 §4 各加一段，
   并进 `docs/privacy-facts.json` 的 `impliedPermissions`。

   **顺带修掉两个"检查在空转"的坑**（比这条权限本身更值得记）：
   * `privacy-audit.mjs --apk` 去 `~/Library/Android/sdk` 找 aapt2 —— 依赖搬去 SSD 之后
     那个路径已经不存在，于是它打印一行"找不到 aapt2，跳过"就**照常退出 0**。
     而政策附录 B 恰恰教用户用这条命令核"打包后的合并权限"。
     现在：按 `ANDROID_SDK_ROOT` 找，且**既然你明确要了 `--apk`，找不到就报错**（不是跳过）。
   * 它原来用 `aapt2 dump permissions`，**这个子命令不报 implied 权限** ——
     上面那条 READ 就是这么漏掉的。改用 `dump badging` 并把 implied 一起收进来。
2. `app/pubspec.yaml` 里那句注释写的是 `maxSdkVersion="28"`，实际是 `29`（已改）。

> ⚠️ **门禁查不到 release 构建**：`verify.sh` 一行 Gradle 都不跑，
> 所以工具链坏掉时它照样全绿。2026-09-30 就真发生过：`~/.config/flutter/settings` 里
> `jdk-dir` 还指着已删除的内置盘 JDK，release 构建直接失败而门禁全绿。
> 现在门禁里有这条检查（前置探测那段），`tool/dev-env.sh` 也会顺手把配置对齐到 SSD。

---

## 终局核验（2026-09-30 首核；**2026-10-05 在 v1.44.0 上逐项重核**）

出门之前把"产物 / 真机 / 对外数字"对齐了一遍。**每一项都是当场跑出来的**，不是抄上面的表。
⚠️ 这张表里的版本号/数字**逐版重核后就地改**（旧值不要留），所以它与上面那张表**允许重复、不允许打架**：

| 项 | 实测结果 |
|---|---|
| **当前状态（2026-10-06，v1.57.0）** | ✅ **已出包、已装到 iPhone**（Redmi 这次没连着，仍是 v1.56.0）。`pubspec.yaml` = `1.57.0+72`、`kAppVersion` = `1.57.0`；`dist/` 里是 `练了么-v1.57.0.apk`（64,665,739 字节）+ `练了么-v1.57.0.aab`；判据跑过 `tool/check-dist.mjs` / `check-aab.mjs`。⚠️ **iPhone 上还是 v1.54.0**（iOS 侧没重装）。下面各行里凡是**明确标了「上一版 / 当时」的**都是历史实测值，没标的按新的重写过 |
| `dist/` 内容 | ✅ `练了么-v1.57.0.apk` + `练了么-v1.57.0.aab` + `copyright/`（**V1.57.0**：源程序 283 文件 / 77,464 行 / 1550 页、说明书 6 页）+ `README.md`—— 没有上一版的残留（`node tool/check-dist.mjs` 当场核过：包内 `1.57.0 (72)` 与真源一致） |
| APK（旁加载包） | `versionCode 72 · versionName 1.57.0`，与 `app_info.dart` / `pubspec.yaml` 一致（`adb shell dumpsys package` 当场读到的就是这个）；签名者 **`CN=李松`**（真 keystore，`apksigner verify --print-certs` 当场核过）；manifest 合并后 **3 条声明**（INTERNET、WRITE_EXTERNAL_STORAGE ≤29、POST_NOTIFICATIONS）+ 1 条注入（DYNAMIC_RECEIVER）+ 1 条隐含（READ ≤29，系统因 WRITE 授予） |
| `privacy-audit.mjs --apk`（发布前必跑） | ✅ 对得上：18 事件 / 7 公共字段 / 2 声明权限 / **打包后合并 5 条**全部已披露 |
| AAB（Google Play 通道） | ✅ `tool/check-aab.mjs "dist/练了么-v1.56.0.aab"`（**2026-10-06 在 v1.56.0 上核**）：121 条目 · 59.7 MB（62,638,979 字节）· **三 ABI** 原生库齐全（arm64-v8a / armeabi-v7a / x86_64）· 版本 **1.56.0** 与 `app_info.dart` 一致。⚠️ `flutter build appbundle` 仍会**假报** "failed to strip debug symbols"（卷名空格）并**退出码非 0**，产物没问题 —— 所以判据必须是"核产物"（`check-aab` / `check-dist`），不是看退出码。AAB 现在也放进 `dist/`，由 `tool/check-dist.mjs` 每次核版本（旧版本残留、文件名没版本号都判红）|
| 真机 `75caf509` | **历史**：装的是 **1.53.0（versionCode 68）**（2026-10-05 用 `adb install -r` 覆盖安装 v1.52.0 release，同签名所以**数据保留**、系统没拒绝；`dumpsys package` 当场读到 `versionName=1.52.0 / versionCode=67`，冷启动无异常，`E/flutter` 0 条。✅ **并且在真机上把 v1.52 那一段走完了**（2026-10-05，`adb shell input` 这次可用）：① 打开「身体数据」→ 录体重 72.5 / 腰围 82 / 肌肉量 34.5 / 身高 176 → 保存 → **摘要卡出现且 BMI 23.4「正常」**（`docs/images/v1520-redmi-02-body-bmi.png`）；② 切到 10/4 再录 73.5 → 保存 → **趋势卡出现（10-04 → 10-05，−1.0 kg）**（`docs/images/v1520-redmi-03-body-trend.png`）；③ 点「撤回我的同意」→ 确认 → 弹层写的是 v1.52 的新文案（`docs/images/v1520-redmi-04-body-revoke.png`）；④ 再进这一页 → **单独同意那道门重新出现**，文案逐项点了「体重、体脂率、腰围、肌肉量和身高」且没有 markdown 星号（`docs/images/v1520-redmi-05-body-consent-gate.png`）；⑤ 点「同意并记录」→ **两条历史记录原样还在**（`docs/images/v1520-redmi-06-body-history-kept.png`）—— 这一步正是 PIPL 第 15 条要的：撤回的是同意、不是数据。⚠️ 仍然**没验**的是手感那一条（单手够不够得着、出汗时按大按钮），那只能人做）。更早那次（v1.47.0）是覆盖安装；上一次 1.44.0 是**卸载后重装** —— 真 keystore 与旧包 debug 签名不同，`install -r` 被拒；本机数据用恢复码从云端取回，2 次训练 / 2 组回来了）（⚠️ **跑过 `flutter drive` 之后必须重装一次**：截图脚本结束时会卸载 App，也会把 `wm size` 留在截图分辨率上 —— 见 `docs/dev-environment.md`）；`force-stop` 后冷启动正常、`E/flutter` **0 条**；屏幕尺寸已复位（1280×2772） |
| 商店截图三套 | `store-assets/screenshots/` 16 张（1080×2400，国内/软著）· `screenshots-play/` 15 张（1080×1920，Play 要的 9:16）· `screenshots-ios/` 15 张（1320×2868，8 位 RGB 无 alpha）。**三套都在 2026-10-06（v1.54.0）重出了一遍**（起因：这一版把「全部数据」页的维度切换从右上角「更多」菜单改成明面上的分段控件 —— **安卓也变了**，所以三套都得重出；iOS 那套还多了底栏/分段/单位行的液态玻璃），**首图换成引导页轮播那一屏**（`00-intro`，用户拍板：商店列表第一张要回答"我能得到什么"）；⚠️ **2026-10-06 重出时那次事故**：脚本用 `adb devices` 取第一台设备，而第一台是用户真机（Redmi `75caf509`）—— 于是**把它上面的 App 卸载了**，重装又被 MIUI 的 USB 安装权限挡着。教训：**设备必须显式点名**，不许用 `adb devices` 的第一行；脚本里那次 `wm size` 也一并打在了真机上（尺寸已复位）—— ⚠️ 它只在**干净安装**那一跑拍得到，所以三套的重出都是"先卸载再跑"。此前那次是 v1.52 收尾（触发原因：v1.48–v1.52 的五个新屏没人重拍过，重跑时 15 步全红 —— 引导页轮播没被处理、身体数据页多了第二个 ListView；两条都已修，并把「转换 surface」挪到失败现场图之前；`11-body-metric` 现在记两天数据，图里有摘要卡 / BMI / 趋势卡。此前**三套是 2026-10-05 在 v1.46.0 上重出**（换新 VI 之后，上一批是 v1.42.2 拍的 —— 旧图还是 volt 绿那一版，与现在的界面不是同一个 App）：模拟器两套走 `flutter drive` + `wm size`（1080×2400 / 1080×1920），App Store 那套走 iOS 模拟器（`lianleme-69`）+ `flatten-png.mjs` 压平。⚠️ 这次重出**当场撞见一个真 bug**：三个 integration test 还在点 `Key('tab-我')`，Tab 改名成「我的」之后会静默失败到「找不到控件」—— 判据是 `LIANLEME-SHOT-SUMMARY` 那行写着「失败 0 步」。（换 VI 之前那次的历史：)⚠️ 触发这次重出的是**四张过期的图**（首页 / 选择器 / 计划 + 首页入口那行）—— v1.38.0 起界面改了三次而图没跟上。**这次重出跑了两轮**（第一轮白跑了）：拍完又把模板标题从 `Row` 改成 `Wrap`（第一版会把名字挤到折行），于是三套都得再拍一遍。⚠️ 中间还真丢过一次：安卓那轮的新图落在无撇号的「跑道」副本里、**没及时拷回主仓库**，随后一次 `rsync --delete` 把它覆盖回旧版（iOS 那套因为是从 `/tmp` 拷的反而留下了）—— **教训：跨仓库搬产物时，`rsync` 的方向要当场确认**。齐/尺寸/夹带由 `tool/check-screenshots.mjs` 每次核对（⚠️ 它只核**齐不齐、尺寸、夹带**，**核不出"内容过不过期"**） |
| 全新克隆 | ✅ `git clone` 后直接 `./verify.sh` → 六层全跑、`未发现失败`（首测 168 个 ✓；`2f66d40` 复测 753 项测试全绿、零阻塞）。见 CHANGELOG：为此加了第 0 步引导 |
| iOS 产物 | ✅ **2026-10-06 在 v1.54.0 上核过**（`tool/ios-device-run.sh` 装到 iPhone 17 Pro：**v1.54.0 (69)** BUILD SUCCEEDED → 装上设备 → 拉起成功 → 工程自动改回；`xcrun devicectl device info apps` 当场读到设备上的 `com.sdknwdtvpv.lianleme.dev **1.54.0 / 69**`，正在验收液态玻璃）。**历史**：2026-10-05 在 v1.53.0 上核过（**v1.53.0 (68)**；对那次构建出来的 `Runner.app` 跑了 `check-ios-app`，逐项一致，唯一那条红仍是免费的 `.dev` bundle id —— **脚本的既定行为，别改守卫**）。**此前在 v1.47.0 上也核过**（`tool/ios-device-run.sh` 装到 iPhone 17 Pro：**v1.47.0 (66)** 装上并拉起；对那次构建出来的 `Runner.app` 跑了 `check-ios-app`）。**当时（v1.46.0）也核过**（`tool/ios-device-run.sh` 装到 iPhone 17 Pro 之后，对**那次构建出来的 Runner.app** 跑 `node tool/check-ios-app.mjs`）：应用内资产三件齐、只有「仅新增」相册权限、主题 Dark、方向锁竖屏、`sqlite3` + `objective_c` 都在、启动屏已编译进包、`Assets.car` + 2 个 AppIcon、设备族 `[1]`、隐私清单 `NSPrivacyTracking=false` + 3 类 required-reason API、`RestWidget.appex` 带 Live Activity 声明 —— **逐项与仓库里的说法一致**。⚠️ 唯一那条红的是 `bundle id`：免费档真机包临时换成 `.dev`，那是**脚本的既定行为**（跑完已把工程改回 `com.sdknwdtvpv.lianleme`），不是缺陷。下表是**更早那一次**的完整记录：版本 **`1.44.0 (63)`**、显示名「练了么」、**只有「仅新增」相册权限（无读权限）**、主题 Dark、方向锁竖屏、应用内资产三件齐、`sqlite3.framework` 与 `objective_c.framework` 都在、**设备族 `[1]`（只承诺 iPhone，2026-09-30 那条「会承诺支持 iPad」的隐患已消除）**、应用级隐私清单（追踪 false + 3 类 required-reason）、**Live Activity 扩展 `RestWidget.appex` + `NSSupportsLiveActivities=true` 确实在包里**。⚠️ 唯一一条红是 `bundle id 是 com.sdknwdtvpv.lianleme.dev` —— 那是**免费 Apple ID 真机装包故意改的**（见 `docs/ios-free-provisioning-guide.md`），**不要为了让守卫变绿去改守卫**。⚠️ **这次顺带核出守卫自己的一个坑**：它的"自动找最新产物"原先只认 `build/ios/**`，而真机装包走的是另一个 derivedData 目录 `build/ios-dd`（`tool/ios-device-run.sh`）—— 于是它挑中了 8 小时前那份 **1.41.0 模拟器包**、报出两条假的"版本不符"，而真正最新的 1.42.3 真机包就在隔壁目录里没被看到。已把 `build/ios-dd` 加进候选（仍按修改时间取最新），现在它挑的是真产物，并且会**把磁盘上更旧的那两份点名报出来**（1.41.0 模拟器包 / 1.36.0 真机包）——"留着一份旧的"正是最容易拿去上传的那一份。工具自检（16 项产物 + 3 项出口合规，造动过手脚的 .app 要求它抓得住）在门禁第 2 层 |
| 软著材料 | `dist/copyright/` 里是 **V1.57.0**：源程序 **283 个源文件 / 77,464 行 / 全文 1550 页**、提交用前 30 + 后 30 页（正好 60 页）、说明书 6 页；著作权人已按 `--owner "李松"` 生成（与 **ICP 备案主体**、**keystore 的 `CN=李松`** 同一个名字）。⚠️ **提交前请确认这个名字与身份证一致** —— 不一致就重跑一次 `node tool/copyright-pdf.mjs --owner "你的姓名"`（改名只影响页脚，一分钟的事）。⚠️ **这三个数字由 `node tool/copyright-pdf.mjs --check-docs` 每次对账**（源文件/行数/页数任意一处漂了就红 —— 它已经抓过两次：加完守卫源码变多、改动后页数变多） |
| 界面文案 | ✅ **2026-10-04 全量审计**（判据与逐条清单见 `docs/copy.md`）：删/收 **20 处**"解释性语言"，分布 7 个文件；两类可机械判的漏字（`开发者`、`号文`）已进 `tool/check-user-text.mjs`（13 条自检）。⚠️ **半可执行**：另外三类（复述标题 / 科普 / 替人操心）**没有机械判据**，只能照判据人读 —— 这一点写在 `docs/copy.md` 第四节，不要当成"有守卫就万事大吉"。真机三张图：`docs/images/v144-prefs-copy-trimmed.png`（偏好设置）、`docs/images/v145-data-tools-no-subtitle.png`（数据与备份）、`docs/images/v144-privacy-copy.png`（隐私与关于）。⚠️ 这三张图的名字里写着 `v144-` / `v145-`，那是**当时打算切的版本号**，后来这批文案改动并进了 v1.42.5 / v1.43.0 的同版追加 —— **v1.44.0 真正对应的是「换图标」那一版**。文件名不改（改了就成孤儿图），但别拿它当版本指路 |

**这份核验能证明什么、不能证明什么**：能证明"我们这边该做的都做了、且对得上"；
**不能**证明"商店会收"—— 那还需要真 keystore（现在仍是 debug 签名）、备案、软著证书、
以及 iOS 那一次真实构建。这几件的入口都在 `docs/your-todo.md`。
