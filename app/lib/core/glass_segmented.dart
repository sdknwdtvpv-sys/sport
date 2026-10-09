/// 练了么 · iOS 26 的**「底托 + 选中胶囊」**：两块**各自独立**的玻璃 ——
/// 胶囊比底托往里缩一点、带自己的一圈亮边，看上去是"凸起来的一块"。
///
/// 这是"单块玻璃"（`glass_surface.dart`）之外的第二件事，两者的分工：
///   * `GlassSurface`：**一块**玻璃（例如某个面的背景）；
///   * `GlassSegmented`：**底托 + 选中胶囊**两块（分段控件与底部 Tab 栏用它）。
///
/// ## ⚠️ 为什么**不**用 `UIGlassContainerEffect`（2026-10-06 真机反馈后改的）
///
/// 苹果那个容器是"把多块玻璃合成一块"的 —— 听起来正是我们要的，但**叠在一起的两块玻璃
/// 会被它抹平成一块**：选中胶囊的亮边与凸起全没了（底托与胶囊同高时，屏幕上什么都看不出来）。
/// 真机上用户的原话就是"切 tab 的时候完全感觉不到玻璃的感觉"。
/// 同一组参数只把容器去掉，胶囊立刻变成一块有亮边的凸起玻璃 ——
/// 逐行对比见 `docs/images/glass-probe-segment-variants.png`（D 行=容器、A/B 行=独立）。
/// 代价：切换时不再有"融合"的形变（苹果自己的分段控件也是"一块独立的选中玻璃"）。
///
/// ## 边界（与 `GlassSurface` 完全一致）
///   * **非 iOS 原样返回 [child]**（外加调用方自己的兜底样式）—— Android 一个像素都不动；
///   * iOS 26+ 真材质；iOS 26 以下退回毛玻璃（**这一支没在真机上验过**）。
///
/// ## ⚠️ 它要求**条目等宽**
/// 几何放在原生侧算（`width / count`），因为"滑动"必须在 UIView 动画里跑，
/// 每帧从 Dart 传坐标既慢又抖。代价就是：**用它的地方，条目必须等宽**。
/// 底栏本来就是 `Expanded`（等分）✓；分段控件那边为了它改成了等分（用户 2026-10-06 拍板）。
///
/// ## 代价
/// 一个平台视图 = 整屏栅格化不能与 Dart 并行（见 `glass_surface.dart` 的说明）。
/// 所以**一屏最多一两个**：底栏一个 + 当前屏的分段控件一个，正好在预算内。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart';
import 'theme.dart';

/// `Color` → `#RRGGBB`（原生按这个解析）。
String _hex(Color c) {
  final int v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class GlassSegmented extends StatefulWidget {
  const GlassSegmented({
    super.key,
    required this.child,
    required this.count,
    required this.index,
    this.radius = 16,
    this.style = GlassStyle.regular,
    this.baseTint,
    this.pillTint,
    this.pillInset = 5,
    this.pillStyle = GlassStyle.clear,
    this.pressBulge = 14,
    this.dragIndex,
    this.onDragSelect,
    this.labels,
    this.icons,
    this.selectedColor,
    this.unselectedColor,
    this.labelFontSize = 12,
    this.iconSize = 22,
    this.emphasisIndex = -1,
    this.emphasisColor,
    this.emphasisIconColor,
    this.emphasisIconSize,
  });

  /// 盖在玻璃上面的内容（标签/图标 —— 仍然是 Flutter 画的，也仍然由 Flutter 收点击）。
  final Widget child;

  /// 几格。**条目等宽**（几何在原生侧按 `width / count` 算）。
  final int count;

  /// 当前选中的格子（0 基）。
  final int index;

  /// 圆角。底栏传 `高度 / 2` 就是胶囊。
  final double radius;

  final GlassStyle style;

  /// 底托与选中胶囊各自的染色（`#RRGGBB` / `#RRGGBBAA`）。
  ///
  /// **胶囊默认不染色 = 全透明的玻璃**（用户 2026-10-06 拍板的那一条：
  /// "鼓起来那一块能不能做成全透明的"）。这时"选中的是谁"由图标/文字的颜色 +
  /// 玻璃自己的边缘高光来说 —— 实测（`docs/images/glass-probe-transparent.png`）
  /// 全透明那颗反而更像苹果：形状靠折射读出来，而不是靠一层白。
  /// ⚠️ 平底卡片上的那两行单位是例外（它们背后没有内容可折射），仍然给一点白。
  final String? baseTint;
  final String? pillTint;

  /// 胶囊相对自己那一格**往里缩**多少 pt（默认 5）。
  /// 这个缝就是"凸起来的那块"与底托之间的分界 —— 缩到 0 两块就贴死了。
  final double pillInset;

  /// 选中胶囊的材质：**默认 `.clear`**（底托才是 `.regular`）。
  /// 两块 `.regular` 叠在一起是**双重磨砂** → 那颗玻璃会变成"奶白疙瘩"、一点都不透
  /// （2026-10-06 真机反馈）。`.clear` 叠在磨砂底托上仍然透得过去。
  final GlassStyle pillStyle;

  /// 按住时**每边**再鼓出来多少 pt（默认 14）。它是"Q 弹"的幅度来源：
  /// 平时胶囊比底托小一圈，按住时一下子鼓出去、**超出底栏边界**，松手弹回来。
  /// 幅度太小就没有那个手感（用户 2026-10-06 反馈"太小了"）。
  final double pressBulge;

  /// 手指左右拖页面时，**这一格应该停在哪**（0 = 第一格，2.4 = 第二格往右 40%）。
  /// 外壳的 `PageController` 每帧把它推进来，原生就让胶囊跟着手指滑 ——
  /// 这是"切 tab 丝滑、有左右拖动的感觉"的来源（用户 2026-10-06 追加的那条）。
  /// `null` = 没有人拖（胶囊停在整格上）。
  final ValueListenable<double>? dragIndex;

  /// **在底栏上按住并横向拖到别格再松手**时回调（参数是松手那一格）。
  /// 只有"按下与松手不是同一格"才会回调 —— 普通点击走上面那层 Flutter 自己的 tap，
  /// 两条路不会重复触发（调用方那边 `_selectTab` 也是幂等的）。
  /// 这就是"按住不放、拖着换 tab"那条路（用户 2026-10-06 要的）。
  final ValueChanged<int>? onDragSelect;

  // ── 原生文案（2026-10-06 加，修的是"文字重影"那个 bug）────────────────────
  //
  // ⚠️ 给了 [labels] 之后，**iOS 上的字由原生画**，[child] 里那份被隐掉（布局与点击照旧）。
  // 原因：玻璃会**折射它背后的东西**，而 Flutter 画的字就在玻璃背后（iOS 平台视图永远盖在
  // Flutter 内容之上）→ 屏幕上出现**两份字**（一份清晰、一份是折射出来的错位虚影），
  // 用户看到的就是「重量单位这里显示 bug」。字画进玻璃**里面**就没有第二份可折射。
  // 非 iOS 不受影响（`labels` 只是不发过去）。

  /// 每格的字。给了就在 iOS 上由原生画。
  final List<String>? labels;

  /// 每格的 SF Symbol 名（底栏用："dumbbell.fill" 那类）。给了就是"图标 + 文字"竖排。
  final List<String>? icons;

  /// 选中/未选中的字色与图标色（`#RRGGBB`）。默认取 `Tokens.accent` / `Tokens.text3`
  /// —— 不写死十六进制是为了不让它和调色板漂（`theme.dart` 一改，这里跟着走）。
  final String? selectedColor;
  final String? unselectedColor;

  final double labelFontSize;
  final double iconSize;

  /// **正中被点亮的那一格**（2026-10-08，v1.61.0）。-1 = 没有。
  ///
  /// ⚠️ 为什么它必须由**原生**画（而不是 Flutter 在底栏上叠一层圆）：
  /// iOS 的平台视图**永远盖在 Flutter 内容之上**，Flutter 画的圆会落在玻璃**背后**，
  /// 被折射成一层发灰的虚影 —— 那正是用户 10.8 清单第 1 条「tab 栏的训练 玻璃效果 bug」。
  /// 这一层（`labelsBox`）是"玻璃之上"的那一层，画在这里就不会被折射。
  final int emphasisIndex;

  /// 那颗圆的填充色（一般是强调色）。
  final String? emphasisColor;

  /// 圆里图标的颜色（一般是"深墨"：强调色圆上要压一个深色图标才看得清）。
  final String? emphasisIconColor;

  /// 被点亮那一格的**图标大小**（2026-10-09，10.9 清单第 2b 条）。
  ///
  /// 为什么要有它：用户说底栏正中"太割裂" —— 左右四个是线性图标，中间却是
  /// "实心圆 + 深色图标"（两套视觉语言）。去掉圆之后，"中间那一格与别人不同"
  /// 就只剩**大小**与颜色两个手段，而图标大小只有原生能改（字与图标都由原生画在玻璃之上）。
  /// null = 与其余几格同一个大小。
  final double? emphasisIconSize;

  @override
  State<GlassSegmented> createState() => _GlassSegmentedState();
}

class _GlassSegmentedState extends State<GlassSegmented> {
  static const String _viewType = 'lianleme/glass_segmented';

  /// 每个平台视图各有一条通道（名字带 viewId）—— 只有"换选中项"这一件事走它。
  MethodChannel? _channel;

  /// 手指按下时在哪一格（松手时比一下，才知道这是"点击"还是"拖到别格"）。
  int? _downCell;

  void _onCreated(int id) {
    _channel = MethodChannel('lianleme/glass_segmented/$id');
  }

  @override
  void initState() {
    super.initState();
    widget.dragIndex?.addListener(_onDrag);
  }

  @override
  void dispose() {
    widget.dragIndex?.removeListener(_onDrag);
    super.dispose();
  }

  /// 手指在拖页面：把"当前停在第几页"（小数）每帧喂给原生，胶囊就跟着手指滑。
  void _onDrag() {
    final double v = widget.dragIndex!.value;
    _channel?.invokeMethod<void>('setIndexFraction', <String, Object?>{'index': v});
  }

  @override
  void didUpdateWidget(GlassSegmented old) {
    super.didUpdateWidget(old);
    if (old.dragIndex != widget.dragIndex) {
      old.dragIndex?.removeListener(_onDrag);
      widget.dragIndex?.addListener(_onDrag);
    }
    if (old.index != widget.index || old.count != widget.count) {
      // 原生侧自己做动画（弹簧滑动）—— 这里只告诉它"现在是第几格"
      _channel?.invokeMethod<void>('setIndex', <String, Object?>{'index': widget.index});
    }
  }

  /// 手指在这一层里按下 / 移动：把"第几格 + 横向坐标"报给原生。
  /// `Listener` 只"看"不改 —— 点击仍然照旧由上面那层 Flutter 内容处理（不抢手势）。
  ///
  /// ⚠️ **坐标必须一起报**：原生那颗"第二水滴"是**跟着手指**冒出来的，只有格号的话
  /// 它只能待在格子中间，就成了"跳"而不是"融"。
  void _press(Offset local, Size size) {
    if (size.width <= 0 || widget.count <= 0) return;
    _downCell = _cellAt(local.dx, size.width);
    _channel?.invokeMethod<void>('press', <String, Object?>{
      'index': _downCell,
      'x': local.dx,
    });
  }

  void _move(Offset local, Size size) {
    if (size.width <= 0) return;
    _channel?.invokeMethod<void>('pressMove', <String, Object?>{'x': local.dx});
  }

  int _cellFor(Offset local, Size size) => _cellAt(local.dx, size.width);

  int _cellAt(double dx, double width) =>
      (dx / (width / widget.count)).floor().clamp(0, widget.count - 1);

  void _release(Offset local, Size size) {
    _channel?.invokeMethod<void>('release');
    // 拖到别格再松手 = 换 tab（普通点击不会走到这里：那时两格相同）
    final ValueChanged<int>? select = widget.onDragSelect;
    if (select != null && _downCell != null) {
      final int up = _cellFor(local, size);
      if (up != _downCell) select(up);
    }
    _downCell = null;
  }

  @override
  Widget build(BuildContext context) {
    // 非 iOS 原样返回：连平台视图都不建（Android 与以前一个像素都不差）
    if (!GlassSurface.isSupportedPlatform) return widget.child;

    // ⚠️ 按压反馈为什么要在 Dart 这边盯着：平台视图在 Flutter 内容**下面**，
    // 手指落在标签/图标那一层，UIKit 根本收不到触摸 ——
    // 于是岩果的 `UIGlassEffect.isInteractive` 触发不了（详见 `GlassBridge.swift` 文件头第 4 条）。
    // 这里用 `Listener`（只观察、不进手势竞技场）把"按在第几格/松开了"通报给原生，
    // 由原生演形变与提亮 —— 点击、旁白、长按那条链路一个字都不动。
    final Widget content = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent e) {
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        _press(e.localPosition, box.size);
      },
      onPointerMove: (PointerMoveEvent e) {
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        _move(e.localPosition, box.size);
      },
      onPointerUp: (PointerUpEvent e) {
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        _release(e.localPosition, box.size);
      },
      onPointerCancel: (PointerCancelEvent e) {
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        _release(e.localPosition, box.size);
      },
      // iOS 上字由原生画：这一份**只留布局与点击**，不画（不画的东西才不会被玻璃折射）
      child: widget.labels == null
          ? widget.child
          : Opacity(opacity: 0, child: widget.child),
    );

    // ⚠️ `content` 必须是 **Stack 的非定位子项**（不能包 `Positioned.fill`）：
    // Stack 的尺寸由非定位子项决定，全是被定位的子项时它会**算不出自己的大小**
    // （`size: MISSING` + 高度约束无界 → 真机上直接抛 layout 断言）。
    // 这是 2026-10-06 用 integration test 抓到的（widget 测试里没露头）。
    return Stack(
      // 按住时原生那颗胶囊会鼓到边界外面 —— 别让 Flutter 把它裁掉
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: UiKitView(
            viewType: _viewType,
            onPlatformViewCreated: _onCreated,
            // ⚠️ 键名要与 `GlassBridge.swift` 里的读取逐字一致（写错只会静默用默认值）
            creationParams: <String, Object?>{
              'count': widget.count,
              'index': widget.index,
              'radius': widget.radius,
              'style': widget.style.wire,
              'pillStyle': widget.pillStyle.wire,
              'pillInset': widget.pillInset,
              'pressBulge': widget.pressBulge,
              if (widget.labels != null) 'labels': widget.labels,
              if (widget.icons != null) 'icons': widget.icons,
              if (widget.labels != null) 'selectedColor': widget.selectedColor ?? _hex(Tokens.accent),
              if (widget.labels != null)
                'unselectedColor': widget.unselectedColor ?? _hex(Tokens.text3),
              if (widget.labels != null) 'labelFontSize': widget.labelFontSize,
              if (widget.labels != null) 'iconSize': widget.iconSize,
              // 正中那颗（可缺省）：键名要与 `GlassBridge.swift` 逐字一致
              if (widget.emphasisIndex >= 0) 'emphasisIndex': widget.emphasisIndex,
              if (widget.emphasisColor != null) 'emphasisColor': widget.emphasisColor,
              if (widget.emphasisIconColor != null)
                'emphasisIconColor': widget.emphasisIconColor,
              if (widget.emphasisIconSize != null)
                'emphasisIconSize': widget.emphasisIconSize,
              if (widget.baseTint != null) 'baseTint': widget.baseTint,
              if (widget.pillTint != null) 'pillTint': widget.pillTint,
            },
            creationParamsCodec: const StandardMessageCodec(),
            // 点击由上面那层 Flutter 内容处理（标签/图标是 Flutter 画的）
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          ),
        ),
        content,
      ],
    );
  }
}

/// 一行的「多选一」（单位、维度这种）：**非 iOS 用调用方自己的老样子，iOS 换成玻璃**。
///
/// 为什么要有这一层：这个分支（"iOS 才画玻璃"）在好几处都要写，而它**必须和
/// `GlassSegmented` 的几何契约一起出现**（条目等宽、宽度是定值）。抄上三遍就等于给
/// "哪天有人只改了两处"留了口子 —— `core/pills.dart` 顶部记着这个仓库吃过同类的亏。
///
/// ⚠️ `itemBuilder` 拿到的 `glass` 不只是"要不要画装饰"：**玻璃那支下面没有实心 accent
/// 底色**，所以选中项的字色通常也要换（深墨压在浅玻璃上会糊，见 `ViSegmented`）。
/// 老样子那一支请原样返回调用方原来的胶囊 —— Android 一个像素都不动。
class GlassSegmentedRow extends StatelessWidget {
  const GlassSegmentedRow({
    super.key,
    required this.count,
    required this.index,
    required this.itemBuilder,
    this.itemWidth = 56,
    this.height = 32,
    this.style = GlassStyle.regular,
    this.baseTint,
    this.pillTint,
    this.pillInset = 5,
    this.pillStyle = GlassStyle.clear,
    this.pressBulge = 14,
    this.labels,
    this.selectedColor,
    this.unselectedColor,
    this.labelFontSize = 12,
  });

  final int count;
  final int index;

  /// 每一格的内容。`glass == false` 时外面**不套任何盒子** —— 老样子由调用方自己给。
  final Widget Function(int index, bool glass) itemBuilder;

  /// iOS 上每格的宽度。**必须是定值**：原生按 `frame.width / count` 切格子。
  final double itemWidth;

  /// iOS 上的高度；圆角 = 高度 / 2（胶囊）。
  final double height;

  /// 材质。⚠️ 放在**平底卡片上**时用 `.clear` + 一点点白：`.regular` 在纯炭黑/纯卡片色
  /// 上会变成一块灰板（2026-10-06 试出来的，见 `docs/feature-backlog.md` §〇「⑦」）——
  /// 玻璃要有东西从背后经过才成立。
  final GlassStyle style;
  final String? baseTint;
  final String? pillTint;

  /// 胶囊往里缩多少 pt（见 `GlassSegmented.pillInset`）。
  final double pillInset;

  /// 选中胶囊的材质（默认 `.clear`，见 `GlassSegmented.pillStyle`）。
  final GlassStyle pillStyle;

  /// 按住时每边再鼓出来多少 pt（见 `GlassSegmented.pressBulge`）。
  final double pressBulge;

  /// 每格的字（给了就由**原生**画 —— 见 `GlassSegmented.labels`：玻璃会折射背后的字）。
  final List<String>? labels;
  final String? selectedColor;
  final String? unselectedColor;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    if (!GlassSurface.isSupportedPlatform) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < count; i++) itemBuilder(i, false),
        ],
      );
    }

    return GlassSegmented(
      count: count,
      index: index,
      radius: height / 2,
      style: style,
      baseTint: baseTint,
      pillTint: pillTint,
      pillInset: pillInset,
      pillStyle: pillStyle,
      pressBulge: pressBulge,
      labels: labels,
      selectedColor: selectedColor,
      unselectedColor: unselectedColor,
      labelFontSize: labelFontSize,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            SizedBox(
              width: itemWidth,
              height: height,
              // 给了 labels 就由原生画字：这一份只留格子尺寸与点击热区，不画
              child: labels == null
                  ? Center(child: itemBuilder(i, true))
                  : Opacity(opacity: 0, child: Center(child: itemBuilder(i, true))),
            ),
        ],
      ),
    );
  }
}
