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
# ⚠️ **依赖全部装在 SSD 上的「harness 依赖」目录**（2026-09-30 起，为了给内置盘腾空间）。
#    那个目录名里**有空格**，所以下面每一处引用都必须加引号 —— 这点和仓库路径里的
#    撇号是同一类坑（本项目的 `~/HARNESS/lianleme` 跑道就是因为撇号才存在的）。
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

echo "✓ Flutter/Android 环境已就绪（依赖在 SSD）"
echo "    flutter  → $(command -v flutter)"
echo "    java     → $(command -v java)"
echo "    adb      → $(command -v adb)"
echo "    node     → $(command -v node 2>/dev/null || echo '（没找到：契约层会失败）')"
