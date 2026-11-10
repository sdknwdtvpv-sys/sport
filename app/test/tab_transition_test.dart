/// 练了么 · v3.0.0 新导航切换（今天 / 现在 / 日志）
///
/// 中间「现在」不是 Tab（由外壳拦截去开始/回到会话），所以页面只在「今天(0)」与
/// 「日志(2)」之间切换；1 号页保留为占位、不参与底栏选中。
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/motion.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/main.dart';

Future<void> _pumpShell(WidgetTester tester) async {
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await ProfileRepository(db).setPrivacyConsent(nowMs: 1);
  await tester.pumpWidget(LianLeMeApp(database: db));
  await tester.pumpAndSettle();
}

double _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!.toDouble();

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('Android：点「日志」真的在动（不再瞬切）', (WidgetTester tester) async {
    await _pumpShell(tester);
    expect(_page(tester), closeTo(0.0, 0.01), reason: '初始在「今天」');

    await tester.tap(find.byKey(const Key('tab-日志')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final double mid = _page(tester);
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(2.0));
    await tester.pumpAndSettle();
    expect(_page(tester), closeTo(2.0, 0.01));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iOS：同一段动画（两条平台的手感一致）', (WidgetTester tester) async {
    await _pumpShell(tester);
    debugSwitchTab?.call(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final double mid = _page(tester);
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(2.0));
    await tester.pumpAndSettle();
    expect(_page(tester), closeTo(2.0, 0.01));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('切换时长来自 Motion.pageTransition，不随距离改',
      (WidgetTester tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('tab-日志')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final double progress = (_page(tester) - 0.0) / 2.0;
    final double expected = Motion.standard.transform(0.5);
    expect(progress, closeTo(expected, 0.06));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('反向自检：`_selectTab` 里不许再有平台判断', () {
    final String src = File('lib/main.dart').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'void _selectTab\(int i\) \{([\s\S]*?)\n  \}').firstMatch(src);
    expect(m, isNotNull);
    final String body = m!
        .group(1)!
        .split('\n')
        .map((String l) {
          final int i = l.indexOf('//');
          return i < 0 ? l : l.substring(0, i);
        })
        .join('\n');
    expect(body.contains('GlassSurface.isSupportedPlatform'), isFalse,
        reason: 'Tab 动画两条平台共用一段');
  });
}
