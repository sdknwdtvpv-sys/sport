/// 练了么 · **从系统健康库读体成分**并合进本机（`docs/plan-health-sync.md` 的施工单）
///
/// 这一层只做三件事，顺序不能换：
///   1. **看那道单独同意在不在** —— 不在就**立刻返回，一个字节都不读**（PIPL 第 29 条
///      的口径："同意范围到哪，处理就到哪"，撤回之后继续读，撤回就成了空话）；
///   2. 过了门才去问平台：有没有健康库 → 请求授权 → 读样本；
///   3. 把样本**按本地日**分组（每个字段取那天**最新**的一个值），交给
///      `BodyMetricRepository.mergeHealthDays` —— 合并规则在那边的注释里，
///      一句话概括是"我们的字段不覆盖，只补缺的；那天只有系统有就新建并留痕"。
///
/// ⚠️ **身高不走 [BodyMetricRepository]**：它不是每日指标，存在档案里
/// （`user_profile.height_cm`），而且**只在档案里是空的时候才填** ——
/// 用户自己量过的身高，凭什么被健康库里一个旧值改掉。
library;

import '../data/body_metric_repository.dart';
import '../data/profile_repository.dart';
import 'health_bridge.dart';

/// 一次同步的结果。界面照它如实说（不许把"没允许"说成"没有数据"）。
enum HealthSyncStatus {
  /// 没单独同意过 —— **一个字节都没读**。
  noConsent,

  /// 这台设备没有健康库（iPad、老安卓、模拟器上没有"健康"的环境）。
  unavailable,

  /// 授权那一步没走完（用户取消 / 系统拒绝）。
  denied,

  /// 读了，但健康库里没有体成分记录。
  empty,

  /// 读到了，并且已经按天合并进本机。
  imported,
}

class HealthSyncOutcome {
  const HealthSyncOutcome({
    required this.status,
    this.samples = 0,
    this.report,
    this.heightFilledCm,
  });

  final HealthSyncStatus status;

  /// 读到的原始样本条数（不是天数 —— 一天可能有好几条）。
  final int samples;

  /// 合并的逐日结果；只有 [HealthSyncStatus.imported] 时非空。
  final HealthMergeReport? report;

  /// 这次**补上的身高**（cm）；没有补就是 null。
  final double? heightFilledCm;
}

class HealthSyncService {
  HealthSyncService({
    required this.bridge,
    required this.bodyMetrics,
    required this.profile,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final HealthBridge bridge;
  final BodyMetricRepository bodyMetrics;
  final ProfileRepository profile;
  final DateTime Function() _clock;

  /// 往前看多少天。**不读全history**：体成分这种数据，半年前的数对今天没有意义，
  /// 而且一次读几百上千条会明显拖慢首次同步。
  static const int lookbackDays = 180;

  Future<HealthSyncOutcome> sync() async {
    // ① 那道门（先看同意，后碰平台 —— 顺序本身就是这条合规要求）
    if (await profile.healthConsentAtMs() == null) {
      return const HealthSyncOutcome(status: HealthSyncStatus.noConsent);
    }

    // ② 平台侧
    if (!await bridge.isAvailable()) {
      return const HealthSyncOutcome(status: HealthSyncStatus.unavailable);
    }
    if (!await bridge.requestPermission()) {
      return const HealthSyncOutcome(status: HealthSyncStatus.denied);
    }
    final List<HealthSample> samples =
        await bridge.readBodyComposition(days: lookbackDays);
    if (samples.isEmpty) {
      return const HealthSyncOutcome(status: HealthSyncStatus.empty);
    }

    // ③ 按本地日分组：每个字段取那天**最新**的一个值。
    //    ⚠️ 要"最新优先"，所以先按时间**降序**排，再用 `??=`（先到的不被后来者盖掉）。
    final List<HealthSample> sorted = List<HealthSample>.of(samples)
      ..sort((HealthSample a, HealthSample b) => b.atMs.compareTo(a.atMs));

    final Map<String, HealthDayValues> byDay = <String, HealthDayValues>{};
    final Map<String, double> weightByDay = <String, double>{};
    final Map<String, double> fatByDay = <String, double>{};
    double? newestHeight;
    for (final HealthSample s in sorted) {
      final String day =
          dayKey(DateTime.fromMillisecondsSinceEpoch(s.atMs));
      if (s.weightKg != null) weightByDay.putIfAbsent(day, () => s.weightKg!);
      if (s.bodyFatPct != null) fatByDay.putIfAbsent(day, () => s.bodyFatPct!);
      if (s.heightCm != null) newestHeight ??= s.heightCm;
    }
    final List<String> dates = <String>{...weightByDay.keys, ...fatByDay.keys}
        .toList()
      ..sort();
    for (final String date in dates) {
      byDay[date] = HealthDayValues(
        date: date,
        weightKg: weightByDay[date],
        bodyFatPct: fatByDay[date],
      );
    }

    final DateTime now = _clock();
    final HealthMergeReport report = await bodyMetrics.mergeHealthDays(
      byDay.values.toList(),
      nowMs: now.millisecondsSinceEpoch,
    );

    // 身高：**只在档案里还是空的时候**才填（用户量过的值优先）
    double? heightFilled;
    if (newestHeight != null && await profile.heightCm() == null) {
      await profile.setHeightCm(newestHeight, nowMs: now.millisecondsSinceEpoch);
      heightFilled = newestHeight;
    }

    return HealthSyncOutcome(
      status: HealthSyncStatus.imported,
      samples: samples.length,
      report: report,
      heightFilledCm: heightFilled,
    );
  }
}
