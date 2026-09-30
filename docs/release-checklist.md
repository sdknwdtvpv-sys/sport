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
- [x] ✅ **App 已装进真机**：`com.sdknwdtvpv.lianleme` v1.0.0 / versionCode 1，
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

## 6. 版本号

- [x] ✅ 遵守 `CHANGELOG.md` 开头的策略：**版本号只跟随 `app/` 下的代码改动**。
      `v1.2.0` 相对 `v1.1.0` 改的是 `app/` 代码（渐进建议接线 / `daysAgo` / `tap_count` 口径），据此切版。
- [x] ✅ **没有**升 major。本次没有破坏性变更（`lastSessionFor` 只是多了一个可选参数，
      两个实现同步改；`TapKind` 是加值），因此按 fix/feature 升 minor。
- [x] ✅ `app/pubspec.yaml` 已 bump：`version: 1.2.0+3`（build number `+2` → `+3`）
- [ ] `app/android/app/build.gradle.kts` 的 `versionCode/versionName` 取自 Flutter，
      无需手改；但**每个商店上传的 versionCode 必须递增**
- [x] ✅ `CHANGELOG.md` 已同步为「v1.2.0」，与 commit / tag 一同落地
- [x] ✅ 顺带补回 CHANGELOG 开头**丢失的版本号策略正文**（本节引用的就是它）
- [ ] ⚠️ **界面上的版本号也要改**：`app/lib/core/app_info.dart` 的 `kAppVersion`。
      以前它是写死在 `profile_screen.dart` 里的，v1.1.0 / v1.2.0 两次切版都没带上，
      界面上错了两个版本。现在由 `app/test/app_version_test.dart` 读 pubspec 核对 ——
      **忘了改 `flutter test` 会红**，不用靠人记得。

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

## 当前状态速览

**2026-09-30 重新核对过一遍**（上一版停在 v1.2.0，好几行早就过期了 —— 过期状态比没有状态更坏，
因为它会让人以为某件事已经做过了）。

| 项 | 状态 |
|---|---|
| 构建链 | ✅ 两种产物都核过：release **APK 59.8M**（`flutter-apk/app-release.apk`）、**AAB 55.9M**（`bundle/release/app-release.aab`）。AAB 用 `node tool/check-aab.mjs` 核过：骨架三件套 + **三 ABI**（arm64-v8a / armeabi-v7a / x86_64，各含 libsqlite3/libflutter/libapp）+ 版本号与 `app_info.dart` 一致。⚠️ `flutter build appbundle` 会**假报失败**（卷名空格坑，见 `docs/dev-environment.md`），产物没问题 |
| 签名接线 | ✅ 接线与硬失败**已验证**（缺 `key.properties` 时构建直接失败、逃生开关有效） |
| 正式签名 | ❌ **还没有真 keystore**。所以 `dist/*.apk` 是**debug 签名的旁加载包** —— 能装自己手机，**商店必拒收**。生成：`app/android/tool/gen-upload-keystore.sh`（在你那边） |
| 权限 | ✅ 源码 manifest **两项**（INTERNET + `WRITE_EXTERNAL_STORAGE` 限 API ≤29）。打包后多一条**隐含**的 `READ_EXTERNAL_STORAGE`（≤29，系统因 WRITE 授予，不是谁声明的）—— **已在政策里如实披露** |
| 隐私政策 | 🚧 中英文已成文、占位符已填；**待法务审核 + 公网 URL + 填生效日**。⚠️ 云备份一旦上线，§3.1/§3.2 必须重写（数据**会**离机） |
| 删除数据入口 | ✅ 已实现并测试。v1.22.0 补上了**条件式的云端删除**：有云备份账号时，弹层多问一句「同时删除云端备份并注销」（默认勾选），先删云端、失败则整个中止 |
| 真机验证 | ✅ Redmi `flourite`（Android 16 / API 36）上跑的是 **v1.21.0**（逐版覆盖安装；冷启动无异常） |
| 测试 | ✅ 门禁 **685 项全绿**、变异 24 杀 / 0 存活 = 100%。⚠️ 上面这个数字是**唯一的事实源**：`verify.sh` 第 5 层会拿实测条数跟它对比，对不上就判红（README 里那些"553 条测试"之类的抄写就是这么烂掉的） |
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
