/// 练了么 · **动效令牌本身对不对**（VI 计划 T1-4）
///
/// 这一组测的是**数字**，不是"能不能动"：
///   * 峰值过冲必须真的是 **9.8%**（那是 `vi-proposal-d` 里算出来的值，不能"差不多"）；
///   * **出场比入场快**（0.7 倍）—— 一条很容易被后来者改反的纪律；
///   * 默认曲线在 0.5 处的位置要落在它该在的区间（否则"同一条曲线"其实换了个手感）。
library;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/motion.dart';

void main() {
  test('★ 曲线控制点与规范一致', () {
    // `Motion.standard` = (0.0, 0.55, 0.45, 1.0)：中点应该已经走过一半以上（前段"给力"）
    final double mid = Motion.standard.transform(0.5);
    expect(mid, greaterThan(0.5), reason: 'standard 的前段要比线性更给力');
    expect(mid, lessThan(0.95), reason: '但不能一步到位（那就成了瞬移）');

    // 入场比 default 更快"到位"（`enter` 的 y1 = 1.0，前段给力）——
    // 它的"缓"在 **x** 轴上（x1 = 0.16 而不是 0.22）：起步那一下更柔，
    // 但一旦动起来就迅速贴到终值。
    expect(Motion.enter.transform(0.5), greaterThan(Motion.standard.transform(0.5)));

    // 出场等价于 Curves.easeIn
    expect(Motion.exit.transform(0.5), closeTo(Curves.easeIn.transform(0.5), 1e-9));
  });

  test('★ `arrival` 的峰值过冲 = 9.8% ± 0.5%', () {
    // 把 `vi-proposal-d` 里算出来的 1.0978 钉死 —— "到达"类动画的全部性格就在这个数上。
    double peak = 0;
    for (int i = 0; i <= 1000; i++) {
      final double v = Motion.arrival.transform(i / 1000);
      if (v > peak) peak = v;
    }
    expect(peak, closeTo(1.0978, 0.005),
        reason: '峰值 ${peak.toStringAsFixed(4)} —— 过冲变了，手感就变了');
  });

  test('★ 出场比入场快：`fast` = 0.7 × `base`（这条纪律要能跑）', () {
    // 出场比入场慢 = 页面在"赖着不走"。
    // ⚠️ 容差 3ms：计划给的就是 260 / 180 = 0.69（不是精确的 0.70）——
    // 拿 1ms 容差去卡它，只会让下一个人去改时长来迁就测试。
    expect(Motion.fast.inMilliseconds,
        closeTo(Motion.base.inMilliseconds * 0.7, 3));
    expect(Motion.exit, isNotNull, reason: '出场曲线必须存在（不许用入场的曲线）');
  });

  test('★ 五档时长是单调递增的，且都 > 0', () {
    final List<int> ms = <int>[
      Motion.instant.inMilliseconds,
      Motion.fast.inMilliseconds,
      Motion.base.inMilliseconds,
      Motion.slow.inMilliseconds,
      Motion.celebrate.inMilliseconds,
    ];
    for (int i = 1; i < ms.length; i++) {
      expect(ms[i], greaterThan(ms[i - 1]), reason: '档位必须单调：$ms');
    }
    // 三个专用值也钉住（它们是"编排的节拍"，不是第六档）
    expect(Motion.restTick.inMilliseconds, 1000);
    expect(Motion.pageTransition.inMilliseconds, 300);
    // T2-3 的完成页时间轴：切分点（420/700/1020/1200）都按它算，改了要让所有图重新对一遍
    expect(Motion.summaryTimeline.inMilliseconds, 1400);
    expect(Motion.summaryTimelineMs, Motion.summaryTimeline.inMilliseconds);
    // T3-6 的内启动屏：环的呼吸周期（与稿子的 ringPulse 2.5s 对齐）
    expect(Motion.splashPulse.inMilliseconds, 2500);
    // 页面转场比默认档长（跨屏 vs 同屏）
    expect(Motion.pageTransition.inMilliseconds,
        greaterThan(Motion.base.inMilliseconds));
  });
}
