#!/usr/bin/env bash
# 练了么 · 一键自检
#
# 用法：
#   ./verify.sh          # 全部五层
#   ./verify.sh --fast   # 跳过 Flutter widget 测试（日常迭代用）
#
# 分层（按"需要什么"切）：
#   契约层（Node）            —— 动作库种子 + JS 规则引擎向量 + 场景 eval
#   领域层（纯 Dart，零依赖）  —— Dart 引擎 vs 同一份 vectors.json + tap_count 边界
#   静态分析（Dart）          —— 需要 package_config.json（跑过一次 pub get）
#   应用层（Flutter）         —— widget 测试（需要 pub get 成功）
#   变异测试（Node + Dart）    —— **唯一一层验证"测试本身有没有用"**：
#                              把源码改坏，看上面的测试红不红（存活 = 盲区）
#
# 两个刻意的选择：
#   * 领域层零依赖：pub get 要清临时目录并访问 pub.dev，受限环境会失败；
#     而领域层是纯 Dart 的，用 SDK 自带的 dart 就能验证 —— 最关键的结论
#     （Dart 与 JS 引擎行为一致）因此不依赖网络也能被证实。
#   * 静态分析用 `dart analyze --fatal-infos` 而不是 `flutter analyze`：
#     Flutter 3.47 的 flutter analyze 在**非 ASCII 路径**下必崩
#     （flutter/flutter#191309），本仓库目录名是中文。两者读同一套
#     analysis_options.yaml，dart analyze 不经过 flutter_tools 的 LSP 客户端，因此不受影响。
#   * 应用层会先检查仓库路径有没有单引号：flutter test 生成 listener.dart 时把
#     测试文件路径塞进 `Uri.parse('file:///…')`，路径里的撇号会提前截断字符串，
#     测试连加载都失败（+0 -14）。这跟上面那条同源，但路径看着全是 ASCII，
#     只有一个标点，很难往那儿想。符号链接绕不过去 —— flutter 读的是 pwd -P
#     的物理路径。这种情况标记为"阻塞"，不误报成测试失败。
#
# 环境导致的无法执行会标记为"阻塞"而非"通过"，且不计入失败：
# 环境坏掉和测试失败是两件事。CI 里各层都是硬门槛。

set -uo pipefail
cd "$(dirname "$0")"
REPO="$PWD"

FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

# 路径含单引号会让 flutter test 必崩（见文件头说明）。提前判定，好在应用层给出
# 准确原因，而不是让它以"测试失败"的面目出现。
case "$REPO" in
  *"'"*) APOSTROPHE_PATH=1 ;;
  *)     APOSTROPHE_PATH=0 ;;
esac

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
echo "${BOLD}[1/6] 动作库种子构建与校验${OFF}"
if node seed/build.mjs >"$LOG" 2>&1; then
  strip "$LOG" | head -5; echo "${GREEN}✓${OFF} 动作库通过"
else
  strip "$LOG"; echo "${RED}✗ 动作库校验失败${OFF}"; fail=1
fi
# docs/exercise-mapping.md 是从种子 + 上游快照生成的：种子一改它就过期。
# 让它大声报错，比留一份"看起来还对"的映射表安全。
if node tool/map-upstream.mjs --check >"$LOG" 2>&1; then
  echo "${GREEN}✓${OFF} 上游映射表与种子一致"
else
  strip "$LOG"; echo "${RED}✗ 上游映射表过期${OFF}"; fail=1
fi
# seed/parts/04-from-upstream.json 同理：它是从上游快照 + 中文名表生成的。
# 这一层同时守住"排除规则没有被绕过"（改规则不同步重生成就会红）。
if node tool/add-upstream-exercises.mjs --check >"$LOG" 2>&1; then
  echo "${GREEN}✓${OFF} 上游补库文件与快照/中文名表一致"
else
  strip "$LOG"; echo "${RED}✗ 上游补库文件过期${OFF}"; fail=1
fi
echo

# ── 2. JS 引擎：向量 + 场景 eval ───────────────────────────────────────
echo "${BOLD}[2/6] JS 规则引擎：测试向量 + 场景 eval${OFF}"
node engine/run-tests.mjs >"$LOG" 2>&1; rc=$?
strip "$LOG" | tail -6
[ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 向量通过（单步正确性）" || { echo "${RED}✗ 向量失败（退出码 $rc）${OFF}"; fail=1; }

# 场景 eval：模拟跨周训练史，对整条轨迹断言产品红线。
# 向量测不出序列问题 —— 每一步都正确的函数，串起来照样可能走成荒谬的轨迹。
node engine/run-scenarios.mjs >"$LOG" 2>&1; rc=$?
strip "$LOG" | tail -12
[ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 场景 eval 通过（序列级产品红线）" || { echo "${RED}✗ 场景 eval 违反红线（退出码 $rc）${OFF}"; fail=1; }
echo

# 埋点那半边的 JS：收集端收/拒/落盘 + 口径计算（北极星边界、漏斗、tap_count）
# 它自己错了会给出"看起来很确定"的错数字，所以和引擎一样进这条门禁。
if node server/collector.selftest.mjs >"$LOG" 2>&1; then
  strip "$LOG" | head -3; echo "${GREEN}✓${OFF} 埋点链路自检通过"
else
  strip "$LOG"; echo "${RED}✗ 埋点链路自检失败${OFF}"; fail=1
fi
echo

# 可用性测试那 7 个数字的口径：中位数、硬错误拦截、判定与目标一致
if node tool/usability-selftest.mjs >"$LOG" 2>&1; then
  strip "$LOG" | head -3; echo "${GREEN}✓${OFF} 可用性测试口径自检通过"
else
  strip "$LOG"; echo "${RED}✗ 可用性测试口径自检失败${OFF}"; fail=1
fi
echo

# 隐私政策对账：客户端会发的事件/字段、manifest 权限，都必须与政策正文一致。
# **这是硬门禁** —— 加了一个新埋点字段却不在政策里写清楚，不许合并。
if node tool/privacy-audit.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 隐私政策与代码一致"
else
  strip "$LOG"; echo "${RED}✗ 隐私政策与代码对不上${OFF}"; fail=1
fi
echo

# 隐私政策页面不能漂：docs/privacy-policy*.md 是唯一事实来源，
# store-assets/privacy/*.html 是要交给商店的公网页面。改了正文没重生成 → 红。
if node tool/gen-privacy-page.mjs --check >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 隐私政策公开页面与正文同源"
else
  strip "$LOG"; echo "${RED}✗ 隐私政策页面过期（跑 node tool/gen-privacy-page.mjs）${OFF}"; fail=1
fi
echo

# 软著材料里的数字不能漂：说明书与申请表都写着「N 个源文件 / M 行」，
# 而那是要填进申请表、与鉴别材料一起交的。加一个文件就会变。
if node tool/copyright-pdf.mjs --check-docs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 软著材料里的源程序量与实际一致"
else
  strip "$LOG"; echo "${RED}✗ 软著材料里的源程序量过期（改文档或重新导出）${OFF}"; fail=1
fi
echo

# 发行资源自检：图标不能是 Flutter 默认图（那是 Google 的商标，也不能上架）、
# 启动图不能是模板纯白（App 是深色的）、应用名不能是模板的 "lianleme"。
# 这类东西没有任何测试会红 —— 只有人记得才会改，所以在这里变成一条命令。
if node tool/asset-check.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 发行资源（图标/启动图/应用名）齐全"
else
  strip "$LOG"; echo "${RED}✗ 发行资源有问题（上架前必须修）${OFF}"; fail=1
fi
echo

# ── 3. Dart 领域层（零依赖） ────────────────────────────────────────────
echo "${BOLD}[3/6] Dart 引擎 vs 同一份 vectors.json（零依赖）${OFF}"
if [ -z "$DART_BIN" ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 未找到 Dart SDK。"; blocked=1
else
  "$DART_BIN" app/tool/check_domain.dart >"$LOG" 2>&1; rc=$?
  strip "$LOG" | tail -18
  [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} Dart 领域层通过" || { echo "${RED}✗ Dart 领域层失败（退出码 $rc）${OFF}"; fail=1; }
fi
echo

# ── 4. 静态分析 ─────────────────────────────────────────────────────────
echo "${BOLD}[4/6] 静态分析（dart analyze --fatal-infos）${OFF}"

# 廉价的 import 冲突检查：db.dart（drift 表）与 models.dart（领域模型）
# 都定义了 Workout / SetRecord。同一文件裸 import 两个库时，
# 一旦用到同名类就是 ambiguity_import —— 编译期也会报，但这里 1 秒就能发现。
# （这个错犯过两次，所以固化成检查。）
conflict=0
for f in $(grep -rlE "db\.dart'" app/lib app/test 2>/dev/null | grep -v '\.tmpdir'); do
  grep -qE "models\.dart'" "$f" || continue
  grep -E "db\.dart'" "$f" | head -1 | grep -q ' hide ' && continue
  grep -E "models\.dart'" "$f" | head -1 | grep -q ' as ' && continue
  echo "  ${RED}✗${OFF} ${f#app/}：db.dart 与 models.dart 裸 import，需 hide 或 as"
  conflict=1
done
[ "$conflict" -eq 0 ] && echo "  ${GREEN}✓${OFF} 无 import 命名冲突" || fail=1
if [ -z "$DART_BIN" ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 未找到 Dart SDK。"; blocked=1
elif [ ! -f app/.dart_tool/package_config.json ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 尚无 app/.dart_tool/package_config.json，需先成功跑过一次 pub get。"; blocked=1
else
  # drift 的 .g.dart 是 part 文件，缺了它 analyze 必然报 URI 不存在
  if grep -q '^  drift:' app/pubspec.yaml 2>/dev/null; then
    (cd app && "$DART_BIN" run build_runner build >>"$LOG" 2>&1)
    # 带 withDefault() 的列在 Dart 数据类里仍是 required —— 少传一个就编译失败。
    # 这个错犯过两次（isPr、unitPref），所以固化成检查。
    if command -v python3 >/dev/null 2>&1; then
      python3 app/tool/check_drift_params.py | sed 's/^/    /'
    fi
  fi
  (cd app && "$DART_BIN" analyze --fatal-infos >"$LOG" 2>&1); rc=$?
  strip "$LOG" | tail -30
  [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 静态分析零问题" || { echo "${RED}✗ 静态分析有问题（退出码 $rc）${OFF}"; fail=1; }
fi
echo

# ── 5. Flutter 应用层 ──────────────────────────────────────────────────
echo "${BOLD}[5/6] Flutter widget 测试${OFF}"
if [ "$FAST" -eq 1 ]; then
  echo "${DIM}⊘ 已按 --fast 跳过。完整校验请去掉该参数。${OFF}"
elif [ -z "$FLUTTER_BIN" ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 未安装 Flutter SDK。"; blocked=1
elif [ "$APOSTROPHE_PATH" -eq 1 ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 仓库路径含单引号，flutter test 生成的 listener.dart 会被撇号截断。"
  echo "${DIM}    把仓库放到不含 ' 的路径再跑（如 ~/HARNESS/lianleme/sport）。${OFF}"
  echo "${DIM}    不是测试失败：同一路径下领域层与静态分析都已通过，只有 flutter test 不行。${OFF}"
  blocked=1
else
  # 不要把 $REPO 拼进单引号字符串。仓库路径可能含单引号，那会提前闭合引号
  # （曾报成 `cd: /Volumes/Elliots: No such file`）。改用 env 传值、内部双引号
  # 展开，任何字符都安全。
  PUBLOG=/tmp/lianleme-pubget.log
  if ! with_timeout 240 env VERIFY_APP="$REPO/app" VERIFY_CACHE="$REPO/.pub-cache" VERIFY_FLUTTER="$FLUTTER_BIN" \
       bash -c 'cd "$VERIFY_APP" && PUB_CACHE="$VERIFY_CACHE" "$VERIFY_FLUTTER" pub get' >"$PUBLOG" 2>&1; then
    echo "${YELLOW}⊘ 阻塞${OFF} —— flutter pub get 未成功：属环境问题，不是测试失败。"
    strip "$PUBLOG" | tail -5 | sed 's/^/    /'
    blocked=1
  else
    with_timeout 420 env VERIFY_APP="$REPO/app" VERIFY_CACHE="$REPO/.pub-cache" VERIFY_FLUTTER="$FLUTTER_BIN" \
      bash -c 'cd "$VERIFY_APP" && PUB_CACHE="$VERIFY_CACHE" "$VERIFY_FLUTTER" test --reporter compact' >"$LOG" 2>&1; rc=$?
    strip "$LOG" | tail -25
    [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 应用层通过" || { echo "${RED}✗ 应用层测试失败（退出码 $rc）${OFF}"; fail=1; }
  fi
fi
echo

# ── 6. 变异测试（验证测试本身） ─────────────────────────────────────────
echo "${BOLD}[6/6] 变异测试（把源码改坏，看测试红不红）${OFF}"
if [ -z "$DART_BIN" ]; then
  echo "${YELLOW}⊘ 阻塞${OFF} —— 未找到 Dart SDK；变异测试要跑领域层。"
  blocked=1
else
  node tool/mutation.mjs >"$LOG" 2>&1; rc=$?
  strip "$LOG" | tail -6
  if [ "$rc" -eq 0 ]; then
    echo "${GREEN}✓${OFF} 没有存活变异体（测试真的在守着行为）"
  else
    echo "${RED}✗ 有存活变异体 = 测试盲区${OFF}"
    echo "${DIM}    处理方式只有一种：补一条能抓住它的测试。别改这个数字。${OFF}"
    fail=1
  fi
fi
echo

# ── 产物完整性 ──────────────────────────────────────────────────────────
echo "${BOLD}[附] 产物完整性${OFF}"
missing=0
for f in README.md PRODUCT.md ROADMAP.md CHANGELOG.md \
         docs/tech-decisions.md docs/data-model.md docs/screens.md \
         docs/interaction-spec.md docs/usability-test.md docs/usability-test-kit.md \
         docs/analytics.md docs/analytics-sdk.md \
         docs/privacy-policy.md docs/privacy-policy.en.md docs/release-checklist.md \
         prototype/index.html \
         seed/build.mjs seed/exercises.json seed/exercises.sql \
         engine/progression.mjs engine/vectors.json engine/run-tests.mjs \
         engine/scenarios.json engine/run-scenarios.mjs \
         seed/upstream-workout-guide.json seed/upstream-workout-guide-LICENSE.txt \
         seed/upstream-confirmed.json docs/exercise-mapping-review.md \
         seed/upstream-zh-names.json seed/parts/04-from-upstream.json \
         seed/popularity-tiers.json app/test/legacy_db.dart app/test/migration_test.dart \
         app/test/cardio_test.dart app/test/analytics_identity_test.dart \
         app/test/assisted_exercise_test.dart \
         server/collector.mjs server/collector.selftest.mjs tool/analytics-report.mjs \
         app/lib/analytics/analytics_context.dart app/lib/data/analytics_meta_repository.dart \
         tool/usability-report.mjs tool/usability-selftest.mjs tool/content-report.mjs \
         tool/privacy-audit.mjs docs/privacy-facts.json docs/release-admin.md \
         tool/copyright-export.mjs docs/store-listing.md \
         usability/记录表.md usability/participants.example.json \
         tool/map-upstream.mjs tool/add-upstream-exercises.mjs docs/exercise-mapping.md \
         app/pubspec.yaml app/lib/main.dart \
         app/lib/domain/progression.dart app/lib/domain/tap_meter.dart \
         app/lib/features/workout/workout_controller.dart \
         app/lib/data/db.dart app/lib/data/drift_local_store.dart \
         app/lib/data/exercise_repository.dart app/assets/exercises.json \
         app/lib/features/exercise/exercise_picker_screen.dart \
         app/lib/features/today/today_planner.dart \
         app/lib/features/today/today_suggestion_screen.dart \
         app/lib/core/labels.dart \
         app/lib/core/app_tab_bar.dart app/lib/data/profile_repository.dart \
         app/lib/analytics/outbox.dart app/lib/analytics/flusher.dart \
         app/lib/analytics/transport.dart app/lib/analytics/outbox_analytics.dart \
         app/lib/features/progress/progress_data.dart \
         app/lib/features/progress/progress_screen.dart \
         app/lib/features/profile/training_stats.dart \
         app/lib/features/profile/backup.dart \
         app/lib/features/profile/backup_exporter.dart \
         app/lib/features/profile/profile_screen.dart \
         app/lib/features/summary/workout_summary.dart \
         app/lib/features/summary/workout_summary_screen.dart \
         app/test/today_planner_test.dart app/test/today_suggestion_test.dart \
         app/test/workout_summary_test.dart app/test/profile_test.dart \
         app/test/progress_test.dart app/test/analytics_test.dart \
         app/test/exercise_repository_test.dart app/test/multi_exercise_test.dart \
         app/test/exercise_picker_test.dart app/test/widget_test.dart \
         app/test/local_store_contract_test.dart \
         app/tool/check_domain.dart tool/mutation.mjs \
         app/test/progression_vectors_test.dart app/test/tap_meter_test.dart \
         app/test/workout_flow_test.dart app/test/backup_test.dart \
         app/test/time_exercise_test.dart app/test/progression_wiring_test.dart \
         app/test/home_entry_test.dart app/test/app_version_test.dart \
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
