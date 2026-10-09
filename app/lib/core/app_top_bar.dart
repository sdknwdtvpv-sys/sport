/// 练了么 · **外壳顶栏**（2026-10-07，v1.60.0）
///
/// 用户两条原话，其实是同一件事："小铃铛放在右上角，注意下布局协调性" 与
/// "所有的设置相关的能不能集成到右上角，一个小齿轮图标" —— 右上角那个动作区该长什么样。
///
/// 之前的状态：**外壳没有统一顶栏**，五个 tab 各画各的标题
/// （「今天」34pt + 一行日期 + 铃铛 / 「我」28pt / 「进步」28pt …），
/// 于是铃铛只活在首页右上角、设置只活在第 4 个 tab 的页面上，而它们本来就该
/// 是**全局**的东西（通知中心与设置与你在哪一屏无关）。
///
/// 现在：左标题（+ 可选副标题，今日那一屏把日期放这儿）、右侧固定两枚 40×40 的动作
/// —— 齿轮（设置）与铃铛（消息）。**两枚同规格、同一基线**，这就是"布局协调性"：
/// 原来是 34pt 的标题 + 一行 13pt 日期 + 一枚 40×40 触区，三个东西各自对齐，看着往下坠。
///
/// ⚠️ 图标**不带文字标签**（顶栏位置金贵）：给它们 `tooltip` 与语义标签，
/// 但别在右上角塞"设置""消息"四个字。
library;

import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'theme.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.unread = 0,
    this.onOpenSettings,
    this.onOpenNotifications,
  });

  /// 左标题（一般就是当前 tab 的名字；「今天」那一屏是"今天"）。
  final String title;

  /// 标题右边那行小字（今日那一屏放日期）。null = 不显示。
  final String? subtitle;

  /// 未读消息数。**> 0 才有那个点** —— 永远亮着的点等于没有点。
  final int unread;

  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenNotifications;

  /// 一排动作的触区（与首页原来那枚铃铛同规格：40×40，好按）。
  static const double actionSize = 40;

  /// 顶栏在**标准字号**下的高度（标题 28pt×1.1 ≈ 31 + 上下各 8 的留白）。
  static const double baseHeight = 48;

  /// **每屏的滚动内容顶部要留出的空间**（2026-10-09，10.9 清单第 2a 条）。
  ///
  /// 只在 iOS 上非零：那边顶栏是**浮在内容之上**的玻璃（内容滚动时从它后面经过 ——
  /// 那正是玻璃要折射的东西），所以第一行内容得往下让出这条高度；
  /// Android 还是"顶栏在内容之上、各占各的位置"（`Column`），**不需要留** ——
  /// 与 `AppTabBar.reservedSpaceFor` 是同一套判据、同一个理由，两处必须一致。
  ///
  /// ⚠️ 跟着**系统字号**缩放：1.5× 时标题 42pt，顶栏自己也长高了 ——
  /// 只按标准字号留空间，大字号下第一行内容会被压在玻璃下面。
  static double reservedSpaceFor(BuildContext context) {
    if (!GlassSurface.isSupportedPlatform) return 0;
    return MediaQuery.textScalerOf(context).scale(baseHeight);
  }

  @override
  Widget build(BuildContext context) {
    final Widget bar = _bar(context);
    // 非 iOS：原样（通栏、无玻璃）—— **一个像素都不动**。
    if (!GlassSurface.isSupportedPlatform) return bar;
    // iOS：顶栏是一块**通栏玻璃**（10.9 清单第 2a 条：顶栏 + 底栏 + 浮层）。
    // ⚠️ 与底栏不同，这里**不垫 backdrop**：顶栏背后是滚动中的页面内容
    // （外壳把内容铺满、顶栏浮在它上面），真实内容从玻璃后面经过才有那个观感。
    return GlassSurface(
      key: const Key('glass-top-bar'),
      radius: 0,
      style: GlassStyle.clear,
      tint: '#10101466',
      child: bar,
    );
  }

  Widget _bar(BuildContext context) {
    return Padding(
      key: const Key('app-top-bar'),
      padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s3, Tokens.s2),
      child: Row(
        // ⚠️ `center`，不是 `end`：标题 28pt、副标题 13pt、动作 40×40 三种高度，
        // 按底边对齐就会让动作区看着"掉下去"（这正是用户说的不协调）。
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // ⚠️ `Expanded`（不是 `Flexible` + `Spacer`）：第一版就是那样写的，
          // 结果标题那一段与 Spacer 各抢一半自由空间，**日期被省略号截断**
          // （商店截图 01-home 里当场看到"10 月 8 日 · …"）。
          // 标题+副标题这一整块应当独占"动作区左边的全部宽度"，副标题只在真的放不下时才省略。
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  title,
                  key: const Key('top-bar-title'),
                  style: const TextStyle(
                    color: Tokens.text,
                    fontSize: 28,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(width: Tokens.s3),
                  Flexible(
                    child: Text(
                      subtitle!,
                      key: const Key('top-bar-subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Tokens.text3, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onOpenSettings != null) _action(
            key: const Key('top-bar-settings'),
            icon: Icons.settings_outlined,
            label: '设置',
            onTap: onOpenSettings!,
          ),
          if (onOpenNotifications != null) _bell(),
        ],
      ),
    );
  }

  Widget _action({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: actionSize,
              height: actionSize,
              child: Icon(icon, color: Tokens.text2, size: 22),
            ),
          ),
        ),
      );

  /// 铃铛 + 未读点。**有未读才带点**（与首页那颗同一套判据，key 也沿用原来那个 ——
  /// 有测试与截图是按它写的）。
  Widget _bell() => Semantics(
        button: true,
        label: '消息',
        child: Tooltip(
          message: '消息',
          child: GestureDetector(
            key: const Key('open-notifications'),
            behavior: HitTestBehavior.opaque,
            onTap: onOpenNotifications,
            child: SizedBox(
              width: actionSize,
              height: actionSize,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  const Icon(Icons.notifications_none, color: Tokens.text2, size: 22),
                  if (unread > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        key: const Key('notifications-unread-dot'),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Tokens.accent, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
