#!/usr/bin/env bash
# 练了么 · 一键自检
#
# 用法：
#   ./verify.sh          # 全部五层
#   ./verify.sh --fast   # 跳过 Flutter widget 测试（日常迭代用）
#
# 分层（按"需要什么"切）：
#   契约层（Node）            —— 动作库种子 + JS 规则引擎向量
#   领域层（纯 Dart，零依赖）  —— Dart 引擎 vs 同一份 vectors.json + tap_count 边界
#   静态分析（Dart）          —— 需要 package_config.json（跑过一次 pub get）
#   应用层（Flutter）         —— widget 测试（需要 pub get 成功）
#
# 两个刻意的选择：
#   * 领域层零依赖：pub get 要清临时目录并访问 pub.dev，受限环境会失败；
#     而领域层是纯 Dart 的，用 SDK 自带的 dart 就能验证 —— 最关键的结论
#     （Dart 与 JS 引擎行为一致）因此不依赖网络也能被证实。
#   * 静态分析用 `dart analyze --fatal-infos` 而不是 `flutter analyze`：
#     Flutter 3.47 的 flutter analyze 在**非 ASCII 路径**下必崩
#     （flutter/flutter#191309），本仓库目录名是中文。两者读同一套
#     analysis_options.yaml，dart analyze 不经过 flutter_tools 的 LSP 客户端，因此不受影响。
#
# 环境导致的无法执行会标记为"阻塞"而非"通过"，且不计入失败：
# 环境坏掉和测试失败是两件事。CI 里各层都是硬门槛。

set -uo pipefail
cd "$(dirname "$0")"
REPO="$PWD"

FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
fail=0
blocked=0
LOG=/tmp/lianleme-verify.log
strip() { grep -vE 'UNDICI|trace-warnings' "$1" 2>/dev/null; }

# macOS 没有 timeout；用后台进程 + 看门狗实现可移植版本
with_timeout() {
  local secs="$1"; shift
  "$@" & local cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null ) 2>/dev/null & local w_pid=$!
  wait "$cmd_pid"; local rc=$?
  kill -TERM "$w_pid" 2>/dev/null; wait "$w_pid" 2>/dev/null
  return $rc
}

echo "${BOLD}练了么 · 自检${OFF}"
echo "${DIM}目录：$REPO${OFF}"
echo

# ── 前置探测 ────────────────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || { echo "${RED}✗ 找不到 node。契约层需要 Node 18+。${OFF}"; exit 1; }
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -lt 18 ] && { echo "${RED}✗ Node 版本过低（$(node -v)），需要 18+。${OFF}"; exit 1; }
echo "${GREEN}✓${OFF} Node $(node -v)"

FLUTTER_BIN="$(command -v flutter 2>/dev/null || true)"
[ -z "$FLUTTER_BIN" ] && [ -x "$HOME/development/flutter/bin/flutter" ] && FLUTTER_BIN="$HOME/development/flutter/bin/flutter"

DART_BIN="$(command -v dart 2>/dev/null || true)"
if [ -z "$DART_BIN" ] && [ -n "$FLUTTER_BIN" ]; then
  CAND="$(dirname "$FLUTTER_BIN")/cache/dart-sdk/bin/dart"; [ -x "$CAND" ] && DART_BIN="$CAND"
fi
[ -z "$DART_BIN" ] && [ -x "$HOME/development/flutter/bin/cache/dart-sdk/bin/dart" ] && \
  DART_BIN="$HOME/development/flutter/bin/cache/dart-sdk/bin/dart"

[ -n "$FLUTTER_BIN" ] && echo "${GREEN}✓${OFF} Flutter → $FLUTTER_BIN" || echo "${YELLOW}!${OFF} 未找到 Flutter"
[ -n "$DART_BIN" ] && echo "${GREEN}✓${OFF} Dart    → $DART_BIN" || echo "${YELLOW}!${OFF} 未找到 Dart"
echo

# ── 1. 动作库 ───────────────────────────────────────────────────────────
echo "${BOLD}[1/5] 动作库种子构建与校验${OFF}"
if node seed/build.mjs >"$LOG" 2>&1; then
  strip "$LOG" | head -5; echo "${GREEN}✓${OFF} 动作库通过"
else
  strip "$LOG"; echo "${RED}✗ 动作库校验失败${OFF}"; fail=1
fi
echo

# ── 2. JS 引擎 ─────────────────────────────────────────────────────────
echo "${BOLD}[2/5] JS 规则引擎测试向量${OFF}"
node engine/run-tests.mjs >"$LOG" 2>&1; rc=$?
strip "$LOG" | tail -14
[ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} JS 引擎通过" || { echo "${RED}✗ JS 引擎失败（退出码 $rc）${OFF}"; fail=1; }
echo

# ── 3. Dart 领域层（零依赖） ────────────────────────────────────────────
echo "${BOLD}[3/5] Dart 引擎 vs 同一份 vectors.json（零依赖）${OFF}"
if [ -z "$DART_BIN" ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 未找到 Dart SDK。"; blocked=1
else
  "$DART_BIN" app/tool/check_domain.dart >"$LOG" 2>&1; rc=$?
  strip "$LOG" | tail -18
  [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} Dart 领域层通过" || { echo "${RED}✗ Dart 领域层失败（退出码 $rc）${OFF}"; fail=1; }
fi
echo

# ── 4. 静态分析 ─────────────────────────────────────────────────────────
echo "${BOLD}[4/5] 静态分析（dart analyze --fatal-infos）${OFF}"
if [ -z "$DART_BIN" ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 未找到 Dart SDK。"; blocked=1
elif [ ! -f app/.dart_tool/package_config.json ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 尚无 app/.dart_tool/package_config.json，需先成功跑过一次 pub get。"; blocked=1
else
  (cd app && "$DART_BIN" analyze --fatal-infos >"$LOG" 2>&1); rc=$?
  strip "$LOG" | tail -30
  [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 静态分析零问题" || { echo "${RED}✗ 静态分析有问题（退出码 $rc）${OFF}"; fail=1; }
fi
echo

# ── 5. Flutter 应用层 ──────────────────────────────────────────────────
echo "${BOLD}[5/5] Flutter widget 测试${OFF}"
if [ "$FAST" -eq 1 ]; then
  echo "${DIM}⊘ 已按 --fast 跳过。完整校验请去掉该参数。${OFF}"
elif [ -z "$FLUTTER_BIN" ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 未安装 Flutter SDK。"; blocked=1
else
  PUBLOG=/tmp/lianleme-pubget.log
  if ! with_timeout 240 bash -c "cd '$REPO/app' && PUB_CACHE='$REPO/.pub-cache' '$FLUTTER_BIN' pub get" >"$PUBLOG" 2>&1; then
    echo "${YELLOW}⊘ 阻塞${OFF} —— flutter pub get 未成功：属环境问题，不是测试失败。"
    strip "$PUBLOG" | tail -5 | sed 's/^/    /'
    blocked=1
  else
    with_timeout 420 bash -c "cd '$REPO/app' && PUB_CACHE='$REPO/.pub-cache' '$FLUTTER_BIN' test --reporter compact" >"$LOG" 2>&1; rc=$?
    strip "$LOG" | tail -25
    [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 应用层通过" || { echo "${RED}✗ 应用层测试失败（退出码 $rc）${OFF}"; fail=1; }
  fi
fi
echo

# ── 产物完整性 ──────────────────────────────────────────────────────────
echo "${BOLD}[附] 产物完整性${OFF}"
missing=0
for f in README.md PRODUCT.md ROADMAP.md \
         docs/tech-decisions.md docs/data-model.md docs/screens.md \
         docs/interaction-spec.md docs/usability-test.md docs/usability-test-kit.md \
         docs/analytics.md docs/analytics-sdk.md \
         prototype/index.html \
         seed/build.mjs seed/exercises.json seed/exercises.sql \
         engine/progression.mjs engine/vectors.json engine/run-tests.mjs \
         app/pubspec.yaml app/lib/main.dart \
         app/lib/domain/progression.dart app/lib/domain/tap_meter.dart \
         app/lib/features/workout/workout_controller.dart \
         app/tool/check_domain.dart \
         app/test/progression_vectors_test.dart app/test/tap_meter_test.dart \
         app/test/workout_flow_test.dart \
         .github/workflows/ci.yml; do
  [ -f "$f" ] && printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$f" || { printf '  %s✗ 缺失%s %s\n' "$RED" "$OFF" "$f"; missing=1; }
done
[ "$missing" -eq 0 ] || fail=1
echo

if [ "$fail" -eq 0 ]; then
  echo "${GREEN}${BOLD}未发现失败。${OFF}"
  [ "$blocked" -eq 1 ] && echo "${YELLOW}但有步骤被环境阻塞，未完成验证。${OFF}"
  echo "${DIM}下一步：open prototype/index.html 看原型；或读 docs/usability-test-kit.md 去招人做测试。${OFF}"
else
  echo "${RED}${BOLD}有检查未通过，见上方输出。${OFF}"
fi
exit "$fail"
