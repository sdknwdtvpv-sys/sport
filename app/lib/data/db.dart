/// 练了么 · drift 表结构（SQLite）
///
/// **本文件是 `docs/data-model.md` 的可执行版本。** 字段、索引、`updated_at` / `deleted_at`
/// 都照那份 DDL 一一对应，不自行发挥。表名与列名走 drift 默认的 snake_case 转换，
/// 结果与文档完全一致（`WorkoutItem` → `workout_item`，`nameEn` → `name_en`）。
///
/// 范围说明：本阶段只落地**跑通持久化所必需**的 4 张表。
/// 其余 7 张（routine / routine_item / body_metric / personal_record /
/// suggestion_log / user_profile / 以及 sync_outbox）等各自功能落地时再加——
/// 一次定义全部表只会增加我无法验证的表面积。
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

/// 动作库。种子数据见 `seed/exercises.sql`（318 条，已用 sqlite3 实测导入）。
class Exercise extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get aliases => text().withDefault(const Constant('[]'))();
  TextColumn get muscleGroup => text()();
  TextColumn get secondaryMuscles => text().withDefault(const Constant('[]'))();
  TextColumn get equipment => text()();

  /// strength | warmup | stretch —— **决定它会不会进「今天练什么」的推荐**。
  ///
  /// 热身与拉伸是动作库的正常成员（能被搜到、能被选、能被记成一组），
  /// 但它们不该当"今天练哪个部位"的答案。2026-09-29 之前它们根本不在库里 ——
  /// 当时的做法是整类排除，那就连"练完拉一下"都记不了。类别比排除诚实。
  ///
  /// 缺省 'strength'：老库（v3）升上来时没有任何一行是热身/拉伸，缺省值就是正确答案。
  TextColumn get category => text().withDefault(const Constant('strength'))();

  TextColumn get trackType => text().withDefault(const Constant('weight_reps'))();
  IntColumn get defaultRestSec => integer().withDefault(const Constant(90))();
  RealColumn get defaultWeightKg => real().nullable()();

  /// **动作说明**（一两句话说清"怎么做 + 最常见的一个错"）。null = 还没写。
  ///
  /// 2026-09-29 加。动作库有 351 个动作而 App 里只有**名字** —— 对"垫脚高脚杯深蹲"这种
  /// 名字，新人看不出是在干什么。这一列是内容债的**可见形式**：有就是有，没有就是 null，
  /// `tool/content-report.mjs` 会把覆盖率与待写队列打出来。
  ///
  /// 只写"要点"，不写长文：选择器的一行放得下（≤ 80 字），也不至于让人在健身房读论文。
  TextColumn get instructions => text().nullable()();

  /// **距离处方：每组多少米**（`distance_time` 动作专用，其余恒 null）。
  ///
  /// 2026-09-29 加。之前距离类动作"能记但不被推荐"，因为处方只有"多少次 / 多少秒"
  /// 两种形态，开不出"走 20 米"。有了这一列，「今天练什么」才敢推荐农夫行走，
  /// 训练屏也才有默认距离可用（首次练时拿它当起点）。
  ///
  /// 为什么写在种子里而不是代码里推导：5 公里跑与 20 米农夫行走差两个数量级，
  /// 任何"默认 3000 米"都是编数据。见 `seed/upstream-zh-names.json` 的约定。
  RealColumn get defaultTargetDistanceM => real().nullable()();
  RealColumn get weightIncrement => real().withDefault(const Constant(2.5))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  IntColumn get popularity => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 埋点的本机身份与会话（`docs/analytics.md` §2.1 的公共字段靠它）。
///
/// **为什么不塞进 `user_profile`**：那张表的每一列都是"用户能看见、能改的设置"，
/// 而且它的写入路径有一堆"必须把其它列原样带回去"的坑（见 ProfileRepository 的注释）。
/// 设备 ID / 会话 ID 是**埋点的记账**，不是用户设置 —— 放一起只会让两边都更容易写错。
///
/// 只有一行（`id = 'local'`）。
class AnalyticsMeta extends Table {
  TextColumn get id => text()();

  /// 设备匿名 ID。随机生成、与任何账号信息无关（`docs/analytics.md` §6）。
  TextColumn get deviceId => text()();

  /// 当前会话 ID。30 分钟无事件即换新会话。
  TextColumn get sessionId => text()();

  /// 上一条事件的时间。判断会话是否过期用它，不是用"App 启动时间"。
  IntColumn get sessionLastAt => integer()();

  /// 首次冷启动的时间。null = 还没开过 → `app_open.is_first_open = true`。
  /// **北极星的分母完全靠它**（"首次 app_open 起 24 小时内"），所以必须落库。
  IntColumn get firstOpenAt => integer().nullable()();

  /// **接入上报之后是否已经清过历史积压**（2026-10-04，`docs/analytics.md` §10 的 B 方案）。
  ///
  /// null = 还没清过。非 null = 清理发生的时刻。
  /// 为什么要有这一位：没配上报地址的包**不会丢事件，只会一直攒**（上限 10000 条）。
  /// 那些积压是用户在"不上报的包"里产生的 —— 那时候我们**没有**告诉过他数据会被发出去，
  /// 接上地址的那天把它们补传，等于事后改主意。所以：**谁记的谁发**，
  /// 第一次在"配了地址的包"里冷启动时，先把积压清掉、把这一位写上，之后再正常发。
  IntColumn get legacyPurgedAt => integer().nullable()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 一次训练。
class Workout extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get routineId => text().nullable()();

  /// in_progress | finished
  /// （领域模型 `Workout` 目前还没有 status 字段，见 saveWorkout 的说明）
  TextColumn get status => text().withDefault(const Constant('in_progress'))();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get durationSec => integer().nullable()();
  RealColumn get totalVolume => real().nullable()();
  IntColumn get totalSets => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 训练中的一个动作。同一次训练里的多组记录挂在这个 id 下。
class WorkoutItem extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 一组记录。近似 append-only —— 训练数据是资产，可回溯高于存储成本。
class SetRecord extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text()();
  TextColumn get workoutItemId => text()();

  /// 冗余字段：避免算"上次同动作"时做三表 JOIN（引擎的热路径）
  TextColumn get exerciseId => text()();
  IntColumn get setIndex => integer()();

  /// normal | warmup
  TextColumn get setType => text().withDefault(const Constant('normal'))();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();

  /// **距离（米）**。只有 `track_type = distance_time` 的动作会写它
  /// （跑步机、划船机、跳绳、农夫行走…）；其余动作恒为 null。
  ///
  /// 为什么存米而不是公里：与"重量一律存 kg"同一条规矩 ——
  /// **存储不跟显示单位走**。5.25 公里的浮点表示会随显示单位变（英里 3.26），
  /// 而米是整数友好的最小单位，算配速（秒/公里）时也不用再乘一次 1000。
  RealColumn get distanceM => real().nullable()();

  RealColumn get rpe => real().nullable()();
  IntColumn get restSecActual => integer().nullable()();
  BoolColumn get isPr => boolean().withDefault(const Constant(false))();
  RealColumn get volume => real().nullable()();
  IntColumn get completedAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 用户档案。单行（本地只有一个用户），存设置项。
///
/// 只有 `progression_mode` 现在真的被用到（S10「我」的渐进建议开关）；
/// 其余列照 `docs/data-model.md` 先建好，等对应功能落地时再用。
class UserProfile extends Table {
  TextColumn get userId => text()();
  TextColumn get goal => text().nullable()();
  IntColumn get weeklyFrequency => integer().nullable()();

  /// kg | lb。**训练重量**的显示单位；存储与引擎始终是 kg（见 core/units.dart）
  TextColumn get unitPref => text().withDefault(const Constant('kg'))();

  /// kg | jin。**体重**的显示单位，与训练重量分开。
  ///
  /// 2026-09-29 用户提出："体重钉死在千克和斤之间切换"。
  /// 中国用户称体重说斤（1 斤 = 500 g），而杠铃重量说 kg —— 一个开关管两件事
  /// 就会打架（把训练切到 lb 的人，体重也不该跟着变磅）。存储同样是 kg。
  TextColumn get bodyWeightUnit => text().withDefault(const Constant('kg'))();
  IntColumn get defaultRestSec => integer().withDefault(const Constant(90))();

  /// double | linear | off
  TextColumn get progressionMode => text().withDefault(const Constant('double'))();

  /// 身高（cm）。2026-10-05，v20。**只用来算 BMI**（BMI = 体重 ÷ 身高²）。
  ///
  /// 可空是刻意的：不填就**不显示 BMI**，而不是拿一个默认身高去编一个数出来 ——
  /// 编出来的 BMI 比没有 BMI 更糟。
  /// 它同样是身体数据（敏感个人信息），与体重共享那一道单独同意门。
  RealColumn get heightCm => real().nullable()();

  /// **昵称**（2026-10-07，v24，10.7 清单第 7 条）。可空 = 没设过。
  ///
  /// 用户原话："现在账户只展示【我】，没办法有用户的名字，很难有身份感。能不能昵称+ID？"
  ///
  /// ⚠️ 三条边界写在列上，免得以后有人拿它当"账号"用：
  ///   * **纯本地**：它不进云备份的合并键、不上报（埋点不带身份，见 privacy-facts）、
  ///     也没打算做"分享名片"那类东西；
  ///   * **可空**：没设过就是 null，界面如实写"还没设昵称"，**不编一个默认名**；
  ///   * 与 `auth_session.email` 无关 —— 昵称不是身份，ID 才是（ID 取账号密钥哈希前缀，
  ///     没登录就不显示 ID，见 `profile_screen.dart` 的身份块）。
  TextColumn get nickname => text().nullable()();

  /// 「帮助改进产品」开关。关掉后除崩溃外一律不上报（见 analytics-sdk.md §10）。
  ///
  /// **默认开启**（2026-10-07，v23 —— 用户在原话里问"帮助改进产品能不能默认打开？"
  /// 并明确选了"真改成开"，见 `docs/plan-ux-2026-10-07.md` §三·9 那张施工单）。
  ///
  /// ⚠️ 这一格的历史**必须连着读**，不然下一个人会以为是手滑翻的：
  ///   1. 很久以前是默认开（但政策只写"可以随时关掉"，"默认同意"在 PIPL 下站不住）；
  ///   2. **2026-09-30（v13）改成默认关**，并且**有一条迁移把老库的 true 翻成 0**；
  ///   3. **2026-10-07（v23）又改回默认开** —— 这次是**用户知情的决定**，
  ///      所以政策中英、首启同意屏、商店两张表、`privacy-facts.json` 与
  ///      `tool/privacy-audit.mjs` 的判据方向**同一趟全部翻过来**（少翻一处就是假话）。
  ///
  /// ⚠️ **v23 不搬任何数据**：这一行的默认值只影响"还没有那一行"的机器（= 新装）。
  /// 存量机器当年看到的是"默认关闭"，**不静默翻转**（迁移链尾有专门一段与一条测试钉着）。
  ///
  /// `tool/privacy-audit.mjs` 会拿 `docs/privacy-facts.json` 的
  /// `analyticsOptIn.defaultOn` 跟这一行的默认值对账 —— 改这里就要同时改那里和政策正文。
  BoolColumn get analyticsEnabled => boolean().withDefault(const Constant(true))();

  /// **首次启动征求隐私政策同意的时刻**。null = 还没同意过（要弹窗）。
  ///
  /// 为什么必须落库：国内商店要求"首次运行时通过弹窗等明显方式提示用户阅读隐私政策
  /// 并征得同意"（小米的隐私合规指引，规则来源国信办秘字〔2019〕191 号）。
  /// 记不住的话每次冷启动都弹 —— 那比不弹更糟。
  ///
  /// 为什么不复用 `analytics_enabled`：那是**使用统计**的开关（可以随时关掉、
  /// 关掉后功能完全不受影响），而这一条是**法律意义上的同意**，两件事不能混。
  IntColumn get privacyConsentAtMs => integer().nullable()();

  /// **用户明确拒绝过**的时刻。null = 没拒绝过（也没同意过）。
  ///
  /// 为什么单独记一列：拒绝之后不能让每次冷启动都再弹一遍（那是骚扰），
  /// 但也不能把"拒绝"写成"同意"（那是撒谎）。两列各自为真，门只看这两个都是 null。
  IntColumn get privacyDeclinedAtMs => integer().nullable()();

  /// **身体数据（体重）的单独同意时刻**。null = 还没单独同意过。
  ///
  /// 为什么需要它（2026-09-30，`docs/tech-decisions.md` 的合规第 2 条自己写着这件事）：
  /// **体重属于敏感个人信息**（医疗健康类），而 PIPL 第 29 条要求处理敏感个人信息
  /// 取得**单独同意** —— 首次启动那道政策总同意**不算**单独同意。
  /// 所以在用户第一次进「身体数据」时，单独问一次、单独落库。
  /// 政策里对应的说法由 `docs/privacy-facts.json` 的 `sensitiveLocal` 与硬门禁对账。
  IntColumn get bodyMetricConsentAtMs => integer().nullable()();

  /// **从系统健康库（HealthKit / Health Connect）读取体成分的单独同意时刻**。
  /// null = 还没单独同意过 —— 也就是**一次都没读过**。
  ///
  /// 为什么不复用上面那一列（2026-10-09）：两者同意的是**两件不同的事**。
  /// 前者的范围是"我们把你的身体数据**记在本机**（并按你自己的选择随加密备份离开设备）"；
  /// 后者是"我们**去读系统健康库里别人写进去的记录**"（可能是体脂秤 App 写的，
  /// 也可能是医院那份）。PIPL 第 29 条要求对**处理目的、方式、种类**逐项单独同意 ——
  /// 拿一个勾盖住两件事，撤回时就会连带撤回另一件，两道门都成了空话。
  /// 所以各自一列、各自一道门、各自一条撤回路径。
  /// 政策里对应的说法由 `docs/privacy-facts.json` 的 `healthSync` 与硬门禁对账。
  IntColumn get healthConsentAtMs => integer().nullable()();

  /// **用户自己设的"默认加重步进"**（kg；null = 没设过 → 各动作用自己的）。
  ///
  /// 为什么要有它（2026-10-09，用户 10.9 清单第 8a 条「加重量的选项能否自定义」）：
  /// 步进本来只来自动作自己的 `weight_increment`（哑铃 2、器械 5、杠铃 2.5…），
  /// 而**有些健身房的片子只有 5 kg 一档** —— 那种地方每个动作都要手改一次步进是不现实的。
  /// 所以：设一次全局默认 → 用它铺到所有动作上；单个动作仍可在训练屏里单独改（那个更优先）。
  RealColumn get defaultWeightIncrement => real().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId};
}

/// 埋点 outbox。字段照 `docs/analytics-sdk.md` §4 的 DDL。
///
/// 与训练数据分开：埋点丢了不影响用户，训练数据丢一条都不行。
/// 所以两者是两条独立的通道、两套重试策略。
class AnalyticsOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get payload => text()();
  IntColumn get priority => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 身体数据（S12）。字段照 `docs/data-model.md` 的 `body_metric` DDL。
///
/// **一天一条**：用 `date`（YYYY-MM-DD 字符串）做业务上的唯一键。
/// 刻意**不加数据库唯一索引** —— 软删除之后用户还要能重新录入同一天，
/// 唯一索引会让那次插入直接炸。唯一性在仓库层判断。
/// 未结束的训练会话（只会有**一行**，见 `kActiveSessionId`）。
///
/// 为什么单独一张表而不是塞进 `user_profile`：这是一份**运行时状态**，
/// 不是用户偏好 —— 它每次记一组都会重写，混进偏好表会让"改设置"和"记一组"
/// 互相覆盖（`user_profile` 的每个 setter 都要把整行带回去）。
class ActiveSessionRow extends Table {
  /// 固定 id（`kActiveSessionId`）：本机同时只会有一个未结束的训练
  TextColumn get id => text()();
  TextColumn get workoutId => text()();
  /// 会话里有哪些动作、什么处方（JSON，见 domain/models.dart 的 ActiveSession）
  TextColumn get payload => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// **动作置顶**（收藏）。2026-10-04，v16。
///
/// 为什么**单独一张表**、而不是 `user_profile` 的一列：它是一份**有顺序的集合**
/// （用户钉住 3–5 个动作，顺序就是他心里的顺序），而 `user_profile` 全是标量偏好。
/// `docs/data-model.md` 给 `active_session_row` 写过同样的理由（那张表是因为"运行时状态"）。
///
/// 为什么顺序显式存 `position` 而不按插入时间排：这个顺序**用户看得见**
/// （选择器的「置顶」分区），不该由两次点击相差几毫秒来决定。
class PinnedExercise extends Table {
  TextColumn get exerciseId => text()();
  IntColumn get position => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{exerciseId};
}

/// **站内消息**（通知中心）。2026-10-05，v19。
///
/// 三类消息**全部本地生成**（`kind` 就是这三类，见 `docs/screens.md` S18）：
///   * `achievement` —— 徽章解锁（现算出来的徽章与已发过的消息对账，见下面 `ref_key`）；
///   * `reminder` —— 训练提醒到点而你还没练（进 App 时补记一条，说明"当时提醒过你"）；
///   * `backup` —— 云备份结果（成功/失败各一条）。
///
/// **为什么要有 `ref_key`**：同一件事只能发一次（同一个徽章不能每练一次就报一次）。
/// 去重靠**数据库层的唯一索引**（见 `onCreate`/迁移里那条 partial index），
/// 而不是靠调用方记得先查一次 —— 那种"记得"迟早会漏。
///
/// ⚠️ 它**是用户数据**：`deleteAllUserData` 必须把它一起清掉
/// （`test/delete_all_test.dart` 的表清单守门会盯着这一条）。
class AppNotification extends Table {
  TextColumn get id => text()();

  /// achievement | reminder | backup
  TextColumn get kind => text()();

  TextColumn get title => text()();
  TextColumn get body => text()();
  IntColumn get createdAtMs => integer()();

  /// 读过的时刻。null = 未读（通知中心那几个未读点靠它）。
  IntColumn get readAtMs => integer().nullable()();

  /// **去重键**：同一 `kind` + 同一个 `refKey` 只会有一条。可空 = 不参与去重。
  TextColumn get refKey => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// **训练提醒的设置**（单行）。2026-10-04，v17。
///
/// 为什么自己一张单行表、而不是塞进 `user_profile`：那张表的**每个 setter 都要把整行带回来**
/// （drift 的 `insertOnConflictUpdate` 写整行，漏一列就抹成默认值 —— 这个坑项目里踩过三次，
/// 注释写在 `profile_repository.dart` 里）。提醒是独立的一件事，单独一张表就不会被
/// "改显示单位"这种操作顺手抹掉。
class ReminderSetting extends Table {
  /// 固定 id（`kReminderId`）：本机只有一份提醒设置
  TextColumn get id => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();

  /// 一天中的第几分钟（0–1439）。默认 20:00 = 1200。
  IntColumn get minutesOfDay => integer().withDefault(const Constant(1200))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class BodyMetric extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get date => text()();

  /// 体重。允许单独记体脂而不记体重，所以这一列可空。
  RealColumn get weightKg => real().nullable()();
  RealColumn get bodyFatPct => real().nullable()();

  /// 腰围（cm）。2026-10-05，v20。
  ///
  /// 与体重一样属**敏感个人信息**（身体数据），所以它和体重共享那一道**单独同意**门
  /// （`body_metric_screen.dart` 的 `_ensureSensitiveConsent`）——
  /// 不是"新开一扇门"，而是同一扇门后面的新字段。
  RealColumn get waistCm => real().nullable()();

  /// 骨骼肌量（kg）。2026-10-05，v20。同样在敏感信息那道门后面。
  RealColumn get muscleMassKg => real().nullable()();

  TextColumn get note => text().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 计划模板（S11）。字段照 `docs/data-model.md` 的 `routine` DDL。
///
/// `source` 区分内置 / 用户自建 / 建议生成 —— 现在只写 `user`，
/// 另两种留给后续（内置模板与"把建议存成计划"）。
class Routine extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get note => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('user'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 计划里的一项。**简化版只有动作 + 组数 + 次数区间**（规格 S11 明确说的）。
///
/// `targetWeightKg` 与 `restSec` 照 DDL 建好但**这一版不暴露编辑入口** ——
/// 前者交给规则引擎建议（NULL 就是这个意思），后者沿用动作自带的休息时长。
class RoutineItem extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get targetRepsLow => integer().withDefault(const Constant(8))();
  IntColumn get targetRepsHigh => integer().withDefault(const Constant(10))();
  RealColumn get targetWeightKg => real().nullable()();
  IntColumn get restSec => integer().withDefault(const Constant(90))();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 云备份账号（**最多一行**）。
///
/// 恢复码就是账号密钥，所以这张表存的是**打开云端备份的唯一凭据**。
/// 三条设计决定：
///
///   * **和 `user_profile` 一样按 `user_id` 做主键**（现在恒为 `local`）——
///     多用户是以后的事，但先把位置留出来，免得将来再加一次表重建。
///   * **存规范形态（27 位、无连字符）**，不存给人看的那版分组写法。
///     展示时再分组 —— 两处都存就会出现"哪份是真的"这种问题。
///   * **它会被「删除全部数据」一起清掉**（见 `drift_local_store.deleteAllUserData`）。
///     ⚠️ 但那只清了本机 —— **云上那份要另外删**，否则恢复码一丢，用户的数据
///     就永远留在一台他控制不了的服务器上了。
class BackupAccount extends Table {
  TextColumn get userId => text()();
  TextColumn get recoveryCode => text()();

  /// 开启云备份的时间
  IntColumn get enabledAtMs => integer()();

  /// 最后一次成功上传的时间与密文字节数（界面上显示"上次备份于…"）
  IntColumn get lastUploadAtMs => integer().nullable()();
  IntColumn get lastUploadBytes => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId};
}

/// **登录会话**（2026-10-06，账号体系 P1-3）。
///
/// 一行（`user_id` 恒为 `local`）：这个设备上**已经登录**的那个账号。
///
/// 存了什么、为什么这些能存：
///
///   * `token` —— 会话凭据（服务端只说"这是谁"，读不到训练明细）；
///   * `email` —— 用户自己填的，界面要显示"当前登录：a@b.com"；
///   * `account_id` —— 账号密钥的哈希，云备份那条链一直在用的身份；
///   * `account_key` —— **账号密钥本体**（16 字节）。它听起来敏感，但今天的
///     `backup_account.recovery_code` 就是同一把密钥、一直是明文存的 ——
///     这一张表没有让本机存储变得更差，只是换了个位置（真要与"设备被拿走"对抗，
///     得上 Keychain/Keystore，那是另一件事，见 `docs/plan-account-login.md` §六）。
///   * `salt_hex` / `kdf` —— 改口令时要拿旧盐算"当前口令的凭据"。
///
/// ⚠️ **它会被「删除全部数据」一起清掉**（见 `drift_local_store.deleteAllUserData`）——
/// 注销/清除之后本机不该留着任何能代表"这个人是谁"的东西。
class AuthSession extends Table {
  TextColumn get userId => text()();
  TextColumn get token => text()();
  TextColumn get email => text()();
  TextColumn get accountId => text()();

  /// 账号密钥（16 字节）
  BlobColumn get accountKey => blob()();

  TextColumn get saltHex => text()();
  TextColumn get kdf => text()();
  IntColumn get loginAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{userId};
}

/// **连续打卡保护（补签）**（2026-10-06，第二部分第 2 条）。
///
/// 一天一行：**这一天被补签保护了**。这是这个仓库里极少数的"用户写下来的**关于历史**的
/// 一条声明"（其余的一切都是训练记录的推导结果）—— 所以它必须**单独存在一张表里**，
/// 而不是去改 `set_record`/`workout`：**记录就是事实**，补签不是"那天我练了"，
/// 而是"我知道那天断了，我选择不让这条链断在这里"。
///
/// ⚠️ 它**是用户数据**：`deleteAllUserData` 必须把它一起清掉，
/// 而且 `test/delete_all_test.dart` 那份表清单守门也要加上它（新加表最容易漏这一步）。
///
/// 为什么不用一列"已用次数"：`date` 既是主键又是"哪一天"，一次补签一周的额度
/// 可以直接由 `date` 反推（周一那天所在的周）—— 存计数就会和这张表本身不一致。
class StreakProtection extends Table {
  /// 被保护的那一天（**本地日**，`YYYY-MM-DD`，与 `body_metric.date` 同一种写法）。
  /// 用字符串而不是时间戳：这一列要能被人肉读出来（排障时一眼看到"补的是哪一天"）。
  TextColumn get date => text()();

  /// 补签这个动作发生的时刻（毫秒）。**不是**被补的那一天 —— 这两个时间
  /// 在界面上是两件事（"10/6 补了 10/5"）。
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{date};
}

@DriftDatabase(tables: <Type>[
  Exercise,
  Workout,
  WorkoutItem,
  SetRecord,
  UserProfile,
  AnalyticsOutbox,
  AnalyticsMeta,
  BodyMetric,
  Routine,
  RoutineItem,
  BackupAccount,
  ActiveSessionRow,
  PinnedExercise,
  ReminderSetting,
  AppNotification,
  StreakProtection,
  AuthSession,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// v2：新增 `body_metric`（S12 身体数据）。
  /// v3：新增 `routine` / `routine_item`（S11 计划模板）。
  /// v4：`exercise` 新增 `category`（热身/拉伸进库，但不进推荐）—— **第一次给已有表加列**。
  /// v5：`set_record` 新增 `distance_m`（有氧记录：跑步机/划船机/跳绳/农夫行走）。
  /// v6：`user_profile` 新增 `body_weight_unit`（体重的显示单位：千克 / 斤）。
  /// v19（2026-10-05）：新增 `app_notification`（站内消息 / 通知中心）。
  /// v7：新增 `analytics_meta`（设备 ID / 会话 ID / 首次启动时间 —— 埋点公共字段）。
  /// v8：`exercise` 新增 `default_target_distance_m`（距离处方：每组多少米）。
  /// v9：`exercise` 新增 `instructions`（动作说明：怎么做 + 最常见的错）。
  /// v10：新增 `backup_account`（云备份账号：恢复码 + 上次备份时间）。
  /// v11：`user_profile` 新增 `privacy_consent_at_ms`（首次启动的隐私政策同意时刻）。
  /// v12：`user_profile` 新增 `privacy_declined_at_ms`（**拒绝过**的时刻）。
  /// v16：新增 `pinned_exercise`（动作置顶 —— 选择器的「置顶」分区）。
  /// v17：新增 `reminder_setting`（训练提醒：开关 + 一天中的第几分钟）。
  ///
  /// **老版本的库已经装在用户手机上**，所以每次加表/加列都必须有 onUpgrade ——
  /// 只改表定义不改 onUpgrade 的话，老用户的 App 一开就崩。
  ///
  /// v19（2026-10-05）：+ `app_notification`（站内消息 / 通知中心）。**只加表、不动任何既有列**。
  /// v20（2026-10-05）：`body_metric` +`waist_cm`/`muscle_mass_kg`、`user_profile` +`height_cm`
  ///（身体数据扩展：腰围 / 肌肉量 / BMI）。**这一版动既有表**，所以两块都要
  /// 「先看库里真实的形状再决定加不加」——见迁移链尾那段的说明。
  /// v21（2026-10-06）：新增 `streak_protection`（连续打卡保护 / 补签）。**只加表**。
  /// v22（2026-10-06）：新增 `auth_session`（登录会话，账号体系 P1-3）。**只加表**。
  /// v24（2026-10-07）：`user_profile` +`nickname`（昵称，10.7 清单第 7 条）。
  /// **加列**，老库升上来是 null = 没设过（界面如实写"还没设昵称"）。
  /// v23（2026-10-07）：**只改一处列默认值** —— `user_profile.analytics_enabled`
  /// 的默认 0 → 1（「帮助改进产品」默认开，用户拍板）。
  /// ⚠️ **这一版不搬任何数据、也不重建任何表**：那个默认值只对"还没有那一行"的机器
  /// （= 新装）生效；**存量机器那一位原样不动**（迁移链尾那段写明了为什么）。
  /// v25（2026-10-09）：`user_profile` +`health_consent_at_ms`（**从系统健康库读取体成分**
  /// 的单独同意时刻）。**加列**，老库升上来是 null = 从没同意过 = 一次都没读过 ——
  /// 那正是准确的历史：这个功能出现之前，这台设备没读过任何健康库里的东西。
  /// v26（2026-10-09）：`user_profile` +`default_weight_increment`（用户自己设的默认加重步进）。
  /// **加列**，老库升上来是 null = 没设过 → 各动作仍用自己的步长（现状不变）。
  @override
  int get schemaVersion => 26;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // 索引直接照 docs/data-model.md 建，保证与文档一致。
          // drift 没有在表定义里声明索引的稳定 API，用 customStatement 更可控。
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_set_exercise '
            'ON set_record (exercise_id, completed_at DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_set_workout_item '
            'ON set_record (workout_item_id, set_index)',
          );
          // 消息去重：**数据库层**保证"同一件事只发一次"（partial unique index）。
          // 不靠调用方"记得先查一次"—— 那种记得迟早会漏，而漏了的后果是
          // 同一个徽章每练一次就报一次，用户会以为这 App 在刷屏。
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_ref '
            "ON app_notification (kind, ref_key) WHERE ref_key IS NOT NULL",
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_workout_user_time '
            'ON workout (user_id, started_at DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_body_metric_date '
            'ON body_metric (date DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_routine_item_routine '
            'ON routine_item (routine_id, position)',
          );
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // v16 → v17：多一张"训练提醒"表。老库升上来时它是空的 ——
          // **准确的历史**：这个功能出现之前，谁也没开过提醒（也就是默认关）。
          if (from < 17) {
            await m.createTable(reminderSetting);
          }
          // v15 → v16：多一张"动作置顶"表。老库升上来时它是空的 ——
          // **准确的历史**：这个功能出现之前，用户一个动作都没置顶过。
          if (from < 16) {
            await m.createTable(pinnedExercise);
          }
          // v14 → v15：多一张"未结束的训练会话"表（训练中断后能回来接着练）。
          // 只加表、不动任何既有列 —— 老库里的数据一行都不用搬。
          if (from < 15) {
            await m.createTable(activeSessionRow);
          }
          // v1 → v2：只多了一张表，没有改动任何既有列，所以不需要数据搬迁。
          if (from < 2) {
            await m.createTable(bodyMetric);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_body_metric_date '
              'ON body_metric (date DESC)',
            );
          }
          // v2 → v3：只多两张表，没有改动任何既有列
          if (from < 3) {
            await m.createTable(routine);
            await m.createTable(routineItem);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_routine_item_routine '
              'ON routine_item (routine_id, position)',
            );
          }
          // v3 → v4：**加列**，不是加表。加列时是 NOT NULL + DEFAULT 'strength'，
          // 所以老库里的 318 个动作全部落成 strength —— 这正是我们要的：
          // 它们本来就都是力量动作。**不需要数据搬迁**（也不需要清表重建）。
          if (from < 4) {
            await m.addColumn(exercise, exercise.category);
          }
          // v4 → v5：又是一次加列，这次是 `set_record`。老库里的组记录全是力量组，
          // 距离一律 null —— 这正是"没记过距离"的诚实表示（不是 0，0 公里是一次真的没动）。
          // ⚠️ 训练数据是资产：加列不能碰任何既有行，也不该重建表。
          if (from < 5) {
            await m.addColumn(setRecord, setRecord.distanceM);
          }
          // v5 → v6：给 `user_profile` 加一列。老库里的档案只有一行（本机用户），
          // 缺省 'kg' 就是正确答案 —— 在"体重单位"这个概念出现之前，
          // 体重显示的确实是 kg（`unit_pref`）。**不需要数据搬迁。**
          if (from < 6) {
            await m.addColumn(userProfile, userProfile.bodyWeightUnit);
          }
          // v6 → v7：加一张新表（只放埋点的记账），没有改动任何既有列。
          // 老库升上来时这张表是空的，首次启动会生成设备 ID 并把首启时间记下 ——
          // 那正是我们要的：升级用户的"首次 app_open"从这一版算起。
          if (from < 7) {
            await m.createTable(analyticsMeta);
          }
          // v7 → v8：给 `exercise` 再加一列（距离处方）。老库里它恒为 null ——
          // 老库本来就没有距离动作（v1.4.0 才补进来），null 是准确的历史。
          if (from < 8) {
            await m.addColumn(exercise, exercise.defaultTargetDistanceM);
          }
          // v8 → v9：动作说明。老库里恒为 null（那时 App 里根本没有这个字段）——
          // 覆盖率工具会把"还没写的"如实算进去，不假装有。
          if (from < 9) {
            await m.addColumn(exercise, exercise.instructions);
          }
          // v9 → v10：加一张新表（只放云备份账号）。老库升上来时这张表是空的 ——
          // 那正是我们要的：**云备份默认关闭**，没有那行就代表"这台机器还没开过"。
          if (from < 10) {
            await m.createTable(backupAccount);
          }
          // v10 → v11：给 `user_profile` 加一列（隐私政策同意时刻）。老库升上来时它是
          // **null = 还没同意过** —— 于是老用户也会看到一次同意弹窗。
          // 这是有意的：他们当年装的那个版本里，应用内根本没有隐私政策可读。
          if (from < 11) {
            await m.addColumn(userProfile, userProfile.privacyConsentAtMs);
          }
          // v11 → v12：再加一列（拒绝时刻）。老库升上来两列都是 null → 会问一次；
          // 用户在这一次里选"不同意"就能进 App 用离线功能，而我们记得他拒绝过。
          if (from < 12) {
            await m.addColumn(userProfile, userProfile.privacyDeclinedAtMs);
          }
          // v12 → v13：**统计开关的默认值从"开"改成"关"**。
          // 列默认值只影响以后新插入的行，老库里那几个 `true` 必须显式翻过来 ——
          // 否则"默认同意"这个毛病会跟着老用户一直活下去。
          // （写这一刀时还没有真实用户，所以它没有覆盖掉任何人的选择。）
          if (from < 13) {
            await customStatement('UPDATE user_profile SET analytics_enabled = 0');
          }
          // v13 → v14：身体数据（体重）的**单独同意**时刻。老库升上来是 null ——
          // 也就是老用户下次进「身体数据」时会看到那道单独同意说明（这是对的：
          // 他们当初同意的是政策，不是"处理敏感个人信息"这件事本身）。
          if (from < 14) {
            await m.addColumn(userProfile, userProfile.bodyMetricConsentAtMs);
          }

          // v17 → v18：埋点那一行多一位"已清过历史积压"（`docs/analytics.md` §10 的 B 方案）。
          // 只加列、不动任何既有数据 —— 老库升上来时它是 null，意思正是"还没清过"。
          //
          // ⚠️ 这一块被迁移测试**连抓两轮**，两条教训都写在这儿（都不显然）：
          //   ① **顺序**：它 `ALTER TABLE analytics_meta`，而那张表是 `from < 7` 才建的。
          //      前几版习惯了"新迁移往链首塞"——v15/16/17 都是 `createTable`，与顺序无关，
          //      所以一直没出事；一旦某个迁移**动既有表**，老库（比如 v1）升上来时表还不存在，
          //      直接 `no such table`。所以它必须排在**链尾**。
          //   ② **判据不是版本号，是"这一列现在有没有"**：
          //      * `m.createTable` 用的是**当前**表定义 —— 老库从 v1 升上来时，
          //        这张表在 `from < 7` 那块就**带着新列**建出来了，再 `addColumn` 就
          //        `duplicate column name`；
          //      * 反过来，迁移测试里 v7+ 的 fixture **没有**这张表（那份 fixture 只写"旧形状"，
          //        是个近似），无条件 `addColumn` 又变成 `no such table`。
          // 一句话留给下一个人：**给既有表加列，先看库里真实的形状。**
          if (from < 18) {
            final List<QueryRow> tables = await customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='analytics_meta'",
            ).get();
            if (tables.isNotEmpty) {
              final List<QueryRow> cols =
                  await customSelect("PRAGMA table_info('analytics_meta')").get();
              final bool hasCol =
                  cols.any((QueryRow r) => r.read<String>('name') == 'legacy_purged_at');
              if (!hasCol) {
                await m.addColumn(analyticsMeta, analyticsMeta.legacyPurgedAt);
              }
            }
          }

          // v18 → v19：站内消息（通知中心）。只加表、不动既有列，所以老库升上来是空的 ——
          // **准确的历史**：这个功能出现之前没有任何消息。
          // ⚠️ 那条 partial unique index 也要在这里建：`onCreate` 只在**新库**上跑，
          // 老库升级走的是这条路径（漏了它，去重在老库上就形同虚设）。
          if (from < 19) {
            await m.createTable(appNotification);
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_ref '
              "ON app_notification (kind, ref_key) WHERE ref_key IS NOT NULL",
            );
          }

          // v19 → v20：身体数据扩展。
          // ⚠️ 这是**第二次动既有表**（第一次是 v18），所以照 v18 那两条教训来：
          //   ① 排在**链尾**（前面可能有 createTable 把这张表建出来）；
          //   ② 判据不是版本号，是**"这一列现在有没有"** —— 新库走 `onCreate` 时
          //      这两张表已经带着新列建好了，再 addColumn 会 `duplicate column name`。
          // 用一个小工具把这三列统一处理，免得三处各写一遍判断。
          // ⚠️ 形参要写成**泛型**（`GeneratedColumn<T>`）：写死 `GeneratedColumn<Object>`
          // 时 `Column<String>` / `RealColumn` 传不进来 —— 而 `dart analyze` **会放过**
          // （它做了隐式下调），只有真正编译（`flutter build`）时才报
          // "The argument type 'Column<String>' can't be assigned to ..."。
          // 2026-10-08 出 v1.61.0 的包时当场撞上：门禁全绿、analyze 干净，出包失败。
          Future<void> addIfMissing<T extends Object>(
              TableInfo table, GeneratedColumn<T> col) async {
            final String name = table.actualTableName;
            final List<QueryRow> exists = await customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='$name'",
            ).get();
            if (exists.isEmpty) return; // 这张表还没有（更老的库）—— 由它自己那条迁移负责
            final List<QueryRow> cols = await customSelect("PRAGMA table_info('$name')").get();
            if (cols.any((QueryRow r) => r.read<String>('name') == col.name)) return;
            await m.addColumn(table, col);
          }

          if (from < 20) {
            await addIfMissing(bodyMetric, bodyMetric.waistCm);
            await addIfMissing(bodyMetric, bodyMetric.muscleMassKg);
            await addIfMissing(userProfile, userProfile.heightCm);
          }

          // v20 → v21：连续打卡保护（补签）。**只加表、不动任何既有列**，
          // 所以老库升上来时它是空的 —— 那正是准确的历史：这个功能出现之前，
          // 谁也没有补签过（也就是说，他们的连续天数从来没有被补签撑过）。
          if (from < 21) {
            await m.createTable(streakProtection);
          }

          // v21 → v22：登录会话表。**只加表**，同样排在这条链的**链尾**
          // （"新加的 createTable 要排在链尾"是纪律，见上面 <18/<20 那两块的教训）。
          // 老库升上来时它是空的 —— 准确的历史：升级之前，这台设备没有登录过任何账号。
          if (from < 22) {
            await m.createTable(authSession);
          }

          // v22 → v23：「帮助改进产品」的列默认值 0 → 1（2026-10-07 用户拍板）。
          //
          // ⚠️ **这一格是"故意什么都不做"，不是漏写。** 理由要说清楚：
          //   * 那个默认值只在**建表 / 缺省插入**时起作用，而 drift 的 Dart 数据类
          //     把这一列当必填，每次写都显式传值 —— 所以**老库根本用不到这个默认值**；
          //   * 更重要的：**我们不静默翻转存量用户的选择**。他们当年在首启同意屏与
          //     政策里看到的是"默认关闭"，把 `analytics_enabled` 从 0 改成 1 等于
          //     对着一份旧承诺收集数据 —— 那是这一版最不该做的事（见
          //     `docs/plan-ux-2026-10-07.md` §三·9）。
          //   * 于是：新装 = 没有那一行 → 读到默认值 1；存量 = 有那一行 → 读它自己的值。
          //     这条语义由 `app/test/migration_test.dart` 里"v22 库升到 v23"那条钉住。
          if (from < 23) {
            // 有意留空：只改列默认值，不搬数据、不重建表。
          }

          // v23 → v24：`user_profile` 加一列「昵称」。**只加列**，老库升上来是 null
          // （= 没设过，界面如实写"还没设昵称"，不编一个默认名）。
          // ⚠️ 与 v20 那几列同一个纪律：`onCreate` 建的新库已经带着这一列，
          // 所以迁移里要**先看库里有没有它**再决定加不加（无条件 addColumn 会
          // `duplicate column name`）。
          if (from < 24) {
            await addIfMissing(userProfile, userProfile.nickname);
          }

          // v24 → v25：`user_profile` 加一列「从系统健康库读取体成分的单独同意时刻」。
          // **只加列**，老库升上来是 null = 从没同意过 = 一次都没读过。
          // ⚠️ 与 v20 / v24 同一个纪律：新库由 `onCreate` 建表时已经带着这一列，
          // 所以迁移里要先看库里有没有它（无条件 addColumn 会 `duplicate column name`）。
          if (from < 25) {
            await addIfMissing(userProfile, userProfile.healthConsentAtMs);
          }

          // v25 → v26：`user_profile` 加一列「用户自己设的默认加重步进」。
          // **只加列**，老库升上来是 null = 没设过 —— 那正是准确的历史：
          // 在这之前，步进只可能来自动作自己（种子里的 2 / 2.5 / 5）。
          if (from < 26) {
            await addIfMissing(userProfile, userProfile.defaultWeightIncrement);
          }
        },
      );
}

/// App 用的工厂。测试请自行传 `NativeDatabase.memory()`，不要走这里。
AppDatabase openAppDatabase() => AppDatabase(driftDatabase(name: 'lianleme'));
