# 练了么 · 埋点事件字典与北极星看板

> 数据层设计的第一原则：**埋点服务于"验证 less is more"，不是服务于做报表。**
> 与本文件配套的指标定义见 `PRODUCT.md` 第 9 节、可用性测试见 `docs/usability-test.md`。

---

## 1. 北极星指标（唯一定义，不允许各部门各自解释）

### 1.1 北极星：首次训练完成率

**定义**：新设备**首次 `app_open`** 起 24 小时内，完成一次 `workout_finished`（且该次训练至少含 1 条 `set_logged`）的比例。

| 项 | 规则 |
|---|---|
| 分母 | 首次 `app_open` 的设备（按 `device_id` 去重） |
| 分子 | 该设备在首次 open 后 **24h 窗口**内产生 `workout_finished` 且 `total_sets ≥ 1` |
| 归因窗口 | 24 小时，固定不调 |
| 排除 | 内部测试设备（`is_internal=true`）、90 天内重装设备（按 `device_id` + 账号指纹识别） |
| 目标 | **≥ 55%** |

> ⚠️ **目标值（55%）目前是估计值，尚未经过真实测试校准。** 指标的**定义**（分母、分子、24h 窗口、
> 排除规则）是要长期固定的，不该随数据漂移；但**目标值**应当在第一轮测试数据出来后修正。

**为什么是它**：训记的弱项是上手成本，我们全部的设计投入（0 注册、0 打字、1 次点击）都指向这一个数字。它同时也是最接近"用户是否真的用起来了"的单一指标。

### 1.2 转化漏斗（北极星的拆解）

```
app_open ──▶ workout_started ──▶ first_set_logged ──▶ workout_finished
   100%          目标 ≥80%           目标 ≥70%            目标 ≥55%
```

| 环节 | 目标 | 若未达标，优先怀疑 |
|---|---|---|
| `app_open → workout_started` | ≥ 80% | S1 空态文案与按钮位置 |
| `workout_started → first_set_logged` | ≥ 70% | S2 建议卡是否让人犹豫；大按钮是否够显眼 |
| `first_set_logged → workout_finished` | ≥ 78% | 训练中路径是否有摩擦（编辑、切换动作） |

---

## 2. 事件字典

### 2.1 通用属性（所有事件自动附带）

| 属性 | 类型 | 说明 |
|---|---|---|
| `event` | string | 事件名 |
| `ts` | int | 客户端事件时间（UTC 毫秒）。**用事件发生时间，不是上报时间** |
| `session_id` | string | 会话 ID，30 分钟无操作即新会话 |
| `device_id` | string | 设备匿名 ID |
| `user_id` | string \| null | 游客为 null。**游客也必须上报**，否则北极星分母缺失 |
| `app_version` | string | 语义化版本 |
| `platform` | `ios` \| `android` | |
| `is_offline` | bool | 事件发生时是否离线 |
| `schema_version` | int | 事件 schema 版本，只增不改 |

### 2.2 核心事件

| 事件名 | 触发时机 | 关键属性 | 用途 |
|---|---|---|---|
| `app_open` | 冷启动完成 | `is_first_open`, `ms_since_launch` | 北极星分母、漏斗起点 |
| `onboarding_step` | 每步引导 | `step_index`, `skipped` | 验证"≤3 步且可跳过" |
| `workout_started` | 进入 S4 | `routine_id`, `source`, `ms_since_launch` | 漏斗第 2 环 |
| `exercise_added` | 添加动作 | `exercise_id`, `add_method`(suggest/search/recent/custom/all/**pinned**) | 建议采纳的另一种度量 |
| **`set_logged`** | 记录一组成功 | `workout_id`, `exercise_id`, `set_index`, `weight_kg`, `reps`, `distance_m`(可选，有氧/农夫行走), `set_type`, `rpe`(可选), **`tap_count`**, **`tap_kinds`**, `entry`(bigbutton/stepper), `is_offline` | **最重要的事件**，见 §3 |
| `set_edited` | 弹层确定修改 | `field`(weight/reps), `from`, `to`, `suggestion_id` | 建议质量、编辑成本 |
| `set_undone` | 撤销一组 | `set_index`, `method`(longpress), `seconds_after_log` | 误触率 |
| `rest_started` | 休息计时开始 | `planned_sec`, `auto`(bool) | — |
| `rest_skipped` | 点击跳过 | `elapsed_sec`, `remaining_sec` | 默认休息时长是否合理 |
| `rest_completed` | 自然归零 | `planned_sec` | — |
| `suggestion_shown` | 建议展示 | `suggestion_id`, `exercise_id`, `reason_code`, `suggested_weight_kg`, `suggested_reps` | 采纳率分母 |
| `suggestion_accepted` | 直接采纳记录 | `suggestion_id`, `reason_code` | 采纳率分子 |
| `suggestion_modified` | 手改后记录 | `suggestion_id`, `reason_code`, `delta_weight_kg`, `delta_reps`, `direction`(up/down) | **引擎失效点定位** |
| `workout_finished` | 结束训练 | `duration_sec`, `total_sets`, `total_volume_kg`, `exercise_count` | 北极星分子 |
| `pr_achieved` | 破纪录 | `exercise_id`, `pr_type`, `value`, `prev_value` | 留存钩子效果 |
| `share_card_created` | 生成分享卡 | `channel`(save/wechat) | 一期唯一社交形态的效果 |
| `body_metric_logged` | 记录身体数据 | `has_weight`, `has_note` | **不上报具体数值**（v1.52 新加的腰围 / 肌肉量 / 身高同样不上报），见 §6 |
| `sync_failed` | 同步连续失败 | `retry_count`, `entity`, `error_code` | 健康度 |
| `paywall_viewed` | 会员页曝光 | `entry_point` | 变现漏斗 |
| `purchase_completed` | 支付成功 | `plan`, `price`, `is_trial` | 变现 |

### 2.3 属性纪律

- **只增不改**：任何已上线事件的属性语义不允许变更。需要改就发新事件 + 提升 `schema_version`。
- **不上报自由文本**：用户的训练备注、自定义动作名一律不上报（隐私 + 无分析价值）。
- **不上报 HealthKit 原始值**：心率、消耗只在设备本地参与展示，绝不上报。
- **`from` / `to` 用数值**，不用字符串拼接，避免后期无法计算。

---

## 3. 体验守卫指标（Less is More 的唯一客观防线）

### `set_logged.tap_count`

定义：从**用户决定练这个动作**到"这一组写入成功"之间，用户产生的点击/轻触次数。

**端到端口径**（2026-09-29 修正）。计入：

| 类型 | `tap_kinds` | 说明 |
|---|---|---|
| 开始训练 | `nav` | 今日页「开始今天的训练」、建议卡「就用这个，开始练」 |
| 选动作 | `exercise_pick` | 「我自己选」里从动作库挑一个 |
| 切换动作 | `exercise_switch` | 训练屏底部条点按、左右滑动、**以及 v1.53 的「换动作」（器械被占）** —— 都是同一个意图：用户为得到这一组多付出了一次操作 |
| 长按大按钮 | `long_press` | 打开修改弹层 |
| 步进调整 | `stepper` | 弹层里每一次 ±；**以及计时动作的「开始计时」**（v1.53）—— 两者是同一件事：给出这一组的值。所以计时动作是「两次点击一组」，这是它真实的操作代价，不藏 |
| 弹层确定 | `sheet_confirm` | |
| 大按钮 | `big_button` | 真正写入这一组的那一下 |

不计入：休息跳过、Tab 切换、返回、滚动浏览、查看历史（它们不产生这一组的数值）。

**为什么改**：旧口径从"进入训练屏"才开始计数，于是把"用户为了得到这一组实际按了 5 次"
记成 1 次 —— 唯一能守住 less is more 的客观闸门会**自我满足**。而竞争对手用的是端到端数字
（Everlift 公开自述"3 组从约 21 次点按降到 8 次"，约 2.7 次/组），口径不一致就没法比。

按端到端口径，**首页一跳直开练**（2026-09-29）之后：

| 场景 | 端到端点击 |
|---|---|
| 一次训练的**第一组** | **2**（首页大按钮 + 大按钮） |
| 同一动作的第 2 组起 | **1** |
| 每切换一个动作 | +1 |

3 个动作各 3 组 ≈ **13 次点击 / 9 组 ≈ 1.4 次/组**；竞品 Everlift 的公开数字是
"3 组从约 21 次降到 8 次"（≈2.7 次/组）。

> 改之前是「今日页 → 建议卡 → 大按钮」= **3 次**，而 `PRODUCT.md` §1 的红线正是
> "超过 3 次点击判负"—— 刚好压线。另有一处更贵的：大按钮上的重量是错的
> （`main.dart` 不传 `lastSession`），于是第二次训练起每组要"长按 + 两次步进 + 确定"
> 才能改成对的重量 = **5 次/组**。两处都已修。

| 分位 | 目标（**待校准**） |
|---|---|
| 中位数 | 待定 |
| P90 | 待定 |
| P99 | 待定 |

> ⚠️ **「中位数」这一格是机器读的**：`tool/usability-report.mjs` 直接从这里取门槛
> （判据 `中位数 ≤ 门槛`；还是"待定"时它把那一项标成"未标定"、**不判不通过**）。
> 所以熟人短测做完之后**只改这一格**就够 —— 别在脚本或别处再抄一个数（那就成了两把尺子）。

> ⚠️ **目标值必须重新标定。** 原来那张表（中位数 = 1 / P90 ≤ 3 / P99 ≤ 6）是在**窄口径**下
> 拍的估计值，标着"待校准"却已经被当成发版门禁在用。换成端到端口径后 `= 1`
> 在物理上就不成立（光导航就 2–3 次），继续沿用等于用旧尺子量新东西。
>
> 校准办法（**2026-10-05 起**）：按 `docs/usability-test-kit.md` **§A 熟人短测**——
> 3–5 个熟人、每人 5 分钟、只取 `tap_count` 分布，**半天做完**就用分布回填上表并去掉"待校准"。
> 「校准前不允许上架」这条内部纪律**已作废**（见 `release-checklist.md` §5）。
> ⚠️ 短测只标定这张表的三行，**§1.1 的 55% 它校准不了**（那要正式可用性测试，仍建议做、不卡上架）。

**上报规则**：`tap_count` 由客户端在记录成功那一刻计算；周期由 `beginSetInteraction()`
开启，控制器构造时用 `ensureSetInteraction()` 接续 ——
**构造时不能清零**，否则"开始训练/选动作"这些发生在构造之前的点击会全丢。

**`tap_kinds`**：与 `tap_count` 同时上报的类型数组（首页直开练是 `["nav","big_button"]`；
走建议卡那条路是 `["nav","nav","big_button"]`）。
它回答的是 `tap_count` 高的时候"这些点击花在哪了" —— 没有它，只知道变差了却不知道该改哪一步。

**治理规则（写进发版流程）**：
> 每个版本发布前必须对比上一版的 `tap_count` 分布。
> **若中位数或 P90 上升，该版本不允许发布**，必须回退导致上升的改动。
> 这条规则高于任何单点功能需求。

> 修订说明：原文是"中位数 > 1 或 P90 上升"。端到端口径下 `> 1` 恒成立，
> 所以判据改为**与上一版比是否上升** —— 门禁的语义是"不能变得更费事"，
> 而不是"一次都不许点"。

其余守卫指标：

| 指标 | 目标 | 说明 |
|---|---|---|
| 首次训练打字次数 | = 0 | 由 `set_edited` 的 `field=reps_custom` 变体推导 |
| 首次训练需滚动找动作次数 | = 0 | `exercise_added.add_method=search` 且发生滚动 |
| 建议采纳率 | ≥ 60% | `suggestion_accepted / (accepted + modified)`，不含未响应 |
| `rest_skipped` 占比 | ≤ 35% | 过高说明默认休息时长不准 |
| 崩溃自由率 | ≥ 99.5% | — |
| 同步失败率 | < 1% | — |

---

## 4. 看板布局

### 第一屏 · 北极星（默认视图）
- 大数字：**首次训练完成率**（近 7 日滚动，含目标线与同比）
- 漏斗：`app_open → workout_started → first_set_logged → workout_finished`（含各环转化率与目标差）
- 首次打开到第一组记录的中位耗时（秒）

### 第二屏 · 体验守卫
- `set_logged.tap_count` 分布直方图（中位数 / P90 / P99 三根参考线）
- 每个大版本的 `tap_count` 中位数趋势（**这条线必须平或下降**）
- 单次训练记录组数分布
- 每组平均间隔（真实休息时长）

### 第三屏 · 建议质量（规则引擎是否成立）
- 采纳率总览 + 按 `reason_code` 拆分（`linear_progress` / `hold` / `add_rep` / `first_time`）
- 采纳率 Top/Bottom 20 动作（找出引擎在哪些动作上失效）
- `suggestion_modified` 的 `direction` 分布（用户系统性改轻 = 引擎过于激进；系统性改重 = 过于保守）
- 采用采纳率 vs. 该动作后续 4 周容量增长的相关性（**建议到底有没有让人进步**）

### 第四屏 · 留存与变现
- D1 / D7 / D30 留存曲线（按首周训练次数分群：0 次 / 1–2 次 / 3 次以上）
- 周人均训练次数、周人均容量
- 免费 → 付费转化，付费用户与非付费用户的 D30 对比

### 第五屏 · 健康度
- 崩溃自由率、同步失败率、离线事件占比
- outbox 平均积压深度与清空耗时

---

## 5. 反指标（出现即停下讨论）

| 现象 | 含义 | 处置 |
|---|---|---|
| `tap_count` 中位数上升而 DAU 同步上升 | 我们在用牺牲核心原则换增长 | 停止上新功能，专项回退 |
| 采纳率高但 `set_edited` 后容量不增长 | 用户只是懒得改，建议没有实际效果 | 重新评估规则引擎价值 |
| `workout_started` 上升但 `workout_finished` 下降 | 入口变简单了，但中途留不住 | 优先排查训练中路径 |
| 免费版限制加码带来短期转化上升、D30 下降 | 在透支信任 | 回退限制 |

---

## 6. 隐私与合规约束（影响埋点设计，不是事后补的）

1. **不上报任何 HealthKit 原始数据**。体重只上报 `has_weight=true/false`，数值永不离开设备。
2. **不上报用户自由文本**（训练备注、自定义动作名称）。
3. 游客态数据同样上报（否则北极星分母缺失），但 `user_id=null` 且不含任何可识别信息。
4. 提供"关闭使用数据改进"开关，关闭后只保留崩溃上报；**不影响任何功能可用性**。
5. 事件数据保留期 24 个月，到期自动聚合去明细。

---

## 7. 埋点实现红线

1. **训练过程中不上报网络请求**。全部写入本地 outbox，训练结束后批量上报。
   理由：健身房常年弱网，任何同步请求都可能阻塞"1 次点击记一组"的体验。**埋点永远不能拖慢记录。**
2. **上报失败不重试超过 3 次**，且失败绝不弹 UI。
3. **埋点不可影响主流程**：任何埋点代码抛异常必须被吞掉，不允许因为埋点导致记录失败。
4. 时间戳用**事件发生时刻**（本地时钟），不用上报时刻。跨时区与离线场景下这是唯一正确的选择。

---

## 8. 埋点验收清单（每个版本）

- [ ] 每个新事件在真机上验证一次，属性齐全、值正确
- [ ] 飞行模式下产生的事件，恢复网络后 **100% 补报**，且 `is_offline=true`
- [ ] `set_logged.tap_count` 在真机上逐次数过，中位数**不高于 §3 的门槛**（门槛由熟人短测标定，见 `docs/usability-test-kit.md` §A）
- [ ] 事件量级 sanity check：`set_logged` 与 `workout_finished.total_sets` 能对上
- [ ] 关闭"使用数据改进"后，除崩溃外无任何上报
- [ ] 埋点异常注入测试：让埋点 SDK 抛错，确认记录功能不受影响

---

## 8. 口径的**可执行版本**（2026-09-29 补）

**为什么要有它**：这份文档把分母、窗口、门禁写得非常死（"首次 `app_open` 的设备"、
"24 小时固定不调"、"中位数或 P90 上升就不许发"）。但只要口径**只活在文档里**，
它就一定会被各自解释 —— 三个人算出三个数，然后争论谁对。

所以同一份定义现在有一个可运行的实现：

```bash
node tool/analytics-report.mjs              # 读 server/data，打出全部口径
node tool/analytics-report.mjs --json       # 机器可读
node tool/analytics-report.mjs --baseline 12  # 发布门禁：中位数高于 12 → 退出码 1
```

它算的就是本文件 §1 与 §7 定义的那些数：北极星（分母/分子/比例）、漏斗四环、
`tap_count` 的中位数与 P90（按 `app_version` 分组）、以及 §5 里**能算**的那几条反指标。
算不了的（要跨版本 + DAU 的）会**明确写"算不了"**，不假装。

数据从哪来：`server/collector.mjs` 是最小的参考收集端（零依赖，落 JSONL）。
它**不是**要上线的后端，而是"真机联调有个能收的东西 + 口径有数据可算"的前提。
将来写真后端时，线格式与语义有一份可运行的参考。

---

## 9. 客户端事件落地状况（**如实记，不粉饰**）

2026-09-29 查出来一个会让人白干一场的窟窿：上报**管线**早就写完了
（outbox / 批量 ≤100 / 退避重试 / 训练期挂起 / 本地环回 HTTP 测试全在），
但客户端当时**只发 6 个事件**，而本文件定义了 31 个 ——
**北极星的分母（`app_open`）和分子（`workout_finished`）从来没发过**，
公共字段（`device_id` / `session_id` / `app_version` / `platform` / `is_offline`）
一个都没带。也就是说：**指标定义写死了，但没有任何数据能算出它。**

### 已经发的（9 个）

| 事件 | 说明 |
|---|---|
| `app_open` | 含 `is_first_open` / `ms_since_launch` —— **北极星分母** |
| `workout_started` | 含 `source`(home_button/suggestion/onboarding/picker/**light**) / `exercise_count` |
| `set_logged` | 本来就有的（含 `tap_count` / `tap_kinds` / `distance_m`） |
| `workout_finished` | 含 `duration_sec` / `total_sets` / `total_volume_kg` / `exercise_count` —— **北极星分子** |
| `rest_started` / `rest_skipped` / `rest_completed` | 本来就有的 |
| `set_undone` | 本来就有的 |
| `seed_import_failed` | 动作库刷新失败（2026-09-29 加，配合"冷启动刷新"那个修复） |

公共字段由 `lib/analytics/analytics_context.dart` **统一附带**（不是各处自己传）：
`schema_version` / `device_id` / `session_id` / `user_id`(null) / `app_version` /
`platform` / `is_offline`。

### 2026-09-30 补发：9 个事件已落地（`v1.19.0`）

| 事件 | 落地位置 | 备注 |
|---|---|---|
| `suggestion_shown` / `suggestion_accepted` / `suggestion_modified` | `workout_controller.logSet` | 三条**同源**：只有真正记下一组时才算一次"展示"，于是 shown == accepted + modified，采纳率必然落在 [0,1]（见下方口径说明） |
| `set_edited` | `workout_controller.onSheetConfirm` | **只记真的改了的那一项**：打开弹层又原样关掉不算编辑 |
| `exercise_added` | `exercise_picker_screen._pick` | `add_method` 多了 `all`（「全部动作」那一区）；硬归到 `suggest` 会让字段说谎。**2026-10-04** 又多了 `pinned`（「置顶」那一区）：用户自己钉的那几个动作是他**直接表态**的结果，混进别的取值等于把这个信号扔掉 |
| `pr_achieved` | `workout_summary_screen._load` | 每次破纪录一条；`pr_type` = weight / reps / time |
| `share_card_created` | `share_card_preview_screen` | `channel` 只有 `save` / `share`：系统分享面板**不会告诉我们发给了谁**，所以不假装知道微信 |
| `body_metric_logged` | `body_metric_screen._save` | 只报 `has_weight` / `has_note` |
| `onboarding_step` | `onboarding_screen` | 三处出口：两个「下一步」与「跳过」 |

**口径说明（采纳率为什么这样记）**：`suggestion_shown` 原本可解释为"建议卡渲染时"，
但那样会把"看了没练"的人也记进分母。现在改成**在记下这一组的同一刻记一次展示**，
紧接着按"记下的值 == 建议的值"分流成 accepted / modified —— 三者严格同源，
比率可解释，且每次展示都对应一次真实动作。

**仍然不发**：`sync_failed` —— 全仓库 `SyncQueue` 只有 `InMemorySyncQueue` 一个实现，
**根本没有真实同步**（离线优先、没有后端）。没有同步就没有"同步失败"，
发了只会是假数据。等有了后端再补。

### 当初的清单（10 个，以及它们卡住哪个指标）

| 事件 | 谁在等它 |
|---|---|
| `suggestion_shown` / `suggestion_accepted` / `suggestion_modified` | **建议采纳率**、引擎失效点定位（§5 反指标之一） |
| `set_edited` | 编辑成本、§5 反指标"采纳率高但容量不增长" |
| `exercise_added` | 建议采纳的另一种度量（`add_method`） |
| `pr_achieved` | 留存钩子效果 |
| `share_card_created` | 一期唯一社交形态的效果 |
| `body_metric_logged` | 体重记录的使用率（**只上报 `has_weight` / `has_note`，数值不出设备**） |
| `sync_failed` | 同步健康度 |
| `onboarding_step` | 验证"≤3 步且可跳过" |

`paywall_viewed` / `purchase_completed` **不发**：S14（变现）已明确砍掉（见 `ROADMAP.md`）。

**现在的结论**：北极星、漏斗、`tap_count` 门禁**都能算了**；
采纳率与编辑成本那两条反指标**还不能**，因为它们要的事件还没发。

---

## 10. 真机端到端验证（2026-09-30 补，**这是"管线通不通"唯一的硬证据**）

在此之前，`HttpAnalyticsTransport` 的注释写着"只在本地环回服务器上验证过"。
本地环回证明的是传输实现，**证明不了真机能不能发出去**（私有目录、Doze、网络栈都可能拦）。
2026-09-30 补上了这一段，做法和结果：

| 步骤 | 命令/做法 | 结果 |
|---|---|---|
| 起收集端 | `node server/collector.mjs --port 8787 --out /tmp/e2e-events` | `{"ok":true,"events":0}` |
| 打通真机 | `adb reverse tcp:8787 tcp:8787`（**不用同一 Wi-Fi**） | `UsbFfs tcp:8787 tcp:8787` |
| 带地址构建 | `flutter build apk --release --dart-define=LIANLEME_ANALYTICS_URL=http://127.0.0.1:8787/v1/events` | 装真机、冷启动 |
| 结果 | `GET /stats` | **`{"events":9,"devices":1,"byEvent":{"app_open":9}}`** |
| 反向对照 | 装**不带地址**的正式包，收集端可达、等 22 秒 | **0 条** —— §3.1"出货包没有地址"由此坐实 |

九条事件正好是 9 次冷启动（v1.9.0 → v1.16.0 各一次），**没有重复投递**，
字段与 `privacy-facts.json` 一致（14 个字段，`user_id` 为 `null`）。
另外单独核过：不带地址的正式包，`libapp.so` 里**搜不到任何 endpoint 字符串**。

### ⚠️ 这次验证暴露的一个待决问题：**积压事件会不会被未来的上报包一起发出去**

`_NullTransport.send` 恒返回 false，而 `AnalyticsFlusher.onColdStart()` 每次冷启动都会
`resetParked()` 把失败计数清零 —— 所以**没配地址的正式包不会丢事件，而是无限攒在本地**
（上限 `maxRows = 10000`）。上面那 9 条就是这么攒了 8 个版本、在一次配了地址的构建里
被一次性发出的。

于是有了一个问题：**接入上报的第一个正式版本，要不要把老版本攒下的事件一起发出去？**

| 选项 | 好处 | 代价 |
|---|---|---|
| A. 照现状发出去 | 北极星的历史分母一次补齐，第一份看板就有数 | 用户当时用的是"不上报"的包，**事后被补传**；政策 §3.2 现在没有覆盖这一条 |
| B. 接入上报的首个版本丢掉积压，只发它自己记的 | 边界干净：谁记的谁发，政策不用打补丁 | 第一份看板上线时没有历史数据 |
| C. 加一个 build-time 的"代次"标记，只发本代次记的事件 | 兼得（B 的干净 + 以后升级不断档） | 多一个要维护的概念与一次迁移 |
| D. **超龄即丢**：事件超过 **30 天**就不再上报 | 不污染当期曲线，又保住"离线一周照样上报" | 堵在队列里超过 30 天的那批**永远发不出去**（本来也发不出去） |

**✅ 2026-10-04 拍板：选 B —— 丢积压，只发这个版本自己记的。**

理由（你拍的，我记下来免得下次重新讨论）：边界干净 —— **谁记的谁发**。
那些积压是用户在"不上报的包"里产生的，那时候我们**没有**告诉过他数据会被发出去；
接上地址的那一天把它们补传，等于事后改主意 —— 政策 §3.2 现在也没覆盖这一条。
代价是"第一份看板上线时没有历史数据"，这个代价我们认（第一份看板本来就要等真实用户）。

**B 已实现（随"把地址编进正式包"那一次，v1.43.0）**：`AnalyticsMeta.legacyPurgedAt` 是
"清过了"的落库标记，`main.dart` 的 `_purgeLegacyOutboxOnce()` 在**真的有地址**的包里
第一次冷启动时先清空 outbox 再置位（顺序在 `onColdStart()` 之前 —— 否则 parked 的事件
会先被放行发出去）。三条边界由 `app/test/analytics_legacy_purge_test.dart` 钉住：
配了地址才清 / 没配地址一条不动 / **只清一次**。
（这一段的上一版写的是"实现还没做，故意的"和"在定下来之前不要发布配了地址的包"——
两句在 v1.43.0 之后都已经过期，2026-10-05 改掉。）

**✅ 2026-10-05 拍板并落地：D 超龄丢弃（30 天）** —— 与 B 不是同一件事，别混：

| | 管什么 | 什么时候发生 |
|---|---|---|
| B | **出身**：接入上报之前攒下的那批 | 只在"配了地址的包"第一次冷启动，**一次** |
| D | **年龄**：任何事件超过 30 天就不发 | **一直都在**（入队与出队各清一次） |

- **规则写死在代码里**：`AnalyticsOutboxStore.maxAge = Duration(days: 30)`，
  `dropExpired()` 判据是"早于 `now - 30 天`"—— 整整 30 天还留着，多 1 毫秒就丢。
- **两条路各清一次**：入队时用**这一条自己的时间戳**当"现在"（顺手把额度腾出来）；
  **出队（`takeBatch`）发之前再清一次**，用 store 的时钟 —— 后者才是真正的闸门：
  "离线很久之后第一次回来"那一段**没有新事件可依赖**，只有发送前这一步拦得住。
  代价是 `takeBatch` 不再是纯读（它会删掉超龄的行），`peekAll()`（导出）仍然只读、
  仍然把超龄的**列出来**（导出是诊断路径：队列里堵着什么都要看得见）。
- **为什么是 30 天**：它同时满足两条本来互相拉扯的要求 —— 三个月前的噪声不许混进
  当期漏斗（分母错了还看不出来），而"出差一周、进山跑步、关掉开关几周"回来照样上报。
- **不新增字段、不动政策 §3.2**：D 只按"时间"判断，不涉及"当时有没有告诉过用户"。
- **测试**：`app/test/analytics_outbox_age_test.dart`（7 条：超龄不发 / 30 天整的边界 /
  离线一周照发 / 入队顺手清 / 不误伤 / parked 的超龄事件也清 / 导出口径）。

**我的建议是 C 或 B，倾向 C**，但这是产品与合规决策，不是我能替定的：
它决定政策 §3.2 怎么写、以及数据安全表的"此前未收集"怎么填。
（2026-10-04 你选了 B，2026-10-05 又补了 D —— 这一节到这里闭环，不再有待决项。）

## 11. 每个事件给谁看：一次**对账**（2026-10-01）

> 这一节不是新埋点，是一次**反问**：18 个事件、7 个公共字段，**谁会用它们回答什么问题**？
> 导火索是那天的产品复盘（`docs/product-review-2026-10-01.md` ➖3）：
> 埋点是**隐私面**，也是政策与两张商店表单的来源 ——
> 少一个没人看的字段，就少一处要解释、要披露、要维护的东西。

口径：**每个事件都要写出一句"谁会用它"**；写不出来的，先标记、**先不删**
（砍埋点要有数据支撑，不能凭感觉）。下表按"用途是否清楚"分三档。

### A 档：北极星与漏斗直接需要（留）

| 事件 | 谁会用它 / 回答什么 |
|---|---|
| `app_open` | 北极星的分母（打开过的人）；`is_first_open` 切新老 |
| `workout_started` | 漏斗第 2 环（点开始训练）；`source` 回答"哪条路真的有人走"（含 2026-10-01 新增的 `light`） |
| `set_logged` | 漏斗第 3 环 + 北极星的**分子**（完成第一次训练）；`tap_count` 就是它的字段 |
| `workout_finished` | 漏斗第 4 环；`total_sets/volume/duration` 是"真的在健身房用"的证据 |

### B 档：有明确使用者，但**低频看**（留，标注复查时间）

| 事件 | 谁会用它 / 回答什么 |
|---|---|
| `suggestion_shown` / `suggestion_accepted` / `suggestion_modified` | 「建议采纳率 ≥ 60%」这个指标的唯一来源（规则引擎这个楔子成不成立） |
| `set_edited` | 采纳率的**修正项**：改了才算"没采纳"，不改不算 |
| `set_undone` / `rest_skipped` | 体验守卫：误触与不耐烦的信号（哪个改动把它们顶上去了，就要回看） |
| `pr_achieved` | 留存钩子（"破纪录"那条推送/总结文案值不值） |
| `onboarding_step` | 首启漏斗（哪一步把人劝退）；只在引导改动时看 |
| `exercise_added` | 动作库缺口（用户自己建的动作 = 我们没有的） |
| `body_metric_logged` | 身体数据这条线有没有人用（**只报填没填，数值不出设备**） |
| `share_card_created` | 分享这个增长钩子值不值（现在没人看，但**它是唯一的分享指标**） |

### C 档：**目前没人看**（先标记，等有数据再决定删不删）

| 事件/字段 | 现状 | 处置 |
|---|---|---|
| `seed_import_failed` | 只在"动作库刷新失败"时出现；我们**没有崩溃/错误看板**，所以没人会看它 | 标记：**下一次审计若仍无人看 → 删**（删它会同时缩小隐私面） |
| `rest_completed` | 与 `rest_started` 成对，但**没有任何指标用它**（休息时长是本地偏好，不进北极星） | 标记：同上 |
| 公共字段 `is_offline` | 想过用它判断"弱网下体验如何"，但**没有任何看板/指标消费它** | 标记：把它从"每个事件都带"降级为"只在需要的事件上带"，能直接减小每一批上报的体积与敏感面 |
| 公共字段 `user_id` | 目前是本机匿名 id，**与 `device_id` 高度重合** | 标记：想清楚"它回答什么"再留；想不出就删 |

**下一步（写进 `docs/your-todo.md` 的那条）**：等真的接了上报地址、有 2–4 周数据之后，
拿"最近 30 天有没有人查过这个事件"做一次决定；在那之前**只标记、不删**。

## 怎么把报表跑起来（2026-10-05 实测跑通）

口径写在本文档里、**可执行版本**是 `tool/analytics-report.mjs`。它读的是"收集端落盘的那堆
jsonl"，所以整条链是这样三步（**全程本机，不碰线上**）：

```bash
# ① 起一个本地收集端（数据落在临时目录，用完就删）
node server/collector.mjs --port 8799 --out /tmp/ev-e2e

# ② 让它收一批事件。真机走 USB 转发（`adb reverse tcp:8799 tcp:8799`）+
#    `--dart-define=LIANLEME_ANALYTICS_URL=http://127.0.0.1:8799/v1/events`；
#    只想验报表本身的话，直接 POST 一批即可 —— 字段是硬的：
#    `{id, event, ts, device_id, session_id, app_version, schema_version, ...}`
#    （少一个必填字段就被拒，收集端会回 400 并说明缺哪个）

# ③ 算报表
node tool/analytics-report.mjs --dir /tmp/ev-e2e
```

**实测过一次"人工造数 → 报表"**（10 台设备：都 app_open、8 台开练、6 台记满一组并完成训练）：

```
北极星：首次 app_open 起 24h 内完成一次训练（含 ≥1 组）
  分母 10 台 · 分子 6 台 · **60.0%**（目标 ≥ 55.0%）
漏斗：app_open 10 · workout_started 80% · first_set_logged 60% · workout_finished 60%
tap_count：1.53.0  n=6  中位数 1  P90 2
一致性自查：set_logged 6 条 · workout_finished 声明 6 组 ✓ 对得上
```

⚠️ 这一步顺带教了我两件事，都写在这儿免得下次再踩：

1. **报表读的是真实字段名**：`workout_finished` 的组数叫 **`total_sets`**（不是 `sets`），
   叫错了不会报错，只会让"一致性自查"那一行红（`声明 0 组 ⚠️ 对不上`）——
   **那条自查就是为这个存在的**；
2. **人工造数必须自洽**：第一次我发了 7 条 `set_logged` 却声明 72 组，自查立刻红。
   **造数骗不过它**，这也是它可用的前提。

**线上那份**（`https://api.elliotli.work`）用同一份代码：把 `--dir` 换成服务器上
`lianleme-collector` 的落盘目录即可（`docs/backend-hosting.md` §四有路径）。
**现在线上一条数据都没有** —— 开关默认关、也没人按过「帮助改进产品」，所以报表
"能算"但"没得算"，如实记着。
