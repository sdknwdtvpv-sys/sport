/// 练了么 · 云备份端到端用的 driver
///
/// 这份 driver 刻意**不写截图**（那套在 `screenshot_driver.dart` 里）：
/// 云备份这条链要的是"接口真的通了"，而证据来自两端 ——
/// 设备侧是测试自己的断言与 `LIANLEME-E2E` 日志，宿主侧是后端库里的密文。
/// 这里只做一件事：把 `integrationDriver()` 挂上，让 `flutter drive` 能跑。
library;

import 'dart:async';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
