/// 练了么 · 「个人信息收集清单」/「与第三方共享个人信息清单」（164 号文）
///
/// **为什么有这一屏**：工信部 164 号文要求在应用内以**二级菜单**形式集中展示这两份清单
/// （不能只在隐私政策长文里写一段）。做法上刻意**不手写第二份真相** ——
/// 这份文本是 `tool/gen-privacy-page.mjs` 生成的：
///   * 收集清单 ← `docs/privacy-facts.json`（已被硬门禁逼着与代码一致）
///   * 共享清单 ← 《隐私政策》§三之五 那张第三方 SDK 表（已被 privacy-audit 逼着与 pubspec 一致）
/// 所以它不可能与政策/代码漂开；`verify.sh` 里有 `--check` 防漂守卫。
///
/// 入口在「我」→「隐私与关于」→「个人信息收集清单」（与隐私政策并列）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/theme.dart';

/// 随包发布的清单文本路径（`pubspec.yaml` 里声明过）
const String kCollectionListAsset = 'assets/collection-list.txt';

class CollectionListScreen extends StatefulWidget {
  const CollectionListScreen({super.key, this.loader});

  /// 读文本的方式。默认读随包资产；测试注入假数据，免得依赖构建产物。
  final Future<String> Function()? loader;

  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> {
  late Future<String> _text;

  @override
  void initState() {
    super.initState();
    _text = (widget.loader ?? () => rootBundle.loadString(kCollectionListAsset))();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s2, Tokens.s5, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      key: const Key('collection-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '个人信息收集清单',
                      style: TextStyle(
                        color: Tokens.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<String>(
                future: _text,
                builder: (BuildContext ctx, AsyncSnapshot<String> snap) {
                  if (snap.hasError) {
                    // 这里出错说明打包漏了资产 —— 如实说，不要留一片空白
                    return Padding(
                      padding: const EdgeInsets.all(Tokens.s5),
                      child: Text(
                        '读不到内置的清单文本（${snap.error}）。\n'
                        '这属于打包问题，请告诉我们。',
                        key: const Key('collection-error'),
                        style: const TextStyle(color: Tokens.danger, height: 1.6),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s3, Tokens.s5, Tokens.s8),
                    child: Column(
                      // 整块文本包在一个带 key 的容器里：测试找的是"清单渲染出来了"，
                      // 不是"它是一个 Text"（2026-10-01 改成按行排版之后仍然成立）。
                      key: const Key('collection-text'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _lines(snap.data!),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 把清单文本**按行排版**，给标题做层级。
  ///
  /// 为什么不再整块丢给一个 `Text`（2026-10-01 真机走查）：这一份是纯文本资产，
  /// 整块渲染的后果是**所有行一样大、一样灰** —— 读者（和审核员）找不到"一、二、"在哪，
  /// 而它偏偏是一份要被人翻的合规材料。
  ///
  /// 规则很少，也不打算做成 Markdown 解析器（那要么引依赖、要么自己写一套）：
  ///   * `一、`/`二、` 开头 → 一级标题
  ///   * `【数字】` 开头 → 二级标题
  ///   * `·` 开头的条目 → 正常正文
  ///   * 空行 → 一小段间距（文本里已有换行，不再重复画分隔线）
  static List<Widget> _lines(String text) {
    final List<Widget> out = <Widget>[];
    final List<String> rows = text.split('\n');
    for (int i = 0; i < rows.length; i++) {
      final String line = rows[i];
      if (line.trim().isEmpty) {
        // 连续空行压成一个间距；行首的空行不要（标题自己带下边距）
        if (out.isNotEmpty && i + 1 < rows.length) {
          out.add(const SizedBox(height: Tokens.s3));
        }
        continue;
      }
      if (RegExp(r'^[一二三四五六七八九十]+、').hasMatch(line)) {
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : Tokens.s4, bottom: Tokens.s2),
          child: Text(
            line,
            style: const TextStyle(
              color: Tokens.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ));
        continue;
      }
      if (RegExp(r'^【\d+】').hasMatch(line.trim())) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: Tokens.s2),
          child: Text(
            line.trim(),
            style: const TextStyle(
              color: Tokens.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
        ));
        continue;
      }
      out.add(Text(
        line,
        style: const TextStyle(color: Tokens.text2, fontSize: 13.5, height: 1.75),
      ));
    }
    return out;
  }
}
