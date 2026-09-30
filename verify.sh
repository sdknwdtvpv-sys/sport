#!/usr/bin/env bash
# 练了么 · 一键自检
#
# 用法：
#   ./verify.sh          # 全部六层（**全新克隆也能直接跑**：会先自动 pub get + 生成 drift 代码）
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

# 依赖装在 SSD 的 `harness-deps` 目录里（见 ~/HARNESS/lianleme/flutter-env.sh）。
# 卷名 `Elliot's SSD` 里有个**撇号**，所以这里处处加引号。
DEPS="/Volumes/Elliot's SSD/harness-deps"

FLUTTER_BIN="$(command -v flutter 2>/dev/null || true)"
[ -z "$FLUTTER_BIN" ] && [ -x "$DEPS/flutter/bin/flutter" ] && FLUTTER_BIN="$DEPS/flutter/bin/flutter"

DART_BIN="$(command -v dart 2>/dev/null || true)"
if [ -z "$DART_BIN" ] && [ -n "$FLUTTER_BIN" ]; then
  CAND="$(dirname "$FLUTTER_BIN")/cache/dart-sdk/bin/dart"; [ -x "$CAND" ] && DART_BIN="$CAND"
fi
[ -z "$DART_BIN" ] && [ -x "$DEPS/flutter/bin/cache/dart-sdk/bin/dart" ] && \
  DART_BIN="$DEPS/flutter/bin/cache/dart-sdk/bin/dart"

[ -n "$FLUTTER_BIN" ] && echo "${GREEN}✓${OFF} Flutter → $FLUTTER_BIN" || echo "${YELLOW}!${OFF} 未找到 Flutter"
[ -n "$DART_BIN" ] && echo "${GREEN}✓${OFF} Dart    → $DART_BIN" || echo "${YELLOW}!${OFF} 未找到 Dart"

# flutter 还有一份**持久配置**（`~/.config/flutter/settings`），**它的优先级高于环境变量**。
# 2026-09-30 把依赖搬去 SSD 时旧路径留在了里面 —— 于是 release 构建报
# "JAVA_HOME is set to an invalid directory"，而**六层门禁全绿**：门禁一行 Gradle 都不跑。
# 这种"绿着烂掉"比测试失败危险得多（CHANGELOG 里那句"从新位置成功构建了 release APK"
# 就是这么过期的）。所以这里自己查一遍：不是测试失败，是打包的硬前提坏了。
FLUTTER_SETTINGS="$HOME/.config/flutter/settings"
if [ -f "$FLUTTER_SETTINGS" ]; then
  STALE_PATHS="$(node -e '
    const fs = require("fs");
    let s = {};
    try { s = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
    const bad = [];
    for (const k of ["jdk-dir", "android-sdk"]) {
      if (s[k] && !fs.existsSync(s[k])) bad.push(k + "=" + s[k]);
    }
    if (bad.length) { console.log(bad.join(" · ")); process.exit(1); }
  ' "$FLUTTER_SETTINGS" 2>/dev/null)" || {
    echo "${RED}✗ flutter 持久配置指向不存在的目录：$STALE_PATHS${OFF}"
    echo "${DIM}  （环境坏了，不是测试失败；但 release 构建一定失败）修：${OFF}"
    echo "${DIM}  flutter config --jdk-dir=\"\$JAVA_HOME\" --android-sdk=\"\$ANDROID_SDK_ROOT\"${OFF}"
    fail=1
  }
fi
echo

# ── 0. 引导：新克隆 / 新机器上先把依赖与生成物准备好 ─────────────────────
#
# **为什么要有这一步（2026-09-30 在一份全新克隆上实测出来的）**：
# 第 2、4、5 层都依赖 `flutter pub get` 的产物，而**它们对"没有产物"的反应互相矛盾** ——
#   * 第 2 层（iOS 依赖可用性）直接判红，还说"有直接依赖不支持 iOS"（其实只是没 pub get）；
#   * 第 4 层（静态分析）判**阻塞**（对，但只是不红）；
#   * 第 5 层自己偷偷 `pub get`，然后因为 `db.g.dart` 没生成而测出失败。
# 于是"全新克隆 → ./verify.sh"是**红的，而且红得莫名其妙**。门禁号称"一条命令跑完六层"，
# 那就该在一条命令里把引导也做掉。
if [ -n "$FLUTTER_BIN" ] && [ ! -f app/.dart_tool/package_config.json ]; then
  echo "${BOLD}[0] 首次运行：拉依赖（pub get）${OFF}"
  PUBLOG=/tmp/lianleme-bootstrap-pubget.log
  if with_timeout 420 env VERIFY_APP="$REPO/app" VERIFY_CACHE="$REPO/.pub-cache" VERIFY_FLUTTER="$FLUTTER_BIN" \
      bash -c 'cd "$VERIFY_APP" && PUB_CACHE="$VERIFY_CACHE" "$VERIFY_FLUTTER" pub get' >"$PUBLOG" 2>&1; then
    echo "  ${GREEN}✓${OFF} 依赖就绪（缓存 $REPO/.pub-cache）"
  else
    echo "  ${YELLOW}⊘ 阻塞${OFF} —— pub get 没成功：属环境问题，不是测试失败。"
    strip "$PUBLOG" | tail -5 | sed 's/^/    /'
    blocked=1
  fi
fi
if [ -n "$DART_BIN" ] && [ -f app/.dart_tool/package_config.json ] && [ ! -f app/lib/data/db.g.dart ]; then
  echo "${BOLD}[0] 首次运行：生成 drift 代码（build_runner）${OFF}"
  # db.g.dart 是 part 文件：缺了它第 4 层必然报 URI 不存在、第 5 层必然编译失败。
  if (cd app && PUB_CACHE="$REPO/.pub-cache" "$DART_BIN" run build_runner build --delete-conflicting-outputs) \
      >>"$LOG" 2>&1; then
    echo "  ${GREEN}✓${OFF} app/lib/data/db.g.dart 已生成"
  else
    echo "  ${YELLOW}⊘ 阻塞${OFF} —— build_runner 没成功：属环境问题。"
    strip "$LOG" | tail -5 | sed 's/^/    /'
    blocked=1
  fi
fi
[ -f app/.dart_tool/package_config.json ] && echo

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

# 极薄后端自检：账号 / 备份 / 注销 + 三条隐私承诺（只存密文、删除彻底、日志不漏凭据）。
# 它现在只是**本地可跑的参考实现**（阶段 1），生产部署见 docs/backend-design.md 阶段 4。
if node server/backend.selftest.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 极薄后端自检通过"
else
  strip "$LOG"; echo "${RED}✗ 极薄后端自检失败${OFF}"; fail=1
fi

# iOS 产物核对工具的**自检**（造几份动过手脚的 .app，要求它抓得住）。
# 安卓那边有 check-aab.mjs 核产物，iOS 这边此前没有任何东西核过产物；
# 2026-09-30 首次真的编出 iOS 包之后才补上（真产物怎么核见 docs/release-checklist.md）。
if node tool/check-ios-app.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} iOS 产物核对自检通过（改坏任何一项都藏不住）"
else
  strip "$LOG"; echo "${RED}✗ iOS 产物核对工具的自检失败${OFF}"; fail=1
fi
echo

# 密文核验工具的**自检**：它故意造一份"ct 其实是明文"的库，要求工具报错。
# 少了这一步，那条检查可能只是"永远打印 ✓"的假守卫（2026-09-30 补）。
if node tool/check-ciphertext.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} 密文核验自检通过（明文藏不住）"
else
  strip "$LOG"; echo "${RED}✗ 密文核验工具的自检失败${OFF}"; fail=1
fi
echo

# 商店截图核对工具的**自检**：截图是全仓库唯一没人核过的交付物，
# 而且真坏过一次 —— `11-body-metric.png` 比 App 旧一个版本（v1.31.0 前多了一道
# 敏感信息单独同意的门，脚本却假定"点开就是表单"）。
if node tool/check-screenshots.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} 截图核对自检通过（少一张/多一张/尺寸不对都藏不住）"
else
  strip "$LOG"; echo "${RED}✗ 截图核对工具的自检失败${OFF}"; fail=1
fi
echo

# 交付目录核对工具的**自检**：dist/ 是交付口（真机装 APK、商店传 AAB、软著交 PDF），
# 而生成物最容易出的事故就是"留着上一版的"——2026-09-30 真的发生过两次。
if node tool/check-dist.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} 交付目录核对自检通过（旧版本/没版本号/坏包都藏不住）"
else
  strip "$LOG"; echo "${RED}✗ 交付目录核对工具的自检失败${OFF}"; fail=1
fi
echo

# CI 与门禁关系核对工具的**自检**：workflow 头部写着"这是门禁的子集"，
# 而那是**承诺**：CI 里加一条门禁不管的命令就当场变假，且本地门禁永远复现不了它。
if node tool/check-ci.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} CI↔门禁核对自检通过（偷跑命令/少步骤/没钉版本都藏不住）"
else
  strip "$LOG"; echo "${RED}✗ CI↔门禁核对工具的自检失败${OFF}"; fail=1
fi
echo

# 用户可见文案核对工具的**自检**：`Text` 不渲染 markdown —— `**` 是三个星号印在屏幕上。
# 这个项目为此付过三次学费（同意弹层、政策里的待办、收集清单开头的说明），每次都是眼睛先看见的。
if node tool/check-user-text.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} 用户文案核对自检通过（字符串里的记号藏不住，注释里的不误报）"
else
  strip "$LOG"; echo "${RED}✗ 用户文案核对工具的自检失败${OFF}"; fail=1
fi
echo

# 商店表单对账工具的**自检**：两张商店表单是提交材料，填错是拒审/下架的理由，
# 而它们此前只是两份 Markdown（埋点字段改过好几轮，每次都可能让某张表变成假话）。
if node tool/check-store-forms.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} 商店表单对账自检通过（漏字段/漏披露/抄错变体都藏不住）"
else
  strip "$LOG"; echo "${RED}✗ 商店表单对账工具的自检失败${OFF}"; fail=1
fi
echo

# 部署包核对工具的**自检**：`server/deploy/` 里全是配置文本，漂了平时看不出来、
# 只在部署那一刻炸（或者更糟：不炸但违背承诺，比如反代开了访问日志 = 记了客户端 IP）。
if node tool/check-deploy.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} 部署包核对自检通过（端口/日志/加固/占位符都藏不住）"
else
  strip "$LOG"; echo "${RED}✗ 部署包核对工具的自检失败${OFF}"; fail=1
fi
echo

# 截图"压平"工具（去掉 alpha + 16 位降 8 位）的自检：App Store 只收 8 位无 alpha，
# 而 iOS 模拟器截出来的是 **16 位 RGBA**（2026-09-30 实测）。读的那 5 种 filter
# 也在这里逐种验过 —— 读错了会一路错到商店上传被拒。
if node tool/flatten-png.mjs --selftest >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} 截图压平自检通过（16 位降 8 位 / 去 alpha / 5 种 filter）"
else
  strip "$LOG"; echo "${RED}✗ 截图压平工具的自检失败${OFF}"; fail=1
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

# CHANGELOG 的版本小节必须**降序**排列。
# 2026-09-30 抓到的：前几轮的插入落错了位置（v1.24.0~v1.25.2 被塞到 v1.23.1 之后，
# 而 v1.26.0 干脆漏写）—— 人翻不出来，机器一眼能查。
if node -e '
  const fs = require("fs");
  const text = fs.readFileSync("CHANGELOG.md", "utf8");
  const vs = [...text.matchAll(/^## v(\d+)\.(\d+)\.(\d+)/gm)]
    .map((m) => [Number(m[1]), Number(m[2]), Number(m[3])]);
  // 别只看行首那些：**粘到上一行去的标题**（少一个换行）在 `^## v` 眼里根本不存在，
  // 于是"降序"照样成立 —— 2026-09-30 就是这么漏掉一个真缺陷的：
  // `…→ 1.27.2+36。## v1.27.1 · iOS 上「存相册」…` 挤在同一行，守护全程绿灯。
  const anywhere = [...text.matchAll(/## v(\d+)\.(\d+)\.(\d+)/g)].length;
  if (anywhere !== vs.length) {
    console.log(`有 ${anywhere - vs.length} 个版本小节没从行首开始（被粘到上一行？少了个换行）`);
    process.exit(1);
  }
  for (let i = 1; i < vs.length; i++) {
    const a = vs[i - 1], b = vs[i];
    const desc = a[0] !== b[0] ? a[0] > b[0] : (a[1] !== b[1] ? a[1] > b[1] : a[2] >= b[2]);
    if (!desc) { console.log(`v${a.join(".")} 之后出现了 v${b.join(".")}`); process.exit(1); }
  }
  process.exit(0);
' >"$LOG" 2>&1; then
  echo "${GREEN}✓${OFF} CHANGELOG 的版本小节是降序的"
else
  echo "${RED}✗ CHANGELOG 的版本小节不是降序：$(strip "$LOG" | head -1)${OFF}"
  fail=1
fi

# 环境文档必须与**磁盘上的真实布局**一致（2026-09-30 补）。
# 起因：依赖搬到 SSD 之后，ROADMAP 里那三个旧路径还带着 ✅ 摆了很久没人发现 ——
# 这类"环境文档漂了"没有任何东西会红，而它会让下一个人按错误路径去找 SDK。
DEPS_ROOT="$(grep -oE '^DEPS="[^"]+"' tool/dev-env.sh 2>/dev/null | head -1 | sed 's/^DEPS="//; s/"$//')"
if [ -z "$DEPS_ROOT" ] || [ ! -d "$DEPS_ROOT" ]; then
  echo "${RED}✗ 读不到 tool/dev-env.sh 里的 DEPS，或它指向的目录不存在（$DEPS_ROOT）${OFF}"
  fail=1
else
  MISSING_DEPS=""
  for name in $(grep -oE '`harness-deps/[a-zA-Z0-9._-]+' docs/dev-environment.md 2>/dev/null \
      | sed 's/`harness-deps\///' | sort -u); do
    [ -d "$DEPS_ROOT/$name" ] || MISSING_DEPS="$MISSING_DEPS $name"
  done
  if [ -n "$MISSING_DEPS" ]; then
    echo "${RED}✗ docs/dev-environment.md 里列的依赖目录在磁盘上不存在：$MISSING_DEPS${OFF}"
    echo "    （依赖搬过家就要同时改文档与 tool/dev-env.sh 的 DEPS）"
    fail=1
  else
    echo "${GREEN}✓${OFF} 环境文档列的依赖目录都真实存在（$DEPS_ROOT）"
  fi
fi

# README 顶部那行 `**vX.Y.Z**` 是访客看到的"现在到哪了"。它漂过：写着 v1.2.0
# 而仓库已经 1.22.x。和软著那两条同一个道理 —— 没人会为了改一个数字去翻 README，
# 所以钉住它。真源只有一个：`app/lib/core/app_info.dart`。
README_VER="$(grep -oE '\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*' README.md 2>/dev/null | head -1 | tr -d '*v')"
APP_VER="$(grep -oE "kAppVersion = '[^']+'" app/lib/core/app_info.dart | head -1 | sed "s/.*'\\(.*\\)'/\\1/")"
if [ -z "$README_VER" ]; then
  echo "${YELLOW}!${OFF} README.md 里找不到 `**vX.Y.Z**`（措辞变了？检查要跟着改）"
elif [ "$README_VER" != "$APP_VER" ]; then
  echo "${RED}✗ README.md 顶部写的是 v$README_VER，实际版本是 $APP_VER${OFF}"
  fail=1
else
  echo "${GREEN}✓${OFF} README 顶部的版本号（v$README_VER）与 app_info.dart 一致"
fi
echo

# docs/your-todo.md 顶部「更新于 …（vX.Y.Z）」是**唯一的待办入口**自己的时间戳。
# 它漂过：写着 v1.23.1，而仓库已经 1.27.2 —— 一份"待办清单"自己都过期了，最伤信任。
# 与 README 那条同一个模式，真源同样是 app/lib/core/app_info.dart。
# ⚠️ 括号是**全角**的（中文文档），第一版写成 ASCII 括号 → 一条都匹配不上，
# 而"匹配不上"当时只报警告不报错 —— 于是这条守卫**静默失效**，门禁照样全绿。
# 所以这里两处都改了：括号改全角，且**匹配不上直接判红**（找不到时间戳 = 这条守卫死了，
# 不是"一切正常"）。
TODO_VER="$(grep -oE '更新于 [0-9-]+（v[0-9]+\.[0-9]+\.[0-9]+）' docs/your-todo.md 2>/dev/null | head -1 | sed 's/.*（v\(.*\)）/\1/')"
if [ -z "$TODO_VER" ]; then
  echo "${RED}✗ docs/your-todo.md 里找不到「更新于 YYYY-MM-DD（vX.Y.Z）」（全角括号）—— 这条守卫已经失效，别当成通过${OFF}"
  fail=1
elif [ "$TODO_VER" != "$APP_VER" ]; then
  echo "${RED}✗ docs/your-todo.md 顶部写的是 v$TODO_VER，实际版本是 $APP_VER${OFF}"
  fail=1
else
  echo "${GREEN}✓${OFF} docs/your-todo.md 的时间戳（v$TODO_VER）与 app_info.dart 一致"
fi

# 「真机上装的是哪一版」这三行**每切一版都该改**，而没人会为了改一个数字去翻它们。
# 它们烂过：README 与 ROADMAP 停在 v1.27.0，release-checklist 甚至停在 v1.21.0 ——
# 而这三行是用户判断"到底验到哪一步了"的依据，说错了就是**把没验的说成验了**。
# 真源同样只有 app/lib/core/app_info.dart。
check_installed_ver() {
  local file="$1" pattern="$2" label="$3"
  local got
  got="$(grep -oE "$pattern" "$file" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  if [ -z "$got" ]; then
    echo "${RED}✗ $file 里找不到「$label」（措辞变了？这条守卫已经失效，别当成通过）${OFF}"
    fail=1
  elif [ "$got" != "$APP_VER" ]; then
    echo "${RED}✗ $file 写的是真机装 v$got，实际版本是 $APP_VER${OFF}"
    fail=1
  else
    echo "${GREEN}✓${OFF} $file 的真机版本（v$got）与 app_info.dart 一致"
  fi
}
# ⚠️ README 那行是 `**v1.27.2 release**` —— 粗体**跨过了版本号**，
# 所以模式末尾**不能**要求 `**`（第一版就是那么写的，于是"匹配不到"→守卫死掉）。
check_installed_ver README.md '上装的是 \*\*v[0-9]+\.[0-9]+\.[0-9]+' '上装的是 **vX.Y.Z'
check_installed_ver ROADMAP.md '已装 `v[0-9]+\.[0-9]+\.[0-9]+`' '已装 `vX.Y.Z`'
check_installed_ver docs/release-checklist.md '上跑的是 \*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*' '上跑的是 **vX.Y.Z**'

# iOS 可用性：每个直接依赖都得声明支持 iOS。
# 挡的是"顺手加一个只有 Android 实现的插件" —— 它在本机（只有安卓真机）完全正常，
# 等装上 Xcode 才发现 iOS 编不过，而那时已经过去很久、也忘了是谁加的。
if [ ! -f app/.dart_tool/package_config.json ]; then
  # 没有 package_config 时这个工具会把每个依赖都判成"missing"，于是报出
  # **"有直接依赖不支持 iOS"** —— 那是句假话（真实原因只是 pub get 没成功）。
  # 按本脚本的约定：环境导致的无法执行算"阻塞"，不算失败。
  echo "${YELLOW}⊘ 阻塞${OFF} —— 尚无 app/.dart_tool/package_config.json（pub get 未成功），"
  echo "${DIM}    iOS 依赖可用性这一条跑不了。${OFF}"
  blocked=1
elif node tool/ios-deps.mjs >"$LOG" 2>&1; then
  echo "${GREEN}✓${OFF} 直接依赖都支持 iOS（或本来就是纯 Dart）"
else
  strip "$LOG"; echo "${RED}✗ 有直接依赖不支持 iOS —— 「双端先上」会被它挡住${OFF}"; fail=1
fi

# 发行资源自检：图标不能是 Flutter 默认图（那是 Google 的商标，也不能上架）、
# 启动图不能是模板纯白（App 是深色的）、应用名不能是模板的 "lianleme"。
# 这类东西没有任何测试会红 —— 只有人记得才会改，所以在这里变成一条命令。
if node tool/asset-check.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 发行资源（图标/启动图/应用名）齐全"
else
  strip "$LOG"; echo "${RED}✗ 发行资源有问题（上架前必须修）${OFF}"; fail=1
fi
echo

# 交付目录：dist/ 里只许有当前版本的 APK/AAB，且**包内**版本号与真源一致
# （文件名可以改，包里的版本号改不了 —— 所以那条才是真证据）。dist/ 不在时跳过。
if node tool/check-dist.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 交付目录干净（只有当前版本，包内版本与真源一致）"
else
  strip "$LOG"; echo "${RED}✗ 交付目录不对（旧版本/坏包/包内版本对不上）${OFF}"; fail=1
fi
echo

# CI 与门禁的关系：CI 只许跑门禁覆盖得了的命令、核心步骤不许少、版本必须钉死、
# 头部那份"没覆盖什么"的清单必须点明（"CI 绿 ≠ 门禁绿"是写在三处文档里的承诺）。
if node tool/check-ci.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} CI 仍是门禁的子集（命令/步骤/版本都对得上）"
else
  strip "$LOG"; echo "${RED}✗ CI 与门禁的关系不对（"子集"这句话已经不成立）${OFF}"; fail=1
fi
echo

# 用户可见文案：`app/lib` 的字符串字面量里不许有 `**`（markdown 记号）或"给我们自己看"的说明
# （仓库/生成物/请勿手改/TODO/待填…）—— 注释不算，不误报。
if node tool/check-user-text.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 界面文案干净（无 markdown 记号、无内部说明）"
else
  strip "$LOG"; echo "${RED}✗ 界面文案里漏出了不该给用户看的东西${OFF}"; fail=1
fi
echo

# 商店表单：事实源 ↔ Google Play 数据安全 ←→ App Store 隐私标签 三边对账
# （变体结构、"不收集"不许抄进变体 B、敏感字段披露、默认关、新字段必须做过决定）。
if node tool/check-store-forms.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 两张商店表单与事实源一致"
else
  strip "$LOG"; echo "${RED}✗ 商店表单与事实源对不上（填错是拒审/下架的理由）${OFF}"; fail=1
fi
echo

# 部署包：端口一致（install.sh ↔ 两个 systemd 单元 ↔ Caddyfile）、入口存在、
# 与客户端的 dart-define 逐字对得上、加固没被删、没开访问日志（承诺"不做 IP 记录"）。
if node tool/check-deploy.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 部署包自洽（端口/入口/加固/无访问日志）"
else
  strip "$LOG"; echo "${RED}✗ 部署包有矛盾（部署那一刻才会炸，现在先拦住）${OFF}"; fail=1
fi
echo

# 商店截图：两套图（1080×2400 / 1080×1920）是否齐、尺寸是否对、有没有夹带
# `zz-fail-*.png` 那种"某一步失败的现场图"。截图是交付物，但此前没人核过。
if node tool/check-screenshots.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -4; echo "${GREEN}✓${OFF} 三套商店截图齐、尺寸对、没夹带（含 App Store 那套的 8 位无 alpha）"
else
  strip "$LOG"; echo "${RED}✗ 商店截图不对（缺图/尺寸变了/夹带失败现场图/带 alpha）${OFF}"; fail=1
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
  # ⚠️ 先把整个文件压成一行再匹配：import 语句**可以跨行**，
  # 而仓库自己的风格就是跨行（main.dart：`import '...db.dart'` 换行再 `hide ...`）。
  # 2026-09-30 这个检查因此误报了 4 个文件 —— 修的是检查，不是那些文件。
  flat=$(tr '\n' ' ' < "$f")
  echo "$flat" | grep -qE "models\.dart'" || continue
  # hide 与 show 都能消除歧义（show 只放进来指定的名字），两者都算数
  echo "$flat" | grep -oE "import '[^']*db\.dart'[^;]*;" | head -1 | grep -qE ' (hide|show) ' && continue
  echo "$flat" | grep -oE "import '[^']*models\.dart'[^;]*;" | head -1 | grep -q ' as ' && continue
  echo "  ${RED}✗${OFF} ${f#app/}：db.dart 与 models.dart 裸 import，需 hide / show / as"
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

    # ── 文档里那句"门禁 N 项全绿"必须是真的 ──────────────────────────────
    # 这个数字每加一个测试都会变，而它偏偏是读文档的人唯一的进度指标。
    # 2026-09-30 它已经漂过三个版本（文档还写着 666、实际 685），原因很朴素：
    # **没人会为了改一个数字专门去翻文档**。所以跟软著那两条一样，变成能跑的命令。
    # 唯一的事实源是 docs/release-checklist.md 的"当前状态速览"那行；README 不再抄数字。
    TEST_COUNT="$(grep -oE '\+[0-9]+: All tests passed' "$LOG" | tail -1 | grep -oE '[0-9]+')"
    if [ -n "$TEST_COUNT" ]; then
      # ⚠️ 正则必须容忍 markdown 的 `**`：第一版写的是 `门禁 [0-9]+ 项全绿`，
      # 而文档里是「门禁 **685 项全绿**」—— 于是它**永远匹配不上**，
      # 每次都只打一句"找不到"就过去了。**空转的守卫比没有守卫更危险**：
      # 我把数字故意改成 666 试过，门禁照样绿。现在改成"数字前后允许任何非数字"，
      # 而且**找不到就判红**（措辞变了就该有人来看一眼）。
      CLAIMED="$(grep -oE '门禁[^0-9]*[0-9]+[^0-9]*项全绿' docs/release-checklist.md 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)"
      if [ -z "$CLAIMED" ]; then
        echo "${RED}✗ docs/release-checklist.md 里找不到「门禁 N 项全绿」—— 这段检查已经空转，请跟着改${OFF}"
        fail=1
      elif [ "$CLAIMED" != "$TEST_COUNT" ]; then
        echo "${RED}✗ docs/release-checklist.md 写的是「门禁 $CLAIMED 项全绿」，实际是 $TEST_COUNT 项${OFF}"
        fail=1
      else
        echo "  ${GREEN}✓${OFF} 文档里的测试数（$TEST_COUNT 项）与实际一致"
      fi
    fi
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
         app/tool/check_domain.dart tool/mutation.mjs tool/check-aab.mjs \
         tool/check-ios-app.mjs tool/check-ciphertext.mjs tool/check-screenshots.mjs \
         tool/check-store-forms.mjs tool/check-ci.mjs tool/check-dist.mjs \
         tool/check-user-text.mjs \
         tool/flatten-png.mjs tool/lib/png.mjs tool/check-deploy.mjs \
         server/deploy/install.sh server/deploy/Caddyfile \
         server/deploy/lianleme-backend.service server/deploy/lianleme-collector.service \
         tool/ios-deps.mjs docs/store-listing-ios.md docs/your-todo.md \
         tool/gen-feature-graphic.py store-assets/feature-graphic-1024x500.png \
         app/test/progression_vectors_test.dart app/test/tap_meter_test.dart \
         app/test/workout_flow_test.dart app/test/backup_test.dart \
         app/test/time_exercise_test.dart app/test/progression_wiring_test.dart \
         app/integration_test/share_card_gallery_test.dart \
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
