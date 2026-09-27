# 练了么 · 实施路线图

> **当前状态**：5 个门禁全绿
> 动作库 165 个动作 · JS 引擎 35/35 · Dart 引擎 41/41 · 静态分析 0 问题 · widget 测试 49/49
>
> 剩下的缺口都是**"没有对应验证手段"**，不是"待验证"。两者要用完全不同的方式对待。

---

## 阶段总览

| 阶段 | 目标 | 预估 | 可并行 |
|---|---|---|---|
| **0** | 钉住工程：git + CI 真跑起来 | 0.5 天 | — |
| **1** | 接 drift，数据活过重启 | 1 天 | 与 5 并行 |
| **2** | 补平台目录，装到真机 | 0.5 天 | — |
| **3** | **自己练一次**（关键里程碑，0 成本） | 1 次训练 | — |
| **4** | 按真实感受修 + 铺 UI 屏 | 2–3 天 | 与 5 并行 |
| **5** | 招 5 人做可用性测试 | 日历 3–5 天 | ✅ 与 1/4 并行 |
| **6** | 真实埋点上报 | 1 天 | — |

> ⚠️ **不要跳过阶段 3 直接铺 12 屏 UI。**
> 阶段 3 的成本是一次训练，产出是"核心假设成不成立"的第一个真实信号。
> 阶段 4 铺哪些屏、怎么改，取决于阶段 3 的感受——反过来做就是赌博。

---

## 阶段 0 · 钉住工程（今天，30 分钟）

**目标**：把"你本地跑过一次"变成"每次提交都自动跑"。

```bash
cd /Users/elliot/Harness/练了么
git init -b main
git add -A
git status --short          # 检查：不该出现 .dart_tool / .pub-cache / .DS_Store / .tmpdir
git commit -m "练了么 v0.1：产品契约 + 165 动作种子 + 双引擎 + 49 项测试"
```

**在 GitHub 上新建一个空仓库**（⚠️ 不要勾选 "Add README" 或 ".gitignore"，否则 push 会冲突），然后：

```bash
git remote add origin git@github.com:<你的账号>/lianleme.git
git push -u origin main
```

**完成标准**：
- [ ] `git status` 干净
- [ ] GitHub 仓库里没有 `.dart_tool/`、`.pub-cache/`、`.DS_Store`
- [ ] Actions 两个 job（`contracts` / `app`）**都绿**

**常见坑**：
- 用 HTTPS 而非 SSH 会一直要密码 → 用 `git@github.com:` 形式，先配好 SSH key
- CI 若在"生成物必须与提交一致"这步红 → 本地跑 `node seed/build.mjs` 后把 `seed/exercises.json`、`seed/exercises.sql` 一起提交
- CI 若在 `flutter pub get` 变慢 → 正常，第一次要下依赖；`cache: true` 之后会快

---

## 阶段 1 · 接 drift 持久化（1 天）

**目标**：数据活过重启。没有这一步，阶段 3 没法做——引擎要看"上次 60kg×8"，没历史就是空的。

### 步骤

1. **加依赖** `app/pubspec.yaml`：

```yaml
dependencies:
  flutter: {sdk: flutter}
  drift: ^2.20.0
  drift_flutter: ^0.2.0
  path_provider: ^2.1.0
  sqlite3_flutter_libs: ^0.5.0

dev_dependencies:
  flutter_test: {sdk: flutter}
  drift_dev: ^2.20.0
  build_runner: ^2.4.0
```
> 版本号以 `flutter pub add` 实际解析为准，不要照抄。

2. **写表结构** `app/lib/data/db.dart`：把 `docs/data-model.md` 的 DDL 逐张翻成 drift 表。
   字段、索引、`updated_at` / `deleted_at` 一个都别改——那份 DDL 是契约。

3. **实现接口** `class DriftLocalStore implements LocalStore`
   （`app/lib/data/local_store.dart` 里的接口，UI 与控制器**一行都不用改**）

4. **代码生成**：

```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```

5. **写契约测试** `app/test/local_store_contract_test.dart` —— **这一步最重要**：

   同一组断言，**同时跑在 `InMemoryLocalStore` 和 `DriftLocalStore` 上**（后者用 `NativeDatabase.memory()`）。
   两个实现共用一份契约，就不会偷偷分叉。

6. **接线**：`main.dart` 里把 `InMemoryLocalStore()` 换成 `DriftLocalStore(...)`。

7. **更新 CI**：在 `flutter pub get` 之后、`analyze` 之前插入

```yaml
      - name: 代码生成
        run: dart run build_runner build --delete-conflicting-outputs
```

**完成标准**：
- [ ] `dart analyze --fatal-infos` 仍为零问题（生成的文件要加进 `analysis_options.yaml` 的 exclude）
- [ ] 契约测试对**两个**实现都绿
- [ ] 杀掉 App 重开，之前的组记录还在
- [ ] CI 绿

> ⚠️ 这一步我在当前环境**无法验证**（跑不了 `pub get`）。上面是规格，不是已验证的步骤。

---

## 阶段 2 · 补平台目录，装到真机（0.5 天）

```bash
cd app
flutter create --org com.yourcompany --project-name lianleme --platforms=ios,android .
flutter run           # 接上手机
```

`flutter create` 只补缺失文件，**不会覆盖已有的 `lib/` 与 `test/`**。生成后决定是否提交 `ios/`、`android/`（`.gitignore` 里已备好注释行）。

**完成标准**：
- [ ] 手机上出现 App，能点「开始今天的训练」进训练屏
- [ ] 点大按钮能记一组（这时还是内存存储，重启即失）
- [ ] 阶段 1 完成后：重启 App，记录还在

**注意**：iOS 真机需要 Apple 开发者账号配置签名；只想验证交互的话 Android 或模拟器更快。

---

## 阶段 3 · 自己练一次（关键里程碑，0 成本）

**这是整个路线图里性价比最高的一步。**

带上手机去健身房，**真的用完整一次训练**——至少 3 个动作、12 组。

**要刻意观察的**：
- [ ] 单手、出汗、注意力在器械上的时候，点得到那个大按钮吗？
- [ ] 组间那 60 秒里，有没有哪一步让你烦？（哪怕只是"多看了一眼"）
- [ ] 休息倒计时你是真的在看，还是根本不看？
- [ ] 动作切换顺手吗？会迷路吗？
- [ ] 长按改重量，你用得着吗？还是压根不想改？
- [ ] **练完你想不想看"进步"页？** 如果不想，说明数据展示的价值判断错了

**记录方式**：练完当天写一段话，写下最烦的那一个瞬间。**不要记"整体感觉不错"这种话——它没有信息量。**

**完成标准（按结果分岔）**：
- 顺手 → 进入阶段 4，按原计划铺屏
- 某一步明显卡 → **先修那一步，再铺屏**（这正是阶段 3 存在的意义）
- 根本不想用第二次 → 停下来，重新审核心假设。此时沉没成本还很小

> 这一步替代不了阶段 5（你是设计者，不是目标用户），但它是**最快的负反馈来源**。
> 花 1 次训练，避免花 3 天铺一堆要被推翻的屏。

---

## 阶段 4 · 按真实感受修 + 铺 UI 屏（2–3 天）

按 `docs/screens.md` 的顺序铺，**每屏配 widget 测试**：

| 顺序 | 屏 | 为什么这个顺序 |
|---|---|---|
| 1 | S2 今日建议卡 | 它是"降低门槛"的主要卖点，且引擎已经就绪 |
| 2 | S7 训练结束总结 | 训练闭环的收尾，也是分享卡的载体 |
| 3 | S8 进步 | 留存钩子；**但先按阶段 3 的观察确认用户真的想看** |
| 4 | S10 我 | 设置、导出、隐私开关 |

**每屏的完成标准**：`dart analyze --fatal-infos` 零问题 + `flutter test` 全绿 + 一条针对该屏核心行为的新 widget 测试。

**红线不变**（`app/README.md` 里有表）：1 次点击 = 1 组、长按不误记、离线可用。

---

## 阶段 5 · 招 5 人做可用性测试（日历 3–5 天，可与 1/4 并行）

按 `docs/usability-test-kit.md` 执行，**重点是第 6 节那个对照环节**：让被试用自己的训记做同一件事，比出省事程度。

这一步**不占工程时间**（招人要等，但不需要你写代码），所以应该尽早启动、与阶段 1/4 并行。

**必须拿到的 7 个数字**（`docs/usability-test-kit.md` §8）：T1 通过率 / T1 中位耗时 / **记录一组的 tap_count 中位数** / 打字次数 / 滚动次数 / T6 采纳情况 / Q3 选择本品人数。

拿到后回填 `docs/analytics.md` 的目标值——现在那个 55% 和 `tap_count = 1` 都还是估计值，文档里已标注"待校准"。

---

## 阶段 6 · 真实埋点上报（1 天）

按 `docs/analytics-sdk.md` 实现：
- `Outbox` 表（`analytics.md` §4 有 DDL）
- `Flusher`：批量 ≤100 条、重试 1s/4s/16s、触发时机五条
- **训练进行中不发任何网络请求**（这是红线，`verify.sh` 之外要手工抓包验证一次）
- `TapMeter` 已经实现并有 6 条边界测试，只需接上 `flushTap()`

**完成标准**：`docs/analytics-sdk.md` §12 那份 11 项验收清单逐条打勾。

---

## 一张图看懂顺序

```
阶段0 git+CI ──▶ 阶段1 drift ──▶ 阶段2 真机 ──▶ 阶段3 自己练一次
                                                      │
                          ┌───────────────────────────┴──────────┐
                          ▼                                      ▼
                   顺手 → 阶段4 铺屏 ──▶ 阶段6 真实埋点    卡住 → 先修那一步
                          ▲
阶段5 招人测试 ────────────┘（并行，只占日历不占工时）
```

**唯一不能跳的是阶段 3。** 其余都可以调整顺序。
