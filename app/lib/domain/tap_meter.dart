/// 练了么 · tap_count 计量器
///
/// `set_logged.tap_count` 中位数是整个产品"less is more"原则的**唯一客观守卫**，
/// 也是发版闸门（见 docs/analytics.md §3）。它算错，闸门就失效。
///
/// 生命周期规则（与 docs/analytics-sdk.md §3.3 一一对应）：
///   * begin() 在"该组交互开始"时调用（开启新周期，会清零）
///   * ensure() 在控制器构造时调用：**已经在周期里就不动**，
///     用来接住"用户点「开始训练」之后、控制器被造出来之前"那些点击
///   * tap()   只在参与产生这一组数值的输入上调用
///   * flush() 在写 set_logged 之前调用，返回值即 tap_count
///
/// **口径是端到端的**（2026-09-29 修正，见 docs/analytics.md §3）：
/// 从"用户决定练这个动作"到"这一组写入成功"之间的**每一次点击都算** ——
/// 包括开始训练、从动作库选动作、训练屏里切换动作、以及改重量的长按/步进/确定。
///
/// 为什么必须改：窄口径（只看大按钮那一下）会把"用户为了得到这一组实际按了 5 次"
/// 记成 1 次，于是唯一能守住 less is more 的客观闸门会自我满足。
/// 竞争对手（Everlift）公开用的是端到端数字："3 组从约 21 次点按降到 8 次"。
///
/// 仍然**不计入**：休息跳过、Tab 切换、返回、滚动浏览、查看历史 ——
/// 这些不产生这一组的数值，也不是"决定练什么"的动作。
library;

enum TapKind {
  bigButton('big_button'),
  longPress('long_press'),
  stepper('stepper'),
  sheetConfirm('sheet_confirm'),
  keyboard('keyboard'),

  /// 端到端新增：开始一次训练 / 在建议卡上确认「就用这个，开始练」。
  nav('nav'),

  /// 端到端新增：从动作库挑一个动作（「我自己选」那条路）。
  exercisePick('exercise_pick'),

  /// 端到端新增：训练屏里切换动作（点底部条，或左右滑动）。
  ///
  /// 滑动严格说不是"点击"，但它和点一下是**同一个动作意图**、代价也相当，
  /// 而且用户为得到这一组确实多付出了一次操作 —— 所以按 1 次计。
  exerciseSwitch('exercise_switch');

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

  /// 确保周期是开着的，**已经在周期里就什么都不做**（不清零）。
  ///
  /// 端到端口径的关键：导航点击发生在控制器构造**之前**，
  /// 构造函数如果调 `begin()` 就会把它们清零 —— 那等于又回到窄口径。
  void ensure() {
    if (_active) return;
    begin();
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
