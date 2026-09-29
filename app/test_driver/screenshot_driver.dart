/// 练了么 · 截图用的 driver
///
/// `integration_test` 里 `takeScreenshot()` 拍下的字节**发不到设备本地**，
/// 会通过 driver 协议送回主机 —— 这个文件就是主机那一端：收下来、写成 PNG。
///
/// 产物写进 `store-assets/screenshots/`（入库）。
/// 工作目录是 `app/`，所以用 `../store-assets/...` 指回仓库。
library;

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final Directory out = Directory('../store-assets/screenshots');
  out.createSync(recursive: true);

  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final File f = File('${out.path}/$name.png');
      f.writeAsBytesSync(bytes, flush: true);
      stdout.writeln('  ✓ ${f.path}（${bytes.length} 字节）');
      return true;
    },
  );
}
