/// 练了么 · 「加重步进」问一次（2026-10-09，10.9 清单第 8a 条）
///
/// 为什么独立成一个文件：**这个对话框有两个入口** ——
///   * 训练屏重量那一行（`step-weight-edit`）：改完这一趟立刻按新步进加减；
///   * 设置 → 偏好设置（`step-row`）：定一个"我这儿的片子就是这个档"。
///
/// 两处要问的东西**一模一样**（档位 + 自定义 + 范围），分成两份实现迟早会长歪
/// （一边少了"自定义"、两边的档位表不一样、key 撞车），测试也要写两遍。
/// 这里只负责**问**，写库与内存都留在各自的调用方（它们手里的东西不一样）。
///
/// 放在 `core/`：它被训练屏与「设置 → 偏好设置」两处用（跨 feature），
/// 与 `core/pills.dart`、`core/glass_switch.dart` 同一类东西。
library;

import 'package:flutter/material.dart';
import 'glass_overlay.dart';

import 'theme.dart';
import 'units.dart';

/// 档位随**当前显示单位**给：kg 下 0.5/1/2/2.5/5；lb 下 1/2.5/5/10。
///
/// 真实健身房里的片子五花八门（1 kg、2.5 kg、5 kg 一对最常见），所以除了档位
/// 还留一格自定义。⚠️ lb 下不给 0.5 —— 那是一对 1 lb 的小片子，
/// 而 lb 单位的用户眼里"最小一步"通常就是 1（1 lb ≈ 0.45 kg，已经比 kg 的 0.5 细）。
///
/// ⚠️ **这些数念的是显示单位，不是 kg**（lb 用户看到的 5 是 5 lb）。
/// 落库前一定要过 [toStoredKg]：直接把它当 kg 存进去，lb 用户点「5」会得到
/// 11 lb 的一步（写 8a 时当场踩到的单位 bug —— 弹层里的数字比别处多拐了一道弯）。
List<double> weightStepPresets(WeightUnit unit) => unit == WeightUnit.lb
    ? const <double>[1, 2.5, 5, 10]
    : const <double>[0.5, 1, 2, 2.5, 5];

/// 问出来的结果。
///
/// ⚠️ 用类包一层而不是直接 pop `double?`：`null` 已经表示"关掉了弹层"
/// （同一个坑在 `_RestPick` 那里踩过），而下面的 [all] 还要带回"范围"。
class WeightStepPick {
  const WeightStepPick(this.kg, {required this.all});

  final double kg;

  /// true = 铺到所有动作（并记成默认值）；false = 只改这一个动作。
  final bool all;
}

/// 弹出「加重步进」。
///
/// [current] 是**当前步进的 kg 值**（控制器/库里都是 kg）；弹层里显示与输入
/// 一律用它念（kg 或 lb），pop 出来的是**kg** —— 换算只在这一层发生一次。
///
/// [exerciseName] 给了就印在标题上（训练屏：用户得知道正在改哪个动作）；
/// 不给就是设置页那一处（那里没有"这个动作"，见 [allowSingleScope]）。
///
/// [allowSingleScope] = false 时**只有"所有动作都改"**：设置页里的"只改默认值"
/// 是一件用户看不见效果的事（它只影响**以后新建**的自定义动作），
/// 摆出来就是让人猜 —— 与其解释不如不给。
Future<WeightStepPick?> pickWeightStep(
  BuildContext context, {
  required WeightUnit unit,
  required double current,
  String? exerciseName,
  bool allowSingleScope = true,
}) async {
  final List<double> presets = weightStepPresets(unit);
  // 弹层内部一律按**显示单位**算（档位、自定义输入、选中判定都是），
  // 只在 pop 那一刻折回 kg。混着来就会出现"选框写着 5 lb、记下去是 5 kg"。
  //
  // ⚠️ kg 下**不 round1**：1.25 是用户输过的合法步进，舍成 1.3 就变成
  // "什么都不动、直接点确定，步进也被改了"。
  final double currentDisplay =
      unit == WeightUnit.kg ? current : round1(toDisplayWeight(current, unit));
  double selected = currentDisplay;
  // ⚠️ 这里**不用 TextEditingController**：对话框 pop 之后路由还要播完退场动画，
  // 而那时候 `TextField` 仍会重建一次 —— 一 dispose 就撞
  // "A TextEditingController was used after being disposed"（写这一条时当场踩到，
  // 而且是**跨用例污染**：崩在下一个用例里，看起来像别人坏了）。
  // 自定义那一格直接改 `selected`，连局部字符串都不用留。

  final WeightStepPick? pick = await showAppDialog<WeightStepPick>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, void Function(void Function()) setLocal) => AlertDialog(
        backgroundColor: Tokens.surface,
        title: Text(
          exerciseName == null || exerciseName.isEmpty
              ? '加重步进'
              : '加重步进 · $exerciseName',
          style: const TextStyle(color: Tokens.text, fontSize: Tokens.fsBody),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: Tokens.s2,
              runSpacing: Tokens.s2,
              children: <Widget>[
                for (final double v in presets)
                  ChoiceChip(
                    key: Key('step-preset-${trimNumber(v)}'),
                    label: Text('${trimNumber(v)} ${unit.wire}'),
                    selected: (v - selected).abs() < 0.001,
                    onSelected: (_) => setLocal(() => selected = v),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.s4),
            TextField(
              key: const Key('step-custom'),
              onChanged: (String v) {
                final double? d = double.tryParse(v.trim());
                if (d != null && d > 0) setLocal(() => selected = d);
              },
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Tokens.text),
              decoration: const InputDecoration(
                labelText: '自定义',
                hintText: '例如 1.25',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('step-cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: Tokens.text2)),
          ),
          if (allowSingleScope)
            TextButton(
              key: const Key('step-apply-one'),
              onPressed: () => Navigator.of(ctx)
                  .pop(WeightStepPick(toStoredKg(selected, unit), all: false)),
              child: const Text('只改这个动作', style: TextStyle(color: Tokens.accent)),
            ),
          TextButton(
            key: const Key('step-apply-all'),
            onPressed: () => Navigator.of(ctx)
                .pop(WeightStepPick(toStoredKg(selected, unit), all: true)),
            child: const Text('所有动作都改', style: TextStyle(color: Tokens.accent)),
          ),
        ],
      ),
    ),
  );
  // 折回 kg 之后可能变成 0.4535923…（lb 的 1）—— 存这个值是对的：
  // 显示会 round1 回 "1 lb"，而引擎那边本来就是 kg 网格。
  if (pick == null || pick.kg <= 0) return null;
  return pick;
}
