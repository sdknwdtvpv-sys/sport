/// 练了么 · 「云备份入口出不出现」在设备上的一致性
///
/// **它证明什么**（缺了它，这条链子中间是断的）：
///   * `test/backup_config_test.dart` 证明的是**判定公式**；
///   * `test/cloud_backup_screen_test.dart` 用的是**注入**的开关
///     （`cloudBackupAvailable: true/false`），所以"「我」页真的去读了编译期配置"
///     这件事它证明不了；
///   * 这里跑的是**真实 App**，读的是**真的编译期常量**。
///
/// 同一份代码跑两次，两次都必须对（断言写成"与 `isCloudBackupConfigured` 一致"，
/// 所以哪种构建都跑得通 —— 而只要有一边对不上就红）：
///
///   1. **只给地址**、不给 `LIANLEME_BACKUP_DISCLOSED`
///      → `isCloudBackupConfigured` 为 false → **入口不该出现**（失败往关闭倒：
///        那样的包政策还写着「本版本未提供云备份」，出现入口就是自相矛盾）
///   2. **两个都给** → 为 true → 入口与那句"云备份要你手动开启"都该出现
///
/// 跑法（**不需要后端**：这一份只看到入口为止，不点进去开备份）：
/// ```bash
/// # ① 只给地址 —— 期望：入口不出现
/// cd app && flutter test integration_test/cloud_entry_gate_test.dart -d emulator-5554 \
///     --dart-define=LIANLEME_BACKUP_URL=http://127.0.0.1:8790
/// # ② 两个都给 —— 期望：入口出现
/// cd app && flutter test integration_test/cloud_entry_gate_test.dart -d emulator-5554 \
///     --dart-define=LIANLEME_BACKUP_URL=http://127.0.0.1:8790 \
///     --dart-define=LIANLEME_BACKUP_DISCLOSED=true
/// ```
/// 上面两行同时也是"这个开关真的能挡住一整个功能"的现场证据。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'evidence_sets.dart';
import 'package:lianleme/backup/backup_config.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('云备份入口：与编译期配置一致（只给地址不算配好）',
      (WidgetTester tester) async {
    /// ⚠️ 与端到端那份同样的理由：**不能用 `pumpAndSettle`** ——
    /// App 里有常驻的休息计时器与埋点刷写，永远等不到"静止"。
    Future<void> settle([int ms = 1000]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    void mark(String s) => debugPrint('LIANLEME-GATE $s');

    /// 「我」页是懒构建的 ListView：没进视口就不存在（见端到端那份里的长注释）。
    Future<void> scrollProfile(Finder target) async {
      for (int i = 0; i < 12 && target.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -260));
        await settle(260);
      }
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target);
        await settle(300);
      }
    }

    final bool expectEntry = isCloudBackupConfigured;
    mark('url="${kBackupUrlDefine.isEmpty ? '(空)' : '已配'}" '
        'disclosed=$kBackupDisclosedDefine → 期望入口=${expectEntry ? '出现' : '不出现'}');

    app.main();
    await settle(6000); // 冷启动：建库 / 导入动作库 / 读设置

    // 干净安装会先撞上同意门（同意之前主界面一个像素都不渲染）
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
      mark('consent-agreed');
    }

    await switchTab(tester, 4, '我的');
    await settle(1200);
    // ⚠️ 2026-10-09 改：设置那三组入口 v1.60.0 起搬进了独立设置页（顶栏右上角那枚齿轮），
    // 云备份入口也跟着搬到了「设置 → 数据与备份」。原来这一份还在「我的」页里翻
    // `cloud-backup` / `delete-all`，那些 key 已经不在那一页了（这条测试只有人手动跑，
    // 所以一直没人发现它过期 —— 顺手一起修掉）。
    await tester.tap(find.byKey(const Key('top-bar-settings')));
    await settle(1200);

    // ①② 先看设置首页那句实话（它由同一个编译期开关分叉）
    final Finder honesty = expectEntry
        ? find.textContaining('你自己开的云备份')
        : find.textContaining('不上传任何人');
    expect(honesty, findsOneWidget,
        reason: expectEntry
            ? '配了地址的包，设置页那句实话应当承认"云备份会联网"'
            : '没配地址的包，设置首页应当说"不上传任何人"');

    // 进「数据与备份」，那里才是云备份入口的所在
    await tester.tap(find.byKey(const Key('open-data-tools')));
    await settle(1500);
    await scrollProfile(find.byKey(const Key('delete-all')));
    await scrollProfile(find.byKey(const Key('cloud-backup')));

    // ① 入口本身
    expect(
      find.byKey(const Key('cloud-backup')),
      expectEntry ? findsOneWidget : findsNothing,
      reason: expectEntry
          ? '两个编译期开关都给了，入口却没出现'
          : '只给了地址（没有 LIANLEME_BACKUP_DISCLOSED），入口**不该**出现 —— '
              '那样的包会出现"界面有入口、政策却说本版本未提供"的自相矛盾',
    );

    // ② 第二个独立信号：入口与那句实话必须同进同退
    // （原来这里是「我的」页脚那句"云备份要你手动开启"—— 2026-10-09 按 10.9 清单第 5 条删掉了，
    //  现在这个信号由上面设置首页那句顶着）
    final Finder blurb = find.byKey(const Key('cloud-backup'));
    expect(
      blurb,
      expectEntry ? findsOneWidget : findsNothing,
      reason: '「关于」里那句版本说明与入口必须同进同退（同一个开关）',
    );

    mark('ok: entry=${expectEntry ? 'shown' : 'hidden'}');
  });
}
