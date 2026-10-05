/// 练了么 · 底部 Tab 栏
///
/// **五个**（训练 / 进步 / 数据 / 计划 / 我的）—— 2026-10-05 按新 VI 从"三个封顶"改过来，
/// 见 `docs/screens.md` 与 `docs/plan-vi-migration.md`。
///
/// 图标用的是 Material 的线框图标（VI 那套自绘的 Tab 图标体系还没做）——
/// **这是个已知的过渡状态**，写在这里免得下一个人以为"已经对上了"。
/// 之前这个组件只是个装饰性的静态元件，现在由外壳持有状态、真的能切换 ——
/// 假的可点按元件比没有更糟。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  static const List<({IconData icon, String label})> tabs =
      <({IconData icon, String label})>[
    (icon: Icons.fitness_center, label: '训练'),
    (icon: Icons.show_chart, label: '进步'),
    (icon: Icons.bar_chart, label: '数据'),
    (icon: Icons.event_note, label: '计划'),
    (icon: Icons.person_outline, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.line)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                key: Key('tab-${tabs[i].label}'),
                onTap: () => onChanged(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      tabs[i].icon,
                      size: 22,
                      color: i == current ? Tokens.accent : Tokens.text3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tabs[i].label,
                      style: TextStyle(
                        color: i == current ? Tokens.accent : Tokens.text3,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
