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
  三条路（**都需要你定**，我不擅自改磁盘布局或搬回内置盘）：
  1. 在这块 SSD 上再建一个**名字没有空格的 APFS 卷**（同一个容器，空间共享），SDK 放那里；
  2. 把 Android SDK 放回内置盘（约 3.5G，用掉刚腾出来的一部分空间）；
  3. 接受现状：APK 照常构建，AAB 用 `check-aab.mjs` 核产物（CI 里也能出 AAB）。

> 这一条和"依赖装在 SSD"是**真的冲突**，不是配置没调好：Android 的工具链对空格路径
> 本来就不支持（`flutter doctor` 也会为此报一条 `[!]`）。

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
而卷名 `Elliot's SSD` 里的空格把它劈开了。**符号链接绕不过去**（脚本会把真实路径解析回来，
试过了）。绕法是**直接调 Java 类**，把脚本本该设的属性自己设上：

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
想彻底解决只有三条路（**都需要你定**，见 `docs/release-checklist.md` 的"待处理"）：
SSD 上再建一个名字没有空格的 APFS 卷 / 把 SDK 放回内置盘 / 继续用这些绕法。

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

## iOS 的规矩（等装 Xcode 时照这个来）

这台机器**现在没有 Xcode**（只有 Command Line Tools），所以 iOS 目前一行都跑不了。
真要上 iOS 时：

- **Xcode 本体必须装在 `/Applications`**（macOS 的要求，搬不走）
- 但它的 **DerivedData / Archives / 模拟器**都可以重定向到 SSD：
  `xcode-select` 之后用 `xcodebuild -derivedDataPath`、模拟器设备放在
  `~/Library/Developer/CoreSimulator`（可用软链指到 SSD）
- CocoaPods 的缓存同理（`~/.cocoapods` 可搬，装好后按同一原则处理）

## Xcode 装了但许可证没接受时怎么办（2026-09-30 记）

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
