/// 练了么 · **身份**（昵称 + 账号 ID）—— 2026-10-07，v1.60.0
///
/// 用户原话："**现在账户只展示【我】，没办法有用户的名字，很难有身份感。能不能昵称+ID？**"
///
/// 这一屏把两件**性质完全不同**的东西摆在一起，并且把它们的边界写清楚：
///
///   * **昵称**：纯本地、你自己起、随时改。不进云备份的合并键、不上报、不做分享名片。
///     没设过就如实写"还没设昵称"（**不编默认名** —— 编一个"健身达人"比空白更糟）。
///   * **ID**：**只有登录之后才存在**，它是账号密钥的哈希前缀（`account_id` 前 8 位，
///     分组写成 `A3F9-21C4`），用于找回与客服核对。**没登录就不显示 ID** ——
///     凭空编一个号既不是账号也不是设备号，那是假身份。
///
/// 昵称存 `user_profile.nickname`（v24 加的列），写入走 `ProfileRepository.setNickname`。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vi_cards.dart';
import '../../data/profile_repository.dart';
import 'profile_widgets.dart';

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({
    super.key,
    required this.profile,
    this.accountId,
    this.email,
  });

  final ProfileRepository profile;

  /// 登录后才有（`auth_session.account_id`）。null = 没登录。
  final String? accountId;

  /// 登录用的邮箱（只用来显示"你登录的是哪个账号"，不改不删）。
  final String? email;

  /// `account_id` → 界面上那个 `A3F9-21C4`。
  ///
  /// 取**前 8 位十六进制**再分组：短到能念出来（客服核对时用户能抄），
  /// 又长到不会撞（32 bit）。⚠️ 它是**公开标识**，不是秘密 —— 真正的密钥是
  /// 设备上那份 `account_key`，从不离开手机。
  static String shortId(String accountId) {
    final String hex = accountId.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toUpperCase();
    final String head = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '·');
    return '${head.substring(0, 4)}-${head.substring(4, 8)}';
  }

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String? n = await widget.profile.nickname();
    if (!mounted) return;
    setState(() {
      if (n != null) _controller.text = n;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.profile.setNickname(_controller.text);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final String? id = widget.accountId;
    return ProfileSubPage(
      title: '身份',
      children: <Widget>[
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Tokens.s5),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...<Widget>[
          profileSectionTitle('昵称'),
          settingsCard(<Widget>[
            Padding(
              padding: const EdgeInsets.all(Tokens.s3),
              child: TextField(
                key: const Key('nickname-field'),
                controller: _controller,
                maxLength: 16,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsBodyS),
                decoration: const InputDecoration(
                  hintText: '怎么称呼你？（只存在这台手机上）',
                  hintStyle: TextStyle(color: Tokens.text3, fontSize: Tokens.fsSub),
                  border: InputBorder.none,
                ),
              ),
            ),
          ]),
          const SizedBox(height: Tokens.s2),
          // 一句实话：昵称是给**你自己**看的，它不参与任何身份判定。
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Tokens.s1),
            child: Text(
              '昵称只存在这台手机上，不上传、不参与找回归档。',
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
            ),
          ),
          const SizedBox(height: Tokens.s5),
          profileSectionTitle('账号 ID'),
          ViCard(
            key: const Key('identity-id-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  id == null ? '还没登录' : IdentityScreen.shortId(id),
                  key: const Key('identity-id'),
                  style: TextStyle(
                    color: id == null ? Tokens.text3 : Tokens.text,
                    fontSize: id == null ? 15 : 22,
                    fontWeight: Tokens.fwBold,
                    letterSpacing: id == null ? 0 : 1.2,
                  ),
                ),
                const SizedBox(height: Tokens.s2),
                Text(
                  id == null
                      // 没登录就不显示 ID —— 不编一个号出来（编出来的既不是账号也不是设备号）
                      ? 'ID 只在登录之后才有。注册后可跨设备取回数据；不注册也能用全部功能。'
                      : '登录的邮箱：${widget.email ?? '（这台设备上没记邮箱）'}\n'
                          '这个 ID 用于找回与客服核对；它由账号密钥算出来，密钥本身从不离开这台手机。',
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s5),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              key: const Key('nickname-save'),
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.accent,
                foregroundColor: Tokens.bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.rPill),
                ),
              ),
              child: const Text('保存'),
            ),
          ),
        ],
      ],
    );
  }
}
