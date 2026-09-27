# 练了么

[![CI](https://github.com/sdknwdtvpv-sys/sport/actions/workflows/ci.yml/badge.svg)](https://github.com/sdknwdtvpv-sys/sport/actions/workflows/ci.yml)

> 训记的竞品。不靠功能更多取胜，靠**把"记录一组"的成本压到 1 次点击**，并让"今天练什么"不需要用户自己想。
>
> 完整产品定义见 [`PRODUCT.md`](PRODUCT.md)。

---

## 30 秒上手

需要 **Node 18+**；跑 Flutter 测试需要 **Flutter SDK**（stable）。

```bash
./verify.sh                        # 自检全部产物（契约层 + 领域层 + 应用层）
open prototype/index.html          # 看 4 张核心屏（第 3 屏可交互）

dart app/tool/check_domain.dart    # 验证 Dart 引擎与 JS 引擎一致（零依赖，不需要 pub）
cd app && flutter test             # 再加上 widget 测试（需要能跑通 pub get）
```

手机上打开 `prototype/index.html` 会自动排成单列 —— 可以直接把手机递给别人演示。

---

## 验证现状

| 门禁 | 命令 | 结果 |
|---|---|---|
| 动作库种子（165 个动作，字段/枚举/步长一致性校验） | `node seed/build.mjs` | ✅ 通过 |
| JS 规则引擎（28 向量 + 3 红线 + 4 条 1RM） | `node engine/run-tests.mjs` | ✅ 35/35 |
| Dart 规则引擎（**同一份** `engine/vectors.json`） | `dart app/tool/check_domain.dart` | ✅ 41/41 |
| 静态分析（最严格档，info 级也算失败） | `cd app && dart analyze --fatal-infos` | ✅ **No issues found!** |
| Flutter widget 测试（交互红线 + `tap_count` 边界） | `cd app && flutter test` | ✅ **49/49** |

三层引擎校验共用同一份 `engine/vectors.json`，所以「Dart 与 JS 行为一致」是被证实的**事实**，不是声称。
`flutter test` 的 49 项 = 34 项引擎向量/红线/1RM + 6 项 `tap_count` 边界 + 9 项 widget 交互测试。

以上 5 层已在 CI 上跑通（[首次运行](https://github.com/sdknwdtvpv-sys/sport/actions) 2m 4s，两个 job 全绿）。
这意味着整套验证在**从零 clone 的干净 Linux 环境**里同样成立，不依赖任何本机配置 ——
中文目录只影响本机的 `flutter analyze`，不影响 CI。

**尚未验证**：drift 持久化、真实埋点上报、iOS/Android 构建都还没接线。

> **下一步做什么** → [`ROADMAP.md`](ROADMAP.md)：6 个阶段，每步都有命令与可验收的完成标准。
> 其中**阶段 3「自己练一次」不要跳过** —— 成本是一次训练，产出是核心假设的第一个真实信号。

## 这个仓库现在是什么

**它不是一份文档，也不是一个完整产品。它是一个"契约仓库"：每一层都用可执行的东西锁住。**

| 层 | 产物 | 可执行？ | 谁验收 |
|---|---|---|---|
| 产品定义 | `PRODUCT.md` | 散文 | 创始人 / 合伙人 |
| 交互 | `prototype/index.html` + `docs/interaction-spec.md` | **原型可交互 + widget 测试** | 设计 / 客户端 |
| 数据 | `docs/data-model.md` + `seed/exercises.sql` | **可执行**：sqlite3 直接导入 165 条 | 客户端 / 后端 |
| 规则引擎 | `engine/progression.mjs` + `app/lib/domain/progression.dart` | **双实现 + 共用 28 条向量** | 客户端（移植验收标准） |
| 埋点 | `docs/analytics.md` + `docs/analytics-sdk.md` | 规格 + `tap_count` 有单测 | 客户端 / 数据 |
| 验证 | `docs/usability-test.md` + `-kit.md` | 流程手册，可照做 | 你本人 |

**这个仓库最重要的一条设计**：Dart 与 JS **共用同一份 `engine/vectors.json`**，不复制。
于是"移植是否完成"成了一个可判定的事实 —— `./verify.sh` 全绿就是一致，没有解释空间。

```
engine/vectors.json ──┬──> engine/run-tests.mjs        （Node）
                      └──> app/test/progression_vectors_test.dart（Dart）
```

---

## 按角色怎么用

### 你是产品 / 创始人 —— 要当面说服别人

1. 打开 `prototype/index.html`，**当面演示第 3 屏**：点大按钮记一组 → 倒计时跑起来 → 长按 → 弹层改重量。40 秒胜过任何 PPT。
2. 电梯陈述在 `PRODUCT.md` §0–§6。
3. 要拿真实数据说话：按 `docs/usability-test-kit.md` 招 5 个人。**第 6 节"训记对照环节"是关键** —— 让被试用自己的训记做同一件事，直接比出省事程度。

### 你是客户端开发（Flutter）—— 要开工

工程已经在 `app/`，跑起来就能看到实现：

| 步骤 | 看什么 | 做完的标准 |
|---|---|---|
| 1 | `docs/tech-decisions.md` | 确认选型（Flutter + 原生 Swift 扩展）与合规红线 |
| 2 | `docs/data-model.md` | 建库；`seed/exercises.sql` 导入 165 条 |
| 3 | `app/lib/domain/progression.dart` | 改引擎后 `flutter test` 必须全绿 —— 28 条向量是你唯一的验收标准 |
| 4 | `app/lib/features/workout/` | 对照 `docs/interaction-spec.md` 扩展其余屏 |
| 5 | `docs/analytics-sdk.md` | 把 `RecordingAnalytics` 换成真实 SDK，§3.5 的边界用例已成 widget 测试 |

**当前工程刻意只做了一件事**：把引擎、交互红线、埋点计量这三样"最容易做坏"的东西用测试锁住。
UI 只实现了 S1 / S4 / S5，动作只有杠铃卧推一个 —— 这是有意的，不是没写完。

### 你是后端开发

- `docs/data-model.md` 全局约定：客户端生成 UUID 主键、每表带 `updated_at` + `deleted_at`、last-write-wins
- `docs/analytics-sdk.md` §1 数据流、§5 上报策略、§6 事件优先级（**P0 不能丢**）
- `docs/tech-decisions.md`：一期只做账号 / 增量同步 / 云备份，**不做实时协同、不做服务端计算**

### 你是数据 / 增长

- `docs/analytics.md`：事件字典 + 北极星定义（首次 `app_open` 起 24h 内完成含 ≥1 组的训练，目标 ≥55%）+ 看板布局
- **必须知道的治理规则**：`set_logged.tap_count` 中位数 > 1 或 P90 上升，**该版本不允许发布**
- `tap_kinds` 回答"点击花在哪了"；§5「反指标」列了四种"出现即停下讨论"的情况

### 你是 QA / 测试

- `./verify.sh` 作为统一回归入口
- `app/test/workout_flow_test.dart` —— 交互红线的自动化版本（9 个 widget 测试）
- `app/test/tap_meter_test.dart` —— `tap_count` 的 6 条边界用例
- `docs/interaction-spec.md` §12 设计验收清单 / `docs/analytics-sdk.md` §12 接入验收清单
- `docs/usability-test-kit.md` —— 可用性测试现场手册

---

## 常用命令

```bash
./verify.sh                        # 全部自检（推荐入口）

node seed/build.mjs                # 重建动作库种子；校验失败即非 0 退出
node engine/run-tests.mjs          # JS 规则引擎向量（35 项）
dart app/tool/check_domain.dart    # Dart 引擎 vs 同一份向量（41 项，零依赖）
cd app && dart analyze --fatal-infos        # 静态分析（不要用 flutter analyze，见下）
cd app && flutter test                      # widget 测试（需要 pub）
```

改动作库：编辑 `seed/parts/*.json` → `node seed/build.mjs` → `exercises.json` 与 `exercises.sql` 自动重建。
改引擎规则：**先改 `engine/vectors.json`**（加一条向量），再改 `engine/progression.mjs` 与 `app/lib/domain/progression.dart`，两边都跑绿才算完成。

---

## 在受限环境里（比如没有网络、或不能删除文件）

`flutter test` 需要先跑通 `flutter pub get`，而 pub 会清理自己的临时目录并访问 pub.dev。
在受限环境里这步会失败。这时**领域层仍然可以完整验证**，因为它是纯 Dart 的：

```bash
dart app/tool/check_domain.dart
```

它跑的是同一份 `engine/vectors.json`，外加 3 条硬红线和 tap_count 边界 ——
也就是"Dart 引擎是否与 JS 引擎一致"这个最关键的结论，不依赖网络就能被证实。
只有 widget 测试需要 Flutter 测试框架，那种情况下 `./verify.sh` 会把应用层标记为
**阻塞而不是通过**，并在结尾明确提示"有步骤未完成验证"。

## 已知工具链问题：`flutter analyze` 在中文路径下必崩

本仓库目录名是中文，而 **Flutter 3.47 的 `flutter analyze` 遇到非 ASCII 路径会崩溃**
（[flutter/flutter#191309](https://github.com/flutter/flutter/issues/191309)）：

```
FormatException: Unexpected end of input (at character 328)
...%E4%BA%86%E4%B9%88/app/"}],"capabilities":{"window":{"workDoneProgress":tr
analysis server exited with code 255
```

**这不是代码问题。** `dart analyze` 走同一套 `analysis_options.yaml`，只是绕过了 flutter_tools
的 LSP 客户端，结果是 `No issues found!`（`--fatal-infos` 最严格档）。

- **本项目一律用 `dart analyze`** —— `verify.sh` 与 CI 都是这样。
- 若你确实需要 `flutter analyze`：把目录改成纯 ASCII 名即可。**源码里没有任何硬编码绝对路径**
  （只有可再生的 `app/.dart_tool/package_config.json` 里有），改名是安全的。
- CI 不受影响：GitHub runner 的工作目录本来就是 ASCII。
- 这与 pub 无关 —— 加 `--no-pub` 仍然崩。

## 现在还没有的东西（别期待）

| 缺什么 | 为什么 | 影响 |
|---|---|---|
| ❌ 可安装的 App | 没有 iOS/Android 构建配置与签名 | 只能用 HTML 原型演示 |
| ❌ 持久化接线 | 引擎/交互优先；drift 会引入 build_runner 代码生成，让 CI 首次运行多一个失败点 | 数据在内存里，重启即失 |
| ❌ 真实埋点上报 | 只有 `RecordingAnalytics`（内存） | 看板还没有数据源 |
| ❌ 后端接口 | 一期极薄，还没开始 | — |
| ⚠️ UI 只有 3 屏、动作只有 1 个 | 刻意收窄，优先锁住易坏的部分 | 不能拿来做真实训练 |

---

## 建议的下一步优先级

1. **跑可用性测试**（5 人）。唯一需要人力的环节，也是唯一能证伪核心假设的手段。
2. **接 drift**：实现 `LocalStore` 接口即可，调用方一行不用改；`docs/data-model.md` 的 DDL 已可直接用。
3. **把 UI 铺到 `docs/screens.md` 的 15 屏**，每铺一屏补对应的 widget 测试。

> 在测试数据出来之前，不建议扩张功能面。若 T1 通过率或 `tap_count` 中位数不达标，现在这批文档与代码里有一半要改。
