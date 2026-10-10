/// 练了么 · **只在 debug 构建里存在**的会员假开关（M1）
///
/// 为什么需要它：M1 要先把界面走查一遍（会员页、被锁处、降级态），
/// 而真内购在 M2 —— 没有它，M1 的所有界面都只能看到"未开通"那一种样子。
///
/// ⚠️ **它必须不可能出现在 release 包里**，这不是洁癖：
///   * Apple 3.1.1 与 2.3.1 都把"审核时把付费藏起来、过审后打开"当违规，
///     一个"能解锁会员的开关"留在正式包里，是解释不清的；
///   * 这个仓库已经有同一个做法的先例：`workout_screen.dart` 里那两个
///     `debugWorkoutScreenBuilds` / `debugRestStripBuilds`（`assert` 包住递增 →
///     release 里那两行不存在）。
///
/// 做法：**读和写都包在 `assert` 里** ——
///   * release 构建里 `assert` 的实参不求值，所以 `_granted` 永远是 `false`，
///     [debugUltraGranted] 恒为 `false`、[debugSetUltraGranted] 是空操作；
///   * 于是即使有人反编译正式包，也找不到"打开会员"的那条路（它根本不在）。
///
/// 判据：`app/test/entitlement_test.dart` 里有一条**扫源码**的测试 ——
/// `debugSetUltraGranted` 的调用点必须都在 `assert(...)` 之内。
library;

bool _granted = false;

/// 只在 debug 构建里可能为 true。
bool get debugUltraGranted {
  bool v = false;
  assert(() {
    v = _granted;
    return true;
  }());
  return v;
}

/// 设置假开关（release 里是空操作）。
void debugSetUltraGranted(bool value) {
  assert(() {
    _granted = value;
    return true;
  }());
}
