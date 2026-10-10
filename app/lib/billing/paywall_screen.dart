/// 练了么 · **会员页（S14）**（M1）
///
/// 施工图：`docs/plan-membership-2026-10-10.md` §二（卖什么）、§三（商品与价格）、
/// §7.1（付费墙必须披露什么）。本屏的职责只有四个：**说清权益、说清价格与续费、
/// 让用户能买、让用户能退回来**（恢复购买 / 管理订阅 / 条款 / 隐私政策）。
///
/// 五条设计约束（都来自既有文档，不是这里的发明）：
///
///   1. **一屏只准一个 accent**（`accent_budget_test`）：只有推荐那一档的按钮是橙底，
///      其余是描边。橙底一律用 `accentInk` 写字（对比度）。
///   2. **价格只能来自商店**（`paywall_copy.dart` 的 `PaywallCatalog`）：
///      拿不到商品就**如实说拿不到**，绝不硬编码一个价格 —— 那会与 App Store 不一致，
///      而"界面价格与内购项不一致"是明确的拒审理由。
///   3. **不做全屏拦截**：这一屏只能从「设置」或被锁的那一处主动进来；
///      训练路径上不许出现付费入口（`free_red_line_test.dart` 扫源码钉住）。
///   4. **降级要说人话**：到期/退款/宽限期各有各的说法（`PaywallCopy.statusLine`），
///      并且**反复讲清"你的数据一条没少"** —— 那是用户此刻唯一真正担心的事。
///   5. **可测**：仓库与商品目录都从构造参数进来，测试注入假目录即可断言 3.1.2 那六项。
library;

import 'package:flutter/material.dart';

import '../core/icon_spec.dart';
import '../core/theme.dart';
import '../core/units.dart';
import '../data/entitlement_repository.dart';
import '../features/profile/privacy_policy_screen.dart';
import '../features/profile/profile_widgets.dart';
import 'entitlement.dart';
import 'paywall_copy.dart';
import 'subscription_terms_screen.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.repository,
    this.catalog = const UnavailablePaywallCatalog(),
    this.now,
  });

  final EntitlementRepository repository;

  /// 商品目录。**M1 默认拿不到商品**（真商店在 M2）；
  /// 调试走查用 `debug_grant.dart` 里的假目录（只在 debug 构建里存在）。
  final PaywallCatalog catalog;

  /// 便于测试固定"现在"
  final DateTime Function()? now;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  UltraAccess _access = UltraAccess.free;
  List<UltraProductView> _products = const <UltraProductView>[];
  bool _loading = true;

  int get _nowMs => (widget.now ?? DateTime.now)().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final UltraAccess access = await widget.repository.access(_nowMs);
    final List<UltraProductView> products = await widget.catalog.load();
    if (!mounted) return;
    setState(() {
      _access = access;
      _products = products;
      _loading = false;
    });
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => ProfileSubPage(
        title: PaywallCopy.title,
        children: <Widget>[
          // ── 状态与定位 ────────────────────────────────────────────────
          Text(
            PaywallCopy.statusLine(_access, expiresOn: _expiresOn()),
            key: const Key('ultra-status'),
            style: const TextStyle(
              color: Tokens.text,
              fontSize: Tokens.fsSub,
              height: Tokens.lhNormal,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            PaywallCopy.tagline,
            style: const TextStyle(
              color: Tokens.text3,
              fontSize: Tokens.fsCap,
              height: Tokens.lhNormal,
            ),
          ),
          const SizedBox(height: Tokens.s5),

          // ── 权益清单（先写免费版就有的）────────────────────────────────
          profileSectionTitle('权益'),
          settingsCard(<Widget>[
            for (final PaywallBenefit b in kPaywallBenefits)
              _benefitRow(b),
          ]),
          const SizedBox(height: Tokens.s5),

          // ── 价格与购买（价格**只来自商店**）────────────────────────────
          profileSectionTitle('价格'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Tokens.s4),
              child: SizedBox(
                height: 20,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            )
          else if (_products.isEmpty)
            Text(
              PaywallCopy.unavailable,
              key: const Key('ultra-unavailable'),
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub),
            )
          else
            for (final UltraProductView p in _products) _productRow(p),

          if (_products.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.s4),
            // ── 续费与试用说明（3.1.2 + 审核惯例；**不许删**）──────────
            _disclosure(),
          ],

          const SizedBox(height: Tokens.s5),

          // ── 退回来的路：恢复购买 / 管理订阅 ───────────────────────────
          settingsCard(<Widget>[
            navTile(
              key: const Key('restore-purchases'),
              title: PaywallCopy.restore,
              subtitle: '换手机、重装之后用它把权益找回来',
              onTap: _restore,
            ),
            const Divider(height: 1, color: Tokens.line),
            navTile(
              key: const Key('manage-subscription'),
              title: PaywallCopy.manage,
              subtitle: PaywallCopy.manageHint,
              onTap: _manage,
            ),
            const Divider(height: 1, color: Tokens.line),
            navTile(
              key: const Key('open-subscription-terms'),
              title: PaywallCopy.terms,
              subtitle: '续期、取消、退款都写在这里',
              onTap: () => _open(const SubscriptionTermsScreen()),
            ),
            const Divider(height: 1, color: Tokens.line),
            // Apple 3.1.2(c) 要的两个链接之一：**隐私政策必须在 App 内可达**。
            // 它就是我们随包那份政策（与公网页面同源，`privacy_policy_screen.dart` 有防漂守卫）。
            navTile(
              key: const Key('open-privacy-from-paywall'),
              title: PaywallCopy.privacy,
              subtitle: '我们收集什么、不收集什么',
              onTap: () => _open(const PrivacyPolicyScreen()),
            ),
          ]),
          const SizedBox(height: Tokens.s4),
          Text(
            PaywallCopy.lifetimeScope,
            key: const Key('ultra-lifetime-scope'),
            style: const TextStyle(
              color: Tokens.text3,
              fontSize: Tokens.fsMicro,
              height: Tokens.lhNormal,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            PaywallCopy.minors,
            style: const TextStyle(
              color: Tokens.text3,
              fontSize: Tokens.fsMicro,
              height: Tokens.lhNormal,
            ),
          ),
        ],
      );

  String? _expiresOn() {
    final int? left = _access.msLeft;
    if (left == null) return null;
    final DateTime d = DateTime.fromMillisecondsSinceEpoch(_nowMs + left);
    return formatDateHuman(d, withYear: true);
  }

  Widget _benefitRow(PaywallBenefit b) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s5, vertical: Tokens.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              b.ultraOnly ? Icons.workspace_premium_outlined : Icons.check,
              color: b.ultraOnly ? Tokens.text2 : Tokens.success,
              size: IconSpec.m,
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Text(
                b.ultraOnly ? '${b.title}（Ultra）' : b.title,
                style: TextStyle(
                  color: b.ultraOnly ? Tokens.text : Tokens.text2,
                  fontSize: Tokens.fsSub,
                  height: Tokens.lhNormal,
                ),
              ),
            ),
          ],
        ),
      );

  /// 一档商品：标题 + 时长 + **商店给的价格** + 一个按钮。
  /// 推荐档是这一屏**唯一**的 accent 按钮（`accent_budget_test` 管着这件事）。
  Widget _productRow(UltraProductView p) {
    final bool primary = p.recommended;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: settingsCard(<Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s5, Tokens.s5, Tokens.s3),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      p.title,
                      key: Key('product-title-${p.product.name}'),
                      style: const TextStyle(
                        color: Tokens.text,
                        fontSize: Tokens.fsBodyS,
                        fontWeight: Tokens.fwStrong,
                      ),
                    ),
                    const SizedBox(height: Tokens.s1),
                    Text(
                      p.hasTrial ? '${p.duration} · 前 ${p.trialDays} 天免费' : p.duration,
                      style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
                    ),
                  ],
                ),
              ),
              Text(
                p.priceLabel,
                key: Key('product-price-${p.product.name}'),
                style: const TextStyle(
                  color: Tokens.text,
                  fontSize: Tokens.fsNum,
                  fontWeight: Tokens.fwBold,
                  fontFeatures: Tokens.tabular,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s5, 0, Tokens.s5, Tokens.s5),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: primary
                ? FilledButton(
                    key: Key('buy-${p.product.name}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.accent,
                      foregroundColor: Tokens.accentInk,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.rPill),
                      ),
                    ),
                    onPressed: () => _buy(p),
                    child: const Text('开通 Ultra',
                        style: TextStyle(fontSize: Tokens.fsBodyS, fontWeight: Tokens.fwBold)),
                  )
                : OutlinedButton(
                    key: Key('buy-${p.product.name}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Tokens.text,
                      side: const BorderSide(color: Tokens.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.rPill),
                      ),
                    ),
                    onPressed: () => _buy(p),
                    child: const Text('选择这一档',
                        style: TextStyle(fontSize: Tokens.fsBodyS)),
                  ),
          ),
        ),
      ]),
    );
  }

  /// 3.1.2 + 审核惯例要的那几行（**唯一出处是 `PaywallCopy`**，测试逐条断言）
  Widget _disclosure() => Container(
        key: const Key('ultra-disclosure'),
        // ⚠️ 卡片内边距只能是 s5（`spacing_grid_test` 判据 2 钉着这件事：
        // 手搓的卡片用 s4，就会与 `navTile`/ListTile 主题的 s5 差 4pt —— 同一个毛病低了一层）
        padding: const EdgeInsets.all(Tokens.s5),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rCard),
          border: Border.all(color: Tokens.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final String line in <String>[
              PaywallCopy.autoRenew,
              PaywallCopy.chargedToAppleId,
              PaywallCopy.trialForfeited,
              PaywallCopy.renewReminder,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Tokens.s2),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: Tokens.text2,
                    fontSize: Tokens.fsMicro,
                    height: Tokens.lhNormal,
                  ),
                ),
              ),
          ],
        ),
      );

  /// M1 里买不了（真内购在 M2）：**如实告诉用户**，而不是摆一个点了没反应的按钮
  void _buy(UltraProductView p) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('内购正在接入（${p.title}），这一版还不能真的购买。'),
        backgroundColor: Tokens.elevated,
      ),
    );
  }

  void _restore() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('内购正在接入，恢复购买会在同一版里上线。'),
        backgroundColor: Tokens.elevated,
      ),
    );
  }

  void _manage() {
    // M1 用应用内说明（不引外部依赖）；M2 换成跳转 Apple 的订阅管理页。
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: const Text('管理订阅', style: TextStyle(color: Tokens.text)),
        content: const Text(
          '取消或更改订阅请到 App Store：\n\n打开 App Store → 点右上角你的头像 → 订阅 → 选择练了么。\n\n'
          '取消之后，当前已付周期结束前仍然可以继续用 Ultra。',
          style: TextStyle(color: Tokens.text2, height: Tokens.lhNormal),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('manage-close'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
