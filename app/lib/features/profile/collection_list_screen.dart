/// 练了么 · 「个人信息收集清单」/「与第三方共享个人信息清单」（164 号文）
///
/// **为什么有这一屏**：工信部 164 号文要求在应用内以**二级菜单**形式集中展示这两份清单
/// （不能只在隐私政策长文里写一段）。做法上刻意**不手写第二份真相** ——
/// 这份文本是 `tool/gen-privacy-page.mjs` 生成的：
///   * 收集清单 ← `docs/privacy-facts.json`（已被硬门禁逼着与代码一致）
///   * 共享清单 ← 《隐私政策》§三之五 那张第三方 SDK 表（已被 privacy-audit 逼着与 pubspec 一致）
/// 所以它不可能与政策/代码漂开；`verify.sh` 里有 `--check` 防漂守卫。
///
/// 入口在「我」→「关于」→「个人信息收集清单」（与隐私政策并列）。
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
                    child: Text(
                      snap.data!,
                      key: const Key('collection-text'),
                      style: const TextStyle(
                        color: Tokens.text2,
                        fontSize: 13.5,
                        height: 1.75,
                      ),
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
}
