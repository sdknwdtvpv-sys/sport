# 界面截图（软著说明书 / 商店列表都要）

**一句话**：截图不该靠"拿手机一张张手工截"。这里是**一条命令从真实 App 里生成**的。

## 怎么跑

```bash
cd app
flutter drive --driver=test_driver/screenshot_driver.dart \
              --target=integration_test/screenshots_test.dart
```

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

两处尺寸差异（如实记，不藏着）：

- 11 张是 **1080×2337**（`integration_test` 抓的是 Flutter 自己的 surface，不含系统状态栏）
- `01b-home-fresh-install.png` 是 **1080×2400**（`adb screencap` 抓的整屏，含状态栏）

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
