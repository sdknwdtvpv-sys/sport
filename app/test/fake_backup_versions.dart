/// 测试用**假多版本 API**（不联网）
library;

import 'package:lianleme/backup/backup_versions.dart';

class FakeBackupVersionApi implements BackupVersionApi {
  FakeBackupVersionApi({
    this.versions = const <CloudBackupVersion>[],
    this.ultra = true,
    this.listError,
    this.downloadError,
  });

  List<CloudBackupVersion> versions;
  bool ultra;
  BackupVersionException? listError;
  BackupVersionException? downloadError;

  /// seq → 密文信封
  final Map<int, String> envelopes = <int, String>{};

  final List<String> calls = <String>[];
  bool closed = false;

  @override
  Future<BackupVersionList> list() async {
    calls.add('list');
    if (listError != null) throw listError!;
    return BackupVersionList(
      ultra: ultra,
      versions: versions,
      limits: const BackupVersionLimits(
        maxVersions: 10,
        maxBlobBytes: 32 * 1024 * 1024,
        maxTotalBytes: 256 * 1024 * 1024,
      ),
    );
  }

  @override
  Future<String> download(int seq) async {
    calls.add('download:$seq');
    if (downloadError != null) throw downloadError!;
    final String? e = envelopes[seq];
    if (e == null) throw BackupVersionException('这个备份版本不存在', statusCode: 404);
    return e;
  }

  @override
  Future<void> restore(int seq) async {
    calls.add('restore:$seq');
  }

  @override
  void close() => closed = true;
}
