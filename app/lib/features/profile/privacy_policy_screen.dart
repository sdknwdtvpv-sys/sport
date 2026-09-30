/// 练了么 · 应用内的隐私政策
///
/// **为什么必须有这一屏**：商店（尤其国内）不是只看你在商店页面填的那个隐私政策 URL ——
/// 小米应用商店的《隐私政策不合规的问题解析和修改指引》写得很直白：
/// "应用需要在**应用内**添加独立的隐私政策，且**尽量保证在四步操作之内**可以查看到"，
/// 并且"必须是可以正常打开和查看的状态"。国信办秘字〔2019〕191 号是这条规则的来源。
/// 我们此前**应用内一个字都没有**（政策只躺在仓库与商店页面里）——那是一条上架硬伤。
///
/// 三条设计取舍：
///
///   1. **内容来自与公网页面同一份 Markdown**（`docs/privacy-policy.md`），
///      由 `tool/gen-privacy-page.mjs` 生成纯文本随包发布，并**有防漂守卫**
///      （改了政策没重新生成 → `verify.sh` 第 2 层判红）。绝不手写第二份。
///   2. **纯文本而不是 Markdown/HTML**：用户看到"**加粗**"那种星号会以为界面坏了；
///      而渲染 Markdown 要么引第三方包、要么自己写解析器 —— 都不值当。
///   3. **可选中复制**（[SelectableText]）：政策里有一串命令与链接，能选中才有用。
///
/// 入口在「我」→「隐私政策」（**两次点击**，符合"四步之内"）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/app_info.dart';
import '../../core/theme.dart';

/// 随包发布的政策文本路径（`pubspec.yaml` 里声明过）
const String kPrivacyTextAsset = 'assets/privacy-policy.txt';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({
    super.key,
    this.loader,
    this.filingNumber = kAppFilingNumber,
  });

  /// 读文本的方式。默认读随包资产；测试注入假数据，免得依赖构建产物。
  final Future<String> Function()? loader;

  /// APP 备案号。**空字符串 = 还没备案**，那一行就不显示 ——
  /// 与其印一句"备案号：待填"，不如不出现。拿到号之后填 `app_info.dart` 里的常量即可。
  final String filingNumber;

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late Future<String> _text;

  @override
  void initState() {
    super.initState();
    _text = (widget.loader ?? () => rootBundle.loadString(kPrivacyTextAsset))();
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
                      key: const Key('privacy-back'),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chevron_left, color: Tokens.text2),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: Tokens.s3),
                  const Expanded(
                    child: Text(
                      '隐私政策',
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
                        '读不到内置的隐私政策文本（${snap.error}）。\n'
                        '这属于打包问题，请告诉我们。',
                        key: const Key('privacy-error'),
                        style: const TextStyle(color: Tokens.danger, height: 1.6),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Tokens.volt),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(Tokens.s5, Tokens.s4, Tokens.s5, Tokens.s8),
                    children: <Widget>[
                      if (widget.filingNumber.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Tokens.s4),
                          child: Text(
                            'APP 备案号：${widget.filingNumber}',
                            key: const Key('privacy-filing'),
                            style: const TextStyle(color: Tokens.text2, fontSize: 13),
                          ),
                        ),
                      SelectableText(
                        snap.data!,
                        key: const Key('privacy-text'),
                        style: const TextStyle(
                          color: Tokens.text2,
                          fontSize: 14,
                          height: 1.75,
                        ),
                      ),
                    ],
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
