/// 展示字体（Oswald）的**存在性**与**接线**核对。
///
/// **为什么需要它**：换字体这件事有三种"看起来做了、其实没做"的失败方式，而且都不报错：
///   1. 文件没进 `app/fonts/`（或名字打错）→ 编译照样过，运行时静默回落系统字体；
///   2. `pubspec.yaml` 没声明 → 同上；
///   3. 用了但**许可没登记** → 「开源许可」页缺一条，而政策与商店都要求"应用内可查"。
/// 三条都在这里钉住：读 pubspec、读文件、真的把字体加载起来量一遍宽度。
///
/// ⚠️ 判据用的是"**宽度**"而不是"长得像"：Oswald 是 condensed（窄体），
/// 同一串数字它比默认字体窄得多；**字体一旦没加载成功，两者宽度会相等**，测试立刻红。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// 读仓库里的文件（`flutter test` 的工作目录就是 `app/`）。
String _read(String rel) => File(rel).readAsStringSync();

/// 用某个字体量一串字的宽度（px）。
double _widthOf(String text, {String? family, double size = 100}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: family, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

void main() {
  test('pubspec 声明了 Oswald，而且许可原文也当成 asset 打进去了', () {
    final String pubspec = _read('pubspec.yaml');
    expect(pubspec.contains('family: Oswald'), isTrue,
        reason: 'pubspec.yaml 里没有 Oswald 这个 family —— 字体不会被打进包');
    expect(pubspec.contains('fonts/Oswald-VariableFont_wght.ttf'), isTrue,
        reason: 'pubspec 声明的字体文件路径不对');
    expect(pubspec.contains('fonts/OFL-Oswald.txt'), isTrue,
        reason: '许可原文没当 asset 打包，应用内读不到它');
  });

  test('字体文件真的在仓库里，而且是 TrueType（不是改了后缀的别的东西）', () {
    final File f = File('fonts/Oswald-VariableFont_wght.ttf');
    expect(f.existsSync(), isTrue, reason: 'app/fonts/Oswald-VariableFont_wght.ttf 不存在');
    final Uint8List head = f.openSync().readSync(4);
    // TrueType 的 sfnt 版本号：0x00010000；OpenType/CFF 是 'OTTO'。两种都收。
    final bool sfnt = head[0] == 0x00 && head[1] == 0x01 && head[2] == 0x00 && head[3] == 0x00;
    final bool otto = String.fromCharCodes(head) == 'OTTO';
    expect(sfnt || otto, isTrue, reason: '文件头不是合法字体（前 4 字节：$head）');
    expect(f.lengthSync() > 50000, isTrue, reason: '字体文件太小，像是下坏了');
  });

  test('main.dart 把字体许可登记进了 LicenseRegistry（否则「开源许可」页缺一条）', () {
    final String main = _read('lib/main.dart');
    expect(main.contains('LicenseRegistry.addLicense'), isTrue);
    expect(main.contains('fonts/OFL-Oswald.txt'), isTrue);
  });

  test('Oswald 能真的加载，而且量出来比系统字体窄（condensed）', () async {
    final Uint8List bytes = File('fonts/Oswald-VariableFont_wght.ttf').readAsBytesSync();
    final FontLoader loader = FontLoader('OswaldProbe')
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();

    final double withFont = _widthOf('0123456789', family: 'OswaldProbe');
    final double fallback = _widthOf('0123456789');
    expect(withFont, lessThan(fallback * 0.92),
        reason: 'Oswald 量出来和默认字体一样宽（$withFont vs $fallback）—— '
            '说明它没被加载，运行时同样会静默回落');
  });
}
