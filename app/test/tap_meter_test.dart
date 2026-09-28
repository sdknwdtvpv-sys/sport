/// 练了么 · tap_count 计量器单元测试
///
/// 这些边界对应 `docs/analytics-sdk.md` §3.5。
/// tap_count 算错，发版闸门就失效，所以它是**必须**有测试的一处。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/domain/tap_meter.dart';

void main() {
  group('TapMeter 生命周期', () {
    test('点一次大按钮 → tap_count = 1', () {
      final TapMeter m = TapMeter()..begin();
      m.tap(TapKind.bigButton);
      expect(m.flush().count, 1);
    });

    test('长按 → 步进 → 确定 → 点大按钮 = 4 次', () {
      final TapMeter m = TapMeter()..begin();
      m.tap(TapKind.longPress);
      m.tap(TapKind.stepper);
      m.tap(TapKind.sheetConfirm);
      m.tap(TapKind.bigButton);
      final TapMeterReading r = m.flush();
      expect(r.count, 4);
      expect(r.kinds, <TapKind>[
        TapKind.longPress,
        TapKind.stepper,
        TapKind.sheetConfirm,
        TapKind.bigButton,
      ]);
    });

    test('长按 → 确定 → 点大按钮 = 3 次（未调步进）', () {
      final TapMeter m = TapMeter()..begin();
      m.tap(TapKind.longPress);
      m.tap(TapKind.sheetConfirm);
      m.tap(TapKind.bigButton);
      expect(m.flush().count, 3);
    });

    test('连点两次是两个独立周期，各自 tap_count = 1', () {
      final TapMeter m = TapMeter();
      m.begin();
      m.tap(TapKind.bigButton);
      expect(m.flush().count, 1);
      m.begin();
      m.tap(TapKind.bigButton);
      expect(m.flush().count, 1);
    });

    test('flush 后计数清零且不再接受点击，直到下一次 begin', () {
      final TapMeter m = TapMeter()..begin();
      m.tap(TapKind.bigButton);
      m.flush();
      m.tap(TapKind.stepper); // 周期外的点击必须被忽略
      expect(m.pending, 0);
      expect(m.isActive, isFalse);
      m.begin();
      m.tap(TapKind.stepper);
      expect(m.pending, 1);
    });

    test('begin 会重置未 flush 的计数（开启新周期）', () {
      final TapMeter m = TapMeter()..begin();
      m.tap(TapKind.stepper);
      m.tap(TapKind.stepper);
      m.begin();
      expect(m.pending, 0);
    });
  });

  group('端到端口径：ensure 不清零', () {
    test('ensure 在周期没开时开一个（直接 new 出控制器的那条路）', () {
      final TapMeter m = TapMeter();
      m.ensure();
      expect(m.isActive, isTrue);
      m.tap(TapKind.bigButton);
      expect(m.flush().count, 1);
    });

    test('ensure 在周期已开时什么都不做 —— 导航点击必须活着', () {
      final TapMeter m = TapMeter();
      // 真实顺序：用户点「开始训练」→ 建议卡确认 → 控制器才被构造
      m.begin();
      m.tap(TapKind.nav);
      m.tap(TapKind.nav);

      m.ensure(); // 控制器构造函数里那一下：绝不能清零

      m.tap(TapKind.bigButton);
      final TapMeterReading r = m.flush();
      expect(r.count, 3, reason: '今日页 → 建议卡 → 大按钮 = 3 次，这是端到端数字');
      expect(r.kinds, <TapKind>[TapKind.nav, TapKind.nav, TapKind.bigButton]);
    });

    test('next 的 begin 仍然清零（下一组是独立周期）', () {
      final TapMeter m = TapMeter();
      m.begin();
      m.tap(TapKind.nav);
      m.ensure();
      m.tap(TapKind.bigButton);
      expect(m.flush().count, 2);

      m.begin(); // 记录完一组后开启下一组
      m.ensure();
      m.tap(TapKind.bigButton);
      expect(m.flush().count, 1, reason: '上一组的导航点击不能算到下一组头上');
    });

    test('切换动作与选动作都是独立的点击类型', () {
      final TapMeter m = TapMeter()..begin();
      m.tap(TapKind.exercisePick);
      m.tap(TapKind.exerciseSwitch);
      m.tap(TapKind.stepper);
      m.tap(TapKind.bigButton);
      final TapMeterReading r = m.flush();
      expect(r.count, 4);
      expect(r.kinds.map((TapKind k) => k.wire).toList(),
          <String>['exercise_pick', 'exercise_switch', 'stepper', 'big_button'],
          reason: 'tap_kinds 要能回答"这些点击花在哪了"');
    });
  });
}
