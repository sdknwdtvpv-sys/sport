# 界面截图（软著说明书 / 商店列表都要）

**一句话**：截图不该靠"拿手机一张张手工截"。这里是**一条命令从真实 App 里生成**的。

## ⚠️ 两种时代：`docs/images/legacy-5tab/` 是**旧 IA** 的证据

**这一批是 5 格时代的证据，只用于追溯，不是当前状态。**

* 3 格底栏（进步 / 开练 / 我）是 **2026-10-10** 落地的（`docs/plan-ux-2026-10-10.md`），
  在那之前的证据图拍的都是**五格底栏**（训练 / 进步 / 数据 / 计划 / 我的）——
  而两批图原来混在同一个目录里、**文件名里没有一处标明"这是旧 IA"**，
  2026-10-10 的 VI 复核就被它们误导过一轮（C 自己按旧图提了一条已经改过的意见）。
* 判定规则（机械、可复核）：**按产出的日期切** —— `git log -1 --date=short` 早于 2026-10-10
  的顶层 `docs/images/*.png` 全部 `git mv` 进了 `docs/images/legacy-5tab/`（83 张，
  用 `git mv` 是为了保住历史）。文档里的引用同时改过，`check-doc-paths` 当场合过。
* **新证据图请放"主题 + 日期"的子目录**（例：`docs/images/plan-vi-2026-10-10/`），
  别再加到顶层 —— 顶层的图一旦没有日期，下一个人分不出它是哪个时代的。
* ⚠️ **三套商店截图（`store-assets/screenshots*`，43 张）还是 5 格时代那一套**，
  重出要等**代码稳定**（切版那一步一起做）。重出后必须体现：① 三格底栏 ② 完成页的新解锁横条
  ③ 分享卡两种版式 ④ 成就册的缩略图 —— 这四条是 T3-8 判据 3 的内容，**现在没做，不是忘了**。

> ✅ **2026-10-04 在 v1.41.0 上整套重出过**（此前那批是 v1.34.0 拍的，而
> v1.38.0 换了首页中间那块、v1.40.0 删了首页一行入口、v1.41.0 又给选择器加了「置顶」、
> 给计划模板加了标签 —— 四张图已经与真机不一样了）。
>
> **这次重出跑了两轮**（值得记下来，因为第一轮白跑了）：第一轮拍完之后又把模板标题从 `Row` 改成 `Wrap`（第一版会把名字挤到折行："上下肢 A · 下 / 肢"），于是**三套都得再拍一遍**。
> ⚠️ 中间还真丢过一次：安卓那轮的新图落在无撇号的「跑道」副本里、**没及时拷回主仓库**，随后一次 `rsync --delete` 把它覆盖回了旧版（iOS 那套因为是从 `/tmp` 拷的，反而留下了）。**教训**：跨仓库改产物时，`rsync` 的方向要当场确认（`rsync -a "$SRC/" "$DST/"` 会**覆盖** DST）。
>
> **重出时的两条实测结论**（下次别再怀疑一遍）：
> * ~~`11-body-metric` 与 `11b-body-revoke` 的字节**完全相同是预期的**：身体数据那一页
>   在 20:9 上**不需要滚动**，「撤回我的同意」本来就在同一屏里。~~
>   ⚠️ **这一条已经作废（2026-10-10）**：2026-10-09 那次改版把撤回入口从「身体数据」页
>   **搬进了「隐私与关于」**（用户原话"撤回同意这种设置类的入口全部收纳到设置里"）。
>   所以现在 `11b-body-revoke` 拍的是**另一页**、两张图的字节**一定不同**；
>   如果哪天又完全相同了，说明脚本又走老路（见下一条的排练办法）。
> * ⚠️ **别在 Android 设备锁屏时跑**：`flutter drive` 会先装 `app-debug.apk`，
>   而 MIUI 每次都要人工点一下「继续安装」对话框 —— 屏幕一锁，既点不到、`uiautomator dump`
>   还会因为动画失败。踩过的坑与绕法写进了 `docs/dev-environment.md`。
> 影响面：软著说明书的首页配图、国内/Play/App Store 三套列表的首图。
> 重出办法就是下面这条命令（真机已解锁、脚本本来就走这条路）——
> 出完记得同步 `docs/release-checklist.md` 里"商店截图三套"那一行的版本与日期。

## 三套图，别拿错

| 目录 | 尺寸 | 给谁用 |
|---|---|---|
| `store-assets/screenshots/` | **1080×2400**（20:9，设备真实比例） | 软著说明书、国内安卓商店（对宽高比宽松） |
| `store-assets/screenshots-play/` | **1080×1920**（**9:16**） | **Google Play** —— 它要求宽高比在 9:16 或（另一种说法）1:2～2:1 之间，**两种口径都排除 20:9** |
| `store-assets/screenshots-ios/` | **1320×2868**（iPhone 6.9 吋，**8 位 RGB、无 alpha**） | **App Store** —— 由 iOS 模拟器（iPhone 17 Pro Max）出图，再过 `tool/flatten-png.mjs` 压平 |

### ✅ 三套的产出路径都在 2026-10-10 **空跑验证过**（切版当天照做即可）

| 那一套 | 怎么出 | 2026-10-10 实测 |
|---|---|---|
| `screenshots/`（1080×2400） | Android 模拟器 `emulator-5554`（原生就是 1080×2400） | 这一套 **16 张**（脚本出 15 张 + `01b-home-fresh-install` 那张是整屏 `adb screencap` 补的，2026-09-30 起就如此）；`SHOT_DIR=/tmp/android-rehearsal` 空跑 **0 失败**，图是暗色的正常画面（**不是**白底/反色） |
| `screenshots-play/`（1080×1920） | 先在模拟器上 `adb -s emulator-5554 shell wm size 1080x1920`，跑完 `wm size reset` | 这一套 **15 张**，空跑 **0 失败**；`wm size` 已复位（`Physical size: 1080x2400`） |
| `screenshots-ios/`（1320×2868，8 位无 alpha） | iOS 模拟器 `FC97CA61-…`（iPhone 18 Pro Max）出图 → `tool/flatten-png.mjs` 逐张压平 | 这一套 **15 张**，空跑 **0 失败**；压平前实测 **16 位 + alpha**，压平后 **8 位 + 无 alpha + 1320×2868** ✅ |

> ⚠️ 顺带纠正一条**本仓里传过的说法**：Android 模拟器上 `convertFlutterSurfaceToImage()`
> 出来的图**不是**"白底/反色"。2026-10-10 那三张的像素均值是 RGB ≈ (23,17,14)～(46,29,22)
> —— 正常的深色界面；上面 `01-home` 也逐张用眼睛看过（三格底栏、橙色大按钮都在）。
> 之前那条结论若还写在别处，以这次的实测为准。

一张总的证据图：`docs/images/plan-vi-2026-10-10/store-rehearsal-sheet-20261010.png`
（⚠️ 文件名里那个日期**故意不加连字符**：`check-screenshots` 会把文档里
「两位数字 + 连字符 + 名字 + 点 png」形状的记号当成**商店截图的文件名**去核，
于是带连字符的日期尾巴会被它截成一段假文件名、判"三套里没有这个文件"。
别"顺手"改回带连字符的写法 —— 这一行本身就得绕开那个形状。）
（2026-10-10 空跑出来的 20:9 那套 15 张拼成一张，一眼能看出"切版当天会出什么样的图"：
三格底栏、橙色大按钮、成就册、分享卡、隐私与关于那一屏都在里面）。

### ⚠️ 重出之前先**空跑一遍**（2026-10-10 加，起因是一次真事故）

```bash
cd app && SHOT_DIR=/tmp/store-rehearsal \
  flutter drive --driver=test_driver/screenshot_driver.dart \
               --target=integration_test/screenshots_test.dart -d <设备>
```

判据是最后那行 `LIANLEME-SHOT-SUMMARY` 里的 **`失败 0 步`**；写 `/tmp` 就**不会动到仓库里那三套图**。
为什么值得多花这几分钟：脚本坏掉有两种形态，**第二种没有任何守卫拦得住** ——
2026-10-10 空跑时才发现 `11b-body-revoke` 那一步早就走不通（报 `Bad state: No element`），
因为 2026-10-09 把撤回入口从「身体数据」页搬进了「隐私与关于」，而脚本还在原地滚；
仓库里那张 `11b-body-revoke.png` 还是**搬之前**拍的 ——
张数、尺寸、夹带全对，`tool/check-screenshots.mjs` 一个字都不会说。**空跑一遍当场就能看见。**

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
              --target=integration_test/screenshots_test.dart -d <设备 id> \
              --dart-define=LIANLEME_BACKUP_URL=https://api.elliotli.work \
              --dart-define=LIANLEME_BACKUP_DISCLOSED=true \
              --dart-define=LIANLEME_ANALYTICS_URL=https://api.elliotli.work/v1/events
```

> ⚠️ **2026-10-06 起：截图要带上面那三个 dart-define**（＝正式包那个变体）。
> 起因很实际：**正式包从 v1.43.0 起就配了服务器地址**，于是「数据与备份」里
> 有「云备份」与「账号」两行；而不带 define 跑出来的图**这两行是没有的** ——
> 那等于拿一个用户装不到的形态去当商店素材。以前没写这一条，是因为那时候
> 正式包真的没配地址（变体 A），现在是变体 B 了。
> ⚠️ 顺带说明：**「账号」那一页本身还不在三套图里**（脚本里没有那一步）——
> 要加就得给 `screenshots_test.dart` 加一步，并且三套的**张数与文档、守卫一起改**。
**`-d` 一定要给**：接了两台设备时（例如真机 + 模拟器），不指定就是薛定谔的截图。
本仓库的做法与踩过的坑见 `docs/dev-environment.md`「安卓模拟器」一节（
`emulator-5554` 就是在那台无头模拟器上跑的，**不需要解锁真机**）。

产物写进 `store-assets/screenshots/`（**入库**：它是交付物，不是 `dist/` 那种构建产物）。

> ⚠️ **2026-10-06（v1.54.0）三套又重出过一遍** —— 起因是「全部数据」页的维度切换改成了明面上的分段控件（**安卓也变**），iOS 那套还多了液态玻璃。此前 **2026-10-05（v1.53.0）** 重出过一次，起因是用户拍板"**商店首图换成引导页那张**"：
> 脚本在跳过轮播之前先截下它（`00-intro`），三套图都在**干净安装**那一跑重出
> （安卓两套走模拟器、App Store 走 iOS 模拟器 + 压平），张数 15/14/14 → **16/15/15**。
> 踩到的两件事记在这里，免得下次重新踩：①**安卓模拟器跑久了会僵**（黑屏、App 渲染不出来 →
> `flutter drive` 卡在 `request_data`、日志里一步都看不到）→ `adb emu kill` 重启，40 秒就能再跑；
> ②`flutter drive` 产出的 `app-debug.apk` 是**测试入口**的包（装上去它会自己跑测试）——
> 要手工验证界面必须另跑 `flutter build apk --debug` 再装。
>
> ⚠️ **2026-10-05（v1.52 收尾）也曾重出过一遍**，那次是被"新屏没人重拍"逼出来的：
> v1.48–v1.52 加了五个新屏/新状态，而脚本只在 v1.46/v1.47 时跑通过 —— 于是这次重跑
> **15 步全红**（`01-home` 起就找不到控件）。根因两条，都值得记住：
>   1. **v1.49 的引导页轮播**在同意门之后，脚本没处理它 → 后面每一步都停在那一屏；
>   2. 身体数据页（v1.52）**多了一个横向 chips 的 ListView**，`find.byType(ListView)`
>      变成"找到 2 个"，`dragUntilVisible` 当场抛错 → 页内补了 `body-scroll` 这个 key。
> 另外顺手修了脚本自己的一个坑：**失败现场图**原先在成功截图之前必定抛
> `Call convertFlutterSurfaceToImage()` —— 最需要看图的时候偏偏没有图，已把"转换 surface"
> 挪到所有截图路径前面。
> ⚠️ **三套图这次都重出了**（安卓两套 1080×2400 / 1080×1920 走模拟器两跑，App Store 那套
> 走 iOS 模拟器 `lianleme-69` + `flatten-png.mjs`）；`11-body-metric` 的**内容**也换了：
> 脚本先真的记两天身体数据，图里才有摘要卡 / BMI / 趋势卡。
>
> ⚠️ **2026-10-09（v1.65.0）只重出了 App Store 那一套**（`lianleme-69` 模拟器 + `flatten-png.mjs`，
> 15 张齐、8 位无 alpha）。**安卓两套不用重出** —— 这一版新加的「从系统健康同步」那张卡
> **只在 iPhone 上出现**（`defaultTargetPlatform` 判断，安卓那一端还没接 Health Connect），
> 所以安卓两套图与 v1.54.0 那批**逐像素一致**，没有任何理由重拍。
> 顺带说明：`11-body-metric` 拍的是**滚动之后**的视角（摘要卡 / 更多指标 / 备注 / 趋势 / 最近记录），
> 新的那张同步卡在列表顶部，所以这一版它没进画面 —— 不是漏拍。
>
> ⚠️ **2026-10-07（v1.60.0）又重出了一次三套**：这一版动了**外壳本身** ——
> 顶栏（标题 + 右上角齿轮/铃铛）与底栏（顺序改成 进步/数据/**训练**/计划/我的，
> 正中那颗凸起圆）**每一张图里都在**，首页也不再自带标题与铃铛。
> 所以三套图全都过期，必须重出（`check-screenshots` 只核张数与尺寸，核不出内容过期）。
> ⚠️ 顺带修了脚本一步：`10b-data-tools` 原先从「我」页点入口，而设置三组搬进了
> **独立的设置页** —— 脚本改成"先点顶栏齿轮、再进数据与备份"。
> ⚠️ 这一趟还从图里逮到一个真 bug：顶栏的日期被省略号截断（"10 月 8 日 · …"）——
> 原因是标题那一段与 `Spacer` 抢自由空间，改成 `Expanded` 之后才拿满宽度。
> **图比测试更早发现它**，所以"重出截图"不只是走流程。
>
> ⚠️ **上一次是 2026-10-05 在 v1.46.0 上重出**（新 VI 的五个 Tab 与四屏重做之后）。
> 触发原因是**换 VI**（旧图还是 volt 绿那一版，与现在的界面不是同一个 App）。
> ⚠️ 同一次重出还撞见一个真问题：`screenshots_test` 等三个 integration test 还在点
> `Key('tab-我')`，而 Tab 已经改名成「我的」—— 它们会**静默失败到「找不到控件」**。
> 判据是那一行 `LIANLEME-SHOT-SUMMARY`：`失败 0 步` 才算过（失败现场会留 `zz-fail-*.png`，
> 那是失败现场图，**不许当交付物留着**）。

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
# 15 张图 → 过一遍压平（16 位 RGBA → 8 位 RGB）→ 入库
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
（`docs/images/legacy-5tab/launcher-icon-verified.png` —— volt 圆底 + 墨色「练」、名称「练了么」，
这是自适应图标第一次被**眼睛**验证，而不是只比字节）。

> ⚠️ **图标换过两次**：v1.44.0 是「深底 + 白『练』+ volt 哑铃」，**v1.45 起是用户给的橙色圆环**。上面那张图是**第一次换图标之前**拍的。
> 新的那张是 `docs/images/legacy-5tab/launcher-icon-verified-v1440.png`（2026-10-05，模拟器应用抽屉里
> 截的，1080 宽原图，能同时看到图标与中文名）。重拍真机那张之前，别把旧图当成现在的样子看。
>
> ⚠️ **换图标之后踩到的一个坑，记下来**：装完新版，启动器**照样显示旧图标** —— 那是
> **launcher 自己的图标缓存**，不是包里的图标（包里已是新的：`aapt2 dump xmltree` 看到
> 自适应 XML 三层齐全、`app/android/app/src/main/res/values/ic_launcher_colors.xml` 是 `#ff1a1a1a`）。
> 清掉缓存才看得到真的：`adb shell pm clear <launcher 包名>`（Pixel 上是
> `com.google.android.apps.nexuslauncher`；清完桌面会重排，图标去应用抽屉里找）。
> **判别方法**：如果图标"看起来像"新旧两张叠在一起，先怀疑缓存，别急着改资源。

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

**13 屏（含引导页那一屏）+ 一道同意门 + 一条撤回入口 + 一张整屏的"全新安装空态"，共 16 张**
（主体是 **2026-10-01 在 v1.34.0 上用真机重出**的那套，1080×2400 ——
尺寸与"齐不齐、有没有夹带"由 `tool/check-screenshots.mjs` 每次进门禁核对。
重出的原因：「我」页重排后身体数据 / 导出 / 导入的入口挪进了「数据与备份」，
商店图必须与 App 一致；顺手多截了 `10b-data-tools` 那一屏）：

| 文件 | 屏 |
|---|---|
| `00-intro.png` | **引导页轮播第一屏**（"一次点击 记录一组"）—— **2026-10-05 起当商店列表首图**（用户拍板：第一张要回答"我能得到什么"）。⚠️ 只在**干净安装**那一跑拍得到 |
| `01-home.png` | 首页（**全新安装**的样子；这一跑没有历史数据） |
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
| `11-body-metric.png` | 身体数据 —— **同意之后**的样子。**2026-10-05（v1.52）这一张改过内容**：脚本会先真的记两天（今天 + 昨天，含腰围 / 肌肉量 / 身高），所以图里有**摘要卡 + BMI + 趋势卡**；单位仍是 **kg / lb / 斤 实时切换**（2026-10-01 起三个单位，默认跟随训练单位）|
| `11a-body-consent.png` | 身体数据前面的**敏感信息单独同意**（PIPL 第 29 条）——见下面那条"图比 App 旧"的坑 |
| `11b-body-revoke.png` | 同一页最下面的**「撤回我的同意」**（PIPL 第 15 条的撤回权，v1.32.0 起）——滚到底才看得见 |
| `docs/images/legacy-5tab/launcher-icon-verified.png` | 启动器图标与名字（不算商店素材，是验证证据） |


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
- **App Store 那套（`store-assets/screenshots-ios/`）是 15 张**：上面那 13 屏 + 同意门 +
  撤回入口，尺寸 1320×2868，来源是 iPhone 17 Pro Max 模拟器（**2026-10-06 在 v1.54.0 上重出**：
  干净安装那一跑，15 张 / 0 步失败。此前那次是 2026-10-01 在 v1.34.0 上：14 张，第一次跑中途
  有 6 步连败、**重跑一次全绿** —— 那是模拟器/App 状态的一次性问题，不是脚本坏了），
  **出完图立刻压平**（16 位 RGBA → 8 位 RGB）。它没有 `01b` —— 模拟器那一跑本身就是全新安装
  （空态首页就是 `01-home`）。

商店通常逐张接收、不要求尺寸一致；Play 那套现在也是 15 张（同样带同意门与撤回入口），
挑 8 张上传就行（首图用 `00-intro`，见 `docs/store-listing.md` §六）。

`integration_test/screenshots_test.dart` 里每一步都单独包了 try：一步失败不会
丢掉前面截好的图，而且会**自动截一张 `zz-fail-<步骤名>` 的现场图**
（第一次跑时 9 步连败却不知道停在哪一屏，才加的这条）。

### 布局 bug 的真机证据（v1.42.2 / v1.42.3）

同一个 bug（胶囊被撑成通栏）在仓库里有**三份拷贝**，两次修完都在真机上拍了对照 ——
这类"本该一行、结果占满屏"的问题，单测能量出宽度，但**只有真机图能让人一眼信**：

| 图 | 证的是什么 | 修之前的样子 |
| --- | --- | --- |
| `docs/images/legacy-5tab/v142-prefs-compact-and-hint.png` | 偏好设置：休息时长 **2 行紧凑胶囊** + 「下次提醒」那行提示（v1.42.2） | 6 个选项各占一整行 |
| `docs/images/legacy-5tab/v143-prefs-rest-one-row.png` | 偏好设置：休息时长收成**一整行**（`90 秒 ›`；副标题只在「跟随动作」这种真看不懂的情况下才出现），页面上一个选项胶囊都没有（v1.42.3） | 上一条那 2 行 |
| `docs/images/legacy-5tab/v143-routine-item-chips.png` | 计划编辑：**组数 1–6 一行**、次数区间两行（v1.42.3） | 7 个组数胶囊各占一整行 |
| `docs/images/legacy-5tab/v143-custom-chips.png` | 新建自定义动作：部位一行、器械两行（v1.42.3） | 6 个部位胶囊各占一整行 |

（都是 Redmi `flourite` 上 `adb exec-out screencap` 抓的整屏，1280×2772。）

### 文案审计的真机证据（v1.42.4）

删文案这种改动**测试断言不了"读起来是否清爽"**（能断言的只是"那句子没了"），
所以三个受影响的页面各拍一张 —— 判据见 `docs/copy.md`：

| 图 | 看到的样子 |
| --- | --- |
| `docs/images/legacy-5tab/v144-prefs-copy-trimmed.png` | 偏好设置：休息时长只剩 `90 秒 ›`；提醒开关打开时**没有副标题**，时间与「下次提醒」两行照旧 |
| `docs/images/legacy-5tab/v145-data-tools-no-subtitle.png` | 数据与备份：五行保留副标题（「不可撤销」「不能导回来」这些一个字没动），**「导出备份文件」一行没有** —— 这是刻意的例外（v1.42.5） |
| `docs/images/legacy-5tab/v144-privacy-copy.png` | 隐私与关于：统计开关那行删掉「默认关闭。」；三个入口**没有副标题**（原来那三句都是复述标题） |

## 给商店/软著用的注意

- 商店通常要求 **3–8 张**，且**必须来自真实 App** —— 这批就是。
  `prototype/index.html` 是设计原型，**不能充数**。
- 软著说明书的界面图，每屏配一句说明即可（提纲见 `store-listing.md` 第七节）。
- 截图里有真实训练数据（"上次 4 组全部达标，线性加重 +2kg"）—— 这比空态好看，
  但也别截图里出现个人信息（当前没有：App 不要求注册）。
