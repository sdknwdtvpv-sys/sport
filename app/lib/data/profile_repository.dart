/// 练了么 · 用户设置（读写 user_profile 那一行）
///
/// 单行表：本地只有一个用户，所以用固定 id。
/// 现在真的被用到的只有 `progression_mode` —— S10「我」的那个开关。
library;

import 'package:drift/drift.dart' show Value;

import '../core/units.dart';
import '../domain/models.dart';
// db.dart（drift 表）与 models.dart（领域模型）都定义了 Workout / SetRecord，预先 hide。
import '../backup/login_session.dart';
import 'auth_session_repository.dart';
import 'db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;

class ProfileRepository {
  ProfileRepository(this._db);

  final AppDatabase _db;

  /// 登录会话的落盘仓储（账号体系 P1-3）。
  ///
  /// 为什么挂在这里：这一层的仓储手里有 `AppDatabase`，而账号页是从「我」页那条链
  /// （`ProfileScreen` → `DataToolsScreen`）进来的，那条链上只有 `ProfileRepository`。
  /// 与其把 db 一路透传，不如让它把"这个库上的一张表"交出去 ——
  /// 与 `cloudAccount()` / `setCloudAccount()`（同一张库里的云备份账号）同源。
  SessionStore authSessionStore() => AuthSessionRepository(_db);

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
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            // 同样：带 withDefault 的列在 Dart 数据类里仍必填，且必须保留已有值
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            // 可空列在 drift 的 data class 里是**可选参数**，但 `insertOnConflictUpdate`
            // 会把整行写一遍 —— 不显式带上就会写成 null，把"已同意隐私政策"抹掉，
            // 于是下次冷启动又弹一次。所以每个 setter 都必须原样带回来。
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// 「帮助改进产品」的**产品默认值**：**开**（2026-10-07 用户拍板）。
  ///
  /// ⚠️ 读这一段之前先看 `docs/plan-ux-2026-10-07.md` §三·9 那张施工单：
  /// 这个默认值在 2026-09-30 被审计改成过"关"（理由是"默认同意站不住"），
  /// 2026-10-07 用户在原话里问"帮助改进产品能不能默认打开？"并明确选了"真改成开"。
  /// 所以这不是谁手滑翻的 —— 是一个**知情的反转**，政策中英、同意屏、商店文本
  /// 与 `tool/privacy-audit.mjs` 的判据方向都跟着一起翻（那几条都必须同时改）。
  ///
  /// ⚠️ **它只对"还没有那一行"的机器生效**（= 新装）。存量机器库里有那一行，
  /// 读出来的就是它自己的值 —— **我们不静默翻转存量用户的选择**：
  /// 他们当初看到的是"默认关闭"，把那个值改成 true 等于对着一份旧承诺收集数据。
  static const bool analyticsDefaultOn = true;

  /// 「帮助改进产品」开关，默认开
  Future<bool> analyticsEnabled() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.analyticsEnabled ?? analyticsDefaultOn;
  }

  /// **昵称**（2026-10-07，v24，10.7 清单第 7 条）。null = 没设过。
  ///
  /// ⚠️ 它**不是身份**：纯本地、不上报、不进云备份的合并键。身份那件事由账号 ID 承担
  /// （`auth_session.account_id` 的前 8 位；没登录就不显示，见身份块）。
  Future<String?> nickname() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    final String? n = row?.nickname?.trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  /// 写昵称。**空白等于没设**（存 null，而不是存空串 —— 否则界面上会有两种"空"）。
  ///
  /// ⚠️ **不能用 `insertOnConflictUpdate`**：实测它**不会把已存在的值写成 NULL**
  /// （先设"李松"、再传 null 走那条路，库里读回来还是"李松"；这条测试当场抓到）。
  /// 而"清空昵称"是用户明确做的动作，所以这一格单独用一条 `update` 精确写两列 ——
  /// 顺带也就不会碰别的设置（可空列那一堆坑在这里一次性绕开）。
  Future<void> setNickname(String? name, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final String? n = name?.trim();
    final String? value = (n == null || n.isEmpty) ? null : n;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    if (existing == null) {
      // 还没有那一行：建一行（其余列按默认值落上）
      await _db.into(_db.userProfile).insert(UserProfileData(
            userId: kLocalUserId,
            progressionMode: 'double',
            unitPref: 'kg',
            bodyWeightUnit: 'kg',
            defaultRestSec: 90,
            analyticsEnabled: analyticsDefaultOn,
            nickname: value,
            createdAt: now,
            updatedAt: now,
          ));
      return;
    }

    await (_db.update(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .write(UserProfileCompanion(
      nickname: Value<String?>(value),
      updatedAt: Value<int>(now),
    ));
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
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: enabled,
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
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

  /// `user_profile.default_rest_sec` 用 **0 表示「跟随动作自带的休息时长」**。
  ///
  /// 为什么用哨兵值而不是 NULL：那一列是 `NOT NULL DEFAULT 90`，
  /// 改成可空要重建表（SQLite 不能直接去掉 NOT NULL），而老用户的库
  /// 已经装到手机上了 —— 为一个偏好设置引入一次表重建不划算。
  /// 0 秒不是一个有意义的休息时长，拿它当哨兵不会和真实取值冲突。
  static const int kRestFollowExercise = 0;

  /// 用户指定的休息时长（秒）。**null = 跟随动作**，这是默认。
  Future<int?> restOverrideSec() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    final int v = row?.defaultRestSec ?? kRestFollowExercise;
    return v == kRestFollowExercise ? null : v;
  }

  /// 写入休息时长偏好。[sec] 传 null 表示回到「跟随动作」。
  ///
  /// 和 [setUnit] / [setProgressionMode] 一样**必须把其它设置原样带回去**。
  Future<void> setRestOverrideSec(int? sec, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: sec ?? kRestFollowExercise,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            // 可空列在 drift 的 data class 里是**可选参数**，但 `insertOnConflictUpdate`
            // 会把整行写一遍 —— 不显式带上就会写成 null，把"已同意隐私政策"抹掉，
            // 于是下次冷启动又弹一次。所以每个 setter 都必须原样带回来。
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// 训练目标（S13）。没设置过返回 null —— 界面据此判断要不要邀请引导。
  ///
  /// 这里读的是**原始 wire 字符串**（hypertrophy / strength / fat_loss / maintain）：
  /// 枚举定义在 feature 层，数据层不该反向依赖它。
  Future<String?> goalWire() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.goal;
  }

  /// 一周练几天。没设置过返回 null。
  Future<int?> weeklyFrequency() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.weeklyFrequency;
  }

  /// 记下引导的结果（目标 + 频率）。
  ///
  /// 和其它 setter 一样**必须把其余设置原样带回去** ——
  /// 否则用户在引导里选个目标，就把单位 / 休息 / 隐私开关全重置了。
  Future<void> setOnboarding({
    required String goalWire,
    required int weeklyFrequency,
    int? nowMs,
  }) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            goal: goalWire,
            weeklyFrequency: weeklyFrequency,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? kRestFollowExercise,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            // 可空列在 drift 的 data class 里是**可选参数**，但 `insertOnConflictUpdate`
            // 会把整行写一遍 —— 不显式带上就会写成 null，把"已同意隐私政策"抹掉，
            // 于是下次冷启动又弹一次。所以每个 setter 都必须原样带回来。
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// 显示单位。没有档案时返回 kg（与 `unit_pref` 的 DB 默认值一致）。
  ///
  /// 注意这里读的只是**显示**偏好 —— 存储与引擎始终是 kg，见 core/units.dart。
  /// 身高（cm）。2026-10-05（v20）。**只用来算 BMI** —— 没填就不显示 BMI，
  /// 而不是拿默认身高编一个数出来（编出来的 BMI 比没有 BMI 更糟）。
  Future<double?> heightCm() async {
    final UserProfileData? row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.heightCm;
  }

  /// 存身高。连带把这一列的其它设置原样带回去（drift 的 upsert 写整行 ——
  /// 漏一列就会被抹成默认值，这个坑项目里踩过三次，注释写在下面 `setUnit` 那里）。
  Future<void> setHeightCm(double? cm, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final UserProfileData? existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            goal: existing?.goal,
            weeklyFrequency: existing?.weeklyFrequency,
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            progressionMode: existing?.progressionMode ?? 'double',
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            heightCm: cm,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  Future<WeightUnit> unit() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return WeightUnit.fromWire(row?.unitPref);
  }

  /// 体重单位（千克 / 斤）。**与训练重量单位是两个设置**。
  ///
  /// 没有档案时返回 kg —— 与 `body_weight_unit` 的 DB 默认值一致。
  Future<BodyWeightUnit> bodyWeightUnit() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return BodyWeightUnit.fromWire(row?.bodyWeightUnit);
  }

  /// 写入体重单位。和别的设置一样：**必须把其它列原样带回去**。
  Future<void> setBodyWeightUnit(BodyWeightUnit unit, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            goal: existing?.goal,
            weeklyFrequency: existing?.weeklyFrequency,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: unit.wire,
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            // 可空列在 drift 的 data class 里是**可选参数**，但 `insertOnConflictUpdate`
            // 会把整行写一遍 —— 不显式带上就会写成 null，把"已同意隐私政策"抹掉，
            // 于是下次冷启动又弹一次。所以每个 setter 都必须原样带回来。
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// 写入显示单位。
  ///
  /// **必须把其它设置原样带回去** —— 这正是 `setProgressionMode` 注释里
  /// 记着的那个坑：只写自己那一列、其余传默认值，会把用户别的设置悄悄抹掉。
  /// 改**训练重量**的显示单位。
  ///
  /// **体重单位默认跟着它走**（2026-10-01 统一口径，真机走查发现的真实不一致：
  /// 以前全局选了 lb，身体数据页还写着 kg）。
  /// 联动的判据是"用户有没有单独选过"：体重单位**本来就等于旧全局值**（或还没写过）
  /// 就一起换；已经不一样了（比如用户单独选了「斤」）→ 那是他的选择，不动。
  Future<void> setUnit(WeightUnit unit, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    final String? oldBody = existing?.bodyWeightUnit;
    final bool bodyFollowsGlobal = oldBody == null || oldBody == existing?.unitPref;

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: unit.wire,
            // ⚠️ 这里也必须带上体重单位 —— 它和训练重量是**两个**设置。
            // 默认跟随：跟随状态下换全局单位，体重单位一起换（见上面那段注释）。
            bodyWeightUnit: bodyFollowsGlobal ? unit.wire : oldBody,
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            // 可空列在 drift 的 data class 里是**可选参数**，但 `insertOnConflictUpdate`
            // 会把整行写一遍 —— 不显式带上就会写成 null，把"已同意隐私政策"抹掉，
            // 于是下次冷启动又弹一次。所以每个 setter 都必须原样带回来。
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  // ---------------------------------------------------------------- 隐私政策同意

  /// 首次启动的隐私政策同意时刻。null = 还没同意过（要弹窗）。
  Future<int?> privacyConsentAtMs() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.privacyConsentAtMs;
  }

  /// 记下"用户同意了隐私政策"。**只写不清** —— 同意了就不再问。
  Future<void> setPrivacyConsent({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            privacyConsentAtMs: existing?.privacyConsentAtMs ?? now,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// 用户**明确拒绝过**的时刻（null = 没拒绝过）。
  /// 身体数据（体重）的**单独同意**时刻；null = 还没单独同意过。
  ///
  /// 与"政策总同意"分开存：PIPL 第 29 条要求敏感个人信息**单独同意**，
  /// 而首次启动那道门征求的是政策总同意 —— 两者不是一回事，不能互相顶替。
  Future<int?> bodyMetricConsentAtMs() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.bodyMetricConsentAtMs;
  }

  /// 记下"他单独同意过处理体重这件事"。
  ///
  /// 形状照抄 `setPrivacyDeclined`：**每个 setter 都必须把已有字段原样带回去**，
  /// 否则 `insertOnConflictUpdate` 会把整行覆盖掉、把别的设置抹了。
  Future<void> setBodyMetricConsent({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs ?? now,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// **撤回**"处理体重"的同意（PIPL 第 15 条给的是撤回权，不只是删除权）。
  ///
  /// 撤回只做一件事：把那条同意记录清成 null —— 于是「身体数据」页下次进来会
  /// **重新弹那道门**（不再收集），而**已经记下来的体重数据一个字都不动**：
  /// 删数据是另一件事，得由用户单独决定（那在「全部数据」里做）。
  /// 把两件事合成一个动作是这类功能最常见的错：用户点"撤回同意"，
  /// 结果把历史记录一起抹了。
  ///
  /// ⚠️ **必须用 Companion + `Value(null)`**，不能照抄上面那些 setter 的写法：
  /// drift 对 `UserProfileData` 用 `nullToAbsent: true`，字段是 null 就当作
  /// "这次没提供"而**跳过这一列**，冲突时保留旧值 —— 那样写出来的效果是
  /// "点了撤回，同意还在"（同一个坑在 `body_metric_repository.dart` 里已经踩过一次，
  /// 那次是软删除的记录复活不了）。
  Future<void> clearBodyMetricConsent({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    // 连这一行都还没建过：没有"同意"可撤回，就什么都别写（不新建行）
    if (existing == null) return;

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileCompanion(
            userId: Value<String>(kLocalUserId),
            bodyMetricConsentAtMs: const Value<int?>(null),
            // createdAt 是**非空列**，Companion 里必须显式给（否则 drift 直接判无效）
            createdAt: Value<int>(existing.createdAt),
            updatedAt: Value<int>(now),
          ),
        );
  }

  // ── 用户自己设的「默认加重步进」（v26，2026-10-09，10.9 清单第 8a 条）──────────
  //
  // 为什么要它：步进本来只来自动作自己的 `weight_increment`（哑铃 2、器械 5、杠铃 2.5…），
  // 而**有些健身房的片子只有 5 kg 一档** —— 那种地方每个动作手改一次步进不现实。
  // 语义：**null = 没设过**（各动作用自己的）；设了之后由设置页那次"铺到所有动作"来落地，
  // 单个动作在训练屏里改的**更优先**（那写在动作自己的 `weight_increment` 上）。

  /// 读全局默认步进（kg）。null = 用户没设过。
  Future<double?> defaultWeightIncrement() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.defaultWeightIncrement;
  }

  /// 记下全局默认步进（`null` = 恢复成"各动作用自己的"）。
  ///
  /// ⚠️ 用 **Companion + `Value<double?>(kg)`**，而不是 `UserProfileData`：
  ///   * `null` 在这里是**一个有意义的值**（"没设过，各动作用自己的"），
  ///     而 drift 对 DataClass 是 `nullToAbsent` —— 写 null 会被当成"这次没提供"而跳过，
  ///     于是"点了恢复默认却还是旧值"（同一个坑在 clearBodyMetricConsent 那里踩过一次）；
  ///   * Companion 只碰列出来的这几列，不必把十几个字段原样抄一遍（抄漏一个就是老 bug）。
  /// `createdAt` 是**非空列**，而这一行可能是第一次建（用户还没动过设置）→ 显式给。
  Future<void> setDefaultWeightIncrement(double? kg, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileCompanion(
            userId: Value<String>(kLocalUserId),
            defaultWeightIncrement: Value<double?>(kg),
            createdAt: Value<int>(existing?.createdAt ?? now),
            updatedAt: Value<int>(now),
          ),
        );
  }

  /// **在哪儿练**（2026-10-09 第二份 docx 第 4 条）。null = 没选过（按健身房算）。
  Future<String?> trainingScenario() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.trainingScenario;
  }

  /// 记下"在哪儿练"。`null` = 恢复成"没选过"（按健身房算）。
  ///
  /// ⚠️ 与 `setDefaultWeightIncrement` 同一条纪律：用 **Companion + `Value<String?>`**，
  /// 不能用 DataClass（drift 对 DataClass 是 `nullToAbsent`，"清回默认"会静默失效）。
  Future<void> setTrainingScenario(String? wire, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileCompanion(
            userId: Value<String>(kLocalUserId),
            trainingScenario: Value<String?>(wire),
            createdAt: Value<int>(existing?.createdAt ?? now),
            updatedAt: Value<int>(now),
          ),
        );
  }

  Future<int?> privacyDeclinedAtMs() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.privacyDeclinedAtMs;
  }

  // ── 「从系统健康库读取体成分」那道单独同意（v25，2026-10-09）──────────────────
  //
  // 三件事与身体数据那道门同构，但**是另一道门**：同意的是"去读系统健康库里
  // 别人写进去的记录"，不是"把体重记在本机"。详见 `db.dart` 里
  // `healthConsentAtMs` 的注释与 `docs/plan-health-sync.md`。

  /// 读那道同意的时刻；null = 从没同意过（= 一次都没读过健康库）。
  Future<int?> healthConsentAtMs() async {
    final row = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    return row?.healthConsentAtMs;
  }

  /// 记下"他单独同意过去读系统健康库"。
  ///
  /// 形状照抄 [setBodyMetricConsent]：**每个 setter 都必须把已有字段原样带回去**，
  /// 否则 `insertOnConflictUpdate` 会把整行覆盖掉、把别的设置抹了。
  Future<void> setHealthConsent({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            nickname: existing?.nickname,
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            healthConsentAtMs: existing?.healthConsentAtMs ?? now,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// **撤回**"去读系统健康库"的同意（PIPL 第 15 条给的是撤回权，不只是删除权）。
  ///
  /// 撤回只做一件事：把那条同意记录清成 null —— 于是下次点「从系统健康同步」时
  /// **重新弹那道门**（不再读），而**已经拉进来的体重数据一个字都不动**：
  /// 删数据是另一件事，由用户在「全部数据」里单独决定。
  ///
  /// ⚠️ **必须用 Companion + `Value(null)`**（理由与 [clearBodyMetricConsent] 那段完全一样：
  /// drift 对 `UserProfileData` 是 `nullToAbsent: true`，写 null 会被当成"这次没提供"
  /// 而跳过这一列 —— 效果是"点了撤回，同意还在"）。
  Future<void> clearHealthConsent({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
    if (existing == null) return;

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileCompanion(
            userId: Value<String>(kLocalUserId),
            healthConsentAtMs: const Value<int?>(null),
            createdAt: Value<int>(existing.createdAt),
            updatedAt: Value<int>(now),
          ),
        );
  }

  /// 记下"用户选择了不同意"。
  ///
  /// ⚠️ **这不是同意**，两列各自为真：同意过就写 [setPrivacyConsent]，拒绝过就写这里。
  /// 拒绝之后 App 照常可用（离线功能本来就不需要联网与权限），**只是不收集任何东西**：
  /// 埋点根本不会启动（见 `main.dart` 的 `_loadConsentThenStart`）。
  Future<void> setPrivacyDeclined({int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await (_db.select(_db.userProfile)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();

    await _db.into(_db.userProfile).insertOnConflictUpdate(
          UserProfileData(
            userId: kLocalUserId,
            progressionMode: existing?.progressionMode ?? 'double',
            unitPref: existing?.unitPref ?? 'kg',
            bodyWeightUnit: existing?.bodyWeightUnit ?? 'kg',
            defaultRestSec: existing?.defaultRestSec ?? 90,
            analyticsEnabled: existing?.analyticsEnabled ?? analyticsDefaultOn,
            // 可空列在 insertOnConflictUpdate 里会被写成 null —— 昵称必须原样带回来，
            // 否则「改一下单位，昵称就没了」（与上面那几列同一个坑，v24 新加的列也要接上）
            nickname: existing?.nickname,
            // v25 新加的可空列同样要原样带回来，否则「改个昵称，健康库那道同意就没了」
            healthConsentAtMs: existing?.healthConsentAtMs,
            defaultWeightIncrement: existing?.defaultWeightIncrement,
          trainingScenario: existing?.trainingScenario,
            privacyConsentAtMs: existing?.privacyConsentAtMs,
            privacyDeclinedAtMs: existing?.privacyDeclinedAtMs ?? now,
            bodyMetricConsentAtMs: existing?.bodyMetricConsentAtMs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  // ---------------------------------------------------------------- 云备份

  /// 云备份账号（**没有就是 null = 这台机器还没开过云备份**）。
  ///
  /// 默认关闭是靠"这张表空着"表达的，不另设一个 boolean ——
  /// 两个来源（开关 + 恢复码）早晚会打架，而只有一个来源时不可能不一致。
  Future<BackupAccountData?> cloudAccount() async {
    return (_db.select(_db.backupAccount)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .getSingleOrNull();
  }

  /// 开启云备份：把恢复码记下来。重复调用就用新的码覆盖。
  ///
  /// ⚠️ 覆盖恢复码等于**换了一个账号**（`account_id` 由它派生），
  /// 云上旧那份就再也打不开了。所以界面上必须拦一道，不能悄悄覆盖。
  Future<void> setCloudAccount(String recoveryCode, {int? nowMs}) async {
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final existing = await cloudAccount();
    await _db.into(_db.backupAccount).insertOnConflictUpdate(
          BackupAccountData(
            userId: kLocalUserId,
            recoveryCode: recoveryCode,
            enabledAtMs: existing?.enabledAtMs ?? now,
            lastUploadAtMs: existing?.lastUploadAtMs,
            lastUploadBytes: existing?.lastUploadBytes,
          ),
        );
  }

  /// 记下"刚成功备份过"。失败时**不要**调它 —— 界面上的"上次备份于…"
  /// 一旦会撒谎，用户就会以为数据安全了。
  Future<void> markCloudUpload(int bytes, {int? nowMs}) async {
    final existing = await cloudAccount();
    if (existing == null) return;
    await _db.into(_db.backupAccount).insertOnConflictUpdate(
          BackupAccountData(
            userId: kLocalUserId,
            recoveryCode: existing.recoveryCode,
            enabledAtMs: existing.enabledAtMs,
            lastUploadAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
            lastUploadBytes: bytes,
          ),
        );
  }

  /// 关闭云备份：**只清本机凭据**。
  ///
  /// 云上那份仍然在（用户可能想留着，用恢复码在别的设备上还能取回来）。
  /// 真要连云端一起删，走 [CloudBackup.deleteAccount]。
  Future<void> clearCloudAccount() async {
    await (_db.delete(_db.backupAccount)
          ..where((t) => t.userId.equals(kLocalUserId)))
        .go();
  }
}
