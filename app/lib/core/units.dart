/// 练了么 · 重量单位
///
/// **存储、引擎、埋点一律用 kg**；单位切换只发生在**显示**与**输入**这两层。
///
/// 为什么不做 lb 原生存储：
///   * 引擎的渐进判定建立在"杠铃片网格"上（杠铃 2.5kg / 哑铃 2kg / 器械 5kg，
///     见 `engine/vectors.json` 里的 `linear_progress_*` 向量）。换单位存储会让
///     重量脱离网格，判重、破纪录、加重步长全都要重算，且历史数据要做迁移。
///   * 埋点 `weight_kg` 是跨用户可比的指标，混两种单位就没法看了。
///   * 用户切回 kg 时，历史数据一行都不用改。
///
/// **代价如实记录**：lb 用户的步进会看到 5.5 lb 这种"不整"的增量，
/// 因为底层网格仍是 2.5kg 的杠铃片。要做成 lb 原生步进（+5 lb），
/// 就得让重量脱离网格 —— 那是另一个量级的改动，不该顺手做。
///
/// 这个文件也是全应用**唯一**的重量格式化入口：此前 `_trim` 在六个文件里
/// 各写了一遍，而且间距还不统一（`60kg` 与 `5400 kg` 并存）。
library;

/// 国际磅。用完整精度，避免来回换算累积误差。
const double kLbPerKg = 2.2046226218487757;

enum WeightUnit {
  kg('kg'),
  lb('lb');

  const WeightUnit(this.wire);

  /// 落库用的字符串，与 `user_profile.unit_pref` 一致
  final String wire;

  static WeightUnit fromWire(String? w) => w == 'lb' ? WeightUnit.lb : WeightUnit.kg;
}

/// kg → 用户单位
double toDisplayWeight(double kg, WeightUnit unit) =>
    unit == WeightUnit.kg ? kg : kg * kLbPerKg;

/// 用户输入 → 存储的 kg
double toStoredKg(double value, WeightUnit unit) =>
    unit == WeightUnit.kg ? value : value / kLbPerKg;

/// 去掉多余的 `.0`：`60.0` → `"60"`，`62.5` → `"62.5"`。
String trimNumber(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// 四舍五入到一位小数。换到 lb 之后会出现 `132.277...` 这种值，
/// 不做这一步界面上就是一串没意义的小数。
double round1(double v) => (v * 10).round() / 10;

/// 千分位。五位数一眼能读：`5400` → `"5,400"`。
String withThousands(int v) {
  final String s = v.abs().toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return v < 0 ? '-$b' : b.toString();
}

/// 「60 kg」/「132.3 lb」。[kg] 为 null 时返回 [nullText]。
///
/// 空格是刻意的：全应用统一成「数字 + 空格 + 单位」。
/// 此前组重量写 `60kg`、容量写 `5400 kg`，两种约定并存。
String formatWeight(double? kg, WeightUnit unit, {String nullText = '—'}) {
  if (kg == null) return nullText;
  return '${trimNumber(round1(toDisplayWeight(kg, unit)))} ${unit.wire}';
}

/// 距离（**米**，存储单位）→「5.00 公里」/「800 米」。
///
/// 为什么小于 1 公里时改口说米：跑步机上"0.80 公里"和"800 米"是同一件事，
/// 但后者才是人在器械上会念的说法。阈值放在 1 公里，不为它引入单位设置
/// （距离的显示单位只有这一种约定，不像重量有 kg/lb 的分歧）。
String formatDistanceKm(double meters) {
  if (meters < 1000) return '${trimNumber(round1(meters))} 米';
  return '${(meters / 1000).toStringAsFixed(2)} 公里';
}

/// 秒数 →「30:00」/「1:05:00」。时长动作（有氧）的数字是秒，
/// 但 1800 秒这种念法在跑步机上没人用。
String formatDurationHms(int seconds) {
  final int s = seconds < 0 ? 0 : seconds;
  final int h = s ~/ 3600;
  final int m = (s % 3600) ~/ 60;
  final int sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// 配速「5'30"/公里」。距离或时长为 0 时返回 null（配速没定义，不要拿 0 去除）。
String? formatPace(double meters, int seconds) {
  if (meters <= 0 || seconds <= 0) return null;
  final double secPerKm = seconds / (meters / 1000);
  final int total = secPerKm.round();
  final int m = total ~/ 60;
  final int s = total % 60;
  final String ss = s.toString().padLeft(2, '0');
  return "$m'$ss\"/公里";
}

/// 容量标签，带千分位。`volumeKg <= 0` 时返回 [zeroText]
/// （有的屏要显示「—」，有的是「自重」，所以交给调用方决定）。
String formatVolume(double volumeKg, WeightUnit unit, {String zeroText = '—'}) {
  if (volumeKg <= 0) return zeroText;
  return '${withThousands(toDisplayWeight(volumeKg, unit).round())} ${unit.wire}';
}
