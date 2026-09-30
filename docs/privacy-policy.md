# 练了么 · 隐私政策

> **状态：草案 —— 未经法务审核，不得直接用于上架。**
>
> 本文档中的每一项**都是从代码里核对出来的**，不是套模板写的（核对方式见文末「附录 B」）。
> 英文版见 `docs/privacy-policy.en.md`；**中英不一致时以中文版为准**。
>
> **上架前只剩两件事：**
> 1. ⬜ 由法务或有资质的人审核 —— 健康数据属《个人信息保护法》的**敏感个人信息**
> 2. ⬜ 把「生效日期」改成实际的首次发布日
>
> | | |
> |---|---|
> | 运营者 | **Elliot.LI**（个人开发者） |
> | 联系方式 | **https://github.com/sdknwdtvpv-sys/sport/issues** |
> | 生效日期 | **首次上架日**（当前：`未发布` —— 上架前必须替换为实际日期） |

---

## 一、一句话概括

**练了么是一款离线优先的训练记录工具。你的训练数据只存在你自己的手机里。
我们不要求注册、不要你的手机号、不要定位、不要通讯录。
唯一的联网行为是「帮助改进产品」开关打开时的匿名使用统计，而这个开关你可以随时关掉。**

---

## 二、我们收集什么

### 2.1 只存在你手机里、不上传的数据

| 数据 | 内容 | 用途 |
|---|---|---|
| 训练记录 | 动作、重量、次数、组序、是否热身、完成时间 | 记录你的训练，算容量与进步曲线 |
| 训练会话 | 开始/结束时间、总组数、总容量 | 训练总结页 |
| 个人设置 | 渐进建议开关、单位偏好、"帮助改进产品"开关 | 记住你的选择 |

这些数据存放在应用私有的本地数据库（SQLite，经 drift 管理），**不会离开设备**。

### 2.2 「帮助改进产品」打开时才会产生的数据

这是一个**默认开启、随时可关**的开关（路径：「我」→「帮助改进产品」）。它只产生下面
18 类事件 —— 字段是**有限且固定**的（完整清单在 `docs/privacy-facts.json`，
由 `tool/privacy-audit.mjs` 与代码逐条对账）：

| 事件 | 什么时候发 | 携带的字段 |
|---|---|---|
| `set_logged` | 记录一组时 | `workout_id`、`exercise_id`、`set_index`、`weight_kg`、`reps`、`distance_m`、`set_type`、`rpe`、`tap_count`、`tap_kinds`、`entry`、`is_offline` |
| `set_undone` | 撤销一组时 | `set_index`、`method`、`seconds_after_log` |
| `app_open` | 冷启动完成 | `is_first_open`、`ms_since_launch`、`entry` |
| `workout_started` | 进入训练屏 | `source`、`exercise_count`、`ms_since_launch` |
| `workout_finished` | 训练结束 | `duration_sec`、`total_sets`、`total_volume_kg`、`exercise_count`、`ms_since_launch` |
| `rest_started` | 开始休息计时 | `exercise_id`、`planned_sec`、`auto` |
| `rest_completed` | 休息计时走完 | `exercise_id`、`planned_sec` |
| `rest_skipped` | 手动跳过休息 | `exercise_id`、`planned_sec` |
| `seed_import_failed` | 动作库刷新失败 | `error`（错误类型，不含内容） |
| `onboarding_step` | 每步引导（选择即前进 / 点跳过） | `step_index`、`skipped` |
| `exercise_added` | 从选动作页选中或新建一个动作 | `exercise_id`、`add_method` |
| `set_edited` | 步进弹层确认时**真的改了**重量或次数 | `field`、`from`、`to`、`suggestion_id` |
| `suggestion_shown` | 记下一组时，那一下是按建议来的 | `suggestion_id`、`exercise_id`、`reason_code`、`suggested_weight_kg`、`suggested_reps` |
| `suggestion_accepted` | 记下的值与建议完全一致 | `suggestion_id`、`reason_code` |
| `suggestion_modified` | 记下的值与建议不同 | `suggestion_id`、`reason_code`、`delta_weight_kg`、`delta_reps`、`direction` |
| `pr_achieved` | 这次训练破了纪录 | `exercise_id`、`pr_type`、`value`、`prev_value` |
| `share_card_created` | 生成分享卡（存相册 / 系统分享） | `channel` |
| `body_metric_logged` | 记录身体数据 | `has_weight`、`has_note` —— **只报"填没填"，体重数值不出设备** |

**每个事件都会另外带上这 7 个公共字段**（它们回答"这是哪台设备、哪一次使用、哪个版本"）：

| 字段 | 是什么 |
|---|---|
| `device_id` | **本机随机生成的匿名标识**（32 位十六进制）。与账号无关、不含设备信息。点「删除全部数据」会**一并清除**（见第五节） |
| `session_id` | 一次使用会话的随机标识；30 分钟没有操作就换一个新的 |
| `user_id` | **恒为 null** —— 没有账号系统。游客也要上报，否则"新用户有没有练起来"这个指标算不出来 |
| `app_version` | 版本号（用于比较不同版本"记一组要几下"） |
| `platform` | `android` / `ios` |
| `is_offline` | 事件发生时是否离线 |
| `schema_version` | 事件格式版本号，只增不改 |

说明几点，避免误解：

- `workout_id` / `exercise_id` / `device_id` / `session_id` 都是**本机生成的随机标识**，
  不是你的身份，也不含手机号、IMEI、广告标识符之类的设备信息。
- 我们会知道"某个动作、某个重量、做了几组"，因为这是产品要验证的核心指标
  （`tap_count` 衡量"记录一组要几下"）。**它属于健康相关信息，我们按敏感个人信息对待。**
- `entry` 记录这次是点大按钮还是长按改重量输入的。
- `app_open` / `workout_started` / `workout_finished` 是"漏斗"的三个点：
  只知道**有没有**走完流程与花了多久，不含任何训练内容以外的东西。

### 2.3 我们**不**收集

- ❌ 姓名、手机号、邮箱、身份证 —— **没有账号系统**
- ❌ 位置信息
- ❌ 通讯录、相册、相机、麦克风
- ❌ 设备广告标识符（无广告 SDK）
- ❌ 剪贴板内容（"导出记录"是**写入**剪贴板给你，我们不读取）
- ❌ **体重等身体数据的数值** —— 只上报"记没记体重 / 有没有备注"这类布尔值，数值不出设备
- ❌ **训练备注、自定义动作名称等自由文本** —— 一律不上报

---

## 三、数据在哪、传给谁

### 3.1 现状（务必如实告知：当前版本不联网上报）

**当前发布的版本不会把你的任何数据发送到任何服务器。** 这不是承诺，是代码事实：

- 上报地址是**编译期配置**的：没配地址时埋点通道是 `_NullTransport`，它**永远失败** ——
  事件只会留在本机的 outbox 里。当前发布的包**没有配地址**。
- 训练数据同步通道是 `InMemorySyncQueue`，只存内存、不上网，App 一关就没了。
- **你可以自己验**：附录 B 给了三条命令（看权限、看埋点字段、看通道是不是 NullTransport）。

换句话说，**现在连我们自己也拿不到你的数据。** 我们如实标注这一点，是因为把
"将来会做"写成"已经在做"是欺骗，反过来把"其实没做"说成"做了"同样没必要。

### 3.2 接入真实上报之后

在未来的版本里，当上面那个开关打开时，2.2 的事件会通过 HTTPS 发送到我们自建的接收端。
届时本政策会更新版本号与生效日期，并在应用内提示。**无论何时，开关关闭后一行数据都不会发出。**

> ⚠️ **待决（2026-09-30，法务审核前必须定）**：按当前代码，没配地址的版本**不会丢**
> 它记下的 2.2 事件，而是攒在本机（上限 1 万条）。所以"接入上报的第一个版本"
> 会把之前版本攒下的事件一起发出去 —— **除非我们显式地不让它发**。
> 这直接影响本节怎么写、以及应用商店数据安全表怎么填。
> 三个选项与代价见 `docs/analytics.md` §10。**在定下来之前不要发布配了上报地址的包。**

我们**不向任何第三方出售、出租或共享**你的个人信息。不接入第三方广告、不接入数据经纪。

---

## 四、权限

应用声明**两项**系统权限（打包后另有 1 条 AndroidX 自动加的签名级自有权限，不涉及用户数据、也不会出现在系统的权限列表里），其中第二项**只在老系统上生效**：

| 权限 | 为什么 | 适用范围 |
|---|---|---|
| `android.permission.INTERNET` | 仅用于 2.2 的匿名使用统计（开关打开时） | 全部 |
| `android.permission.WRITE_EXTERNAL_STORAGE` | 把「分享训练卡」的图片存进系统相册 | **仅 Android 9 及以下**（带 `maxSdkVersion="29"`） |

关于第二项，说明三点：

- **Android 10 及以上完全不需要它** —— 新系统走 MediaStore，写入相册不需要任何权限。
  我们在声明时带了 `android:maxSdkVersion="29"`，所以**新系统的用户在被请求的权限列表里
  根本看不到这一项**。
- 它只能写图片，且只在你自己点「存相册」时才会用到。
- 分享卡是**在本机画出来的**：图片由设备上的界面直接渲染成 PNG，
  **不会上传到我们的服务器**。点「分享」是把这张图交给系统分享面板，
  之后你选了哪个应用（微信、相册……）由你决定，那一步的数据处理适用那个应用的隐私政策。

除此之外**不申请**定位、通讯录、相机、麦克风、日历、后台运行等任何权限。

> 实现说明：Flutter 模板默认只在 debug/profile 变体里加 INTERNET（为了热重载），
> release 版原本没有这个权限。本项目把它显式声明到 main，使三个变体行为一致 ——
> 否则将来接上报地址时，release 版会**静默失败**且不报错。

---

## 五、你的权利与控制

| 权利 | 怎么做 |
|---|---|
| **关闭使用统计** | 「我」→「帮助改进产品」关掉。立即生效，功能不受任何影响 |
| **导出你的全部数据** | 「我」→「导出全部记录」，生成 CSV 复制到剪贴板 |
| **删除全部数据** | 「我」→「数据」→「删除全部数据」。二次确认后立即清空本机记录与设置 |
| **卸载即删除** | 卸载应用会一并删除本机数据库 |

删除的范围，写清楚以免误解：

- **会删**：全部训练与组记录、个人设置（含各项开关）、**还没上报出去的埋点事件**、
  **以及埋点用的匿名设备标识**（`device_id` / 会话标识 / 首次启动时间）。
  代价如实告知：删过之后，这台设备在统计里会被当成一台新设备
  （否则"删除"就删不干净）
- **不会删**：内置的动作库（351 个动作）—— 那是产品自带的资料，不含你的任何信息
- 是**硬删除**，不是打标记。删除后无法恢复，我们也没有备份能帮你恢复

---

## 六、数据保留

- 本机数据：你不删就一直在（这正是训练记录工具该有的行为）。
- outbox 里的待发事件：有数量上限，超过后按优先级丢弃（P0 训练数据优先保留）。
- 服务器端：**当前不存在服务器端数据。**

---

## 七、未成年人

本产品不面向 14 周岁以下儿童，也不会有意收集其个人信息。
若你是未成年人的监护人并认为我们持有相关信息，请通过文末方式联系。

---

## 八、政策变更

本政策更新时，我们会在应用内与版本更新说明中提示，并更新文首的生效日期。
涉及重大变更（例如开始真实上报）时，会单独征求你的同意。

---

## 附录 A：本政策的事实来源

| 说法 | 代码/文件位置 |
|---|---|
| 18 类埋点事件与字段 | `app/lib` 下所有 `track(...)` 调用点；**逐条对账见 `tool/privacy-audit.mjs`** |
| 7 个公共字段（含 `device_id`） | `app/lib/analytics/analytics_context.dart`；匿名 ID 存在 `analytics_meta` 表 |
| 删除数据会清掉匿名标识 | `app/lib/data/drift_local_store.dart`（同一事务内删 `analyticsMeta`） |
| 事实源与政策正文的对应 | `docs/privacy-facts.json`（机器可查） |
| 开关默认开启、落库 | `app/lib/data/db.dart`（`analyticsEnabled`，默认 `true`）、`app/lib/data/profile_repository.dart` |
| 关闭后什么都不记 | `app/lib/analytics/analytics.dart`（`NoopAnalytics`）、`analytics.dart` 的 `if (!enabled) return;` |
| 当前不联网 | `app/lib/main.dart`（`_NullTransport`）、`app/lib/data/sync_queue.dart`（`InMemorySyncQueue`） |
| 训练期间不发请求 | `app/lib/analytics/flusher.dart` 的 `suspend()` / `resume()`，有测试守着 |
| 权限就那两项（另有一项仅 API ≤29 生效） | `app/android/app/src/main/AndroidManifest.xml`（**打包后**用 `aapt2 dump badging` 核，见附录 B） |
| 删除权可用（第四十七条） | `app/lib/features/profile/profile_screen.dart`（`_deleteAll`）、`app/lib/data/local_store.dart`（`deleteAllUserData`） |
| 删除含待发埋点 | `app/lib/data/drift_local_store.dart`（同一事务内删 `analyticsOutbox`） |
| 无账号系统 | 全仓库无登录/注册代码；`app/lib/data/` 下只有本地库 |

## 附录 B：怎么自己核对

不必相信本文档，可以直接验：

```bash
# 0. 一条命令把"代码 ↔ 隐私事实 ↔ 政策正文"全对一遍（对不上会退出码 1）
node tool/privacy-audit.mjs
#    再核一次**打包后**的合并权限（插件的权限在这一步才会露出来）
node tool/privacy-audit.mjs --apk app/build/apk/<你的包>.apk

# 1. 看权限：可以自己解包看合并后的 manifest
unzip -p app/build/apk/<你的包>.apk AndroidManifest.xml | strings | grep -i permission

# 2. 看埋点发了什么
grep -rn "track('" app/lib/

# 3. 看当前是否真的不联网（应该是永远失败的 _NullTransport 或没配地址）
grep -n "LIANLEME_ANALYTICS_URL\|_NullTransport" app/lib/main.dart

# 4. 抓包验证"训练中零请求"（需要真机，见 docs/analytics-sdk.md §12）
```
