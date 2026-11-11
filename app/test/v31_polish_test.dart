/// v3.1.0 深度打磨回归（task-24）
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/vi_area_chart.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  test('★ 08 图表：顶部 24pt 留白、最大值在左上、末点左右留 6pt',
      () {
    final String src = _src('lib/core/vi_area_chart.dart');
    expect(src.contains('const double topPad = 24'), isTrue);
    expect(src.contains('const double sidePad = 6'), isTrue);
    expect(src.contains('tp.paint(canvas, const Offset(0, 0))'), isTrue,
        reason: 'y 轴最高值在左上，不再压末点');
  });

  test('★ 08 图例只画实际存在的线；sparse 不再同时画线+提示', () {
    final String src = _src('lib/features/progress/progress_screen.dart');
    expect(src.contains('if (hasCompare)'), isTrue);
    expect(src.contains('points: sparse ? const <double>[] : series'), isTrue);
  });

  test('★ 09 全部数据：容量/1RM 合并成一张卡、可切换、3 个 y 刻度', () {
    final String src = _src('lib/features/progress/all_data_screen.dart');
    for (final String k in <String>[
      'all-data-merged-card',
      'all-data-merged-trend',
      'all-data-trend-volume',
      'all-data-trend-1rm',
    ]) {
      expect(src.contains(k), isTrue, reason: '缺 key $k');
    }
    expect(src.contains("_axisLabel('0')"), isTrue);
    expect(src.contains('formatDateAxis(start)'), isTrue);
    expect(src.contains("_trendCard(s.oneRmTrend"), isFalse);
  });

  test('★ 07 总结：分享降为标题行文字按钮，完成键 72', () {
    final String src = _src('lib/features/summary/workout_summary_screen.dart');
    expect(src.contains("key: const Key('summary-share')"), isTrue);
    expect(src.contains('TextButton('), isTrue);
    expect(src.contains('height: 72'), isTrue);
    expect(src.contains('_shareButton('), isFalse);
  });

  test('★ 会话轴：日志默认展开最近一次、用 2px 轴', () {
    final String src = _src('lib/features/progress/progress_screen.dart');
    expect(src.contains('initiallyExpanded: i == 0'), isTrue);
    expect(src.contains("Key('session-set-"), isTrue);
    expect(src.contains('Container(width: Tokens.timelineStroke'), isTrue);
  });

  test('★ 11a 同意页：标题缩短、三句正文、48pt 实心主操作', () {
    final String src = _src('lib/features/body/body_metric_screen.dart');
    expect(src.contains('身体数据要先单独征得同意'), isTrue);
    expect(src.contains("key: Key('body-consent')"), isTrue);
    expect(src.contains('height: 48'), isTrue);
    expect(src.contains("Key('body-consent-agree')"), isTrue);
    expect(src.contains('第 29 条'), isTrue);
  });

  test('★ 训练当前行：组号与重量之间有分隔', () {
    final String src = _src('lib/features/workout/workout_screen.dart');
    expect(src.contains("const Text(' · '"), isTrue);
  });

  testWidgets('ViAreaChart 在 2.0× 下不溢出且能画最大值', (WidgetTester tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: ViAreaChart(
            points: const <double>[0.1, 0.4, 0.2, 0.9],
            yMaxLabel: '6,480 kg',
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
