/// 练了么 · 「我」这一族的**公共零件**（2026-10-01）
///
/// **为什么把它们抽出来**：用户反馈「我」页太长（7 个区块、要滚三屏），于是把
/// 休息时长 / 单位 / 渐进开关收进「偏好设置」，导出 / 导入 / 删除收进「数据与备份」，
/// 政策 / 清单 / 许可收进「隐私与关于」。三个二级页与原页需要**同一套**
/// 区块标题、卡片、胶囊选项 —— 各写一遍的下场是「我」页改圆角、别的页没跟上。
///
/// 这里只放**没有状态**的展示件：逻辑（落库、弹层、导航）都留在各自的页面里。
library;

import '../../core/icon_spec.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

// 胶囊选项已经搬到 `core/pills.dart` —— 它被三处共用（偏好设置 / 计划编辑 / 新建动作），
// 而 2026-10-04 之前它是**三份拷贝**，于是同一个「被撑满」的 bug 也复制了三份。
// 这里转出去，是为了让既有调用方（settings_screen 等）的 import 不用改。
export '../../core/pills.dart' show choicePill;

/// 区块标题（「休息时长」「训练统计」这种小灰字）。
Widget profileSectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(left: Tokens.s1, bottom: Tokens.s2),
      child: Text(
        t,
        style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap),
      ),
    );

/// 卡片容器。
///
/// ⚠️ 背景色必须交给 `Material` 而不是 `DecoratedBox`：
/// ListTile / SwitchListTile 的水波纹画在**最近的 Material 祖先**上，
/// 中间隔一层带背景色的 DecoratedBox 会把它盖住 ——
/// Flutter 在 debug 下会直接抛断言（`ListTile background color or ink splashes may be invisible`）。
/// 边框用 `shape` 画，不引入额外的 DecoratedBox。
Widget settingsCard(List<Widget> children) => Material(
      color: Tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.rCard),
        side: const BorderSide(color: Tokens.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );

/// 一行「标题 + 说明 + 右箭头」的导航行（二级页入口）。
///
/// `subtitle` 是**可空**的（2026-10-04 文案审计改的）：以前它是必填，于是每个入口都被
/// 逼着写一句说明 —— 结果是「隐私政策 / 我们收集什么、不收集什么，逐条写在里面」
/// 这种**把标题换个说法再说一遍**的句子。可空之后，"想不出该说什么"就能什么都不说。
Widget navTile({
  required Key key,
  required String title,
  String? subtitle,
  required VoidCallback onTap,
  IconData trailing = Icons.chevron_right,
  Color? trailingColor,
  Color? titleColor,
}) =>
    ListTile(
      key: key,
      onTap: onTap,
      title: Text(
        title,
        style: TextStyle(color: titleColor ?? Tokens.text, fontSize: Tokens.fsSub),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(color: Tokens.text3, fontSize: Tokens.fsCap, height: Tokens.lhSnug),
            ),
      trailing: Icon(trailing, color: trailingColor ?? Tokens.text3, size: IconSpec.m),
    );

/// 二级页的外壳：统一的标题栏 + 返回箭头 + 可滚动内容。
///
/// 为什么不用 `Scaffold` 的 `AppBar`：全 App 的标题都是**页面内的大字标题**
/// （首页「今天练点什么？」、训练屏动作名），AppBar 会多出一条与设计语言无关的横杠。
class ProfileSubPage extends StatelessWidget {
  const ProfileSubPage({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;

  /// 标题行**最右边**的一个动作（可为空）。
  ///
  /// 2026-10-09 加：身体数据页要一个**看得见的「完成」**来收键盘 ——
  /// iOS 的数字键盘没有回车键，而"点空白处收起"这件事用户并不知道
  /// （第二份 docx 第 3 条：「这个页面的输入按键，没办法退出」）。
  /// 放在标题行右侧，与返回箭头一左一右，是二级页最自然的位置。
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.bg,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s5),
            children: <Widget>[
              Row(
                children: <Widget>[
                  GestureDetector(
                    key: const Key('subpage-back'),
                    onTap: () => Navigator.of(context).maybePop(),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(right: Tokens.s3, top: Tokens.s1, bottom: Tokens.s1),
                      child: Icon(Icons.chevron_left, color: Tokens.text2, size: IconSpec.l),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Tokens.text,
                        fontSize: Tokens.fsNum,
                        fontWeight: Tokens.fwBold,
                        letterSpacing: Tokens.lsSnug,
                      ),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
              const SizedBox(height: Tokens.s5),
              ...children,
            ],
          ),
        ),
      );
}
