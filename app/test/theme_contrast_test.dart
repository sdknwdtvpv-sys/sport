/// 练了么 · **对比度守卫**（VI 计划 T0-2 / T0-3 / T0-4，2026-10-10）
///
/// **为什么要有它**：`docs/interaction-spec.md` §9 写着「`--text-3` 仅用于非关键信息，
/// 且 ≥ 4.5:1」，而真值 `#6B6157` 在 `surface` 上只有 **2.95:1** —— 规格与实现互相打脸，
/// 而且**没有任何机械检查会红**。颜色漂移不会报错、不会崩，只会让用户在暗光健身房里读不清。
///
/// 这个文件干两件事：
///   1. **算**：按 WCAG 2.x 的相对亮度公式，把关键组合的对比度算出来并钉住下限；
///   2. **扫**：在**真实的界面树**上找 `text3` 的 `Text`，往上找它最近的一层底色，
///      断言只落在白名单（`bg` / `surface`）上 —— 因为 `text3` 对新值在 `elevated` 上只有 4.22:1。
///
/// ⚠️ 扫描是**采样**而不是全量：它只能扫到"被 pump 出来的那几屏"。
/// 所以下面显式列了样本，并且有一条"样本里必须真的扫到 text3"的反向断言 ——
/// **一个从来没扫到东西的扫描器是假的守卫**。
library;

import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';
import 'package:lianleme/features/today/today_planner.dart';
import 'package:lianleme/features/today/today_screen.dart';

/// WCAG 2.x 相对亮度。
double _luminance(Color c) {
  double ch(double v) {
    final double s = v;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// 两色对比度（1:1 ～ 21:1）。
double contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// `text3` 只许压在这两层上（`elevated` 上只有 4.22:1，不合格）。
///
/// ⚠️ 用 `List<int>`（ARGB32 整数）而不是 `Set<Color>`：`Color` 在 dart:ui 里
/// **没有原始相等性**，放进 `const Set` 会被分析器拒掉。
const List<int> _allowedUnderText3 = <int>[0xFF0E0C0A, 0xFF1A1714];

/// 在元素树里往上找**最近的一层不透明底色**。找不到就返回 null（= 继承页面底色 `bg`）。
Color? _nearestBackground(Element element) {
  Color? found;
  element.visitAncestorElements((Element a) {
    final Widget w = a.widget;
    if (w is Container) {
      final Decoration? d = w.decoration;
      if (d is BoxDecoration && d.color != null && d.color!.a > 0) {
        found = d.color;
        return false;
      }
      if (w.color != null && w.color!.a > 0) {
        found = w.color;
        return false;
      }
    } else if (w is ColoredBox && w.color.a > 0) {
      found = w.color;
      return false;
    } else if (w is Material && w.color != null && w.color!.a > 0) {
      found = w.color;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  group('对比度（WCAG 2.x，按 hex 实算）', () {
    test('★ text3 对 bg 与 surface 都 ≥ 4.5:1', () {
      // 这就是 T0-3 的全部理由：规格 §9 承诺 4.5:1，旧值只有 2.95:1。
      expect(contrast(Tokens.text3, Tokens.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(Tokens.text3, Tokens.surface), greaterThanOrEqualTo(4.5));
      // 顺带把另外两级也钉住（它们是正文，必须更高）
      expect(contrast(Tokens.text2, Tokens.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(Tokens.text, Tokens.bg), greaterThanOrEqualTo(7.0));
    });

    test('★ 橙底上的字只许是 accentInk（§4 硬约束）', () {
      expect(contrast(Tokens.accentInk, Tokens.accent), greaterThanOrEqualTo(4.5));
      // 白字是**永久禁止**的那一种：写进测试，免得有人从 `vi/` 里把白胶囊搬进代码
      expect(contrast(const Color(0xFFFFFFFF), Tokens.accent), lessThan(4.5),
          reason: '橙底白字只有 3.08:1 —— 这条不是"建议"，是硬约束');
    });
  });

  group('text3 只许落在 bg / surface 上（真实界面树扫描）', () {
    late AppDatabase db;
    late ExerciseRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = ExerciseRepository(db);
      await repo.importSeed(loadJson: () async => '{"exercises":[]}');
    });
    tearDown(() => db.close());

    /// 扫一屏：返回 (扫到的 text3 个数, 违规的说明列表)。
    ({int found, List<String> bad}) scan(WidgetTester tester) {
      int found = 0;
      final List<String> bad = <String>[];
      for (final Element e in find.byType(Text).evaluate()) {
        final Text t = e.widget as Text;
        final Color? c = t.style?.color;
        if (c != Tokens.text3) continue;
        found++;
        final Color? bg = _nearestBackground(e);
        if (bg != null && !_allowedUnderText3.contains(bg.toARGB32())) {
          bad.add('「${t.data}」压在 ${bg.toARGB32().toRadixString(16)} 上 '
              '（对比度 ${contrast(Tokens.text3, bg).toStringAsFixed(2)}:1）');
        }
      }
      return (found: found, bad: bad);
    }

    testWidgets('选动作页：扫到 text3 且全部落在合法底色上', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ExercisePickerScreen(repository: repo),
      ));
      await tester.pumpAndSettle();
      final ({int found, List<String> bad}) r = scan(tester);
      expect(r.bad, isEmpty, reason: 'text3 落在 elevated/更亮的层上：${r.bad.join('；')}');
      expect(r.found, greaterThan(0),
          reason: '这一屏一个 text3 都没扫到 —— 那这条守卫什么也没守住（样本失效了）');
    });

    testWidgets('★ 反向自检：把 text3 放进 elevated 卡片里，扫描器必须抓到', (WidgetTester tester) async {
      // **一个从来没红过的守卫是不可信的** —— 这条就是让上面那个扫描器"红一次"。
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Tokens.bg,
          body: Container(
            color: Tokens.elevated,
            child: const Text('灰字', style: TextStyle(color: Tokens.text3)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final ({int found, List<String> bad}) r = scan(tester);
      expect(r.found, 1);
      expect(r.bad, isNotEmpty,
          reason: 'elevated 上 text3 只有 4.22:1 —— 扫描器必须抓到这一种');
    });

    testWidgets('首页：扫到 text3 且全部落在合法底色上', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Tokens.bg,
          body: TodayScreen(
            onStart: () {},
            streak: 3,
            weeklyFact: '本周已练 1 次',
            todayPlan: <PlannedExercise>[
              PlannedExercise(
                exercise: ExerciseData(
                  id: 'ex_bench',
                  name: '杠铃卧推',
                  aliases: '[]',
                  muscleGroup: 'chest',
                  secondaryMuscles: '[]',
                  subTags: '[]',
                  equipment: 'barbell',
                  category: 'strength',
                  trackType: 'weight_reps',
                  defaultRestSec: 90,
                  weightIncrement: 2.5,
                  isBuiltin: true,
                  popularity: 100,
                  createdAt: 0,
                  updatedAt: 0,
                ),
                plan: const PlanTarget(
                    targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final ({int found, List<String> bad}) r = scan(tester);
      expect(r.bad, isEmpty, reason: 'text3 落在 elevated/更亮的层上：${r.bad.join('；')}');
      expect(r.found, greaterThan(0), reason: '这一屏一个 text3 都没扫到 —— 样本失效了');
    });
  });
}
