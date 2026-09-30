/// 练了么 · 云备份开关的判定（配置层）
///
/// 这里守的是一句**对外承诺**：没配地址的包里，政策正文写着「本版本未提供云备份」，
/// 而这句话必须**永远为真**。光有地址是不够的 —— 只有地址、没有
/// `LIANLEME_BACKUP_DISCLOSED` 时入口不该出现，否则界面与政策互相矛盾。
///
/// `String.fromEnvironment` 是编译期常量，一个测试进程里给不了两种取值，
/// 所以判定逻辑抽成了 `cloudBackupConfiguredFor` 纯函数，四种组合全钉在这里；
/// 编译期那两个常量本身只验"默认构建是关的"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/backup/backup_config.dart';

void main() {
  group('云备份开关', () {
    test('两个都给了才算配好', () {
      expect(
        cloudBackupConfiguredFor(url: 'https://api.example.com', disclosed: true),
        isTrue,
      );
    });

    test('只有地址、没有"政策已改写"的声明 → 不算配好（失败往关闭倒）', () {
      expect(
        cloudBackupConfiguredFor(url: 'https://api.example.com', disclosed: false),
        isFalse,
      );
    });

    test('声明了但没有地址 → 不算配好（没有后端可用）', () {
      expect(cloudBackupConfiguredFor(url: '', disclosed: true), isFalse);
    });

    test('两个都没有 → 不算配好（默认构建就是这一种）', () {
      expect(cloudBackupConfiguredFor(url: '', disclosed: false), isFalse);
    });

    test('只有空白的地址也不算数', () {
      expect(
        cloudBackupConfiguredFor(url: '   \n ', disclosed: true),
        isFalse,
      );
    });

    test('默认构建（测试环境没有 dart-define）：入口不该出现', () {
      // 这一条钉的是"编译期默认值"本身：上面五条只证明公式对，
      // 这条证明**没传 define 时拿到的就是关闭**。
      expect(kBackupUrlDefine, isEmpty);
      expect(isCloudBackupConfigured, isFalse);
    });
  });
}
