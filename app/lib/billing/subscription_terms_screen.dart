/// 练了么 · 订阅条款（应用内）
///
/// 为什么要有这一屏：Apple 3.1.2(c) + Schedule 2 §3.8(b) 要求付费墙上有
/// **条款链接**（用 Apple 标准 EULA 就链 Apple 的；用自定义条款就链自己的），
/// 且**必须在 App 内可达**。我们选**自定义条款**：我们只卖一个数字服务，
/// 条款短、能自己讲清楚；而且不引外部依赖（打开外链要 `url_launcher`，
/// 那会动隐私政策的第三方 SDK 清单 —— 不值当，见方案 §8.4）。
///
/// ⚠️ 它**不是**完整的《用户协议》：完整协议在 M4（上架材料）时给律师过一遍，
/// 这一屏只覆盖"订阅这件事"该说清的十条。这条差别如实写在页面底部。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../features/profile/profile_widgets.dart';

/// 条款正文（**唯一出处**；`paywall_copy_test.dart` 会断言关键几条还在）
const List<String> kSubscriptionTerms = <String>[
  '一、练了么 Ultra 是按期提供的数字服务：包含云端备份历史、进阶分析、批量整理与导出进阶等'
      '（具体权益以应用内「练了么 Ultra」那一页当时展示的清单为准）。',
  '二、订阅按你购买时选择的周期自动续期。费用在你的 Apple ID 上结算，'
      '并在每个周期结束前的 24 小时内自动扣取。',
  '三、你可以随时取消：App Store → 右上角头像 → 订阅。取消之后，'
      '当前已付周期结束前仍然可以继续使用 Ultra（我们不提前收回）。',
  '四、若订阅包含免费试用：试用期内取消不会产生费用；未使用的试用期在你购买之后作废。',
  '五、价格以 App Store 上显示的价格为准。价格调整会由 Apple 按它的规则提前通知你，'
      '你可以在生效前取消。',
  '六、退款由 Apple 按 App Store 的退款政策处理（我们无权也没有能力直接退款）；'
      '确有必要时，你可以通过应用内的反馈邮箱联系我们协助。',
  '七、免费版是完整可用的记录工具：记录训练、历史、身体数据、导出自己的数据都不收费。'
      'Ultra 卖的是"更省心"，不是"能不能用"。',
  '八、订阅到期或退款之后：Ultra 的云端多版本与进阶能力停止，'
      '你本机记录的数据一条都不会被删除；云端也保留最新一份备份。',
  '九、未成年人请在监护人同意后购买；我们会按法规对未成年人设置消费限制。',
  '十、条款变更时，我们会在应用内提前告知；继续使用即视为接受变更后的条款。',
];
const String kSubscriptionTermsNote =
    '这一屏只讲"订阅这件事"。完整的《用户协议》与《隐私政策》分别见「隐私与关于」里的入口。';

/// 订阅条款页（纯文本，可选中复制）
class SubscriptionTermsScreen extends StatelessWidget {
  const SubscriptionTermsScreen({super.key});

  @override
  Widget build(BuildContext context) => ProfileSubPage(
        title: '订阅条款',
        children: <Widget>[
          for (final String line in kSubscriptionTerms)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.s4),
              child: SelectableText(
                line,
                style: const TextStyle(
                  color: Tokens.text2,
                  fontSize: Tokens.fsSub,
                  height: Tokens.lhLoose,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Tokens.s2),
            child: Text(
              kSubscriptionTermsNote,
              style: const TextStyle(
                color: Tokens.text3,
                fontSize: Tokens.fsCap,
                height: Tokens.lhNormal,
              ),
            ),
          ),
        ],
      );
}
