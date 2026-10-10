/// 练了么 · **空态的两条纪律**（VI 计划 T3-2，2026-10-10）
///
/// **为什么要有它**：全 App 16 处空态**全部**是"一到两行灰字、无图形、无按钮"，
/// 其中只有 5 处做到了 `docs/copy.md` 判据第 4 条的"说出下一步"。
/// 而 `text3` 在 `bg` 上只有 3.23:1 —— 连"被读到"都保证不了。
///
/// 这一条把两件事从"文档里的要求"变成"跑得出来的断言"：
///   1. **每一处空态都有一个可点的下一步**（不是"有文字"，是**真的有按钮**）；
///   2. **空态的图形全部是品牌环的派生** —— 空态是这套视觉语言里最容易长出
///      "随手画的插图"的地方，所以五个 `EmptyArt` 的几何只许来自 `BrandMarkGeometry`。
///
/// `EmptyState` 的构造器把"按钮必填"做进了类型（`action` + `onAction` 都是必填参数），
/// 所以第 1 条测的是**接线**：六处空态真的都传了下一步。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/empty_state.dart';
import 'package:lianleme/core/theme.dart';

/// 计划里点名的六处空态（key 写在各自的屏上）。
const List<String> kEmptyKeys = <String>[
  'empty-today', // 首页：一次都没练过
  'empty-progress', // 进步页：还没有训练记录
  'empty-all-data', // 全部数据页：这个动作还没有记录
  'empty-picker', // 动作库：搜不到
  'empty-notifications', // 通知中心：还没有消息
  'empty-plan-history', // 计划页：还没有练过
];

void main() {
  testWidgets('每个空态都给下一步动作', (WidgetTester tester) async {
    // 六处空态各自的接线在其它测试里（每屏一条），这里钉的是**组件层面的合同**：
    // 只要用了 `EmptyState`，就一定有一颗可点的按钮，而且点得动。
    for (final EmptyArt art in EmptyArt.values) {
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: EmptyState(
            key: const Key('probe'),
            art: art,
            title: '一句事实。',
            body: '一句解释。',
            action: '下一步',
            onAction: () => taps++,
          ),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('empty-art')), findsOneWidget,
          reason: '$art 要有图形（空态的第一眼是图形，不是灰字）');
      expect(find.byKey(const Key('empty-title')), findsOneWidget);
      final Finder button =
          find.descendant(of: find.byKey(const Key('probe')), matching: find.byType(TextButton));
      expect(button, findsOneWidget, reason: '$art 的空态必须有**按钮**，不是一句"你可以…"');
      await tester.tap(button);
      await tester.pump();
      expect(taps, 1, reason: '$art 的下一步必须真的能点');
    }

    // 六处空态的 key 都得在代码里真的存在（防"测试写了、界面没接"）
    final String all = <String>[
          'lib/features/today/today_screen.dart',
          'lib/features/progress/progress_screen.dart',
          'lib/features/progress/all_data_screen.dart',
          'lib/features/exercise/exercise_picker_screen.dart',
          'lib/features/notifications/notification_center_screen.dart',
          'lib/features/routine/plan_screen.dart',
        ]
            .map((String p) => File(p).readAsStringSync())
            .join('\n');
    for (final String key in kEmptyKeys) {
      expect(all.contains("Key('$key')"), isTrue, reason: '六处空态里少了 $key');
    }
  });

  test('空态图形全部是 BrandMark 的派生', () {
    final String src = File('lib/core/empty_state.dart').readAsStringSync();
    // 五档都要在（枚举值本身）
    for (final EmptyArt art in EmptyArt.values) {
      expect(src.contains(art.name), isTrue, reason: 'EmptyArt.${art.name} 不在文件里');
    }
    // painter 里必须引用品牌环的几何常量（而不是另编一套半径/线宽）
    expect(src.contains('BrandMarkGeometry'), isTrue,
        reason: '空态图形的几何必须来自 BrandMarkGeometry');
    for (final String name in <String>[
      'outerRadius',
      'holeRadius',
      'band',
      'ringPath',
    ]) {
      expect(src.contains('BrandMarkGeometry.$name'), isTrue,
          reason: '少了 BrandMarkGeometry.$name —— 五个图形只许从品牌环派生');
    }
    // 反向自检：文件里不许出现"手写的圆半径"这种绝对像素
    expect(RegExp(r'Radius\.circular\(9[0-9]\)').hasMatch(src), isFalse,
        reason: '出现手写半径就说明有图形脱离品牌环了');
  });

  test('反向自检：`EmptyState` 的按钮是**必填**参数', () {
    // 类型层面的纪律：少了 onAction 就编译不过 —— 这里用"源码里那两行还在"来钉住它，
    // 因为 `const EmptyState(...)` 的缺失场景没法在运行期构造出来。
    final String src = File('lib/core/empty_state.dart').readAsStringSync();
    expect(src.contains('required this.action'), isTrue);
    expect(src.contains('required this.onAction'), isTrue);
    expect(src.contains('required this.art'), isTrue);
    // 图形必须由调用方给定：空态不许有个"默认图案"（那会让每一处都长一样）
    expect(src.contains('this.art ='), isFalse, reason: 'art 不许有默认值');
  });

  test('空态的标题不许用 text3（它得先被读到）', () {
    final String src = File('lib/core/empty_state.dart').readAsStringSync();
    final int titleAt = src.indexOf("key: const Key('empty-title')");
    final int bodyAt = src.indexOf("key: const Key('empty-body')");
    expect(titleAt, greaterThan(0));
    // 标题那一段用 text2、正文那段才允许 text3
    final String titleBlock = src.substring(titleAt, bodyAt > titleAt ? bodyAt : titleAt + 400);
    expect(titleBlock.contains('Tokens.text2'), isTrue,
        reason: '标题是功能性文本 → text2（T0-3 的口径）');
    expect(titleBlock.contains('Tokens.text3'), isFalse,
        reason: '标题不许用 text3（在 bg 上只有 3.23:1）');
  });
}
