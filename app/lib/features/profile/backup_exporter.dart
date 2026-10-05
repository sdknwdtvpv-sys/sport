/// 练了么 · 把备份交给系统
///
/// 与分享卡同一个套路（见 `features/summary/share_card_exporter.dart`）：
/// 抽成接口是为了**可测** —— 插件调用在 widget 测试里验证不了，
/// 但"点了「导出备份」之后到底交出去了什么"完全可以验证。
///
/// 也**不需要新依赖**：`share_plus` 支持 `XFile.fromData`，
/// 所以一个字节数组就能当文件分享出去（存到「文件」、发给自己、AirDrop…），
/// 不用为了写临时文件再引 `path_provider`。
library;

import 'dart:convert';

import 'package:share_plus/share_plus.dart';

abstract class BackupExporter {
  /// 把备份内容交给系统分享面板。**不需要任何权限**。
  Future<void> shareBackup(String json, {required String fileName});
}

/// 真身：走 share_plus。
class PluginBackupExporter implements BackupExporter {
  const PluginBackupExporter({this.subject = '练了么 · 训练记录备份'});

  /// 分享时的主题（邮件/微信里显示的那一行）。
  ///
  /// 加这个字段是为了**同一个通道也能送埋点导出**（`analytics_export.dart`）：
  /// 那份文件不该顶着"训练记录备份"发出去。默认值不变，
  /// 所以既有的调用点与测试替身都不用改。
  final String subject;

  @override
  Future<void> shareBackup(String json, {required String fileName}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(
            utf8.encode(json),
            mimeType: 'application/json',
            name: fileName,
          ),
        ],
        // 不加这句，接收方拿到的文件名会是一串临时路径名
        fileNameOverrides: <String>[fileName],
        subject: subject,
      ),
    );
  }
}
