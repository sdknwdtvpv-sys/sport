# 练了么 · 埋点 SDK 接入清单

> 指标定义与看板见 `docs/analytics.md`。本文是**开发照着接就行**的实现规格。
> 第一原则：**埋点永远不能拖慢"1 次点击记一组"。** 任何与之冲突的实现都是错的。

---

## 1. 数据流与分层

```
业务代码
   │  track(event, props)          ← 唯一写入入口，同步、无 IO、无网络
   ▼
TapMeter（交互计量器）              ← 只负责 tap_count
   │
   ▼
Outbox（本地 SQLite 表）            ← 落盘，断电不丢
   │
   ▼
Flusher（批量上报器）               ← 有网 + 不在训练中 才触发
   │
   ▼
服务端 /analytics/batch
```

**关键约束**：`track()` 必须是**纯内存操作 + 一次本地插入**，调用方不需要 await，不返回 Future。任何在 `track()` 里发起网络请求的实现都必须打回。

---

## 2. 业务侧最小 API

**只暴露 4 个方法。** API 面越大，埋点越容易污染业务逻辑。

```dart
abstract class Analytics {
  /// 记录事件。同步返回，绝不抛异常，绝不阻塞 UI。
  void track(String event, [Map<String, Object?> props = const {}]);

  /// 开始一次"记录一组"的交互计量
  void beginSetInteraction();

  /// 本次交互中发生了一次点击。kind 见 TapKind
  void countTap(TapKind kind);

  /// 取出并清零本次交互的计量（在 set_logged 之前调用）。
  /// 返回 count + kinds —— 只看总数无法回答"这些点击花在哪了"。
  TapMeterReading flushTap();

  /// 立即尝试上报（仅在训练结束 / 进入后台 / 冷启动后调用）
  Future<void> flush({bool force = false});
}

enum TapKind { bigButton, longPress, stepper, sheetConfirm, keyboard }
```

**不暴露的东西**：不加 `setUserId` 之外的任何 setter，不做 `Analytics.instance.trackA/trackB` 之类的语义封装。事件名由埋点字典决定，不允许业务侧自由命名。

---

## 3. ★ `tap_count` 采集方案（本 SDK 最容易做错的地方）

### 3.1 为什么它重要

`tap_count` 中位数是整个产品"less is more"原则的**唯一客观守卫**。它算错，发版闸门就失效。

### 3.2 计量器的生命周期

```dart
class TapMeter {
  int _count = 0;
  bool _active = false;
  final _kinds = <TapKind>[];

  void begin() { _count = 0; _kinds.clear(); _active = true; }

  void tap(TapKind k) {
    if (!_active) return;   // 不在交互周期内的点击一律忽略
    _count++;
    _kinds.add(k);
  }

  ({int count, List<TapKind> kinds}) flush() {
    final r = (count: _count, kinds: List<TapKind>.from(_kinds));
    _count = 0; _kinds.clear(); _active = false;
    return r;
  }
}
```

### 3.3 计时边界（**必须严格按此实现**）

**口径是端到端的**（2026-09-29 修正，理由见 `analytics.md` §3）：周期从"用户决定练这个动作"
开始，到这一组被记录为止。所以开启周期必须**早于导航**。

| 时机 | 动作 |
|---|---|
| 用户按「开始今天的训练」 | `begin()` —— **必须在这里开**，控制器要等导航走完才被构造 |
| 用户走 S13 引导并以「开始练」收尾 | `begin()` |
| 控制器构造（`WorkoutController`） | `ensure()` —— **不能 `begin()`**：那会把导航点击清零 |
| 大按钮点按产生一次记录 | `tap(bigButton)` |
| 长按大按钮触发弹层 | `tap(longPress)` —— **长按算一次点击**，用户确实按了 |
| 弹层里每次步进 | `tap(stepper)` |
| 弹层「确定」 | `tap(sheetConfirm)` |
| 建议卡「就用这个，开始练」/「我自己选」 | `tap(nav)` |
| 从动作库选中一个动作 | `tap(exercisePick)` |
| 切换动作（底部条点按或左右滑动） | `tap(exerciseSwitch)` |
| 键盘输入（若将来启用） | `tap(keyboard)` |
| 记录成功、写 `set_logged` 前 | `flushTap()` → 上报 `tap_count` 与 `tap_kinds` |
| 记录成功之后 | `begin()` —— 开启下一组的周期 |

**计数的边界定义**（实现后才发现原表述有歧义，以此为准）：
一次 `tap_count` 周期从 `begin()` 开始，到**该组被大按钮记录**为止。
调整（长按 + 步进 + 确定）若发生在记录之前，全部计入这一组；
若用户先记录、再调整，则算作下一组的周期。

> `ensure()` 的语义：周期没开就开、开着就什么都不做。它存在只为了一件事 ——
> 让"控制器被构造"这个纯粹的实现细节**不影响用户看到的数字**。

### 3.4 明确**不计入**的操作

休息「跳过」、Tab 切换、返回、滚动浏览、查看历史、S13 引导中间选目标/频率的那几步
（那是搭计划，不是记这一组）。

> 修订说明：原文把**动作切换**也列在"不计入"里。按端到端口径它必须计入 ——
> 用户为了得到下一组确实多操作了一次，而且"底部条到底有没有用"正是产品要回答的问题。
> 滑动严格说不是"点击"，但与点一下是同一个动作意图、代价相当，按 1 次计。

### 3.5 必须覆盖的边界用例（写单测）

| 用例 | 期望 |
|---|---|
| 连点大按钮 2 次 | 产生 2 条 `set_logged`，**各自 `tap_count = 1`**（两次独立周期） |
| 长按 → 步进 → 确定 → 点大按钮 | `tap_count = 4`（1 长按 + 1 步进 + 1 确定 + 1 记录） |
| 长按 → 确定 → 点大按钮（未调步进） | `tap_count = 3` |
| 点大按钮后点「跳过」休息 | 下一组 `tap_count = 1`，跳过不计入 |
| 记录后撤销再记录 | 第一条 `tap_count = 1`，第二条 = 1，撤销单独上报 `set_undone` |
| 中途切到别的 App 再回来 | 周期内计数保留，不重置（用户仍在处理这一组） |
| **先 `begin()` + `tap(nav)` 两次，再构造控制器，再点大按钮** | **`tap_count = 3`** —— 构造时的 `ensure()` 绝不能清零 |
| **切换动作后记一组** | **`tap_count = 2`**（1 切换 + 1 记录），且 `tap_kinds = [exercise_switch, big_button]` |

> 最后一条是取舍：切走再回来说明用户在处理同一组，计数应连续。若实测发现这会让中位数虚高，再改为"切后台即 flush"。

---

## 4. Outbox 表结构

```sql
CREATE TABLE analytics_outbox (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  payload     TEXT NOT NULL,          -- 完整事件 JSON
  priority    INTEGER NOT NULL,       -- 0=P0 1=P1 2=P2
  created_at  INTEGER NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  last_error  TEXT
);
CREATE INDEX idx_outbox_flush ON analytics_outbox(priority, created_at);
```

---

## 5. 上报策略

| 项 | 规格 |
|---|---|
| 批量大小 | ≤ 100 条 或 ≤ 256KB，先到先发 |
| 触发时机 | ① `workout_finished` 之后 ② App 进入后台 ③ 冷启动后 5 秒 ④ 网络恢复 ⑤ 前台每 60 秒（**且不在训练中**） |
| 重试 | 1s / 4s / 16s + 随机抖动，最多 3 次 |
| 超过 3 次 | 标记 parked（`attempts >= 3`），不再自动重试，等下次冷启动 |
| 容量上限 | 10000 行。超出时按 `priority` 从低到高、同优先级按 `created_at` 从旧到新丢弃，并上报 `outbox_overflow` |
| **超龄即丢** | **超过 30 天的事件不再上报**（2026-10-05 拍板的 D 方案，`docs/analytics.md` §10）。入队时按"这一条自己的时间戳"顺手清一次（把额度腾出来），**出队（`takeBatch`）发之前再按 store 的时钟清一次** —— 后者才是真闸门（离线很久之后第一次回来，那一段没有新事件可依赖）。判据：早于 `now - 30 天`；整整 30 天还留着，多 1 毫秒就丢。⚠️ 因此 `takeBatch` **不再是纯读**（它会删掉超龄的行）；只读的 `peekAll()`（导出）仍然把超龄的列出来 —— 导出是诊断路径，队列里堵着什么都要看得见 |
| 上报失败 | **绝不弹 UI**。连续失败 3 次且用户回到首页时，在「我」页显示一个静默红点 |

---

## 6. 事件优先级

| 级别 | 事件 | 丢失影响 |
|---|---|---|
| **P0 不可丢** | `app_open`、`workout_started`、`set_logged`、`workout_finished`、`purchase_completed` | 北极星与漏斗失真，直接导致决策错误 |
| **P1 可延迟** | `suggestion_shown/accepted/modified`、`set_edited`、`set_undone`、`pr_achieved`、`rest_*` | 影响建议质量分析，不影响北极星 |
| **P2 可采样** | `onboarding_step`、`paywall_viewed`、`share_card_created`、`body_metric_logged` | 影响辅助分析 |

**采样策略**：P0 / P1 **一律 100% 上报**（采纳率与漏斗的分母不能有采样误差）；P2 可采样 50%，采样标记写进 `payload.sampled = true`。

---

## 7. 训练态静默规则

> **训练进行中（`workout.status = in_progress`）不发任何网络请求。**

事件照常写入 outbox，但 Flusher 在这期间不触发。理由：健身房常年弱网，任何同步请求都可能与"1 次点击记一组"争夺主线程与网络栈。

唯一例外：用户手动在「我」页点"立即同步"。

---

## 8. 时基（容易被忽略的正确性问题）

| 用途 | 必须使用 |
|---|---|
| 事件时间戳 `ts` | 墙上时钟，事件发生时取**一次**并固化 |
| 耗时类属性（`duration_sec`、`ms_since_launch`、`rest.elapsed_sec`） | **单调时钟**（`Stopwatch`） |

**绝不能**用两次 `DateTime.now()` 相减算耗时：用户改系统时间或 NTP 校正会产生负值或巨大值，直接毁掉分布图。埋点 SDK 启动时创建一个全局 `Stopwatch`，所有耗时都相对它计算。

---

## 9. Schema 版本与兼容

- 每条事件附带 `schema_version`（整数，起始 1）。
- **属性只增不改**：已上线事件的属性语义不允许变更，需要改就发新事件名 + 提升版本。
- 服务端必须容忍未知属性（忽略而非报错）。
- 客户端不得依赖服务端返回结构，上报成功与否只看 HTTP 状态码。

---

## 10. 隐私与合规（与 `analytics.md` §6 一致，落到实现）

| 要求 | 实现 |
|---|---|
| 不上报自由文本 | `track()` 内部对属性值做白名单校验，拒绝长度 > 64 的字符串（疑似备注） |
| 不上报 HealthKit 原始值 | SDK 层不提供任何 HealthKit 读取入口 |
| 体重只报布尔 | `body_metric_logged` 的 props 只有 `has_weight` / `has_note` |
| 隐私开关 | 设置项「帮助改进产品」**默认开**（2026-10-07 用户拍板；此前 2026-09-30～v1.58.0 是「默认关」、再之前是「默认开」—— 翻过两次，每次都与政策/商店文本同期改）。**关掉之后**除崩溃上报外**零上报**（连队列里没发出去的也停发，见 `FlushOutcome.disabled`）；开关本身**不影响任何功能** |
| 游客上报 | `user_id` 可为 null，但事件必须上报（否则北极星分母缺失） |

---

## 11. Kill Switch

服务端下发配置，客户端每次冷启动拉取并缓存，**拉取失败时沿用上次缓存**（不允许因为拉不到配置就全量上报）：

- `analytics_non_p0_enabled`（默认 true）：关闭后只上报 P0
- `analytics_all_enabled`（默认 true）：全局关闭
- 崩溃上报走**独立通道**，不受以上开关影响

---

## 11.5 怎么接一个真实地址（2026-09-29）

**客户端已就绪**：`lib/analytics/transport.dart` 里的 `HttpAnalyticsTransport`
（超时、读掉响应体、任何错都只返回 false 不抛异常）。接地址不需要改代码：

```bash
# 真机联调（本机起收集端，用局域网 IP，不是 127.0.0.1）
node server/collector.mjs --port 8787
flutter run --dart-define=LIANLEME_ANALYTICS_URL=http://192.168.x.x:8787/v1/events

# 正式包
flutter build apk --release --dart-define=LIANLEME_ANALYTICS_URL=https://your.host/v1/events
```

不配 → 回落 `NullTransport`：事件照常落本地 outbox（P0 永不丢），只是不发。
**这个默认值是安全的那一个** —— 没配地址却"假装上报了"才是危险的。
配了但配错（不是 http(s) / 没有 host）→ 不发，并在 logcat 里明说，不静默。

线格式（客户端 → 服务端）：

```json
{ "events": [ { "id": "ev_...", "event": "set_logged", "ts": 1790000000000,
                "priority": 0, "schema_version": 1, "device_id": "...",
                "session_id": "...", "user_id": null, "app_version": "1.8.0",
                "platform": "android", "is_offline": false,
                "reps": 8, "tap_count": 1, "...": "其余 props 摊平" } ] }
```

事件专有属性是**摊平**在同一层的（见 `AnalyticsEventPayload.toJson`），
公共字段由 `analytics_context.dart` 统一附加；同名字段以公共层为准。

**收下来的数据怎么变成指标**：`node tool/analytics-report.mjs`
（口径的可执行版本，见 `docs/analytics.md` §8）。

## 12. 接入验收清单

- [x] ✅ **公共字段自动附带且有测试**（`analytics_identity_test.dart`：七个字段、
      同名字段以公共层为准、取不到公共字段时事件照发）
- [x] ✅ **漏斗四环有端到端测试**（`home_entry_test.dart`：app_open → workout_started
      → set_logged → workout_finished，并断言 `total_sets` 与 `set_logged` 条数一致）
- [x] ✅ **收集端与口径有自检**（`node server/collector.selftest.mjs`，已进 verify.sh：
      收/拒/落盘、北极星 24h 边界、漏斗、tap_count 中位数与 P90、真实 HTTP 往返）
- [ ] 每个事件在真机上验证一次，属性齐全、取值正确 ← **还没做的只有这一条**：
      真机点一遍 + `node tool/analytics-report.mjs` 看数对不对
- [ ] 飞行模式跑完整场训练 → 恢复网络后 **100% 补报**，且所有事件 `is_offline: true`
- [ ] `set_logged.tap_count` **人工逐次数过**，与上报值一致
- [ ] 连点大按钮 2 次 → 两条 `set_logged` 各自 `tap_count = 1`（单测覆盖）
- [ ] 长按 + 步进 + 确定 → `tap_count = 4`（单测覆盖）
- [ ] 埋点抛异常注入 → 记录功能完全不受影响，训练可正常完成
- [x] **关闭隐私开关 → 除崩溃外零上报**（2026-09-30 在设备上验过，见 `app/integration_test/analytics_outbox_e2e_test.dart`）：默认（关）状态下跑完整轮训练后，应用**自己的库**里 `analytics_enabled=false · pending=0`；同一个流程把开关预置成开，则是 `analytics_enabled=true · pending=11` —— 两跑缺一不可，否则「0 条」可能只是测量坏了。
      **2026-09-30 又在 iOS 上跑了两跑**（iPhone 17 Pro Max 模拟器 / iOS 27.0）：`pending=0` 与 `pending=11` 逐项一致 —— 也就是说这条设备级证明**不是安卓独有**，两端同结论（线 1 的"同等可发布"要求这个）
- [ ] outbox 灌到 10000 行 → 丢弃顺序符合优先级，且上报了 `outbox_overflow`
- [x] **超过 30 天的事件不再上报**（2026-10-05，D 方案）：入队顺手清 + 出队发之前清，两侧都验；边界（整整 30 天还留着 / 多 1 毫秒就丢）与"离线一周照样上报"各一条 —— `app/test/analytics_outbox_age_test.dart`（7 条）
- [ ] 手动把系统时间改到未来 → 所有耗时属性仍为非负
- [ ] 训练进行中抓包 → **无任何网络请求**
- [ ] `set_logged` 条数与 `workout_finished.total_sets` 能对上（量级 sanity check）
