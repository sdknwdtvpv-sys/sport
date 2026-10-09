/// 练了么 · LocalStore 的 drift 实现
///
/// 与 `InMemoryLocalStore` 实现同一个接口，行为必须完全一致 ——
/// 由 `test/local_store_contract_test.dart` 用**同一组断言**同时验证两者。
///
/// 注意 import 前缀：drift 生成的表类叫 `Workout` / `SetRecord`，
/// 领域模型里也有同名类（`domain.Workout` / `domain.SetRecord`），
/// 所以领域模型一律加 `domain.` 前缀，避免歧义。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/models.dart' as domain;
import 'db.dart';
import 'local_store.dart';

class DriftLocalStore implements LocalStore {
  DriftLocalStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> saveSet(domain.SetRecord r) async {
    // workout_item 是"某次训练里的某个动作"，由组记录派生。
    // 用确定性 id，保证同一 (workout, exercise) 反复写入不会产生重复行。
    final itemId = 'wi_${r.workoutId}_${r.exerciseId}';
    await _db.into(_db.workoutItem).insertOnConflictUpdate(
          WorkoutItemData(
            id: itemId,
            workoutId: r.workoutId,
            exerciseId: r.exerciseId,
            position: 0,
            updatedAt: r.completedAtMs,
          ),
        );

    await _db.into(_db.setRecord).insertOnConflictUpdate(
          SetRecordData(
            id: r.id,
            workoutId: r.workoutId,
            workoutItemId: itemId,
            exerciseId: r.exerciseId,
            setIndex: r.setIndex,
            setType: r.setType.wire,
            weightKg: r.weightKg,
            reps: r.reps,
            // 距离：只有 distance_time 的动作有值，其余是 null
            distanceM: r.distanceM,
            // 可选的 RPE。DB 列早就有，以前一直没写值 —— 现在接上。
            rpe: r.rpe,
            // 注意：withDefault() 只给 SQL 层加 DEFAULT，Dart 数据类里这些字段仍是 required，
            // 必须显式传。setType 同理（上面已传）。
            isPr: false,
            // volume 物化：weight × reps（自重动作 weight 为 null，容量记 0）。
            // **距离动作的容量记 0**：它的"次数"其实是秒（1800），
            // 拿 20kg × 1800 当容量是把两个量纲乘在一起。距离动作要看的是
            // 里程与配速，不是容量。
            volume: r.hasDistance ? 0 : (r.weightKg ?? 0) * r.reps,
            completedAt: r.completedAtMs,
            updatedAt: r.completedAtMs,
          ),
        );
  }

  @override
  Future<void> deleteSet(String id) async {
    // 软删除：训练数据不物理删除，留痕可回溯
    await (_db.update(_db.setRecord)..where((t) => t.id.equals(id)))
        .write(SetRecordCompanion(
      deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  @override
  Future<List<domain.SetRecord>> setsFor(String workoutId) async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) => t.workoutId.equals(workoutId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<void> saveWorkout(domain.Workout w) async {
    // 领域模型 `Workout` 目前只有 id / startedAtMs / sets，没有 status。
    // 先把容量与组数物化进去，status 固定 in_progress；
    // 等 S7「训练结束总结」落地时领域模型会补上 status 与 endedAt。
    // ⚠️ **必须用 Companion + `Value(...)`，不能用 DataClass**（2026-10-04 踩到）：
    // drift 对 DataClass 是 **nullToAbsent** —— 传 `note: null` 是"这一列不改"，
    // 于是"把笔记清空"这个动作**静默失效**（写进去能读出来，清掉却还是旧值）。
    // 这条教训 `ROADMAP.md` 的清单里本来就有（`SetRecordData.isPr` /
    // `UserProfileData.unitPref` 各踩过一次），这次是第三次 —— 所以这里的坑要写全。
    await _db.into(_db.workout).insertOnConflictUpdate(
          WorkoutCompanion(
            id: Value<String>(w.id),
            // 结束时间与状态都要回写，否则 S7 之后再来一组就会把结束时间抹掉
            status: Value<String>(w.isFinished ? 'finished' : 'in_progress'),
            startedAt: Value<int>(w.startedAtMs),
            endedAt: Value<int?>(w.endedAtMs),
            totalVolume: Value<double>(w.totalVolume),
            totalSets: Value<int>(w.totalSets),
            // note 要用 Value 包起来：`Value<String?>(null)` = **显式清空**（这才是"清笔记"）
            note: Value<String?>(w.note),
            createdAt: Value<int>(w.startedAtMs),
            updatedAt: Value<int>(w.endedAtMs ?? w.startedAtMs),
          ),
        );
  }

  @override
  Future<domain.Workout?> loadWorkout(String id) async {
    final row = await (_db.select(_db.workout)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    final sets = await setsFor(id);
    return domain.Workout(
      id: row.id,
      startedAtMs: row.startedAt,
      endedAtMs: row.endedAt,
      note: row.note,
    )..sets.addAll(sets);
  }

  // ── 未结束的训练会话（2026-10-01）────────────────────────────────────
  //
  // 只存一行。payload 是 JSON：会话里有哪些动作、处方、当前第几个、
  // 以及休息到什么时候（绝对时间戳）。放在这里而不是 `user_profile`：
  // 它是运行时状态、写得频繁，混进偏好表会和"改设置"互相覆盖。
  @override
  Future<void> saveActiveSession(domain.ActiveSession session) async {
    await _db.into(_db.activeSessionRow).insertOnConflictUpdate(
          ActiveSessionRowData(
            id: kActiveSessionId,
            workoutId: session.workoutId,
            payload: jsonEncode(session.toJson()),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Future<domain.ActiveSession?> activeSession() async {
    final ActiveSessionRowData? row = await (_db.select(_db.activeSessionRow)
          ..where((t) => t.id.equals(kActiveSessionId)))
        .getSingleOrNull();
    if (row == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(row.payload);
    } catch (_) {
      // 读不出来就当没有 —— 一份坏掉的运行时状态不该让 App 起不来
      return null;
    }
    return domain.ActiveSession.fromJson(decoded);
  }

  @override
  Future<void> clearActiveSession() async {
    await (_db.delete(_db.activeSessionRow)
          ..where((t) => t.id.equals(kActiveSessionId)))
        .go();
  }

  @override
  Future<List<domain.SetRecord>> allSets() async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) => t.setType.equals('normal') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<domain.SetRecord>> setsForExercise(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) =>
              t.exerciseId.equals(exerciseId) &
              t.setType.equals('normal') &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    // 排除本次训练放在 Dart 里做：SQL 层的"取反"要用到 .not() / Constant(true)，
    // 而我无法在本机编译验证这些 API。筛选逻辑本身极便宜（单个动作的历史不过几十条），
    // 用确定能跑的形式换掉一次可能的编译失败是划算的。
    final filtered = excludeWorkoutId == null
        ? rows
        : rows.where((SetRecordData r) => r.workoutId != excludeWorkoutId).toList();
    return filtered.map(_toDomain).toList();
  }

  @override
  Future<List<String>> recentExerciseIds() async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) => t.setType.equals('normal') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    if (rows.isEmpty) return const <String>[];

    final latestWorkoutId = rows.last.workoutId;
    final ids = <String>[];
    for (final SetRecordData r in rows) {
      if (r.workoutId == latestWorkoutId && !ids.contains(r.exerciseId)) {
        ids.add(r.exerciseId);
      }
    }
    return ids;
  }

  @override
  Future<List<String>> pinnedExerciseIds() async {
    // 按 position 取（不是按插入时间）—— 这个顺序是**用户看得见的顺序**
    final rows = await (_db.select(_db.pinnedExercise)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return rows.map((PinnedExerciseData r) => r.exerciseId).toList();
  }

  @override
  Future<void> setPinnedExerciseIds(List<String> ids) async {
    // 整体替换放进一个事务：中途失败不会留下"置顶了一半"的清单
    // （用户看得见的顺序出错，比操作失败更难解释）。
    await _db.transaction(() async {
      await _db.delete(_db.pinnedExercise).go();
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < ids.length; i++) {
        await _db.into(_db.pinnedExercise).insert(
              PinnedExerciseCompanion.insert(
                exerciseId: ids[i],
                position: i,
                createdAt: now,
              ),
            );
      }
    });
  }

  @override
  Future<domain.LastSession?> lastSessionFor(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    // 只取正式组；按完成时间升序，最后一条所在的那次训练就是"上次"。
    // excludeWorkoutId 排除本次训练（同一次里再次进入同一个动作时要用）。
    final rows = await (_db.select(_db.setRecord)
          ..where((t) {
            Expression<bool> cond = t.exerciseId.equals(exerciseId) &
                t.setType.equals('normal') &
                t.deletedAt.isNull();
            if (excludeWorkoutId != null) {
              cond = cond & t.workoutId.equals(excludeWorkoutId).not();
            }
            return cond;
          })
          ..orderBy([(t) => OrderingTerm.asc(t.completedAt)]))
        .get();
    if (rows.isEmpty) return null;

    final latestWorkoutId = rows.last.workoutId;
    final same = rows.where((SetRecordData r) => r.workoutId == latestWorkoutId).toList();
    return domain.LastSession(
      weightKg: same.last.weightKg,
      reps: same.map((SetRecordData r) => r.reps ?? 0).toList(),
      distances: same.map((SetRecordData r) => r.distanceM).toList(),
      // 真实天数。以前这里漏了这个字段 → daysAgo 恒为 0 →
      // 引擎的 21 天回归保护（progression.dart 的 kStaleDays 分支）永远不触发。
      daysAgo: daysSince(same.last.completedAt),
    );
  }

  domain.SetRecord _toDomain(SetRecordData row) => domain.SetRecord(
        id: row.id,
        workoutId: row.workoutId,
        exerciseId: row.exerciseId,
        setIndex: row.setIndex,
        reps: row.reps ?? 0,
        completedAtMs: row.completedAt,
        weightKg: row.weightKg,
        distanceM: row.distanceM,
        setType: row.setType == 'warmup' ? domain.SetType.warmup : domain.SetType.normal,
        rpe: row.rpe,
      );

  /// **回收站**：软删除过的组，最近删的在前。
  ///
  /// 2026-10-04 补的出口 —— 在此之前 `deleteSet` 只写 `deletedAt`，
  /// 而**全仓没有任何地方读它**：长按撤销之后那组就永远取不回来了。
  @override
  Future<List<domain.DeletedSet>> deletedSets({int limit = 200}) async {
    final List<SetRecordData> rows = await (_db.select(_db.setRecord)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy(<OrderingTerm Function($SetRecordTable)>[
            (t) => OrderingTerm.desc(t.deletedAt),
          ])
          ..limit(limit))
        .get();
    return rows
        .map((SetRecordData r) => domain.DeletedSet(
              set: _toDomain(r),
              deletedAtMs: r.deletedAt ?? 0,
            ))
        .toList();
  }

  /// 从回收站恢复一组。
  ///
  /// ⚠️ **必须用 Companion + `Value(null)`**：drift 对 DataClass 是 `nullToAbsent`，
  /// 直接把 `null` 塞进 `write()` 是"这一列不改"，而不是"清空"。
  /// （这个坑本项目踩过两次，`ROADMAP.md` 的教训清单里记着。）
  @override
  Future<void> restoreSet(String id) async {
    await (_db.update(_db.setRecord)..where((t) => t.id.equals(id)))
        .write(SetRecordCompanion(
      deletedAt: const Value<int?>(null),
      updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  @override
  Future<void> deleteAllUserData() async {
    // 整个清空放进一个事务：中途失败就整体回滚，不会留下"训练没了但组还在"的
    // 半残状态 —— 那比不删更糟，用户会以为删干净了。
    //
    // 删除顺序按"子 → 父"（组 → 训练项 → 训练），虽然这些表没有外键级联，
    // 但顺序符合直觉，将来加上外键也不会突然炸。
    await _db.transaction(() async {
      // 未结束的训练会话也是用户状态（它写着"刚才在练第几个动作"）。
      // 用户说"删除全部数据"，这条也必须走 —— 否则下次冷启动还会弹出
      // 「上次的训练还没结束」，而那次训练的数据已经被删光了（自相矛盾的界面）。
      await _db.delete(_db.activeSessionRow).go();
      // 动作置顶也是用户数据（他钉住的那几个动作）。新加表最容易漏掉这一步，
      // 所以 test/delete_all_test.dart 有一份**表清单守门**：出现新表就要去改那里。
      await _db.delete(_db.pinnedExercise).go();
      // 「今天的安排」（v27，10.9 清单第 6 条）也是用户数据 —— 那是他自己拖动、
      // 替换、删过的那一份。留着它，删光之后首页还会摆着"今天练这几个"。
      await _db.delete(_db.dayPlanItem).go();
      await _db.delete(_db.dayPlanDay).go();
      // 训练提醒也是用户设置（他自己选的开关与时间）
      await _db.delete(_db.reminderSetting).go();
      // 站内消息也是用户数据（那是他练出来的通知）。新加表最容易漏这一步 ——
      // `test/delete_all_test.dart` 有一份表清单守门，出现新表就要去改那里。
      await _db.delete(_db.appNotification).go();
      // 补签保护也是用户数据（他自己决定"这一天不能让链断"）。⚠️ 它是这一批里
      // 唯一一张新增的表，所以这份清单里漏了它、用户点了"删除全部数据"之后
      // 连续天数还是被补签撑着的读法就成立了 —— 那既错又难查。
      await _db.delete(_db.streakProtection).go();
      await _db.delete(_db.setRecord).go();
      await _db.delete(_db.workoutItem).go();
      await _db.delete(_db.workout).go();
      // 个人设置一并清掉：用户说"删除全部数据"就包括他的偏好开关。
      // 之后会回落到默认值（渐进建议开、单位默认 kg、"帮助改进产品"**开**）。
      // ⚠️ 最后那一条翻过两次：v1.28.0 从开改成关（审计 A 的后半段），
      // **2026-10-07（v23）用户拍板又改回开** —— 见 `docs/plan-ux-2026-10-07.md` §三·9。
      // 这里曾写着"开"（过期话），后来写着"关"（也过期了）—— 所以现在由
      // `test/delete_all_test.dart` 的断言直接跟着真源钉，不再靠注释记忆。
      await _db.delete(_db.userProfile).go();
      // 还没发出去的埋点事件也必须清 —— 否则"删了数据"之后还会继续上报，
      // 这在合规上是明确不允许的。
      await _db.delete(_db.analyticsOutbox).go();
      // 身体数据（S12）同样是用户数据。新加表时最容易漏掉这一步，
      // 于是用户点了"删除全部数据"、体重还留在库里。
      await _db.delete(_db.bodyMetric).go();
      // 计划模板（S11）同样是用户数据
      await _db.delete(_db.routineItem).go();
      await _db.delete(_db.routine).go();
      // 埋点的本机身份（设备 ID / 会话 / 首启时间）也清掉。**这是有意的取舍**：
      // 留着它能让"90 天内重装"的排除规则生效、北极星分母更干净，
      // 但用户说"删除全部数据"时，一个能把他和过去关联起来的标识就不该留下。
      // 后果如实记录：删过数据的设备再打开会被算成一台新设备（分母多一个）。
      await _db.delete(_db.analyticsMeta).go();
      // 云备份账号（恢复码）也清掉。
      // ⚠️ 这只清了**本机**那串凭据。政策里承诺的"云端也删"是另一件事：
      // 客户端必须另外调 `DELETE /v1/account`，否则用户的数据会一直留在服务器上，
      // 而他连打开它的钥匙都没了（恢复码刚被他自己删掉）。
      // 所以「删除全部数据」必须多问一句"云端备份也删吗"。
      // **那件事已经做了**（v1.22.0，在 features/profile/profile_screen.dart 的
      // `_deleteAll()`：先问用户 → 先删云端、失败则整个中止 → 再清本机）。
      // 数据层这行只负责清**本机**那串凭据，不联网；这里曾写着"这一条还没做"，也是句过期的话。
      await _db.delete(_db.backupAccount).go();
      // 登录会话（令牌 + 邮箱 + 账号密钥）。**必须清**：注销/清除之后本机不该留下
      // 任何能代表"这个人是谁"的东西，也不该留着一个还有效的会话令牌。
      // ⚠️ 注销账号（连云端一起删）走的是 `LoginSession.deleteAccount()`，
      // 那是另一条路；这里只负责本机这一份。
      await _db.delete(_db.authSession).go();
      // exercise（动作库）刻意不删：那是产品资产，不是用户数据，
      // 删了用户就没法再记录任何动作。
    });
  }
}
