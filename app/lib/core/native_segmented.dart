/// 练了么 · **苹果原生 `UISegmentedControl`** 的 Dart 侧（2026-10-09）
///
/// 用户看完底栏换成真 `UITabBar` 之后问：「其他的切换选项能不能也做成这个效果呢，
/// 比如说像周 月 年的那个调整」。所以"三选一 / 两选一"这类切换器也接上系统控件。
///
/// 用它的是 `ViSegmented`（`core/vi_cards.dart`）的 **iOS 分支** —— 那一个组件被
/// 5 处复用（进步页的周/月/年、数据页的按动作看/按时间看、计划页的三视图、
/// 身体数据页的指标切换、分享卡预览的明暗），所以改一处就都换了。
///
/// ⚠️ **筛选胶囊不换成原生**（有意）：动作选择器里的部位 / 器械 / 类型 / 细分标签
/// 是"8 个里挑一个 + 全部"的标签云，`UISegmentedControl` 塞 8 段会挤成一排小字。
///
/// ## 与 `native_tab_bar.dart` 同一套规矩
///
/// * 触摸归**原生**（`EagerGestureRecognizer`）—— 真控件自己处理点选与选中动画；
/// * 选中变化由原生回给 Dart（`onChanged`），Dart 那边是唯一真源；
/// * **宽度由 Dart 定**（`itemWidth × 段数`）：原生 `apportionsSegmentWidthsByContent`
///   关了，等宽由我们说了算 —— 否则同一行里的别的元素会跟着跳。
///
/// ⚠️ 代价与前一块一样：**Flutter 的测试点不到它**（合成事件进不了 UIKit）。
/// 依赖"点切换器"的 iOS 自动化要改走业务入口（底栏那件事已经踩过一次，见
/// `main.dart` 的 `debugSwitchTab`）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart' show GlassSurface;

/// 原生分段控件的参数（键名与 `NativeSegmentedBridge.swift` 一一对应）。
@immutable
class NativeSegmentedSpec {
  const NativeSegmentedSpec({
    required this.labels,
    required this.selectedIndex,
    required this.selectedColor,
    required this.unselectedColor,
    this.selectedTint,
    this.fontSize = 12,
  });

  final List<String> labels;
  final int selectedIndex;

  /// `#RRGGBB`（原生按这个解析）
  final String selectedColor;
  final String unselectedColor;

  /// **选中胶囊的底色**（`#RRGGBB`）。`null` = 用系统玻璃。
  ///
  /// 2026-10-10 用户拍板：「**橙色**」—— 底栏选中那颗字/图标本来就是强调色，
  /// 分段控件却是一块系统灰玻璃，同一屏里两种"选中"。
  /// ⚠️ 盖上去之后 iOS 26 那块**液态玻璃就没了**（这正是当初不设它的理由），
  /// 是有意识的取舍；盖了就得靠底色本身好看。
  final String? selectedTint;
  final double fontSize;

  Map<String, Object?> toMap() => <String, Object?>{
        'labels': labels,
        'selectedIndex': selectedIndex,
        'selectedColor': selectedColor,
        'unselectedColor': unselectedColor,
        'selectedTint': selectedTint,
        'fontSize': fontSize,
      };
}

/// 参数变了之后该往原生发哪条消息 —— `null` = 什么都不用发。
///
/// 单独抽出来是因为这条决策**在 widget 测试里看不见**：`_channel` 要等原生
/// `onPlatformViewCreated` 才建起来，而测试里没有原生那一侧，`invokeMethod`
/// 静默丢弃。抽成纯函数才钉得住"段数变了必须整块重建"。
///
/// * `setSpec` —— 段数或文字变了。`setSelected` 只挪选中位，**改不了标题**：
///   只发后者的话界面上会留着上一套标签（「身体数据」页撤销授权后可选指标
///   从 4 个变 3 个，正是这条路）。
/// * `setSelected` —— 段没变、只是选中位变了（用户点了别的格，或 Dart 那边改了）。
@visibleForTesting
String? nativeSegmentedUpdate({
  required List<String> oldLabels,
  required int oldIndex,
  required List<String> newLabels,
  required int newIndex,
}) {
  if (!sameLabels(oldLabels, newLabels)) return 'setSpec';
  if (oldIndex != newIndex) return 'setSelected';
  return null;
}

/// 两份标签逐字相等？（顺序也算，原生的格是按顺序插的）
@visibleForTesting
bool sameLabels(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 一块**真的 `UISegmentedControl`**。
///
/// 非 iOS 返回 `SizedBox.shrink()` —— 那些平台由调用方（`ViSegmented`）自己用 Flutter 画。
class NativeSegmented extends StatefulWidget {
  const NativeSegmented({
    super.key,
    required this.spec,
    required this.width,
    this.height = 32,
    this.onChanged,
  });

  final NativeSegmentedSpec spec;

  /// 显式宽度（= `itemWidth × 段数`）：等宽由我们定，原生不许按内容撑开
  final double width;
  final double height;

  /// 用户点了某一段（原生回调，0 起）
  final ValueChanged<int>? onChanged;

  @override
  State<NativeSegmented> createState() => _NativeSegmentedState();
}

class _NativeSegmentedState extends State<NativeSegmented> {
  MethodChannel? _channel;

  void _onCreated(int id) {
    _channel = MethodChannel('lianleme/native_segmented/$id');
    _channel!.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onChanged') {
        final Object? args = call.arguments;
        final Object? raw = args is Map ? args['index'] : null;
        if (raw is num) widget.onChanged?.call(raw.toInt());
      }
    });
  }

  @override
  void didUpdateWidget(NativeSegmented old) {
    super.didUpdateWidget(old);
    // 该发哪条由 `nativeSegmentedUpdate` 定（那是个纯函数，有单测）。
    switch (nativeSegmentedUpdate(
      oldLabels: old.spec.labels,
      oldIndex: old.spec.selectedIndex,
      newLabels: widget.spec.labels,
      newIndex: widget.spec.selectedIndex,
    )) {
      case 'setSpec':
        // 段数/文字变了要整块重建：`setSelected` 只挪选中位，改不了标题。
        _channel?.invokeMethod<void>('setSpec', widget.spec.toMap());
      case 'setSelected':
        _channel?.invokeMethod<void>('setSelected', <String, Object?>{
          'index': widget.spec.selectedIndex,
        });
      case _:
        break;
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassSurface.isSupportedPlatform) return const SizedBox.shrink();
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: UiKitView(
        key: const Key('native-segmented'),
        viewType: 'lianleme/native_segmented',
        layoutDirection: TextDirection.ltr,
        creationParams: widget.spec.toMap(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        // 真控件自己接触摸（与底栏那条同源的理由）
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      ),
    );
  }
}
