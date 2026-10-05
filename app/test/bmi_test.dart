/// BMI 的口径自测（v1.52）。
///
/// 这一层是纯函数，但它是"给用户看的那个数"的唯一出处 ——
/// 算错了不会崩、不会红，只会**静默地把一个错的数字摆在体重旁边**。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/features/body/bmi.dart';

void main() {
  test('正常算：70 kg / 175 cm → 22.9', () {
    final double? bmi = bmiOf(weightKg: 70, heightCm: 175);
    expect(bmi, isNotNull);
    expect(bmi!.toStringAsFixed(1), '22.9');
  });

  test('缺任一项就是 null（**不拿默认身高编一个数**）', () {
    expect(bmiOf(weightKg: 70, heightCm: null), isNull);
    expect(bmiOf(weightKg: null, heightCm: 175), isNull);
    expect(bmiOf(weightKg: null, heightCm: null), isNull);
  });

  test('离谱的输入也是 null（0 / 负数 / 身高 3 米）', () {
    expect(bmiOf(weightKg: 0, heightCm: 175), isNull);
    expect(bmiOf(weightKg: -5, heightCm: 175), isNull);
    expect(bmiOf(weightKg: 70, heightCm: 0), isNull);
    expect(bmiOf(weightKg: 70, heightCm: 300), isNull);
  });

  test('分档用**中国标准**（18.5 / 24 / 28 三条线，边界属于上一档之上的那一档）', () {
    // 用一组刚好落在边界两侧的身高体重造 BMI
    double bmiAt(double weight, double height) => bmiOf(weightKg: weight, heightCm: height)!;

    expect(bmiBand(bmiAt(50, 170)), '偏瘦');   // 17.3
    expect(bmiBand(bmiAt(55, 170)), '正常');   // 19.0
    expect(bmiBand(bmiAt(72, 170)), '超重');   // 24.9
    expect(bmiBand(bmiAt(85, 170)), '肥胖');   // 29.4

    // 边界值本身
    expect(bmiBand(18.49), '偏瘦');
    expect(bmiBand(18.5), '正常');
    expect(bmiBand(23.99), '正常');
    expect(bmiBand(24), '超重');
    expect(bmiBand(27.99), '超重');
    expect(bmiBand(28), '肥胖');
  });

  test('没有 BMI 时：显示「—」，提示写的是"填身高就能算"（不说分数）', () {
    expect(bmiText(null), '—');
    expect(bmiBand(null), '—');
    expect(bmiHint(null), contains('身高'));
    expect(bmiHint(null), isNot(contains('肌肉量')));
  });

  test('算出来时：带一位小数，并提醒"肌肉量大的人也会偏高"（不把它说成健康结论）', () {
    expect(bmiText(22.94), '22.9');
    expect(bmiHint(22.9), contains('参考'));
  });
}
