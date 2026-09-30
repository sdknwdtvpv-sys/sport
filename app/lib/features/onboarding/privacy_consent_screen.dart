/// 练了么 · 首次启动的隐私政策同意
///
/// **这一屏是法律要求，不是产品偏好**。小米应用商店《隐私政策不合规的问题解析和修改指引》
/// 对"首次启动"写得很具体（规则来源：国信办秘字〔2019〕191 号）：
///
///   * 应用需要在**首次运行时以主动弹窗等明显方式**提示用户阅读隐私政策，并**征得同意**；
///   * 同意环节必须提供**明确的"同意"和"拒绝"两个按钮**，
///     且**不得使用"好的""我知道了"**这类模棱两可的措辞；
///   * **不得默认勾选**代表同意的选框，也不得"点登录/同意按钮就等于勾上了"；
///   * 同意之前**不得收集任何个人信息**。
///
/// 对应的三条实现决定：
///
///   1. **两个按钮就是同意与拒绝**（`同意并继续` / `不同意`），不搞勾选框 ——
///      没有勾选框就不可能"默认勾选"，也不会出现"点按钮等于勾上"的争议。
///   2. **同意之前不起埋点、不上报**：`main.dart` 里 `_initAnalytics()` 被挪到同意之后。
///      我们的默认包里本来就没有上报地址（`_NullTransport`），但规矩是规矩。
///   3. **拒绝不等于"卡死"**：给出"再看一遍政策"和"退出"两条路 —— 拒绝后应用不做任何
///      收集，也不该假装能用。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../../core/theme.dart';
import '../profile/privacy_policy_screen.dart';

class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({
    super.key,
    required this.onAgree,
    this.nowMs,
  });

  /// 用户点了「同意并继续」。调用方负责落库并放行主界面。
  final Future<void> Function() onAgree;

  /// 便于测试固定时间
  final int Function()? nowMs;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  /// 用户点了「不同意」之后进入的状态（不是退出，而是把话说清楚）
  bool _refused = false;
  bool _busy = false;

  Future<void> _agree() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAgree();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPolicy() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext ctx) => const PrivacyPolicyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s6, Tokens.s5, Tokens.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: Tokens.s6),
              const Text(
                '练了么',
                style: TextStyle(
                  color: Tokens.volt,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: Tokens.s3),
              Text(
                _refused ? '你选择了不同意' : '开始之前，请先看一下隐私政策',
                key: const Key('consent-title'),
                style: const TextStyle(
                  color: Tokens.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: Tokens.s4),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _refused
                        ? '不同意也可以 —— 这不会影响你手机上的任何东西，因为同意之前我们什么都不收集。\n\n'
                            '但练了么目前没有"不同意也能用"的模式：所有功能都在本地跑，'
                            '而隐私政策要说明的正是这些本地数据怎么处理。\n\n'
                            '如果你想再看一遍政策，点下面的按钮；想好了也可以随时回来同意。'
                        : '我们不会要求注册、不要手机号、不要定位、不读通讯录。\n\n'
                            '你的训练记录只存在这台手机上。唯一的联网行为是'
                            '「帮助改进产品」的匿名使用统计 —— 那个开关默认开着，'
                            '可以随时在「我」页关掉，关了功能完全不受影响。\n\n'
                            '详细的收集范围、用途与你的权利，都写在隐私政策里。',
                    key: const Key('consent-body'),
                    style: const TextStyle(color: Tokens.text2, fontSize: 14, height: 1.8),
                  ),
                ),
              ),
              TextButton(
                key: const Key('consent-read-policy'),
                onPressed: _openPolicy,
                child: const Text(
                  '阅读《隐私政策》',
                  style: TextStyle(color: Tokens.volt, fontSize: 15),
                ),
              ),
              const SizedBox(height: Tokens.s3),
              // 两个按钮就是**明确的同意与拒绝**：不设勾选框，也就不存在"默认勾选"
              // 或"点按钮等于勾上"这两种被明确禁止的形态。
              SizedBox(
                height: 52,
                child: TextButton(
                  key: const Key('consent-agree'),
                  onPressed: _busy ? null : _agree,
                  style: TextButton.styleFrom(
                    backgroundColor: Tokens.volt,
                    foregroundColor: Tokens.voltInk,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Tokens.rPill),
                    ),
                  ),
                  child: const Text('同意并继续',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: Tokens.s3),
              if (_refused)
                SizedBox(
                  height: 44,
                  child: TextButton(
                    key: const Key('consent-exit'),
                    // 拒绝之后**不做任何收集**，也不假装能用 —— 如实退出
                    onPressed: () => SystemNavigator.pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: Tokens.elevated,
                      foregroundColor: Tokens.text2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.rPill),
                      ),
                    ),
                    child: const Text('退出练了么', style: TextStyle(fontSize: 14)),
                  ),
                )
              else
                SizedBox(
                  height: 44,
                  child: TextButton(
                    key: const Key('consent-refuse'),
                    onPressed: _busy ? null : () => setState(() => _refused = true),
                    style: TextButton.styleFrom(
                      backgroundColor: Tokens.elevated,
                      foregroundColor: Tokens.text2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Tokens.rPill),
                      ),
                    ),
                    child: const Text('不同意', style: TextStyle(fontSize: 14)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
