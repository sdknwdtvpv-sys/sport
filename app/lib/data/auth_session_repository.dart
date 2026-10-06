/// 练了么 · 登录会话的落盘（drift 实现）
///
/// 对应表 `auth_session`（`app/lib/data/db.dart`，v22 新增）。这一层只做一件事：
/// 把 `LoginSession` 要存的那份东西**原样**读写进本机库 —— 判断与安全逻辑都在
/// `lib/backup/login_session.dart`，这里不重复一遍（两处都判就会分叉）。
///
/// 三条与本仓库其它表一致的规矩：
///
///   1. **一行**（`user_id` 恒为 `local`）：这台设备当前登录的是谁。多账号切换是以后的事，
///      但按 `user_id` 做主键把位置留在那儿了（与 `user_profile` / `backup_account` 同款）。
///   2. **账号密钥按 blob 存**，不做 base64 / hex 转换 —— 转换只会多一处可能出错的编码。
///   3. **它会被「删除全部数据」清掉**（`drift_local_store.deleteAllUserData`），
///      也有表清单守门盯着（`app/test/delete_all_test.dart`）。
library;

import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../backup/login_session.dart';
import 'db.dart';

/// `user_id` 的常量值（与 `ProfileRepository` / 云备份账号同一套）
const String kAuthSessionUserId = 'local';

class AuthSessionRepository implements SessionStore {
  AuthSessionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<StoredSession?> read() async {
    final AuthSessionData? row = await (_db.select(_db.authSession)
          ..where((AuthSession t) => t.userId.equals(kAuthSessionUserId)))
        .getSingleOrNull();
    if (row == null) return null;
    return StoredSession(
      token: row.token,
      email: row.email,
      accountId: row.accountId,
      accountKey: Uint8List.fromList(row.accountKey),
      saltHex: row.saltHex,
      kdf: row.kdf,
      loginAtMs: row.loginAtMs,
    );
  }

  @override
  Future<void> write(StoredSession session) async {
    await _db.into(_db.authSession).insertOnConflictUpdate(AuthSessionCompanion.insert(
          userId: kAuthSessionUserId,
          token: session.token,
          email: session.email,
          accountId: session.accountId,
          accountKey: session.accountKey,
          saltHex: session.saltHex,
          kdf: session.kdf,
          loginAtMs: session.loginAtMs,
        ));
  }

  @override
  Future<void> clear() async {
    await (_db.delete(_db.authSession)
          ..where((AuthSession t) => t.userId.equals(kAuthSessionUserId)))
        .go();
  }
}
