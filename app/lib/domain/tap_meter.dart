/// 练了么 · tap_count 计量器
///
/// `set_logged.tap_count` 中位数是整个产品"less is more"原则的**唯一客观守卫**，
/// 也是发版闸门（见 docs/analytics.md §3）。它算错，闸门就失效。
///
/// 生命周期规则（与 docs/analytics-sdk.md §3.3 一一对应）：
///   * begin() 在"该组交互开始"时调用：进入训练主屏、动作切换后、以及每记录完一组之后
///   * tap()   只在参与产生这一组数值的输入上调用
///   * flush() 在写 set_logged 之前调用，返回值即 tap_count
///
/// 明确**不计入**：休息跳过、动作切换、Tab 切换、返回、滚动浏览、查看历史。
library;

enum TapKind {
  bigButton('big_button'),
  longPress('long_press'),
  stepper('stepper'),
  sheetConfirm('sheet_confirm'),
  keyboard('keyboard');

  const TapKind(this.wire);
  final String wire;
}

class TapMeterReading {
  const TapMeterReading(this.count, this.kinds);
  final int count;
  final List<TapKind> kinds;
}

class TapMeter {
  int _count = 0;
  bool _active = false;
  final List<TapKind> _kinds = <TapKind>[];

  bool get isActive => _active;
  int get pending => _count;

  /// 开启一个新的交互周期。重复调用会重置计数 ——
  /// 「点大按钮记录后立刻再点一次」必须是两个独立周期，各自 tap_count = 1。
  void begin() {
    _count = 0;
    _kinds.clear();
    _active = true;
  }

  void tap(TapKind kind) {
    if (!_active) return; // 不在交互周期内的点击一律忽略
    _count++;
    _kinds.add(kind);
  }

  TapMeterReading flush() {
    final reading = TapMeterReading(_count, List<TapKind>.unmodifiable(_kinds));
    _count = 0;
    _kinds.clear();
    _active = false;
    return reading;
  }
}
