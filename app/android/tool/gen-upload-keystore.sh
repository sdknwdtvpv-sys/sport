#!/usr/bin/env bash
#
# 练了么 · 生成 Android 发布签名（upload keystore）
#
# 用法：
#     cd app/android && ./tool/gen-upload-keystore.sh
#
# 为什么需要它：
#   仓库里 release 构建默认回落到 debug 签名，而**所有商店都拒收 debug 签名的包**。
#   上传 Google Play 后必须始终用同一个 key 签名后续版本 —— 因此这个 keystore
#   一旦生成就要妥善备份，丢了就无法再更新已发布的应用（除非用 Play App Signing 走恢复流程）。
#
# 安全约定：
#   * 本脚本**不会**把密码写进任何日志，也不会回显
#   * keystore 与 key.properties 都已被 app/android/.gitignore 忽略，不进仓库
#   * 密码请存进密码管理器。**丢了就找不回来。**

set -euo pipefail

cd "$(dirname "$0")/.."   # → app/android

# ── keytool 从哪来（2026-10-05 真踩，改了取法）──────────────────────────────
#
# ⚠️ **macOS 自带一个 `/usr/bin/keytool` 占位程序**：它不在 PATH 里找不到真 JDK 时，
# 只会打印一句 `The operation couldn't be completed. Unable to locate a Java Runtime.`
# 并且**退出码 1**。而上一版脚本的取法是 `command -v keytool` 优先 —— 于是它挑中了这个
# 占位程序，症状是"问完密码、打印完那行中文之后突然说找不到 Java"。
#
# 现在的取法：**先问仓库自己的环境脚本**（JDK/SDK 位置的真源，env 搬过家：jdk-17 从
# `~/development` 搬到了 SSD 的 `harness-deps`，任何硬编码路径都会过期），
# 然后逐个候选**试跑 `-help` 验真**，挑第一个真能跑的。
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
if [ -f "$REPO_ROOT/tool/dev-env.sh" ]; then
  # shellcheck disable=SC1090
  . "$REPO_ROOT/tool/dev-env.sh" >/dev/null 2>&1 || true
fi

KT_CANDIDATES=()
[ -n "${JAVA_HOME:-}" ] && KT_CANDIDATES+=("$JAVA_HOME/bin/keytool")
KT_CANDIDATES+=("/Volumes/Elliot's SSD/harness-deps/jdk-17/Contents/Home/bin/keytool")
KT_CANDIDATES+=("$HOME/development/jdk-17/bin/keytool")
KT_CANDIDATES+=("$(command -v keytool 2>/dev/null || true)")

KEYTOOL=""
for c in "${KT_CANDIDATES[@]}"; do
  [ -n "$c" ] || continue
  [ -x "$c" ] || continue
  # ★ 验真：占位程序 `-help` 退出码是 1，真 JDK 是 0
  if "$c" -help >/dev/null 2>&1; then KEYTOOL="$c"; break; fi
done

if [ -z "$KEYTOOL" ]; then
  echo "✗ 找不到**能用的** keytool（不是找不到文件，是找到的都是 macOS 的占位程序）。" >&2
  echo "  这台机器上的 JDK 在 SSD 的 harness-deps 里。先跑这一句再重试：" >&2
  echo "      source \"$REPO_ROOT/tool/dev-env.sh\"" >&2
  echo "  或者手动指过去：" >&2
  echo "      export JAVA_HOME=\"/Volumes/Elliot's SSD/harness-deps/jdk-17/Contents/Home\"" >&2
  exit 1
fi
echo "keytool：$KEYTOOL"

KEYSTORE="upload-keystore.p12"
PROPS="key.properties"
ALIAS="upload"

echo "练了么 · 发布签名生成"
echo "目录：$(pwd)"
echo

if [ -f "$KEYSTORE" ] || [ -f "$PROPS" ]; then
  echo "✗ 已存在 $KEYSTORE 或 $PROPS —— 不覆盖。"
  echo "  换新签名会让已发布的应用无法更新；确实要重做请先手动备份并删除它们。"
  exit 1
fi

read -r -p "签名主体 CN（你的名字或组织，如 sdknwdtvpv）: " CN
[ -n "$CN" ] || { echo "✗ CN 不能为空"; exit 1; }
read -r -p "组织 O（可留空回车跳过）: " ORG
read -r -p "国家代码 C（两位，如 CN）[CN]: " COUNTRY
COUNTRY="${COUNTRY:-CN}"

DNAME="CN=${CN}"
[ -n "$ORG" ] && DNAME="${DNAME}, O=${ORG}"
DNAME="${DNAME}, C=${COUNTRY}"

echo
echo "keystore 密码（至少 6 位，输入时不回显）："
read -r -s -p "  密码: " STORE_PASS; echo
read -r -s -p "  再输一次: " STORE_PASS2; echo
[ "$STORE_PASS" = "$STORE_PASS2" ] || { echo "✗ 两次不一致"; exit 1; }
[ "${#STORE_PASS}" -ge 6 ] || { echo "✗ 至少 6 位"; exit 1; }

# key 密码直接复用 store 密码 —— 分开设容易记混，收益很小。
KEY_PASS="$STORE_PASS"

echo
echo "→ 生成 ${KEYSTORE}（RSA 2048，有效期 10000 天，PKCS12 格式）"
"$KEYTOOL" -genkeypair \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storetype PKCS12 \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "$DNAME"

echo "→ 写 $PROPS"
cat > "$PROPS" <<EOF
# 由 tool/gen-upload-keystore.sh 生成 —— 不进仓库（见 .gitignore）。
# 密码请同时存进密码管理器：丢了就无法再更新已发布的应用。
storePassword=${STORE_PASS}
keyPassword=${KEY_PASS}
keyAlias=${ALIAS}
storeFile=$(pwd)/${KEYSTORE}
EOF
chmod 600 "$PROPS" "$KEYSTORE"

echo
echo "✓ 完成"
echo "    keystore : $(pwd)/$KEYSTORE"
echo "    properties: $(pwd)/$PROPS  (权限 600)"
echo
echo "验证签名者（应显示你刚才填的 CN，而不是 Android Debug）："
"$KEYTOOL" -list -v -keystore "$KEYSTORE" -storepass "$STORE_PASS" 2>/dev/null \
  | grep -E "所有者|Owner|别名|Alias" | sed 's/^/    /'
echo
echo "接着跑：cd .. && flutter build appbundle --release"
