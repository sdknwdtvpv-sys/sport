/// 练了么 · 「我」这一族的**公共零件**（2026-10-01）
///
/// **为什么把它们抽出来**：用户反馈「我」页太长（7 个区块、要滚三屏），于是把
/// 休息时长 / 单位 / 渐进开关收进「偏好设置」，导出 / 导入 / 删除收进「数据与备份」，
/// 政策 / 清单 / 许可收进「隐私与关于」。三个二级页与原页需要**同一套**
/// 区块标题、卡片、胶囊选项 —— 各写一遍的下场是「我」页改圆角、别的页没跟上。
///
/// 这里只放**没有状态**的展示件：逻辑（落库、弹层、导航）都留在各自的页面里。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 区块标题（「休息时长」「训练统计」这种小灰字）。
Widget profileSectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(left: Tokens.s1, bottom: Tokens.s2),
      child: Text(
        t,
        style: const TextStyle(color: Tokens.text3, fontSize: 13),
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

/// 胶囊选项（休息时长、重量单位都用它）。
///
/// 选中态用 volt 底 + 深色字：这是全 App 唯一的"选中"语言，
/// 不用再引入第二套（勾选框 / 单选圆圈）。
Widget choicePill({
  required String label,
  required bool active,
  required VoidCallback onTap,
  Key? key,
}) =>
    GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
        height: 36,
        decoration: BoxDecoration(
          color: active ? Tokens.volt : Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.rPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Tokens.voltInk : Tokens.text2,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );

/// 一行「标题 + 说明 + 右箭头」的导航行（二级页入口）。
Widget navTile({
  required Key key,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  IconData trailing = Icons.chevron_right,
  Color? trailingColor,
  Color? titleColor,
}) =>
    ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
      onTap: onTap,
      title: Text(
        title,
        style: TextStyle(color: titleColor ?? Tokens.text, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Tokens.text3, fontSize: 13, height: 1.4),
      ),
      trailing: Icon(trailing, color: trailingColor ?? Tokens.text3, size: 20),
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
  });

  final String title;
  final List<Widget> children;

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
                      child: Icon(Icons.chevron_left, color: Tokens.text2, size: 26),
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Tokens.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.s5),
              ...children,
            ],
          ),
        ),
      );
}
