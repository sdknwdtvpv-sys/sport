/// 练了么 · 兑换页（M4a，**只有非 iOS 渠道有自建码输入**）
///
/// 平台边界（`docs/plan-membership-2026-10-10.md` §6.3，这条是硬的）：
///
///   * **iOS**：不允许出现自建码输入框（Apple 3.1.1 明确禁止"用自己的机制解锁内容/功能"）。
///     苹果自己的 Offer Code 兑换面板留到 M4b；这一版**不做假的**，只如实写一句"在 App Store 兑换"。
///   * **Android / 国内渠道**：显示输入框，把码发到 `POST /v1/billing/redeem` 在线核销。
///
/// 这一屏在 `kUltraReleased == false` 时从应用里进不来（会员页本身不可达）；
/// 测试直接 pump 它，用 `debugDefaultTargetPlatformOverride` 钉住平台分支。
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/entitlement_repository.dart';
import 'billing_server.dart';
import 'entitlement.dart';
import 'paywall_copy.dart';

/// 这一版是不是 iOS（抽成函数是为了让测试与调用点用同一份判断）。
bool isIosPlatform() => defaultTargetPlatform == TargetPlatform.iOS;

class RedeemScreen extends StatefulWidget {
  const RedeemScreen({
    super.key,
    required this.client,
    this.repository,
    this.now,
  });

  /// 服务端计费客户端（真身 / 测试注入假 API 都行）。null 不该被打开。
  final BillingServerClient client;

  final EntitlementRepository? repository;
  final DateTime Function()? now;

  @override
  State<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends State<RedeemScreen> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _error;
  UltraAccess? _access;
  String? _success;

  int get _nowMs => (widget.now ?? DateTime.now)().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    final EntitlementRepository? repo = widget.repository;
    if (repo == null) return;
    final UltraAccess access = await repo.access(_nowMs);
    if (!mounted) return;
    setState(() => _access = access);
  }

  Future<void> _redeem() async {
    if (_busy) return;
    final String code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请先输入兑换码。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    final RedeemResult result = await widget.client.redeem(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.ok ? null : (result.message ?? '兑换失败，请稍后再试。');
      _success = result.ok ? (result.message ?? '兑换成功，Ultra 已开通。') : null;
      if (result.ok) _code.clear();
    });
    if (result.ok) await _loadAccess();
  }

  @override
  Widget build(BuildContext context) {
    final bool ios = isIosPlatform();
    return Scaffold(
      backgroundColor: Tokens.bg,
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        title: const Text('兑换码'),
        foregroundColor: Tokens.text,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.s5),
        children: <Widget>[
          const Text(
            '兑换 Ultra',
            style: TextStyle(
              color: Tokens.text,
              fontSize: Tokens.fsTitle,
              fontWeight: Tokens.fwStrong,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          if (ios)
            const Text(
              'iOS 上的兑换请使用 App Store 的「兑换礼品卡或代码」功能。'
              '在应用内直接输入我们自己印的码，是不符合 App Store 审核规则的 —— 所以这里不放输入框。',
              key: Key('redeem-ios-note'),
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            )
          else ...<Widget>[
            const Text(
              '输入你从国内渠道拿到的兑换码（LMU 开头，不区分大小写）。',
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            ),
            const SizedBox(height: Tokens.s4),
            TextField(
              key: const Key('redeem-code-field'),
              controller: _code,
              enabled: !_busy,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '兑换码',
                hintText: 'LMU-XXXXX-XXXXX-XXXXX-XXXXX',
              ),
              onSubmitted: (_) => _redeem(),
            ),
            const SizedBox(height: Tokens.s3),
            FilledButton(
              key: const Key('redeem-submit'),
              onPressed: _busy ? null : _redeem,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('兑换'),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            Text(
              _error!,
              key: const Key('redeem-error'),
              style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            ),
          ],
          if (_success != null) ...<Widget>[
            const SizedBox(height: Tokens.s3),
            Text(
              _success!,
              key: const Key('redeem-success'),
              style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            ),
          ],
          if (_access != null) ...<Widget>[
            const SizedBox(height: Tokens.s4),
            Text(
              PaywallCopy.statusLine(_access!, expiresOn: null),
              key: const Key('redeem-status'),
              style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub, height: Tokens.lhNormal),
            ),
          ],
        ],
      ),
    );
  }
}
