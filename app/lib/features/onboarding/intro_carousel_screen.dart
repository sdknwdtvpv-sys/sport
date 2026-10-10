/// 练了么 · **首启引导（3 屏卖点轮播）** —— v1.49
///
/// 用户 2026-10-05 拍板要做，并给了**四条约束**（这一条是产品决定，不是我的自由发挥）：
///   1. **只在全新安装出现一次**；
///   2. **每屏可跳过**；
///   3. **放在同意门之后**；
///   4. 最后一屏的按钮是**「开始第一次训练」**，不是「完成」。
///
/// ⚠️ 满足第 1 条**不需要新增任何"看过没"的落库标记**：同意门本身就是
/// "每次安装只出现一次"的那个标记 —— 顾客同意过之后，冷启动再也不会走到这一屏。
/// 少一个字段就少一处会漂的真相（这个仓库的规矩）。
///
/// ⚠️ 第 4 条是刻意的：引导页常见的收尾是「完成」——那是个**终点**，
/// 而这里此刻唯一该发生的事是"开始第一次训练"。所以末屏按钮直接开练。
library;

import '../../core/icon_spec.dart';
import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';

/// 一屏的内容（三屏都是"图 + 标题 + 一句话"）。
class _Slide {
  const _Slide({required this.title, required this.body, required this.art});

  final String title;
  final String body;

  /// 插图。**全是自绘的 widget**，没有图片资源 —— 与整个项目一致
  /// （图标/截图之外的图片一律不进包）。
  final Widget art;
}

class IntroCarouselScreen extends StatefulWidget {
  const IntroCarouselScreen({
    super.key,
    required this.onSkip,
    required this.onStartFirst,
  });

  /// 「跳过」：不开始训练，直接进主界面。
  final VoidCallback onSkip;

  /// 末屏按钮：**开始第一次训练**。
  final VoidCallback onStartFirst;

  @override
  State<IntroCarouselScreen> createState() => _IntroCarouselScreenState();
}

class _IntroCarouselScreenState extends State<IntroCarouselScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  static const List<_Slide> _slides = <_Slide>[
    _Slide(
      title: '一次点击\n记录一组',
      body: '不用选动作、不用填重量，打开就能记。把记录成本压到最低，专注训练本身。',
      art: _TapArt(),
    ),
    _Slide(
      title: '今天练什么\n不用你想',
      body: '根据你的训练历史和进度，自动生成下一阶段计划。双重渐进，科学加量。',
      art: _PlanArt(),
    ),
    _Slide(
      title: '看得见的进步\n才是动力',
      body: '自动追踪力量、容量与纪录。数据不会说谎，每一次进步都被记录。',
      art: _ProgressArt(),
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool last = _index == _slides.length - 1;
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 跳过：**每一屏都在**（约束 2）
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('intro-skip'),
                onPressed: widget.onSkip,
                child: const Text('跳过', style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext context, int i) => _page(_slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s6, Tokens.s4, Tokens.s6, Tokens.s6),
              child: Row(
                children: <Widget>[
                  // 圆点：当前位置一眼可见
                  for (int i = 0; i < _slides.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        key: Key('intro-dot-$i'),
                        width: i == _index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _index ? Tokens.accent : Tokens.elevated,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  const Spacer(),
                  // 末屏换成整颗「开始第一次训练」（约束 4）
                  if (last)
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: const Key('intro-start'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Tokens.accent,
                          foregroundColor: Tokens.accentInk,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Tokens.rPill),
                          ),
                        ),
                        onPressed: widget.onStartFirst,
                        child: const Text('开始第一次训练',
                            style: TextStyle(fontSize: Tokens.fsBodyS, fontWeight: Tokens.fwBold)),
                      ),
                    )
                  else
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: FilledButton(
                        key: const Key('intro-next'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Tokens.accent,
                          foregroundColor: Tokens.accentInk,
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        // 动效只从 `Motion` 取值（VI 计划 T1-4）——
                        // 原来是 220ms + `Curves.easeOut`（规格外的第 22 个数字）。
                        onPressed: () => _pages.nextPage(
                          duration: Motion.base,
                          curve: Motion.standard,
                        ),
                        child: const Icon(Icons.arrow_forward, size: IconSpec.m),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(_Slide s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Spacer(flex: 2),
            Center(child: s.art),
            const Spacer(flex: 3),
            Text(
              s.title,
              style: const TextStyle(
                color: Tokens.text,
                fontSize: Tokens.fsHero,
                height: Tokens.lhTight,
                fontWeight: Tokens.fwBold,
                letterSpacing: Tokens.lsTight,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            Text(
              s.body,
              style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            ),
            const Spacer(),
          ],
        ),
      );
}

/// 第 1 屏：橙色圆环 + 闪电 + 绿勾（"一键就记下了"）。
class _TapArt extends StatelessWidget {
  const _TapArt();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: 172,
              height: 172,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Tokens.accent, width: 18),
              ),
            ),
            const Positioned(
              left: 62,
              top: 62,
              child: Icon(Icons.bolt, color: Tokens.text, size: IconSpec.xl),
            ),
            Positioned(
              right: 34,
              bottom: 40,
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: Tokens.success, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Tokens.inkOnSuccess, size: IconSpec.m),
              ),
            ),
          ],
        ),
      );
}

/// 第 2 屏：迷你「本周计划」卡（四根竖条 + AI 角标）。
class _PlanArt extends StatelessWidget {
  const _PlanArt();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(Tokens.s4),
              decoration: BoxDecoration(
                color: Tokens.surface,
                borderRadius: BorderRadius.circular(Tokens.rCard),
                border: Border.all(color: Tokens.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text('本周计划',
                            style: TextStyle(color: Tokens.text, fontSize: Tokens.fsCap)),
                      ),
                      Text('4 练',
                          style: Tokens.display(14, weight: 700, color: Tokens.accent)),
                    ],
                  ),
                  const SizedBox(height: Tokens.s3),
                  // 四根进度条：已练过的两根亮、后两根暗
                  for (int i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        height: 8,
                        width: i < 2 ? 150 : 110,
                        decoration: BoxDecoration(
                          color: i < 2 ? Tokens.accent : Tokens.elevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: -10,
              top: -10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Tokens.accent,
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
                child: const Text('AI',
                    style: TextStyle(
                        color: Tokens.accentInk, fontSize: Tokens.fsMicro, fontWeight: Tokens.fwBold)),
              ),
            ),
          ],
        ),
      );
}

/// 第 3 屏：柱状图 + 绿色的 +32% 角标。
class _ProgressArt extends StatelessWidget {
  const _ProgressArt();

  // 递增的柱高（比例）—— 手写而不是随机：截图与视觉验收要**可复现**
  static const List<double> _bars = <double>[0.28, 0.4, 0.34, 0.5, 0.62, 0.74, 0.88, 1];

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        height: 140,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Align(
              alignment: Alignment.bottomLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (final double h in _bars)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 18,
                        height: 130 * h,
                        decoration: BoxDecoration(
                          color: Tokens.accent.withValues(alpha: 0.35 + 0.65 * h),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: -4,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Tokens.success,
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
                child: const Text('+32%',
                    style: TextStyle(
                        color: Tokens.inkOnSuccess, fontSize: Tokens.fsMicro, fontWeight: Tokens.fwBold)),
              ),
            ),
          ],
        ),
      );
}
