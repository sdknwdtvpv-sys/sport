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
- [x] ✅ **App 已装进真机**：**历史**上第一次装上真机时是 `com.sdknwdtvpv.lianleme` v1.0.0 / versionCode 1（那是当时，早已过时）；**现在装的是 v1.33.0 / versionCode 44** —— 见下面"终局核验"，
      设备 Redmi `flourite`（Android 16 / API 36）—— 阶段 2 的关键一步达成
- [ ] 在真机上**实际用一遍**，完成 `ROADMAP.md` 阶段 2 的 5 条完成标准，其中两条最关键：
  - [ ] **练两个动作**（卧推 → 返回 → 深蹲），两组都在
  - [ ] **杀掉 App 重开**，组一条不少；进同一动作能看到「上次 xx kg × n」
- [ ] 完成 `ROADMAP.md` 阶段 3：带手机去健身房**真的练一次**

## 2. ⛔ 发布签名

**接线已验证（2026-09-29，用临时密钥在真机上走通了三种情况；临时密钥已删）**：

| 情况 | 实测行为 |
|---|---|
| 有 `key.properties` | release 包由**正式密钥**签名：`CN=LianLeMe Verify…`（临时密钥的 DN） |
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

- [ ] 通过 `docs/usability-test-kit.md` 招 5 人测试，拿回 §8 的 7 个数字
- [ ] 用**端到端口径**的真实分布回填 `docs/analytics.md` 的目标值
      （现在 55% 与 `tap_count` 的目标都还是**估计值**，标着"待校准"）
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
| 软著材料里的版本 / 模式版本 / 源程序量 | `tool/copyright-pdf.mjs --check-docs`（第 2 层里跑） |
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

## 9. 构建与验收命令汇总

```bash
source ~/HARNESS/lianleme/flutter-env.sh        # flutter/java/adb 上 PATH
cd "/Volumes/Elliot's SSD/HARNESS/lianleme/sport"

./verify.sh                                      # 全量自检（六层全过才算过；含变异测试 0 存活）

cd app
# ⚠️ 现在没有真 keystore，正式产物必须先加这个逃生开关（否则 Gradle 硬失败）。
#    它出的是 **debug 签名**的包，能装自己手机，**商店必拒收**。
ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build appbundle --release   # 商店用（AAB）
ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build apk --release         # 旁加载用（APK）

# ⚠️ 上面 AAB 那条命令**会报一句假的失败**（"failed to strip debug symbols"），
#    .aab 其实已经产出。核产物要跑这个：
cd .. && node tool/check-aab.mjs

# 验收 release 产物
"$JAVA_HOME/bin/keytool" -printcert -jarfile \
  build/app/outputs/bundle/release/app-release.aab | grep 所有者   # 不应是 Android Debug
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
| 构建链 | ✅ 两种产物都核过（**2026-10-01 在 v1.35.2 上重编重核**）：release **APK 62.3M**、**AAB 57.8M**（`bundle/release/app-release.aab`；旧行写的 59.8M/55.9M 是 v1.22–1.30 那会儿的）。AAB 用 `node tool/check-aab.mjs` 核过：骨架三件套 + **三 ABI**（arm64-v8a / armeabi-v7a / x86_64，各含 libsqlite3/libflutter/libapp）+ 版本号与 `app_info.dart` 一致。⚠️ `flutter build appbundle` 会**假报失败**（卷名空格坑，见 `docs/dev-environment.md`），产物没问题 |
| 签名接线 | ✅ 接线与硬失败**已验证**（缺 `key.properties` 时构建直接失败、逃生开关有效） |
| 正式签名 | ❌ **还没有真 keystore**。所以 `dist/*.apk` 是**debug 签名的旁加载包** —— 能装自己手机，**商店必拒收**。生成：`app/android/tool/gen-upload-keystore.sh`（在你那边） |
| 权限 | ✅ 源码 manifest **两项**（INTERNET + `WRITE_EXTERNAL_STORAGE` 限 API ≤29）。打包后多一条**隐含**的 `READ_EXTERNAL_STORAGE`（≤29，系统因 WRITE 授予，不是谁声明的）—— **已在政策里如实披露** |
| 隐私政策 | 🚧 中英文已成文、占位符已填；**待法务审核 + 公网 URL + 填生效日**。⚠️ 云备份一旦上线，§3.1/§3.2 必须重写（数据**会**离机） |
| 删除数据入口 | ✅ 已实现并测试。v1.22.0 补上了**条件式的云端删除**：有云备份账号时，弹层多问一句「同时删除云端备份并注销」（默认勾选），先删云端、失败则整个中止。**v1.30.0 起另有逐表核对 + 表清单守门**（`app/test/delete_all_test.dart`）：删除后除动作库外**每张表都必须是 0 行**（负向验证：把 `body_metric` 的删除拆掉 → 立刻红，报 `body_metric=1`）；库里新增/改名一张表而没更新那份清单 → 也红。这条正是删除权的失败方式：**新表忘了接，界面上看不出任何异常** |
| 真机验证 | ✅ Redmi `flourite`（Android 16 / API 36）上跑的是 **v1.35.2**（`versionCode 48`，逐版覆盖安装；冷启动无异常）。**2026-09-30 手机解锁后跑了一遍"手势走查"**（`adb shell input` 注入 —— 与手指走的是同一条输入链路）：冷启动 → 训练屏（建议 **40 kg × 8**，第 1 组/共 3 组）→ **一次点击记一组**（头变「第 2 组」、组列表出现 `40 kg × 8 ✓`、休息计时 **01:27** 起跳）→ 总结页（容量 **320 kg** / 不到 1 分钟 / 1 组 + 拉伸建议）→ 进步页（本周容量 320 kg、PR 墙「杠铃卧推 40 kg」）→ 我页（统计 1 次/1 组/320 kg；**「帮助改进产品」默认关**；**云备份入口不出现** —— 与"没配地址就没有入口"一致）→ **杀进程重开**：首页显示「我上周练了 1 次」（数据还在）。全程 `E/flutter` **0 条**、`overflowed` **0 条**；证据图 `docs/images/walkthrough-0*.png`。⚠️ **这仍然不等于"用手指走一遍"**：注入走的是输入层，**手感、误触、单手可达性、出汗时的触控**它测不到（README 与 `your-todo` 那一条仍然挂着）。⚠️ **手机已解锁**（2026-09-30 起），所以这一栏能做的事多了：真机云备份端到端已跑通（`E2E-OK`），安卓那两套商店截图已在真机上整套重跑、App Store 那套已在 iOS 模拟器出图。**但「用手指走一遍」仍然只有你能做** —— 我验的是装上、启动、`E/flutter` 零异常、以及自动化点 key 的流程；手感、误触、单手可达性测不到。细节见 `docs/your-todo.md` §四 |
| **体检数据的单独同意** | ✅ v1.31.0：体重属**敏感个人信息**（医疗健康类），按 PIPL 第 29 条**单独**征求同意 —— 第一次进「身体数据」页时单独弹一次说明（只存本机/不上传/可改可删），点了才记录，点「先不用」就不进那一页；同意时刻单独落库（schema **v14**）。中英政策与 `privacy-facts.json` 的 `sensitiveLocal` 同步，硬门禁**两处横查**（政策说法 ↔ 代码里那道门）|
| 匿名统计的默认值 | ✅ **默认关闭**（v1.28.0，审计 A 的后半段）。只有用户主动到「我 → 帮助改进产品」打开才会有数据发出去；off 时连队列里没发出去的也停发；硬门禁三处对账（`privacy-facts.json` ↔ 代码默认值 ↔ 中英政策正文）。**并在设备上验过两跑**：默认（关）跑完整轮训练，应用真实库里 `pending=0`；同一流程预置成开则 `pending=11` —— 证明测量本身没坏（`integration_test/analytics_outbox_e2e_test.dart`）。**iOS 上同样两跑一致**（2026-09-30，模拟器 iOS 27.0）。⚠️ 这条与下面「积压事件」那条一起，决定"配了上报地址的包"能不能发 |
| 个人信息收集清单（164 号文） | ✅ 应用内二级菜单「我 → 关于 → 个人信息收集清单」（v1.29.0）。两份清单都是**生成物**：收集清单 ← `privacy-facts.json`，共享清单 ← 政策里的第三方 SDK 表；与应用内隐私政策共用一套生成与防漂守卫（`gen-privacy-page.mjs --check`） |
| 屏幕方向 | ✅ **锁竖屏**（v1.30.0）。实测横屏下首页 `RenderFlex overflowed by 80px`，入口文字与底部导航重叠 —— 我们没有横屏设计，所以两端都锁（安卓 `screenOrientation="portrait"`、iOS 手机方向数组只留 Portrait），各有一条守卫钉着 |
| 显示配置 | ✅ 六种配置实测过（常规竖屏 / 横屏 / iPad 宽度 / 浅色模式 / 大字号 1.3× / 小屏 720×1280），矩阵与复现命令在 `docs/screenshots.md`。⚠️ 它能证明"不会坏"，**不能**替代用手指走一遍 |
| **iOS 侧** | 🟡 代码侧就绪，且**已能构建**（⚠️ 在 Xcode 里会看到 **1 条警告** —— `share_plus` 插件里 `keyWindow` 的弃用提示，有 `@available` 守卫、我们的部署目标 iOS 15 走不到那行，**不用管**：见 `docs/tech-decisions.md`「已知警告」）：**2026-09-30 已构建**（许可证接受之后的第一次）：`flutter build ios --simulator --no-codesign` → 183M 的 Runner.app；`flutter build ios --release --no-codesign` → **19M / arm64 / 最低 iOS 15.0**。产物逐项核对过：显示名「练了么」、bundle id `com.sdknwdtvpv.lianleme`、版本 `1.31.0 / 40` —— 那是首编那一次的产物）、**只有 `NSPhotoLibraryAddUsageDescription`**（没有读相册那条）、`ITSAppUsesNonExemptEncryption=false`、`UIUserInterfaceStyle=Dark`、方向数组**只有竖屏**；`Frameworks/` 里有 `sqlite3.framework` 与 `objective_c.framework`（正是守卫盯着的两个原生资源包），且**没有 Pods** —— SPM 路线由真实构建确认。 ✅ **2026-10-01 在 v1.35.2 上重编重核**：`flutter build ios --release --no-codesign` → **20.9MB / arm64**，`node tool/check-ios-app.mjs` 逐项一致（身份「练了么」· `com.sdknwdtvpv.lianleme`、版本 **1.35.2 (48)**、只有仅新增相册权限、Dark、竖屏锁、应用内资产三件、`sqlite3.framework` + `objective_c.framework`、启动屏已编译进包、`Assets.car` + 2 个 AppIcon、**设备族 `[1]` = 只支持 iPhone** —— 2026-09-30 拍板，产物里含 iPad 现在会判红）。**新增第 10 条核对：应用级隐私清单**（`PrivacyInfo.xcprivacy`）必须在包里、`NSPrivacyTracking=false`、至少声明一类 required-reason API —— 2026-10-01 补的文件 + 守卫（两条负向用例）。**第 9 条核对：出口合规的"决定"必须留痕** —— 包里确实有标准算法的加密代码（AES-256-GCM + HKDF-SHA256，云备份用），所以 `docs/store-listing-ios.md` 里必须写明算法、两种口径与"谁来决定"（见该文件「出口合规」一节，负向测试：把算法名从文档里拿掉 → 真产物核对当场红）。 ✅ **2026-09-30 又进一步**：模拟器运行时（iOS 27.0，约 8G）装好后，App **第一次在 iOS 上真的跑起来** —— 同一份 `integration_test/screenshots_test.dart` 在 iPhone 17 Pro Max 上出图 **12 张 / 0 步失败 / 1320×2868**，逐屏用眼睛看过；因为 iOS 模拟器给的是 **16 位 RGBA**、而 App Store 只收 **8 位无 alpha**，新增 `tool/flatten-png.mjs` 压平（三套截图现在都由 `tool/check-screenshots.mjs` 核，含这两条硬规矩）。⚠️ 还差**签名与上传**（要 Apple Developer 账号）。⚠️ 另有一条**未定性**的观察：在那台模拟器上第一次跑这套脚本时（运行时刚装完、App 首次启动），首页刷新报过一次 drift 后台 isolate 的错（0 张图）；此后**连跑 5 次全新安装，5 次全绿 13/13** —— 像一次性环境问题，但**没定位到根因**，也没在真机上验过（那要 Apple 账号）。商店表单字段见 `docs/store-listing-ios.md` |
| **CI（GitHub Actions）** | ✅ **CI 跑的就是门禁本身**（2026-09-30）：`.github/workflows/ci.yml` 只有一条 `./verify.sh`，在 `ubuntu-24.04` / node 22 / flutter 3.47.5 上跑。三次实测：`7f0ed36` → 235 秒、`997070a` → 249 秒、**`6be4a66`（v1.34.0）→ 262 秒**，都是 `success`。**关键是它绿得可证**：多了一步「门禁账目」——日志里 `[1/6]`…`[6/6]` 必须都在、**不许出现「⊘ 阻塞」**、且写着"未发现失败"，否则判红（`verify.sh` 在开发机上把"环境阻塞"当不失败，CI 上必须反过来）。失败时那几行会被抬成 `::error::` **注解**（job 日志要凭据才读得到，注解公开可读）|
| 全新克隆 | ✅ **`git clone` 之后直接 `./verify.sh` 就能跑完六层**（2026-09-30 首次实测：一份干净克隆里跑出 168 个 ✓、`未发现失败`；**2026-09-30 晚在 `2f66d40` 上又跑了一遍**：753 项测试全绿、**`未发现失败`、零阻塞**、新增的那几个守卫（CI/商店表单/交付目录/部署包/截图）自检也都在克隆里跑过 —— `dist/` 不在时的跳过路径同样验到了）。此前不是这样：第 2 层会假报「有直接依赖不支持 iOS」、第 4 层判阻塞、第 5 层自己 pub get 后因缺 `db.g.dart` 失败 —— 三层对「还没引导过」的反应互相矛盾。现在 `verify.sh` 开头有第 0 步引导（按需 pub get + 生成 drift 代码）|
| 测试 | ✅ 门禁 **778 项全绿**、变异 24 杀 / 0 存活 = 100%。⚠️ 上面这个数字是**唯一的事实源**：`verify.sh` 第 5 层会拿实测条数跟它对比，对不上就判红（README 里那些"553 条测试"之类的抄写就是这么烂掉的） |
| 上报地址的"积压事件"决策 | ❌ **未定，且它会阻断"配了上报地址的包"**：没配地址的包把事件攒在本地（不丢），所以第一次配上地址时会把**旧版本攒下的事件**一起发出去。三选项见 `docs/analytics.md` §10，建议 C（或 B）。**定下来之前不要发布配了 `LIANLEME_ANALYTICS_URL` 的包** |
| `tap_count` 门禁 | ❌ 口径已改端到端、目标值**待用真实测试数据重新校准**。按项目规则**不允许上架**（旁边加载到自己的开发机不受此限） |

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

## 终局核验（2026-09-30，逐项实测）

出门之前把"产物 / 真机 / 对外数字"对齐了一遍。**每一项都是当场跑出来的**，不是抄上面的表：

| 项 | 实测结果 |
|---|---|
| `dist/` 内容 | `练了么-v1.31.0.apk` + `copyright/`（V1.31.0 的源程序与说明书 PDF/HTML + measure.html）+ `README.md` —— **没有上一版的残留** |
| APK（旁加载包） | `versionCode 48 · versionName 1.35.2`，与 `app_info.dart` / `pubspec.yaml` 一致；manifest 合并后 **2 条声明**（INTERNET、WRITE_EXTERNAL_STORAGE ≤29）+ 1 条注入（DYNAMIC_RECEIVER）+ 1 条隐含（READ ≤29，系统因 WRITE 授予） |
| `privacy-audit.mjs --apk`（发布前必跑） | ✅ 对得上：18 事件 / 7 公共字段 / 2 声明权限 / **打包后合并 5 条**全部已披露 |
| AAB（Google Play 通道） | ✅ `tool/check-aab.mjs`（**在 v1.35.2 上重核**）：119 条目 · 57.8 MB · **三 ABI** 原生库齐全（arm64-v8a / armeabi-v7a / x86_64）· 版本 **1.35.2** 与 `app_info.dart` 一致。⚠️ `flutter build appbundle` 仍会**假报** "failed to strip debug symbols"（卷名空格）并**退出码非 0**，产物没问题 —— 所以判据必须是"核产物"（`check-aab` / `check-dist`），不是看退出码。AAB 现在也放进 `dist/`，由 `tool/check-dist.mjs` 每次核版本（旧版本残留、文件名没版本号都判红）|
| 真机 `75caf509` | 装的是 **1.35.2（versionCode 48）**（⚠️ **跑过 `flutter drive` 之后必须重装一次**：截图脚本结束时会卸载 App，也会把 `wm size` 留在截图分辨率上 —— 见 `docs/dev-environment.md`）；`force-stop` 后冷启动正常、`E/flutter` **0 条**；屏幕尺寸已复位（1280×2772） |
| 商店截图三套 | `store-assets/screenshots/` 15 张（1080×2400，国内/软著）· `screenshots-play/` 14 张（1080×1920，Play 要的 9:16）· `screenshots-ios/` 14 张（1320×2868，8 位 RGB 无 alpha）。三套都是 **2026-10-01 在 v1.34.0 上重出**、v1.35.1 沿用（界面未再改版式）的（多一张 `10b-data-tools`：「我」页重排后身体数据/导出的入口在那一页）。齐/尺寸/夹带由 `tool/check-screenshots.mjs` 每次核对 |
| 全新克隆 | ✅ `git clone` 后直接 `./verify.sh` → 六层全跑、`未发现失败`（首测 168 个 ✓；`2f66d40` 复测 753 项测试全绿、零阻塞）。见 CHANGELOG：为此加了第 0 步引导 |
| iOS 产物 | ✅ `node tool/check-ios-app.mjs`（新工具，2026-09-30，安卓那边 `check-aab.mjs` 的对应物）：两种构建都逐项核过 —— 身份（显示名/两端 bundle id 一致）、版本 `1.31.0 (40)`、**只有「仅新增」相册权限（无读权限）**、主题 Dark、方向锁定、应用内资产三件齐、`sqlite3.framework` 与 `objective_c.framework` 都在。⚠️ 它同时报出一条产品决定：`UIDeviceFamily = [1,2]` → **这个包在商店里会承诺「支持 iPad」**（`your-todo` 第 10 条那一项）。工具带自检（造几份动过手脚的 .app 要求它抓得住），自检已进门禁第 2 层 |
| 软著材料 | `dist/copyright/` 里是 **V1.35.2**：源程序 **172 个文件 / 45,306 行 / 全文 907 页**、提交用前 30 + 后 30 页（正好 60 页）、说明书 6 页；著作权人仍是占位符（**待你实名提交**，生成命令：`node tool/copyright-pdf.mjs --owner "你的姓名"`） |

**这份核验能证明什么、不能证明什么**：能证明"我们这边该做的都做了、且对得上"；
**不能**证明"商店会收"—— 那还需要真 keystore（现在仍是 debug 签名）、备案、软著证书、
以及 iOS 那一次真实构建。这几件的入口都在 `docs/your-todo.md`。
