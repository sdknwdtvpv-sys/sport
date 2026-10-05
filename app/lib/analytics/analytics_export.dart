/// 练了么 · 把本机攒下的埋点事件导出成 **JSONL**
///
/// **为什么需要它**：北极星（首次打开 → 完成第一次训练 ≥ 55%）与
/// `tap_count` 门禁（"less is more"唯一的客观守卫）都是**从事件算出来的**，
/// 而没配上报地址的包里 `_NullTransport` 恒失败 —— 事件只会在本地 `analytics_outbox`
/// 里越攒越多，**没有任何出口**。于是"带手机去健身房真的练一次"那一趟
/// （`ROADMAP.md` 阶段 3）只能得到"顺不顺"的定性印象，
/// 唯一客观指标一个数都拿不到。
///
/// 这个文件给的就是那个出口。三个刻意的设计：
///
///   1. **格式与收集端落盘的一模一样**（一行一条事件 JSON，即 JSONL）。
///      于是它可以直接被 `tool/analytics-report.mjs` 算 ——
///      导出的文件就是那个工具要的输入，中间不需要任何转换。
///   2. **只读、不改动队列**。导出不是"发送"，也不是"清空"；
///      用户随时可以再导一次，内容只会更多。
///   3. **不上报"导出"这个动作本身**。否则"为了让用户拿到数据而记录一次点击"
///      要再写一条政策披露 —— 那是自己给自己造隐私债
///      （`docs/privacy-facts.json` 里的 `doesNotEmitEvent`）。
///
/// 为什么要跟隐私政策同步改：这个出口把**埋点事件原样交给用户**，
/// 而 `docs/privacy-policy.md` §五只写了"可以导出全部记录（CSV）"，
/// 没写"可以导出统计事件"。三处对账（facts ↔ 代码 ↔ 中英政策正文）
/// 由 `tool/privacy-audit.mjs` 核。
library;

import 'dart:convert';

import 'outbox.dart';

/// 导出结果：正文 + 两个用来跟用户交代的数字。
class EventsExport {
  const EventsExport({required this.jsonl, required this.count});

  /// 一行一条事件（JSONL）。空队列时是空字符串 —— 调用方**不该**导出空文件。
  final String jsonl;

  /// 事件条数
  final int count;

  bool get isEmpty => count == 0;

  /// 给人看的一句话
  String get summary => '已导出 $count 条统计事件';
}

/// 把事件编码成 JSONL。**纯函数**，好单测。
///
/// 每行的字段就是**上报时会发出去的那一份**（`AnalyticsEventPayload.toJson()`：
/// `id` / `event` / `ts` / `priority` + 公共字段 + 事件自己的 props），
/// 所以 `tap_count`、`tap_kinds`、`device_id` 都在里面 ——
/// 与 `docs/analytics.md` §3 的口径是同一份，不存在"导出的是另一个东西"。
String buildEventsJsonl(List<AnalyticsEventPayload> events) {
  final StringBuffer out = StringBuffer();
  for (final AnalyticsEventPayload e in events) {
    out.writeln(jsonEncode(e.toJson()));
  }
  return out.toString();
}

/// 导出文件名。带日期，用户存多份也分得清。
///
/// 扩展名用 `.jsonl` 而不是 `.json`：一行一条，**不是**一个 JSON 数组 ——
/// 收件人拿 Excel 或 `jq` 打开时，这个区别很要紧。
String eventsFileName(int nowMs) {
  final DateTime t = DateTime.fromMillisecondsSinceEpoch(nowMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '练了么-埋点-${t.year}-${two(t.month)}-${two(t.day)}.jsonl';
}
