/// 练了么 · 动作插图（RepDB 免费档）
///
/// **这是什么**：`app/assets/repdb-art/` 里的一批扁平风格动作插图，来自
/// [RepDB](https://repdb.co) 的**免费档**数据集（637 个动作、512px WebP 静图）。
/// 我们用它的免费档图，**只用作插图**：中文动作说明仍然是我们自己写的
/// （RepDB 只有英/德/西三种语言，一个字都没有中文）。
///
/// **许可（`tool/repdb-license.txt` 是原文副本，改动前先读它）**：
///   * 允许**个人与商业用途**，**限于应用内使用**，**必须署名**；
///   * 不得作为数据集/API 再分发（第 3 条）—— 所以这些图**只能随端一起走**，
///     我们不做"导出图库"这类功能；
///   * 不得作为生成式模型的输入/参考/训练素材（第 5 条）；
///   * 付费档预览图（`premium-samples/`）**仅限评估**，一个字节都不许进包（第 6 条）。
///
/// **署名落在哪**：`features/profile/repdb_credits_screen.dart`（「我」→「隐私与关于」→
/// 「动作插图来源」）。许可第 2 条要求的可见链接就写在那里，**逐字**是
/// 「Exercise data by RepDB (repdb.co)」——`tool/check-repdb-art.mjs` 会核对这句话还在。
///
/// **为什么是"缺失就降级"而不是"必须有图"**：351 个动作里只有一部分能在 RepDB
/// 找到**同一个动作**（见 `tool/repdb-art-map.tsv` 的规矩：器械/平面/握距都不许凑）。
/// 找不到就**不画图**，绝不拿一个近似的动作顶上 —— 少一张图没有任何代价，
/// 错一张图（例如给"杠铃划船"配"直立划船"）是产品缺陷。
///
/// 加载是**惰性且只读**的：清单很小（约十几 KB），进程内缓存一次；
/// 读不出来（测试环境没有 asset、清单损坏）就整体当"无图"处理，不抛异常 ——
/// 插图是锦上添花，它不该有能力让动作详情页白屏。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 清单资源的路径（生成物，见 `tool/vendor-repdb-art.mjs`）
const String kRepdbArtManifestAsset = 'assets/repdb-art.json';

/// 许可第 2 条要求的**逐字**署名。改这句话之前先读许可原文。
const String kRepdbAttribution = 'Exercise data by RepDB (repdb.co)';

/// 一个动作的插图（可能只有一张 `main`，也可能有 `start` + `peak` 两张）。
///
/// `assetPathOf` 拿到的路径直接可以喂给 `Image.asset`。
class ExerciseArt {
  const ExerciseArt({
    required this.exerciseId,
    required this.repdbId,
    this.start,
    this.peak,
    this.main,
  });

  /// 我们的动作 id（`app/assets/exercises.json` 里的 id）
  final String exerciseId;

  /// RepDB 的动作 id（署名与追溯用）
  final String repdbId;

  /// 起始姿势（多数动作有）
  final String? start;

  /// 顶峰姿势（多数动作有）
  final String? peak;

  /// 单张图（拉伸/静力类动作用这个字段，它们没有第二个姿势）
  final String? main;

  /// 画在卡片上的**主图**：优先顶峰（那是最能看出这个动作的一张），
  /// 其次单张图，最后才是起始姿势。
  String? get hero => peak ?? main ?? start;

  /// 有没有第二张可以切换（有 `start` 又有 `peak` 时才有）
  bool get hasSecondPose => start != null && peak != null;

  /// 与 [hero] 配对的第二张（没有就返回 null）
  String? get secondPose => hasSecondPose ? start : null;

  bool get isEmpty => hero == null;
}

/// 动作插图清单。**不可变**，由 [RepdbArtCatalog.load] 构造。
class RepdbArtCatalog {
  const RepdbArtCatalog._(this._byExercise, this._byRepdbId);

  /// 空清单：任何动作都没有图（测试默认值、asset 读不出来的降级值）
  static const RepdbArtCatalog empty = RepdbArtCatalog._(
    <String, ExerciseArt>{},
    <String, ExerciseArt>{},
  );

  final Map<String, ExerciseArt> _byExercise;
  final Map<String, ExerciseArt> _byRepdbId;

  /// 有插图的动作数量（门禁与文档引用它）
  int get count => _byExercise.length;

  ExerciseArt? forExercise(String exerciseId) => _byExercise[exerciseId];

  /// 反查：这张图配的是哪个动作（署名页/溯源用）
  ExerciseArt? forRepdbId(String repdbId) => _byRepdbId[repdbId];

  Iterable<ExerciseArt> get all => _byExercise.values;

  /// 从清单 JSON 构造。**字段缺失一律降级**（宁可少一张图，不要抛异常）。
  ///
  /// `json` 的结构见 `tool/vendor-repdb-art.mjs` 的 `buildManifest`：
  /// ```json
  /// { "schema": 1, "attribution": "...", "exercises": [
  ///     { "id": "ex_bb_bench_press", "repdb": "bench-press",
  ///       "start": "assets/repdb-art/bench-press-start.webp",
  ///       "peak":  "assets/repdb-art/bench-press-peak.webp" } ] }
  /// ```
  factory RepdbArtCatalog.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['exercises'];
    if (raw is! List) return empty;
    final Map<String, ExerciseArt> byExercise = <String, ExerciseArt>{};
    final Map<String, ExerciseArt> byRepdb = <String, ExerciseArt>{};
    for (final Object? row in raw) {
      if (row is! Map) continue;
      final Object? id = row['id'];
      final Object? repdb = row['repdb'];
      if (id is! String || id.isEmpty || repdb is! String || repdb.isEmpty) {
        continue;
      }
      String? path(Object? v) {
        if (v is! String) return null;
        final String t = v.trim();
        return t.isEmpty ? null : t;
      }

      final ExerciseArt art = ExerciseArt(
        exerciseId: id,
        repdbId: repdb,
        start: path(row['start']),
        peak: path(row['peak']),
        main: path(row['main']),
      );
      if (art.isEmpty) continue; // 没有任何图 → 当作没有这条
      byExercise[id] = art;
      byRepdb[repdb] = art;
    }
    return RepdbArtCatalog._(byExercise, byRepdb);
  }

  /// 读资源并构造清单。**读不出来就返回 [empty]**（不抛）。
  ///
  /// 只读一次：清单在整个进程里是不变的，插图入口会被反复构建
  /// （动作详情、训练屏要领块都会问"这个动作有图吗"），每次读 asset 是浪费。
  static Future<RepdbArtCatalog> load({Future<String> Function()? loader}) async {
    try {
      final String text =
          await (loader ?? () => rootBundle.loadString(kRepdbArtManifestAsset))();
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return empty;
      return RepdbArtCatalog.fromJson(decoded);
    } catch (_) {
      // 清单缺失/损坏/平台通道不可用（纯 Dart 测试）—— 一律当"没有插图"，
      // 界面继续长成原来的样子。**不 rethrow**：插图不该有能力让页面白屏。
      return empty;
    }
  }
}

/// 进程内缓存：第一次加载后所有调用方共用同一份。
class RepdbArt {
  RepdbArt._();

  static RepdbArtCatalog? _cached;
  static Future<RepdbArtCatalog>? _inflight;

  /// 已加载的清单（没加载过时是 null）
  static RepdbArtCatalog? get cached => _cached;

  /// 取清单（首次会读 asset）。
  static Future<RepdbArtCatalog> catalog({Future<String> Function()? loader}) {
    final RepdbArtCatalog? hit = _cached;
    if (hit != null) return Future<RepdbArtCatalog>.value(hit);
    return _inflight ??= RepdbArtCatalog.load(loader: loader).then(
      (RepdbArtCatalog c) {
        _cached = c;
        _inflight = null;
        return c;
      },
    );
  }

  /// **同步**取一个动作的插图：还没加载完就返回 null（界面下一帧会重建）。
  ///
  /// 为什么允许"第一次为空"：动作详情页不该为了等一张插图而转圈 ——
  /// 文字说明才是用户点进来的原因。插图晚一帧出现是可以接受的。
  static ExerciseArt? of(String exerciseId) => _cached?.forExercise(exerciseId);

  /// 测试用：塞一份清单，或清空缓存。
  static void debugSet(RepdbArtCatalog? catalog) {
    _cached = catalog;
    _inflight = null;
  }
}
