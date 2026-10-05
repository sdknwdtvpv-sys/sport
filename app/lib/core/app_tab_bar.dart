/// 练了么 · 底部 Tab 栏
///
/// **三个封顶**（见 `docs/screens.md`）。之前它只是个装饰性的静态组件，
/// 现在由外壳持有状态、真的能切换 —— 假的可点按元件比没有更糟。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  static const List<({IconData icon, String label})> tabs =
      <({IconData icon, String label})>[
    (icon: Icons.fitness_center, label: '练'),
    (icon: Icons.show_chart, label: '进步'),
    (icon: Icons.person_outline, label: '我'),
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
