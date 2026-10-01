# 练了么

**v1.35.2** · [![CI](https://github.com/sdknwdtvpv-sys/sport/actions/workflows/ci.yml/badge.svg)](https://github.com/sdknwdtvpv-sys/sport/actions/workflows/ci.yml)

> 训记的竞品。不靠功能更多取胜，靠**把"记录一组"的成本压到 1 次点击**，并让"今天练什么"不需要用户自己想。
>
> 完整产品定义见 [`PRODUCT.md`](PRODUCT.md)。

---

## 30 秒上手

需要 **Node 18+**；跑 Flutter 测试需要 **Flutter SDK**（stable）。

```bash
./verify.sh                        # 自检全部产物（契约层 + 领域层 + 应用层）
open prototype/index.html          # 看全部 13 屏（S4 训练主屏可交互）

dart app/tool/check_domain.dart    # 验证 Dart 引擎与 JS 引擎一致（零依赖，不需要 pub）
cd app && flutter test             # 再加上 widget 测试（需要能跑通 pub get）
```

手机上打开 `prototype/index.html` 会自动排成单列 —— 可以直接把手机递给别人演示。

---

## 验证现状

| 门禁 | 命令 | 结果 |
|---|---|---|
| 动作库种子（351 个动作＝318 力量 + 11 热身 + 13 有氧 + 9 拉伸，字段/枚举/步长/类别一致性校验 + 与上游映射表一致） | `node seed/build.mjs` + `node tool/map-upstream.mjs --check` + `node tool/add-upstream-exercises.mjs --check` | ✅ 通过 |
| JS 规则引擎（45 向量 + 4 红线 + 4 条 1RM） | `node engine/run-tests.mjs` | ✅ 53/53 |
| Dart 规则引擎（**同一份** `engine/vectors.json`） | `dart app/tool/check_domain.dart` | ✅ 60/60 |
| 静态分析（最严格档，info 级也算失败） | `cd app && dart analyze --fatal-infos` | ✅ **No issues found!** |
| Flutter 测试（引擎 + 持久化契约 + 数据库迁移 + 有氧记录 + 全部界面 + 埋点上报 + 云备份 + 冒烟） | `cd app && flutter test` | ✅ **全绿**（当前条数见 `docs/release-checklist.md` 的"当前状态速览"） |
| **场景 eval**（把产品红线写成序列级断言：连练 12 周之后还讲不讲道理） | `node engine/run-scenarios.mjs` | ✅ 8 场景 / 152 步 / 12 条红线 |
| **埋点链路**（收集端收/拒/落盘 + 北极星 24h 边界 + 漏斗 + `tap_count` 门禁口径） | `node server/collector.selftest.mjs` | ✅ 通过 |
| **可用性测试口径**（中位数 / 硬错误拦截 / 判定与 §8 目标一致） | `node tool/usability-selftest.mjs` | ✅ 通过 |
| 动作说明覆盖率（内容债的可见形式：推荐位 + 全库 + 待写队列） | `node tool/content-report.mjs` | 推荐位 48/48 · 全库 **351/351** |
| **隐私政策对账**（代码会发的事件/字段、manifest 权限 ↔ 政策正文） | `node tool/privacy-audit.mjs`（发布前加 `--apk`） | ✅ 一致 |
| **变异测试**（唯一验证"测试本身有没有用"的一层） | `node tool/mutation.mjs` | ✅ 24 杀死 / **0 存活** |

> **向量管"单步对不对"，场景 eval 管"连起来讲不讲道理"。** 向量给一个输入看输出；
> 而用户感受到的是序列 —— 每一步都正确的函数，串起来照样可能走成荒谬的轨迹。
> 场景 eval 模拟一段跨周训练史（把上一步的建议当成用户实际练的内容喂回去），
> 再对整条 152 步的轨迹断言产品红线：理由一行放得下、双重渐进只在做满区间上限后才加重、
> 自重永不出现重量、按时长动作按 5 秒推进且不说「次」、重量只保持或增加……
>
> 它**不是装饰**：变异清单里有一条"只有场景 eval 抓得住"的变异体（把回归保护的文案写长到
> 59 字）—— 向量层 44/44 全过，场景层抓出来。那是这套 eval 存在的证明。

> **最后一行是这套自检里最该被理解的一层。** 前五层回答"代码对不对"，
> 它回答"**这些测试真的在守着行为吗**"：把源码故意改坏，看前五层红不红；
> 改坏了还不红 = 盲区。它第一次跑就抓出 4 个真实盲区（21 天边界、浮点噪声的等价性、
> `ensure()`/`flush()` 语义），并暴露了两处工具自身的假阳性。见 `tool/mutation.mjs` 的文件头。

三层引擎校验共用同一份 `engine/vectors.json`，所以「Dart 与 JS 行为一致」是被证实的**事实**，不是声称。
`flutter test` 的构成：引擎向量/红线/1RM + `tap_count` 边界 + **widget 交互测试**
+ **56 项持久化契约测试**（28 条断言 × 2 个实现：内存版与 drift 版）
+ **22 项动作库** + 4 项多动作 + **25 项动作选择页** + 2 项启动冒烟 + **22 项今日规划**
+ 6 项今日建议卡 + **3 项首页入口** + 18 项训练总结 + 15 项分享卡 + **20 项身体数据** + **29 项「我」页** + **23 项「进步」页**
+ **43 项埋点上报** + **5 项迁移** + **24 项单位换算** + **14 项休息偏好**
+ **19 项动作切换** + **22 项全部数据** + **16 项计划模板仓库** + **12 项计划模板界面** + **13 项首次引导**
+ **5 项渐进建议接线**（`progression_wiring_test.dart`：测的不是引擎算得对不对，而是**历史真的走进了控制器**）
+ **11 项按时长动作**（平板支撑类：引擎按秒推进 + 界面说「秒」不说「次」）
+ **22 项备份**（`backup_test.dart` 16 + `backup_scope_test.dart` 6：可导回的文件 / 粘贴导入 / 坏行跳过 / 幂等 / 预置 6 周历史 / **跨库恢复时按动作名补建缺失动作**）
+ **1 项版本号一致性**（`app_version_test.dart`：读 `pubspec.yaml` 核对界面上显示的版本号）
+ **7 项「我」页结构**（`profile_structure_test.dart`：三个二级页入口都进得去，
  而且**被收走的那些 key 不许再出现在「我」页上** —— 防止第一屏慢慢长回三屏）。

> 契约那 56 项容易数错：**每条断言都会在两个实现上各跑一遍**，
> 所以加 3 条断言等于加 6 项测试。

那 26 项是"换实现 UI 零改动"这句话的证明：同一组断言同时跑在 `InMemoryLocalStore` 和
`DriftLocalStore` 上，两者行为必须完全一致（组序、跨训练隔离、重复保存幂等、热身组排除、
软删除排除、自重动作重量为 null……）。

以上 6 层**就是 CI 本身**：workflow 只有一条命令 `./verify.sh`（[运行记录](https://github.com/sdknwdtvpv-sys/sport/actions)）。
而且 CI 里还有一道**账目**：日志里六层的标记必须都在、**不许出现「⊘ 阻塞」**
（`verify.sh` 在开发机上允许"环境阻塞不算失败"，CI 上这会让"某一层没跑"也变绿 —— 所以那里反过来判红）。
所以「CI 绿」= 「门禁绿」，没有第二种口径 —— 这层关系由 `tool/check-ci.mjs` 守着
（CI 不跑门禁、用 `--fast` 偷偷跳过某一层、混进门禁不管的命令、版本没钉住，都会判红）。
这也意味着整套验证在**从零 clone 的干净 Linux 环境**里同样成立，不依赖任何本机配置 ——
中文目录只影响本机的 `flutter analyze`，不影响 CI（runner 的工作目录本来就是 ASCII）。

**尚未验证**：真实埋点上报地址，以及 App 在真实设备上的表现。构建链已打通（Android APK
可构建，`libsqlite3.so` 三个 ABI 齐全，`flutter run` 的构建与安装阶段正常），但 App
**至今没在任何设备上跑过** ——「杀掉 App 重开、记录还在」这条要等真机确认（阶段 2/3）。

> ⚠️ **改过 `db.dart` 的表结构后，必须先重跑代码生成**，否则分析与测试都会报
> "Target of URI doesn't exist"：`cd app && dart run build_runner build`

> **下一步做什么** → [`ROADMAP.md`](ROADMAP.md)：6 个阶段，每步都有命令与可验收的完成标准。
> 其中**阶段 3「自己练一次」不要跳过** —— 成本是一次训练，产出是核心假设的第一个真实信号。

## 在新机器上继续

**这个仓库是唯一真源。** 换一台电脑只需要重新装工具链 —— 项目本身没有任何东西
只存在于某一台机器上（`db.g.dart`、`.dart_tool/` 是生成物，刻意不提交）。

### 一次性准备

| 需要 | 版本 | 用途 |
|---|---|---|
| Git | 任意 | |
| Node.js | **18+** | 动作库构建脚本 + JS 引擎测试 |
| Flutter SDK | **3.47.5**（stable） | 应用层。CI 也锁这一版，别用别的 |
| Android Studio | 最新 | **只在要跑真机 / 模拟器时需要**，写代码不需要 |

Flutter 的官方 zip 装法（arm64 Mac）。**建议直接用镜像**，官方源实测约 600 KB/s，
这个 2.1G 的包要下近一小时，镜像约 10.3 MB/s（见坑 5）：

```bash
mkdir -p ~/development
cd ~/development
curl -L -o flutter_3.47.5.zip \
  https://storage.flutter-io.cn/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.5-stable.zip
unzip -q flutter_3.47.5.zip
export PATH="$HOME/development/flutter/bin:$PATH"
flutter --version
```

### Android 工具链（不需要 Android Studio）

JDK + 命令行工具就够，比 Android Studio 省事，也不需要管理员权限：

```bash
# JDK 17：Flutter 对 AGP ≥ 8.0 要求的最低与默认版本就是 17，工程 target 也是 17
curl -L -o ~/development/jdk17.tar.gz \
  https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/aarch64/mac/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.20.1_1.tar.gz
tar xzf ~/development/jdk17.tar.gz -C ~/development
ln -sfn ~/development/jdk-17.0.20.1+1/Contents/Home ~/development/jdk-17

# Android 命令行工具
curl -L -o ~/development/commandlinetools.zip \
  https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip
mkdir -p ~/Library/Android/sdk/cmdline-tools
unzip -q ~/development/commandlinetools.zip -d /tmp/clt && \
  mv /tmp/clt/cmdline-tools ~/Library/Android/sdk/cmdline-tools/latest

export JAVA_HOME="$HOME/development/jdk-17"
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" \
  "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358"

flutter config --android-sdk "$ANDROID_SDK_ROOT"
flutter config --jdk-dir "$JAVA_HOME"
flutter doctor
```

`ndk` 版本必须与 `flutter.ndkVersion` 一致（定义在
`$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`），
否则 Gradle 报版本不匹配。首次 `flutter build apk` 时 Gradle 还会自己补装 CMake 与
它需要的 platform 版本 —— `sqlite3` 3.x 靠 native assets 编译 C 代码，这步省不掉。

**验证要跑 `build`，别只看 `doctor`** —— doctor 只证明装上了，build 才证明整条链能跑：

```bash
cd app && flutter build apk --debug
# ✓ Built build/app/outputs/flutter-apk/app-debug.apk
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libsqlite3.so
```

⚠️ 若 `maven.google.com` 不可达（DNS 解析到真实 Google IP 后连接超时），Android 工程
会卡在拉 AGP 与 androidx 上。**别改工程的 `settings.gradle.kts`** —— 那会影响所有人和
CI。用本机 `~/.gradle/init.gradle` 把可达镜像插到仓库列表最前面，详见文末
「这台机器上没有、也不需要带走的东西」。

### 拉下来之后

```bash
git clone git@github.com:sdknwdtvpv-sys/sport.git
cd sport

node seed/build.mjs
./verify.sh --fast
```

**克隆路径不要含单引号**，否则应用层跑不了（见坑 4）。macOS 上
`/Volumes/<卷名>` 常带撇号，`$HOME` 一般干净 —— 路径不干净时可以先跑
`./verify.sh --fast`（契约层 + 领域层 + 静态分析都正常），要跑 `flutter test`
时再把仓库放到干净路径。

`./verify.sh` 会自己判断缺什么：**Flutter 没装就跳过应用层并明确标注"阻塞"，
不会假装通过。**

### 要跑 App 时

```bash
cd app
flutter pub get
dart run build_runner build
dart analyze --fatal-infos
flutter test
```

`db.g.dart` 刻意不提交，所以 `build_runner` 那步不能跳 —— 但**忘了生成会大声报错**
（`Target of URI doesn't exist`），不会静默用旧 schema 通过。

### 五个环境坑（都踩过，记下来）

1. **`flutter analyze` 在中文路径下必崩** —— 上游 bug
   ([flutter/flutter#191309](https://github.com/flutter/flutter/issues/191309))，
   本仓库目录名是中文。**本项目一律用 `dart analyze`**，`verify.sh` 与 CI 都是。
2. **zsh 默认不把 `#` 当注释**，而且 `[...]` 会被当通配符（`zsh: no matches found`）。
   从文档里复制命令时**连同尾随注释一起粘**会报奇怪的错 —— 本仓库的命令都不带尾随注释。
3. **受限环境下 `flutter pub get` 可能失败**（它要清自己的临时目录、还要访问 pub.dev）。
   这时 `./verify.sh` 会把应用层标为"阻塞"而不是"通过"。
4. **路径里有一个单引号，`flutter test` 就必崩** —— 比第 1 条更隐蔽，因为路径看着
   全是 ASCII，只有一个标点。`flutter_tools` 生成 `listener.dart` 时会把测试文件
   路径塞进单引号字符串：

   ```dart
   goldenFileComparator = LocalFileComparator(Uri.parse('file:///Volumes/Elliot's SSD/.../foo_test.dart'));
   //                                                                  ↑ 字符串在这里被截断
   ```

   结果是所有测试连加载都失败（`+0 -14`），报的却是 `Expected ',' before this` 这种
   让人往语法上找的错。注意：

   - **符号链接救不了** —— flutter 读的是 `pwd -P` 的物理路径，不是逻辑路径。
   - **只影响 `flutter test`，不影响构建。** 同一路径下领域层、`dart analyze`、
     以及 `flutter build apk` 都实测通过 —— Gradle 构建不走那段生成的 Dart。
     所以**真机装包/调试可以直接在主仓库做，只有跑测试才需要换到干净路径**。
   - `verify.sh` 会识别这种情况并标为"阻塞"，不会误报成测试失败。
   - 解法：**把仓库放到不含 `'` 的路径再跑 `flutter test`**（macOS 上
     `/Volumes/<卷名>` 常带撇号，`$HOME` 一般干净）。

5. **官方源慢到会超时，换镜像快 17～39 倍**（实测）：

   | 源 | 实测速度 |
   |---|---|
   | `storage.googleapis.com`（Flutter SDK zip） | ~600 KB/s |
   | `storage.flutter-io.cn` | **~10.3 MB/s** |
   | `pub.dev`（依赖） | ~40 KB/s |
   | `pub.flutter-io.cn` | **~1.5 MB/s** |

   2.1G 的 SDK zip 从 1 小时缩到几分钟。`pub get` 不换源会慢到 `verify.sh`
   的 240 秒超时里跑不完，然后被标成"阻塞"—— 看着像环境坏，其实只是慢：

   ```bash
   export PUB_HOSTED_URL=https://pub.flutter-io.cn
   export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
   ```

### 这台机器上没有、也不需要带走的东西

| | |
|---|---|
| `~/development/flutter`（4.1G） | 新机器按上面的命令重装 |
| `~/development/jdk-17` | 同上，Temurin 17 |
| `~/Library/Android/sdk` | 同上，sdkmanager 装 |
| `.pub-cache` | 新机器 `flutter pub get` 时会重新下 |
| `~/.gradle/init.gradle` | **本机专用的 Maven 镜像覆盖**。这台机器的网络下 `maven.google.com` 不可达，它把 `dl.google.com/dl/android/maven2` 与 `maven.aliyun.com/repository/google` 插到 `google()` 前面。**刻意不放进仓库** —— 本机网络问题不该写进工程、影响 CI；纯离线/正常网络下没有它也能构建 |
| 这段开发过程的对话记录 | **不在仓库里**。但结论都落进了 `CHANGELOG.md`、`ROADMAP.md` 的教训清单、以及 `docs/` |

## 这个仓库现在是什么

**它不是一份文档，也不是一个完整产品。它是一个"契约仓库"：每一层都用可执行的东西锁住。**

| 层 | 产物 | 可执行？ | 谁验收 |
|---|---|---|---|
| 产品定义 | `PRODUCT.md` | 散文 | 创始人 / 合伙人 |
| 交互 | `prototype/index.html`（**13 屏，零依赖，双击就开**）+ `docs/interaction-spec.md` | **原型可交互 + widget 测试** | 设计 / 客户端 |
| 数据 | `docs/data-model.md` + `seed/exercises.sql` + `app/lib/data/db.dart` | **可执行**：351 条种子可直接导入；drift 落库有契约测试，**每一次 schema 迁移（v1→v10）都有测试** | 客户端 / 后端 |
| 规则引擎 | `engine/progression.mjs` + `app/lib/domain/progression.dart` | **双实现 + 共用 45 条向量** | 客户端（移植验收标准） |
| 埋点 | `docs/analytics.md` + `docs/analytics-sdk.md` | 规格 + `tap_count` 有单测 | 客户端 / 数据 |
| 验证 | `docs/usability-test.md` + `-kit.md` | 流程手册 + **7 个数字可一键算**（`tool/usability-report.mjs`）；现场打印 `usability/记录表.md` | 你本人 |
| **上架前的行政** | `docs/release-admin.md` + `docs/store-listing.md` | 软著 / App 备案 / 隐私政策公网 URL（行政）；应用描述、分级问卷、**数据安全表单 A/B 两版**、软著源码 60 页（`tool/copyright-export.mjs`） | 你与我各半 |

**这个仓库最重要的一条设计**：Dart 与 JS **共用同一份 `engine/vectors.json`**，不复制。
于是"移植是否完成"成了一个可判定的事实 —— `./verify.sh` 全绿就是一致，没有解释空间。

```
engine/vectors.json ──┬──> engine/run-tests.mjs        （Node）
                      └──> app/test/progression_vectors_test.dart（Dart）
```

---

## 按角色怎么用

### 你是产品 / 创始人 —— 要当面说服别人

1. 打开 `prototype/index.html`（**不需要任何工具链，双击就行**），当面演示训练主屏：点大按钮记一组 → 倒计时跑起来 → 长按 → 弹层改重量。40 秒胜过任何 PPT。
   **13 屏在同一页**（S1–S13，覆盖已实现范围），往右就是动作选择器、动作切换、结束总结、进步、全部数据、我、计划模板、身体数据、首次引导。
   它现在是**招测试者时当面演示用的**（真机上也能装包演示）；`Cmd+P` 可打印成 PDF。
2. 电梯陈述在 `PRODUCT.md` §0–§6。
3. 要拿真实数据说话：按 `docs/usability-test-kit.md` 招 5 个人。**第 6 节"训记对照环节"是关键** —— 让被试用自己的训记做同一件事，直接比出省事程度。

### 你是客户端开发（Flutter）—— 要开工

工程已经在 `app/`，跑起来就能看到实现：

| 步骤 | 看什么 | 做完的标准 |
|---|---|---|
| 1 | `docs/tech-decisions.md` | 确认选型（Flutter + 原生 Swift 扩展）与合规红线 |
| 2 | `docs/data-model.md` | 建库；`seed/exercises.sql` 导入 351 条 |
| 3 | `app/lib/domain/progression.dart` | 改引擎后 `flutter test` 必须全绿 —— 28 条向量是你唯一的验收标准 |
| 4 | `app/lib/features/workout/` | 对照 `docs/interaction-spec.md` 扩展其余屏 |
| 5 | `docs/analytics-sdk.md` | 接真实上报地址 —— 客户端管线已就绪（outbox + 批量 ≤100 + 退避重试 + **训练期间挂起**），现用 `_NullTransport` 兜底 |

**当前进度**：引擎、交互红线、埋点计量这三样"最容易做坏"的东西，已被**六层门禁**（测试 + 变异测试）锁住；
UI 已实现 **8 屏**（S1 / S2 / S3 / S4 / S5 / S7 / S8 / S10），动作库 **351 个**
（318 力量 + 11 热身 + 13 有氧 + 9 拉伸，其中有氧支持**记距离**）。
还没做的见上文「现在还没有的东西（别期待）」，下一步见 [`ROADMAP.md`](ROADMAP.md)。

### 你是后端开发

- `docs/data-model.md` 全局约定：客户端生成 UUID 主键、每表带 `updated_at` + `deleted_at`、last-write-wins
- `docs/analytics-sdk.md` §1 数据流、§5 上报策略、§6 事件优先级（**P0 不能丢**）
- `docs/tech-decisions.md`：一期只做账号 / 增量同步 / 云备份，**不做实时协同、不做服务端计算**

### 你是数据 / 增长

- `docs/analytics.md`：事件字典 + 北极星定义（首次 `app_open` 起 24h 内完成含 ≥1 组的训练，目标 ≥55%）+ 看板布局
- **必须知道的治理规则**：`set_logged.tap_count` 中位数或 P90 **比上一版上升**，**该版本不允许发布**
  （口径是端到端的：导航、选动作、切换动作都计入，见 `docs/analytics.md` §3）
- `tap_kinds` 回答"点击花在哪了"；§5「反指标」列了四种"出现即停下讨论"的情况

### 你是 QA / 测试

- `./verify.sh` 作为统一回归入口
- `app/test/workout_flow_test.dart` —— 交互红线的自动化版本（9 个 widget 测试）
- `app/test/tap_meter_test.dart` —— `tap_count` 的 10 条边界用例（含端到端口径的 `ensure` 语义）
- `app/test/progression_wiring_test.dart` —— **历史真的走进了控制器**（引擎对不等于接线对）
- `docs/interaction-spec.md` §12 设计验收清单 / `docs/analytics-sdk.md` §12 接入验收清单
- `docs/usability-test-kit.md` —— 可用性测试现场手册

---

## 常用命令

```bash
./verify.sh                        # 全部自检（推荐入口）

node seed/build.mjs                # 重建动作库种子；校验失败即非 0 退出
node engine/run-tests.mjs          # JS 规则引擎向量（35 项）
dart app/tool/check_domain.dart    # Dart 引擎 vs 同一份向量（41 项，零依赖）
cd app && dart analyze --fatal-infos        # 静态分析（不要用 flutter analyze，见下）
cd app && flutter test                      # widget 测试（需要 pub）
```

改动作库：编辑 `seed/parts/*.json` → `node seed/build.mjs` → `exercises.json` 与 `exercises.sql` 自动重建。
改引擎规则：**先改 `engine/vectors.json`**（加一条向量），再改 `engine/progression.mjs` 与 `app/lib/domain/progression.dart`，两边都跑绿才算完成。

---

## 在受限环境里（比如没有网络、或不能删除文件）

`flutter test` 需要先跑通 `flutter pub get`，而 pub 会清理自己的临时目录并访问 pub.dev。
在受限环境里这步会失败。这时**领域层仍然可以完整验证**，因为它是纯 Dart 的：

```bash
dart app/tool/check_domain.dart
```

它跑的是同一份 `engine/vectors.json`，外加 3 条硬红线和 tap_count 边界 ——
也就是"Dart 引擎是否与 JS 引擎一致"这个最关键的结论，不依赖网络就能被证实。
只有 widget 测试需要 Flutter 测试框架，那种情况下 `./verify.sh` 会把应用层标记为
**阻塞而不是通过**，并在结尾明确提示"有步骤未完成验证"。

## 已知工具链问题：`flutter analyze` 在中文路径下必崩

本仓库目录名是中文，而 **Flutter 3.47 的 `flutter analyze` 遇到非 ASCII 路径会崩溃**
（[flutter/flutter#191309](https://github.com/flutter/flutter/issues/191309)）：

```
FormatException: Unexpected end of input (at character 328)
...%E4%BA%86%E4%B9%88/app/"}],"capabilities":{"window":{"workDoneProgress":tr
analysis server exited with code 255
```

**这不是代码问题。** `dart analyze` 走同一套 `analysis_options.yaml`，只是绕过了 flutter_tools
的 LSP 客户端，结果是 `No issues found!`（`--fatal-infos` 最严格档）。

- **本项目一律用 `dart analyze`** —— `verify.sh` 与 CI 都是这样。
- 若你确实需要 `flutter analyze`：把目录改成纯 ASCII 名即可。**源码里没有任何硬编码绝对路径**
  （只有可再生的 `app/.dart_tool/package_config.json` 里有），改名是安全的。
- CI 不受影响：GitHub runner 的工作目录本来就是 ASCII。
- 这与 pub 无关 —— 加 `--no-pub` 仍然崩。

## 现在还没有的东西（别期待）

> 这一节原先留在早期状态（"没有构建配置""数据在内存里""动作只有 1 个"），已按实际
> 进度重写。想知道"能不能用"，请看 `ROADMAP.md` 的阶段表 —— 那里才是准的。

| 缺什么 | 为什么 | 影响 |
|---|---|---|
| 🚧 **真机交互验收** | 真机上装的是 **v1.35.2 release**（逐版覆盖安装，`versionCode 48`）。**自动化那半已经做完了**（2026-09-30 手机解锁当天跑的）：`adb shell input` 注入走了一遍 冷启动 → 一次点击记一组（→ 休息计时起跳）→ 总结（320 kg）→ 进步 → 我 → **杀进程重开数据还在**，`E/flutter` 与 `overflowed` 都是 0，证据图在 `docs/images/walkthrough-0*.png`。**剩下的是"真的用手指走一遍"** —— 手感、误触、单手可达性、出汗时按大按钮 | 六层门禁全绿；**这一条只剩人类判断**（自动化走的是输入层，不是手感）—— **这是最大的一条** |
| ✅ ~~v1 → v2 迁移的真机验证~~（已在真机过） | 真机里原本是 `v1.0.0` 留下的**老库**，直接覆盖安装 `v1.2.0`（`schemaVersion` 1 → 3）后，`onUpgrade` 跑完、**数据一条没丢**（冷启动读回 12 组） | 这是"老库升级必须真机过一次"的实测通过 |
| 🚧 **分享卡的交付** | 生成与交付都已实现（`share_plus` + `gal`），但分享面板与相册写入依赖平台通道 | 测试覆盖不到，只能真机跑 |
| ❌ **发布签名** | 目前只有 debug key；release 签名要生成 keystore 并妥善保管（不能进仓库） | 商店不接受 debug 签名的包 |
| 🚧 **隐私政策** | 中英文均已成文、占位符已填（运营者 `Elliot.LI`） | 待**法务审核** + 公网可访问 URL |
| ❌ **真实埋点上报地址** | 客户端已就绪（outbox + 批量 ≤100 + 退避重试 + 训练期间挂起），只缺后端接收，现用 `_NullTransport` 兜底 | 事件不丢，但看板没有数据源 |
| 🚧 **云端（账号 + 备份）** | **服务端与客户端都已落地**：`server/backend.mjs`（零依赖 HTTP + 17 条自检）· 客户端加密/账号层（恢复码 + HKDF + AES-256-GCM，**服务端只存密文**）· 云备份界面（默认关闭、**没配地址的包里连入口都不出现**）· 「删除全部数据」会问是否一并删云端。**还差一台服务器 + 域名 + 备案**（阶段 4，在你那边） | 现在**装到手机上的包看不到云备份**（编译期没配地址）—— 这是设计，不是没做完。端到端"服务端看不到明文"已有测试证明（真的把服务端起起来、翻它的 sqlite 找明文） |
| ❌ **S14 会员页** | `PRODUCT.md` 列的四大权益（AI 动态调整 / 多端云同步 / 无限历史对比 / 教练协作）**全部依赖后端**，一项都不存在 | 做出来等于向用户宣传不存在的功能，比不做更糟 —— 等后端落地再说 |
| ⚠️ **`tap_count` 目标值未校准** | `docs/analytics.md` 的 55% 与 `tap_count` 目标都还是**估计值**，且口径已改端到端、旧目标作废，要靠阶段 5 拿真实数字 | **按项目自己的门禁，校准前不允许发布** |

> 📋 **哪些事只能由人来做、现在卡在谁那**：见 [`docs/your-todo.md`](docs/your-todo.md)。

已实现 **13 屏**：S1 / S2 / S3 / S4 / S5 / S6 / S7 / S8 / S9 / S10 / S11 / S12 / **S13**。
另有二级页 **云备份**（v1.21.0，入口只在配了服务器地址的包里出现；见 `docs/screens.md` S10 那节）。
未做：**S14 会员页**（原因见下表）。
（**S15 设置的内容已并入 S10**：单位 / 默认休息 / 渐进开关 / 导出都在那儿。）

---

## 建议的下一步优先级

1. **插上手机跑起来**（收尾阶段 2）—— 开手机的「USB 安装」权限，然后 `flutter run`。
2. **自己去练一次**（阶段 3）—— `ROADMAP.md` 标的唯一硬依赖链，也是唯一能验证
   "它到底能不能用"的手段。成本是一次训练，产出是核心假设的第一个真实信号。
3. **招 5 人做可用性测试**（阶段 5）—— 只占日历、不占工时，尽早启动；拿回 7 个数字
   回填 `docs/analytics.md` 的目标值。
4. **按真实感受修**，再补分享卡与体重记录。

> 在测试数据出来之前，不建议扩张功能面。若 T1 通过率或 `tap_count` 中位数不达标，现在这批文档与代码里有一半要改。
