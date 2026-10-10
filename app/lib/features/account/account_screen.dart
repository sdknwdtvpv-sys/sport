/// 练了么 · 账号（邮箱 + 口令）
///
/// **形态是"可选"**（2026-10-06 用户拍板，见 `docs/plan-account-login.md` §〇）：
/// 不登录 = 今天的样子（全功能可用、数据只在本机）；这个页面是"想要云备份 /
/// 换手机能找回"的人**主动选**的那条路。**没有启动闸门** —— 不登录照样能用。
///
/// ## 界面上必须讲清楚的三件事
///
/// 1. **口令不会离开这台手机**。发出去的是口令派生出来的认证凭据与一把"包起来的钥匙"，
///    服务端两样都推不出账号密钥 —— 所以"服务端读不到你的训练数据"这句话加了账号之后仍然成立。
/// 2. **恢复码是账号的上一级**：忘了口令时，靠"恢复码 + 邮箱验证码"重设一个新口令；
///    恢复码丢了、口令也忘了，账号就找不回（服务端没有明文密钥，这是端到端加密的必然代价）。
/// 3. **"登出"与"注销"不是一回事**（与云备份那条路同一条纪律）：登出只是这台设备不再登录；
///    注销会把账号、邮箱绑定与**云端备份一起删掉**。两个按钮、两段文案，不含糊成一句"删除"。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backup/account_login.dart';
import '../../backup/login_session.dart';
import '../../core/theme.dart';
import '../../core/glass_overlay.dart';
import '../../data/db.dart' show BackupAccountData;
import '../../data/profile_repository.dart';

/// 这个页面当前在哪一步（用一个枚举而不是五个路由：五步共用同一份 busy/error 状态，
/// 拆成五个页面反而要把状态搬来搬去）。
enum _Step { overview, register, login, reset, changePassword, registered }

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.session,
    required this.profile,
    this.onChanged,
  });

  /// 登录会话（注入：生产是真身，测试用假传输 + 内存存储）
  final LoginSession session;

  /// 用来查"这台机器上有没有云备份账号" —— 有的话，注册时**绑的是那个账号**
  /// （也就是"老用户绑邮箱"：数据、恢复码、云端备份都不作废）
  final ProfileRepository profile;

  /// 登录/登出/注销之后通知外面（入口那一行的文案要跟着变）
  final VoidCallback? onChanged;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  _Step _step = _Step.overview;
  StoredSession? _session;
  bool _busy = false;
  String? _error;
  bool _codeSent = false;

  /// 注册成功后**只显示这一次**的恢复码 + "我抄好了"那道门
  String? _displayCode;
  bool _wrote = false;
  bool _boundExisting = false;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  final TextEditingController _currentPassword = TextEditingController();
  final TextEditingController _recoveryInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _newPassword.dispose();
    _currentPassword.dispose();
    _recoveryInput.dispose();
    super.dispose();
  }

  /// 只读本地会话（**不联网**）：所以服务器挂了、没信号，这一页照样能打开，
  /// 而且能正确显示"你已经登录过了"。
  Future<void> _load() async {
    final StoredSession? s = await widget.session.restore();
    if (mounted) setState(() => _session = s);
  }

  void _go(_Step step) => setState(() {
        _step = step;
        _error = null;
        _codeSent = false;
        _code.clear();
        _password.clear();
      });

  /// 统一的收尾：busy 标记、错误话术、通知外面
  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on LoginFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      // 传输出来的错都已经被 LoginSession 翻成 LoginFailure 了；走到这里说明是别的东西。
      // **不把整条异常印到屏幕上**（会连类名一起给用户看）：界面上一句人话，
      // 细节进 debugPrint（`tool/check-user-text.mjs` 会拦住 `'…$e'` 这种写法）。
      debugPrint('账号页未预期的错误：$e\n$st');
      if (mounted) setState(() => _error = '出错了，稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode(String purpose) async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = '先填邮箱');
      return;
    }
    await _run(() async {
      await widget.session.sendCode(email: _email.text.trim(), purpose: purpose);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _register() async {
    await _run(() async {
      // 这台机器上已经有云备份账号（恢复码）→ **绑它**，不新建。
      // 这就是"老用户绑邮箱"：历史数据、恢复码、云端那份密文全都不作废。
      final BackupAccountData? existing = await widget.profile.cloudAccount();
      final StoredSession session;
      if (existing != null) {
        final String code = existing.recoveryCode;
        session = await widget.session.bindExisting(
          email: _email.text.trim(),
          code: _code.text.trim(),
          password: _password.text,
          accountKey: LoginSession.accountKeyFromRecoveryCode(code),
        );
        if (mounted) setState(() => _boundExisting = true);
      } else {
        session = await widget.session.register(
          email: _email.text.trim(),
          code: _code.text.trim(),
          password: _password.text,
        );
      }
      if (mounted) {
        setState(() {
          _session = session;
          _displayCode = existing != null ? null : recoveryCodeFor(session.accountKey);
          _wrote = false;
          _step = _Step.registered;
        });
        widget.onChanged?.call();
      }
    });
  }

  Future<void> _login() async {
    await _run(() async {
      final StoredSession session =
          await widget.session.login(email: _email.text.trim(), password: _password.text);
      if (mounted) {
        setState(() {
          _session = session;
          _step = _Step.overview;
        });
        widget.onChanged?.call();
      }
    });
  }

  Future<void> _reset() async {
    await _run(() async {
      final StoredSession session = await widget.session.resetWithRecoveryCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
        password: _newPassword.text,
        recoveryCode: _recoveryInput.text.trim(),
      );
      if (mounted) {
        setState(() {
          _session = session;
          _step = _Step.overview;
        });
        widget.onChanged?.call();
      }
    });
  }

  Future<void> _changePassword() async {
    await _run(() async {
      await widget.session.changePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (mounted) {
        setState(() => _step = _Step.overview);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('口令已改，其他设备上的登录已失效'), backgroundColor: Tokens.elevated),
        );
      }
    });
  }

  Future<void> _logout() async {
    await _run(() async {
      final String? warning = await widget.session.logout();
      if (mounted) {
        setState(() => _session = null);
        widget.onChanged?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning ?? '已登出'), backgroundColor: Tokens.elevated),
        );
      }
    });
  }

  Future<void> _deleteAccount() async {
    final bool? ok = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.elevated,
        title: const Text('注销账号', style: TextStyle(color: Tokens.text)),
        content: const Text(
          '会删掉：这个账号、绑定的邮箱，以及云端那份备份。\n\n'
          '本机的训练记录不动（它一直是你的）。\n\n'
          '注销之后云端就没有你的任何东西了，这一步不能撤销。',
          style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('account-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('算了', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('account-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('注销', style: TextStyle(color: Tokens.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await widget.session.deleteAccount();
      if (mounted) {
        setState(() {
          _session = null;
          _step = _Step.overview;
        });
        widget.onChanged?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        foregroundColor: Tokens.text,
        title: const Text('账号'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.s4),
        children: <Widget>[
          if (_error != null) ...<Widget>[
            Text(
              _error!,
              key: const Key('account-error'),
              style: const TextStyle(color: Tokens.danger, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
            ),
            const SizedBox(height: Tokens.s3),
          ],
          ..._buildStep(),
        ],
      ),
    );
  }

  List<Widget> _buildStep() {
    switch (_step) {
      case _Step.overview:
        return _session == null ? _loggedOut() : _loggedIn(_session!);
      case _Step.register:
        return _registerForm();
      case _Step.registered:
        return _registered();
      case _Step.login:
        return _loginForm();
      case _Step.reset:
        return _resetForm();
      case _Step.changePassword:
        return _changePasswordForm();
    }
  }

  // ------------------------------------------------------------ 未登录

  List<Widget> _loggedOut() => <Widget>[
        const Text(
          '登录之后能做的事：',
          style: TextStyle(color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong),
        ),
        const SizedBox(height: Tokens.s2),
        const Text(
          '· 换手机时用邮箱与口令找回训练记录（云端那份是加密的）\n'
          '· 换口令不必重新备份一次',
          style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsSub, height: Tokens.lhLoose),
        ),
        const SizedBox(height: Tokens.s3),
        const Text(
          '登录不改变的事：\n'
          '· 不登录照样能用全部功能，数据只在你手机上\n'
          '· 口令不会离开这台手机 —— 服务器读不到你的训练明细',
          style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhLoose),
        ),
        const SizedBox(height: Tokens.s5),
        FilledButton(
          key: const Key('account-register'),
          onPressed: _busy ? null : () => _go(_Step.register),
          child: const Text('注册一个账号'),
        ),
        const SizedBox(height: Tokens.s2),
        OutlinedButton(
          key: const Key('account-login'),
          onPressed: _busy ? null : () => _go(_Step.login),
          child: const Text('我已有账号'),
        ),
      ];

  // ------------------------------------------------------------ 已登录

  List<Widget> _loggedIn(StoredSession s) => <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.email, key: const Key('account-current-email'),
              style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsSub)),
          subtitle: const Text('已登录', style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
        ),
        const Divider(color: Tokens.line),
        ListTile(
          key: const Key('account-change-password'),
          contentPadding: EdgeInsets.zero,
          onTap: _busy ? null : () => _go(_Step.changePassword),
          title: const Text('改口令', style: TextStyle(color: Tokens.text, fontSize: Tokens.fsSub)),
          subtitle: const Text('改完其他设备上的登录会失效', style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
        ),
        ListTile(
          key: const Key('account-logout'),
          contentPadding: EdgeInsets.zero,
          onTap: _busy ? null : _logout,
          title: const Text('登出', style: TextStyle(color: Tokens.text, fontSize: Tokens.fsSub)),
          subtitle: const Text('只是这台设备不再登录，云端那份还在',
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
        ),
        ListTile(
          key: const Key('account-delete'),
          contentPadding: EdgeInsets.zero,
          onTap: _busy ? null : _deleteAccount,
          title: const Text('注销账号', style: TextStyle(color: Tokens.danger, fontSize: Tokens.fsSub)),
          subtitle: const Text('账号、邮箱与云端备份一起删掉',
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
        ),
      ];

  // ------------------------------------------------------------ 注册

  List<Widget> _registerForm() => <Widget>[
        const Text('注册', style: TextStyle(color: Tokens.text, fontSize: Tokens.fsBody, fontWeight: Tokens.fwStrong)),
        const SizedBox(height: Tokens.s3),
        TextField(
          key: const Key('account-email'),
          controller: _email,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '邮箱'),
        ),
        const SizedBox(height: Tokens.s2),
        if (!_codeSent)
          FilledButton(
            key: const Key('account-send-code'),
            onPressed: _busy ? null : () => _sendCode('register'),
            child: const Text('发验证码到邮箱'),
          ),
        if (_codeSent) ...<Widget>[
          const Text('验证码已经发出，去邮箱里看一眼（十分钟内有效）',
              style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap)),
          const SizedBox(height: Tokens.s2),
          TextField(
            key: const Key('account-code'),
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '6 位验证码'),
          ),
          const SizedBox(height: Tokens.s2),
          _passwordField(const Key('account-password'), _password, '设置一个口令'),
          const SizedBox(height: Tokens.s2),
          FilledButton(
            key: const Key('account-submit'),
            onPressed: _busy ? null : _register,
            child: const Text('创建账号'),
          ),
        ],
        const SizedBox(height: Tokens.s2),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.overview),
          child: const Text('返回', style: TextStyle(color: Tokens.text3)),
        ),
      ];

  List<Widget> _registered() => <Widget>[
        const Text('账号建好了', key: Key('account-registered'),
            style: TextStyle(color: Tokens.text, fontSize: Tokens.fsBody, fontWeight: Tokens.fwStrong)),
        const SizedBox(height: Tokens.s3),
        if (_boundExisting)
          const Text(
            '这个账号绑的是你原来那串恢复码：训练记录、云端备份、恢复码都没有变。',
            style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
          )
        else ...<Widget>[
          const Text(
            '下面这串恢复码只显示这一次。忘了口令时，靠它 + 邮箱验证码重设口令 —— '
            '它也丢了、口令也忘了，账号就找不回。',
            style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
          ),
          const SizedBox(height: Tokens.s3),
          SelectableText(
            _displayCode ?? '',
            key: const Key('account-recovery-code'),
            style: const TextStyle(color: Tokens.accent, fontSize: Tokens.fsBodyS, height: Tokens.lhNormal),
          ),
          TextButton(
            key: const Key('account-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _displayCode ?? ''));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板'), backgroundColor: Tokens.elevated),
                );
              }
            },
            child: const Text('复制', style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
          ),
          CheckboxListTile(
            key: const Key('account-wrote-check'),
            value: _wrote,
            onChanged: (bool? v) => setState(() => _wrote = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('我已经把它抄在纸上了', style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
          ),
        ],
        const SizedBox(height: Tokens.s3),
        FilledButton(
          key: const Key('account-done'),
          // 有恢复码要抄的那条路：不勾就不让过（这一步之后它再也不完整显示）
          onPressed: (!_boundExisting && !_wrote) ? null : () => _go(_Step.overview),
          child: const Text('完成'),
        ),
      ];

  // ------------------------------------------------------------ 登录 / 找回 / 改口令

  List<Widget> _loginForm() => <Widget>[
        const Text('登录', style: TextStyle(color: Tokens.text, fontSize: Tokens.fsBody, fontWeight: Tokens.fwStrong)),
        const SizedBox(height: Tokens.s3),
        TextField(
          key: const Key('account-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '邮箱'),
        ),
        const SizedBox(height: Tokens.s2),
        _passwordField(const Key('account-password'), _password, '口令'),
        const SizedBox(height: Tokens.s3),
        FilledButton(
          key: const Key('account-submit'),
          onPressed: _busy ? null : _login,
          child: const Text('登录'),
        ),
        TextButton(
          key: const Key('account-forgot'),
          onPressed: _busy ? null : () => _go(_Step.reset),
          child: const Text('忘了口令？用恢复码重设', style: TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap)),
        ),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.overview),
          child: const Text('返回', style: TextStyle(color: Tokens.text3)),
        ),
      ];

  List<Widget> _resetForm() => <Widget>[
        const Text('用恢复码重设口令',
            style: TextStyle(color: Tokens.text, fontSize: Tokens.fsBody, fontWeight: Tokens.fwStrong)),
        const SizedBox(height: Tokens.s2),
        const Text(
          '恢复码抄错一位、或者邮箱填错，本地就会先拦下来（不会白发一次请求）。',
          style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhNormal),
        ),
        const SizedBox(height: Tokens.s3),
        TextField(
          key: const Key('account-recovery-input'),
          controller: _recoveryInput,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: '恢复码（27 位）'),
        ),
        const SizedBox(height: Tokens.s2),
        TextField(
          key: const Key('account-email'),
          controller: _email,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '邮箱'),
        ),
        const SizedBox(height: Tokens.s2),
        if (!_codeSent)
          FilledButton(
            key: const Key('account-send-code'),
            onPressed: _busy ? null : () => _sendCode('reset'),
            child: const Text('发验证码到邮箱'),
          ),
        if (_codeSent) ...<Widget>[
          TextField(
            key: const Key('account-code'),
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '6 位验证码'),
          ),
          const SizedBox(height: Tokens.s2),
          _passwordField(const Key('account-password'), _newPassword, '新的口令'),
          const SizedBox(height: Tokens.s2),
          FilledButton(
            key: const Key('account-submit'),
            onPressed: _busy ? null : _reset,
            child: const Text('重设口令'),
          ),
        ],
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.login),
          child: const Text('返回登录', style: TextStyle(color: Tokens.text3)),
        ),
      ];

  List<Widget> _changePasswordForm() => <Widget>[
        const Text('改口令', style: TextStyle(color: Tokens.text, fontSize: Tokens.fsBody, fontWeight: Tokens.fwStrong)),
        const SizedBox(height: Tokens.s3),
        _passwordField(const Key('account-current-password'), _currentPassword, '当前口令'),
        const SizedBox(height: Tokens.s2),
        _passwordField(const Key('account-new-password'), _newPassword, '新口令'),
        const SizedBox(height: Tokens.s3),
        FilledButton(
          key: const Key('account-submit'),
          onPressed: _busy ? null : _changePassword,
          child: const Text('确认改口令'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _go(_Step.overview),
          child: const Text('返回', style: TextStyle(color: Tokens.text3)),
        ),
      ];

  /// 口令输入框：带一个**本地**强度提示（只是提示，不拦 —— 拦的是长度与明显弱口令）
  Widget _passwordField(Key key, TextEditingController controller, String label) {
    final String? weak = controller.text.isEmpty ? null : PasswordPolicy.check(controller.text);
    final int strength = PasswordPolicy.strength(controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          key: key,
          controller: controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            helperText: weak ??
                (controller.text.isEmpty
                    ? null
                    : <String>['偏弱', '一般', '不错'][strength]),
          ),
        ),
      ],
    );
  }
}
