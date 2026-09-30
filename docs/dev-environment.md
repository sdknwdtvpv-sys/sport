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
