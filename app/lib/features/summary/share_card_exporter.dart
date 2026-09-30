/// 练了么 · 把分享卡交给系统
///
/// 抽成接口是为了**可测**：插件调用本身在 widget 测试里验证不了，
/// 但"点了按钮之后到底调了哪个方法、传了什么"完全可以验证。
/// 生产实现是 [PluginShareCardExporter]，测试里换成假的。
///
/// 两条交付路径（对应 pubspec 里记录的那次依赖例外）：
///   * [shareToSystem] —— `share_plus`，拉起系统分享面板。**不需要任何权限**
///   * [saveToGallery] —— `gal`，存进系统相册
library;

import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// 存相册时建的相簿名。用户在系统相册里能一眼找到。
const String kShareAlbumName = '练了么';

abstract class ShareCardExporter {
  /// 拉起系统分享面板（微信、微博等由系统列出）。
  Future<void> shareToSystem(Uint8List png, {String fileName});

  /// 存进系统相册。
  ///
  /// 返回 `false` 表示**没存成**（典型原因是用户拒绝了相册权限）——
  /// 界面上必须如实告诉用户，不能假装成功。
  Future<bool> saveToGallery(Uint8List png, {String fileName});

  /// 这次存相册**会不会弹系统权限框**（Android 10+ 走 MediaStore 免权限 → false）。
  ///
  /// 存在的理由是一条硬规矩：**申请权限时要同步告知目的**
  /// （191 号文二.3；OPPO 审核规范同义）。系统弹框只有一句冷冰冰的"允许写入媒体"，
  /// 用户不知道我们要干什么 —— 所以界面要先自己说一句。不需要权限的平台不该白问一次，
  /// 所以由实现来回答"到底要不要"。
  Future<bool> galleryNeedsPermission();
}

/// 真身：走 share_plus 与 gal。
class PluginShareCardExporter implements ShareCardExporter {
  const PluginShareCardExporter();

  @override
  Future<void> shareToSystem(Uint8List png,
      {String fileName = 'lianleme'}) async {
    final String name = '$fileName.png';
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(png, mimeType: 'image/png', name: name),
        ],
        // 不加这句，接收方拿到的文件名会是一串临时路径名
        fileNameOverrides: <String>[name],
      ),
    );
  }

  @override
  Future<bool> galleryNeedsPermission() async {
    // gal 说"已经有权限"时（Android 10+ 永远如此，走 MediaStore），就不该再问一句
    try {
      return !await Gal.hasAccess();
    } catch (_) {
      // 问不出来时按"需要"处理：多问一句远好过不告而取
      return true;
    }
  }

  @override
  Future<bool> saveToGallery(Uint8List png,
      {String fileName = 'lianleme'}) async {
    // gal 在没有权限的平台上必须先申请。Android 10+ 走 MediaStore 免权限，
    // 所以 hasAccess 会直接返回 true；Android 9 及以下才会真的弹窗。
    if (!await Gal.hasAccess()) {
      final bool granted = await Gal.requestAccess();
      if (!granted) return false;
    }
    await Gal.putImageBytes(png, album: kShareAlbumName, name: fileName);
    return true;
  }
}
