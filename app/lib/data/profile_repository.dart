/// 练了么 · 用户设置（读写 user_profile 那一行）
///
/// 单行表：本地只有一个用户，所以用固定 id。
/// 现在真的被用到的只有 `progression_mode` —— S10「我」的那个开关。
library;

import '../domain/models.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，预先 hide。
import 'db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;

class ProfileRepository {
  ProfileRepository(this._db);

  final AppDatabase _db;

  /// 本地用户 id。多用户是以后的事，现在固定。
  static const String kLocalUserId = 'local';

  /// 读取渐进建议设置。没有档案（从没设置过）时返回引擎的默认值。
  Future<ProgressionMode> progressionMode() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return ProgressionMode.fromWire(row?.progressionMode);
  }

  /// 写入渐进建议设置（没有档案就新建）。
  ///
  /// 注意：drift 里带 `withDefault` 的列在 Dart 数据类里**仍然是 required**，
  /// 所以 user_id / progression_mode / created_at / updated_at 四个都必须显式传。
  Future<void> setProgressionMode(ProgressionMode mode, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: mode.wire,
            // ⚠️ 带 withDefault() 的列在 Dart 数据类里**仍然是 required**，必须显式传。
            // 而且要保留已有值 —— 否则以后再加设置项时，一开一关渐进建议就把别人的设置抹了。
            unitPref: existing?.unitPref ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            // 同样：带 withDefault 的列在 Dart 数据类里仍必填，且必须保留已有值
            analyticsEnabled: existing?.analyticsEnabled ?? true,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// 「帮助改进产品」开关，默认开
  Future<bool> analyticsEnabled() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.analyticsEnabled ?? true;
  }

  /// 写入隐私开关。
  /// 关掉之后 `main.dart` 会换成 NoopAnalytics —— 功能不受任何影响。
  Future<void> setAnalyticsEnabled(bool enabled, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: enabled,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// 是否有过任何记录 —— 「我」页的空态判断用
  Future<bool> hasAnyRecord() async {
    final rows = await (_db.select(_db.setRecord)
          ..where((t) => t.deletedAt.isNull())
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }
}
