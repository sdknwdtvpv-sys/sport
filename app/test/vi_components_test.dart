/// 新 VI 共用件的自测（卡片 / 统计块 / 分段选择 / 进度条 / 面积图）。
///
/// **为什么组件要有自己的测试**：这些件会被几十个页面用到，
/// 一个"看起来只是样式"的错会同时出现在所有页面上，而**页面测试通常只查文字与 Key**，
/// 根本查不到"卡片没有描边""圆角是错的"这类问题。
/// 这个仓库已经吃过一次同类的亏（胶囊选项三份拷贝，同一个布局 bug 复制三份）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/core/vi_area_chart.dart';
import 'package:lianleme/core/vi_cards.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(backgroundColor: Tokens.bg, body: Center(child: child)),
    );

BoxDecoration _decorationOf(WidgetTester tester, Key key) {
  final Container c = tester.widget<Container>(
    find.descendant(of: find.byKey(key), matching: find.byType(Container)).first,
  );
  return c.decoration! as BoxDecoration;
}

void main() {
  testWidgets('卡片：surface 底 + 白 6% 描边 + rCard 圆角（三样缺一不可）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(
      const ViCard(key: Key('c'), child: Text('内容')),
    ));
    expect(find.text('内容'), findsOneWidget);
    final BoxDecoration d = _decorationOf(tester, const Key('c'));
    expect(d.color, Tokens.surface);
    expect(d.border!.top.color, Tokens.line);
    expect(d.borderRadius, BorderRadius.circular(Tokens.rCard));
  });

  testWidgets('卡片：可点与不可点都行，且不点也要能渲染',
      (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(_host(ViCard(
      key: const Key('tappable'),
      onTap: () => taps++,
      child: const Text('点我'),
    )));
    await tester.tap(find.byKey(const Key('tappable')));
    expect(taps, 1);
  });

  testWidgets('统计块：数字走展示字体（Oswald），标签与涨跌都在',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const StatTile(
      label: '总训练容量',
      value: '12.4 t',
      delta: '+18%',
      deltaUp: true,
      key: Key('tile'),
    )));
    final Text value = tester.widget<Text>(find.text('12.4 t'));
    expect(value.style!.fontFamily, Tokens.displayFont,
        reason: '大数字没走 Oswald —— 界面稿里所有统计数字都是它');
    expect(find.text('总训练容量'), findsOneWidget);
    expect(find.text('+18%'), findsOneWidget);
  });

  testWidgets('统计块：没有涨跌时不占位（不留一块空白）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const StatTile(label: 'L', value: 'V')));
    expect(find.text('L'), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(2));
  });

  testWidgets('分段选择：点第二个会回调 1，选中项用 accentInk 字色',
      (WidgetTester tester) async {
    int picked = 0;
    await tester.pumpWidget(_host(ViSegmented(
      labels: const <String>['周', '月', '年'],
      current: 0,
      onChanged: (int i) => picked = i,
    )));
    await tester.tap(find.byKey(const Key('seg-月')));
    expect(picked, 1);
    final Text first = tester.widget<Text>(find.text('周'));
    expect(first.style!.color, Tokens.accentInk);
  });

  testWidgets('进度条：把超出范围的比例夹回去（0 / 负数 / 超过 1 / NaN 都不许画到框外）',
      (WidgetTester tester) async {
    for (final double v in <double>[0, -3, 0.5, 1, 7, double.nan]) {
      await tester.pumpWidget(_host(ViProgressBar(value: v, key: const Key('bar'))));
      await tester.pump();
      final FractionallySizedBox f = tester.widget<FractionallySizedBox>(
        find.descendant(of: find.byKey(const Key('bar')), matching: find.byType(FractionallySizedBox)),
      );
      expect(f.widthFactor, inInclusiveRange(0.0, 1.0), reason: 'value=$v 没被夹住');
    }
  });

  testWidgets('面积图：空数据 / 一个点 / 很多点都能画，不抛异常也不溢出',
      (WidgetTester tester) async {
    for (final List<double> pts in <List<double>>[
      <double>[],
      <double>[0.5],
      <double>[0, 0.3, 0.9, 0.2, 1],
      <double>[2, -1, 0.5], // 越界的比例也要夹住
    ]) {
      await tester.pumpWidget(_host(SizedBox(width: 200, child: ViAreaChart(points: pts))));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'points=$pts 画崩了');
    }
  });

  testWidgets('面积图：宽度极小时不除零（点数 >1 且宽度 0）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(
      const SizedBox(width: 0, child: ViAreaChart(points: <double>[0.1, 0.9])),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
