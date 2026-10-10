/// 练了么 · **iOS 26 的开关**：直接用系统的 `UISwitch`
///
/// 用户 2026-10-06 的备忘条第 3 条：「开关按钮没有上苹果的原生玻璃效果」。
/// 那时候开关是 Flutter 的 Material `Switch`（一颗实心胶囊 + 一个圆点），
/// 与 iOS 26 的液态玻璃开关完全不是同一个东西。
///
/// **为什么不自己画一个**：Material 那套做不到；自己用 `UIView` 仿也要重写材质、
/// 按压回弹、旁白语义 —— 而且永远差一点。`UISwitch` 在 iOS 26 上**自带**液态玻璃，
/// 这正是"用用户已经会的东西"那条一贯做法。
///
/// ## 边界（与其它玻璃件一致）
///   * **非 iOS 原样返回 Material `Switch`**（Android 一个像素都不动）；
///   * iOS 26 以下也是系统 `UISwitch`（老系统上是老样子 —— 那**正是**如实的样子）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart';
import 'theme.dart';

class GlassSwitch extends StatefulWidget {
  const GlassSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch> {
  static const String _viewType = 'lianleme/switch';

  /// `UISwitch` 的尺寸是系统定的（不同版本会变），给它一块**富余的盒子**再居中，
  /// 免得哪天系统把开关画大一点就被裁掉。
  static const Size _box = Size(64, 40);

  MethodChannel? _channel;

  void _onCreated(int id) {
    _channel = MethodChannel('lianleme/switch/$id');
  }

  @override
  void didUpdateWidget(GlassSwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      // 值由 Dart 说了算：原生只负责"画成系统那个样子"与把用户的操作报回来
      _channel?.invokeMethod<void>('setValue', <String, Object?>{'value': widget.value});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassSurface.isSupportedPlatform) {
      // Android：老样子（Material 开关）
      return Switch(
        value: widget.value,
        onChanged: widget.onChanged,
        activeThumbColor: Tokens.accentInk,
        activeTrackColor: Tokens.accent,
      );
    }

    return SizedBox(
      width: _box.width,
      height: _box.height,
      child: UiKitView(
        viewType: _viewType,
        onPlatformViewCreated: _onCreated,
        creationParams: <String, Object?>{
          'value': widget.value,
          'onColor': _hex(Tokens.accent),
        },
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
    );
  }
}

String _hex(Color c) {
  final int v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 一行「标题 + 说明 + 开关」，两端外观**刻意不同**：
///   * iOS：`ListTile` + [GlassSwitch]（原生玻璃开关）；
///   * Android：`SwitchListTile`（与以前一个像素都不差）。
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    if (!GlassSurface.isSupportedPlatform) {
      return SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Tokens.accentInk,
        activeTrackColor: Tokens.accent,
        title: title,
        subtitle: subtitle,
      );
    }
    return ListTile(
      onTap: () => onChanged(!value),
      title: title,
      subtitle: subtitle,
      trailing: GlassSwitch(value: value, onChanged: onChanged),
    );
  }
}
