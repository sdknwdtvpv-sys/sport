# 开发环境：依赖全部装在 SSD 上（2026-09-30 起）

## 一句话

**所有第三方依赖（SDK、JDK、缓存）都放在 `/Volumes/Elliot's SSD/harness-deps/`**，
不再占内置盘。内置盘因此空出约 **14G**（38G → 52G）。

一条命令把环境准备好：

```bash
source tool/dev-env.sh          # 仓库里的正本
source ~/HARNESS/lianleme/flutter-env.sh   # 跑道上的副本（内容相同）
```

> **正本在仓库里**（`tool/dev-env.sh`），跑道那份是副本 —— 副本存在的理由和
> `~/HARNESS/lianleme` 这条跑道一样：构建要在**没有撇号**的路径下做。
> 改路径时改正本，然后 `cp tool/dev-env.sh ~/HARNESS/lianleme/flutter-env.sh`。
> （原先这个脚本只活在跑道里、不在版本控制内 —— 机器一换就丢了。）

## 目录里有什么

| 目录 | 是什么 | 大约 |
|---|---|---|
| `harness-deps/flutter` | Flutter SDK（含 dart-sdk） | 3.9G |
| `harness-deps/jdk-17` | JDK 17（`JAVA_HOME` 指到 `Contents/Home`） | 309M |
| `harness-deps/android-sdk` | Android SDK（platform-tools / build-tools / platforms / cmdline-tools） | 3.5G |
| `harness-deps/gradle` | Gradle 用户目录（`GRADLE_USER_HOME`：依赖与构建缓存） | 4.8G |
| `harness-deps/pub-cache` | Dart 包缓存（`PUB_CACHE`） | 848M |

环境脚本导出的变量：`FLUTTER_ROOT` / `JAVA_HOME` / `ANDROID_SDK_ROOT`（= `ANDROID_HOME`）
/ `GRADLE_USER_HOME` / `PUB_CACHE` / `PATH`。

## Node 的版本要求（两个门槛，别混）

| 用途 | 最低版本 | 为什么 |
|---|---|---|
| 契约层（seed 构建 / 向量 / 场景 eval / 各 tool） | **18+** | `verify.sh` 会检查这一条 |
| `server/backend*.mjs` 与 `app/test/cloud_backup_test.dart` | **22.5+** | 服务端用 **`node:sqlite`**，那是 Node 22.5 才有的内置模块 |

第二个门槛容易漏：`app/test/cloud_backup_test.dart` 会**真的把服务端拉起来**跑云备份的
端到端，所以**跑 flutter test 的那台机器也得有够新的 Node**。
CI 的 `app` job 一开始就漏了（只给契约层装了 Node）—— 现在两个 job 都钉 `node-version: '22'`。
测试里也加了前置检查：Node 不够新会**直接说清原因**，而不是让服务端起不来、
再以"端口等待超时"的样子报出来。

## ⚠️ 目录名必须是 ASCII —— 这是踩过的坑，不是洁癖

你最初要的名字是「harness 依赖」。它**直接把 Android 构建弄坏了**：

```
Included build '/Volumes/Elliot's SSD/harness ä¾èµ/flutter/packages/flutter_tools/gradle' does not exist.
```

`依赖` 变成了乱码。原因是 **Java 的 `.properties` 按 ISO-8859-1 解码**，而
`app/android/local.properties` 里的 `flutter.sdk` 是 Flutter 用 UTF-8 写进去的中文路径 ——
Gradle 读出来就是乱码，于是"找不到 Flutter 的 gradle 插件"。
（同一个坑的另一种形态：仓库所在卷名里的**撇号**逼出了 `~/HARNESS/lianleme` 这条干净跑道。）

**所以这个目录叫 `harness-deps`：纯 ASCII、没有空格。改名前先想清楚这两条。**

## ⚠️ 还有一份"影子配置"：`flutter config`（搬完家最容易漏的东西）

`source tool/dev-env.sh` 只设了环境变量。**Flutter 自己还有一份持久配置**
（`~/.config/flutter/settings`），里面的 `jdk-dir` / `android-sdk`
**优先级高于 `JAVA_HOME` / `ANDROID_SDK_ROOT`**。

搬去 SSD 时旧路径留在了里面，后果是 2026-09-30 真实发生的这一幕：

```
ERROR: JAVA_HOME is set to an invalid directory: /Users/elliot.li/development/jdk-17
```

那个目录**已经不存在了**（JDK 搬去了 SSD），于是 release 构建直接失败 ——
而**六层门禁全绿**，因为 `verify.sh` 一行 Gradle 都不跑。
CHANGELOG 里那句"从新位置成功构建了 release APK"就是这么过期的：
它当时是真的，后来旧 JDK 被删掉，就再没人重新构建过。

现在有两道保险：

| 在哪 | 做什么 |
|---|---|
| `verify.sh` 前置探测 | 读 `~/.config/flutter/settings`，发现指向**不存在的目录**就**判红**（不是测试失败，是打包的硬前提坏了） |
| `tool/dev-env.sh` | 与 `$JAVA_HOME` / `$ANDROID_SDK_ROOT` 不一致时，自动 `flutter config` 对齐到 SSD（正常情况一次 flutter 调用都不会发生） |

手工修：

```bash
flutter config --jdk-dir="$JAVA_HOME" --android-sdk="$ANDROID_SDK_ROOT"
```

> **教训**：搬依赖不是 `mv` 一下就完了。任何**自己记着绝对路径**的工具
> （`flutter config`、`local.properties`、`~/.android`、IDE 的 SDK 设置）
> 都要跟着改。判据很简单：**做一次 release 构建**，别只看门禁绿不绿。

## ⚠️ `flutter drive` 跑完会把 App **卸载掉**（2026-10-01 栽的跟头）

**症状**：截图脚本（或任何 `flutter drive` / `integration_test`）跑完，
**手机上的 App 就没了** —— 桌面图标消失、`pm list packages` 里查不到。
下一次有人拿起手机想看，会以为"根本没装过"。

**原因**：`flutter drive` 结束时会把测试安装的 App **卸载**（它自己装、自己清）。
所以"装真机 → 跑截图脚本 → 交付"这个顺序是错的：脚本会把刚装好的正式包一起带走。

**规矩**（写进 `docs/release-checklist.md` 的真机那一行）：

> **任何一次在真机上跑 `flutter drive` 之后，都必须重新 `adb install -r` 一份
> `dist/` 里的正式 APK**，再核对 `versionName` / `versionCode`。

**2026-10-01 又踩了一次（这次是自己造的）**：`flutter test` 也会重新生成那个文件。
当时的顺序是「删掉 registrant → 后台起 release 构建 → 顺手跑几条 `flutter test` 数测试条数」，
于是测试**在构建期间**把坏文件写了回去，Gradle 正好编译到它 —— 构建红，
而错误信息指向的还是两天前那件事。

> **并列规矩**：**构建期间不要跑 `flutter test`**。要数测试条数就先数完，再构建；
> 或者构建完再数。两条规矩合起来才够 —— 只记"跑过 integration_test 之后要删"是不够的。

**顺带**：`flutter drive` 不会还原 `wm size` —— 截完图记得 `adb shell wm size reset`，
否则手机会停在 1080×1920 之类的截图分辨率上（截屏、看界面都会觉得"怎么变扭了"）。

## ⚠️ 在 MIUI 上跑 `flutter drive`：**安装被拦** + **锁屏就跑不了**（2026-10-04 栽的跟头）

**症状**：`flutter drive` 在"Installing app-debug.apk"这一步失败三次然后退出：

```
adb: failed to install .../app-debug.apk:
  Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]
Application failed to start on attempt: 3
```

**原因**：MIUI 对**每一次 adb 安装**都弹一个「USB 安装提示 — 是否继续？」对话框，
9 秒没人点就自动拒绝。`flutter install -r`（覆盖安装）通常不弹，但
**卸载之后的全新安装**、以及 `flutter drive` 自己那次安装**会弹** ——
于是"手动跑得通、脚本跑不通"。

**绕法**（本次用的）：装之前在后台起一个"盯框就点"的循环 —— 轮询
`uiautomator dump`，看到「继续安装」就按 dump 里的 `bounds` 点它的中心。
脚本 `/tmp/tap-install.sh`（一次性工具，没入库；逻辑见下）与安装命令**并行**跑：

```bash
(adb -s <设备> install -r dist/练了么-vX.Y.Z.apk >/tmp/inst.log 2>&1 &)
# 另一个终端：轮询 uiautomator dump，点「继续安装」
```

⚠️ **两个更隐蔽的前提**（这次各栽了一次）：

1. **屏幕不能锁**。锁屏时既点不到对话框，`uiautomator dump` 还会因为动画报错 ——
   而 `flutter drive` 失败信息里只会说"安装被用户拒绝"，**看不出是锁屏造成的**。
   跑之前先 `adb shell dumpsys power | grep mWakefulness=`（要 `Awake`）
   并确认 `dumpsys window | grep mCurrentFocus` 不是 `NotificationShade`（锁屏/下拉栏）。
2. **别用手写坐标点对话框**。它的 y 位置随屏幕高度变（本次见过 1673 / 2082 / 2525 三个值），
   硬编码必然点空 —— 而"点空了"的表现与"没点"一模一样。按 `bounds` 算中心点。

## ⚠️ 跑完 integration_test 之后，release 构建会残一个坏文件（2026-10-01 记）

**症状**：`flutter build apk --release` 直接红，报

```
GeneratedPluginRegistrant.java:24: 错误: 程序包dev.flutter.plugins.integration_test不存在
```

**原因**：`app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
是 Flutter 生成的（**不在 git 里**）。`integration_test` 是 dev 依赖，但它的插件也会被写进
`.flutter-plugins-dependencies`；一旦上一次跑的是 `flutter drive`（截图 / 云备份端到端那几条），
生成出来的注册文件里就带着 `IntegrationTestPlugin` —— 而 release 构建里没有这个包。

**修法**（一秒，不用 `flutter clean`）：

```bash
rm -f app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
# 下一次 build 会重新生成正确的版本
```

**为什么会忘**：这个文件是生成物、又是"本地痕迹"，出问题的地方（Java 编译）离原因
（两天前跑过截图脚本）很远。**记在这里的判断是**：先删了重编，不要花时间去查 Gradle。

## ⚠️ 卷名里的空格会**假装**弄坏 AAB 构建（其实是误报）

`flutter build appbundle --release` 在这台机器上**必然**打印这句：

```
Release app bundle failed to strip debug symbols from native libraries.
```

**而 .aab 其实已经正常产出了。** 真因要在 `-v` 日志里才看得到：

```
executing: [.../android-sdk/cmdline-tools/latest/bin/apkanalyzer files list ...app-release.aab
apkanalyzer: line 173: test: : integer expression expected
错误: 找不到或无法加载主类 SSD.harness-deps.android-sdk.cmdline-tools.latest
原因: java.lang.ClassNotFoundException: SSD.harness-deps.android-sdk.cmdline-tools.latest
```

`apkanalyzer` 是个 shell 脚本，它把自己的位置拼进 classpath 时**没加引号**；
卷名 `Elliot's SSD` 里的空格把它劈成两段，Java 就把 `SSD.harness-deps…` 当成了类名。
flutter_tools 拿不到输出 → 认定"没剥掉调试符号" → 报失败。**产物本身没问题。**

* `.apk`（旁加载用）**不受影响** —— 它不走 apkanalyzer 那一步。
* `.aab`（商店用）也用 `node tool/check-aab.mjs` 核，别信 flutter 那句话。
  它检查骨架三件套、三个 ABI 的原生库、以及版本号是否与 `app_info.dart` 一致。
* 想让命令真的退出 0：SDK 必须放在**没有空格**的路径上。
  而这块 SSD 的**卷名**里就有空格 —— 所以任何放在它上面的 SDK 路径都带空格。

### ✅ 首选做法（方案 C，用户 2026-10-05 拍板）：把同一个卷**另外**挂到一个没有空格的挂载点

真源不动（还是 `/Volumes/Elliot's SSD`，数据一个字节都不搬），只是让工具链换一条
**路径里没有空格**的入口进去：

```bash
sudo tool/mount-ssd-space-free.sh        # 挂载（幂等；已挂好就直接过）
tool/mount-ssd-space-free.sh --check     # 只读检查，**不需要 sudo**
sudo tool/mount-ssd-space-free.sh --unmount   # 卸掉别名挂载点
sudo tool/mount-ssd-space-free.sh --fstab     # 打印重启后仍然生效的那一行
```

脚本头顶写着为什么需要它（AAB 误报 / `privacy-audit --apk` 空转 / `sdkmanager` 报错，
三次受害者）、真值从哪来、以及**哪一步没验证过**。

**这一步为什么不能"顺便"做掉**：一个 APFS 卷同一时刻只能挂在一个地方。所以顺序必然
是"先从 `/Volumes/Elliot's SSD` 卸下来 → 再挂到 `~/HARNESS/ssd`"，而不是"多挂一个"。

**本机验证到哪一步**（写这段的人和跑这个脚本的人不是同一个时间点，所以分开写）：

| 环节 | 状态 | 证据 |
|---|---|---|
| 卷的身份（UUID / 设备节点 / 文件系统） | ✅ 验证过 | `diskutil info -plist "/Volumes/Elliot's SSD"`：`VolumeUUID=C25E83A4-B93C-404E-8726-953F7DE08BD5`、`DeviceIdentifier=disk7s1`、`FilesystemType=apfs`、`APFSContainerReference=disk7`（物理载体 `disk6s2`） |
| `diskutil mount` 支不支持自定义挂载点 | ✅ 验证过 | `diskutil mount` 的用法行：`[-mountPoint Path] DiskIdentifier\|DeviceNode` |
| `/etc/fstab` 会不会被认 | ✅ 查了手册 | `man diskarbitrationd`："/etc/fstab is consulted for user-defined mount points, indexed by filesystem"；`man fstab` 的 EXAMPLES 里是 `UUID=… <挂载点> apfs rw`，并且明说 **APFS 卷别写块设备节点** |
| **一个卷同一时刻只能挂一处**（所以必须先卸再挂） | ✅ 验证过 | 卷挂在 `/Volumes/Elliot's SSD` 时，`/sbin/mount_apfs /dev/disk7s1 <别的目录>` → **rc=75**，`volume could not be mounted: Operation already in progress` |
| **"卸下来 → 换到自定义挂载点挂上"这个动作本身** | ✅ 验证过 | 用一个临时 APFS 镜像（**不需要 root**）做的对照实验：`diskutil unmount /Volumes/probevol` → `diskutil mount -mountPoint /tmp/probe-mnt-nospace <UUID>` → 挂载表里真的出现 `on /private/tmp/probe-mnt-nospace`。**所以方案 C 的机制成立**；实验后镜像已卸载删除 |
| **挂载点那条路径里有软链时，挂载表记的是物理路径** | ✅ 验证过 | 挂载点用软链 `/tmp/probe-link`（指向真实目录）时，挂载表记成 `/private/tmp/probe-real-dir` —— 照字面 grep 会**找不到**，把"挂好了"误报成"没挂上"。脚本因此同时认你给的路径和它的物理路径（默认挂载点 `~/HARNESS/ssd` 的物理路径就是它本身，已核过） |
| **`diskutil mount` 的"成功"是假的** | ✅ 验证过 | 卷已挂载时 `diskutil mount -mountPoint <空目录> <UUID>` → 退 **0**、打印 `Volume Elliot's SSD on C25E… mounted`，而挂载表里**根本没有**那个目录。所以脚本一律**以挂载表为准**，不看它的输出和退出码 |
| 在**这块真 SSD** 上卸下再挂上 | ❌ **没验证** | 这台机器 `sudo -n true` 返回 **126 Operation not permitted**（没有挂载权限）；而且这个卷现在正被跑着的仓库、编辑器、终端占着，`diskutil unmount` 会被 `dissented by PID …` 顶回来 —— 不能拿正在用的真源盘试（上面那条对照实验是**另一块临时镜像**，不是它） |
| `--fstab` 持久化 | ❌ **没验证** | 同上（`/etc/fstab` 要 root 写）。**另有一个没验证的风险**：生效之后卷会不会**只**挂在指定挂载点、`/Volumes/Elliot's SSD` 就此消失 —— 那样硬编码真源的 `tool/dev-env.sh`、`verify.sh`、`tool/workbench.mjs`、`tool/asset-check.mjs` 会一起红。所以先只做挂载，fstab 另说 |
| 挂上之后工具链是不是真的好了 | ❌ **没验证** | 缺的就是这个卷尺：挂好后要真跑一次 `flutter build appbundle --release`，看那句误报在不在、退出码是不是 0 |

**用户跑完请回报两件事**（缺了就没法判断这条到底成没成）：
1. `tool/mount-ssd-space-free.sh --check` 的完整输出；
2. `cd app && flutter build appbundle --release` 的退出码，以及还打不打印
   `Release app bundle failed to strip debug symbols from native libraries.`

### 挂不了 / 没权限时用这几条（**备选**，都是真跑过的记录，不是纸上的选项）

1. 在这块 SSD 上再建一个**名字没有空格的 APFS 卷**（同一个容器，空间共享），SDK 放那里 ——
   等于把"多一个挂载点"换成"多一个卷"，一个卷一处挂载，因此没有上面的卸载问题；
2. 把 Android SDK 放回内置盘（约 3.5G，用掉刚腾出来的一部分空间）；
3. 接受现状：APK 照常构建，AAB 用 `node tool/check-aab.mjs` 核产物（CI 里也能出 AAB）；
4. 继续用绕法：`sdkmanager` / `avdmanager` 直接调 Java 类（**四条命令在下文
   「`sdkmanager` / `avdmanager` 在这台机器上是坏的」那一节**，每条都真跑过）。

> **符号链接不算一条路**（试过了）：`apkanalyzer` 自己会 `cd` 进去再取 `pwd -P`，
> 物理路径里的空格照样露出来。新挂载点是**真挂载**，不是软链 —— 这正是它和软链的区别。

> 这一条和"依赖装在 SSD"是**真的冲突**，不是配置没调好：Android 的工具链对空格路径
> 本来就不支持（`flutter doctor` 也会为此报一条 `[!]`）。

## iOS 模拟器（2026-09-30 装好）—— App Store 截图就靠它

Xcode 的许可证接受之后，还要单独下**模拟器运行时**（Xcode 26+ 起不再随 Xcode 附带）：

```bash
xcodebuild -downloadPlatform iOS     # 约 8G，不需要 sudo，进度写在自己的日志里
xcrun simctl list runtimes           # 装好后能看到 iOS 27.0（24A434）
```

装机实测（2026-09-30）：**iOS 27.0 runtime + iPhone 17 Pro Max 设备**，
`flutter drive … -d <模拟器 UDID>` 出图 **12 张 / 0 步失败 / 1320×2868**。
两个只有真跑才会知道的事：

* iOS 模拟器截出来的 PNG 是 **16 位 RGBA**（同一份脚本在安卓上是 8 位 RGBA），
  App Store 只收 **8 位无 alpha** → 出图后过 `node tool/flatten-png.mjs`；
* 磁盘：运行时解包后系统盘会少掉约 10G（下载 8G + 解包），装之前先看一眼 `df -h /`。

## 安卓模拟器（2026-09-30 装好）—— 以及那个空格坑的第三个受害者

**为什么装它**：真机（Redmi `flourite`）长期锁屏、拿不到解锁凭据，于是
"界面到底长什么样""截图是不是当前版本"这两件事一直卡着。
模拟器没有锁屏，能跑 `integration_test` 出图、能 `screencap` 看屏、也能当云备份端到端的设备
（宿主机后端在模拟器里是 `10.0.2.2`）。**它不能替代真机验收**，但能让"看不见"变成"看得见"。

装的东西（都在 SSD 上）：

| 项 | 位置 | 大小 |
|---|---|---|
| emulator | `harness-deps/android-sdk/emulator` | 1.1G |
| 系统镜像 | `harness-deps/android-sdk/system-images/android-36/google_apis/arm64-v8a` | 4.3G |
| AVD | `harness-deps/avd/lianleme_api36.avd`（`ANDROID_AVD_HOME` 指过去） | 数 G（用到才长） |

```bash
export ANDROID_AVD_HOME="/Volumes/Elliot's SSD/harness-deps/avd"
export ANDROID_EMULATOR_HOME="/Volumes/Elliot's SSD/harness-deps/emulator-home"
"$ANDROID_SDK_ROOT/emulator/emulator" -avd lianleme_api36 \
    -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect -no-snapshot &
# 约 40 秒后：adb -s emulator-5554 shell getprop sys.boot_completed → 1
```

### ⚠️ `sdkmanager` / `avdmanager` 在这台机器上是坏的 —— 卷名里的空格，第三个受害者

```
$ sdkmanager --list
.../sdkmanager: line 173: test: : integer expression expected
错误: 找不到或无法加载主类 SSD.harness-deps.android-sdk.cmdline-tools.latest
```

和 AAB 那次（`apkanalyzer`）、和 `privacy-audit --apk` 那次是**同一个根因**：
这两个都是 shell 脚本，把自己的位置拼进 classpath 时**没加引号**，
而卷名 `Elliot's SSD` 里的空格把它劈开了。

**首选做法**：把卷另外挂到一个没有空格的挂载点 —— 见本文
「✅ 首选做法（方案 C…）」那一节，一条命令是 `sudo tool/mount-ssd-space-free.sh`。
挂上之后 `sdkmanager --list` 应当**直接能跑**，下面这段绕法就不用再抄了。

**下面这段是备选（挂不了 / 没权限时用），也是真跑过的记录** ——
原理是**直接调 Java 类**，把脚本本该设的属性自己设上。
（符号链接**绕不过去**：脚本会 `cd` 进去再取 `pwd -P`，把物理路径里的空格解析回来，试过了。）

```bash
SDK="/Volumes/Elliot's SSD/harness-deps/android-sdk"; CT="$SDK/cmdline-tools/latest"
# 列表 / 安装
"$JAVA_HOME/bin/java" -cp "$(ls $CT/lib/*.jar | tr '\n' ':')" \
  com.android.sdklib.tool.sdkmanager.SdkManagerCli --sdk_root="$SDK" --list
yes | "$JAVA_HOME/bin/java" -cp "$(ls $CT/lib/*.jar | tr '\n' ':')" \
  com.android.sdklib.tool.sdkmanager.SdkManagerCli --sdk_root="$SDK" \
  "emulator" "system-images;android-36;google_apis;arm64-v8a"
# 建 AVD（注意这个多一个 toolsdir 属性，缺了会报 "tools directory property is not set"）
"$JAVA_HOME/bin/java" -Dcom.android.sdkmanager.toolsdir="$CT" \
  -classpath "$CT/lib/avdmanager-classpath.jar" com.android.sdklib.tool.AvdManagerCli \
  create avd -n lianleme_api36 -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_6
```

**根因还是那条**：Android 工具链不支持带空格的 SDK 路径，而这块 SSD 的卷名带空格。
首选是**方案 C**：把卷另外挂到没有空格的挂载点（`sudo tool/mount-ssd-space-free.sh`，
要动磁盘布局，所以是你来跑；哪一步在本机验证过、哪一步没有，都写在上文那张表里）。
挂不了或没权限时，退到本文那几条备选：SSD 上再建一个名字没有空格的 APFS 卷 /
把 SDK 放回内置盘 / 继续用上面这些绕法。

## 没搬的东西，以及为什么

| 没搬 | 为什么 |
|---|---|
| `~/.workbuddy/binaries/node`（707M） | 它是 **harness 自带的运行时**，harness 按这个路径找它；搬到 SSD 既不省空间（那份还得留着），又多一个要同步维护的运行时。环境脚本已把它的 bin 加进 `PATH`（契约层需要 Node 18+） |
| `~/.android`（3.6M） | 里面是**调试签名密钥**。换位置可能让 debug 签名变化，导致 `adb install -r` 覆盖安装失败 —— 3.6M 不值得冒这个险 |

## SSD 是外置盘：后果要清楚

依赖在外置盘上，意味着**SSD 没插上就什么都构建不了**。不过这不是新风险——
**项目本身就在这块盘上**（`/Volumes/Elliot's SSD/HARNESS/lianleme`），没插上连代码都没有。
环境脚本会**明确报错**而不是让人看一堆莫名其妙的工具报错：

```
✗ 找不到依赖目录：/Volumes/Elliot's SSD/harness-deps
  SSD 没挂载？本项目的依赖都在那块盘上，插上再 source 这个文件。
```

## iOS 环境（2026-10-01 现状：**都装好了**）

这台机器上 iOS 这一套**已经可用**：Xcode 27.0（`/Applications/Xcode.app`）、
`xcode-select` 指过去、**许可证已接受**、模拟器运行时 iOS 27.0 已装。
能做的事都做过了：`flutter build ios --release --no-codesign`（20.8MB / arm64）、
模拟器出图（`store-assets/screenshots-ios/` 14 张）、云备份端到端。

**规矩（照这个来，别把 Xcode 搬走）**：

- **Xcode 本体必须装在 `/Applications`**（macOS 的要求，搬不走）
- 但 **DerivedData / Archives / 模拟器**都可以重定向到 SSD：
  `xcodebuild -derivedDataPath`、模拟器设备在 `~/Library/Developer/CoreSimulator`
  （可用软链指到 SSD）
- CocoaPods 的缓存同理（`~/.cocoapods` 可搬）—— **不过本工程走 SPM，没有 Podfile**，
  所以这条只是备用
- **真机测试**（免费 Apple ID / 7 天签名 / 怎么装）见 `docs/ios-free-provisioning-guide.md`

## ⚠️ Xcode 许可证被拒时怎么办（**2026-09-30 已解决**，留作排错）

> 现状：许可证**已经接受**了，这一节不是待办，是"万一哪台新机器/重装后又遇到"的排错记录。

装了 Xcode 之后，`xcode-select` 会指向 `/Applications/Xcode.app`。**在许可证被接受之前**，
`xcrun` 拒绝服务，于是这些东西**一起挂**：

| 命令 | 为什么也挂 |
|---|---|
| `xcodebuild` / `clang` | 直接要许可证 |
| `git` | macOS 的 `/usr/bin/git` 是 xcrun 的壳 |
| `python3` | 同上，`/usr/bin/python3` 也是壳 |
| `flutter` / `dart` | 包装脚本会探测 Xcode；`flutter test` 的原生资源构建还要问 Apple SDK 路径 |

**正式解法只有一条**（需要 sudo 密码，所以只能你来）：

```bash
sudo xcodebuild -license accept        # 装完第一次可顺手：sudo xcodebuild -runFirstLaunch
```

**在等这一步期间**，本机可以继续跑门禁与测试 —— 做法是**绕开 Xcode、改用 Command Line
Tools**（等价于 `sudo xcode-select --switch /Library/Developer/CommandLineTools`，
但不需要 sudo）：

```bash
mkdir -p /tmp/fixbin
printf '#!/bin/sh\nDEVELOPER_DIR=/Library/Developer/CommandLineTools exec /usr/bin/xcrun "$@"\n' > /tmp/fixbin/xcrun
printf '#!/bin/sh\nDEVELOPER_DIR=/Library/Developer/CommandLineTools exec /usr/bin/python3 "$@"\n' > /tmp/fixbin/python3
printf '#!/bin/sh\nexec /Applications/Xcode.app/Contents/Developer/usr/bin/git "$@"\n' > /tmp/fixbin/git
FL="/Volumes/Elliot's SSD/harness-deps/flutter"
printf '#!/bin/sh\nexport DEVELOPER_DIR=/Library/Developer/CommandLineTools\nexec %s %s "$@"\n' \
  "$FL/bin/cache/dart-sdk/bin/dart" "$FL/bin/cache/flutter_tools.snapshot" > /tmp/fixbin/flutter
printf '#!/bin/sh\nexec %s "$@"\n' "$FL/bin/cache/dart-sdk/bin/dart" > /tmp/fixbin/dart
chmod +x /tmp/fixbin/* && export PATH=/tmp/fixbin:$PATH
```

⚠️ 这只让**测试/门禁/安卓构建**继续能跑，**iOS 构建仍然要正式的许可证**
（`xcrun --sdk iphonesimulator` 拿不到 SDK）。也不是"破解"许可证 ——
只是不用 Xcode、用 CLT 那套（Xcode 装之前本来就是这么跑的）。

> 注意 `flutter doctor` 在这个状态下会报 "Xcode installation is incomplete" ——
> 那是它透过 CLT 看 Xcode，属于预期，不是新的故障。
