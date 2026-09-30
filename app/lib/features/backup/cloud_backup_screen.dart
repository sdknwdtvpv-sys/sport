/// 练了么 · 云备份
///
/// **这个屏只在配了服务器地址的包里存在**（见 `lib/backup/backup_config.dart`）——
/// 没配地址的正式包，「我」页连入口都不会出现。理由很直白：一个点进去必然报错的
/// 入口，比没有这个功能更伤。
///
/// ## 界面上必须讲清楚的三件事
///
/// 1. **恢复码是唯一的钥匙**。丢了就真找不回 —— 服务端只有 `SHA-256(恢复码)`，
///    没有任何办法帮用户恢复。所以开启时强制"抄下来 + 我确认抄好了"这一步，
///    而且这一步**不能**做成可以一路点过去的确认框。
/// 2. **服务端看不到内容**。存上去的是端到端加密的密文，服务端连动作名和重量都看不到。
///    这句话是产品卖点，也必须是真的 —— 它由 `test/cloud_backup_test.dart` 里
///    "翻 sqlite 文件搜明文"那几条守着。
/// 3. **"关闭"与"注销"不是一回事**。关闭只清本机凭据（云端那份还在，用恢复码还能取回）；
///    注销会把云端数据一起删掉。这两个按钮分开、文案分开，不能含糊成一句"删除"。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backup/backup_config.dart';
import '../../backup/backup_crypto.dart';
import '../../backup/backup_transport.dart';
import '../../backup/cloud_backup.dart';
import '../../backup/recovery_code.dart';
import '../../core/theme.dart';
import '../../data/db.dart' show BackupAccountData;
import '../../data/exercise_repository.dart';
import '../../data/local_store.dart';
import '../../data/profile_repository.dart';
import '../profile/backup.dart';
import '../profile/backup_source.dart';

class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({
    super.key,
    required this.store,
    required this.repository,
    required this.profile,
    this.cloud,
    this.onDataChanged,
    this.clock,
  });

  final LocalStore store;
  final ExerciseRepository repository;
  final ProfileRepository profile;

  /// 云备份服务。不传就按编译期配置建一个真身（测试一律注入假传输）。
  final CloudBackup? cloud;

  /// 从云端恢复之后通知上层刷新（首页那张"我上周练了 N 次"要跟着变）
  final VoidCallback? onDataChanged;

  /// 便于测试固定"现在"
  final DateTime Function()? clock;

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  BackupAccountData? _account;
  bool _busy = false;
  String? _error;
  String? _notice;

  int get _nowMs => (widget.clock?.call() ?? DateTime.now()).millisecondsSinceEpoch;

  /// 没注入就按编译期配置建；没配地址则返回 null（这一屏不该被打开）
  CloudBackup? get _cloud {
    if (widget.cloud != null) return widget.cloud;
    final Uri? base = cloudBackupBaseUrl;
    if (base == null) return null;
    return CloudBackup(transport: HttpBackupTransport(baseUrl: base));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final BackupAccountData? row = await widget.profile.cloudAccount();
    if (!mounted) return;
    setState(() => _account = row);
  }

  /// 跑一次会碰网络的操作：统一 busy 状态 + 把异常翻译成人话。
  ///
  /// **备份失败必须让用户看见** —— 这和埋点恰好相反（埋点失败要静默）。
  /// 用户点完"立即备份"就走了，界面上却什么都没发生，他会以为数据安全了。
  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await body();
    } on BackupTransportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on BackupDecryptException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // 意料之外的错也要说出来，不能吞 —— 但别把栈甩给用户
      if (mounted) setState(() => _error = '出错了：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ 开启

  Future<void> _enable() async {
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.elevated,
        title: const Text('开启云备份', style: TextStyle(color: Tokens.text)),
        content: const Text(
          '备份会**加密后**存到服务器上。\n\n'
          '· 服务端只拿到密文，看不到动作名、重量、体重\n'
          '· 钥匙是一串「恢复码」，只显示这一次 —— 请抄在纸上\n'
          '· 恢复码丢了，连我们也帮不了你（服务端没有你的钥匙）',
          style: TextStyle(color: Tokens.text2, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('cloud-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('先不用', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('cloud-agree'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续', style: TextStyle(color: Tokens.volt)),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    // ⚠️ 建号与"请用户抄下恢复码"必须分成两段：
    // 对话框如果留在 `_run` 里，`_busy` 会一直为真 —— 顶上那个转圈
    // 永远不会停（`pumpAndSettle` 直接超时；真机上则是"背后一直在转"）。
    CloudAccount? account;
    await _run(() async {
      final CloudBackup? cloud = _cloud;
      if (cloud == null) {
        setState(() => _error = '这个版本没有配备份服务器');
        return;
      }
      account = await cloud.createAccount();
    });
    if (account == null || !mounted) return;

    // 恢复码只出现这一次。没抄下来就不落库 —— 落库等于给了用户一个
    // 他打不开的账号，比没开还糟。
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => _RecoveryCodeDialog(account: account!),
    );
    if (saved != true || !mounted) return;

    await widget.profile.setCloudAccount(account!.recoveryCode, nowMs: _nowMs);
    await _load();
    if (!mounted) return;
    setState(() => _notice = '云备份已开启');
  }

  // ------------------------------------------------------------ 备份 / 恢复

  Future<void> _uploadNow() async {
    final BackupAccountData? account = _account;
    if (account == null) return;
    await _run(() async {
      final CloudBackup? cloud = _cloud;
      if (cloud == null) {
        setState(() => _error = '这个版本没有配备份服务器');
        return;
      }
      final BackupBundle bundle = await collectBackup(
        store: widget.store,
        repository: widget.repository,
        nowMs: _nowMs,
      );
      final BackupUploadResult r = await cloud.upload(
        recoveryCode: account.recoveryCode,
        plaintext: bundle.json,
      );
      // **上传成功之后**才记时间：这一行会显示成"上次备份于…"，
      // 它一旦会撒谎，用户就会以为数据安全了。
      await widget.profile.markCloudUpload(r.bytes, nowMs: _nowMs);
      await _load();
      if (!mounted) return;
      setState(() =>
          _notice = '已备份 ${bundle.workouts} 次训练 / ${bundle.sets} 组'
              '（${_sizeLabel(r.bytes)} 密文）');
    });
  }

  Future<void> _restore() async {
    final BackupAccountData? account = _account;
    if (account == null) return;
    await _run(() async {
      final CloudBackup? cloud = _cloud;
      if (cloud == null) {
        setState(() => _error = '这个版本没有配备份服务器');
        return;
      }
      final String? json = await cloud.download(account.recoveryCode);
      if (!mounted) return;
      if (json == null) {
        setState(() => _error = '云端还没有备份');
        return;
      }
      final BackupParse parsed = parseBackup(json);
      if (!parsed.ok) {
        setState(() => _error = '云端的备份读不出来：${parsed.error}');
        return;
      }
      final BackupApplyResult r = await applyBackup(widget.store, parsed);
      if (!mounted) return;
      widget.onDataChanged?.call();
      setState(() => _notice = '已从云端恢复：${r.summary}');
    });
  }

  // ------------------------------------------------------------ 关闭 / 注销

  Future<void> _disableLocalOnly() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.elevated,
        title: const Text('关闭云备份', style: TextStyle(color: Tokens.text)),
        content: const Text(
          '只清掉本机这串恢复码。\n\n'
          '云端那份**还在** —— 抄下来的恢复码以后还能把它取回来。\n'
          '但本机不再备份，直到你重新输入恢复码。',
          style: TextStyle(color: Tokens.text2, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('cloud-keep'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('cloud-disable-ok'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('关闭', style: TextStyle(color: Tokens.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.profile.clearCloudAccount();
    await _load();
    if (!mounted) return;
    setState(() => _notice = '已关闭（云端那份还在）');
  }

  Future<void> _deleteEverything() async {
    final BackupAccountData? account = _account;
    if (account == null) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.elevated,
        title: const Text('删除云端备份并注销', style: TextStyle(color: Tokens.text)),
        content: const Text(
          '服务器上的备份会**连同账号一起删掉**，不可撤销。\n\n'
          '本机数据不受影响。',
          style: TextStyle(color: Tokens.text2, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('cloud-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('cloud-delete-ok'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Tokens.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _run(() async {
      final CloudBackup? cloud = _cloud;
      if (cloud == null) {
        setState(() => _error = '这个版本没有配备份服务器');
        return;
      }
      await cloud.deleteAccount(account.recoveryCode);
      await widget.profile.clearCloudAccount();
      await _load();
      if (!mounted) return;
      setState(() => _notice = '云端备份已删除，账号已注销');
    });
  }

  /// 用别处的恢复码接管一个已有账号（换手机走这条）
  Future<void> _adopt() async {
    final TextEditingController input = TextEditingController();
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: Tokens.elevated,
        title: const Text('用恢复码取回', style: TextStyle(color: Tokens.text)),
        content: TextField(
          key: const Key('cloud-adopt-input'),
          controller: input,
          autofocus: true,
          maxLines: 2,
          style: const TextStyle(color: Tokens.text),
          decoration: const InputDecoration(
            hintText: '把 27 位恢复码粘进来（大小写、连字符都无所谓）',
            hintStyle: TextStyle(color: Tokens.text3),
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('cloud-adopt-cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: Tokens.text2)),
          ),
          TextButton(
            key: const Key('cloud-adopt-ok'),
            onPressed: () => Navigator.of(ctx).pop(input.text),
            child: const Text('取回', style: TextStyle(color: Tokens.volt)),
          ),
        ],
      ),
    );
    if (code == null || !mounted) return;

    await _run(() async {
      final CloudBackup? cloud = _cloud;
      if (cloud == null) {
        setState(() => _error = '这个版本没有配备份服务器');
        return;
      }
      // 先本地校验恢复码（抄错一位在这里就被拦住），再问服务器。
      // 服务器上那条 `/v1/account` 是幂等的，所以"这台机器本来就登记过"也没关系。
      final CloudAccount account = await cloud.register(code);
      await widget.profile
          .setCloudAccount(account.recoveryCode, nowMs: _nowMs);
      await _load();
      if (!mounted) return;
      setState(() => _notice = '已绑定这个恢复码；可以点「从云端恢复」了');
    });
  }

  // ------------------------------------------------------------ 界面

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _timeLabel(int? ms) {
    if (ms == null) return '还没备份过';
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '上次备份：${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final CloudBackup? cloud = _cloud;
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('cloud-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '云备份',
                      style: TextStyle(
                        color: Tokens.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Tokens.volt),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s8),
                children: <Widget>[
                  if (cloud == null) ..._notConfigured() else ..._body(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _notConfigured() => <Widget>[
        _card(
          <Widget>[
            const Text('这个版本没有配备份服务器',
                style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: Tokens.s2),
            const Text(
              '云备份需要一台服务器（在开发者那边，还没上）。'
              '本机的「导出备份文件 / 导入备份」不受影响，一直可用。',
              style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ];

  List<Widget> _body() {
    final BackupAccountData? account = _account;
    return <Widget>[
      if (_error != null) _banner(_error!, Tokens.danger, const Key('cloud-error')),
      if (_notice != null) _banner(_notice!, Tokens.volt, const Key('cloud-notice')),
      if (account == null) ..._setup() else ..._enabled(account),
      const SizedBox(height: Tokens.s5),
      const Divider(height: 1, color: Tokens.line),
      const SizedBox(height: Tokens.s4),
      const Text(
        '备份内容是端到端加密的：服务端存的是密文，看不到动作名、重量、体重。\n'
        '恢复码是唯一的钥匙，服务端没有它 —— 所以丢了就是丢了。',
        style: TextStyle(color: Tokens.text3, fontSize: 12, height: 1.6),
      ),
    ];
  }

  List<Widget> _setup() => <Widget>[
        _card(<Widget>[
          const Text('还没开启',
              style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.s2),
          const Text(
            '开启后，训练记录会加密存到服务器上：换手机、或手机丢了都能取回来。\n'
            '默认关闭 —— 不想要的话，什么都不会上传。',
            style: TextStyle(color: Tokens.text3, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: Tokens.s4),
          _primaryButton(const Key('cloud-enable'), '开启云备份', _enable),
          const SizedBox(height: Tokens.s3),
          _ghostButton(const Key('cloud-adopt'), '我有恢复码，取回已有备份', _adopt),
        ]),
      ];

  List<Widget> _enabled(BackupAccountData account) => <Widget>[
        _card(<Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Tokens.volt, shape: BoxShape.circle),
              ),
              const SizedBox(width: Tokens.s2),
              const Text('已开启',
                  style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: Tokens.s3),
          Text(_timeLabel(account.lastUploadAtMs),
              key: const Key('cloud-last-upload'),
              style: const TextStyle(color: Tokens.text2, fontSize: 13)),
          if (account.lastUploadBytes != null)
            Text('密文大小 ${_sizeLabel(account.lastUploadBytes!)}',
                style: const TextStyle(color: Tokens.text3, fontSize: 12)),
          const SizedBox(height: Tokens.s4),
          _primaryButton(const Key('cloud-upload'), '立即备份', _uploadNow),
          const SizedBox(height: Tokens.s3),
          _ghostButton(const Key('cloud-restore'), '从云端恢复（合并，不覆盖本机）', _restore),
        ]),
        const SizedBox(height: Tokens.s4),
        _card(<Widget>[
          const Text('你的恢复码',
              style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.s3),
          SelectableText(
            formatRecoveryCode(account.recoveryCode),
            key: const Key('cloud-code'),
            style: const TextStyle(
              color: Tokens.volt,
              fontSize: 15,
              height: 1.6,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: Tokens.s3),
          _ghostButton(const Key('cloud-copy'), '复制恢复码', () async {
            await Clipboard.setData(
              ClipboardData(text: formatRecoveryCode(account.recoveryCode)),
            );
            if (!mounted) return;
            setState(() => _notice = '恢复码已复制（抄在纸上更保险）');
          }),
        ]),
        const SizedBox(height: Tokens.s4),
        _card(<Widget>[
          const Text('不想要了',
              style: TextStyle(color: Tokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.s3),
          _ghostButton(const Key('cloud-disable'), '关闭云备份（云端保留）', _disableLocalOnly),
          const SizedBox(height: Tokens.s3),
          _ghostButton(
            const Key('cloud-delete'),
            '删除云端备份并注销',
            _deleteEverything,
            danger: true,
          ),
        ]),
      ];

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(Tokens.s4),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rCard),
          border: Border.all(color: Tokens.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _banner(String text, Color color, Key key) => Container(
        key: key,
        margin: const EdgeInsets.only(bottom: Tokens.s4),
        padding: const EdgeInsets.all(Tokens.s3),
        decoration: BoxDecoration(
          color: Tokens.elevated,
          borderRadius: BorderRadius.circular(Tokens.rCard),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.5)),
      );

  Widget _primaryButton(Key key, String label, VoidCallback onTap) => SizedBox(
        height: 48,
        child: TextButton(
          key: key,
          onPressed: _busy ? null : onTap,
          style: TextButton.styleFrom(
            backgroundColor: Tokens.volt,
            foregroundColor: Tokens.voltInk,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rPill)),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _ghostButton(Key key, String label, VoidCallback onTap, {bool danger = false}) =>
      SizedBox(
        height: 44,
        child: TextButton(
          key: key,
          onPressed: _busy ? null : onTap,
          style: TextButton.styleFrom(
            backgroundColor: Tokens.elevated,
            foregroundColor: danger ? Tokens.danger : Tokens.text2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.rPill)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
      );
}

/// 恢复码**只显示这一次**。
///
/// 刻意不做成"随便点一下就过去"的确认框：必须真的勾上"我抄好了"才能继续 ——
/// 这不是仪式感，是因为**这一步之后那串码再也不会完整显示给用户**
/// （服务端没有它，我们也帮不了他）。
class _RecoveryCodeDialog extends StatefulWidget {
  const _RecoveryCodeDialog({required this.account});

  final CloudAccount account;

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  bool _copied = false;
  bool _wrote = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Tokens.elevated,
      title: const Text('抄下你的恢复码', style: TextStyle(color: Tokens.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '这是取回备份的唯一钥匙，**只显示这一次**。',
            style: TextStyle(color: Tokens.text2, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: Tokens.s3),
          SelectableText(
            widget.account.displayCode,
            key: const Key('cloud-new-code'),
            style: const TextStyle(
              color: Tokens.volt,
              fontSize: 16,
              height: 1.6,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: Tokens.s3),
          TextButton(
            key: const Key('cloud-new-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.account.displayCode));
              if (mounted) setState(() => _copied = true);
            },
            child: Text(
              _copied ? '已复制到剪贴板' : '复制',
              style: const TextStyle(color: Tokens.text2, fontSize: 13),
            ),
          ),
          CheckboxListTile(
            key: const Key('cloud-wrote-check'),
            value: _wrote,
            onChanged: (bool? v) => setState(() => _wrote = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('我已经把它抄在纸上了',
                style: TextStyle(color: Tokens.text2, fontSize: 13)),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('cloud-new-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('算了，不开了', style: TextStyle(color: Tokens.text2)),
        ),
        TextButton(
          key: const Key('cloud-new-ok'),
          onPressed: _wrote ? () => Navigator.of(context).pop(true) : null,
          child: const Text('开启', style: TextStyle(color: Tokens.volt)),
        ),
      ],
    );
  }
}
