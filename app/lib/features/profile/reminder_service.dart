/// 练了么 · 训练提醒的"什么时候排、排什么"
///
/// 这一层把三件事捏在一起：**用户的设置**（要不要提醒、几点）、
/// **今天的训练情况**（练过了就不打扰）、以及**平台桥**（交给系统去响）。
///
/// 它被调用的时机就三类：开 App、练完一次、用户改设置 —— 三处都调同一个
/// `sync()`，这样"提醒"永远与"当前的事实"一致（包括用户刚关掉开关那一刻）。
library;

import '../../data/local_store.dart';
import '../../domain/models.dart';
import '../../data/reminder_repository.dart';
import 'reminder.dart';
import 'reminder_bridge.dart';

class ReminderService {
  ReminderService({
    required this.repository,
    required this.bridge,
    required this.store,
  });

  final ReminderRepository repository;
  final ReminderBridge bridge;
  final LocalStore store;

  /// 把系统的排程同步成"现在这个设置 + 今天这个事实"该有的样子。
  ///
  /// 幂等：调多少次结果都一样（每次都先取消再排）。练完一次调它，就会把
  /// "今天已经练过了"这件事反映成"顺延到明天"。
  Future<void> sync({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final ReminderSettings settings = await repository.load();

    if (!settings.enabled) {
      await bridge.cancel();
      return;
    }

    final List<SetRecord> sets = await store.allSets();
    final int? at = nextReminderAtMs(
      nowMs: now,
      minutesOfDay: settings.minutesOfDay,
      trainedToday: hasTrainedOn(
        sets: sets,
        day: DateTime.fromMillisecondsSinceEpoch(now),
      ),
    );
    if (at == null) {
      await bridge.cancel();
      return;
    }
    await bridge.schedule(ReminderRequest(
      atMs: at,
      title: '今天还没练',
      body: '练一组就记一次 —— 打开就是今天的安排',
    ));
  }
}
