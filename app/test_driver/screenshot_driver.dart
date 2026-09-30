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
  // 输出目录可以用环境变量覆盖 —— 商店对**宽高比**的要求不一样：
  // 这套截图是从设备上按逻辑分辨率抓的，而 Google Play 要求
  // 宽高比在 1:2 ～ 2:1 之间（第三方资料对"必须 9:16"还是"1:2～2:1"有分歧，
  // 但**两边都排除 20:9**）。所以需要另一套时把设备调成 1080×1920 再跑：
  //   adb shell wm size 1080x1920
  //   SHOT_DIR=../store-assets/screenshots-play flutter drive ...
  //   adb shell wm size reset
  final Directory out = Directory(
    Platform.environment['SHOT_DIR'] ?? '../store-assets/screenshots',
  );
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
