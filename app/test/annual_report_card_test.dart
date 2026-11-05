/// 练了么 · 年度报告卡 / 屏幕（Ultra 权益 9）
///
/// 判据：空数据如实空态、数字不编、大字号不溢出、渲染幂等、年份切换。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/profile/annual_report.dart';
import 'package:lianleme/features/profile/annual_report_card.dart';
import 'package:lianleme/features/profile/annual_report_screen.dart';
import 'package:lianleme/features/summary/share_card_exporter.dart';

SetRecord _set(String id, String exerciseId, int atMs,
        {double? weightKg, int reps = 8, double? distanceM}) =>
    SetRecord(
      id: id,
      workoutId: 'w_$id',
      exerciseId: exerciseId,
      setIndex: 1,
      reps: reps,
      completedAtMs: atMs,
      weightKg: weightKg,
      distanceM: distanceM,
    );

final Map<String, String> _names = <String, String>{'bench': '卧推', 'run': '跑步'};
final Map<String, String> _muscles = <String, String>{'bench': 'chest', 'run': 'legs'};

AnnualReport _report({List<SetRecord>? sets}) => buildAnnualReport(
      sets: sets ??
          <SetRecord>[
            _set('a', 'bench', DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 100, reps: 5),
            _set('b', 'bench', DateTime(2026, 3, 1).millisecondsSinceEpoch, weightKg: 90, reps: 10),
          ],
      year: 2026,
      exerciseNames: _names,
      muscleGroups: _muscles,
      timeExercises: const <String>{},
    );

class _FakeExporter implements ShareCardExporter {
  int shares = 0;
  int saves = 0;
  bool needsPermission = false;

  @override
  Future<void> shareToSystem(Uint8List png, {String fileName = 'x'}) async => shares += 1;

  @override
  Future<bool> saveToGallery(Uint8List png, {String fileName = 'x'}) async {
    saves += 1;
    return true;
  }

  @override
  Future<bool> galleryNeedsPermission() async => needsPermission;
}

void main() {
  Future<void> pumpCard(WidgetTester tester, AnnualReport report) async {
    tester.view.physicalSize = const Size(600, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: AnnualReportCard(report: report))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('有数据：数字如实落在卡上（容量/次数/组数/天数/周数/PR/部位）', (WidgetTester tester) async {
    final AnnualReport r = _report();
    await pumpCard(tester, r);

    expect(find.byKey(const Key('annual-volume')), findsOneWidget);
    expect(find.text(r.volumeLabel), findsOneWidget);
    expect(find.text('${r.workoutCount} 次'), findsOneWidget);
    expect(find.text('${r.setCount} 组'), findsOneWidget);
    expect(find.text('${r.trainingDays} 天'), findsOneWidget);
    expect(find.text('${r.attendanceWeeks} 周'), findsOneWidget);
    expect(find.textContaining('卧推'), findsOneWidget);
    expect(find.text('胸'), findsOneWidget);
    expect(find.byKey(const Key('annual-empty')), findsNothing);
  });

  testWidgets('空数据：只写空态，不显示任何统计数字', (WidgetTester tester) async {
    await pumpCard(tester, _report(sets: const <SetRecord>[]));
    expect(find.byKey(const Key('annual-empty')), findsOneWidget);
    expect(find.byKey(const Key('annual-volume')), findsNothing);
    expect(find.byKey(const Key('annual-workouts')), findsNothing);
  });

  testWidgets('只有有氧：不写"总容量 0"，写自重/有氧 + 里程（不编容量）', (WidgetTester tester) async {
    await pumpCard(tester, _report(sets: <SetRecord>[
      _set('r', 'run', DateTime(2026, 2, 1).millisecondsSinceEpoch, reps: 1800, distanceM: 5000),
    ]));
    expect(find.byKey(const Key('annual-volume')), findsNothing);
    expect(find.byKey(const Key('annual-no-volume')), findsOneWidget);
    expect(find.byKey(const Key('annual-distance')), findsOneWidget);
    expect(find.textContaining('5.00 km'), findsOneWidget);
  });

  testWidgets('渲染幂等：同一报告重建两次，文字完全一致', (WidgetTester tester) async {
    final AnnualReport r = _report();
    await pumpCard(tester, r);
    final List<String> first = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '')
        .toList();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: AnnualReportCard(report: r))),
    ));
    await tester.pumpAndSettle();
    final List<String> second = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '')
        .toList();
    expect(second, first);
  });

  testWidgets('屏幕：2.0× 字号不溢出（卡片自身固定缩放，外层可滚）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AnnualReportScreen(
          sets: <SetRecord>[
            _set('a', 'bench', DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 100, reps: 5),
          ],
          exerciseNames: _names,
          muscleGroups: _muscles,
          timeExercises: const <String>{},
          initialYear: 2026,
          now: () => DateTime(2026, 11, 6),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('屏幕：年份切换 + 未来不能翻；空数据禁用分享/存相册', (WidgetTester tester) async {
    final _FakeExporter exporter = _FakeExporter();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AnnualReportScreen(
        sets: <SetRecord>[
          _set('a', 'bench', DateTime(2026, 2, 1).millisecondsSinceEpoch, weightKg: 100, reps: 5),
        ],
        exerciseNames: _names,
        muscleGroups: _muscles,
        timeExercises: const <String>{},
        initialYear: 2026,
        now: () => DateTime(2026, 11, 6),
        exporter: exporter,
        capture: (GlobalKey key) async => Uint8List.fromList(<int>[1, 2, 3]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('annual-year-prev')));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('2026 年度报告'), findsNothing);
    expect(find.text('2025 年度报告'), findsOneWidget);
    await tester.tap(find.byKey(const Key('annual-year-next')));
    await tester.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('annual-share')));
    await tester.pumpAndSettle();
    expect(exporter.shares, 1);
    await tester.tap(find.byKey(const Key('annual-save')));
    await tester.pumpAndSettle();
    expect(exporter.saves, 1);
  });

  testWidgets('屏幕：没有数据时分享/存相册是禁用的', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AnnualReportScreen(
        sets: const <SetRecord>[],
        exerciseNames: _names,
        muscleGroups: _muscles,
        timeExercises: const <String>{},
        initialYear: 2026,
        now: () => DateTime(2026, 11, 6),
      ),
    ));
    await tester.pumpAndSettle();
    final FilledButton share = tester.widget<FilledButton>(find.byKey(const Key('annual-share')));
    expect(share.onPressed, isNull);
    final OutlinedButton save = tester.widget<OutlinedButton>(find.byKey(const Key('annual-save')));
    expect(save.onPressed, isNull);
    expect(find.byKey(const Key('annual-empty')), findsOneWidget);
  });
}
