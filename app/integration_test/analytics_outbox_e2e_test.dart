/// 练了么 · 「默认关」在**设备上、对真实数据库**的证明
///
/// **它补的是 A2 最后一块设备级证据**（审计第一条的后半段）。此前：
///   * `test/backup_config_test.dart` 证的是判定公式；
///   * `test/profile_test.dart` / `test/privacy_consent_test.dart` 用的是**测试自己造的库**；
///   * `cloud_entry_gate_test.dart` 证的是"入口出不出来"。
/// 没有任何一条证明过：**在设备上跑完一整轮训练之后，应用自己的数据库里到底攒了几条事件**。
/// 这一条就是干这个：跑真实 App（`app.main()`），跑完流程，然后直接读**同一台设备上的**库。
///
/// 两跑，缺一不可（否则这条检查可能是空转）：
/// ```bash
/// # ① 默认（统计关）—— 期望：队列里 0 条
/// cd app && flutter test integration_test/analytics_outbox_e2e_test.dart -d emulator-5554
/// # ② 预先把开关打开 —— 期望：队列里 > 0 条（证明"能看见事件"这件事本身不是假的）
/// cd app && flutter test integration_test/analytics_outbox_e2e_test.dart -d emulator-5554 \
///     --dart-define=LIANLEME_E2E_ANALYTICS=on
/// ```
/// ② 之所以必须跑：如果测量方式坏了（比如查错了表、或事件根本没写进库），
/// ① 也会"通过"—— 那就是一条永远绿的假守卫。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/main.dart' as app;

/// `on` = 先把「帮助改进产品」打开再启动 App；否则走默认（关）
const String kMode = String.fromEnvironment('LIANLEME_E2E_ANALYTICS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('设备上跑完一轮训练：真实库里的待发事件条数符合开关状态',
      (WidgetTester tester) async {
    final bool analyticsOn = kMode == 'on';

    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    void mark(String s) => debugPrint('LIANLEME-OUTBOX $s');

    // ---------------------------------------------------------------- 预备
    // ② 模式：先把开关写进**真实的那个库**，再启动 App —— 因为启动时会读它。
    if (analyticsOn) {
      final AppDatabase seed = openAppDatabase();
      await ProfileRepository(seed).setPrivacyConsent(nowMs: 1);
      await ProfileRepository(seed).setAnalyticsEnabled(true, nowMs: 2);
      await seed.close();
      mark('preset: analytics_enabled = 1');
    }
    mark('mode=${analyticsOn ? 'on' : 'off(default)'}');

    // ---------------------------------------------------------------- 跑真实 App
    app.main();
    await settle(6000); // 冷启动：建库 / 导入动作库 / 读设置

    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
      mark('consent-agreed');
    }

    // 一次完整训练：开始 → 记两组 → 结束 → 总结
    await tester.tap(find.byKey(const Key('start-workout')));
    await settle(2500);
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1500);
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1500);
    await tester.tap(find.byKey(const Key('back-button')));
    await settle(3000);
    await tester.tap(find.byKey(const Key('summary-done')));
    await settle(2000);
    mark('workout-done');

    // ---------------------------------------------------------------- 读**设备上真实的库**
    final AppDatabase db = openAppDatabase();
    final int pending = await AnalyticsOutboxStore(db).pending();
    final bool stored = await ProfileRepository(db).analyticsEnabled();
    mark('analytics_enabled=$stored · pending=$pending');
    await db.close();

    if (analyticsOn) {
      expect(pending, greaterThan(0),
          reason: '开关是开的、又跑了一整轮训练，队列里却一条都没有 —— '
              '要么事件没写进库，要么这条测量本身是坏的（那样 ① 的"通过"也不算数）');
    } else {
      expect(pending, 0,
          reason: '默认关（谁都没主动打开）：跑完整轮训练后，本机队列必须**一条都没有**。'
              '这正是政策里"默认关闭，只有你主动打开才会有数据发出去"那句话的设备级证据');
    }
  });
}
