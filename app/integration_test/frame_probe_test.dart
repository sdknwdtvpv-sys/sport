/// 练了么 · **帧率探针**（VI 计划 T2-1 判据 2/3）
///
/// **为什么要跑在真机上、还要 `--profile`**：
///   * iOS 模拟器**不支持** profile 模式，而 debug 模式的数字没有意义（Dart VM 未优化）；
///   * 这一条要量的是"休息倒计时每秒整屏重建"的代价，而 iOS 上同一屏还活着一个
///     `UITabBar` 平台视图（`glass_surface.dart` 文件头："活着的期间 Flutter 的栅格化
///     不再与 Dart 并行（**整屏代价**）"）—— 平台视图不进 Flutter 的截图，
///     所以只能靠**帧时间**看它。
///
/// 三段（与计划一致）：
///   ① 冷启动：`app.main()` 起、到外壳出现后 2 秒；
///   ② 连点三个 tab ×10（这一段的底栏是平台视图）；
///   ③ 记 10 组：前两组**完整等完 60 秒休息**（这是被测量的窗口），
///      后 8 组点「跳过」把总时长压到 ~2.5 分钟。
///
/// 产物：一行 `LIANLEME-FRAMES {json}` 打到日志里（`frames` / `marks` / `rests`），
/// 由 `tool/frame-probe-plot.py` 画成 `motion-probe-2026-10-10.png`。
/// **在这个脚本里也断言一次预算**（休息窗口内 raster 不许超过一帧）——
/// 数字不好看时当场红，而不是等回了主机才发现。
///
/// 跑法：
///   flutter drive --profile --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/frame_probe_test.dart -d <设备 id>
library;

import 'dart:convert';
// `FramePhase` 只在 dart:ui 里（`flutter/scheduler.dart` 不带它）
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianleme/main.dart' as app;

import 'evidence_sets.dart';

/// 一帧的预算（60Hz = 16.6ms；这里用 16ms 作为"没有掉帧"的线，与计划一致）。
const double kFrameBudgetMs = 16;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('帧率探针：冷启动 / 连点三个 tab ×10 / 记 10 组（含 2×60 秒休息）',
      (WidgetTester tester) async {
    final List<List<double>> frames = <List<double>>[]; // [build, raster, ts]
    final List<Map<String, Object?>> marks = <Map<String, Object?>>[];
    final List<List<int>> rests = <List<int>>[]; // [起始帧号, 结束帧号]

    void mark(String name) =>
        marks.add(<String, Object?>{'name': name, 'frame': frames.length});

    int? tsBaseUs;
    double r2(double v) => (v * 100).roundToDouble() / 100;
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final FrameTiming t in timings) {
        final int tsUs = t.timestampInMicroseconds(FramePhase.rasterFinish);
        tsBaseUs ??= tsUs;
        frames.add(<double>[
          r2(t.buildDuration.inMicroseconds / 1000),
          r2(t.rasterDuration.inMicroseconds / 1000),
          // 时间戳：横轴要画"真实的秒"，不能靠帧号 × 16.67 猜
          // （休息那 60 秒里每秒只有 1 帧，帧号完全对不上时间）。
          // 存**相对**第一帧的毫秒，省一半体积（绝对微秒有 12 位）。
          r2((tsUs - tsBaseUs!) / 1000),
        ]);
      }
    });

    Future<void> settle([int ms = 600]) async {
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < ms ~/ 120; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    // ── ① 冷启动 ────────────────────────────────────────────────────────
    mark('cold_start_begin');
    app.main();
    await settle(2500);
    if (find.byKey(const Key('consent-agree')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('consent-agree')));
      await settle(2000);
    }
    if (find.byKey(const Key('intro-skip')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('intro-skip')));
      await settle(1500);
    }
    mark('cold_start_end');

    // ── ② 连点三个 tab ×10 ──────────────────────────────────────────────
    mark('tab_taps_begin');
    for (int i = 0; i < 10; i++) {
      for (final (int idx, String label) in <(int, String)>[
        (0, '进步'),
        (1, '开练'),
        (2, '我'),
      ]) {
        await switchTab(tester, idx, label);
        await settle(300);
      }
    }
    mark('tab_taps_end');

    // ── ③ 记 10 组 ──────────────────────────────────────────────────────
    await switchTab(tester, 1, '开练');
    await settle(800);
    if (find.byKey(const Key('start-workout')).evaluate().isEmpty) {
      debugPrint('LIANLEME-FRAMES-ABORT 找不到「开始训练」按钮 —— 这一屏状态与预期不符');
      return;
    }
    await tester.tap(find.byKey(const Key('start-workout')));
    await settle(2000);
    mark('workout_begin');

    for (int i = 0; i < 10; i++) {
      if (find.byKey(const Key('big-log-button')).evaluate().isEmpty) {
        debugPrint('LIANLEME-FRAMES-ABORT 第 $i 组时找不到大按钮');
        break;
      }
      await tester.tap(find.byKey(const Key('big-log-button')));
      await settle(700);
      final bool resting = find.byKey(const Key('rest-bar')).evaluate().isNotEmpty;
      if (!resting) continue;
      final int from = frames.length;
      if (i < 2) {
        // 被测量的窗口：**完整等完** 60 秒（每秒一跳，正是 T2-1 要压住的那 60 次）
        for (int s = 0; s < 62; s++) {
          await tester.pump(const Duration(seconds: 1));
        }
      } else {
        // 其余组跳过休息，把总时长压下来（跳过也走同一段代码）
        await settle(900);
        if (find.byKey(const Key('skip-rest')).evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const Key('skip-rest')));
          await settle(600);
        }
      }
      rests.add(<int>[from, frames.length]);
    }
    mark('workout_end');

    // ── 预算断言：休息窗口内 raster 不许超过一帧 ────────────────────────
    double worst = 0;
    int worstFrame = -1;
    double restBuildWorst = 0;
    for (final List<int> w in rests) {
      for (int i = w[0]; i < w[1] && i < frames.length; i++) {
        if (frames[i][1] > worst) {
          worst = frames[i][1];
          worstFrame = i;
        }
        if (frames[i][0] > restBuildWorst) restBuildWorst = frames[i][0];
      }
    }
    final int restFrames = rests.fold<int>(0, (int a, List<int> w) => a + (w[1] - w[0]));

    // 先把**要引用的那几个结论**打成一行短的：长的帧数据可能被 logcat 掐掉尾巴，
    // 而"休息窗口最差 raster"这几个数不能因此丢掉（第一次跑就是这么丢的）。
    debugPrint('LIANLEME-FRAMES-SUMMARY ${jsonEncode(<String, Object?>{
          'frames': frames.length,
          'span_ms': frames.isEmpty ? 0 : frames.last[2],
          'rests': rests,
          'rest_frame_count': restFrames,
          'rest_worst_raster_ms': worst,
          'rest_worst_frame': worstFrame,
          'rest_build_max_ms': restBuildWorst,
        })}');

    final String payload = jsonEncode(<String, Object?>{
      'frames': frames,
      'marks': marks,
      'rests': rests,
      'rest_frame_count': restFrames,
      'rest_worst_raster_ms': worst,
      'rest_worst_frame': worstFrame,
    });
    // ⚠️ **必须分段**：Android 的 logcat 会把单行截断在 ~1KB（第一次跑就是这么丢的，
    // 日志里那行 JSON 断在一个数字中间，回主机解析才发现）。每段 ≤ 700 字符、按序号拼回。
    const int chunk = 600;
    final int parts = (payload.length / chunk).ceil();
    for (int i = 0; i < parts; i++) {
      final int from = i * chunk;
      final int to = from + chunk < payload.length ? from + chunk : payload.length;
      debugPrint('LIANLEME-FRAMES-PART $i/$parts ${payload.substring(from, to)}');
    }
    // ⚠️ 打完**别马上退出**：最后一段常常在进程收尾时被 logcat 吃掉（第一次跑丢的就是它）。
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(restFrames, greaterThan(60),
        reason: '休息窗口几乎没有采到帧 —— 这个探针没有量到东西');
    expect(worst, lessThan(kFrameBudgetMs),
        reason: '休息期间最差的一帧 raster = ${worst.toStringAsFixed(1)}ms'
            '（帧号 $worstFrame）超过 $kFrameBudgetMs ms 预算');
  });
}
