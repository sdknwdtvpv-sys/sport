# 练了么 · 原型的 token 是**生成的**，不是手写的（2026-10-10）

> 这份文档只有一件事要说清：**`prototype/` 下那两份稿子的 `:root{}` 由
> `tool/gen-prototype-tokens.mjs` 从 `app/lib/core/theme.dart` 生成 —— 手改会被门禁打回。**

## 为什么（这不是洁癖，是已经发生过的事）

`app/lib/core/theme.dart` 的文件头上写着一条契约：

> 「与 `docs/interaction-spec.md` §2–§4 和 `prototype/index.html` 的 CSS 变量一一对应。
> 改这里之前先改规格 —— **三处必须同时一致**。」

而这条契约**从来没有守卫**（`tool/check-guards-wired.mjs` 那份"谁在跑"的名单里也没有它）。
2026-10-10 的 VI 复核实测漂了三处（都在 `prototype/index.html`）：

- `--elevated` 是冷蓝灰 `#1F1F24`，而真值是暖黑 `#24201C`；
- `--pr` 是旧的琥珀 `#F5C451`，而真值是 `#FBBF24`；
- `--r-card` 是 `20px`，而真值是 `12px`（**而且它被 9 处引用**）。

原型的读者是**设计和评审**：他们照着它看、照着它改。**它偏一个值，比代码里偏一个值更贵**——
因为看到它的人会以为那是准的。

## 怎么用

```bash
node tool/gen-prototype-tokens.mjs          # 就地生成（改完 theme.dart 跑这个）
node tool/gen-prototype-tokens.mjs --check  # 只比对，漂了就退出码 1（门禁跑这个）
```

门禁里的位置：`verify.sh` 里紧跟 `gen-privacy-page.mjs --check` 那一组（同一个模式）。

## 口径（三件必须说清，否则下一个人会猜）

1. **真源只有一处**：`app/lib/core/theme.dart`。生成器**不做任何兜底** ——
   解析不到某个常量就直接报错退出（兜底会让漂移变成静默的）。
2. **字号 / 行高暂不在生成范围内**：`theme.dart` 今天**没有字阶令牌**（那是 VI 计划批次 1 的
   T1-3）。所以 `--fs-*` / `--lh-*` 那 7 行由生成器里的 `FONT_BLOCK` 常量原样写回；
   等 `theme.dart` 有了 `fs*` / `lh*` 令牌，改那个常量即可。
   `prototype/index.html` 的 `--safe-bottom` 同理（它是原型自己用的，不是 App 的令牌）。
3. **两份原型的变量命名不同**，所以生成器里有一张显式映射表（`FILES[].map`）：
   - `prototype/index.html`：`--bg` / `--surface` / `--elevated` / `--line` / `--line-strong` /
     `--text` / `--text-2` / `--text-3` / `--accent` / `--accent-press` / `--accent-ink` /
     `--pr` / `--danger`（+ 间距 `--s1..--s8`、圆角 `--r-card/--r-sheet/--r-pill`、`--h-primary`）
   - `prototype/ref-3tab-2026-10-10.html`：`--bg` / `--surface` / `--elev` / `--line` / `--line2` /
     `--t1` / `--t2` / `--t3` / `--accent` / `--ink` / `--ok` / `--pr` / `--rare`
   **没有映射的变量不生成**（例如 `index.html` 里没有 `--success`，就不硬塞一个进去 ——
   原型只画它要画的东西）。

## 改一个颜色的正确顺序

1. 改 `app/lib/core/theme.dart`；
2. 跑 `node tool/gen-prototype-tokens.mjs`（原型跟着走）；
3. 同步 `docs/interaction-spec.md` §4 的令牌表（**三处一致的第三处**）；
4. 跑 `node tool/check-doc-paths.mjs` 与 `node tool/gen-prototype-tokens.mjs --check`。

⚠️ 加一份新原型（`prototype/` 下的新稿子）时：在生成器的 `FILES` 里加一条
（路径 + 命名映射 + 要不要生成间距/圆角），**别手写 `:root`**。

## 生成块长什么样

两份文件里都插了开始/结束标记，生成器只替换标记之间的内容：

```
  /* ⚠️ 这一段由 `tool/gen-prototype-tokens.mjs` 从 `app/lib/core/theme.dart` 生成 —— 手改会被门禁打回 */
  …生成的变量…
  /* ── 生成块结束 ── */
```

首次生成时，标记还不存在 —— 生成器会把原来的 `:root{ … }` 整段换掉，之后就一直走标记。
