/// 练了么 · 云备份端到端（真机上跑**真实 App**，打**真实后端**）
///
/// **它证明什么**：`test/cloud_backup_test.dart` 已经证明"服务端拿到的只有密文"，
/// 但那是 Dart 进程里的 HTTP。这一份走的是**完整的那条路**：
/// 真实 App（真实字体、真实布局、真实权限）→ 真实 HTTP → 真实 `server/backend.mjs`。
///
/// **"换手机"是在一次 run 里演的**，而且**只用 App 自己的界面**：
///   1. 记两组 → 我 → 云备份 → 开启（把恢复码读出来留在内存里）→ 立即备份
///   2. 我 → 删除全部数据（**故意不勾"同时删除云端备份"**）← 这一步等于换了台新手机
///   3. 用刚才那串恢复码"取回已有备份" → 从云端恢复
///   4. 断言数据真的回来了
/// 全程没有第二台设备、没有跨进程传密钥 —— 因为"新手机"要的东西就是那串码，
/// 而它就握在用户手里（这里握在测试手里）。
///
/// 跑法（**必须先在宿主端起后端、并把端口反代到设备**）：
/// ```bash
/// node server/backend.mjs --port 8790 --db /tmp/e2e/backend.sqlite &
/// adb -s emulator-5554 reverse tcp:8790 tcp:8790     # 模拟器/真机都靠这条走回环
/// adb -s emulator-5554 shell pm clear com.sdknwdtvpv.lianleme   # 从干净状态开始
/// cd app && flutter drive --driver=test_driver/cloud_e2e_driver.dart \
///     --target=integration_test/cloud_backup_e2e_test.dart -d emulator-5554 \
///     --dart-define=LIANLEME_BACKUP_URL=http://127.0.0.1:8790 \
///     --dart-define=LIANLEME_BACKUP_DISCLOSED=true      # 少了这个，入口根本不出现（失败往关闭倒）
/// ```
/// ⚠️ 必须用 `127.0.0.1` + `adb reverse`，**不能**用模拟器那套 `10.0.2.2`：
/// `dart:io` 会拒绝明文的非回环地址（"Insecure HTTP is not allowed by platform"），
/// 而回环有豁免 —— 这条踩过（见 `docs/dev-environment.md`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/backup/recovery_code.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('云备份：开启 → 备份 → 换手机 → 用恢复码恢复', (WidgetTester tester) async {
    /// ⚠️ **不能用 `pumpAndSettle`**：App 里有常驻的休息计时器与埋点刷写，
    /// 永远等不到"静止"。推进固定时长（与截图测试同一套写法）。
    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    /// 记一步日志（这些行会出现在 `flutter drive` 的输出里，是唯一的现场线索）
    void mark(String s) => debugPrint('LIANLEME-E2E $s');

    /// 取某个 key 上的文本。
    ///
    /// **两种都要能吃**：`cloud-server-state` 的 key 落在 `Text` 上，而提示横幅
    /// （`cloud-notice`）的 key 落在包着 Text 的 `Container` 上 ——
    /// 第一版直接 `widget<Text>(...)`，于是撞上 `type 'Container' is not a subtype of type 'Text'`。
    String textAt(Key key) {
      final Finder f = find.byKey(key);
      final Widget w = tester.widget(f);
      if (w is Text) return w.data!;
      return tester
          .widget<Text>(find.descendant(of: f, matching: find.byType(Text)))
          .data!;
    }

    /// 「我」页是懒构建的 ListView：目标不在视口里时 `find` 直接落空。
    /// 所以自己滚 —— 不用 `dragUntilVisible`，它内部会 `pumpAndSettle`。
    /// [up] = true 时往上滚（目标在当前视口**上方**时用）。
    /// 空态那句"还没有训练记录"就在统计卡里，而删完数据时视口停在最底下的
    /// 「删除全部数据」那儿 —— 不往回滚就找不到（懒构建，没进视口就不存在）。
    Future<void> scrollToInProfile(Finder target, {bool up = false}) async {
      for (int i = 0; i < 12 && target.evaluate().isEmpty; i++) {
        await tester.drag(
            find.byType(ListView), Offset(0, up ? 260 : -260));
        await settle(260);
      }
      expect(target, findsOneWidget, reason: '滚了 12 次还是没找到目标');
      // ⚠️ 只"找到"还不够：懒构建的列表里，目标可能刚好卡在视口下沿，
      // 这时 `tap` 会打在视口外面 —— **不报错，也点不动**。
      // 第一版就栽在这儿：`cloud-enable` 找不到，看起来像"没配地址"，
      // 其实是那一下点击根本没落到 tile 上。
      await tester.ensureVisible(target);
      await settle(400);
    }

    app.main();
    await settle(6000); // 冷启动：建库 / 导入 351 个动作 / 读设置
    mark('app-started');

    // 首次启动多了一道**隐私政策同意门**（法律要求，见
    // features/onboarding/privacy_consent_screen.dart）：干净安装的包里
    // 主界面在同意之前一个像素都不渲染。所以这里必须先同意 ——
    // 这一步同时也算"在真机上真的点过那道门"的证据。
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
      mark('privacy-consent-agreed');
    }


    // ---------------------------------------------------------------- 1. 先有数据
    await tester.tap(find.byKey(const Key('start-workout')));
    await settle(2500);
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1500);
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1500);
    await tester.tap(find.byKey(const Key('back-button')));
    await settle(3000); // 结束训练 → 弹总结
    await tester.tap(find.byKey(const Key('summary-done')));
    await settle(2000);
    mark('logged-2-sets');

    // 把"换手机之前"的本机数据**逐字段**抄一份下来。
    // 为什么要抄：原来这条端到端只验到"统计卡显示 2 组"——**个数对**不等于**内容对**，
    // 万一恢复出来重量/次数/动作是错的，那一步照样绿。下面恢复完之后会逐字段比。
    Future<List<String>> snapshotLocalSets() async {
      final AppDatabase db = openAppDatabase();
      final List<SetRecord> sets = await DriftLocalStore(db).allSets();
      final List<String> rows = <String>[
        for (final SetRecord r in sets)
          '${r.id}|${r.workoutId}|${r.exerciseId}|${r.setIndex}|${r.reps}|'
              '${r.weightKg}|${r.completedAtMs}|${r.setType.name}',
      ]..sort();
      await db.close();
      return rows;
    }

    final List<String> before = await snapshotLocalSets();
    expect(before, hasLength(2), reason: '先确认本机真的有两组要备份');
    mark('snapshot-before=${before.join(' ／ ')}');

    // ---------------------------------------------------------------- 2. 开启云备份
    await tester.tap(find.byKey(const Key('tab-我')));
    await settle(1800);
    await scrollToInProfile(find.byKey(const Key('cloud-backup')));
    await tester.tap(find.byKey(const Key('cloud-backup')));
    await settle(1500);
    // 失败时先看清"到底停在哪一屏"：这一行比任何猜测都管用
    mark('after-entry-tap back=${find.byKey(const Key('cloud-back')).evaluate().length} '
        'enable=${find.byKey(const Key('cloud-enable')).evaluate().length} '
        'notConfigured=${find.text('这个版本没有配备份服务器').evaluate().length}');

    expect(find.byKey(const Key('cloud-enable')), findsOneWidget,
        reason: '没配 LIANLEME_BACKUP_URL 时连入口都不该出现；这里应该已经配了');
    await tester.tap(find.byKey(const Key('cloud-enable')));
    await settle(800);
    await tester.tap(find.byKey(const Key('cloud-agree')));
    await settle(2500); // 建号要走一次网络

    // 建号失败时界面上会有错误横幅 —— 把它打进日志，别让人对着
    // "cloud-new-code 找不到"猜（这一次就是：宿主端的 sqlite 被我删了，
    // 而服务端还开着旧句柄，接口直接 500）。
    if (find.byKey(const Key('cloud-error')).evaluate().isNotEmpty) {
      mark('enable-failed: ${textAt(const Key('cloud-error'))}');
    }
    expect(find.byKey(const Key('cloud-new-code')), findsOneWidget,
        reason: '恢复码对话框没出来 —— 建号失败了？（日志里有 enable-failed 的话看它）');
    final String shown = tester
        .widget<SelectableText>(find.byKey(const Key('cloud-new-code')))
        .data!;
    final String code = normalizeRecoveryCode(shown);
    expect(code.length, kRecoveryCodeLength);
    mark('account-created code=$shown');

    await tester.tap(find.byKey(const Key('cloud-wrote-check')));
    await settle(400);
    await tester.tap(find.byKey(const Key('cloud-new-ok')));
    await settle(2000);
    mark('cloud-enabled');

    // ---------------------------------------------------------------- 3. 备份上去
    await tester.tap(find.byKey(const Key('cloud-upload')));
    await settle(3000);
    final String upNotice = textAt(const Key('cloud-notice'));
    expect(upNotice, contains('已备份'), reason: '上传失败时界面会显示错误而不是这句');
    expect(upNotice, contains('1 次训练'), reason: '刚才记的是 1 次训练');
    mark('uploaded: $upNotice');

    // 云端状态那一行也是真实后端的回答（不是本机记录）
    final String serverLine = textAt(const Key('cloud-server-state'));
    expect(serverLine, startsWith('云端：'), reason: '应该在"上次备份"下面显示云端真实状态');
    mark('server-state: $serverLine');

    // ---------------------------------------------------------------- 4. 换手机
    await tester.tap(find.byKey(const Key('cloud-back')));
    await settle(1500);
    await scrollToInProfile(find.byKey(const Key('delete-all')));
    await tester.tap(find.byKey(const Key('delete-all')));
    await settle(800);

    // **故意不勾"同时删除云端备份"** —— 换手机的人不会把云端删掉，
    // 而且这一步同时验了"不勾时云端那份要留着"。
    expect(tester.widget<CheckboxListTile>(
      find.byKey(const Key('delete-all-cloud'))).value, isTrue,
      reason: '默认应当是"也删"');
    await tester.tap(find.byKey(const Key('delete-all-cloud')));
    await settle(500);
    await tester.tap(find.byKey(const Key('delete-all-confirm')));
    await settle(2500);
    mark('local-data-deleted (cloud kept)');

    // 本机现在是空的。
    // ⚠️ 空的时候「我」页**不显示统计行**（那是空态，不是"0 组"）——
    // 第一版在这里断言 '0 组'，于是找不到 key。空态本身就是证据。
    await scrollToInProfile(find.textContaining('还没有训练记录'), up: true);
    expect(find.textContaining('还没有训练记录'), findsOneWidget,
        reason: '删除全部数据之后本机应当回到空态');
    expect(find.byKey(const Key('profile-stat-sets')), findsNothing,
        reason: '空态下不该有统计行');

    // ---------------------------------------------------------------- 5. 用恢复码取回
    await scrollToInProfile(find.byKey(const Key('cloud-backup')));
    await tester.tap(find.byKey(const Key('cloud-backup')));
    await settle(1500);
    expect(find.byKey(const Key('cloud-enable')), findsOneWidget,
        reason: '删除全部数据也清掉了本机凭据 —— 现在应当回到"还没开启"');

    await tester.tap(find.byKey(const Key('cloud-adopt')));
    await settle(800);
    await tester.enterText(find.byKey(const Key('cloud-adopt-input')), shown);
    await settle(400);
    await tester.tap(find.byKey(const Key('cloud-adopt-ok')));
    await settle(2500);
    mark('adopted-existing-code');

    await tester.tap(find.byKey(const Key('cloud-restore')));
    await settle(3500);
    final String restoreNotice = textAt(const Key('cloud-notice'));
    expect(restoreNotice, contains('已从云端恢复'), reason: '恢复失败会显示错误');
    expect(restoreNotice, contains('1 次训练'), reason: '云端那份就是这一次训练');
    mark('restored: $restoreNotice');

    // ---------------------------------------------------------------- 6. 数据真的回来了
    await tester.tap(find.byKey(const Key('cloud-back')));
    await settle(1500);
    // 统计卡在**上方**（视口还停在"数据"区）
    await scrollToInProfile(find.byKey(const Key('profile-stat-sets')), up: true);
    expect(textAt(const Key('profile-stat-sets')), '2 组',
        reason: '换手机之后本机必须把 2 组拿回来');

    // **逐字段**比对：动作、重量、次数、组序、完成时间、组类型，一个都不许变。
    // 个数对只是"看起来回来了"，字段对才是"真的回来了"。
    final List<String> after = await snapshotLocalSets();
    mark('snapshot-after=${after.join(' ／ ')}');
    expect(after, orderedEquals(before),
        reason: '恢复出来的每一组必须与换手机之前**逐字段一致**'
            '（id / workoutId / 动作 / 组序 / 次数 / 重量 / 完成时间 / 组类型）');

    mark('verified-2-sets-restored (field-by-field)');
    mark('E2E-OK');
  });
}
