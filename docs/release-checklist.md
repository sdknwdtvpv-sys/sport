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

**现状：`release` 构建回落到 debug 签名**（`CN=Android Debug`），而那个 keystore 是构建时
自动生成的、机器相关 —— 商店一律拒收。

- [ ] 生成正式签名：
      ```bash
      cd app/android && ./tool/gen-upload-keystore.sh
      ```
      或复制 `key.properties.example` 为 `key.properties` 手动填写。
- [ ] **把 keystore 和密码备份到密码管理器与离线介质** —— 丢了就无法再更新已发布的应用
- [ ] 确认 `key.properties` 与 `*.p12` / `*.jks` / `*.keystore` **没有**进仓库：
      ```bash
      git status --short            # 不应出现 key.properties
      git check-ignore -v app/android/key.properties
      ```
- [ ] 构建并**验证签名者不再是 Android Debug**：
      ```bash
      cd app && flutter build appbundle --release
      "$JAVA_HOME/bin/keytool" -printcert -jarfile \
        build/app/outputs/bundle/release/app-release.aab | grep 所有者
      ```
- [ ] 决定是否启用 **Play App Signing**（Google Play 强烈建议；上传密钥与签名密钥分离，
      上传密钥丢了还能找回）

> 本项目已把「没有签名就产出 release」改成**硬失败**：缺失 `key.properties` 时
> `flutter build appbundle --release` 会直接报错退出，而不是静默给你一个 debug 签名的包。
> 确实需要 debug 签名（如性能测试）时用
> `ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build ...`。

## 3. ⛔ 隐私合规

- [ ] 审核并定稿 `docs/privacy-policy.md`（**当前是草案，未经法务审核**）
- [x] ✅ 占位符已填：运营者 `Elliot.LI`（个人开发者）、联系方式为 GitHub issue 地址
- [ ] 把「生效日期」改成实际的首次发布日（当前是 `【上架日填写】`）
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

## 7. 商店材料（国内商店额外）

- [ ] **软件著作权登记**（软著）—— 国内主流商店必需，办理有周期，**尽早启动**
- [ ] **App 备案**（工信部）—— 部分商店已强制要求
- [ ] 应用图标与截图（各商店尺寸不同）
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

./verify.sh                                      # 全量自检（5/5 才算过）

cd app
flutter build appbundle --release                # 商店用（AAB）
flutter build apk --release                      # 旁加载用（APK）

# 验收 release 产物
"$JAVA_HOME/bin/keytool" -printcert -jarfile \
  build/app/outputs/bundle/release/app-release.aab | grep 所有者   # 不应是 Android Debug
"$ANDROID_SDK_ROOT/build-tools/36.0.0/aapt2" dump badging \
  build/app/outputs/apk/release/app-release.apk | grep -E "^package|sdkVersion"
```

---

## 当前状态速览

| 项 | 状态 |
|---|---|
| 构建链 | ✅ APK 152M / AAB 53M 均可产出，`libsqlite3.so` 三 ABI 齐全 |
| 签名接线 | ✅ 已配好并三向验证（缺失时硬失败 / 逃生开关 / 正式签名生效） |
| 权限 | ✅ 只有 INTERNET，已进 release manifest |
| 隐私政策 | 🚧 中英文已成文、占位符已填；**待法务审核 + 公网 URL + 填生效日** |
| 删除数据入口 | ✅ 已实现并测试（400 项测试全绿），**待真机点一次** |
| 真机验证 | 🚧 真机上装的仍是 `v1.0.0`；`v1.2.0` **还没在设备上跑过** |
| `tap_count` 门禁 | ❌ 口径已改端到端、目标值**待重新校准**，按项目规则**不允许发布** |
