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
}
