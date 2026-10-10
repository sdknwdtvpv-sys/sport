/// 练了么 · 会员页（S14）的**文案与商品视图模型** —— 全站唯一出处
///
/// 为什么单独一个文件：付费墙上有几行字**不是文案偏好，是合规要求**
/// （`docs/plan-membership-2026-10-10.md` §7.1 第 2 条 / Apple Schedule 2 §3.8(b)）：
/// 订阅**标题**、**时长**、**价格**、**条款链接**、**隐私政策链接**，外加审核惯例那四条
/// （24 小时取消、费用计入 Apple ID、未用试用作废、恢复购买可见）。
/// 它们散在界面代码里，改版时最容易"顺手删掉一行"—— 所以集中在这里，
/// 由 `app/test/paywall_copy_test.dart` **逐条断言**。
///
/// 另一条硬规矩：**价格只能来自商店**（Apple 要求界面价格与应用内购买项一致）。
/// 于是商品信息走 [PaywallCatalog] 接口：M2 接真商店，M1 用 [UnavailablePaywallCatalog]
/// （拿不到就如实说"获取不到"，**不许硬编码一个价格**）。
library;

import 'entitlement.dart';

/// 一个商品的展示要素（价格与时长都来自商店返回值，不在这里编）。
class UltraProductView {
  const UltraProductView({
    required this.id,
    required this.product,
    required this.title,
    required this.duration,
    required this.priceLabel,
    this.trialDays,
    this.recommended = false,
  });

  /// 商店商品 ID（一旦创建不能改，见方案 §3.1）
  final String id;
  final UltraProduct product;

  /// 「Ultra 年订阅」
  final String title;

  /// 「1 年」/「每月」/「一次性」
  final String duration;

  /// 商店给的本地化价格（「¥98.00」/「$14.99」）。**不许自己拼**。
  final String priceLabel;

  /// 免费试用天数（没有就是 null）
  final int? trialDays;

  /// 是否是这一屏推荐的那一档（推荐档是**唯一**用 accent 的那个按钮）
  final bool recommended;

  bool get hasTrial => trialDays != null && trialDays! > 0;
}

/// 商品目录：M1 只有一个"拿不到"的实现，M2 换成真商店（`in_app_purchase`）。
abstract class PaywallCatalog {
  Future<List<UltraProductView>> load();
}

/// 「现在拿不到商品」—— **release 在 M1 阶段就是这个**。
///
/// 界面此时**不显示任何价格**、也不显示购买按钮（宁可不卖，也不编一个价格），
/// 只写一行"暂时获取不到商品信息"。
class UnavailablePaywallCatalog implements PaywallCatalog {
  const UnavailablePaywallCatalog();

  @override
  Future<List<UltraProductView>> load() async => const <UltraProductView>[];
}

/// 权益清单里的一行
class PaywallBenefit {
  const PaywallBenefit(this.title, {this.ultraOnly = false, this.note});

  final String title;

  /// true = 只有 Ultra 有；false = 免费版也有（写出来是为了让用户看清"免费版已经够用"）
  final bool ultraOnly;
  final String? note;
}

/// 付费墙上的**每一句用户可见文案**。
class PaywallCopy {
  const PaywallCopy._();

  static const String title = '练了么 Ultra';

  /// 顶部一句定位（不卖功能点、卖省心 —— 与 `PRODUCT.md` §8 同一口径）
  static const String tagline = '记录永远免费。Ultra 让数据更省心：云端有历史，分析看得更远。';

  // ── Apple 3.1.2 / Schedule 2 §3.8(b) 要的五项（标题/时长/价格由商品给）──
  static const String terms = '订阅条款';
  static const String privacy = '隐私政策';

  /// 审核惯例那四条里的三条（24 小时、计入 Apple ID、试用作废）
  static const String autoRenew = '订阅会自动续期，除非在当前周期结束前 24 小时取消。';
  static const String chargedToAppleId = '费用在你确认购买时计入你的 Apple ID。';
  static const String trialForfeited = '未使用的试用期，在你购买之后作废。';

  /// 中国大陆：自动续费提醒（《互联网平台价格行为规则》要求每次扣款前显著提醒）
  static const String renewReminder = '每次扣费前 5 天，我们会在这里提醒你一次（写清时间、金额和怎么取消）。';

  /// 恢复购买 / 管理订阅（Apple 两条硬要求）
  static const String restore = '恢复购买';
  static const String manage = '管理订阅';
  static const String manageHint = '也可以自己取消：App Store → 右上角头像 → 订阅。';

  /// 未成年人（《未成年人网络保护条例》第四十四/四十五条）
  static const String minors = '未成年人请在监护人同意后购买。';

  /// 终身版到底含什么（方案 §3.2：云有持续成本，"终身含无限云"是卖欠条）
  static const String lifetimeScope =
      '终身版含本地全部能力 + 1 份云备份（8 MB）。云端的多版本与更大容量只在订阅期内提供。';

  /// 拿不到商品时如实说（不编价格、不放一个点了没反应的按钮）
  static const String unavailable = '暂时获取不到商品信息，请稍后再试。';

  /// 已开通时顶部那行状态（`UltraAccess` → 人话）
  static String statusLine(UltraAccess a, {required String? expiresOn}) {
    switch (a.state) {
      case UltraState.none:
        return '你还没有开通 Ultra。';
      case UltraState.trial:
        return expiresOn == null ? '试用中。' : '试用中，到 $expiresOn 结束。';
      case UltraState.active:
        return expiresOn == null ? 'Ultra · 终身。' : 'Ultra，有效期到 $expiresOn。';
      case UltraState.grace:
        return '自动续费没有成功，App Store 正在宽限期内重试；这期间 Ultra 照常可用。';
      case UltraState.billingRetry:
        return '自动续费没有成功，App Store 还在重试；这期间 Ultra 照常可用。';
      case UltraState.expired:
        return '订阅已到期。你的数据一条没少，续费或恢复购买即可继续用 Ultra 的能力。';
      case UltraState.refunded:
        return '这笔购买已退款，Ultra 已停用。';
      case UltraState.revoked:
        return '这笔购买已被撤销，Ultra 已停用。';
    }
  }
}

/// 权益清单（免费 vs Ultra）。**顺序是有意的**：先写免费版就有的，
/// 让"免费版已经够用"这件事一眼可见 —— 这是我们与付费墙之间唯一的道德约束。
const List<PaywallBenefit> kPaywallBenefits = <PaywallBenefit>[
  PaywallBenefit('记录训练、历史、身体数据'),
  PaywallBenefit('导出自己的数据（CSV / 完整备份）'),
  PaywallBenefit('分享卡、周报卡、成就徽章'),
  PaywallBenefit('云备份：最新 1 份（8 MB）'),
  PaywallBenefit('云备份历史：最近 10 份，可恢复到任意一份', ultraOnly: true),
  PaywallBenefit('云备份容量：单份 32 MB，账号 256 MB', ultraOnly: true),
  PaywallBenefit('进阶分析：分动作趋势、周/月/季对比', ultraOnly: true),
  PaywallBenefit('批量整理历史：多选改动作、批量移到回收站', ultraOnly: true),
  PaywallBenefit('导出进阶：训练年报卡、按动作拆分', ultraOnly: true),
];
