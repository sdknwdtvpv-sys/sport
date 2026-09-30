/// 练了么 · 云备份的开关到底由什么决定
///
/// **结论：编译期常量。没有配服务器地址的包，界面上连"云备份"这个入口都不会出现。**
///
/// 为什么做成编译期而不是一个运行时开关：
///
///   * 现在**还没有服务器**（买服务器/域名/备案在用户那边，见
///     `docs/backend-design.md` 阶段 4）。发一个"点进去永远报错"的入口，
///     比没有这个功能更伤 —— 用户会以为自己的网有问题。
///   * 隐私政策必须**始终是真的**。没有配地址 = 这个包在任何情况下都不会把
///     训练明细发出去，政策里"数据不出设备"那几句就依然成立。
///     一旦某个包配了地址，`tool/privacy-audit.mjs` 会**强制**要求政策正文
///     同步改写（见 `docs/privacy-facts.json` 的 `cloudBackup`）—— 靠人记得改
///     是靠不住的，2026-09-29 埋点那次就是这么漂的。
///
/// 开发与真机验证用（走本机后端）：
///
/// ```bash
/// adb reverse tcp:8790 tcp:8790
/// flutter run --release --dart-define=LIANLEME_BACKUP_URL=http://127.0.0.1:8790
/// ```
///
/// ⚠️ 正式包**必须**是 `https://`：账号凭据（`account_id`）在
/// `Authorization` 头里明文传，明文 HTTP 等于把它交给同网的任何人。
library;

/// 编译期注入的服务器地址（默认空串 = 不启用云备份）
const String kBackupUrlDefine = String.fromEnvironment('LIANLEME_BACKUP_URL');

/// 这个包到底有没有云备份后端
bool get isCloudBackupConfigured => kBackupUrlDefine.trim().isNotEmpty;

/// 服务器根地址。没配就是 null —— 调用方必须先问 [isCloudBackupConfigured]。
Uri? get cloudBackupBaseUrl {
  if (!isCloudBackupConfigured) return null;
  final Uri? parsed = Uri.tryParse(kBackupUrlDefine.trim());
  // 解析不出来也当没配：宁可没有这个功能，也不要一个必定失败的入口。
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return null;
  return parsed;
}

/// [cloudBackupBaseUrl] 是不是明文的 http（**只允许在开发时出现**）
///
/// 不做成断言：真机验证要走 `adb reverse` + `http://127.0.0.1`，
/// 那时候硬崩会挡住调试。但界面上会如实标出来，别让它悄悄流到正式包里。
bool get isCloudBackupPlainHttp => cloudBackupBaseUrl?.scheme == 'http';
