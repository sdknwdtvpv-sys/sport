# 界面截图（软著说明书 / 商店列表都要）

**一句话**：截图不该靠"拿手机一张张手工截"。这里是**一条命令从真实 App 里生成**的。

## 两套图，别拿错

| 目录 | 尺寸 | 给谁用 |
|---|---|---|
| `store-assets/screenshots/` | **1080×2400**（20:9，设备真实比例） | 软著说明书、国内安卓商店（对宽高比宽松） |
| `store-assets/screenshots-play/` | **1080×1920**（**9:16**） | **Google Play** —— 它要求宽高比在 9:16 或（另一种说法）1:2～2:1 之间，**两种口径都排除 20:9** |

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
| **iPad Pro 12.9 吋** 2048×2732（≈4:3） | `wm size 2048x2732` + `wm density 320` | ⚠️ 不崩、0 溢出，但**是拉长的手机布局**（大按钮变通栏、内容靠左、大片空白）→ 建议 `TARGETED_DEVICE_FAMILY = "1"`；证据图 `docs/images/ipad-width-*.png` |
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

## 已覆盖 / 还缺

**11 屏全部到手**（2026-09-30，Android 14 模拟器，1080×2337）：

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
| `10-profile.png` | 我（单位 / 统计 / 渐进建议 / 隐私 / 数据） |
| `11-body-metric.png` | 身体数据（**kg / 斤 实时切换**） |
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

商店通常逐张接收、不要求尺寸一致；若要统一，用 11 张那套即可（它自己也齐了）。

`integration_test/screenshots_test.dart` 里每一步都单独包了 try：一步失败不会
丢掉前面截好的图，而且会**自动截一张 `zz-fail-<步骤名>` 的现场图**
（第一次跑时 9 步连败却不知道停在哪一屏，才加的这条）。

## 给商店/软著用的注意

- 商店通常要求 **3–8 张**，且**必须来自真实 App** —— 这批就是。
  `prototype/index.html` 是设计原型，**不能充数**。
- 软著说明书的界面图，每屏配一句说明即可（提纲见 `store-listing.md` 第七节）。
- 截图里有真实训练数据（"上次 4 组全部达标，线性加重 +2kg"）—— 这比空态好看，
  但也别截图里出现个人信息（当前没有：App 不要求注册）。
