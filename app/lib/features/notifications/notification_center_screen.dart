/// 练了么 · **消息通知（通知中心）** —— v1.50
///
/// 按 `vi/notifications-settings.html` 的第一屏做：标题 + 「全部已读」+ 一排分类 chip
/// （全部 / 成就 / 训练 / 系统）+ 列表（每条：分类图标、标题、一句话、相对时间、未读点）。
///
/// ⚠️ **不做的事，写明白**：这里**不申请系统通知权限**、也不推送任何东西 ——
/// 它是"进来才看"的站内消息。系统级的推送只有「训练提醒」那一条（本地通知，
/// 由 `reminder.dart` 管），两件事刻意分开：站内消息不需要任何权限就能用。
library;

import '../../core/icon_spec.dart';
import 'package:flutter/material.dart';

import '../../core/empty_state.dart';
import '../../core/theme.dart';
import '../../core/pills.dart';
import '../../core/units.dart';
import '../../core/vi_cards.dart';
import '../../data/db.dart' show AppNotificationData;
import '../../data/notification_repository.dart';
import 'notification_detail_screen.dart';
import 'notification_visuals.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key, required this.repository});

  final NotificationRepository repository;

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<AppNotificationData> _rows = const <AppNotificationData>[];
  int _unread = 0;
  String? _kind; // null = 全部
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<AppNotificationData> rows = await widget.repository.listOf(_kind);
    final int unread = await widget.repository.unreadCount();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _unread = unread;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await widget.repository.markAllRead();
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.bg,
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            key: const Key('notifications-back'),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: Tokens.s3),
                        const Expanded(
                          child: Text('消息通知',
                              style: TextStyle(
                                  color: Tokens.text, fontSize: Tokens.fsHeadline, fontWeight: Tokens.fwBold)),
                        ),
                        // 「全部已读」**不在标题栏**了（2026-10-06 用户备忘条第 6 条：
                        // "全部已读放在这个页面最下面 做一个悬浮胶囊"）—— 见页面底部那颗胶囊。
                      ],
                    ),
                  ),
                  const SizedBox(height: Tokens.s3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Tokens.s5),
                    // ⚠️ **筛选胶囊那一行要能横滚**（2026-10-10 大字号全屏扫描抓到的）：
                    // 四个胶囊在 **2.0×** 下合计 376pt > 屏宽 371pt（溢出 5px）。
                    // 与动作库的筛选行同一个做法（`Expanded` + 横向 `ListView`）——
                    // 胶囊数量或字号再长也不会有"看不见的第四格"。
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: <Widget>[
                          for (final (String? kind, String label) in <(String?, String)>[
                            (null, '全部'),
                            (NotificationKind.achievement,
                                NotificationKind.label(NotificationKind.achievement)),
                            (NotificationKind.reminder,
                                NotificationKind.label(NotificationKind.reminder)),
                            (NotificationKind.backup,
                                NotificationKind.label(NotificationKind.backup)),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: Tokens.s2),
                              child: choicePill(
                                key: Key('notif-filter-$label'),
                                label: label,
                                active: _kind == kind,
                                onTap: () {
                                  setState(() => _kind = kind);
                                  _load();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Tokens.s4),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _rows.isEmpty
                            ? Center(
                                child: EmptyState(
                                  // 这一屏的空态下一步是"离开它" —— 通知中心是查东西的地方，
                                  // 没有东西可查时最该做的是回到今天，而不是在这里等。
                                  key: const Key('empty-notifications'),
                                  art: EmptyArt.ringWithLock,
                                  title: '还没有消息。',
                                  body: '成就解锁、错过的提醒、备份结果都会记在这里。',
                                  action: '回到今天',
                                  onAction: () => Navigator.of(context).maybePop(),
                                ),
                              )
                            : ListView.separated(
                                // 底部多留一截：那颗悬浮胶囊不能把最后一条压住
                                padding: EdgeInsets.fromLTRB(
                                    Tokens.s5, 0, Tokens.s5, Tokens.s5 + 56),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: Tokens.s3),
                                itemBuilder: (BuildContext context, int i) =>
                                    _tile(_rows[i]),
                              ),
                  ),
                ],
              ),
              // 「全部已读」：一颗**悬浮胶囊**（有一封未读才出现 —— 没有未读时它是个摆设）
              if (_unread > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: Tokens.s4,
                  child: Center(child: _markAllCapsule()),
                ),
            ],
          ),
        ),
      );

  /// 点一条 → **整屏详情页**（v1.58.0；用户 2026-10-07："点进去，下面弹出的形式不明显"）。
  ///
  /// 老实现是 `showModalBottomSheet` + `mainAxisSize.min`：一条贴着底边的矮纸，
  /// 内容多高它就多高 —— "点进去了"这件事几乎看不出来。现在与 App 里其它二级页
  /// （账号／备份／成就／隐私与关于）走同一套导航语汇：整屏 + 左上角返回。
  ///
  /// 顺手把这条标为已读（点开就是读过 —— 这条消息的意义已经被读到了）。
  Future<void> _openDetail(AppNotificationData n) async {
    if (n.readAtMs == null) {
      await widget.repository.markRead(n.id);
      if (mounted) await _load();
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationDetailScreen(notification: n),
      ),
    );
  }

  /// 底部那颗「全部已读」胶囊（与主按钮同一套语言：主色实心 + 深墨字）。
  Widget _markAllCapsule() => GestureDetector(
        key: const Key('notifications-mark-all'),
        onTap: _markAllRead,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s5, vertical: 13),
          decoration: BoxDecoration(
            color: Tokens.accent,
            borderRadius: BorderRadius.circular(Tokens.rPill),
            boxShadow: Tokens.glow(Tokens.accent),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.done_all, size: IconSpec.m, color: Tokens.accentInk),
              SizedBox(width: Tokens.s2),
              Text('全部已读',
                  style: TextStyle(
                      color: Tokens.accentInk, fontSize: Tokens.fsSub, fontWeight: Tokens.fwBold)),
            ],
          ),
        ),
      );

  Widget _tile(AppNotificationData n) {
    final bool unread = n.readAtMs == null;
    return ViCard(
      key: Key('notification-${n.id}'),
      padding: const EdgeInsets.all(Tokens.s5),
      // 点得进去看详情（用户 2026-10-06 的备忘条第 5 条：现在点不动，
      // 而"解锁了哪个成就 / 备份成没成"这些细节在列表里是看不全的）
      onTap: () => _openDetail(n),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Tokens.elevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(iconForKind(n.kind), color: colorForKind(n.kind), size: IconSpec.m),
          ),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        n.title,
                        style: const TextStyle(
                            color: Tokens.text, fontSize: Tokens.fsSub, fontWeight: Tokens.fwStrong),
                      ),
                    ),
                    // 未读点：**不只靠颜色** —— 「全部已读」那个按钮只在有未读时出现，
                    // 而每一条自己的未读状态由这个小圆点表示（它旁边还有时间）
                    if (unread)
                      Container(
                        key: Key('unread-${n.id}'),
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: Tokens.accent, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(n.body,
                    style: const TextStyle(color: Tokens.text2, fontSize: Tokens.fsCap, height: Tokens.lhNormal)),
                const SizedBox(height: 8),
                Text(
                  '${NotificationKind.label(n.kind)} · ${relativeTime(n.createdAtMs)}',
                  style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「3 分钟前 / 昨天 / 10月5日」。
///
/// 抽成顶层函数是为了**可测**：时间文案是最容易写错又最难看出来的地方
/// （"昨天"算成两天前、未来时间显示成负数……）。
String relativeTime(int ms, {DateTime? now}) {
  final DateTime t = now ?? DateTime.now();
  final Duration d = t.difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.isNegative) return '刚刚'; // 时钟偏了也别显示负数
  if (d.inMinutes < 1) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays == 1) return '昨天';
  if (d.inDays < 7) return '${d.inDays} 天前';
  final DateTime day = DateTime.fromMillisecondsSinceEpoch(ms);
  return formatDateHuman(day);
}
