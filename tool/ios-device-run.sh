#!/usr/bin/env bash
#
# 练了么 · 把 App 装到**你自己的 iPhone** 上（免费 Apple ID / Personal Team）
#
# 为什么需要一条脚本，而不是照文档敲三条命令：
#   1. 免费档要求 bundle id **全局唯一**，所以真机测试必须临时换一个 dev id；
#      而换 id 会让 `tool/check-ios-app.mjs` 判红（它要求"产物里的 id == Info.plist ==
#      安卓 applicationId"三处一致）—— 本脚本把那次改动**圈起来**，跑完自动改回去；
#   2. Team ID 也一样：它属于某个 Apple ID，不该写进仓库。脚本从 Xcode 已登录的账号里
#      读出来、临时写进工程，跑完撤回 —— 所以**你不需要在 Xcode 里点 Signing & Capabilities**；
#   3. 免费签名 **7 天到期**，每 7 天要重来一次 —— 这套动作值得是一条命令。
#
# 用法：
#   LIANLEME_DEVICE="<设备 UDID 或名字>" tool/ios-device-run.sh
#   LIANLEME_DEV_BUNDLE_ID=com.yourname.lianleme.dev LIANLEME_TEAM_ID=XXXXXXXXXX … tool/ios-device-run.sh
#   LIANLEME_KEEP_PATCH=1 …   # 保留工程改动（接着要跑真机上的测试时用；跑完自己 git checkout 回来）
#   LIANLEME_DART_DEFINES='A=1 B=2' …   # 编译期常量（空格分隔）。**装"接了后端"的包必须给** ——
#                                       # 不给的话 iOS 上还是旧行为（云备份入口都不出现）；
#                                       # 给了之后 `flutter build ios --config-only` 会把它们写进
#                                       # `ios/Flutter/Generated.xcconfig` 的 DART_DEFINES，Xcode 构建阶段读它。
#
# 前置（只有你能做）：
#   * Xcode → Settings（⌘,）→ Accounts 里登录你的 Apple ID（免费即可）—— 脚本从这里读 Team；
#   * iPhone 插线 + 在手机上「信任此电脑」+ 打开「开发者模式」
#     （设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启 → 解锁输密码）。
#
# ✅ **2026-10-04 在 iPhone 17 Pro（iOS 27.2）上完整跑通过**：BUILD SUCCEEDED → 装上设备 →
#    拉起成功 → 工程自动改回。实测结论（含那个必须两个都传的 provisioning 开关）记在
#    docs/ios-free-provisioning-guide.md 第六节。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$REPO/app/ios/Runner.xcodeproj/project.pbxproj"
BAK="$(mktemp -t lianleme-pbxproj)"
DEV_ID="${LIANLEME_DEV_BUNDLE_ID:-com.sdknwdtvpv.lianleme.dev}"
DEVICE="${LIANLEME_DEVICE:-}"
KEEP="${LIANLEME_KEEP_PATCH:-}"
# 编译期常量（三个 dart-define）。⚠️ macOS 自带 bash 3.2，`set -u` 下**展开空数组会报
# "unbound variable"** —— 所以下面用的是 `${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"}` 这种写法。
DEFINES="${LIANLEME_DART_DEFINES:-}"
DEFINE_ARGS=()
for _kv in $DEFINES; do DEFINE_ARGS+=("--dart-define=$_kv"); done
[ ${#DEFINE_ARGS[@]} -eq 0 ] || echo "→ 编译期常量 ${#DEFINE_ARGS[@]} 个：$DEFINES"

red() { printf '\033[31m%s\033[0m\n' "$1"; }
ok()  { printf '\033[32m%s\033[0m\n' "$1"; }

# ── 中途失败也要把工程改回去（否则门禁会在你不知情时判红）────────────────────
restore() {
  if [ -f "$BAK" ]; then
    cp "$BAK" "$PBX"
    rm -f "$BAK"
    if [ -n "$KEEP" ]; then
      red "⚠️ 按 LIANLEME_KEEP_PATCH 保留了工程改动（dev bundle id + Team）。"
      echo "   用完请恢复：git -C \"$REPO\" checkout -- app/ios/Runner.xcodeproj/project.pbxproj"
    else
      echo "↩︎ 已把 iOS 工程改回原来的 bundle id 与 Team 设置"
    fi
  fi
}
trap restore EXIT

if grep -q "lianleme\.dev" "$PBX"; then
  red "✗ 工程里已经是 dev bundle id —— 上一次跑可能没跑完。先恢复："
  echo "    git -C \"$REPO\" checkout -- app/ios/Runner.xcodeproj/project.pbxproj"
  exit 1
fi

[ -n "$DEVICE" ] || { red "✗ 没给设备。用法：LIANLEME_DEVICE=\"<UDID 或名字>\" $0"; exit 1; }

echo "→ 当前连着的设备（要装的那台应该在列表里，且不是 unpaired）："
xcrun devicectl list devices 2>/dev/null | sed -n '1,8p'

# ── Team ID：优先环境变量，其次从 Xcode 已登录的账号里读（免费档优先）──────────
TEAM_ID="${LIANLEME_TEAM_ID:-}"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(defaults export com.apple.dt.Xcode - 2>/dev/null | python3 -c '
import plistlib, sys
try:
    d = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit(0)
# 结构是 {账户 UUID: [ {teamID, teamName, isFreeProvisioningTeam, ...}, ... ]}，
# 所以要把值里那层 list 摊平（第一版按 dict 取，直接 AttributeError）。
teams = (d.get("IDEProvisioningTeamByIdentifier") or {})
flat = []
for v in teams.values():
    flat.extend(v if isinstance(v, list) else [v])
free = [t.get("teamID") for t in flat if isinstance(t, dict) and t.get("isFreeProvisioningTeam")]
allt = [t.get("teamID") for t in flat if isinstance(t, dict)]
print(((free or allt or [""])[0]) or "")
' || true)"
fi
if [ -z "$TEAM_ID" ]; then
  red "✗ 没找到可用的 Team —— 先在 Xcode → Settings（⌘,）→ Accounts 里登录你的 Apple ID（免费即可）"
  echo "    也可以显式指定：LIANLEME_TEAM_ID=XXXXXXXXXX $0"
  exit 1
fi
echo "→ 用 Team $TEAM_ID"

echo "→ 临时把 bundle id 换成 ${DEV_ID}（主 App 与扩展一起）、并写入 Team"
cp "$PBX" "$BAK"
python3 - "$PBX" "$DEV_ID" "$TEAM_ID" <<'PY'
import sys

path, dev, team = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8').read()

# 扩展的 id 必须挂在主 App 之下（check-ios-app.mjs 第 ⑪ 条也这么要求）
s = s.replace('PRODUCT_BUNDLE_IDENTIFIER = com.sdknwdtvpv.lianleme.RestWidget;',
              f'PRODUCT_BUNDLE_IDENTIFIER = {dev}.RestWidget;')
s = s.replace('PRODUCT_BUNDLE_IDENTIFIER = com.sdknwdtvpv.lianleme;',
              f'PRODUCT_BUNDLE_IDENTIFIER = {dev};')

# 只给"我们这个 App 的 6 份配置"加签名设置：主 App 3 份 + 扩展 3 份。
# RunnerTests 不参与 `flutter build ios`，不动它（免得动到不必要的地方）。
for ident in (f'{dev}.RestWidget;', f'{dev};'):
    s = s.replace(
        f'PRODUCT_BUNDLE_IDENTIFIER = {ident}\n',
        f'PRODUCT_BUNDLE_IDENTIFIER = {ident}\n'
        f'\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
        f'\t\t\t\tDEVELOPMENT_TEAM = {team};\n',
    )
open(path, 'w', encoding='utf-8').write(s)
PY

echo "→ 编 + 签（release；自动签名，Xcode 会自动建描述文件）"
#
# ⚠️ **这里必须用 `xcodebuild` 而不是 `flutter build ios`**（2026-10-04 实测出来的）：
# 免费档第一次要把**这台设备**注册到 Apple 那边才会发描述文件，而负责这件事的开关是
# `-allowProvisioningDeviceRegistration` —— Flutter 只传了 `-allowProvisioningUpdates`，
# 于是报 "Your team has no devices from which to generate a provisioning profile"。
# 两个都传之后，第一次构建会自动注册设备 + 建 App ID + 建描述文件。
DD="$REPO/app/build/ios-dd"

# ⚠️ **必须先让 Flutter 重写一遍 `ios/Flutter/Generated.xcconfig`**（2026-10-04 踩的）：
# 那份文件里缓存着 `FLUTTER_ROOT`，而它在「跑道副本」里会**跟着 rsync 一起被覆盖**成
# 主仓库里的旧值（这台机器上旧值指向一个早就搬走的 `~/development/flutter`）。
# 症状是构建中途报 `.../xcode_backend.sh: No such file or directory`，
# 看起来像工程坏了，其实只是那句 FLUTTER_ROOT 过期。`--config-only` 一秒就重写它。
( cd "$REPO/app" && flutter build ios --config-only --release ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"} >/dev/null )
if [ -n "${LIANLEME_USE_FLUTTER_BUILD:-}" ]; then
  ( cd "$REPO/app" && flutter build ios --release ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"} )
  APP_PATH="$REPO/app/build/ios/iphoneos/Runner.app"
else
  ( cd "$REPO/app/ios" && xcodebuild \
      -workspace Runner.xcworkspace \
      -scheme Runner \
      -configuration Release \
      -destination "id=$DEVICE" \
      -allowProvisioningUpdates \
      -allowProvisioningDeviceRegistration \
      -derivedDataPath "$DD" \
      build )
  APP_PATH="$DD/Build/Products/Release-iphoneos/Runner.app"
fi
[ -d "$APP_PATH" ] || { red "✗ 没找到产物：$APP_PATH"; exit 1; }
echo "→ 产物：$APP_PATH"

echo "→ 装到设备"
xcrun devicectl device install app --device "$DEVICE" "$APP_PATH"

echo "→ 拉起（锁屏看 Live Activity 就直接按电源键）"
xcrun devicectl device process launch --device "$DEVICE" "$DEV_ID" || true

ok "✓ 装好了。这个包 7 天后会打不开 —— 再跑一次本脚本即可。"
echo "   验「组间休息」：App 里点大按钮记一组 → 按电源键锁屏 → 应看到倒计时与「下一组 …」"
echo "   验「训练提醒」：我 → 偏好设置 → 训练提醒（开关）→ 会弹系统授权 → 时间设成 2 分钟后 → 锁屏等"
if [ -z "$KEEP" ]; then
  echo "   （工程改动会在本脚本退出时自动撤回；跑完请确认 ./verify.sh 是绿的）"
fi
