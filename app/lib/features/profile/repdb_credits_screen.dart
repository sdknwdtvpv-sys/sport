/// 练了么 · 动作插图来源（RepDB 署名页）
///
/// **这一页存在的唯一理由是履行许可证义务**，不是"我们很有品味地感谢了一下"。
///
/// RepDB Free Tier License v1.0 第 2 条（原文副本在 `tool/repdb-license.txt`）：
///
/// > **Attribution required.** Place a visible link — "Exercise data by RepDB (repdb.co)" —
/// > in your app's about/credits screen, your project's README, or your website footer.
///
/// 所以这一页上有三件**不能删**的东西：
///   1. 逐字的署名文本 [kRepdbAttribution]（"Exercise data by RepDB (repdb.co)"）；
///   2. 可复制的出处地址（`repdb.co` 与仓库地址）—— 我们**不引 `url_launcher`**
///      （见 `subscription_terms_screen.dart` 的同类裁决：为一句话加一个平台通道不划算），
///      所以用 `SelectableText` 而不是可点链接。"可见的链接"由**清单里的地址**满足；
///   3. 许可摘要：允许什么、禁止什么。用户（和审核员）有权知道这些图不是我们画的。
///
/// 另有**一条合规标注**（与许可无关）：这些图是 AI 生成的
/// （许可原文 "Origin of the data" 一节：*All images are original works generated with
/// AI tooling commissioned by RepDB*）。国内《人工智能生成合成内容标识办法》
/// 2025-09-01 生效，要求对 AI 生成内容作出标识 —— 所以这里写明，
/// 动作详情页的插图角上也有「AI 生成」四个字。
///
/// [kRepdbAttribution] 与这一页的入口由 `tool/check-repdb-art.mjs` 与
/// `app/test/repdb_art_test.dart` 守着：删掉署名或删掉入口，门禁会红。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/repdb_art.dart' show RepdbArt, kRepdbAttribution;
import 'profile_widgets.dart';

class RepdbCreditsScreen extends StatelessWidget {
  const RepdbCreditsScreen({super.key});

  /// 出处地址（写在这里而不是 URL 常量表里：它只在这一页用，且必须与署名同源）
  static const String _homepage = 'https://repdb.co';
  static const String _dataset = 'https://github.com/RepDB/exercise-dataset';

  @override
  Widget build(BuildContext context) {
    final int artCount = RepdbArt.cached?.count ?? 0;
    return ProfileSubPage(
      title: '动作插图来源',
      children: <Widget>[
        profileSectionTitle('插图出处'),
        settingsCard(<Widget>[
          Padding(
            padding: const EdgeInsets.all(Tokens.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ⚠️ 这一行是**许可证要求的署名原文**，逐字。不要翻译、不要改写、
                // 不要合并成"数据来源：RepDB"。
                const SelectableText(
                  kRepdbAttribution,
                  key: Key('repdb-attribution'),
                  style: TextStyle(
                    color: Tokens.text,
                    fontSize: Tokens.fsSub,
                    fontWeight: Tokens.fwStrong,
                  ),
                ),
                const SizedBox(height: Tokens.s3),
                Text(
                  artCount > 0
                      ? '本应用里有 $artCount 个动作收了示意图，'
                          '来自 RepDB 的免费公开动作数据集。'
                      : '本应用里的动作示意图来自 RepDB 的免费公开动作数据集。',
                  style: const TextStyle(
                    color: Tokens.text2,
                    fontSize: Tokens.fsCap,
                    height: Tokens.lhNormal,
                  ),
                ),
                const SizedBox(height: Tokens.s3),
                // 可复制（我们不做可点外链 —— 不为一句地址引一个依赖）
                const SelectableText(
                  '$_homepage\n$_dataset',
                  key: Key('repdb-homepage'),
                  style: TextStyle(color: Tokens.text3, fontSize: Tokens.fsMicro, height: Tokens.lhNormal),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: Tokens.s5),
        profileSectionTitle('关于这些图'),
        settingsCard(<Widget>[
          // ── 三条用户真正需要知道的 ──────────────────────────────────
          _bullet(
            'AI 生成',
            '这些示意图由 RepDB 用 AI 工具生成后挑选，不是真人教练拍的示范照片；'
                '也不是医学或解剖学教材图。动作怎么做，请以本应用里那段中文说明为准。',
          ),
          const Divider(height: 1, color: Tokens.line),
          _bullet(
            '中文说明是我们自己写的',
            'RepDB 的数据只有英、德、西三种语言，一个字中文都没有 —— '
                '所以「动作要领」那些句子是本应用自己写的，不是翻译过来的。',
          ),
          const Divider(height: 1, color: Tokens.line),
          _bullet(
            '许可允许我们做什么',
            'RepDB 免费档允许在应用内用于个人与商业用途，条件是署名（就是上面那一行）。'
                '不许把它当数据集或接口再分发，也不许拿这些图去训练或改造 AI 模型。',
          ),
        ]),
      ],
    );
  }

  /// 一条"小标题 + 说明"。与「基本事实」那种 chip 不同：这里是**段落**，
  /// 所以用左对齐的两段文字而不是卡片里并排。
  Widget _bullet(String title, String body) {
    return Padding(
      padding: const EdgeInsets.all(Tokens.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Tokens.text,
              fontSize: Tokens.fsSub,
              fontWeight: Tokens.fwStrong,
            ),
          ),
          const SizedBox(height: Tokens.s2),
          Text(
            body,
            style: const TextStyle(
              color: Tokens.text2,
              fontSize: Tokens.fsCap,
              height: Tokens.lhNormal,
            ),
          ),
        ],
      ),
    );
  }
}
