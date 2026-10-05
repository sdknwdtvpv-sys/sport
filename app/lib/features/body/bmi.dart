/// 练了么 · **BMI 与身体数据的展示口径**（2026-10-05，v1.52）
///
/// 三条规矩，逐条都有理由：
///
///   1. **没填身高就不算 BMI**（返回 null）—— 拿一个默认身高去编一个数出来，
///      比不显示更糟：用户会拿它当自己的数看。
///   2. **分档用中国标准**（《中国成人超重和肥胖症预防控制指南》：
///      <18.5 偏瘦 / 18.5–23.9 正常 / 24–27.9 超重 / ≥28 肥胖），
///      而不是 WHO 那套 25/30 —— 同一串数字在两套标准下结论不同，
///      用哪套要写出来，不能含糊。
///   3. **BMI 只是参考**：肌肉量大的人 BMI 也会偏高。所以文案里带一句提醒，
///      不把它说成"健康结论"。
library;

/// BMI = 体重(kg) ÷ 身高(m)²。
///
/// 缺任一项、或身高不合理（≤0 / >250）时返回 null —— **宁可没有，也不给一个假数**。
double? bmiOf({double? weightKg, double? heightCm}) {
  if (weightKg == null || heightCm == null) return null;
  if (weightKg <= 0 || heightCm <= 0 || heightCm > 250) return null;
  final double m = heightCm / 100;
  return weightKg / (m * m);
}

/// 一位小数（界面上的念法）。
String bmiText(double? bmi) => bmi == null ? '—' : bmi.toStringAsFixed(1);

/// 中国标准的分档名。null → 没有 BMI（界面显示「—」）。
String bmiBand(double? bmi) {
  if (bmi == null) return '—';
  if (bmi < 18.5) return '偏瘦';
  if (bmi < 24) return '正常';
  if (bmi < 28) return '超重';
  return '肥胖';
}

/// 给用户看的一句提醒（只在真的算出来 BMI 时才说）。
String bmiHint(double? bmi) =>
    bmi == null ? '填上身高就能算 BMI（只存在本机）' : 'BMI 只是参考：肌肉量大的人也会偏高';
