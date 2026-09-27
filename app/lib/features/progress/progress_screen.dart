/// 练了么 · S8「进步」
///
/// 对应 `docs/screens.md` S8。只有三块内容（规格里就是这么定的）：
/// 本周容量曲线、PR 墙、体重。
///
/// **体重没做** —— 需要 `body_metric` 表与录入界面（S12），是另一块工作。
/// 与其放一个空的「体重 —」，不如先不放；等有了再加回来。
///
/// 曲线是自己画的（`CustomPainter`），不引图表库：
/// 七个点、一条折线，为它加一个依赖不值得。
library;

import 'package:flutter/material.dart';

// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，预先 hide。
import '../../core/theme.dart';
import '../../data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../domain/models.dart';
import 'progress_data.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    super.key,
    required this.store,
    required this.repository,
    this.now,
  });

  final LocalStore store;
  final ExerciseRepository repository;

  /// 测试注入固定时间用；生产为 null，取当前时间
  final DateTime? now;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  ProgressData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SetRecord> sets = await widget.store.allSets();
    final List<ExerciseData> rows = await widget.repository.search(limit: 500);
    final Map<String, String> names = <String, String>{
      for (final ExerciseData r in rows) r.id: r.name,
    };
    if (!mounted) return;
    setState(() {
      _data = buildProgress(
        sets: sets,
        exerciseNames: names,
        today: widget.now ?? DateTime.now(),
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final ProgressData d = _data!;

    if (d.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: Tokens.s5),
        child: Center(
          child: Text(
            '还没有训练记录。\n练完第一次，这里就会长出曲线和纪录。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Tokens.text3, fontSize: 15, height: 1.6),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s5),
      children: <Widget>[
        const Text(
          '进步',
          style: TextStyle(
            color: Tokens.text,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: Tokens.s5),
        _weekCard(d),
        const SizedBox(height: Tokens.s5),
        _sectionTitle('PR 墙'),
        _prCard(d),
      ],
    );
  }

  Widget _weekCard(ProgressData d) {
    return Container(
      padding: const EdgeInsets.all(Tokens.s5),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('本周容量', style: TextStyle(color: Tokens.text3, fontSize: 13)),
          const SizedBox(height: Tokens.s2),
          Text(
            d.weekVolumeLabel,
            key: const Key('progress-week-volume'),
            style: const TextStyle(
              color: Tokens.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            d.weekWorkouts == 0 ? '这 7 天还没练' : '这 7 天练了 ${d.weekWorkouts} 次',
            style: const TextStyle(color: Tokens.text3, fontSize: 13),
          ),
          const SizedBox(height: Tokens.s4),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(
              key: const Key('progress-sparkline'),
              painter: _SparklinePainter(d.sparkline),
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(_dayLabel(d.week.first.day),
                  style: const TextStyle(color: Tokens.text3, fontSize: 11)),
              const Text('今天', style: TextStyle(color: Tokens.text3, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _prCard(ProgressData d) {
    return Container(
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        border: Border.all(color: Tokens.line),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < d.prs.length; i++)
            Container(
              key: Key('pr-${d.prs[i].exerciseId}'),
              padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.s4, vertical: Tokens.s4),
              decoration: BoxDecoration(
                border: i == d.prs.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: Tokens.line)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      d.prs[i].name,
                      style: const TextStyle(color: Tokens.text, fontSize: 15),
                    ),
                  ),
                  Text(
                    d.prs[i].label,
                    style: const TextStyle(
                      color: Tokens.pr,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: Tokens.s1, bottom: Tokens.s2),
        child: Text(t, style: const TextStyle(color: Tokens.text3, fontSize: 13)),
      );

  String _dayLabel(DateTime d) => '${d.month}/${d.day}';
}

/// 七个点的折线。不引图表库：为一条线加一个依赖不值得。
class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);

  /// 0..1 的比例，长度即点数
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final Paint line = Paint()
      ..color = Tokens.volt
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final Paint dot = Paint()..color = Tokens.volt;
    final Paint baseline = Paint()
      ..color = Tokens.line
      ..strokeWidth = 1;

    // 底部基线：全 0 时也让用户看得出这是"一条线"，而不是空白
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      baseline,
    );

    final double stepX =
        values.length > 1 ? size.width / (values.length - 1) : 0;
    final double usableH = size.height - 8;

    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = stepX * i;
      final double y = size.height - 4 - usableH * values[i].clamp(0.0, 1.0);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);

    for (int i = 0; i < values.length; i++) {
      final double x = stepX * i;
      final double y = size.height - 4 - usableH * values[i].clamp(0.0, 1.0);
      canvas.drawCircle(Offset(x, y), 3, dot);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) => oldDelegate.values != values;
}
