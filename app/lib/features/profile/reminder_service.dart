/// 练了么 · 训练提醒的"什么时候排、排什么"
///
/// 这一层把三件事捏在一起：**用户的设置**（要不要提醒、几点）、
/// **今天的训练情况**（练过了就不打扰）、以及**平台桥**（交给系统去响）。
///
/// 它被调用的时机就三类：开 App、练完一次、用户改设置 —— 三处都调同一个
/// `sync()`，这样"提醒"永远与"当前的事实"一致（包括用户刚关掉开关那一刻）。
///
/// **2026-10-05 加的第二件事：训练结束那条预告**（`next_training_copy.dart`）。
/// 它不是"多一条通知"，而是**同一个提醒位置上换一句更具体的话**：
///   * 练完了、而且知道下次练哪儿 → 今晚那个点说「明天该练背了」（不再是"今天还没练"）；
///   * 说不出来（没有下次部位 / 那个点今天已经过了 / 没练过）→ 一字不改地退回原来那条。
///
/// ⚠️ **为什么不新开一个通知位**：两个平台的真身都只有**一个**排程位
/// （Android 一个 `requestCode`、iOS 一个 `requestId`），值是"同一时刻只该有一条提醒"。
/// 想再多排一条就得动两端原生 + 再想清楚两条撞在一起怎么办 —— 而这句话本来就属于
/// 同一件事（"下一次该练了"），换句话就够了。
library;

import '../../data/local_store.dart';
import '../../domain/models.dart';
import '../../data/reminder_repository.dart';
import 'next_training_copy.dart';
import 'reminder.dart';
import 'reminder_bridge.dart';

/// 「今天还没练」那条的文案（通用版）。
///
/// 只在这里写一次：`composeReminder` 与测试都引它，免得文案在两处漂开。
const String kTrainingReminderTitle = '今天还没练';
const String kTrainingReminderBody = '练一组就记一次 —— 打开就是今天的安排';

/// 下一次练哪个部位（给"训练结束提醒"用的**输入**，不是文案）。
///
/// 返回 null = 说不出来（没有训练历史 / 库对不上）→ 预告那条就不排，退回通用那条。
/// 抽成函数类型而不是让服务依赖 planner：这一层只该知道"问谁能拿到答案"。
typedef NextMuscleKey = Future<String?> Function();

/// **要不要排、排在哪、说什么** —— 纯函数，服务只负责把它交给桥。
///
/// 三档判断（顺序就是优先级）：
///   1. 开关关着 → null（调用方负责把系统里旧的撤掉）；
///   2. **今天练过 + 知道下次部位 + 用户那个点还没过** → 训练结束那条预告，
///      排在**今天**那个点：练完当天晚上告诉你"明天该练背了"；
///   3. 其它（没练过的、说不出下次部位的、那个点今天已经过去的）→ 通用那条，
///      行为与本功能上线前**一字不差**。
///
/// 第 2 档里"那个点今天已经过去就退回通用"是刻意的：`nextTrainingReminderAt` 遇到
/// 过了点会顺延到明天，而"明天该练背了"这句**明天晚上才响出来就成了假话**
/// （那时候"明天"是后天）。宁可不发这句预告，也不发一句此刻不成立的话 ——
/// 这是这个项目一贯的口径（见 `docs/feature-backlog.md` 第三轮）。
ReminderRequest? composeReminder({
  required int nowMs,
  required ReminderSettings settings,
  required bool trainedToday,
  String? nextMuscleKey,
}) {
  if (!settings.enabled) return null;

  // 通用那条先算出来：它既是第 3 档的答案，也是"预告说不出来"时的退路。
  // ⚠️ 非法时间会在这里得到 null（宁可没有提醒，也不要排在错的钟点）。
  final int? genericAt = nextReminderAtMs(
    nowMs: nowMs,
    minutesOfDay: settings.minutesOfDay,
    trainedToday: trainedToday,
  );
  if (genericAt == null) return null;
  final ReminderRequest generic = ReminderRequest(
    atMs: genericAt,
    title: kTrainingReminderTitle,
    body: kTrainingReminderBody,
  );

  if (!trainedToday) return generic;
  final (String, String)? copy = nextTrainingReminderCopy(nextMuscleKey);
  if (copy == null) return generic;

  final int nudgeAt = nextTrainingReminderAt(
    nowMs: nowMs,
    minutesOfDay: settings.minutesOfDay,
  );
  if (!isSameLocalDay(nudgeAt, nowMs)) return generic;
  return ReminderRequest(atMs: nudgeAt, title: copy.$1, body: copy.$2);
}

class ReminderService {
  ReminderService({
    required this.repository,
    required this.bridge,
    required this.store,
    this.nextMuscle,
  });

  final ReminderRepository repository;
  final ReminderBridge bridge;
  final LocalStore store;

  /// "下一次该练哪个部位"从哪问（生产由 `main.dart` 接上 `TodayPlanner`）。
  /// 不传 = 这条预告功能没接上，行为与从前完全一致（单测就是这么跑的）。
  final NextMuscleKey? nextMuscle;

  /// 把系统的排程同步成"现在这个设置 + 今天这个事实"该有的样子。
  ///
  /// 幂等：调多少次结果都一样（每次都先取消再排）。练完一次调它，就会把
  /// "今天已经练过了"这件事反映成"今晚告诉你明天练什么 / 否则顺延到明天"。
  Future<void> sync({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final ReminderSettings settings = await repository.load();

    if (!settings.enabled) {
      await bridge.cancel();
      return;
    }

    final List<SetRecord> sets = await store.allSets();
    final bool trainedToday = hasTrainedOn(
      sets: sets,
      day: DateTime.fromMillisecondsSinceEpoch(now),
    );
    // 只在"今天练过"时才会用到下次部位：没练过的时候问了也用不上，
    // 而且那会白白读一次库（`sync()` 在冷启动路径上）。
    final String? nextMuscleKey = trainedToday ? await _askNextMuscle() : null;

    final ReminderRequest? request = composeReminder(
      nowMs: now,
      settings: settings,
      trainedToday: trainedToday,
      nextMuscleKey: nextMuscleKey,
    );
    if (request == null) {
      await bridge.cancel();
      return;
    }
    await bridge.schedule(request);
  }

  /// 问"下次练哪个部位"。**失败静默**：这条预告排不上，绝不该影响记录训练
  /// （与 `ReminderBridge` 的静默口径一致）。
  Future<String?> _askNextMuscle() async {
    final NextMuscleKey? ask = nextMuscle;
    if (ask == null) return null;
    try {
      final String? key = await ask();
      return (key == null || key.isEmpty) ? null : key;
    } catch (_) {
      return null;
    }
  }
}
