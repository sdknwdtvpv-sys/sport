/// 练了么 · 「存相册」在 **两个平台**上的真实行为（iOS 两条权限路 + 安卓免权限那条）
///
/// **为什么单为它写一个**：`docs/release-admin.md` 的「iOS 与安卓的差异清单」里列着
/// 一条只有 Xcode 能回答的问题 —— *"分享面板与『存到相册』在 iOS 上的真实行为
/// （权限弹窗文案、被拒之后的路径）"*。安卓那边这条早就验过（Android 10+ 走 MediaStore
/// **根本不需要权限**），iOS 却要真的过 `PHPhotoLibrary` 的 `.addOnly` 授权 ——
/// 而这是**上架审核会看的**那类行为：申请权限前有没有说明目的、被拒之后是不是如实告知。
///
/// 这一条在**模拟器**上把两条路都走一遍（宿主机预置 TCC，见下面的跑法）：
///   * **授权**：`Gal.hasAccess()` 为真 → **不该再弹**说明框（Android 10+ 免权限，同一条规矩：
///     不需要问的时候别白问）→ 存成 → 界面说「已存进相册」；
///   * **拒绝**：`hasAccess()` 为假 → 先弹**说明目的**的框（191 号文二.3）→ 用户点「继续」→
///     `Gal.requestAccess()` 返回 false → 界面**如实**说「没有相册权限，没存成」，
///     而且**不崩**（用户刚练完，最不该看到的就是崩溃）。
///
/// 安卓那一侧验的是**相反**的一件事（`LIANLEME_GALLERY_MODE=android`）：
/// Android 10+ 走 MediaStore **根本不需要权限**，所以**说明框不该出现**、
/// 存完直接说「已存进相册」——"不需要问的时候别白问一次"这条规矩的另一半。
///
/// 跑法（**必须先装一次 App 再设权限**，`simctl privacy` 要求这个 bundle 已经存在）：
/// ```bash
/// UDID=$(xcrun simctl create t com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
///          com.apple.CoreSimulator.SimRuntime.iOS-27-0)
/// xcrun simctl boot "$UDID"
/// cd app && flutter build ios --simulator
/// xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
/// xcrun simctl privacy "$UDID" revoke photos-add com.sdknwdtvpv.lianleme   # 或 grant
/// flutter test integration_test/share_card_gallery_test.dart -d "$UDID" \
///     --dart-define=LIANLEME_GALLERY_MODE=deny                            # 或 =grant
/// ```
///
/// 安卓（模拟器 API 36 = Android 16，MediaStore 免权限那条路）：
/// ```bash
/// flutter test integration_test/share_card_gallery_test.dart -d emulator-5554 \
///     --dart-define=LIANLEME_GALLERY_MODE=android
/// adb shell ls /sdcard/Pictures /sdcard/DCIM   # 图真的落进系统相册了吗
/// ```
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

/// `grant` = 宿主机已预置"允许"；`deny` = 已预置"拒绝"。
/// 一次跑一种，**断言写成"必须与这个模式相符"** —— 否则它只是"跑过去了"，证明不了行为。
const String kMode = String.fromEnvironment('LIANLEME_GALLERY_MODE');

void main() {
  // 返回值不接：`dart analyze --fatal-infos` 会把"接了却没用"的局部变量也判成问题
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('存相册：iOS 权限两条路各走一遍', (WidgetTester tester) async {
    void mark(String s) => debugPrint('LIANLEME-GALLERY $s');

    // 推进固定时长而不是等"稳定"：App 里有常驻的休息计时器
    Future<void> settle([int ms = 1200]) async {
      final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    if (Platform.isAndroid) {
      expect(kMode, 'android',
          reason: '安卓这边用 LIANLEME_GALLERY_MODE=android（验的是"免权限、不该白问"那条路）');
    } else {
      expect(kMode == 'grant' || kMode == 'deny', isTrue,
          reason: 'iOS 必须显式指定 LIANLEME_GALLERY_MODE=grant|deny —— '
              '不指定的话这条测试不知道自己在验哪条路');
    }

    app.main();
    await settle(6000);

    // 过隐私政策那道门
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2500);
    }

    // ── 走到"有记录的总结页"（分享按钮只在真有记录时出现）
    await tester.tap(find.byKey(const Key('start-workout')));
    await settle(2500);
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1600);
    await tester.tap(find.byKey(const Key('big-log-button')));
    await settle(1600);
    await tester.tap(find.byKey(const Key('back-button')));
    await settle(3000);

    expect(find.byKey(const Key('summary-share')), findsOneWidget,
        reason: '一次都没练的总结页不会有分享按钮 —— 说明上面那几步没真的记上');

    // ── 分享卡预览 → 存相册
    await tester.tap(find.byKey(const Key('summary-share')));
    await settle(1800);
    expect(find.byKey(const Key('share-card-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-card-save')));
    await settle(2000);

    // 说明目的那个框：**授权状态下不该出现**（不需要问就别白问）
    final bool rationale = find.byKey(const Key('gallery-rationale')).evaluate().isNotEmpty;
    mark('mode=$kMode rationale=$rationale');

    if (rationale) {
      // 框里必须先说清目的（系统弹框不会说）
      final String text =
          tester.widget<Text>(find.byKey(const Key('gallery-rationale'))).data!;
      expect(text.contains('写入相册'), isTrue, reason: '说明框要讲清系统会问什么');
      expect(text.contains('从不读取'), isTrue, reason: '要讲清我们不做的事');
      expect(text.contains('**'), isFalse, reason: 'Text 不渲染 markdown，用户会看到星号');
      await tester.tap(find.byKey(const Key('gallery-rationale-ok')));
      await settle(2500);
    }

    if (kMode == 'android') {
      expect(rationale, isFalse,
          reason: 'Android 10+ 走 MediaStore 免权限，不该白弹一次说明框');
      expect(find.text('已存进相册'), findsOneWidget,
          reason: '免权限那条路必须真的存成，并如实告诉用户');
      mark('toast=已存进相册（安卓免权限）');
    } else if (kMode == 'grant') {
      expect(rationale, isFalse,
          reason: '已经有权限了还弹说明框 —— 等于白问一次（与安卓免权限那条规矩相反）');
      expect(find.text('已存进相册'), findsOneWidget,
          reason: '授权状态下必须真的存成，并如实告诉用户');
      mark('toast=已存进相册');
    } else {
      expect(rationale, isTrue,
          reason: '还没授权时必须先说明目的，再走系统授权 —— 这是审核会看的那一步');
      expect(find.text('没有相册权限，没存成'), findsOneWidget,
          reason: '被拒之后要**如实**说没存成，不能假装成功');
      mark('toast=没有相册权限，没存成');
    }

    mark('GALLERY-OK mode=$kMode');
  });
}
