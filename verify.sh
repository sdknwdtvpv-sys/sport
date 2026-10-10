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
skipped=0
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

# ── 跑某个工具的**自检**（`--selftest`）─────────────────────────────────
#
# 为什么抽成一个函数：这段 if/else 在门禁里原本**复制了 14 遍**（每加一个守卫就再抄一份），
# 想改一次行为（比如"失败时多打几行"）就得改 14 处 —— 2026-10-01 抽出来。
# 行为**与原来逐字一致**：成功打自检的最后一行摘要 + ✓；失败打完整输出 + ✗，
# 并把整条门禁判红（`fail=1`）。
selfcheck() {
  local tool="$1" ok="$2" bad="$3"
  if node "$tool" --selftest >"$LOG" 2>&1; then
    strip "$LOG" | tail -1
    echo "${GREEN}✓${OFF} $ok"
  else
    strip "$LOG"
    echo "${RED}✗ $bad${OFF}"
    fail=1
  fi
  echo
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
  # ⚠️ **失败重试一次**（2026-10-07 加）：CI 上拉包是从 pub.dev 现拉的，
  # registry 抖一下就会让整条门禁红成一片（而本地有缓存，永远看不到这种红）。
  # 重试一次很便宜；真的是"拉不动"就还是红。
  if with_timeout 420 env VERIFY_APP="$REPO/app" VERIFY_CACHE="$REPO/.pub-cache" VERIFY_FLUTTER="$FLUTTER_BIN" \
      bash -c 'cd "$VERIFY_APP" && PUB_CACHE="$VERIFY_CACHE" "$VERIFY_FLUTTER" pub get' >"$PUBLOG" 2>&1 \
    || { echo "  ${YELLOW}…pub get 第一次失败，5 秒后重试${OFF}"; sleep 5; \
         with_timeout 420 env VERIFY_APP="$REPO/app" VERIFY_CACHE="$REPO/.pub-cache" VERIFY_FLUTTER="$FLUTTER_BIN" \
           bash -c 'cd "$VERIFY_APP" && PUB_CACHE="$VERIFY_CACHE" "$VERIFY_FLUTTER" pub get' >>"$PUBLOG" 2>&1; }; then
    echo "  ${GREEN}✓${OFF} 依赖就绪（缓存 $REPO/.pub-cache）"
  else
    echo "  ${YELLOW}⊘ 阻塞${OFF} —— pub get 没成功：属环境问题，不是测试失败。"
    # ⚠️ 尾 20 行（原先是 5）：CI 上唯一能看到原因的地方就是这几行，
    # 而 pub 的报错正文常常在最后几行之前（2026-10-07 就是因为只看 5 行，
    # 只知道"build_runner 没成功"却不知道**为什么**）。
    strip "$PUBLOG" | tail -20 | sed 's/^/    /'
    blocked=1
  fi
fi
if [ -n "$DART_BIN" ] && [ -f app/.dart_tool/package_config.json ] && [ ! -f app/lib/data/db.g.dart ]; then
  echo "${BOLD}[0] 首次运行：生成 drift 代码（build_runner）${OFF}"
  # db.g.dart 是 part 文件：缺了它第 4 层必然报 URI 不存在、第 5 层必然编译失败。
  if (cd app && PUB_CACHE="$REPO/.pub-cache" "$DART_BIN" run build_runner build) >>"$LOG" 2>&1 \
     || { echo "  ${YELLOW}…build_runner 第一次失败，5 秒后重试${OFF}"; sleep 5; \
          (cd app && PUB_CACHE="$REPO/.pub-cache" "$DART_BIN" run build_runner build) >>"$LOG" 2>&1; }; then
    echo "  ${GREEN}✓${OFF} app/lib/data/db.g.dart 已生成"
  else
    echo "  ${YELLOW}⊘ 阻塞${OFF} —— build_runner 没成功：属环境问题。"
    strip "$LOG" | tail -20 | sed 's/^/    /'
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

# 可用性测试的「预置 6 周历史」：用文件自己记录的基准日复现它，逐字节比对，
# 并用**真引擎**核对任务卡 T6 那句"App 建议你这次推 62.5 公斤"真的成立
# （今天轮到胸 + 卧推上次 3 组 × 10 次 @ 60kg ⇒ 加重 2.5 ⇒ 62.5）。
# 2026-10-01 之前这份 JSON **全仓不存在也没有生成器**，现场只能手搓。
if node tool/preset-history.mjs --check >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 预置 6 周历史与生成器一致（含真引擎算出的 62.5kg）"
else
  strip "$LOG"; echo "${RED}✗ 预置 6 周历史过期或与生成器不一致${OFF}"; fail=1
fi
echo

# ── 2. JS 引擎：向量 + 场景 eval ───────────────────────────────────────
echo "${BOLD}[2/6] JS 规则引擎：测试向量 + 场景 eval${OFF}"
node engine/run-tests.mjs >"$LOG" 2>&1; rc=$?
strip "$LOG" | tail -6
[ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 向量通过（单步正确性）" || { echo "${RED}✗ 向量失败（退出码 ${rc}）${OFF}"; fail=1; }

# 场景 eval：模拟跨周训练史，对整条轨迹断言产品红线。
# 向量测不出序列问题 —— 每一步都正确的函数，串起来照样可能走成荒谬的轨迹。
node engine/run-scenarios.mjs >"$LOG" 2>&1; rc=$?
strip "$LOG" | tail -12
[ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 场景 eval 通过（序列级产品红线）" || { echo "${RED}✗ 场景 eval 违反红线（退出码 ${rc}）${OFF}"; fail=1; }
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

# 任务卡三处一致：`usability/tasks.json` 是唯一事实源，递卡文档 / 测试脚本 / 记录表
# 必须都跟上。2026-10-01 发现 kit §4 与记录表的 T3/T4/T5 内容不一致（含刻意必败的 T5），
# 而报告工具只认 id、抓不到 —— 那是"同一批事实写两遍"的第三次复发。
if node tool/check-usability-tasks.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 任务卡三处与事实源一致"
else
  strip "$LOG"; echo "${RED}✗ 任务卡在三份文档之间漂了${OFF}"; fail=1
fi
echo

# 极薄后端自检：账号 / 备份 / 注销 + 三条隐私承诺（只存密文、删除彻底、日志不漏凭据）。
# 它现在只是**本地可跑的参考实现**（阶段 1），生产部署见 docs/backend-design.md 阶段 4。
if node server/backend.selftest.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 极薄后端自检通过"
else
  strip "$LOG"; echo "${RED}✗ 极薄后端自检失败${OFF}"; fail=1
fi

# 邮件模块自检：注册/找回要发验证码，而这个后端**零依赖**（不引 nodemailer），
# 所以 SMTP 客户端是自己写的几十行 —— 自己写的协议对话必须有一条自检盯着：
# 对着假 SMTP 服务器跑完整对话、明文默认必拒、真 TLS（465，生产就是这条）也走一遍。
# openssl 不在时 TLS 那一步如实标"跳过"，不判失败也不假装通过。
if node server/mailer.selftest.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 邮件模块自检通过"
else
  strip "$LOG"; echo "${RED}✗ 邮件模块自检失败${OFF}"; fail=1
fi

# 账号体系自检：注册 / 登录 / 会话令牌 / 改口令踢号 / 忘口令重置 / 应用内注销。
# 邮件走 `--mail-out`（文件）模式，所以**不需要真的 SMTP** 就能端到端跑通。
# 它盯的是"看起来成功了"的那类错：令牌没吊销、注销没删干净、库里/日志里出现明文、
# 以及最要紧的 —— 服务端**解不开**账号密钥（`wrapped` 原样保管）。
if node server/auth.selftest.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 账号体系自检通过"
else
  strip "$LOG"; echo "${RED}✗ 账号体系自检失败${OFF}"; fail=1
fi

# plist 读写库的**自检**：核 iOS 产物要读 Info.plist，macOS 上靠 /usr/bin/plutil，
# 而 CI 是 ubuntu（**没有 plutil**）—— 那就得有一个自己的解析器，且它必须被验过
# （解析/序列化互逆、坏输入会抛、与系统 plutil 结果一致）。
# 公共零件的自检：Android SDK 的查找口径（aapt2）与文档守卫的公共零件（枚举 + 历史窗口）。
# 这两份代码以前各在别处复制过一份，抽出来之后**必须有自检**，否则下次又被抄回去。
selfcheck tool/lib/android-sdk.mjs "Android SDK 查找口径自检通过（DEPS/环境变量优先级、写死路径没长回来）" "Android SDK 查找口径的自检失败"

selfcheck tool/lib/docs.mjs "文档公共零件自检通过（枚举一处、历史判定按窗口）" "文档公共零件的自检失败"

selfcheck tool/check-doc-facts.mjs "文档事实核对自检通过（schema/动作数/事件数写旧了都藏不住）" "文档事实核对工具的自检失败"

selfcheck tool/lib/plist.mjs "plist 读写库自检通过（解析/序列化互逆、坏输入会抛）" "plist 读写库自检失败"

# 工作台数据层的**公共零件**（2026-10-04 抽出来，原来 800 行全塞在 tool/workbench.mjs 里）。
# 为什么这三份必须有自检：一个"永远返回空数组"的解析器不会报错，
# 它只会安静地把看板变成一片"这一节里没有条目"——**一个会撒谎的看板比没有看板更坏**。
# 三份都拿真仓库跑一遍（不是只喂夹具），所以"路径拼错了导致全空"当场就露。
selfcheck tool/lib/markdown-table.mjs "Markdown 表格切分自检通过（转义竖线/围栏代码块/退化行都算得对）" "Markdown 表格切分的自检失败"

selfcheck tool/lib/collect-docs.mjs "文档采集自检通过（5 份文档的进度/待办/拍板都读得出，读不出就如实说读不出）" "文档采集的自检失败"

selfcheck tool/lib/collect-repo.mjs "仓库采集自检通过（版本/CHANGELOG/产物残留/git/证据/合规都算得对）" "仓库采集的自检失败"

# iOS 产物核对工具的**自检**（造几份动过手脚的 .app，要求它抓得住）。
# 安卓那边有 check-aab.mjs 核产物，iOS 这边此前没有任何东西核过产物；
# 2026-09-30 首次真的编出 iOS 包之后才补上（真产物怎么核见 docs/release-checklist.md）。
selfcheck tool/check-ios-app.mjs "iOS 产物核对自检通过（改坏任何一项都藏不住）" "iOS 产物核对工具的自检失败"

# 密文核验工具的**自检**：它故意造一份"ct 其实是明文"的库，要求工具报错。
# 少了这一步，那条检查可能只是"永远打印 ✓"的假守卫（2026-09-30 补）。
selfcheck tool/check-ciphertext.mjs "密文核验自检通过（明文藏不住）" "密文核验工具的自检失败"

# 商店截图核对工具的**自检**：截图是全仓库唯一没人核过的交付物，
# 而且真坏过一次 —— `11-body-metric.png` 比 App 旧一个版本（v1.31.0 前多了一道
# 敏感信息单独同意的门，脚本却假定"点开就是表单"）。
selfcheck tool/check-screenshots.mjs "截图核对自检通过（少一张/多一张/尺寸不对都藏不住）" "截图核对工具的自检失败"

# 交付目录核对工具的**自检**：dist/ 是交付口（真机装 APK、商店传 AAB、软著交 PDF），
# 而生成物最容易出的事故就是"留着上一版的"——2026-09-30 真的发生过两次。
selfcheck tool/check-dist.mjs "交付目录核对自检通过（旧版本/没版本号/坏包都藏不住）" "交付目录核对工具的自检失败"

# CI 与门禁关系核对工具的**自检**：「CI 绿 = 门禁绿」是写在 README 与政策里的**承诺**
# （2026-09-30 起 CI 跑的就是这条 `verify.sh`）。用 --fast 偷跳第 5 层、混进门禁不管的
# 命令、版本没钉死，都会当场变假，而本地门禁按定义复现不了 CI 自己加的东西。
selfcheck tool/check-ci.mjs "CI↔门禁核对自检通过（偷跑命令/少步骤/没钉版本都藏不住）" "CI↔门禁核对工具的自检失败"

# "守卫有没有真的在跑"的**自检**：写了一个守卫 ≠ 它在门禁里跑 ——
# `check-aab.mjs` 就曾经存在很久却从没在门禁里跑过（一个不跑的守卫等于没有）。
selfcheck tool/check-guards-wired.mjs "守卫接线自检通过（存在但从不跑、假的代跑关系都藏不住）" "守卫接线核对工具的自检失败"

# 文档版本核对工具的**自检**：版本号是这仓库最勤劳的一类漂移 ——
# 第 2 层已守"三处真机版本"，但文档里还有别处**陈述现状**（产物行、终局核验、iOS 那一行）。
selfcheck tool/check-doc-versions.mjs "文档版本核对自检通过（过期的 versionCode/设备版本/重核版本都藏不住）" "文档版本核对工具的自检失败"

# 文档表格核对工具的**自检**：这些表大半是要照着填的（商店表单/软著申请表/清单），
# 而 markdown 表格坏起来很安静 —— 被截断、错列，只有眼睛看得出来。
selfcheck tool/check-doc-tables.mjs "文档表格核对自检通过（截断/错列藏不住，转义竖线不误报）" "文档表格核对工具的自检失败"

# 文档路径核对工具的**自检**：文档里到处都是 `tool/xxx.mjs` 这种引用，
# 文件改名/搬家之后它们会**悄悄指空** —— 读者照着敲就是"文件不存在"。
selfcheck tool/check-doc-paths.mjs "文档路径核对自检通过（指空的引用藏不住）" "文档路径核对工具的自检失败"

selfcheck tool/check-vi-strokes.mjs "vi 稿子线宽守卫自检通过（1.5 / 1.8 越界、2.5 / 3 例外、没有描边的不误报）" "vi 稿子线宽守卫的自检失败"

# 任务卡一致性工具的**自检**：回归用例照着真事故做 ——
# `usability/记录表.md` 里的 T5 被换成别的内容（kit 的 T5 是刻意必败任务），
# 而报告工具只认 id，当时没有任何东西会发现。
selfcheck tool/check-usability-tasks.mjs "任务卡一致性自检通过（三份文档漂了会被抓到）" "任务卡一致性工具的自检失败"

# 预置历史生成器的**自检**：确定性（--check 的地基）+ 三条把任务卡钉住的不变量 ——
# 今天必须轮到胸、真引擎对卧推必须算出 62.5kg、T4 的"上周卧推总容量"必须是 1800kg。
selfcheck tool/preset-history.mjs "预置历史自检通过（确定性 + 真引擎算出 62.5kg + T4 答案 1800kg）" "预置历史生成器的自检失败"

# 用户可见文案核对工具的**自检**：`Text` 不渲染 markdown —— `**` 是三个星号印在屏幕上。
# 这个项目为此付过三次学费（同意弹层、政策里的待办、收集清单开头的说明），每次都是眼睛先看见的。
selfcheck tool/check-user-text.mjs "用户文案核对自检通过（字符串里的记号藏不住，注释里的不误报）" "用户文案核对工具的自检失败"

# 商店表单对账工具的**自检**：两张商店表单是提交材料，填错是拒审/下架的理由，
# 而它们此前只是两份 Markdown（埋点字段改过好几轮，每次都可能让某张表变成假话）。
selfcheck tool/check-store-forms.mjs "商店表单对账自检通过（漏字段/漏披露/抄错变体都藏不住）" "商店表单对账工具的自检失败"

# 部署包核对工具的**自检**：`server/deploy/` 里全是配置文本，漂了平时看不出来、
# 只在部署那一刻炸（或者更糟：不炸但违背承诺，比如反代开了访问日志 = 记了客户端 IP）。
# shell 脚本的「变量后紧跟中文」：macOS 自带 bash 3.2 在 UTF-8 locale 下会把那个字符的字节
# 吞进变量名 → `set -u` 当场 unbound variable。2026-10-05 真踩：你在终端里跑生成 keystore
# 的脚本，走到问完密码之后报 `KEYSTORE?: unbound variable`，而我这边复现不出来 ——
# **因为触发条件是 locale**（我的是 LC_CTYPE=C，Terminal 是 UTF-8）。
selfcheck tool/check-shell-locale.mjs "shell 变量后紧跟中文的自检通过（bash 3.2 的地雷藏不住）" "shell locale 核对工具的自检失败"

selfcheck tool/check-deploy.mjs "部署包核对自检通过（端口/日志/加固/占位符都藏不住）" "部署包核对工具的自检失败"

# 工作台（`tool/workbench.mjs`）的自检：它自己不"守卫"任何东西，但它**是你看现状的那一页** ——
# 一页会说谎的现状比没有现状更坏，所以它的解析/渲染/自报家门（"这是样例数据不是真实用户"）
# 都由自检钉着。⚠️ 里面有一条会**在真仓库上跑一次真守卫**：第一版把守卫路径拼错了
# （漏了 `tool/`），13 个守卫全部报红、报的还是一句没头没脑的 `Node.js v22.22.2`。
selfcheck tool/workbench.mjs "工作台自检通过（版本/产物残留/待办/埋点自报家门/业务占位不撒谎/只读/真机解析/真守卫都算得对）" "工作台自检失败"

# 截图"压平"工具（去掉 alpha + 16 位降 8 位）的自检：App Store 只收 8 位无 alpha，
# 而 iOS 模拟器截出来的是 **16 位 RGBA**（2026-09-30 实测）。读的那 5 种 filter
# 也在这里逐种验过 —— 读错了会一路错到商店上传被拒。
selfcheck tool/flatten-png.mjs "截图压平自检通过（16 位降 8 位 / 去 alpha / 5 种 filter）" "截图压平工具的自检失败"

# 隐私政策对账：客户端会发的事件/字段、manifest 权限，都必须与政策正文一致。
# **这是硬门禁** —— 加了一个新埋点字段却不在政策里写清楚，不许合并。
#
# 自检放在对账**前面**：这条门禁里有一半是"政策 ↔ 库"的横切检查（v1.52 起
# 「身体数据」的几个字段要双向点名），而这种检查写错了会**静默通过** ——
# 静默通过的隐私检查比没有更坏。所以先证明它抓得住坏的，再看它对真文件怎么说。
selfcheck tool/privacy-audit.mjs \
  "隐私政策对账自检通过（政策漏字段 / 英文版漏 / 库没列 / fields 丢了 / 身高未点名都抓得住）" \
  "隐私政策对账自检失败（这条规则本身可能已经失效）"
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

# 原型的 token 不能漂（2026-10-10，VI 计划 T1-6）：`app/lib/core/theme.dart` 的文件头写着
# 「三处必须一致」（theme.dart / interaction-spec §4 / prototype 的 CSS 变量），
# 而这条契约从来没有守卫 —— 实测已经漂了三处（--elevated 是冷蓝灰、--pr 是旧琥珀、
# --r-card 20px）。现在原型的 :root 是**生成的**，手改会被这一条打回。
if node tool/gen-prototype-tokens.mjs --check >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 原型的 :root 与 theme.dart 同源"
else
  strip "$LOG"; echo "${RED}✗ 原型的 token 漂了（跑 node tool/gen-prototype-tokens.mjs）${OFF}"; fail=1
fi
echo

# 软著材料里的数字不能漂：说明书与申请表写着「N 个源文件 / M 行」，release-checklist
# 的「终局核验」表里还抄了一份带**页数**的。这些都是要填进申请表、与鉴别材料一起交的。
# VI 稿子的线宽纪律（2026-10-10，VI 计划 T3-7）：客户稿子自己的线宽就有 5 个值
# （`progress-home` 一张里 1.5 / 1.8 / 2 / 3，`tab-icon-system` 整张 1.8），
# 而 VI 交付物最重要的一条是"**下一个照做的人不会做错**" —— 稿子混着，App 就一定会混
# （`app/lib` 曾经 112 个字形 / 12 个尺寸 / 3 套图标族，正是这件事的下游）。
if node tool/check-vi-strokes.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -1; echo "${GREEN}✓${OFF} vi/ 稿子的线宽只有 {2, 2.5, 3}"
else
  strip "$LOG"; echo "${RED}✗ vi/ 稿子的线宽越界（默认 2 / 大色块上的勾 2.5 / 大插画 3）${OFF}"; fail=1
fi
echo

if node tool/copyright-pdf.mjs --check-docs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 软著材料里的源程序量与实际一致（文件数 / 行数 / 页数）"
else
  strip "$LOG"; echo "${RED}✗ 软著材料里的源程序量过期（改文档或重新导出）${OFF}"; fail=1
fi
selfcheck tool/copyright-pdf.mjs "软著文档数字守卫自检（四种漂法都抓得住）" "软著文档数字守卫自检不过"

# CHANGELOG 的结构：版本小节**降序**、**不重复**、且都从**行首**开始。
# 2026-09-30 抓到的：粘到上一行去的标题在 `^## v` 眼里根本不存在，于是"降序"照样成立，
# 守护全程绿灯。当时修了判据，但那段逻辑是写在 bash 里的 `node -e`（**自己没法被测**）——
# 2026-10-01 抽成 `tool/check-changelog.mjs` 并补了 6 条自检。
if node tool/check-changelog.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} CHANGELOG 结构（降序 / 不重复 / 都从行首开始）"
else
  strip "$LOG"; echo "${RED}✗ CHANGELOG 结构不对${OFF}"; fail=1
fi

# 环境文档必须与**磁盘上的真实布局**一致（2026-09-30 补）。
# 起因：依赖搬到 SSD 之后，ROADMAP 里那三个旧路径还带着 ✅ 摆了很久没人发现 ——
# 这类"环境文档漂了"没有任何东西会红，而它会让下一个人按错误路径去找 SDK。
#
# 2026-09-30：用户拍板"CI 直接跑 ./verify.sh"之后，这条要能在 **ubuntu** 上活下来。
# 它核的是「**这台机器上**依赖目录的布局与文档写的一致吗」—— 换一台机器（CI 的
# ubuntu runner）那套 SSD 路径根本不存在，这里无从核起。所以分三种：
#   * 读不到 DEPS            → 红（那是 dev-env.sh 被改坏了，哪台机器都该知道）
#   * DEPS 的**上级目录**不在 → 不适用（这台机器不是那台开发机）——不红也不阻塞，
#                              因为这不是"没验完"，而是"与这台机器无关"。
#                              （CI 上就是这个分支：/Volumes/... 不存在）
#   * 上级目录在、harness-deps 缺 → 红（依赖搬过家而文档没跟着改 —— 这才是要抓的）
DEPS_ROOT="$(grep -oE '^DEPS="[^"]+"' tool/dev-env.sh 2>/dev/null | head -1 | sed 's/^DEPS="//; s/"$//')"
DEPS_PARENT="$(dirname "$DEPS_ROOT")"
if [ -z "$DEPS_ROOT" ]; then
  echo "${RED}✗ 读不到 tool/dev-env.sh 里的 DEPS${OFF}"
  fail=1
elif [ ! -d "$DEPS_PARENT" ]; then
  echo "${DIM}⊘ 不适用${OFF} —— 这台机器上没有 ${DEPS_PARENT}（不是那台开发机，例如 CI）。"
  echo "${DIM}    这条核的是开发机的依赖布局与 docs/dev-environment.md 是否一致，与 CI 无关。${OFF}"
  skipped=$((skipped + 1))
elif [ ! -d "$DEPS_ROOT" ]; then
  echo "${RED}✗ tool/dev-env.sh 的 DEPS 指向不存在的目录（${DEPS_ROOT}）—— 依赖搬过家就要同时改文档与它${OFF}"
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
    echo "${GREEN}✓${OFF} 环境文档列的依赖目录都真实存在（${DEPS_ROOT}）"
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
  echo "${RED}✗ README.md 顶部写的是 v${README_VER}，实际版本是 $APP_VER${OFF}"
  fail=1
else
  echo "${GREEN}✓${OFF} README 顶部的版本号（v${README_VER}）与 app_info.dart 一致"
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
  echo "${RED}✗ docs/your-todo.md 顶部写的是 v${TODO_VER}，实际版本是 $APP_VER${OFF}"
  fail=1
else
  echo "${GREEN}✓${OFF} docs/your-todo.md 的时间戳（v${TODO_VER}）与 app_info.dart 一致"
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
    echo "${RED}✗ $file 里找不到「${label}」（措辞变了？这条守卫已经失效，别当成通过）${OFF}"
    fail=1
  elif [ "$got" != "$APP_VER" ]; then
    echo "${RED}✗ $file 写的是真机装 v${got}，实际版本是 $APP_VER${OFF}"
    fail=1
  else
    echo "${GREEN}✓${OFF} $file 的真机版本（v${got}）与 app_info.dart 一致"
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

# CI 与门禁的关系：2026-09-30 用户拍板"CI 直接跑 ./verify.sh"（在此之前 CI 只是子集，
# 于是"CI 绿"不等于"门禁绿"）。现在核的是：CI 跑的就是这条命令本身、不许加门禁不管的
# 步骤、也不许用 --fast 偷偷跳过某一层，三个版本仍要钉死。
if node tool/check-ci.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} CI 跑的就是门禁本身（命令/触发/版本都对得上）"
else
  strip "$LOG"; echo "${RED}✗ CI 与门禁的关系不对（CI 跑的不是门禁本身）${OFF}"; fail=1
fi
echo

# 守卫接线：每个守卫要么在门禁里直接跑，要么写明"由谁代跑/为什么按需"（名单在工具里，逐条有理由）
if node tool/check-guards-wired.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 没有"存在但从不跑"的守卫"
else
  strip "$LOG"; echo "${RED}✗ 有守卫没在跑（不跑的守卫等于没有）${OFF}"; fail=1
fi
echo

# 文档里的"当前版本"：产物行/设备行/重核行写的版本必须等于 kAppVersion + pubspec 的 build
# （历史叙述跳过 —— 复盘旧版本是正常的）。
if node tool/check-doc-versions.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 文档里陈述现状的版本号都与真源一致"
else
  strip "$LOG"; echo "${RED}✗ 有文档的版本说法过期（过期比没有更坏）${OFF}"; fail=1
fi
echo

# 文档表格：README 与 docs/*.md 里的 markdown 表格必须连着的、每行列数与表头一致
if node tool/check-doc-tables.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 文档表格都规整（连着、列数对）"
else
  strip "$LOG"; echo "${RED}✗ 有表格被截断或错列（这些表是要照着填的）${OFF}"; fail=1
fi
echo

# 文档里的**事实数字**：`schema vN` / 内置动作数 / 埋点事件数 / 公共字段数，必须等于仓库里
# 算得出来的真源（`db.dart` 的 schemaVersion、动作库、埋点清单……）。
#
# ⚠️ **2026-10-09 才补上这一跑 —— 这条守卫此前是"假的"**：它只有上面那段 `selfcheck`
# （跑的是工具自己的 `--selftest`），**真实的扫描一次都没在门禁里跑过**；
# 而 `check-guards-wired.mjs` 判"守卫有没有在跑"时，把 `selfcheck <路径>` 也算成"直接跑"，
# 于是两边都以为这块有人守着。实际上 `docs/release-checklist.md` 里那句
# 「中间夹着 schema v22→v24 两步迁移」早就过期了（真源是 24），漂了不知多少天没人红 ——
# 是 2026-10-09 查 HealthKit 那件事时手动跑了一次真实扫描才发现的。
if node tool/check-doc-facts.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 文档里的事实数字（schema/动作数/事件数/公共字段）都与真源一致"
else
  strip "$LOG"; echo "${RED}✗ 有文档的事实数字与仓库对不上（它们要能用仓库算出来）${OFF}"; fail=1
fi
echo

# 脚本里 `$VAR` 后面**紧邻非 ASCII 字符**：macOS 自带 bash 3.2 在 UTF-8 locale 下会把那个
# 字符的字节吞进变量名，`set -u` 当场 `unbound variable` —— 而这类脚本多半是在"已经改完工程、
# 正在装包"的中途炸掉（最难受的位置）。修法永远只是补一对花括号（`$VAR（` → `${VAR}（`）。
#
# ⚠️ 与上面那条同一个毛病：2026-10-09 之前它**也只有自检在跑**，真实扫描从没跑过。
# 补上之后当场抓到 `tool/ios-device-run.sh` 里 5 处 —— 那正是装真机用的那个脚本。
if node tool/check-shell-locale.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} shell 脚本里没有 \$VAR 紧邻中文的坑（bash 3.2 会吞字节）"
else
  strip "$LOG"; echo "${RED}✗ 有 shell 脚本的 \$VAR 后面紧邻非 ASCII 字符（补一对花括号）${OFF}"; fail=1
fi
echo

# 文档路径：README 与 docs/*.md 里带斜杠的路径引用必须真的存在
# （裸文件名、构建产物、URL、占位符、以及"不在仓库里"的名单都跳过 —— 名单要写理由）。
if node tool/check-doc-paths.mjs >"$LOG" 2>&1; then
  strip "$LOG" | tail -2; echo "${GREEN}✓${OFF} 文档里引用的路径都存在"
else
  strip "$LOG"; echo "${RED}✗ 文档里有指空的路径引用${OFF}"; fail=1
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
  [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} Dart 领域层通过" || { echo "${RED}✗ Dart 领域层失败（退出码 ${rc}）${OFF}"; fail=1; }
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
  # ⚠️ **两个 import 都要看**（2026-10-01 修）：判据原先只认 db.dart 上的 hide/show、
  # 或 models 上的 as —— 而 `import 'models.dart' show PlanTarget;` 同样消除了歧义
  # （models 只放进来一个名字，重叠的 Workout/SetRecord 只能来自 db.dart）。
  # 那次误报打在 routine_repository.dart 上：文件本身是对的，判据不全。
  dbimp=$(echo "$flat" | grep -oE "import '[^']*db\.dart'[^;]*;" | head -1)
  modelimp=$(echo "$flat" | grep -oE "import '[^']*models\.dart'[^;]*;" | head -1)
  echo "$dbimp" | grep -qE ' (hide|show|as) ' && continue
  echo "$modelimp" | grep -qE ' (hide|show|as) ' && continue
  echo "  ${RED}✗${OFF} ${f#app/}：db.dart 与 models.dart 裸 import —— 至少要在一处写 hide / show / as"
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
  [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 静态分析零问题" || { echo "${RED}✗ 静态分析有问题（退出码 ${rc}）${OFF}"; fail=1; }
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
    [ "$rc" -eq 0 ] && echo "${GREEN}✓${OFF} 应用层通过" || { echo "${RED}✗ 应用层测试失败（退出码 ${rc}）${OFF}"; fail=1; }

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
         tool/check-usability-tasks.mjs usability/tasks.json \
         tool/preset-history.mjs usability/preset-6-weeks.json \
         tool/privacy-audit.mjs docs/privacy-facts.json docs/release-admin.md \
         tool/copyright-export.mjs docs/store-listing.md \
         usability/记录表.md usability/participants.example.json \
         usability/真机自测表.md \
         tool/check-shell-locale.mjs tool/map-upstream.mjs tool/add-upstream-exercises.mjs docs/exercise-mapping.md \
         app/pubspec.yaml app/lib/main.dart \
         app/ios/Runner/PrivacyInfo.xcprivacy \
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
         tool/check-user-text.mjs tool/check-doc-paths.mjs tool/check-doc-tables.mjs \
         tool/check-doc-versions.mjs tool/check-guards-wired.mjs \
         tool/flatten-png.mjs tool/lib/png.mjs tool/lib/plist.mjs tool/check-deploy.mjs \
         tool/check-changelog.mjs tool/check-doc-facts.mjs tool/lib/android-sdk.mjs tool/lib/docs.mjs \
         server/deploy/install.sh server/deploy/Caddyfile \
         server/deploy/lianleme-backend.service server/deploy/lianleme-collector.service \
         tool/ios-deps.mjs docs/store-listing-ios.md docs/your-todo.md \
         docs/feature-backlog.md \
         tool/gen-feature-graphic.py store-assets/feature-graphic-1024x500.png \
         app/test/progression_vectors_test.dart app/test/tap_meter_test.dart \
         app/test/workout_flow_test.dart app/test/backup_test.dart \
         app/test/time_exercise_test.dart app/test/progression_wiring_test.dart \
         app/integration_test/share_card_gallery_test.dart \
         app/test/home_entry_test.dart app/test/app_version_test.dart \
         app/test/today_plan_test.dart \
         app/test/analytics_export_test.dart \
         .github/workflows/ci.yml; do
  [ -f "$f" ] && printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$f" || { printf '  %s✗ 缺失%s %s\n' "$RED" "$OFF" "$f"; missing=1; }
done
[ "$missing" -eq 0 ] || fail=1
echo

if [ "$fail" -eq 0 ]; then
  echo "${GREEN}${BOLD}未发现失败。${OFF}"
  [ "$blocked" -eq 1 ] && echo "${YELLOW}但有步骤被环境阻塞，未完成验证。${OFF}"
  [ "$skipped" -gt 0 ] && echo "${DIM}另有 $skipped 项与这台机器无关，已跳过（不是没验，是这台机器上无从核起）。${OFF}"
  echo "${DIM}下一步：open prototype/index.html 看原型；或读 docs/usability-test-kit.md 去招人做测试。${OFF}"
else
  echo "${RED}${BOLD}有检查未通过，见上方输出。${OFF}"
fi
exit "$fail"
