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
| `exercise_added` | 添加动作 | `exercise_id`, `add_method`(suggest/search/recent/custom) | 建议采纳的另一种度量 |
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
| `body_metric_logged` | 记录体重 | `has_weight`, `has_note` | **不上报具体数值**，见 §6 |
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
| 切换动作 | `exercise_switch` | 训练屏底部条点按，或左右滑动（同一个动作意图，按 1 次计） |
| 长按大按钮 | `long_press` | 打开修改弹层 |
| 步进调整 | `stepper` | 弹层里每一次 ± |
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

> ⚠️ **目标值必须重新标定。** 原来那张表（中位数 = 1 / P90 ≤ 3 / P99 ≤ 6）是在**窄口径**下
> 拍的估计值，标着"待校准"却已经被当成发版门禁在用。换成端到端口径后 `= 1`
> 在物理上就不成立（光导航就 2–3 次），继续沿用等于用旧尺子量新东西。
>
> 校准办法不变：按 `docs/usability-test-kit.md` 招 5 人测试，拿回 §8 的 7 个数字，
> 用真实分布回填本表。**在数字到手之前，按项目自己的规则不允许发布**（见 `release-checklist.md` §5）。

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
- [ ] `set_logged.tap_count` 在真机上逐次数过，中位数为 1
- [ ] 事件量级 sanity check：`set_logged` 与 `workout_finished.total_sets` 能对上
- [ ] 关闭"使用数据改进"后，除崩溃外无任何上报
- [ ] 埋点异常注入测试：让埋点 SDK 抛错，确认记录功能不受影响
