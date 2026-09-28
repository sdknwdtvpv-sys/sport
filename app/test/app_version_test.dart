/// 练了么 · 界面上的版本号必须与 `pubspec.yaml` 一致
///
/// 这个文件存在的唯一理由，是一个真实发生过的事故：
/// 版本号曾经写死在 `profile_screen.dart` 里，v1.1.0 与 v1.2.0 两次切版
/// **都没带上它** —— 界面上一直写着「版本 1.0.0」，错了两个版本没人发现，
/// 直到有人在真机上多看了一眼「我」页。
///
/// 一个字符串不值得引入 `package_info_plus`，但值得一条测试：
/// 切版时 bump 了 pubspec 却忘了改 `kAppVersion`，这里会红。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/app_info.dart';

void main() {
  test('kAppVersion 与 pubspec.yaml 的 version 前缀一致（忘了改就红）', () {
    // flutter test 的工作目录就是 app/，所以直接读得到 pubspec.yaml。
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final RegExpMatch? m =
        RegExp(r'^version:\s*(\S+)$', multiLine: true).firstMatch(pubspec);

    expect(m, isNotNull, reason: 'pubspec.yaml 里必须有一行 version:');
    // pubspec 写的是 1.2.0+3 这种「版本+build number」，界面上只显示版本。
    final String pubspecVersion = m!.group(1)!.split('+').first;

    expect(
      kAppVersion,
      pubspecVersion,
      reason: 'pubspec.yaml 是 $pubspecVersion，而 core/app_info.dart 里是 '
          '$kAppVersion —— 切版时两处都要改（界面上显示的是 kAppVersion）',
    );
  });
}
