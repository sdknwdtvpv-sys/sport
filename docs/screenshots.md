# 界面截图（软著说明书 / 商店列表都要）

**一句话**：截图不该靠"拿手机一张张手工截"。这里是**一条命令从真实 App 里生成**的。

## 三套图，别拿错

| 目录 | 尺寸 | 给谁用 |
|---|---|---|
| `store-assets/screenshots/` | **1080×2400**（20:9，设备真实比例） | 软著说明书、国内安卓商店（对宽高比宽松） |
| `store-assets/screenshots-play/` | **1080×1920**（**9:16**） | **Google Play** —— 它要求宽高比在 9:16 或（另一种说法）1:2～2:1 之间，**两种口径都排除 20:9** |
| `store-assets/screenshots-ios/` | **1320×2868**（iPhone 6.9 吋，**8 位 RGB、无 alpha**） | **App Store** —— 由 iOS 模拟器（iPhone 17 Pro Max）出图，再过 `tool/flatten-png.mjs` 压平 |

两套是**同一个测试**跑出来的，只是把设备的逻辑分辨率换了一下：

```bash
adb -s <设备> shell wm size 1080x1920      # 切到 9:16
cd app && SHOT_DIR=../store-assets/screenshots-play \
  flutter drive --driver=test_driver/screenshot_driver.dart \
               --target=integration_test/screenshots_test.dart -d <设备>
adb -s <设备> shell wm size reset          # 记得还原
```

> ⚠️ **口径本身就有一处分歧**：第三方整理的 Play 规格里，一处写"必须 9:16 或 16:9"，
> 另一处写"1:2 ～ 2:1"（[官方页](https://support.google.com/googleplay/android-developer/answer/9866151)在我这儿取不到）。
> 9:16 的 1080×1920 在**两种口径下都合法**，所以那套是安全的。国内商店用 20:9 那套即可。
>
> Apple 那边**既不认 9:16 也不认 20:9**：它按设备档位要求精确像素（6.7" = 1290×2796 等），
> 要等 iOS 模拟器跑通之后单独出图 —— 见 `docs/store-listing-ios.md`。

## 怎么跑

```bash
cd app
flutter drive --driver=test_driver/screenshot_driver.dart \
              --target=integration_test/screenshots_test.dart -d <设备 id>
```
**`-d` 一定要给**：接了两台设备时（例如真机 + 模拟器），不指定就是薛定谔的截图。
本仓库的做法与踩过的坑见 `docs/dev-environment.md`「安卓模拟器」一节（
`emulator-5554` 就是在那台无头模拟器上跑的，**不需要解锁真机**）。

产物写进 `store-assets/screenshots/`（**入库**：它是交付物，不是 `dist/` 那种构建产物）。

## App Store 那套：iOS 模拟器出图 + 一次"压平"

2026-09-30，模拟器运行时（iOS 27.0，8G，`xcodebuild -downloadPlatform iOS`）装好后，
这个 App **第一次真的在 iOS 上跑起来**（此前只到"编得出包"这一层）：

```bash
UDID=$(xcrun simctl create lianleme-69 \
        com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
        com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$UDID"
cd app && SHOT_DIR=/tmp/shots-ios flutter drive \
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/screenshots_test.dart -d "$UDID"
# 12 张图 → 过一遍压平（16 位 RGBA → 8 位 RGB）→ 入库
for f in /tmp/shots-ios/*.png; do
  node tool/flatten-png.mjs "$f" "store-assets/screenshots-ios/$(basename "$f")"
done
```

**为什么必须压平**（两步都是实测出来的，不是抄规格）：Flutter 在 **iOS 模拟器**上截出来的
PNG 是 **16 位 RGBA**（同一份脚本在安卓上是 8 位 RGBA）；而 App Store 的截图规格要求
**8 位、扁平、不带 alpha**。`tool/flatten-png.mjs` 干这两件事，并且**只干这两件事**：
不缩放、不裁剪；只要有一个像素不是完全不透明，它就**拒绝**而不是替你垫个黑底。

> ⚠️ 一条边界：Apple 那张规格表（`developer.apple.com/help/app-store-connect/reference/
> screenshot-specifications`）在我这儿**只能取到被截断的正文**，档位要求（"6.9 或 6.5 二选一，
> 其余由 App Store Connect 自动降采样"）来自第三方整理（[appshot 的 specs](https://raw.githubusercontent.com/ai-zixun/appshot/refs/heads/main/skills/appshot/references/apple-specs.md)、
> [Adalo 的 2026 指南](https://studio.adalo.com/blog/app-store-screenshot-sizes-2026)）——
> **上传时 App Store Connect 自己会校验**，以那时为准。我们按最保险的做：6.9 吋那套出全、压平。

## 出的图对不对：`node tool/check-screenshots.mjs`

截图是本仓库**唯一一类此前没有任何东西核过**的交付物（图标有 `asset-check.mjs`、
AAB 有 `check-aab.mjs`、iOS 包有 `check-ios-app.mjs`，截图全靠人记得）—— 而它**真坏过**。
这个工具每次进门禁第 2 层，核四件事：

1. **齐**：清单写在工具里（显式的，改名要改它）；
2. **对**：每张的实际像素 == 这套图的规格（1080×2400 / 1080×1920 / **1320×2868**）——
   挡住"被谁顺手缩过一遍"和"拿错设备出的图"；**App Store 那套还多两条：必须 8 位、必须没有
   alpha**（工具报的是"忘了压平"，不是"图不好看"）；
3. **没夹带**：目录里不许有清单外的 PNG。典型的是 `zz-fail-<步骤>.png` —— 那是脚本某一步
   失败时自动拍的现场图，**它在 = 这套图不全，不能上架**；
4. **那道同意门与那条撤回入口必须在**（`11a-body-consent.png`、`11b-body-revoke.png`）。

自检 9 例（少一张 / 那道门不见 / 尺寸不对 / 夹带失败现场图 / 混进清单外的图 / 整套没了 /
App Store 那张仍是 RGBA / App Store 那张仍是 16 位 / 好的三套）。

> ⚠️ **它为什么要有第 4 条 —— 一个真发生过的 bug**：v1.31.0 起「身体数据」前面多了一道
> **敏感信息单独同意**的门（PIPL 第 29 条），而截图脚本当时假定"点开就是表单"。
> 在**已同意**的设备上跑，它拍到的确实是表单；在**干净安装**上跑，它拍到的会是对话框 ——
> 而且**照样命名成 `11-body-metric`**。同一份脚本，出什么图取决于设备状态，目录里还看不出来。
> 现在脚本走用户真实路径（门 → 点「同意并记录」→ 再拍），并额外留一张 `11a-body-consent`。

## 为什么用 `integration_test` 而不是 widget 测试

两条路都试过，差别是决定性的：

| | widget 测试（`flutter test`） | integration_test（`flutter drive`） |
|---|---|---|
| 字体 | 用测试字体，**汉字会渲染成方框** | 真实系统字体 |
| 分辨率 | 要手工摆 | 真实设备（本项目 1280×2772） |
| 点击 | 进程内模拟 | 进程内模拟 |

**关键点：真机上本来截不了图。** MIUI 禁掉了 `adb shell input`（`INJECT_EVENTS`），
屏幕点不动。但 integration_test 的点击是**在 App 进程内模拟**的，不走 adb 注入那条路 ——
所以它绕开了这个限制。

## ⚠️ 真机安装受 MIUI 限制（2026-09-30 实际踩到）

`flutter drive` 会先装一个测试包。**MIUI 的「USB 安装」授权会失效**，症状是：

```
Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]
```

更糟的是：连续失败之后**设备上原来的 App 也被卸掉了**（2026-09-30 就是这样，
Redmi flourite 上现在没有「练了么」）。恢复方法（**必须在手机上操作**）：

1. 设置 → 更多设置 → 开发者选项 → 打开 **「USB 安装」**（有的版本叫「通过 USB 安装应用」）
2. 若弹出确认框，点「允许」
3. 之后 `adb install -r` 与 `flutter drive` 都能用；装回正式包：
   `adb install -r ../dist/练了么-v<版本>.apk`

## 真机装不上时的替代路径：Android 模拟器（2026-09-30 打通）

> ⚠️ **当前未安装**：`emulator` 与 `system-images;android-34;google_apis;arm64-v8a`
> 已在 2026-09-30 按你的要求卸载（它们占 6.5G，而截图已经取完）。
> 需要再出图时按下面命令装回即可（约 2G 下载）。真机的输入注入现在可用了，
> 走真机比走模拟器更快。

MIUI 锁住 USB 安装时（见上），**模拟器不受影响** —— 能装、能跑、能截，
而且**输入注入是通的**（真机被 MIUI 禁了，模拟器没有）。

> ⚠️ **2026-09-30 补充（别当它永远成立）**：这条是当时在**无头模拟器 + debug 包**上验的。
> 同一天在同一个模拟器上装 **release 包**（`dist/练了么-v1.32.0.apk`）后，
> `adb shell input tap` 连点三次都没落进 App（隐私同意门一直没被点掉），原因没查清。
> **截图流程不受影响** —— `flutter drive` 的点击是进程内模拟的，与 adb 注入无关；
> 但"用 adb 点着走一遍"这件事**不能默认能用**，得每次现验。

一次装好（约 2GB 下载，之后一直可用）：

```bash
sdkmanager --install "emulator" "system-images;android-34;google_apis;arm64-v8a"
avdmanager create avd -n lianleme -k "system-images;android-34;google_apis;arm64-v8a" -d pixel_6
emulator -avd lianleme -no-window -no-audio -no-boot-anim -no-snapshot \
         -gpu swiftshader_indirect -memory 2048 &     # 无头启动，不需要窗口
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 install -r "dist/练了么-v<版本>.apk"
```

**已经用它验过的事**：v1.17.0 在**全新安装**的 Android 14 上装得上、起得来、渲染正确
（`store-assets/screenshots/01b-home-fresh-install.png`）；启动器里图标与名字也对
（`docs/images/launcher-icon-verified.png` —— volt 圆底 + 墨色「练」、名称「练了么」，
这是自适应图标第一次被**眼睛**验证，而不是只比字节）。

**已知的坑（别重复踩）**：

- 软件渲染很吃 CPU：本机负载 8 时它自己吃 346%，总负载被推到 20。
  这时 SystemUI 会弹 "isn't responding" —— **不影响 App**，也不影响
  `binding.takeScreenshot`（那只截 Flutter 自己的 surface）。
- 但在这种负载下 **`flutter drive` 会卡在最后一步**：测试 11 步全跑完了
  （到 `10-profile`），driver 侧的写盘迟迟不返回（截图字节要等整个 run 结束才回传）。
  要用模拟器出图，**先把机器空出来**，或者用真机。
- 截图落盘目录仍是 `store-assets/screenshots/`（driver 不区分来源，文件名要自己标）。
- **它占约 6.5GB 磁盘**（emulator 1.1GB + 系统镜像 4.2GB + AVD 1.2GB）。
  2026-09-30 已按此回收（命令如下），下次要用再重装：
  ```bash
  sdkmanager --uninstall "emulator" "system-images;android-34;google_apis;arm64-v8a"
  avdmanager delete avd -n lianleme
  ```

## 显示配置矩阵（2026-09-30 实测，同一套脚本换配置跑）

同一个 emulator（`lianleme_api36` / API 36）上，用同一份 `screenshots_test.dart` 换显示配置跑，
看**会不会坏**。判据是两条：`logcat` 里 `overflowed` 命中数（布局溢出）+ 人眼看截图。

| 配置 | 怎么设 | 结果 |
|---|---|---|
| 常规竖屏 1080×2400 | 默认 | ✅ 11/11、0 溢出 |
| **横屏** 2400×1080 | `adb shell wm size 2400x1080` | ❌ **首页 `RenderFlex overflowed by 80px`**（另有 44px 一处），入口文字与底部导航重叠 —— **已用"锁竖屏"修掉**（v1.30.0，两端各一条守卫） |
| **iPad Pro 12.9 吋** 2048×2732（≈4:3） | `wm size 2048x2732` + `wm density 320` | ⚠️ 不崩、0 溢出，但**是拉长的手机布局**（大按钮变通栏、内容靠左、大片空白）→ **已据此拍板只支持 iPhone**（`TARGETED_DEVICE_FAMILY = "1"`，2026-09-30，见 `docs/release-admin.md`）；证据图 `docs/images/ipad-width-*.png` |
| **系统浅色模式** | `adb shell cmd uimode night no` | ✅ 11/11、0 溢出；App 仍是深色（与 iOS 的 `UIUserInterfaceStyle=Dark` 一致），没有白底/白闪 |
| **大字号** 1.3× | `adb shell settings put system font_scale 1.3` | ✅ 11/11、0 溢出；长句正常换行（截图里「每个动作用它自带的休息时长……」折成两行） |
| **小屏** 720×1280 @320dpi | `wm size 720x1280` + `wm density 320` | ✅ 11/11、0 溢出 |

跑完记得**还原**（这几条都会改设备状态）：

```bash
adb shell wm size reset          # 屏幕尺寸
adb shell wm density reset       # 密度
adb shell settings put system font_scale 1.0
adb shell cmd uimode night no    # 若原来是自动/夜间，按原值改回
```

> ⚠️ **这张表能证明的是"这些配置下不会坏"，不能证明"好看"**。横屏那次就是靠它抓出来的；
> 而「手感、误触、单手可达性」这类只有人用手指走一遍才知道 —— 那件事仍挂在
> `docs/your-todo.md` 里，没有被这张表顶掉。

## 真机全流程走查（另一批图，不是商店素材）

2026-10-01 在真机上把整个 App 走了一遍并逐屏留证：`docs/ux-review-2026-10-01.md`
（20 张图在 `docs/images/ux-review-2026-10-01/`）。那批图的作用是**发现"哪里不顺眼"**，
不是交付物 —— 商店素材看下面三套。

## 已覆盖 / 还缺

**12 屏 + 一道同意门 + 一条撤回入口 + 一张整屏的"全新安装空态"，共 15 张**
（主体是 **2026-10-01 在 v1.34.0 上用真机重出**的那套，1080×2400 ——
尺寸与"齐不齐、有没有夹带"由 `tool/check-screenshots.mjs` 每次进门禁核对。
重出的原因：「我」页重排后身体数据 / 导出 / 导入的入口挪进了「数据与备份」，
商店图必须与 App 一致；顺手多截了 `10b-data-tools` 那一屏）：

| 文件 | 屏 |
|---|---|
| `01-home.png` | 首页（有历史数据） |
| `01b-home-fresh-install.png` | 首页（**全新安装**的空态） |
| `02-suggestion.png` | 建议卡（今天练 X + 每个动作的建议重量与理由） |
| `03-routine.png` | 我的计划 |
| `04-picker.png` | 选动作（351 个动作 + 三排筛选 + 动作说明） |
| `05-workout.png` | 训练屏（大按钮上写着建议重量） |
| `06-workout-logged.png` | 记完两组（组列表 + 休息计时） |
| `07-summary.png` | 训练完成（容量/时长/组数 + 分享训练卡） |
| `08-progress.png` | 进步（本周容量 + PR 墙 + 体重入口） |
| `09-all-data.png` | 全部数据 |
| `10-profile.png` | 「我」页（**2026-10-01 重排后**：训练统计 + 三个入口 + 版本行，一屏不滚） |
| `10b-data-tools.png` | 「数据与备份」页（身体数据 / 导出 CSV / 导出备份 / 导入备份 / 删除全部数据） |
| `11-body-metric.png` | 身体数据（**kg / lb / 斤 实时切换**，2026-10-01 起三个单位，默认跟随训练单位）——**同意之后**的样子 |
| `11a-body-consent.png` | 身体数据前面的**敏感信息单独同意**（PIPL 第 29 条）——见下面那条"图比 App 旧"的坑 |
| `11b-body-revoke.png` | 同一页最下面的**「撤回我的同意」**（PIPL 第 15 条的撤回权，v1.32.0 起）——滚到底才看得见 |
| `docs/images/launcher-icon-verified.png` | 启动器图标与名字（不算商店素材，是验证证据） |

尺寸（如实记，不藏着）：

- **2026-09-30 又在真机上整套重跑过**（Redmi `flourite` / Android 16 / API 36）：
  国内那套 `wm size 1080x2400`、Play 那套 `wm size 1080x1920`，两套都是同一台真机、
  `integration_test` 抓 Flutter 自己的 surface（**不含系统状态栏**），爬完立刻 `wm size reset`。
  重跑的原因：v1.28.0 改了同意门与「我」页的隐私开关文案与默认值、v1.29.0 又新增了
  「个人信息收集清单」入口 —— 上一批截图是那之前的界面。
  > 真机与模拟器的差别：Doze / 厂商后台策略 / 真实字体渲染都更接近用户手里的样子；
  > 但**这一套仍然不能替代"用手指走一遍"的验收**（自动化点的是坐标与 key，不是手感）。
- `01b-home-fresh-install.png` 是 **`adb screencap` 抓的整屏**（含状态栏）
- `11a-body-consent.png` 与 `11b-body-revoke.png` 是**无头模拟器上"干净安装"那一跑**的产物
  （2026-09-30，1080×2400，与主体同一分辨率）：真机上装的是已经点过同意的状态，
  **那道门根本不会再弹** —— 要看它、要拍它，只能在干净安装上。它们也**不是**给商店上传的图
  （商店那几屏里夹一张对话框反而不好看），是留给软著说明书与合规自查的证据：
  一条证"同意是单独征得的"，一条证"同意随时可以撤回"（`**` 那类漏字只有截图看得见）。
- **App Store 那套（`store-assets/screenshots-ios/`）是 14 张**：上面那 12 屏 + 同意门 +
  撤回入口，尺寸 1320×2868，来源是 iPhone 17 Pro Max 模拟器（2026-10-01 在 v1.34.0 上重出：
  干净安装那一跑，14 张 / 0 步失败；第一次跑中途有 6 步连败、**重跑一次全绿** —— 那是模拟器/App 状态的一次性问题，不是脚本坏了），
  **出完图立刻压平**（16 位 RGBA → 8 位 RGB）。它没有 `01b` —— 模拟器那一跑本身就是全新安装
  （空态首页就是 `01-home`）。

商店通常逐张接收、不要求尺寸一致；Play 那套现在也是 14 张（同样带同意门与撤回入口），
挑 8 张上传就行。

`integration_test/screenshots_test.dart` 里每一步都单独包了 try：一步失败不会
丢掉前面截好的图，而且会**自动截一张 `zz-fail-<步骤名>` 的现场图**
（第一次跑时 9 步连败却不知道停在哪一屏，才加的这条）。

## 给商店/软著用的注意

- 商店通常要求 **3–8 张**，且**必须来自真实 App** —— 这批就是。
  `prototype/index.html` 是设计原型，**不能充数**。
- 软著说明书的界面图，每屏配一句说明即可（提纲见 `store-listing.md` 第七节）。
- 截图里有真实训练数据（"上次 4 组全部达标，线性加重 +2kg"）—— 这比空态好看，
  但也别截图里出现个人信息（当前没有：App 不要求注册）。
