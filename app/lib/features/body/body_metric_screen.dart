/// 练了么 · S12 身体数据录入
///
/// 规格（`docs/screens.md` S11–S15）：**体重 + 备注，一天一条**。
///
/// 两点刻意的决定：
///   1. **日期可补录最近 7 天**。体重常常是事后补记的，
///      而"一天一条"意味着补录同一天应该是**改**那一条，不是新增。
///      用一排日期 chips 而不是日期选择器：少一次弹窗、少一层交互。
///   2. **体重用数字输入而不是步进按钮**。项目一贯"不做全键盘"是针对
///      S5 每组改重量那种场景（一手拿手机、一手拿杠铃）；体重是一个
///      你早上就知道的确定数值，从默认值一步步加减反而荒唐。
///      这是一个有意的例外，不是忘了规矩。
library;

import '../../core/icon_spec.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import '../../core/fields.dart';
import '../../core/theme.dart';
import '../../core/glass_overlay.dart';
import '../../core/vi_area_chart.dart';
import '../../core/vi_cards.dart';
import 'bmi.dart';
import 'body_trend.dart';
import '../../core/units.dart';
import '../../analytics/analytics.dart';
import '../../data/body_metric_repository.dart';
import '../../data/db.dart';
import '../../data/profile_repository.dart';
import '../../health/health_bridge.dart';
import '../../health/health_sync.dart';

/// 「健康库里没找到」该去哪儿看 —— **两端不一样**。
///
/// ⚠️ 为什么做成函数：原来的写法写死了「iPhone 的「健康」App」，
/// 而 2026-10-09 之后**安卓 14+ 也会出现这个入口**（平台自带的 Health Connect）——
/// 那种时候告诉安卓用户"去 iPhone 的健康 App 里看看"就是一句**假话**。
/// 抽成纯函数还顺带能被单测直接钉住两个分支，不用去伪装平台。
String healthEmptyHint(TargetPlatform platform) => platform == TargetPlatform.iOS
    ? '健康库里没有找到体重、体脂率、身高或腰围。\n\n'
        '要么那里本来就没有这些记录，要么刚才没允许读取 —— '
        '可以去 iPhone 的「健康」App 里看看有没有数据。'
    : '健康库里没有找到体重、体脂率或身高。\n\n'
        '要么那里本来就没有这些记录，要么刚才没允许读取 —— '
        '可以到系统里的「健康连接 / Health Connect」里看看有没有数据。';

/// **「从系统健康同步」读的是哪几样**（2026-10-09，10.9 清单第 9 条）。
///
/// ⚠️ 两端**不一样**，而且这是事实、不是偷懒：Health Connect（Android 14+ 平台自带那个）
/// **没有腰围这一类数据**，也没有对应的读权限 —— 我们在 android-36 的 `HealthPermissions`
/// 里 grep 过，一个 WAIST 都没有（构建时也当场红过一次：照着"应该有个
/// WaistCircumferenceRecord"写，Kotlin 直接编不过）。所以：
///   * iPhone（HealthKit）：体重、体脂率、身高、**腰围**；
///   * Android：体重、体脂率、身高。
/// 界面上的小字与同意框正文都走这个函数 —— 一条写死的"四样"在 Android 上就是假话。
String healthReadSummary(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? '体重、体脂率、身高、腰围' : '体重、体脂率、身高';

/// 「没拿到许可」该去哪儿打开 —— 同上，两端的设置路径根本不是同一条。
String healthDeniedHint(TargetPlatform platform) => platform == TargetPlatform.iOS
    ? '没有拿到读取健康数据的许可。\n\n'
        '你可以在系统「设置 → 隐私与安全性 → 健康 → 练了么」里打开，再回来试一次。'
    : '没有拿到读取健康数据的许可。\n\n'
        '你可以在系统「设置 → 应用 → 健康连接 / Health Connect → 应用权限」里'
        '给「练了么」打开读权限，再回来试一次。';


class BodyMetricScreen extends StatefulWidget {
  const BodyMetricScreen({
    super.key,
    required this.repository,
    this.unit = BodyWeightUnit.kg,
    this.analytics,
    this.profile,
    this.clock,
    this.onSaved,
    this.onUnitChanged,
    this.healthBridge,
  });

  final BodyMetricRepository repository;

  /// 体重的显示与输入单位（**千克 / 斤**）的**初始值**。
  /// **存储始终是 kg**（见 core/units.dart）。
  ///
  /// 它在**本页内**可以实时切换（[onUnitChanged] / 页内那个小开关）——
  /// 用户的理由很直接：称体重的时候才想起来"我要按斤看"，
  /// 那时不该退出去到「我」页翻设置。
  final BodyWeightUnit unit;

  /// 埋点（可选）。上报 `body_metric_logged` —— **只报"填没填"，不报数值**（见隐私政策 §6）。
  final Analytics? analytics;

  /// 用户偏好仓库。传了才会把实时切换的单位**落库**（测试可以不传）。
  final ProfileRepository? profile;

  /// 单位在本页被切换后通知上层（让「进步」页那张卡片也跟着变）。
  final ValueChanged<BodyWeightUnit>? onUnitChanged;

  /// 便于测试固定"今天"。不传则用真实时间。
  final DateTime Function()? clock;

  /// 保存后回调，让上一页刷新（「我」和「进步」都要显示体重）
  final VoidCallback? onSaved;

  /// **从系统健康库读体成分**那座桥（2026-10-09）。
  ///
  /// ⚠️ 只有 **iPhone** 这一版接了（HealthKit）。安卓那一端还没接
  /// （Health Connect 要动 minSdk 并新增一个 Gradle 依赖，见 `docs/plan-health-sync.md` §七），
  /// 所以别的平台上**这个入口根本不出现** —— 不给一个做不到的承诺。
  ///
  /// 传值规则：显式传了就用传进来的（测试用假桥）；没传时按平台决定 ——
  /// iPhone 上自动建一座真桥，其它平台没有入口。
  final HealthBridge? healthBridge;

  @override
  State<BodyMetricScreen> createState() => _BodyMetricScreenState();
}

class _BodyMetricScreenState extends State<BodyMetricScreen> {
  /// 有没有输入框正拿着焦点（= 键盘大概率开着）。
  ///
  /// 2026-10-09（第二份 docx 第 3 条）：用户原话「这个页面的输入按键，没办法退出」——
  /// iOS 的数字键盘**没有回车/完成键**，而"点空白处收起"这件事用户并不知道。
  /// 所以键盘一开，标题行右边就出现一个看得见的「完成」。
  bool _fieldFocused = false;

  final TextEditingController _weight = TextEditingController();

  /// 本页当前使用的体重单位。**初值来自构造参数，之后由页内那个开关实时改。**
  late BodyWeightUnit _unit = widget.unit;
  final TextEditingController _note = TextEditingController();
  List<BodyMetricData> _recent = const <BodyMetricData>[];

  /// 腰围 / 肌肉量 / 身高的输入（2026-10-05，v1.52）。
  ///
  /// ⚠️ 身高**不是**每日指标，它存进 `user_profile`（只用来算 BMI）——
  /// 和其它三项一起进表单，但保存时走的是另一条路（见 `_save`）。
  final TextEditingController _waist = TextEditingController();
  final TextEditingController _muscle = TextEditingController();
  final TextEditingController _height = TextEditingController();

  /// 最近一次记录里的体脂/肌肉量/腰围（摘要块用）。
  BodyMetricData? _latest;

  /// 身高（cm）。存在 `user_profile` 里，不是每日指标 —— 只用来算 BMI。
  double? _heightCm;

  /// 趋势卡当前选中的指标（v1.52）。记过哪个才切得过去，见 `trendMetrics`。
  BodyTrendMetric _trendMetric = BodyTrendMetric.weight;
  late DateTime _selected;
  bool _loading = true;

  /// 单独同意还没问完时为 true。
  ///
  /// 为什么单独一个状态：同意未决时如果照旧走 `_loading` 那条分支，弹层后面会挂一个
  /// **永远转的圈**（`_load()` 要等同意之后才调）—— 测试里表现为 `pumpAndSettle` 超时，
  /// 用户那边表现为"提示框后面卡住了"。所以这段时间渲染一块**静态**占位。
  bool _consentPending = false;
  bool _saving = false;

  /// 「从系统健康库读取」那道**单独同意**在不在（2026-10-09）。
  ///
  /// 与 `_consentPending` 是两件事：那一道管"记在本机"，这一道管"去读系统里别人写下的记录"。
  /// 只有同意过才显示那条撤回入口 —— 没同意过就没什么可撤回的。

  /// 正在读健康库（入口那一行显示转圈，避免连点两次）。
  bool _healthBusy = false;

  /// **这台设备现在能不能读到系统健康库**（`_load()` 里问平台，见 [_healthBridge]）。
  ///
  /// ⚠️ 为什么不能只看"是不是 iPhone"：安卓那半边**只有 Android 14+ 能读**
  /// （平台自带的 Health Connect；13 及以下要抬 minSdk 26 走 Jetpack 库，那是产品决定，
  /// 见 `docs/plan-health-sync.md` §七）。所以入口出现与否**由平台自己回答**，
  /// 不由我们按机型猜 —— 猜错的那一半用户会看到一个点下去什么都读不到的入口。
  bool _healthAvailable = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _selected = _now;
    // **敏感个人信息的单独同意**（PIPL 第 29 条）：
    // 体重属于医疗健康类的敏感个人信息，首次启动那道"政策总同意"**不等于**单独同意。
    // 所以进这一页先单独问一次；同意过就直接读数据，没同意过就先弹说明。
    unawaited(_ensureSensitiveConsent());
  }

  /// 过"单独同意"这道门：没同意过就弹一次；用户点「先不用」就退出这一页（不收集任何东西）。
  Future<void> _ensureSensitiveConsent() async {
    final ProfileRepository? profile = widget.profile;
    // 没有 profile（纯嵌入/测试场景，比如截图脚本）时不做拦截 —— 真实 App 一定传。
    if (profile == null) {
      await _load();
      return;
    }
    if (await profile.bodyMetricConsentAtMs() != null) {
      await _load();
      return;
    }
    if (!mounted) return;
    setState(() => _consentPending = true); // 静态占位，别再转圈
    final bool? agree = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: const Text('身体数据是敏感个人信息，要先单独征得你同意',
            style: TextStyle(color: Tokens.text)),
        content: const Text(
          // ⚠️ 这里**不能**写 markdown 的 `**`：`Text` 不渲染 markdown，
          // 用户会直接看到星号（v1.31.0 真机截图时抓到过一次）。
          // test/body_consent_test.dart 里有一条断言专门守着这件事。
          //
          // v1.52：这一页不止记体重了（还记体脂率 / 腰围 / 肌肉量 / 身高），
          // 所以说明里的"记的是体重"必须跟着改 —— 只写体重就变成"收集了没说"。
          // 它们共用**这一次**同意（同一类数据、同一个页面、同一个用途），
          // 不是每加一个字段就再弹一次窗。
          //
          // ⚠️ 2026-10-05：这一句原来写的是「不会上传（云备份里也不含身体数据）」，
          // 而身体数据那天起**会进备份** —— 那句话就成了假话。改法不是把它删掉
          // （"去向"是这道门最要紧的一句），而是把真实条件写出来：
          // **只有你自己打开云备份**，它才会以密文离开这台手机。
          // 撤回同意之后连备份里也不会再有（判据在 backup_source.dart）。
          '「身体数据」记的是你的体重、体脂率、腰围、肌肉量和身高 —— '
          '按《个人信息保护法》，这类健康数据属于'
          '敏感个人信息，需要我们单独征求你的同意（首次启动时那次是政策总同意，'
          '不等于这一条）。\n\n'
          '· 它们默认只存在这台手机上。只有你自己在「数据与备份 → 云备份」里'
          '开启云备份时，它们才会和训练记录一起以密文上传（端到端加密，服务端读不出来）；'
          '云备份默认是关的，你不开就不上传。\n'
          '· 用途只有一个：给你自己看长期变化（身高只用来算 BMI）；\n'
          '· 你可以随时在「全部数据」里改或删掉它们，也可以随时撤回这次同意。',
          key: Key('body-consent'),
          style: TextStyle(color: Tokens.text2, height: Tokens.lhNormal),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('body-consent-decline'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('先不用', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('body-consent-agree'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意并记录', style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    );
    if (agree != true) {
      // 不同意 → 直接退出这一页：不读、不写、不收集
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await profile.setBodyMetricConsent();
    if (mounted) setState(() => _consentPending = false);
    await _load();
  }

  // ══ 从系统健康库读体成分（2026-10-09）════════════════════════════════════
  //
  // 这一整块与上面那道"身体数据"的单独同意是**两道不同的门**，别把它们合成一道：
  //   * bodyMetricConsent  → "我们把你的体重记在这台手机上"
  //   * healthConsent      → "我们去读系统健康库里别人写下的记录"
  // 目的不同、种类不同、撤回也该各撤各的（PIPL 第 29 条要的就是逐项同意）。
  // 判据在 `docs/privacy-facts.json` 的 `healthSync`，由 tool/privacy-audit.mjs 每次对账。

  /// 系统健康库那座桥。两端都接了：iOS 走 HealthKit，Android 14+ 走平台自带的
  /// Health Connect（见 `HealthConnectApi34.kt`）。**能不能读由平台回答**
  /// （`isAvailable()`），入口只在它说"能"的时候出现。
  ///
  /// 测试可以显式传一个假桥（`widget.healthBridge`），那就完全按假的来。
  HealthBridge get _healthBridge =>
      widget.healthBridge ?? const MethodChannelHealthBridge();

  /// 过"读系统健康库"这道门。返回 true = 可以往下读。
  Future<bool> _ensureHealthConsent() async {
    final ProfileRepository? profile = widget.profile;
    if (profile == null) return false;
    if (await profile.healthConsentAtMs() != null) {
      return true;
    }
    if (!mounted) return false;
    final bool? agree = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: const Text('读系统健康库要单独征得你同意',
            style: TextStyle(color: Tokens.text)),
        content: Text(
          // ⚠️ 这里同样**不能**写 markdown 的星号：`Text` 不渲染 markdown。
          // ⚠️ 读哪几样**分平台**（Android 读不到腰围，见 [healthReadSummary]）——
          // 写死"四样"在 Android 上就是假话。
          '「系统健康库」就是 iPhone 上那个「健康」App。这里读的只有'
          '${healthReadSummary(Theme.of(context).platform)}（都是体成分）——'
          '心率、睡眠、运动记录一次都不读，也不申请。\n\n'
          '· 只读，不写回：我们一个字都不会写进你的健康库；\n'
          '· 按《个人信息保护法》，这几样属于敏感个人信息，要单独征求你的同意 —— '
          '它与「身体数据」那道门是两件事：那一道管"记在这台手机上"，'
          '这一道管"去读系统里别人写下的记录"；\n'
          '· 不同意就一个字节都不读；\n'
          '· 读进来的数只落在这台手机上，不上传（只有你自己开的云备份会带走它们，'
          '那份是端到端加密的密文）；\n'
          '· 随时可以撤回：撤回之后不再读，已经并进来的那些天不会被删掉。',
          key: Key('health-consent'),
          style: TextStyle(color: Tokens.text2, height: Tokens.lhNormal),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('health-consent-decline'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('先不用', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('health-consent-agree'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意并读取',
                style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    );
    if (agree != true) return false;
    await profile.setHealthConsent();
    return true;
  }

  /// 点那一行的完整流程：过门 → 读 → 合并 → 如实报数。
  Future<void> _healthSync() async {
    final HealthBridge bridge = _healthBridge;
    final ProfileRepository? profile = widget.profile;
    if (profile == null || _healthBusy) return;

    if (!await _ensureHealthConsent()) return;
    if (!mounted) return;
    setState(() => _healthBusy = true);

    final HealthSyncOutcome out = await HealthSyncService(
      bridge: bridge,
      bodyMetrics: widget.repository,
      profile: profile,
      clock: widget.clock,
    ).sync();

    if (!mounted) return;
    setState(() => _healthBusy = false);
    // 并进来的天要立刻看得见（摘要、最近记录、趋势都靠 _load 刷新）
    await _load();
    if (!mounted) return;
    widget.onSaved?.call();
    await _showHealthResult(out);
  }

  /// 如实报数：新增几天 / 补了几天 / 几天没动 / 几天跳过。
  Future<void> _showHealthResult(HealthSyncOutcome out) async {
    final HealthMergeReport? r = out.report;
    final String body;
    switch (out.status) {
      case HealthSyncStatus.imported:
        final StringBuffer b = StringBuffer();
        b.write('从系统健康读到 ${out.samples} 条记录。\n\n');
        b.write('· 新记了 ${r?.created ?? 0} 天；\n');
        b.write('· 补上了 ${r?.filled ?? 0} 天缺的项；\n');
        b.write('· ${r?.unchanged ?? 0} 天本来就有，没动；\n');
        // ⚠️ 只说"没动"不说为什么，用户会以为失败 —— 所以把两种原因都写出来
        b.write('· ${r?.skipped ?? 0} 天没动'
            '（你删过的那天不会复活，系统里没数的天也不会凭空记一条）。\n');
        if (out.heightFilledCm != null) {
          b.write('\n身高补上了 ${trimNumber(round1(out.heightFilledCm!))} cm。');
        }
        final int touched = r?.touched ?? 0;
        if (touched == 0) {
          b.write('\n\n你自己记的那些天一个都没被改动。');
        } else {
          b.write('\n\n你自己记过的字段一个都没被覆盖，只补了缺的那些。');
        }
        body = b.toString();
      case HealthSyncStatus.empty:
        body = healthEmptyHint(defaultTargetPlatform);
      case HealthSyncStatus.denied:
        body = healthDeniedHint(defaultTargetPlatform);
      case HealthSyncStatus.unavailable:
        body = '这台设备上没有可用的系统健康库。';
      case HealthSyncStatus.noConsent:
        body = '还没有同意读取系统健康库。';
    }

    await showAppDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: const Text('同步结果', style: TextStyle(color: Tokens.text)),
        content: Text(
          body,
          key: const Key('health-result'),
          style: const TextStyle(color: Tokens.text2, height: Tokens.lhNormal),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('health-result-ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了', style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    );
  }

  /// 入口那一行。**只有同意过才显示撤回入口**（没同意过就没什么可撤回的）。
  Widget _healthSyncCard() {
    return ViCard(
      child: InkWell(
        key: const Key('health-sync-entry'),
        onTap: _healthBusy ? null : _healthSync,
        borderRadius: BorderRadius.circular(Tokens.rCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Tokens.s4, vertical: Tokens.s3),
          child: Row(
            children: <Widget>[
              Icon(Icons.favorite_outline, size: IconSpec.m, color: Tokens.accent),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('从系统健康同步',
                        style: TextStyle(color: Tokens.text, fontSize: Tokens.fsSub)),
                    const SizedBox(height: 2),
                    Text(
                      '只读${healthReadSummary(Theme.of(context).platform)} · 可选',
                      style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                    ),
                  ],
                ),
              ),
              _healthBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right, color: Tokens.text3, size: IconSpec.m),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _weight.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 最近 7 天，含今天（倒序：今天在最左）。
  List<DateTime> get _dayChoices {
    final DateTime today = _now;
    return <DateTime>[
      for (int i = 0; i < 7; i++) DateTime(today.year, today.month, today.day - i),
    ];
  }

  Future<void> _load() async {
    final double? height = await widget.profile?.heightCm();
    // 平台自己回答"能不能读"。桥内部对 MissingPluginException / PlatformException 都是
    // 静默降级成 false（见 health_bridge.dart），所以这里不需要再包一层 try。
    final bool healthAvailable = await _healthBridge.isAvailable();
    final List<BodyMetricData> recent = await widget.repository.recent();
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _heightCm = height;
      _healthAvailable = healthAvailable;
      // 摘要块看的是**最近一条有体重的记录**（`recent` 已按日期倒序）
      _latest = recent.isEmpty ? null : recent.first;
      if (height != null) _height.text = trimNumber(round1(height));
      _loading = false;
    });
    await _prefill();
  }

  /// 选中某天时，把已有的记录填进输入框 —— 补录应该是"看到已有值再改"，
  /// 而不是"面对空框重新猜上次填了什么"。
  Future<void> _prefill() async {
    final BodyMetricData? row =
        await widget.repository.forDate(dayKey(_selected));
    if (!mounted) return;
    setState(() {
      // 软删除过的不填 —— 用户已经删掉它了
      final bool usable = row != null && row.deletedAt == null;
      _weight.text = usable
          ? trimNumber(round1(toDisplayBodyWeight(row.weightKg ?? 0, _unit)))
          : '';
      _note.text = usable ? (row.note ?? '') : '';
      // 新字段也一样回填（2026-10-05）：补录时"看到已有值再改"，不是面对空框重猜
      _waist.text = usable && row.waistCm != null ? trimNumber(round1(row.waistCm!)) : '';
      _muscle.text =
          usable && row.muscleMassKg != null ? trimNumber(round1(row.muscleMassKg!)) : '';
    });
  }

  @override
  void didUpdateWidget(BodyMetricScreen old) {
    super.didUpdateWidget(old);
    // 上层换了单位（比如整棵树按新偏好重建）→ 跟着换，并把输入框里的数字一起换过去。
    // 本地已经切过（_switchUnit 已经通知过上层）时这里通常是 no-op。
    if (old.unit != widget.unit && widget.unit != _unit) {
      _adoptUnit(widget.unit, persist: false, notify: false);
    }
  }

  /// 把当前单位换成 [next]：输入框里的数字**跟着换成同一个体重**，其余不动。
  void _adoptUnit(BodyWeightUnit next,
      {required bool persist, required bool notify}) {
    if (next == _unit) return;
    final double? asKg = _parsedWeight;
    setState(() {
      _unit = next;
      if (asKg != null) {
        _weight.text = trimNumber(round1(toDisplayBodyWeight(asKg, next)));
      }
    });
    if (persist) unawaited(_persistUnit(next));
    if (notify) widget.onUnitChanged?.call(next);
  }

  /// 实时切换体重单位。
  ///
  /// **数字要跟着变**（"实时数据变动"）：输入框里已经填的值是**旧单位**下的数，
  /// 切换后换成新单位下**同一个体重**的值 —— 85.5 切到斤就是 171，而不是留个 85.5
  /// 让人以为自己体重变了。已经存进库的 kg 一个字节都不动。
  ///
  /// 输入框里的内容解析不出来（空的、半截的、超范围的）就原样留着，不猜。
  void _switchUnit(BodyWeightUnit next) =>
      _adoptUnit(next, persist: true, notify: true);

  Future<void> _persistUnit(BodyWeightUnit u) async {
    final ProfileRepository? p = widget.profile;
    if (p == null) return;
    await p.setBodyWeightUnit(u);
  }

  /// 只接受数字与小数点的输入。
  double? get _parsedWeight {
    final String t = _weight.text.trim();
    if (t.isEmpty) return null;
    final double? v = double.tryParse(t);
    if (v == null) return null;
    // 明显不合理的值当作没填，避免把 720 kg 存进去。
    // 范围按**显示单位**判断：400 kg（= 882 lb = 800 斤），再换成 kg 存库。
    // ⚠️ 三个单位都要算 —— 以前只有 kg/斤，加了 lb 之后
    // 用 `_unit == kg ? 400 : 400 * 2` 会把 400 lb（≈181 kg）也判成超标。
    final double maxInDisplay = toDisplayBodyWeight(400, _unit);
    if (v <= 0 || v > maxInDisplay) return null;
    return round1(bodyWeightToKg(v, _unit));
  }

  bool get _canSave => !_saving && _parsedWeight != null;

  /// 把输入框里的字变成数字。**空 / 非法一律当"没填"**（null），
  /// 而不是当 0 —— 0 会写进库里，变成"今天腰围 0 厘米"。
  double? _parsed(TextEditingController c) {
    final String t = c.text.trim();
    if (t.isEmpty) return null;
    final double? v = double.tryParse(t);
    return (v == null || v <= 0) ? null : v;
  }

  /// 收起键盘 + 取消焦点（「完成」按钮与"点空白"都走它）。
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() => _fieldFocused = false);
  }

  /// 表单里的一个小输入框（腰围 / 肌肉量 / 身高）。
  ///
  /// ⚠️ **名字必须常驻**（2026-10-09 第二份 docx 第 1 条：用户原话「指标填了数之后，
  /// 就不显示名称了」）：原来把名字写在 `hintText` 里，一输入就没了 ——
  /// 用户看着两个数字分不清哪个是腰围、哪个是肌肉量。现在名字是字段**上方**一行小字
  /// （`label`），`hintText` 只用来举例。
  Widget _smallField(String label, String key, TextEditingController c,
          {String? hint}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
          const SizedBox(height: Tokens.s1),
          TextField(
            key: Key(key),
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            // 点输入框以外的地方 → 收起键盘（第 3 条的另一半）
            onTapOutside: (_) => _dismissKeyboard(),
            style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsBody),
            decoration: appFieldDecoration(hint: hint),
          ),
        ],
      );

  /// 趋势卡（v1.52）：把最近记过的那几项画成一条线。
  ///
  /// 规则全在 `body_trend.dart`（纯计算，有单测），这里只管画：
  ///  * **一个点都不画** —— 记不到两次就不出现这张卡。画一条两个点的"趋势"是编故事，
  ///    而画一条平线会让人以为"我这段时间完全没变"。
  ///  * 切换器**只列画得出的指标** —— 列一个点了没反应的，等于给个假入口。
  ///  * 用 `ViAreaChart`（与「进步」页那张容量图同一个组件），不抄第二份画法。
  Widget _trendCard() {
    final List<BodyTrendMetric> available = trendMetrics(_recent);
    if (available.isEmpty) return const SizedBox.shrink();
    final BodyTrendMetric metric =
        available.contains(_trendMetric) ? _trendMetric : available.first;
    final BodyTrend trend = bodyTrend(_recent, metric);
    final double? delta = trend.delta;
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.s5),
      child: ViCard(
        key: const Key('body-trend'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text('身体数据趋势',
                      style: TextStyle(
                          color: Tokens.text,
                          fontSize: Tokens.fsSub,
                          fontWeight: Tokens.fwStrong)),
                ),
                ViSegmented(
                  key: const Key('body-trend-seg'),
                  labels: <String>[
                    for (final BodyTrendMetric m in available) m.label,
                  ],
                  current: available.indexOf(metric),
                  onChanged: (int i) =>
                      setState(() => _trendMetric = available[i]),
                ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            ViAreaChart(
              key: const Key('body-trend-chart'),
              points: trendPoints(trend.values),
              height: 110,
            ),
            const SizedBox(height: Tokens.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(shortDate(trend.firstDate),
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                // 首尾差：**带单位和正负号**，否则"掉了 2"读不出是 kg 还是 cm
                Text(
                  delta == null ? '' : trendDeltaText(metric, delta),
                  key: const Key('body-trend-delta'),
                  style: TextStyle(
                    color: delta != null && delta < 0
                        ? Tokens.success
                        : Tokens.text2,
                    fontSize: Tokens.fsMicro,
                  ),
                ),
                Text(shortDate(trend.lastDate),
                    style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: Tokens.s2),
              child: Text(
                '这条线只有 ${trend.samples.length} 次记录，'
                '${metric.label}的单位是 ${metric.unit}',
                key: const Key('body-trend-hint'),
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 摘要：当前体重 + BMI（含分档）+ 体脂 / 肌肉量 / 腰围。
  ///
  /// ⚠️ 有一项没记就**不摆那一格**，而不是摆一个「—」占位 ——
  /// 空格子会让人以为"我记过但是丢了"。
  Widget _summaryCard(BodyMetricData m) {
    final double? bmi = bmiOf(weightKg: m.weightKg, heightCm: _heightCm);
    final List<(String, String)> tiles = <(String, String)>[
      if (m.bodyFatPct != null) ('体脂率', '${m.bodyFatPct!.toStringAsFixed(1)} %'),
      if (m.muscleMassKg != null) ('肌肉量', '${m.muscleMassKg!.toStringAsFixed(1)} kg'),
      if (m.waistCm != null) ('腰围', '${m.waistCm!.toStringAsFixed(1)} cm'),
      ('BMI', bmiText(bmi)),
    ];
    return Container(
      key: const Key('body-summary'),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                m.weightKg == null
                    ? '还没记体重'
                    : formatBodyWeight(m.weightKg!, _unit),
                key: const Key('body-summary-weight'),
                style: Tokens.display(28, weight: 700, letterSpacing: Tokens.lsTight),
              ),
              const SizedBox(width: Tokens.s2),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(m.date, style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Wrap(
            spacing: Tokens.s3,
            runSpacing: Tokens.s2,
            children: <Widget>[
              for (final (String label, String value) in tiles)
                Column(
                  key: Key('body-tile-$label'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro)),
                    Text(value,
                        style: const TextStyle(
                            color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            bmi == null ? bmiHint(bmi) : 'BMI ${bmiText(bmi)} · ${bmiBand(bmi)} —— ${bmiHint(bmi)}',
            key: const Key('body-bmi-hint'),
            style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro, height: Tokens.lhSnug),
          ),
        ],
      ),
    );
  }

  /// 最近 7 天里**带体重**的记录有几条（用来判断"是不是称得太勤"）。
  ///
  /// ⚠️ 只数 `weightKg != null` 的：`body_metric` 里也可能只记腰围/肌肉量，
  /// 而"称体重"这件事问的是体重那一列。
  int _weighInsInLastWeek(List<BodyMetricData> rows) {
    // ⚠️ 用**这一页的钟**（`widget.clock`），不是 `DateTime.now()` ——
    // 这一页所有"今天"都由它决定（日期 chips、默认选中那一天），
    // 提醒的 7 天窗口要是自己另取一个"现在"，就会算出与页面对不上的结论
    // （测试里当场抓到：页面停在夹具那天、窗口却按真机时间算 → 一条都没数进去）。
    final DateTime now = _now;
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime from = today.subtract(const Duration(days: 6));
    return rows.where((BodyMetricData r) {
      if (r.weightKg == null) return false;
      final DateTime? d = DateTime.tryParse(r.date);
      if (d == null) return false;
      return !d.isBefore(from) && !d.isAfter(today);
    }).length;
  }

  /// 一周内称第二次了 —— 说一句事实，别让人以为"每天称"是我们希望的。
  ///
  /// 用户原话：「每天称体重意义不大」+「弹出**友情**提醒」——所以：
  ///   * 不是错误提示（没有红色、没有"禁止"），就一句"看趋势比看单天更有意义"；
  ///   * 结论来自真实身体数据：一天内的波动主要是水分与吃的东西，**不是脂肪**；
  ///   * 一个按钮「知道了」，点掉就走（不拦保存、不改数据）。
  Future<void> _maybeWarnWeighFrequency(int count) async {
    await showAppDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: Text('这周已经称过 $count 次了',
            style: const TextStyle(color: Tokens.text)),
        content: const Text(
          '一周称两次就够 —— 一天之内的波动主要是水分和刚吃的东西，不是脂肪。'
          '看一周、一个月的趋势比看单天更有意义。',
          key: Key('weigh-frequency-note'),
          style: TextStyle(color: Tokens.text2, height: Tokens.lhNormal),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('weigh-frequency-ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了', style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    await widget.repository.save(
      date: dayKey(_selected),
      weightKg: _parsedWeight,
      bodyFatPct: null, // 体脂本页不录（走「全部数据」/导入）；保留字段以免覆盖
      waistCm: _parsed(_waist),
      muscleMassKg: _parsed(_muscle),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    // 身高不是每日指标：存进 profile（只用来算 BMI）。填了才存，空着不动。
    final double? newHeight = _parsed(_height);
    if (newHeight != null && widget.profile != null) {
      await widget.profile!.setHeightCm(newHeight);
      _heightCm = newHeight;
    }

    // `body_metric_logged`：**保存成功之后**才报 —— 放在 `_load` 里会变成
    // "一打开页面就报记了一次体重"（第一次就是这么写错的，测试当场抓到）。
    // 只报"填没填"，数值一律不出设备（隐私政策 §6）。
    widget.analytics?.track('body_metric_logged', <String, Object?>{
      'has_weight': _parsedWeight != null,
      'has_note': _note.text.trim().isNotEmpty,
    });

    final List<BodyMetricData> recent = await widget.repository.recent();
    // ★ 一周称两次就够（10.8 清单第 1 / 4 条）：用户原话是
    //   「每天称体重意义不大，如果用户在一周内更新体重两次，弹出友情提醒」+
    //   「按照上面讲的，不建议每天称体重」。
    // 判据：这次保存之后，**最近 7 天里有 ≥ 2 条带体重的记录** → 说一声。
    // ⚠️ 只提醒、不拦、不改数据；语气是"说个事实"，不说教（见 `docs/copy.md`）。
    final int weekCount = _weighInsInLastWeek(recent);
    if (!mounted) return;
    setState(() {
      _recent = recent;
      // 摘要块跟着更新（刚记完的那条可能不是"最近一条有体重的"）
      _latest = recent.isEmpty ? null : recent.first;
      _saving = false;
    });
    if (weekCount >= 2) await _maybeWarnWeighFrequency(weekCount);
    widget.onSaved?.call();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已记录 ${dayKey(_selected)} 的身体数据'),
        backgroundColor: Tokens.elevated,
        // 浮动到保存按钮**上方**。默认贴底会盖住按钮 —— 用户发现填错了
        // 想立刻改一次，却点不到按钮（这个是被测试抓出来的）。
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, 88),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        // ⚠️ 这一层 `Focus` 只做一件事：**知道"有输入框正拿着焦点"** ——
        // 标题行那个「完成」靠它决定出不出（`onFocusChange` 对子孙节点的焦点变化也触发）。
        child: Focus(
          onFocusChange: (bool has) {
            if (has != _fieldFocused && mounted) {
              setState(() => _fieldFocused = has);
            }
          },
          child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('body-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '身体数据',
                      style: TextStyle(
                        color: Tokens.text,
                        fontSize: Tokens.fsHeadline,
                        fontWeight: Tokens.fwBold,
                      ),
                    ),
                  ),
                  // 键盘开着时给一个**看得见的出口**（第二份 docx 第 3 条）：
                  // iOS 数字键盘没有回车键，"点空白收起"又没人知道。
                  if (_fieldFocused)
                    TextButton(
                      key: const Key('body-keyboard-done'),
                      onPressed: _dismissKeyboard,
                      style: TextButton.styleFrom(foregroundColor: Tokens.accent),
                      child: const Text('完成'),
                    ),
                ],
              ),
            ),
            if (_consentPending)
              const Expanded(
                child: Center(
                  child: Text('先确认上面那条说明',
                      key: Key('body-consent-pending'),
                      style: TextStyle(color: Tokens.text3)),
                ),
              )
            else if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                // 这一页里有两个滚动体（纵向整页 + 「日期」那排横向 chips），
                // 所以给整页这个一个 key：测试里 `find.byType(ListView)` 会同时命中两个，
                // 拖拽/滚动就无从下手。有了名字，测试点的是"整页"而不是"某个 ListView"。
                child: ListView(
                  key: const Key('body-scroll'),
                  padding: const EdgeInsets.fromLTRB(
                      Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s6),
                  children: <Widget>[
                    // 摘要在最上面（2026-10-05）：进来第一眼该看到"现在是多少"。
                    // 没有记录时整块不出现。
                    if (_latest != null) ...<Widget>[
                      _summaryCard(_latest!),
                      const SizedBox(height: Tokens.s5),
                    ],

                    // 从系统健康库同步（2026-10-09，可选）。
                    // 放在摘要下面、正式录入之前 —— 它是"把别处已有的数拿过来"，
                    // 与"现在记一组"是两件事，所以单独一张卡，不混进输入区。
                    // ⚠️ **能不能读由平台回答**（iOS 走 HealthKit；安卓只有 14+ 能读平台自带的
                    // Health Connect）—— 平台说不能，入口根本不出现，不给做不到的承诺。
                    if (_healthAvailable && widget.profile != null) ...<Widget>[
                      _healthSyncCard(),
                      const SizedBox(height: Tokens.s5),
                    ],

                    // ══ 记这一天的 ═════════════════════════════════════════
                    //
                    // ⚠️ **2026-10-08（10.8 第二批第 3 条）重排**：用户原话是
                    // 「这一页的版式太乱了，重新设计下」。诊断：这一屏有 9 块东西
                    // **平铺**（摘要 / 趋势 / 日期 / 单位 / 体重 / 腰围+肌肉量 / 身高 /
                    // 备注 / 最近记录），块与块之间只有 3–5pt 的缝，**没有分组**，
                    // 于是"我要记今天的数"这件事被趋势卡与历史记录冲散了。
                    //
                    // 新结构只有三组，按**使用频次**排：
                    //   ① 记这一天的（日期 → 体重 → 更多指标 → 备注）—— 每天用
                    //   ② 看趋势（趋势卡）—— 每周看
                    //   ③ 最近记录（历史）—— 偶尔翻
                    // 摘要在最上面**只做一件事**：一眼看到现在的数。
                    _sectionTitle('记这一天的'),
                    const SizedBox(height: Tokens.s3),
                    // **在记哪一天**是上下文，不是输入项 —— 所以它紧跟标题，而不是
                    // 夹在"体重"与"腰围"之间（原来就在那个位置）。
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: <Widget>[
                          for (final DateTime d in _dayChoices) _dayChip(d),
                        ],
                      ),
                    ),
                    const SizedBox(height: Tokens.s2),
                    Text(
                      _selectedDayLabel,
                      key: const Key('body-day-label'),
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                    ),
                    const SizedBox(height: Tokens.s4),
                    // 体重与单位**同一张卡**：标签那一行右侧就是单位开关
                    //（原来单位单独占一行、上面还压着一个"体重"标签，重复了一遍）。
                    _weightCard(),
                    const SizedBox(height: Tokens.s4),
                    // 更多指标（都可选）：从属于"今天这一条记录"，所以在一张卡里
                    _moreMetricsCard(),
                    const SizedBox(height: Tokens.s3),
                    // 备注：名字**常驻**（与腰围/肌肉量同一个理由 —— 第二份 docx 第 1 条），
                    // 「（可选）」与例子留在 hint 里
                    const Text('备注',
                        style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
                    const SizedBox(height: Tokens.s1),
                    TextField(
                      key: const Key('body-note'),
                      controller: _note,
                      onTapOutside: (_) => _dismissKeyboard(),
                      maxLines: 2,
                      style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsSub),
                      decoration: appFieldDecoration(
                        hint: '可选，例如：空腹、练后',
                        contentPadding: const EdgeInsets.all(Tokens.s4),
                      ),
                    ),

                    // ══ 看趋势 ═════════════════════════════════════════════
                    if (trendMetrics(_recent).isNotEmpty) ...<Widget>[
                      const SizedBox(height: Tokens.s5),
                      _sectionTitle('看趋势'),
                      // `_trendCard` 自己带 top padding（原来它上面就是摘要卡）
                      _trendCard(),
                    ],

                    // ══ 最近记录 ═══════════════════════════════════════════
                    if (_recent.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Tokens.s4),
                      _sectionTitle('最近记录 · ${_recent.length} 条'),
                      const SizedBox(height: Tokens.s2),
                      for (final BodyMetricData r in _recent.take(10))
                        _historyRow(r),
                    ],

                    // ⚠️ 这里原来有两条**撤回同意**（身体数据 / 读系统健康）——
                    // 2026-10-09（第二份 docx 第 2 条）用户要求「撤回同意这种设置类的
                    // 入口全部收纳到设置里，这里不展示」，两条都搬去了
                    // 「设置 → 隐私与关于」的「撤回同意」一组（文案一个字没改）。
                    // 这一页留下的只有**征得同意**那道门（它必须留在收集发生的地方）。
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s4),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  key: const Key('body-save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _canSave ? Tokens.accent : Tokens.line,
                    foregroundColor: _canSave ? Tokens.accentInk : Tokens.text3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Tokens.rPill),
                    ),
                  ),
                  // 没填有效体重就不能存：存一条空的身体数据没有意义
                  onPressed: _canSave ? _save : null,
                  child: const Text('保存',
                      style: TextStyle(fontSize: Tokens.fsHeadline, fontWeight: Tokens.fwBold)),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _dayChip(DateTime d) {
    final String key = dayKey(d);
    final bool active = dayKey(_selected) == key;
    final bool isToday = key == dayKey(_now);
    return Padding(
      padding: const EdgeInsets.only(right: Tokens.s2),
      child: GestureDetector(
        key: Key('body-day-$key'),
        onTap: () async {
          setState(() => _selected = d);
          await _prefill();
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
          decoration: BoxDecoration(
            color: active ? Tokens.accent : Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.rPill),
          ),
          child: Text(
            isToday ? '今天' : formatDateAxis(d),
            style: TextStyle(
              color: active ? Tokens.accentInk : Tokens.text2,
              fontSize: Tokens.fsCap,
              fontWeight: active ? Tokens.fwBold : Tokens.fwBody,
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyRow(BodyMetricData r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(r.date,
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
          ),
          Text(
            r.weightKg == null
                ? '—'
                : formatBodyWeight(r.weightKg, _unit),
            style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsBodyS,
                fontWeight: Tokens.fwStrong),
          ),
          if (r.note != null && r.note!.isNotEmpty) ...<Widget>[
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Text(
                r.note!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 体重的单位开关（kg / lb / 斤）。
  ///
  /// ⚠️ **2026-10-10 用户：「选中胶囊还有没改的，你再查一下」** —— 查出来两处漏网，
  /// 这是其中一处：它当时还在用旧的 `GlassSegmentedRow`（iOS 26 那块玻璃底托 +
  /// 浅色选中胶囊），是"选中胶囊"里唯一没跟着改的两块之一。现在换成 `ViSegmented`：
  /// iOS 上一块真的 `UISegmentedControl`（选中 = **强调橙**，与周/月/年同款），
  /// 非 iOS 仍是老样子的实心胶囊（Android 一个像素都不动）。
  ///
  /// ⚠️ 它**自己不带"体重"标签、也不带 `Spacer`**（2026-10-08 重排改的）：
  /// 现在它贴在「体重」那张卡的标题行右侧，而**Row 的非弹性子项拿到的宽度约束是无界的** ——
  /// 里面再放 `Spacer`/`Expanded` 会当场抛
  /// `RenderFlex children have non-zero flex but incoming width constraints are unbounded`
  /// （重排时被 body_consent_test 那批测试抓到，14 条一起红）。
  /// 标签与右对齐现在由外层那个 Row（`_weightCard`）负责。
  Widget _weightUnitRow() {
    return ViSegmented(
      key: const Key('body-unit-row'),
      itemWidth: 52,
      labels: <String>[for (final BodyWeightUnit u in BodyWeightUnit.values) u.label],
      current: BodyWeightUnit.values.indexOf(_unit),
      // 标签是给人看的（`斤`），key 是给测试用的（`jin`）—— 所以 key 得自己给
      itemKey: (int i) => Key('body-unit-${BodyWeightUnit.values[i].wire}'),
      onChanged: (int i) => _switchUnit(BodyWeightUnit.values[i]),
    );
  }

  /// 分组标题（2026-10-08 重排新增）：这一页现在只有三组
  /// ——「记这一天的」「看趋势」「最近记录」。
  ///
  /// 与 `_label` 的区别：`_label` 是**块内**的小标签（"身高 cm"），
  /// 这个是**分组**标题 —— 所以字号更大、上面留白更多，而且下面带一条分隔线。
  Widget _sectionTitle(String text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            text,
            style: const TextStyle(
              color: Tokens.text,
              fontSize: Tokens.fsSub,
              fontWeight: Tokens.fwBold,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          // 分组标题下的分隔线：躺在 bg 上 → hair（VI 计划 T0-4 的页面级长分隔）
          const Divider(height: 1, color: Tokens.hair),
        ],
      );

  /// 「正在记哪一天」那行字：**把日期念成人话**（今天 / 昨天 / 10 月 5 日）。
  ///
  /// 为什么要有它：日期胶囊只写"10/5"，选中之后没有任何地方念一遍完整的那一天 ——
  /// 补录时最容易记错的就是"我到底在改哪一天"。
  String get _selectedDayLabel {
    final DateTime today = DateTime(_now.year, _now.month, _now.day);
    final int diff = today.difference(_selected).inDays;
    final String when = switch (diff) {
      0 => '今天',
      1 => '昨天',
      2 => '前天',
      _ => formatDateHuman(_selected),
    };
    return '正在记：$when（${formatDateHuman(_selected)}）';
  }

  /// 体重那一张卡：**标签 + 单位开关在同一行**，下面是大号输入框。
  ///
  /// 全页唯一的必填项 —— 所以它占满宽度、字号最大（24pt），单位开关就贴在它右边。
  Widget _weightCard() => ViCard(
        key: const Key('body-weight-card'),
        padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s4, Tokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text('体重',
                    style: TextStyle(
                        color: Tokens.text,
                        fontSize: Tokens.fsSub,
                        fontWeight: Tokens.fwStrong)),
                const Spacer(),
                _weightUnitRow(),
              ],
            ),
            const SizedBox(height: Tokens.s2),
            TextField(
              key: const Key('body-weight'),
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => _dismissKeyboard(),
              style: const TextStyle(
                  color: Tokens.text, fontSize: Tokens.fsNumL, fontWeight: Tokens.fwBold),
              // 这一个本来就在卡片里，所以底用 `bg`（下沉的井）—— 边界照旧走 lineStrong
              decoration: appFieldDecoration(
                hint: '例如 72.5',
                fontSize: Tokens.fsHeadline,
                fill: Tokens.bg,
              ),
            ),
          ],
        ),
      );

  /// 更多指标（都可选）：腰围 / 肌肉量 / 身高。
  ///
  /// 它们与体重是**同一天同一条记录**的几个字段 —— 所以在一张卡里，
  /// 而且明确写着"可选"：不填也能保存（可保存性由体重决定）。
  Widget _moreMetricsCard() => ViCard(
        key: const Key('body-more-metrics'),
        padding: const EdgeInsets.fromLTRB(Tokens.s4, Tokens.s3, Tokens.s4, Tokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('更多指标（可选）',
                style: TextStyle(
                    color: Tokens.text2,
                    fontSize: Tokens.fsCap,
                    fontWeight: Tokens.fwStrong)),
            const SizedBox(height: Tokens.s3),
            Row(
              children: <Widget>[
                Expanded(
                    child: _smallField('腰围 cm', 'body-waist', _waist,
                        hint: '例如 82')),
                const SizedBox(width: Tokens.s3),
                Expanded(
                    child: _smallField('肌肉量 kg', 'body-muscle', _muscle,
                        hint: '例如 34.5')),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            // 身高只用来算 BMI，说清楚（不然用户以为它也是"今天的体重数据"）
            _smallField('身高 cm', 'body-height', _height,
                hint: '只用来算 BMI'),
          ],
        ),
      );

}
