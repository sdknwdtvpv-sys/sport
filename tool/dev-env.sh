#!/usr/bin/env bash
#
# 练了么 · Flutter / Android / JDK 环境变量（**仓库里的正本**）
#
# 用法：
#     source tool/dev-env.sh
#
# 跑道上那份 `~/HARNESS/lianleme/flutter-env.sh` 是它的副本 —— 之所以有副本，
# 是因为构建要在没有撇号的路径下做（见 verify.sh 文件头的说明）。
# **改这一份，然后同步过去**：
#     cp tool/dev-env.sh ~/HARNESS/lianleme/flutter-env.sh
#
# 约定与踩过的坑见 docs/dev-environment.md。
#
# 用法（在你自己的终端里）：
#     source ~/HARNESS/lianleme/flutter-env.sh
#
# ⚠️ **依赖全部装在 SSD 上的 `harness-deps` 目录**（2026-09-30 起，为给内置盘腾空间）。
#    引用它的路径都要加引号 —— 卷名 `Elliot's SSD` 里有个**撇号**，和仓库跑道
#    `~/HARNESS/lianleme` 存在的原因是同一类坑。
#
#    目录名**必须是纯 ASCII**，这不是洁癖：最初叫「harness 依赖」，Android 构建直接失败
#    （`Included build '/Volumes/Elliot's SSD/harness ä¾èµ/flutter/…' does not exist.`）——
#    Java 的 `.properties` 按 ISO-8859-1 解码，而 `local.properties` 里的 `flutter.sdk`
#    是 Flutter 用 UTF-8 写的中文路径。详见 docs/dev-environment.md。
#
# 装了什么（约 13G）：
#     flutter/      Flutter SDK          ~3.9G
#     jdk-17/       JDK 17（JAVA_HOME 指到 Contents/Home）
#     android-sdk/  Android SDK（platform-tools / build-tools / platforms / cmdline-tools）
#     gradle/       Gradle 用户目录（GRADLE_USER_HOME，依赖与构建缓存 ~4.8G）
#     pub-cache/    Dart 包缓存（PUB_CACHE ~850M）
#
# 没搬的：`~/.android`（只有 3.6M，但里面是**调试签名密钥**；
# 换位置可能让 debug 签名变化，导致 `adb install -r` 覆盖安装失败，不值得冒这个险）。

DEPS="/Volumes/Elliot's SSD/harness-deps"

if [ ! -d "$DEPS" ]; then
  echo "✗ 找不到依赖目录：$DEPS"
  echo "  SSD 没挂载？本项目的依赖都在那块盘上，插上再 source 这个文件。"
  # 被 source 时用 return，被直接执行时用 exit
  return 1 2>/dev/null || exit 1
fi

export FLUTTER_ROOT="$DEPS/flutter"
export JAVA_HOME="$DEPS/jdk-17/Contents/Home"
export ANDROID_SDK_ROOT="$DEPS/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export GRADLE_USER_HOME="$DEPS/gradle"
export PUB_CACHE="$DEPS/pub-cache"

# Node：契约层（seed 构建 / 向量 / 场景 eval / 各 tool）需要 Node 18+。
# ⚠️ **它不搬去 SSD**，这是有意的例外：这个 Node 是 harness 自带的运行时
# （`~/.workbuddy/binaries/node`，707M），harness 自己要按这个路径找它；
# 搬到 SSD 既不省空间（那份还得留着），又会多出一个要同步维护的运行时。
NODE_BIN="$HOME/.workbuddy/binaries/node/versions/current/bin"
[ -d "$NODE_BIN" ] || NODE_BIN="$HOME/.workbuddy/binaries/node/versions/22.22.2-3/bin"

export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$NODE_BIN:$PATH"

# pub 走镜像：pub.dev 实测约 40KB/s，不换源 pub get 会慢到超时
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# ── 顺手把 flutter 的**持久配置**对齐（2026-09-30 踩出来的） ──────────────────
# `~/.config/flutter/settings` 里的 `jdk-dir` / `android-sdk` **优先级高于上面这些环境变量**。
# 搬去 SSD 时旧路径留在了里面（jdk-dir 指向已删除的 `~/development/jdk-17`），后果是：
#     release 构建报 "JAVA_HOME is set to an invalid directory"，
#     而**六层门禁全绿** —— verify.sh 一行 Gradle 都不跑。
# 所以：真的不一致才动它（正常情况下一次 flutter 调用都不会发生）。
FLUTTER_SETTINGS="$HOME/.config/flutter/settings"
if [ -f "$FLUTTER_SETTINGS" ] && command -v flutter >/dev/null 2>&1; then
  FLUTTER_TOOLCHAIN="$(node -e '
    try {
      const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      process.stdout.write([s["jdk-dir"] || "", s["android-sdk"] || ""].join("|"));
    } catch (e) {}
  ' "$FLUTTER_SETTINGS" 2>/dev/null)"
  if [ "$FLUTTER_TOOLCHAIN" != "$JAVA_HOME|$ANDROID_SDK_ROOT" ]; then
    flutter config --jdk-dir="$JAVA_HOME" --android-sdk="$ANDROID_SDK_ROOT" >/dev/null 2>&1
    echo "    （flutter 的持久配置原本指向别处，已对齐到 SSD）"
  fi
fi

echo "✓ Flutter/Android 环境已就绪（依赖在 SSD）"
echo "    flutter  → $(command -v flutter)"
echo "    java     → $(command -v java)"
echo "    adb      → $(command -v adb)"
echo "    node     → $(command -v node 2>/dev/null || echo '（没找到：契约层会失败）')"
