/// 练了么 · 动作库刷新失败时，**遥测里到底发了什么**
///
/// **为什么单列一条**：政策里 `seed_import_failed` 的字段表写的是
/// `error`（**错误类型，不含内容**），而代码原先发的是 `'$e'` —— **整条异常消息**。
/// 那可能带出文件路径之类的设备细节（`'$e'` 还会连类名一起发出去），也就是说
/// **政策说的和代码做的不是一回事**。
///
/// 这类"政策措辞 vs 代码行为"的偏差，`privacy-audit` 只能核到**字段名**那一层
/// （它不知道发的是类型还是整条消息），所以必须有一条测试把它钉住。
///
/// 顺带它也是**唯一**一条真的驱动"冷启动 + 动作库刷新失败"这条路的测试：
/// 之前没有任何测试跑过 `_importSeedQuietly` 的 catch 分支。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/analytics/outbox.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  /// 加载器**延迟一会儿再抛**，而且消息里带一个只可能来自"消息"的记号。
  ///
  /// ⚠️ 为什么要延迟：冷启动时 `_initAnalytics()` 与 `_importSeedQuietly()` 是**并发**发的，
  /// 而"统计开没开"是从库里异步读出来的 —— 失败太快的话，事件会发生在 `setEnabled(true)`
  /// 之前，于是被**正确地**丢掉（默认关的纪律）。第一版就是这么写的，测试空转。
  Future<String> failingLoader() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    throw const FormatException('SEED-ERR-7021');
  }

  testWidgets('刷新失败：遥测里只有错误**类型**，没有整条消息', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // ⚠️ 两道门都得先过，否则冷启动根本走不到动作库导入那一步：
    //   ① 隐私政策总同意 —— 没同意时 App 停在同意门那儿，`_importSeedQuietly()` 压根不发；
    //   ② 统计开关 —— 默认关，关着的话即使出了错也不会入队（默认关的纪律）。
    await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
    await ProfileRepository(db).setAnalyticsEnabled(true, nowMs: 1);

    await tester.pumpWidget(app.LianLeMeApp(
      database: db,
      seedLoader: failingLoader,
    ));
    // 冷启动那几步是异步的：推一会儿时间让 catch 分支真的跑到
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final List<AnalyticsEventPayload> rows = await AnalyticsOutboxStore(db).takeBatch();
    final AnalyticsEventPayload event = rows.firstWhere(
      (AnalyticsEventPayload r) => r.name == 'seed_import_failed',
      orElse: () => throw StateError(
          '没记到 seed_import_failed —— 要么统计没开，要么 catch 分支没跑到；'
          '这条测试会变成空转，别当成通过'),
    );

    final String error = '${event.props['error']}';
    expect(error, isNotEmpty, reason: 'error 字段必须在');

    // ① 不含消息内容（政策承诺"不含内容"）—— 这是这条测试真正的牙
    expect(error.contains('SEED-ERR-7021'), isFalse,
        reason: '遥测里带上了异常消息的内容 —— 政策写的是「错误类型，不含内容」');
    // ② 是一个类型名，而不是一整句话
    expect(error.length, lessThan(40), reason: 'error 应该是个类型名（短），不是整条消息');
    expect(error.contains('Exception') || error.contains('Error'), isTrue,
        reason: '应该是 `runtimeType` 那样的类型名（例如 FormatException）');
  });
}
