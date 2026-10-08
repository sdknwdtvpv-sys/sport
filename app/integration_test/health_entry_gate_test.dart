/// 练了么 · 「从系统健康同步」这个入口**在真设备上出不出现**（由平台自己回答）
///
/// **它补的是哪一段**（缺了它，这条链子中间是断的）：
///   * `test/health_sync_test.dart` 证明的是**规则**（合并、同意门、桥的降级），
///     而它的页面那几条用的是**注入**的假桥 + `debugDefaultTargetPlatformOverride`
///     伪装的平台；
///   * 「真实 App 跑在真的 iOS / 真的安卓上时，那个入口到底出不出来」——
///     也就是 `defaultTargetPlatform` 那一个判断 + 整条导航路径 —— 只有这里能证明。
///
/// 断言写成"**与平台自己的回答一致**"，所以同一份测试在两种设备上都成立：
/// 期望值不是按机型猜的，而是先问一次 `HealthBridge.isAvailable()`
///   * iOS → HealthKit（iPhone 上恒为 true）→ 入口**出现**；
///   * 安卓 → **只有 14+ 且系统里真有 Health Connect 模块**才是 true → 那才出现，
///     13 及以下**不出现**（见 `docs/plan-health-sync.md` §七）。
/// 这正是 `docs/privacy-facts.json` 里 `healthSync._platforms` 那句承诺的现场证据，
/// 而且它验的是"界面说的"与"平台说的"一致 —— 比按机型猜期望值强。
///
/// ⚠️ **这条测试故意不去点那个入口。** 点下去的第一个平台副作用是
/// `requestAuthorization` → **系统级的健康授权弹窗** —— 那是系统 UI，测试框架既点不到、
/// 也关不掉，整条测试会永远卡在那里（与"钥匙串弹窗卡住 codesign"同一类问题）。
/// 所以这里只验到"入口在不在"，点进去之后的流程由 `test/health_sync_test.dart`
/// 用假桥覆盖（那里连"没同意时桥一次都没被调用"都钉住了）。
///
/// 跑法：
/// ```bash
/// # iOS 模拟器（期望：入口出现）
/// cd app && flutter test integration_test/health_entry_gate_test.dart -d <iOS 模拟器 UDID>
/// # 安卓（期望：入口不出现）
/// cd app && flutter test integration_test/health_entry_gate_test.dart -d emulator-5554
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/health/health_bridge.dart';
import 'package:lianleme/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('「从系统健康同步」入口：出不出现由平台自己回答（与它一致）',
      (WidgetTester tester) async {
    /// ⚠️ 不能用 `pumpAndSettle`：App 里有常驻的休息计时器与埋点刷写，永远等不到"静止"
    /// （与端到端那份同一个理由）。
    Future<void> settle([int ms = 1000]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    void mark(String s) => debugPrint('LIANLEME-HEALTH-GATE $s');

    app.main();
    await settle(6000); // 冷启动：建库 / 导入动作库 / 读设置

    // 干净安装会先撞上隐私政策同意门
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
      mark('consent-agreed');
    }

    // 干净安装除了同意门还有**引导页轮播** —— 不跳过它，外壳（底栏）根本不会渲染，
    // 底下那几个 `tab-*` 一个都找不到（第一次跑就栽在这儿）。
    if (find.byKey(const Key('intro-skip')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('intro-skip')));
      await settle(1500);
      mark('intro-skipped');
    }

    // 走「进步」页那张体重卡片上的按钮 → 身体数据页。
    // ⚠️ 为什么不用首页那个 `quick-weight`：那是**今天有事要练**时才渲染的快捷入口，
    // 干净设备上首页是空状态，找不到它（第一次写这条测试就栽在这儿）。
    // 「进步」页的这张卡**没数据也在**（`w == null` 时按钮写「记录」），所以它稳定。
    await tester.tap(find.byKey(const Key('tab-进步')));
    await settle(1500);
    final Finder weightEdit = find.byKey(const Key('progress-weight-edit'));
    for (int i = 0;
        i < 10 && weightEdit.evaluate().isEmpty && find.byType(Scrollable).evaluate().isNotEmpty;
        i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await settle(260);
    }
    expect(weightEdit, findsOneWidget, reason: '「进步」页那张体重卡上的按钮没找到');
    await tester.tap(weightEdit);
    await settle(2000);

    // 身体数据页自己那道「敏感个人信息单独同意」——干净安装时会先弹它
    if (find.byKey(const Key('body-consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('body-consent-agree')));
      await settle(1500);
      mark('body-consent-agreed');
    }

    // **期望值由平台自己回答**（这一条才是这个文件真正要验的东西）：
    //   * iOS → HealthKit（`isHealthDataAvailable`，iPhone 上恒为 true）；
    //   * Android → **只有 14+ 且系统里真有 Health Connect 模块才是 true**。
    // 所以同一份测试在两种设备上都成立，而且验的是"界面说的"与"平台说的"一致 ——
    // 比"按机型猜一个期望值"强，因为猜错的那一半用户会看到一个点下去读不到的入口。
    final bool platformSaysYes =
        await const MethodChannelHealthBridge().isAvailable();
    final bool expectEntry = platformSaysYes;
    mark('platform=$defaultTargetPlatform · 平台说能读=$platformSaysYes → '
        '期望入口=${expectEntry ? '出现' : '不出现'}');

    // 入口在列表顶部，但页面本身可能停在别处 —— 先试着把它拖进视口
    final Finder entry = find.byKey(const Key('health-sync-entry'));
    for (int i = 0; i < 6 && entry.evaluate().isEmpty; i++) {
      await tester.drag(find.byKey(const Key('body-scroll')), const Offset(0, 260));
      await settle(260);
    }

    expect(
      entry,
      expectEntry ? findsOneWidget : findsNothing,
      reason: expectEntry
          ? '平台说这台设备能读系统健康库，入口却没出现 —— 要么平台判断被改坏了，'
              '要么它被挡在视口外'
          : '平台说这台设备读不到（安卓 13 及以下、或系统没有 Health Connect 模块），'
              '入口**不该**出现 —— 出现就是给了一个点下去什么都读不到的承诺',
    );

    // 第二个独立信号：副标题那句（万一有人只改了入口那一处）
    expect(
      find.textContaining('只读体重、体脂率、身高'),
      expectEntry ? findsOneWidget : findsNothing,
      reason: '入口与它那句说明必须同进同退（同一个平台判断）',
    );

    // 没同意过的时候，**不该**出现撤回入口（没什么可撤回的）
    expect(
      find.byKey(const Key('health-revoke')),
      findsNothing,
      reason: '干净设备上还没同意过，不该有撤回入口',
    );

    mark('ok: entry=${expectEntry ? 'shown' : 'hidden'}');
  });
}
