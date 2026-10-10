/// 练了么 · **消息详情页**（2026-10-07，v1.58.0）
///
/// 起因是用户看完通知中心之后说：**"消息通知里的消息，点进去，下面弹出的形式不明显。
/// 优化一下。"**
///
/// 原来的做法是 `showModalBottomSheet` + `mainAxisSize.min` —— 它有多矮就多矮，
/// 一条纸贴着底边滑上来，注意力几乎为零（`docs/images/` 里那张真机截图就是这个观感）。
/// 而且它与 App 里**所有**二级页的导航语汇都不一致：账号、备份、成就、隐私与关于
/// 都是"整屏 + 左上角返回 + 22pt 标题"。
///
/// 现在改成整屏页，复用 `ProfileSubPage` 那一套外壳（同一个返回键 `subpage-back`、
/// 同一个标题规格）—— **二级页只有一种长相**，用户在哪儿都不会迷路。
///
/// ⚠️ 只负责**画**：把这一条标为已读是通知中心的事（点开即读过），
/// 这一页不去动仓库 —— 详情页越纯，测试越好钉。
library;

import '../../core/icon_spec.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vi_cards.dart';
import '../../data/db.dart' show AppNotificationData;
import '../../data/notification_repository.dart' show NotificationKind;
import '../profile/profile_widgets.dart';
import 'notification_visuals.dart';

class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({super.key, required this.notification});

  final AppNotificationData notification;

  @override
  Widget build(BuildContext context) {
    final AppNotificationData n = notification;
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(n.createdAtMs);
    return ProfileSubPage(
      title: '消息',
      children: <Widget>[
        // 分类 + 绝对时间：列表里只有相对时间（"3 天前"），想核对"到底哪天"时不够用
        Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Tokens.elevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                iconForKind(n.kind),
                color: colorForKind(n.kind),
                size: IconSpec.m,
              ),
            ),
            const SizedBox(width: Tokens.s3),
            Expanded(
              child: Text(
                NotificationKind.label(n.kind),
                style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
              ),
            ),
            Text(
              '${at.year}-${_two(at.month)}-${_two(at.day)} '
              '${_two(at.hour)}:${_two(at.minute)}',
              key: const Key('notification-detail-time'),
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s5),
        // 正文：整屏之后**不用再挤成一行**，标题与正文各占一段
        ViCard(
          child: Column(
            key: const Key('notification-detail'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                n.title,
                style: const TextStyle(
                    color: Tokens.text,
                    fontSize: Tokens.fsHeadline,
                    height: Tokens.lhSnug,
                    fontWeight: Tokens.fwBold),
              ),
              const SizedBox(height: Tokens.s3),
              Text(
                n.body,
                style: const TextStyle(
                    color: Tokens.text2, fontSize: Tokens.fsSub, height: Tokens.lhLoose),
              ),
            ],
          ),
        ),
        const SizedBox(height: Tokens.s4),
        // 一句实话：这一页里出现的消息**全在本机算出来**（三条规则都是本地判据），
        // 所以我们不推、不上传 —— 用户不必猜"这条是不是服务器发来的"。
        const Text(
          '这些消息都在这台手机上生成，不推送、不上传。',
          key: Key('notification-detail-local-note'),
          style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro, height: Tokens.lhNormal),
        ),
      ],
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
