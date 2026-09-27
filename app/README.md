# 练了么 · Flutter 工程

## 现在有什么

```
lib/
  domain/            ← 纯 Dart，不 import flutter（可被 dart test 直接测）
    progression.dart    规则引擎（engine/progression.mjs 的 Dart 移植）
    tap_meter.dart      tap_count 计量器
    models.dart         领域模型
  data/
    local_store.dart    LocalStore 接口 + 内存实现（drift 待接）
    sync_queue.dart     同步队列（离线补报）
  analytics/
    analytics.dart      埋点接口 + RecordingAnalytics（真实 SDK 待接）
  features/
    workout/            训练会话状态机 + 训练主屏（S4/S5）
    today/              「练」空态（S1）
  core/theme.dart       设计令牌（与 docs/interaction-spec.md 一一对应）
  main.dart             入口
test/
  progression_vectors_test.dart   读 ../engine/vectors.json，与 JS 共用规格
  tap_meter_test.dart             tap_count 的 6 条边界用例
  workout_flow_test.dart          9 个 widget 测试（交互红线）
```

## 跑起来

```bash
cd app
flutter pub get           # 受限环境下这步可能失败（pub 要清临时目录）
dart run build_runner build   # 生成 db.g.dart（*.g.dart 不提交，必须先跑这步）
flutter test              # 全部测试 —— 已验证 49/49 通过
dart analyze --fatal-infos  # 静态分析，必须零问题
                          # （不要用 flutter analyze：Flutter 3.47 在中文路径下会崩，
                          #   见仓库根 README「已知工具链问题」）
flutter run               # 需要先补平台目录，见下
```

**pub 跑不通时**，领域层仍可完整验证（纯 Dart、零依赖）：

```bash
dart app/tool/check_domain.dart   # 28 条向量 + 3 条红线 + 1RM 边界 + tap_count 边界
```

只有 `test/workout_flow_test.dart` 这类 widget 测试必须走 Flutter 测试框架。

## 补平台目录（第一次做真机调试前）

本工程**刻意不包含** `ios/` 与 `android/` —— 它们应当由你用**自己的组织标识**生成，
否则包里会带着一个别人随便起的 bundle id，后期改起来很痛。

```bash
cd app
flutter create --org com.yourcompany --project-name lianleme --platforms=ios,android .
```

`flutter create` 只会补缺失的文件，不会覆盖已存在的 `lib/` 与 `test/`。
生成后按需决定是否提交这两个目录（见 `.gitignore`）。

## 三条红线（有测试守着，别改坏）

| 红线 | 由谁守 |
|---|---|
| 1 次点击 = 1 组，`tap_count` 中位数必须为 1 | `workout_flow_test.dart` + `tap_meter_test.dart` |
| 长按不误记 | `workout_flow_test.dart` |
| 离线可用、训练中不发网络请求 | `workout_flow_test.dart` |

## 改引擎的正确顺序

1. **先在 `engine/vectors.json` 加一条向量**（描述期望行为，先看它变红）
2. 改 `app/lib/domain/progression.dart`
3. 改 `engine/progression.mjs`（两边必须一致）
4. `./verify.sh` 两边都跑绿

顺序反了就会变成"改完代码补测试"，向量也就失去了规格的意义。

## 刻意收窄的地方（不是没写完）

- **动作只有一个**（杠铃卧推）：这一版的目标是把引擎、交互红线、埋点计量这三样最容易做坏的东西锁死，不是铺量。
- **UI 只有 S1 / S4 / S5**：其余屏见 `docs/screens.md`。
- **无第三方依赖**：`pubspec.yaml` 里除了 Flutter SDK 什么都没有。多一个依赖，CI 首次运行就多一个失败点。
- **无 drift / 无真实埋点上报**：接的时候只需实现 `LocalStore` 与 `Analytics` 接口，调用方一行不用改。
