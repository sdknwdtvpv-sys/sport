# 练了么 · 实施路线图

> 本文件与代码同步维护。测试数 **145**（构成见 `README.md` 的「验证现状」）。

---

## 一眼看懂

| # | 阶段 | 状态 | 卡在谁那 |
|---|---|---|---|
| **0** | 钉住工程：git + CI 真跑起来 | ✅ 完成 | — |
| **1** | 数据活过重启（接 drift） | ✅ 完成（只剩真机验证） | 阶段 2 |
| **2** | 装到真机 | ⬜ 未开始 | **需要你装 Android 工具链** |
| **3** | **自己去练一次** | ⬜ 未开始 | 阶段 2 |
| **4** | 铺 UI 屏 | 🚧 进行中（6 屏里完成 5 屏） | 部分不依赖手机 |
| **5** | 招 5 人做可用性测试 | ⬜ 未开始 | 招募只占日历，可随时启动 |
| **6** | 真实埋点上报 | ⬜ 未开始 | — |

**唯一的硬依赖链**：`3 → 2 → 你装 Android 工具链`。其余都可以并行或调序。

---

## 阶段 0 · 钉住工程 ✅

**做完了什么**：仓库 `sdknwdtvpv-sys/sport`，CI 两个 job（契约层 + 应用层）全绿。
第一次跑 2m 8s，之后 56s（Flutter SDK 缓存命中）。CI 里锁了 Flutter 3.47.5 与 `ubuntu-24.04`。

**这一步的意义**：把"你本地跑过一次"变成了"每次提交都自动跑"。

---

## 阶段 1 · 数据活过重启 ✅（剩一条真机验证）

**做完了什么**：drift 落库（4 张表 + 3 个索引）+ 契约测试（19 条断言 × 2 个实现 = 38 项）。
`.g.dart` 不提交、由 CI 生成 —— 提交了会悄悄过期，忽略了会大声报错。

**唯一未验的**：
- [ ] 杀掉 App 重开，之前的组记录还在 ← 要等阶段 2

**依赖的正确版本**（`app/pubspec.yaml` 里已是这些）：
```yaml
dependencies:
  drift: ^2.35.0
  drift_flutter: ^0.3.1
dev_dependencies:
  build_runner: ^2.16.1
  drift_dev: ^2.35.0
```

> ⚠️ **不要加 `sqlite3_flutter_libs`**。它已终止维护（最新版号 `0.6.0+eol`），
> pub.dev 上的描述写着 "Not used anymore, update to version 3.x of package:sqlite3 instead"。
> 原生库现在由 `sqlite3` 3.x 自己构建，而 `drift_flutter` 已经传递依赖它。
> 几乎所有 drift 教程都还在教你加这个包。

---

## 阶段 2 · 装到真机 ⬜

**前置条件（我查过了，你机器上一个都没有）**：
```
Java          ✗ 未找到
安卓 SDK      ✗ 未找到
adb           ✗ 未找到（连手机用的）
Android Studio ✗ 未安装
```

**所以第一步不是连手机，是装 Android Studio**（约 1GB 安装包 + 几 G SDK，半小时到一小时）。
它会把 Java、SDK、adb、模拟器一次带齐：https://developer.android.com/studio

装完验证：
```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter doctor                    # 应看到 [✓] Android toolchain
flutter doctor --android-licenses # 提示没接受许可时跑，一路 y
```

**然后生成平台目录**：
```bash
cd /Users/elliot/Harness/练了么
git add -A && git commit -m "chore: 阶段 2 前的快照"   # 先存档，改坏能一键还原

cd app
flutter create --org com.你的反域名 --project-name lianleme --platforms=ios,android .

cd ..
git status --short                # 看它改了什么
git diff app/pubspec.yaml         # 最关键：assets 与 drift 依赖还在吗？
```

若 `pubspec.yaml` 被重写（丢了 `assets:` 或 drift 依赖）：
```bash
git checkout -- app/pubspec.yaml && cd app && flutter pub get
```

`--org` 换成你自己的反向域名（如 `com.sdknwdtvpv`），它会写进 iOS bundle id 与
Android applicationId，后期改很麻烦。

**在手机上跑**：
1. 手机「设置 → 关于手机 → 连点 7 次版本号」→ 成为开发者
2. 「设置 → 系统 → 开发者选项 → 打开 USB 调试」
3. 数据线插电脑，手机上点「允许 USB 调试」
4. `flutter devices` 确认电脑认得出手机，然后 `flutter run`

**完成标准**（后两条专门验证已修的两个 bug）：
- [ ] 手机上出现 App，点「开始今天的训练」进到今日建议卡
- [ ] 「我自己选」能搜（试 `bp`、`rdl`），点一个动作进训练屏，点大按钮记一组
- [ ] **练两个动作**（卧推 → 返回 → 深蹲），两组都在
- [ ] **杀掉 App 重开** —— 组一条不少（验证 id 撞主键的修复）
- [ ] 重开后进同一动作，能看到「上次 xx kg × n」（验证 workout 行落库的修复）

**注意**：iOS 真机要配 Apple 签名，**先用 Android 最快**。

---

## 阶段 3 · 自己去练一次 ⬜（性价比最高的一步）

**前置条件已全部就绪**：多动作、动作选择、数据持久化都做完了。

带上手机去健身房，**真的用完整一次训练**（≥3 个动作、12 组）。成本是一次训练，
产出是"核心假设成不成立"的第一个真实信号。

**要刻意观察的**：
- [ ] 单手、出汗、注意力在器械上时，点得到那个大按钮吗？
- [ ] 组间那 60 秒里，哪一步让你烦了？哪怕只是"多看了一眼"
- [ ] 休息倒计时你真的在看，还是根本不看？
- [ ] 动作切换顺手吗？会迷路吗？
- [ ] 长按改重量你用得上吗？
- [ ] **练完你想不想点开"进步"页？** 不想的话，说明数据展示的价值判断错了

**记录方式**：练完当天写下**最烦的那一个瞬间**。不要记"整体感觉不错"——那没有信息量。

**结果分岔**：
- 顺手 → 继续铺屏
- 某一步明显卡 → **先修那一步，再铺屏**
- 根本不想用第二次 → 停下来重审核心假设，此时沉没成本还很小

---

## 阶段 4 · 铺 UI 屏 🚧（6 屏完成 5 屏）

> 顺带修了一个真 bug：**空态永远显示「还没有训练记录」**——
> `lastWeekSessions` 从没被传过值，练完回来它还是这么说。

> 顺带把**假的 Tab 栏做成了真的** —— 那三个 Tab 之前是装饰性的、点不动。
> 假的可点按元件比没有更糟，所以外壳（`HomeShell`）现在持有 Tab 状态。

| 顺序 | 屏 | 状态 | 说明 |
|---|---|---|---|
| 1 | **S2 今日建议卡** | ✅ 完成 | 逻辑（`TodayPlanner`）+ 界面 + 串进导航 |
| 2 | **S7 训练结束总结** | ✅ 完成 | 三项大数 + 破纪录判定 |
| 3 | S7 分享卡图片 | ⬜ 推迟 | `RepaintBoundary.toImage()` + 相册写入，**需要平台通道，我在本机无法验证**，所以不做"看起来完成了但没人跑过"的代码 |
| 4 | **S8 进步** | ✅ 完成 | 本周容量曲线（自绘，不引图表库）+ PR 墙。**体重没做** —— 需要 `body_metric` 表与录入界面（S12），是另一块工作 |
| 5 | **S10 我** | ✅ 完成 | 训练统计 / 渐进建议开关（真落库）/ 全量 CSV 导出到剪贴板 |
| 6 | S3 / S4 / S5 打磨 | ⬜ 未开始 | 动作选择页与训练主屏已能用，属打磨 |

**每屏的完成标准**：`dart analyze --fatal-infos` 零问题 + `flutter test` 全绿
+ 一条针对该屏核心行为的新 widget 测试。

**红线不变**（`app/README.md` 有表）：1 次点击 = 1 组、长按不误记、离线可用。

---

## 阶段 5 · 招 5 人做可用性测试 ⬜

按 `docs/usability-test-kit.md` 执行，**重点是第 6 节那个对照环节**：让被试用自己的训记
做同一件事，直接比出省事程度。

**这一步只占日历、不占工时**，所以尽早启动招募。

**必须拿到的 7 个数字**（`docs/usability-test-kit.md` §8）：T1 通过率 / T1 中位耗时 /
**记录一组的 tap_count 中位数** / 打字次数 / 滚动次数 / T6 采纳情况 / Q3 选择本品人数。

拿到后回填 `docs/analytics.md` 的目标值——现在那个 55% 与 `tap_count = 1` 都是估计值，
文档里已标注"待校准"。

---

## 阶段 6 · 真实埋点上报 🚧（客户端部分完成）

**已完成**：
- `analytics_outbox` 表 + `AnalyticsOutboxStore`（入队 / 取批次 / 失败累加 / parked / 溢出丢弃）
- `AnalyticsFlusher`：批量 ≤100、重试 1s/4s/16s + 抖动、连续 3 次失败 parked、冷启动放行
- `AnalyticsTransport` 三实现：接口 / 假传输（测试）/ `HttpAnalyticsTransport`（真身）
- `OutboxAnalytics`：`track()` 同步返回、绝不抛异常、尊重隐私开关
- 优先级 P0/P1/P2 映射
- **训练期间挂起**（`_flusher.suspend()` / `resume()`）—— 红线落进代码，不只写在文档里
- S10 加了「帮助改进产品」开关（关掉立刻生效 + 落库）
- **26 项测试**，含**用本地环回 HttpServer 验证真实 HTTP 传输**

**剩余**：
- [ ] 接真实上报地址（`main.dart` 的 `_NullTransport` → `HttpAnalyticsTransport`）
- [ ] **手工抓包验证"训练中零请求"** —— 测试覆盖不到，只能真机抓
- [ ] `docs/analytics-sdk.md` §12 的 11 项验收清单逐条打勾

> 没后端时用 `_NullTransport`（永远失败）：事件留在本地 outbox 不丢，
> 所以"到底有没有记下来"是可验证的；直接不上报反而看不出区别。

---

## 我们偏离过原计划的地方（记下来，不装作没发生）

1. **跳过了阶段 3 先做阶段 4。**
   原计划是"阶段 3 优先级最高，不要先铺 12 屏"。但阶段 2 卡在"要装 Android 工具链"上，
   你选了先做 UI。**代价是：阶段 4 铺的屏目前基于我的假设，没有真实使用信号。**
   缓解办法是排序——优先做"逻辑已经就绪"的屏（S2 的引擎、S7 的统计），
   把"价值判断型"的屏（S8 进步页）留到真练过之后。

2. **S7 的分享卡没做。** 需要平台通道，无法在本机验证，宁可空着也不写没跑过的代码。

3. **测试数我数错过。** 契约测试是"每条断言 × 2 个实现"，我加断言时只按 1 条算，
   README 里一度写低了。已修正并加了提醒。

---

## 教训清单（避免重犯）

**drift 的 API 已经猜错五次。别再猜** —— 源码在
`~/.pub-cache/hosted/pub.dev/drift-<版本>/lib/`，签名一行 grep 就有。

已踩过的：
1. 伴生类叫 `<Table>Companion`，不是 `<Table>UpdateCompanion`（后者只是基类）
2. `withDefault()` 只加 SQL 层 DEFAULT，Dart 数据类字段**仍是 `required`**
   —— **这个坑我踩了两次**（先 `SetRecordData.isPr`，后 `UserProfileData.unitPref`）。
   现在 `app/tool/check_drift_params.py` 会从生成文件反查必填参数、逐个调用点比对，
   已接进 `verify.sh`，不再靠记性。
3. `where` / `orderBy` / `limit` **全部返回 `void`**，不能链式 `.get()`
4. `Value` 只在 `package:drift/drift.dart` 里，`drift/native.dart` 不导出
5. `.not()` 不存在（所以排除逻辑放到 Dart 里做）

**改过表结构之后必须先重跑代码生成**，否则分析与测试都报 "Target of URI doesn't exist"：
```bash
cd app && dart run build_runner build
```
（`*.g.dart` 刻意不提交 —— 提交了会悄悄过期，忽略了会大声报错。）

**还有一条**：**改完一处错要顺手扫一遍同类**（`hide` 的歧义错误犯过两次，
`withDefault` 的必填参数也犯过两次）。两次都固化成脚本了，见 `verify.sh`。

**其他两条**：
- **同一个错修完要扫一遍同类**：`hide` 那个歧义错误我在一个文件修过，却没检查其他文件，
  结果又炸了一次。现在 `verify.sh` 里有一条 1 秒的自动检查。
- **断言涉及具体数据时，先用 Python 拿真实种子推演一遍**再交给别人跑。
  这条抓到过"按名称检索其实匹配到了别名"这种编译器和分析器都看不见的错。

---

## 一张图看懂顺序

```
阶段0 git+CI ✅ ──▶ 阶段1 drift ✅ ──▶ 阶段2 真机 ⬜ ──▶ 阶段3 自己练一次 ⬜
                                            ▲                    │
                                    需要你装 Android 工具链        │
                                                                 ▼
阶段4 铺屏 🚧（S2 ✅ S7 ✅ ／ 剩余待定）◀──────────────── 按真实感受修
       ▲
阶段5 招人测试 ⬜ ── 可随时启动（只占日历不占工时）

阶段6 真实埋点 ⬜ ── 依赖阶段 4 收尾
```
