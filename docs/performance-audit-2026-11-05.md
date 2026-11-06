# 技术优化清单（2026-11-05）

> 审计范围：Flutter 客户端（`app/lib`）、零依赖服务端（`server/`）、工程脚本与门禁（`verify.sh` / `tool/`）。
> 目的不是"找点东西改"，而是**先证明哪里真的值得动**，再只动其中风险最低、有判据的那几处。
>
> 结论先行（三句）：
> 1. **性能目前不是产品瓶颈**：数据量还在"一个人练一年"的量级，客户端最慢的几处都在首帧之后、且与数据量线性相关；
>    真正值钱的是**结构**（冷启动重复读全表）和**工程效率**（门禁里一段 24 秒的自检）。
> 2. **最该钉死的是确定性**：`app/pubspec.lock` 的 registry 与 CI 不一致时，锁文件会整份失效 ——
>    2026-10-14 的 build_runner 2.16.2 事故就是这么来的（见 §5）。
> 3. 第一轮只落地了三类改动：CI/依赖确定性（§5）、收集端落盘批量化 + 413（§6.1）、
>    截图守卫自检从 24s 降到 1.3s（§6.2）。**客户端与 schema 的改动当时只给方案**；
>    2026-11-05 晚用户拍板全部做掉并切 v1.68.2 —— 落地回执见 **§8**（本文前面的审计内容
>    保留当时的样子，只在对应条目上补"已实施"）。
>
> 测量条件（重要，决定了这些数字能用到哪）：macOS 27 / Apple Silicon 开发机，
> 仓库外的构建跑道 `~/HARNESS/lianleme`（路径不含撇号），pub cache 与 Gradle 缓存**已热**。
> 所有"耗时"都是这台机器上的观测值；**SQL 条数、文件字节数、调用链**才是可移植的事实。
> 标「待测」的条目 = 需要真机 / DevTools / CI 才能量的，**不要当结论用**。

---

## 0. 怎么测的（每条都能复跑）

| 测什么 | 做法 |
|---|---|
| 六层门禁耗时 | `cd ~/HARNESS/lianleme && ./verify.sh 2>&1 \| while IFS= read -r l; do printf '%4ds %s\n' "$(( $(date +%s) - start ))" "$l"; done`（`start` 在跑之前取） |
| 冷引导耗时 | 先把跑道里的 `app/.dart_tool` 与生成物 `db.g.dart` 移走，再跑上一条（即 `verify.sh` 的 `[0]` 引导会真的执行） |
| 冷启动 SQL 条数 | 临时 widget 测试：`AppDatabase(NativeDatabase.memory(logStatements: true))` + 把 `driftRuntimeOptions.debugPrint` 接到一个数组，预置 144 组历史、走"已同意隐私政策"的启动路径，`pumpAndSettle` 后按表统计 `SELECT`。**这份测量没有入库**（数字会随无关改动漂，留在仓库里会变成第二个事实源）；配方就是这三行 + `main.dart` 的 `LianLeMeApp`。 |
| 收集端落盘 | 同一批事件分别喂给旧实现（`git show HEAD:server/collector.mjs`）与新实现，`process.hrtime.bigint()` 计时；旧实现每条一次 `mkdirSync`+`appendFileSync`，新实现按天一次 |
| 截图守卫自检 | `/usr/bin/time -p node tool/check-screenshots.mjs --selftest`（旧实现 23.66s / 新实现 1.34s） |
| 包体积 | `find assets fonts -type f -exec stat -f %z {} + \| awk`（**文件真实字节数**，不是 `du` 的块占用） |

---

## 1. 客户端

### 1.1 冷启动：首帧不被挡，但首帧之后有 6 次全表扫描

**事实一：`main()` 里没有任何同步 await。** `main.dart:102` 只有 `_registerFontLicense(); runApp(...)`，
许可是**惰性**注册（`LicenseRegistry.addLicense` 的闭包只在打开「开源许可」页时跑，`main.dart:107-113`）。
`initState`（`main.dart:426-433`）里三件事全是 unawaited：`_refreshHome()`、`_loadUnit()`、`_loadConsentThenStart()`。
数据库是 `late final` + drift 惰性打开，第一次访问发生在异步函数里。**所以没有"启动被阻塞"的问题**，
下面这些都是**首帧之后**的 CPU/IO，用户感受是"进去之后首页数字跳一下"，不是黑屏。

**事实二（测出来的）：一次已同意态的冷启动，`SELECT` 共 74 条；`set_record` 查询 18 条，其中 6 条是
"没有 `workout_id` / `exercise_id` 条件的全表扫描"；`exercise` 20 条（逐动作 `byId` 的 N+1）；
`user_profile` 11 条。**（144 组历史、内存库、`logStatements` 统计。）

这 6 次全表扫描的来源（调用链，全部可核对）：

| # | 路径 | 出处 |
|---|---|---|
| 1 | `_refreshHome()` 读全部正式组 | `main.dart:625` → `drift_local_store.dart:169-175` |
| 2 | `_loadTodayPlan()` → `planToday()` 判断"是不是第一次训练"又读一遍全表 | `main.dart:734` → `today_planner.dart:394` |
| 3 | `_hintFor()` → `nextMuscleGroupKey()` → `recentExerciseIds()` | `main.dart:679-697` → `today_planner.dart:335-343` |
| 4 | **同一个 `nextMuscleGroupKey()` 里**，`nextTrainingDay()` 又读一次 `recentExerciseIds()` | `today_planner.dart:336` 与 `:313`（同一调用帧内重复） |
| 5 | `_loadTodayPlan()` → `nextTrainingDay()` 再读一次 | `main.dart:737` → `today_planner.dart:312-313` |
| 6 | `_syncReminder()` → `ReminderService.sync()` 又读全表（提醒开着时） | `main.dart:699-701` → `reminder_service.dart:115` |

另外 `_loadUnit()` 里的 `_hintFor`（`main.dart:561`）和 `_refreshHome` 里的 `_hintFor` 会各算一次提示行，
即上面的第 3 条至少跑两遍。**"今天练过"的分支才会走到 `nextMuscleGroupKey`**，所以没练过的用户少 2 次；
但表里第 1/2/5 条是所有人都有的。

**成本/收益（诚实标注）**：全表扫描本身是 O(总组数)。按 3 年 × 每周 3 练 × 20 组 ≈ 9,000 组估算，
单次扫描要在 SQLite 侧排序 + 在 Dart 侧建 9,000 个对象；**具体毫秒数待测**（需要真机或 profile build 的
DevTools timeline）。可确定的是：**读库次数与历史长度无关，而每次的代价与历史长度成正比**，
所以历史越长，重复次数越亏。

**建议（v1.68.2 已实施，见 §8）**：

- **A1（✅ 已实施）**：把"这次启动已经读到的 `sets` / `recentIds`"传下去，别让每个下游各读一遍。
  具体：`ReminderService.sync` 加可选的 `sets`（`reminder_service.dart:115` 的默认行为不变）；
  `_loadTodayPlan` 加可选的 `sets`（顺带把 `planToday` 的 `firstTime` 传进去，`today_planner.dart:394` 就不用再读）；
  `nextMuscleGroupKey()` 复用自己已经读到的 `recentIds` 调 `nextTrainingDay(recentIds: …)`（消掉第 4 条）。
  预期：6 次全表扫描 → 4 次（-33%）；`_hintFor` 出现两次的重复还能再消一次。成本 S/M，风险 L（纯参数化，不动 UI）。
  实际（同口径实测）：**6 → 4 次**；提醒开着 **8 → 4**；首启且今日计划尚未落库 **9 → 5**。
  另外把 `_importSeedQuietly()` 与 `_refreshHome()` 两次并发算计划的重复也收掉了（共享在读 future + 快照）。
- **A2（✅ 已实施，v1.68.2）：给"正式组按时间"这条查询加部分索引。**
  现在 `onCreate` 里只有 `idx_set_exercise (exercise_id, completed_at DESC)` 与
  `idx_set_workout_item`（`db.dart:765-773`），`allSets()` / `recentExerciseIds()` 的
  `where set_type='normal' and deleted_at is null order by completed_at` 用不上它们。
  收益：两处"全表扫 + 排序"变成"按索引顺序扫"（`EXPLAIN QUERY PLAN` 已实测会用上，见下）；
  历史越长收益越大；成本 M；风险 M（**迁移是唯一会碰老用户库的改动**）。

  **v31 迁移方案（先写在前面，再写代码）**

  1. **索引形状**：`CREATE INDEX IF NOT EXISTS idx_set_live_time ON set_record (completed_at)
     WHERE set_type = 'normal' AND deleted_at IS NULL`。
     - 为什么是部分索引：它只装"正式组且未删除"的行（热身/拉伸组与回收站不进来），比整表索引小；
     - **它真的会被用上**（这一点先验证过再写代码）：`node:sqlite` 里建同样的表/索引，
       `EXPLAIN QUERY PLAN SELECT * FROM set_record WHERE set_type = ? AND deleted_at IS NULL
       ORDER BY completed_at ASC` → `SCAN s USING INDEX p`（参数化不影响部分索引被采用；换成
       等值字面量结论相同）。对照组 `(set_type, deleted_at, completed_at)` 普通复合索引也有效
       （`SEARCH … USING COVERING INDEX`），但部分索引更小、语义就是这一条查询，故选它。
     - `idx_set_exercise (exercise_id, completed_at DESC)` 继续保留：它服务的是"单动作历史"
       那条查询（`lastSessionFor` / `setsForExercise`），与本索引不是替身关系。
  2. **改动点**：`app/lib/data/db.dart` —— `schemaVersion` 30 → 31；`onCreate` 里加这条索引
     （新装库从一开始就有）；`onUpgrade` **链尾**加 `if (from < 31) { customStatement(...) }`
     （老库走迁移这条路；`onCreate` 不会替它跑）。索引名与 SQL 只写在这一处，`data-model.md` 只记口径。
  3. **幂等**：`IF NOT EXISTS` + drift 的 `user_version` 机制 —— 已经到 v31 的库重复打开不会再进
     `onUpgrade`；每次打开都执行也不会重复建。**测试要真的用文件库开两次**验这一点（内存库测不出来）。
  4. **回滚**：本迁移**只加一个索引，不动任何一行的数据、不改任何列**，所以"回滚"的代价是零：
     如果 v31 后发现问题，下一个版本执行 `DROP INDEX IF EXISTS idx_set_live_time` 即可回到 v30 的
     查询计划（**不做 schemaVersion 降级** —— drift 打开"比代码更新"的库会直接报错，降级版本号
     是比索引本身危险得多的操作）。最坏情况（迁移抛异常）也只发生在 `CREATE INDEX` 上：DDL 在
     drift 的迁移事务里，失败会整体回滚，老库保持 v30 原样（App 会报打不开，不会留下半迁移状态）。
  5. **迁移测试**（`app/test/migration_test.dart` + `legacy_db.dart` 的 v30 fixture）：
     a) v30 老库打开 → 不崩、`idx_set_live_time` 真的存在、`EXPLAIN QUERY PLAN` 用上它、
        且 `allSets()` 的结果与迁移前用裸 SQL 查到的**逐条一致**（迁移前的结果在 `setup` 里先抓一份）；
     b) 新装库（`onCreate` 路径）同样有这条索引；
     c) 文件库：v30 → 打开（迁移）→ 关闭 → 再打开（v31 幂等）不崩、索引只有一条、数据行数不变；
     d) 迁移不碰老数据：正式组 / 热身组 / 已删除组混着放，迁移后三类的查询结果与迁移前一致。
  6. **同步文档**：`docs/data-model.md`（索引清单 + 这条索引的 WHERE 口径）、
     `docs/tech-decisions.md`（"为什么加一个只覆盖正式组的部分索引、为什么不改查询"的决策记录）。

### 1.2 drift 热查询：N+1 与"先全读再在 Dart 里筛"

| 位置 | 事实 | 影响 | 建议 |
|---|---|---|---|
| `drift_local_store.dart:169-175` `allSets()` | 无 `limit`、无日期窗；全表读出后在 Dart 建对象 | 冷启动/练完回来每条路径都读一次；`exercise_picker`、`progress`、`all_data`、`profile`、`backup` 等 7+ 处各自读（`grep 'allSets()' app/lib`） | A2 的索引；**不建议加缓存**（写入路径多，缓存失效比读全表更容易错） |
| `drift_local_store.dart:199-214` `recentExerciseIds()` | 全表读 + `ids.contains` 在最近一次训练的组里做 O(k²) 去重 | k = 一次训练的组数（10–20），可忽略；真正贵的是全表 | 用 SQL 取"最近一次 workout"的 id + `DISTINCT`，或配合 A1 只读一次 |
| `drift_local_store.dart:245-275` `lastSessionFor()` | 读出该动作**全部历史**再在 Dart 里取最后一次 | 单动作历史几十条，可接受；但 `planForGroup` 一次给 4 个动作 → 4 条查询（`today_planner.dart:453-454`） | 低优先；若要动，改成 `order by completed_at desc limit …` 再按 workout 取 |
| `drift_local_store.dart:178-196` `setsForExercise()` | `excludeWorkoutId` 在 Dart 里过滤（注释说明了原因：避开无法本机编译验证的 drift API） | 单动作量小 | 不动（注释里的取舍仍然成立） |
| `drift_local_store.dart:25-64` `saveSet()` | 写 `workout_item` 与 `set_record` 两条语句，**不在同一事务** | 不是性能问题，是"中途被杀会留下孤儿 workout_item"的正确性风险 | 包一层 `_db.transaction`（成本 S，风险 L）—— 但属 `app/lib` 改动，等拍板 |
| `backup_source.dart:104-125` `collectBackup()` | 1 次 `allSets` + 每个 workout 一次 `setsFor` + 一次 `loadWorkout`（而 `loadWorkout` 内部又调 `setsFor`，`drift_local_store.dart:114-126`）→ 约 **3 条/次训练** | 用户点"导出/云备份"才走；300 次训练 ≈ 900 条查询 | 低优先（用户可感知的是等待，待测）；可改成按 workout 一次查完再分组 |
| `drift_local_store.dart:295-309` 回收站 | 按 `deleted_at` 排序无索引 | 低频页面 | 跟 A2 一起加部分索引 |

**索引现状**：`db.dart:765-791` 建了 `set_exercise` / `set_workout_item` / `notification_ref` /
`workout_user_time` / `body_metric_date` / `routine_item_routine`。`docs/data-model.md:80-81` 的
`exercise(name)` / `exercise(muscle_group, popularity)` **在 drift 的 `onCreate` 里没有**（文档与实现在这里不一致，
影响的是动作库搜索/排序；351 条的表全扫也只有微秒级，**不建议为它单开一次迁移**，但要记一笔：下次本来就要迁移时一起补）。

### 1.3 列表重建：只有一处真正的长列表

全仓只有 **1 处**懒构建：`day_plan_editor.dart:188` 的 `ReorderableListView.builder`。
其余 `ListView(` 都是固定块数的小页面（十几行），不是热点。**唯一值得看的是动作选择器**：
`exercise_picker_screen.dart:500` 用 `ListView(children: children)` 一次性 build，浏览态最多 **500 个 `ListTile`**
（`limit: browsing ? 500 : 60`，`:160`；每个 tile 还带 `Key`、`onTap`、`onLongPress`、副标题）。
500 个 tile 一次性 build 在低端安卓上可能占 1–2 帧，**具体帧时间待测**（DevTools / profile build）。
改成 `ListView.builder` 是行为等价的重构，但**有一条真实风险**：现有 widget 测试用
`find.byKey('exercise-…')` 找屏幕外的行，懒构建后它们不会被建出来，测试要改成 `scrollUntilVisible`
（不是放宽断言，是补滚动；但属于测试改动）。成本 M，收益待测，**需要 lead 决定**。

"整树 setState" 检查：`HomeShell` 的 `setState`（`main.dart` 多处）会重建当前 tab 的外壳，
但二级页各有自己的 `State` 与 `_load()`；没发现"一个开关重画整个 500 行列表"的写法。
`progress_screen.dart:697` 每次 rebuild 会跑一次 `volumeSeries`（O(总组数)），10,000 组时约 10,000 次算术 ——
**不是瓶颈，不建议为它加记忆化**（多一处缓存状态，反而多一个会漂的真相）。

### 1.4 包体积：3.18 MiB 资源，其中 2.77 MiB 是有意为之

| 资源 | 真实字节 | 说明 |
|---|---|---|
| `assets/repdb-art/`（426 张 WebP） | **2,900,254 B = 2.77 MiB** | 226 个动作的动作插图；其中 **200 个动作各有 start+peak 两张**，26 个只有一张 |
| └ 其中 `*-peak.webp`（200 张） | 1,388,758 B = **1.32 MiB** | "顶峰位"第二张；界面有"起始/顶峰"切换（用户可见） |
| `fonts/Oswald-VariableFont_wght.ttf` | 172,088 B = 168 KiB | 只给数字/拉丁字母；许可随包（必要） |
| `assets/exercises.json` | 170,043 B = 166 KiB | 351 个动作的种子（必要） |
| `assets/repdb-art.json` | 41,651 B | 插图清单（必要） |
| `assets/privacy-policy.txt` | 30,507 B | 政策正文，商店要求应用内可读（必要） |
| `assets/collection-list.txt` | 11,644 B | 164 号文双清单（必要） |
| `fonts/OFL-Oswald.txt` | 8,000 B | 字体许可（必要） |

**可以去掉的候选只有一项**：200 张 peak 图 = 1.32 MiB。但"起始/顶峰切换"是**用户可见行为**，
去掉就得改界面与 `app/test/repdb_art_test.dart` —— **不是性能优化，是产品决定**，交 lead/用户拍板。
不建议做的事：把 320px 降到更低分辨率、或重新编码 WebP —— 会触发逐张看图（错配风险），
而这个体积只占商店包的一小部分；仓库已有 `tool/check-repdb-art.mjs` 守许可与清单，
真要做体积，应该加"单张 > 20 KiB 报警"这类可执行判据，而不是凭感觉重压。

### 1.5 `flutter test` 能测到的纯函数：没有值得优化的热点

- `progress_data.dart:137-153` `lastSevenDays` 是 **7×N** 的循环（每天扫一遍全量），
  `buildProgress` 再叠上 `personalBests` / `weekWorkoutCount` / `daysSinceLastPr` 等约 8 趟 O(N) + 一次排序
  （`progress_data.dart:380-405`）。N = 10,000 时总操作量 < 10⁵ 次、全是内存算术，**估算 < 2 ms**（无需 CI 测量）。
- 规则引擎 `progression.dart` 的 `suggestNext` 是 O(1) 的纯函数，输入是"上一次 + 处方"，与历史长度无关。
- `weeklyMuscleCounts` / `muscleBalanceHint` / `streak` 系列都是单趟 O(N)，且只在首页刷新时各算一次。

**结论：不把"合并纯函数遍历"当成优化项。** 这类改动的收益在毫秒以下，而它会动到有大量断言的
纯函数，收益/风险比不划算。

---

## 2. 服务端（`server/`）

### 2.1 SQL 预编译与索引

- `auth-store.mjs` 与 `backend-store.mjs` 里每个方法都**现场 `db.prepare(...)`**（前者 16 处、后者 6 处）。
  `node:sqlite` 的 `prepare` 是一次 SQLite 解析，量级是微秒到几十微秒；真正贵的是每次鉴权
  `resolveToken()` 要 prepare+执行两条语句（`auth-store.mjs:149-156`）。
  **建议（低优先，未做）**：按 SQL 文本缓存 `StatementSync`（一个 `Map`，SQL 都是常量，天然有界）。
  预期收益：请求 CPU 里的固定开销下降一点；**没有真实 QPS 数据，收益待测**，成本 S，风险 L（语句随 `db.close()` 释放要注意）。
- 索引：`auth_accounts_email`、`auth_tokens_account`、`auth_codes_lookup`、`auth_events_lookup`
  （`auth-store.mjs:52/62/74/83`）都在；`backend-store.mjs` 的主键查询也都有索引（主键即索引）。
  `prune()` 的 `delete from auth_events where at < ?`（`auth-store.mjs:242-243`）**没有 `at` 单列索引**，
  它现在只在"发码成功 / 登录成功"时调用（`auth.mjs:219/285`），所以频率低；若按 §2.3 改成失败路径也清，
  必须先加索引（否则每次失败登录变成一次全表删）。**加索引属于服务端 schema 改动**，跟 §2.3 一起拍板。

### 2.2 请求体上限：三处都已是有界、可读的拒绝

| 入口 | 上限 | 超限行为 | 出处 |
|---|---|---|---|
| `PUT /v1/backup` | 8 MiB | **先读完再回 413**（不掐断连接，注释里记了踩坑） | `backend.mjs:75-92`、`:168-173`、`backend-store.mjs:26` |
| `POST /v1/auth/*` | 8 KiB | 回 400/413（`readBody` 的 `tooLarge`） | `auth.mjs:167-171` |
| `POST /v1/events`（收集端） | 5 MiB | **本轮修**：原先是 `req.destroy()`，客户端拿到 socket reset；现在读完回 413（§6.1） | `collector.mjs` 的 `MAX_BODY_BYTES` |

### 2.3 鉴权/限流：正确性没问题，但"失败登录事件"可以无界增长

- 正确性核过的点：令牌只在库里存 sha256、前缀 `lm1_` 让"已吊销"回 401 不退回 404（`auth-store.mjs:26-36`）；
  `resolveToken` 明确排除 `revoked_at`；登录失败与不存在的邮箱走同一条耗时路径（`auth.mjs:270-275`，
  不存在的邮箱也做一次 scrypt）；`/v1/auth/salt` 对不存在邮箱回 HMAC 假盐（`auth.mjs:188-192`）；
  发信限流是"每邮箱 60 秒 1 条 / 24 小时 10 条 + 全局每日 200"（`auth.mjs:198-220`），不按 IP（设计决定）。
- **无界增长的那一处**：登录失败只 `recordEvent('login_fail', email)`（`auth.mjs:278`，key 是邮箱），
  而 `prune()` 只在成功路径跑。每邮箱 15 分钟内失败 10 次后该邮箱不再写（`auth.mjs:269`），
  但**换邮箱就能继续写**，且没有任何全局失败上限 → `auth_events` 可以随攻击时间线性增长（直到成功登录/发码触发一次 prune，
  而攻击者不会成功）。**这是存储型 DoS 面，不是性能热点。**
  - 方案 1（改行为，需拍板）：加"全局失败登录上限/窗口"，超出直接 429。
  - 方案 2（不改响应）：给 `at` 加索引 + 失败路径按节流（如每 100 次）调 `prune()`；仍是"删除追不上写入"的窗口期，
    只能防长期堆积，不防持续攻击。
  - **✅ 已拍板并落地（v1.68.2）**：方案 1 + 2 结合 —— 全局失败上限（300 次 / 15 分钟，超出回
    429 + `Retry-After`）**加上**节流 prune（失败路径也会清，但最多每 60 秒一次全表删）。
    接口语义不变（普通失败仍 401、不带 `Retry-After`）。判据在 `server/auth.selftest.mjs`（15 条）。
  - **⚠️ 复核后改过一次检查位置（2026-11-05，同一版内）**：全局 cap 的 429 判断放在**口令校验之后**，
    只拦"本来就会失败"的请求。原先它排在校验之前 —— 那样攻击者只要用 300 次错误口令，
    就能让**所有用户**（包括口令正确的）在 15 分钟里全部 429：那是把"存储 DoS"换成了
    **登录可用性 DoS**（云备份/取回依赖登录，等于把整个账号功能一起打掉）。
    **代价如实记**：达到上限后每次失败仍然要**先付一次 scrypt**（CPU 成本不受这道闸门保护），
    换的是"口令正确的用户永远登得进来"；存储侧则停在 cap —— 被 429 的那次**不记事件**，
    所以表不会继续长。每邮箱上限的 429 位置**没动**（那是既有行为：同一个邮箱连续失败 10 次，
    连正确口令也先挡 15 分钟；它挡的是单个账号、不是整台服务）。
    判据是 selftest 里那条 ★："全局 cap 打满时，口令正确的用户仍能登录（200）"—— 旧写法在这一条上必红。
- 另外 scrypt `N=16384`（`auth.mjs:64-79`）每次登录/注册要几十毫秒 —— 这是**反暴力破解的成本，不是缺陷**；
  已有每邮箱失败窗口，不建议调低。

### 2.4 collector 落盘策略：已修（见 §6.1）

原实现每条事件一次 `mkdirSync` + `appendFileSync`（同步 I/O，整段挡住事件循环）。
现在按"批内按天分组、每天一次追加"；同一天内事件顺序不变，跨天本来就写两个文件，落盘内容逐字节不变。
**不建议**进一步改成异步写：现在的同步写保证"202 返回时数据已落盘"，异步会引入"回了 202 但没写下去"的窗口，
而这条链路的合规要求是"别丢"。

### 2.5 错误处理里可能的未捕获异常

- `createBackend` 的请求回调是 **async**（`backend.mjs:101`），`catch` 里先 `console.error` 再 `json(res, 500)`
  （`:206-211`）。如果异常发生在**响应头已经发出之后**（例如 `GET /v1/backup` 写 body 时客户端断开），
  `json()` 会抛 `ERR_HTTP_HEADERS_SENT`；这个异常发生在 `catch` 内、而外层没有第二层捕获，
  会成为 **unhandled rejection**（Node 默认退出）。触发条件苛刻（客户端下载中主动断连），
  但修法很便宜：`catch` 里判断 `if (!res.headersSent && !res.writableEnded)` 再写响应，
  并用注入的 `log` 而不是 `console.error`（`backend.mjs:208` 是唯一一处绕过注入 log 的地方，自检抓不到它）。
  成本 S，风险 L，收益是"进程不被一个断连带走"。**本轮没动**（边界：服务端改动也只做了收集端两个明确目标）。
- `readBody` 的 `req.on('error')` 已经兜底（`backend.mjs:90`）；`collector` 的 `req.on('end')` 现在写盘包了 try/catch，
  失败回 500 而不是让异常从回调里抛出去（`server/collector.mjs` 的 `handleBatch`）。
- `mailer.mjs` 每封信新建一条 TLS 连接（`mailer.mjs:165-167`），没有连接复用；在"全局 200 封/天"的量级下
  **不值得做连接池**（省下的握手时间 ≪ 维护成本）。

---

## 3. 工程效率（`./verify.sh` 六层）

### 3.1 实测耗时分布（这台机器，热 pub cache）

| 层 | 热跑（已有 `.dart_tool`） | 冷引导（移走 `.dart_tool` + `db.g.dart`） | 里面最贵的是什么 |
|---|---:|---:|---|
| `[0]` pub get | 0s | **1s**（pub cache 已热） | 真正从零的 CI 要下载依赖（**待测**，见 §3.3） |
| `[0]` build_runner | 0s | **26s** | `dart run build_runner build`（生成 `db.g.dart`） |
| `[1]` 动作库 | 1s | <1s | 种子构建 + 三份一致性检查 |
| `[2]` JS 引擎 + 守卫 | **31s** | **32s** | **其中 24s 是 `check-screenshots.mjs --selftest`**（已在本轮修到 1.3s，§6.2） |
| `[3]` Dart 领域层 | <1s | <1s | 60 条向量，纯 Dart |
| `[4]` 静态分析 | **7s** | **30s** | `dart analyze --fatal-infos`（分析服务器冷启动占大头） |
| `[5]` Flutter 测试 | **60s** | **60s** | 1787 项；其中云备份端到端真的起 Node 服务端 |
| `[6]` 变异测试 | **3s** | 4s | 24 个变异体各跑一遍相关测试 |
| **合计** | **102s**（修 §6.2 之前） | **153s**（冷引导） | 修完 §6.2 之后热跑实测 **68s**（差里的 24s 确定来自截图自检；其余是第 5 层的机器波动） |

> 与 README 里"约 8 分钟"的差距来自"缓存热不热"：8 分钟那是以往**从零下载依赖 + 首次编译 native assets**
> 的口径。CI 上还有下载依赖与 native assets 构建，**CI 实际墙钟待测**（需要一次真实 run 才能说，别拿本机数字替代）。

### 3.2 可以省的地方（按"省的时间 / 风险"排）

1. **已做**：`check-screenshots --selftest` 24s → 1.34s（§6.2）。修前热跑 102s、修后热跑 **68s**（同一天两次实测，见 §6.2）。
2. **不建议做**：把第 2 层剩下的 ~28 个 node 自检并行化。修完截图那条之后第 2 层只剩约 8s，
   并行化要重构 `verify.sh` 的 `selfcheck()`（共享 `$LOG`），收益 < 5s、风险却是门禁本身。
3. **需要拍板**：`[2]` 与 `[4]` 并行（两者互不读对方的产物）。热跑最多省 ~7s，冷跑最多省 ~8s；
   风险是 CPU 争抢让第 5 层的云备份端到端（会起本地服务端并等端口）偶发超时 —— **要改就单独一轮验证稳定性**。
4. **需要拍板（CI 配置）**：给 CI 加 `actions/cache` 缓存 `~/.pub-cache`（key 用 `pubspec.lock` 的哈希）。
   这不会让门禁少跑任何一步（`tool/check-ci.mjs` 只禁止"门禁不管的 `run:` 命令"，缓存 action 不是检查），
   但**它是一条新的 CI 依赖**，要 lead 同意；收益取决于 CI 网络（待测）。
5. **不做**：把 `flutter test` 分片到多个 job —— 那会破坏"CI 跑的就是 `./verify.sh` 本身"这条承诺（`tool/check-ci.mjs` 第 1/3 条会红）。

### 3.3 CI 时长

只核了"逻辑上的构成"：本机热跑 102s / 冷引导 153s；CI 额外要 **checkout + 装 Flutter SDK + 下载依赖
（现在走与锁文件一致的镜像）+ 首次 native assets 编译**，所以我**不写 CI 的具体分钟数**（待测；
量法：在 CI 里给 `./verify.sh` 前后加时间戳，或直接读 workflow 的 step 耗时）。

---

## 4. 优先级排序

维度：**收益**（对用户/对发布风险）、**成本**（改动面 + 验证成本）、**风险**（引入新问题的可能）。
"拍板"列写"已做"的表示本轮已落地并有判据；写"lead/用户"的表示**本轮没动**。

| # | 事项 | 收益 | 成本 | 风险 | 证据 | 拍板 |
|---|---|---|---|---|---|---|
| P0 | CI 的 registry 与 `pubspec.lock` 对齐 + build_runner 精确钉版 | **高**（消灭不可复现的 CI 红） | S | L | §5；`node tool/check-ci.mjs` + 新增 4 条自检 | ✅ 已做 |
| P1 | 截图守卫自检夹具复用 + 压缩档位 | 中（每次门禁省 ~23s） | S | L | 23.66s → 1.34s，12 条用例不变 | ✅ 已做 |
| P1 | 收集端按天批量落盘 + 超限回 413 | 中（一批 100 条：6000 次同步调用 → 30 次；实测 60.5×） | S | L | §6.1 的对照实验 + 自检断言 | ✅ 已做 |
| P2 | 冷启动共享读库（A1） | 中（全表扫 6→4 同口径；随历史增长放大） | M | L | 见 §8 的对照测量（旧 9/8/6 → 新 5/4/4） | ✅ 已做（v1.68.2） |
| P2 | `set_record` 部分索引（A2） | 中高（长期；所有"读全部组"的路径） | M | M | §1.1 的迁移方案 + `migration_test.dart` 的 v30→v31 用例（索引真的被查询计划用上） | ✅ 已做（v31 引入，当前 v32） |
| P3 | 动作选择器 `ListView.builder` | 中（旧实现一次 build 500 个 tile） | M | M（测试补懒构建判据） | §1.3；新测试断言同屏 tile < 50 且滚到底仍能到达 | ✅ 已做（v1.68.2） |
| P3 | 失败登录事件表全局上限 / 索引 + 节流 prune | 中（存储 DoS 面） | M | M（改安全策略/行为） | §2.3；`auth.selftest.mjs` 15 条新判据 | ✅ 已做（v1.68.2） |
| P3 | `saveSet` 两条写进同一事务 | 低（正确性兜底） | S | L | §1.2；`save_set_transaction_test.dart`（触发器让第二刀必炸） | ✅ 已做（v1.68.2） |
| P3 | `auth-store`/`backend-store` prepared statement 缓存 | 低（无 QPS 数据，待测） | S | L | §2.1 | 可自行做（服务端），本轮未做 |
| P3 | 备份导出 N+1（约 3 条/次训练） | 低（用户主动操作，待测） | M | L | §1.2 | lead（`app/lib`） |
| P4 | 去掉 200 张 peak 图（-1.32 MiB） | 低（包体积） | M | M（改用户可见行为） | §1.4 | 用户 |
| P4 | CI 加 pub cache | 待测（看 CI 网络） | S | L | §3.2 | lead |
| P4 | `catch` 里防 `ERR_HTTP_HEADERS_SENT` + 用注入 log | 低（健壮性） | S | L | §2.5 | 可自行做，本轮未做 |
| — | 纯函数合并遍历、progress 列表优化、并行化第 2 层、异步落盘 | **不建议做** | — | — | §1.5/§3.2/§2.4 | — |

**一句话读法**：P0/P1/P2 与大部分 P3 已在 v1.68.2 落地（见 §8）；剩下没做的是**收益低或需要产品/安全决策**的
P3/P4（prepared cache、备份 N+1、去 peak 图、CI 缓存、并行化），以及审计判为"不建议做"的那几项。

---

## 5. B：依赖 / CI 确定性（已落地）

### 5.1 事故的机制（为什么它会"时红时绿"）

- `app/pubspec.lock` 里 **103 个 hosted 依赖**的 `url:` 都是 `https://pub.flutter-io.cn`（开发机走国内镜像，
  见 `README.md`「五个环境坑」第 5 条）。CI 不设 `PUB_HOSTED_URL`，默认 `https://pub.dev`。
- pub 把 **registry 地址当成包身份的一部分**：CI 上的默认源与锁文件里的 `url:` 不一致时，锁文件里那些条目
  会被当作"另一个源的包"而不被采用，pub 于是按 `pubspec.yaml` 的 `^` 约束**重新解析最新版**。
  `build_runner: ^2.16.1` 在这一步解析到了 **2.16.2**；那一版在本 Dart SDK 上编译报
  `BuildStepImpl is missing implementations` → `db.g.dart` 没生成 → 第 4–6 层全红。
- 2026-11-04 再跑又绿：说明这不是"版本坏了"，而是**锁文件有没有被采纳**取决于当时解析到了什么。
  不可复现的漂移必须**从结构上**消灭，不能靠重跑。

### 5.2 改了什么

| 文件 | 改动 | 判据 |
|---|---|---|
| `.github/workflows/ci.yml` | job 级 `env: PUB_HOSTED_URL: https://pub.flutter-io.cn`（与锁文件同一个值），头部写明原因 | 文件里有、值等于锁文件 |
| `app/pubspec.yaml` | `build_runner: 2.16.1`（精确版，去掉 `^`） | 锁文件里仍是 2.16.1；`flutter pub get` 后锁文件**零 diff**（已实测） |
| `tool/check-ci.mjs` | 新增第 7 条：CI 的 registry（不写 = `https://pub.dev`）必须**等于** `app/pubspec.lock` 里的 `url:`；并新增 4 条自检用例（CI 不声明 registry / 抄错 / 锁换到 pub.dev / 锁里读不出 url）。头部从"五件事"改为"七件事" | `node tool/check-ci.mjs` 绿 + `--selftest` 16/16 |

### 5.3 为什么这样能防住那次红

1. **锁文件重新成为唯一真源**：CI 与锁文件同一个 registry → pub 直接采用锁里 103 个版本，不做"按 `^` 重新解析"。
   `build_runner` 只可能是 2.16.1 —— 不是"这次恰好没升"，而是"没有升级这条路径"。
2. **第二道锁**：即使有人在**另一个 registry** 上跑 `pub get`（锁文件的 `url:` 会被重写完），
   精确版 `2.16.1` 也保证 build_runner 不会变成 2.16.2。这是对"事故的具体版本"的兜底，
   而第 1 条是对"整个依赖图"的兜底。
3. **守卫会红**：删掉 `PUB_HOSTED_URL`、抄错一个字符、或把锁文件换源而不改 CI，`node tool/check-ci.mjs`
   都会判红 —— 它在 `verify.sh:667` 有**真实运行**（不是只有自检），所以本地门禁与 CI 同步能发现。

### 5.4 残余风险（如实记）

- CI 从此依赖 `pub.flutter-io.cn` 的可达性（之前依赖 pub.dev，同样有单点）。**不建议加自动 fallback**：
  一 fallback 就回到"两个源，锁文件可能不被采纳"的原始问题。镜像真的挂了，应该像任何源故障一样红一次、再修。
- 没有把锁文件改回 pub.dev 的理由：开发机的 `PUB_HOSTED_URL` 就是镜像（`README.md` 的推荐做法），
  锁文件与本地环境一致，本地 `verify.sh` 才不会每次 `pub get` 都重写锁；CI 对齐锁文件比全仓改源小得多。

---

## 6. C：本轮实现的两个低风险优化

### 6.1 收集端：一批事件只落一次盘 + 超限回 413

**出处**：`server/collector.mjs` 原第 47-64 行（每条事件 `mkdirSync` + `appendFileSync`）、第 91-95 行（超限 `req.destroy()`）。
**改法**：`handleBatch` 先把收下的事件按天分组，再每天一次 `appendDayFile`（导出的默认实现仍是 mkdir+append）；
`POST /v1/events` 超 `MAX_BODY_BYTES` 时不再缓存但读完请求，回 **413 + 说清上限**（与 `backend.mjs` 的 `readBody` 同一条教训）；
落盘失败回 500 且不计入 `/healthz` 的 `events`。`appendDayFile` 做成可注入（`writeDayFile`），自检才能**数**落盘次数。

**改前/改后证据（同一台机器、同一批数据）**：

| 指标 | 改前 | 改后 |
|---|---:|---:|
| 30 批 × 100 条事件的同步文件调用 | 6,000 次 | **30 次** |
| 同上，耗时 | 401.6 ms | **6.6 ms（60.5×）** |
| 6 MiB 请求体（上限 5 MiB） | 客户端 `fetch failed`（socket reset） | **HTTP 413** `{"error":"请求体超过上限 5242880 字节"}` |
| 落盘内容 | — | 逐字节不变（同一天顺序不变；跨天仍是两个文件） |

**新增判据**（`server/collector.selftest.mjs`，`verify.sh` 第 2 层跑）：同一批 2 条只写 1 次；跨天批 2 条写 2 次（各一天）；
落盘失败回 500 且不计 events；小上限下超大请求体回 413 且错误里带上限数字。这些断言在旧实现上都会失败
（旧实现没有 `writeDayFile` 参数、也没有 413 这条路径）。

### 6.2 截图守卫自检：24s → 1.34s（同一条判据，不放松）

**出处**：`tool/check-screenshots.mjs` 的自检为 12 条用例各造一棵夹具树，每棵 46 张 1080×2400 的 PNG，
`tool/lib/png.mjs` 用 zlib **level 9** 压缩纯色占位图 —— 12 × 46 ≈ 550 张图、每张压缩 10 MB 原始数据，
`--selftest` 实测 **23.66s**，在门禁第 2 层里占 **24s/153s（16%）**。
**改法**：夹具模板**只造一次**，每条用例 `cpSync` 一份（用例仍然互相隔离）；夹具 PNG 用 `level: 1`
（占位图只验尺寸/通道/位深，内容不参与判据）；`writePng` 的默认仍是 level 9，**真实截图/特征图不受影响**。

**改前/改后**：`/usr/bin/time -p node tool/check-screenshots.mjs --selftest`
**23.66s → 1.34s（17.6×）**；整条门禁热跑 **102s → 68s**（同一台机器、同一天，`./verify.sh` 末尾均为
「未发现失败」、1787 项测试全绿）；12 条用例逐条仍绿（少一张 / 那道门 / 失败现场图 / 尺寸 / 混入 / 整套没了 /
RGBA / 16 位 / 三处文档数字与点名都对不上）。**判据一条没少、没放宽**：改的是夹具的生成方式，不是检查逻辑。

**没做的 C（以及为什么）**：客户端冷启动那 6 次全表扫描（§1.1 的 A1/A2）是清单里收益最大的一处，
但它要动 `app/lib`（涉及是否切版）或数据库 schema（涉及迁移）—— 按边界**只写方案，不动代码**，交 lead 拍板。

---

## 7. 需要 lead / 用户拍板的事项

> 2026-11-05 晚：用户拍板"P2/P3 三项全做 + 切 v1.68.2"，第 1–4 条已落地（§8）。
> 仍然**只有下面三条**需要拍板；其余都已做完。

1. ✅ **已拍板**：动 `app/lib`（切版 v1.68.2）—— A1 共享读库、`saveSet` 事务、选择器懒构建全部落地。
2. ✅ **已拍板并落地**：部分索引（v31 引入，当前 schema 已是 **v32**；迁移方案 §1.1，测试在 `migration_test.dart`）。
3. ✅ **已拍板并落地**：失败登录事件**全局上限 + 429 Retry-After + 节流 prune**（§2.3）。
4. ✅ **已拍板并落地**：动作选择器 `ListView.builder`（§1.3，补了懒构建判据与滚动测试）。
5. ⬜ **包体积**：200 张 peak 图（1.32 MiB）去留 —— 用户可见功能，不由工程单方决定。
6. ⬜ **CI 加 `actions/cache` 缓存 pub**（§3.2）：会加一条 CI 依赖，收益取决于 CI 网络，需要 lead 同意。
7. ⬜ **第 2 层与第 4 层并行**（§3.2）：收益 7–8s，但会改变门禁执行顺序、需要单独验稳定性；要不要冒这个险。
8. ✅ **已切版**：v1.68.2（`app_info.dart` / `pubspec.yaml` / CHANGELOG / README / release-checklist /
   your-todo / 软著源程序量全部同步；**不重出** APK/AAB/截图/软著 PDF，按用户指示）。

---

## 8. 落地回执（2026-11-05 晚，v1.68.2）

用户拍板后，本清单的 P2/P3 全部落地。这里只记**改前/改后证据**与判据位置，机制解释在上面各节。

| 改动 | 改前 → 改后（同一台机器、同一组夹具） | 判据 |
|---|---|---|
| 部分索引（v31 引入，当前 v32） | 无索引（`EXPLAIN QUERY PLAN` 全表扫 + 排序）→ `SCAN … USING INDEX idx_set_live_time` | `migration_test.dart`：v30→v31 索引存在 + 计划用上 + 结果与迁移前逐条一致 + 热身组/删除组不受影响 + 文件库重复打开幂等 + 新装库 `onCreate` 也有 |
| 冷启动共享读库（A1） | 全表扫：**旧 9 / 8 / 6 → 新 5 / 4 / 4**（依次为：种子导入+提醒开 / 种子跳过+提醒开 / 种子导入+提醒关；审计同口径那次是 6） | `today_planner_test.dart`（`nextMuscleGroupKey` 读 1 次、传 `recentIds` 读 0 次）+ `reminder_test.dart`（传 `sets` 读 0 次、不传时行为一致、两条路同一条提醒） |
| `saveSet` 同事务 | 第二刀失败会留下孤儿 `workout_item` → 两行一起回滚 | `save_set_transaction_test.dart`（SQLite 触发器必炸） |
| 选择器懒构建 | 浏览态一次 build 351（最多 500）个 tile → 同屏只建视口内的（测试断言 < 50），滚到底仍能到达 | `exercise_picker_test.dart` 新增懒构建判据 + 既有 38 条分区/筛选/搜索测试不变 |
| 登录全局限流 | 换邮箱可无限写 `auth_events` → 全局 300 次 / 15 分钟即 429 + `Retry-After`；**429 排在口令校验之后**（cap 打满时口令正确仍 200；被 429 的那次不记事件）；失败路径也节流 prune（≤1 次/60s） | `auth.selftest.mjs` 新增 15 条（跨邮箱 429、Retry-After 正整数、普通失败无该头、**cap 打满时正确口令仍 200**、被 429 不记事件、窗口滑过自动恢复、失败路径触发 prune、49h 前事件真被剪、TTL 内不误删、窗口内不重复 prune、过窗恢复） |
| 工程效率（第一轮） | 收集端 6,000→30 次同步写（60.5×）；截图自检 23.66s→1.34s（17.6×，整条门禁 102s→68–71s） | `collector.selftest.mjs` / `check-screenshots.mjs --selftest` |

**门禁**：完整 `./verify.sh` 六层「未发现失败」，测试 **1787 项**（v1.68.2 新增 9 项、v1.68.3 新增 29 项）；变异 24 杀 / 0 存活。
**不重出**：APK / AAB / 商店截图 / 软著 PDF（本机无 keystore，用户未说"部署"；`dist/` 为空时守卫如实跳过）。
