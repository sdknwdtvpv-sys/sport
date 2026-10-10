# 方案 · 场景与回访（v2 第二批）

> **状态（2026-10-04 更新）：①② 都已完成。** 见文末「进度」一节；③ Widget 按下面的建议**先不做**。
> 来源：v2 规划时你点的第 2 条 ——
> "做场景与回访的一批"（锁屏/灵动岛组间休息 · Widget · 本地提醒）。
>
> ⚠️ **这一批与前一批（回收站/笔记/1RM）有一个本质区别**：
> 前一批是**纯 Dart、零新权限**；这一批**三件都要动平台原生配置**
> （iOS 扩展 target / Android AppWidget / 通知权限），
> 而每一种都会连带**中英政策 + 隐私事实表 + 两张商店表单**。
> `docs/feature-backlog.md` 自己写过："值得单独一批做，不适合塞进别的版本"。
>
> 所以这一页按**风险从低到高**排序，并且明确每一件"能不能单独上线"。

---

## 为什么是这三件（共同的判断）

`docs/decision-index.md` A 类第 11 条 + `docs/competitor-xunji-pro-v7.md` 第三档。
三件服务的是同一个问题：**用户不打开 App 的时候，我们还在不在他的视野里？**

而 `PRODUCT.md` §1 写着唯一要设计好的场景是「**组间休息的 60 秒**」——
那个场景里用户**恰恰不看手机**（手机在包里/架子上、或者锁屏扣在器械上）。
所以这三件不是"加功能"，是**把核心场景从"App 里"延伸到"器械旁"**。

| # | 件 | 服务的场景 | 需要什么 | 能单独上线吗 |
|---|---|---|---|---|
| 1 | **锁屏 / 灵动岛组间休息** | 组间那 60 秒（**最贴核心场景**） | iOS ActivityKit 扩展 target | ✅ 能（只 iOS） |
| 2 | **Widget** | 不打开 App 也看得见"今天练什么 / 上次练到哪" | iOS WidgetKit + Android AppWidget | ✅ 能（两端可分批） |
| 3 | **本地提醒**（"明天该练背了"） | 回访钩子（D7） | 通知权限 + 调度 | ✅ 能，但要**先过政策/表单那一关** |

---

## 1. 锁屏 / 灵动岛组间休息（先做这一件）

**为什么排第一**：它命中的是"唯一要设计好的场景"，而成本**只碰 iOS、不碰权限**。

* **做什么**：`startRest` 时启动一个 Live Activity，显示
  「休息 01:27 · 下一组 62.5 kg × 8」，倒计时结束/用户跳过时结束它。
* **技术**：iOS 16.1+ 的 ActivityKit；Flutter 侧通过 MethodChannel 调用，
  **业务逻辑仍全在 Dart**（`workout_controller` 只管发"开始休息/结束休息"两个事件）。
* **门禁要跟上**（这是本项目的规矩：新产物必须有新守卫）：
  * `tool/check-ios-app.mjs` 现在核对 `.app` 的十项（身份/权限/资产/设备族…）——
    加了扩展之后产物里会多一个 `PlugIns/*.appex`，**要加一条"扩展真的在包里、且它的
    Info.plist 声明了 Live Activity"**；
  * 反向用例：把扩展从包里拿掉 → 守卫必须红（否则它就是"看着核过了"）。
* **代价**：iOS 侧 2–4 人日 + 门禁 1 人日；**Android 没有等价物**
  （Android 14+ 有"实时通知"，但形态与可见性都不同）→ 先做 iOS，Android 只做常驻通知（可选）。
* **风险**：低。不碰权限、不碰数据落库、不影响 `tap_count`（它是被动显示）。

## 2. Widget（第二件）

**做什么**（两个尺寸，两个内容）：
* 小号：**上次练到哪**（"上次练到第 3/6 个动作 · 继续"）—— 不打开 App 就能续上；
* 中号：**今天练什么**（部位 + 前 3 个动作）—— 与首页那块同源（同一份 `_todayPlan`）。

**技术**：iOS WidgetKit（Swift）+ Android AppWidget（Kotlin/Glance）。
⚠️ **Widget 不能直接读 Flutter 的 drift 库**（那是 App 私有沙盒里的 SQLite）——
所以必须有一个**共享容器**：App 在每次 `_loadTodayPlan()` 之后，往
`UserDefaults(suiteName:)` / Android `SharedPreferences` 写一小份 JSON 摘要。
**这份摘要是第二份数据**，因此必须有：
* 一条"摘要与真源一致"的测试（写 → 读 → 逐字段比对）；
* 一条"摘要过期"的处理（App 很久没打开 → Widget 显示"打开 App 更新"，**不许显示陈旧的计划**）。

**代价**：iOS + Android 各 3–5 人日（两套原生）+ 共享容器与测试 2 人日。
**风险**：中。它是本项目**第一次写原生 UI**，且要维护两套。

## 3. 本地提醒（第三件，**但它有前置**）

`docs/feature-backlog.md` #6 已经把它标为"下一批第一件"，并写明了原因：
"要引入通知插件 + 新权限，会同时动**中英政策 / 隐私事实表 / 两张商店表单 / iOS 与安卓配置**"。

**顺序上它应当与下面这批一起做**（不是因为它难，而是因为**它的成本主要在文档与合规**）：
1. 引入通知能力 + 运行时权限（Android 13+ 需要 `POST_NOTIFICATIONS`）；
2. 政策：中英两份都要加"本地通知"那一段（**本地通知不联网**，这句话本身要写清楚）；
3. `docs/privacy-facts.json`：`permissions` 加一条 + 一张商店表单要勾"通知"；
4. `tool/privacy-audit.mjs` / `check-store-forms.mjs` 的横查要能覆盖它；
5. 然后才是"什么时候提醒"的产品判断（练完第二天？连续两天没练？**默认关，用户主动开**）。

**代价**：通知本身 1–2 人日 + **政策与表单同步 1–2 人日**（这一半才是真的成本）。
**风险**：中。多一个权限 = 多一份隐私面，而本项目在"默认不收集"上做过一次完整审计
（`docs/privacy-policy.md` §2.1），这条要按同样的标准写。

---

## 建议的批次顺序

| 序 | 件 | 为什么是这个顺序 | 预计 |
|---|---|---|---|
| 1 | 锁屏/灵动岛休息 | 最贴核心场景；只碰 iOS；不碰权限 | 3–5 人日 |
| 2 | 通知（含政策/表单同步） | 它是 **D7 钩子**，而 D7 ≥ 35% 是四条护栏里唯一还没排过功能的一条 | 2–4 人日 |
| 3 | Widget | 成本最高（两套原生 + 共享容器），但价值与 1/2 重叠一部分 —— **等 1/2 的数据** | 8–12 人日 |

⚠️ **第 3 件建议先不做**，理由同 `docs/plan-apple-watch.md`：
1 和 2 会告诉我们"用户到底想不想在 App 之外看到训练"——
如果锁屏倒计时没人用，Widget 大概率也没人用。**先花 3 人日验证，再花 10 人日建设。**

---

## 与既有承诺的关系（必须先说清）

| 承诺 | 这一批会不会破 |
|---|---|
| "数据只存在这台设备上" | ❌ 不破：三件都在本机（Live Activity / Widget / 本地通知都**不联网**） |
| "首次 60 秒零权限" | ⚠️ **要小心**：通知权限**不能**在启动时要——必须在使用到该功能时才问（现在体重单独同意那道门就是这么做的） |
| "每组 ≤ 1 次点击" | ❌ 不破：三件都是被动显示，不增加点击 |
| 渐进式暴露 | ✅ 三件默认都关/不出现，用户主动开 |

---

## 进度（2026-10-04）

### ① 锁屏 / 灵动岛组间休息 —— ✅ **已实现**

* `app/ios/RestWidget/`：ActivityKit 扩展（`RestActivityAttributes` + `RestActivityWidget`：
  锁屏卡片 + 灵动岛三态）。**倒计时由系统自己走**（`Text(timerInterval:)`），
  所以 App 被挂起时锁屏上的数字照样准；
* `app/ios/Runner/RestActivityBridge.swift` + `app/lib/features/workout/rest_activity.dart`：
  MethodChannel（`lianleme/rest_activity`，四个方法：start / end / activeCount）。
  **业务逻辑仍在 Dart** —— 休息状态只有一份真相（`workout_controller` 的 `_restEndsAtMs`）；
* **最低系统 iOS 16.2**（`ActivityContent` 是 16.2 才有的；16.1 只有会吃弃用警告的旧 API）；
  低于它、以及 Android 上，桥是**静默 no-op**；
* `NSSupportsLiveActivities = true` 已加进 `Runner/Info.plist`。

**顺手修掉一个真 bug**（这条比功能本身重要）：`workout_controller` 的休息倒计时原来是
"每秒减一"，而 **App 被系统挂起时 Dart 定时器不走** —— 回来之后剩余时间会把挂起那段白送掉，
而锁屏上系统按结束时刻走的倒计时是准的，**同一个事实在两个界面上对不上**。
现在每跳都从 `_restEndsAtMs` 重算。回归测试见 `app/test/rest_activity_test.dart`
（**撤掉修复会红**：`Actual: <59>`）。

### ⚠️ 验证到了哪一步、没验到什么

| 已验（自动） | 手段 |
|---|---|
| 记一组 → 系统里**真的开出 1 条** Live Activity；跳过休息 → **撤下** | `app/integration_test/rest_activity_e2e_test.dart`（模拟器上跑真实 App） |
| 扩展**真的在产物里**、扩展点/包名/`NSSupportsLiveActivities` 都对 | `tool/check-ios-app.mjs` 第 ⑪ 条（含 4 条负向自检） |
| 什么时候该开、什么时候该撤、挂起后剩余时间准不准 | `app/test/rest_activity_test.dart`（8 条） |

* **锁屏上那行字长什么样** —— ✅ **2026-10-04 在真机上验收了**：iPhone 17 Pro（iOS 27.2）装了 v1.42.0 的 dev 包（**免费 Apple ID / Personal Team**，路径见 `docs/ios-free-provisioning-guide.md`），记一组后锁屏出现 `组间休息 1:32 · 杠铃卧推 · 下一组 40 kg × 8 · 第 2/3 组`，**倒计时在自己走**（证据图 `docs/images/legacy-5tab/v142-live-activity-lockscreen.png`）。排版与设计一致：左边是标号+大号倒计时，右边是动作名/下一组/组序 |

⚠️ **为什么之前在模拟器上验不了**：这台机器的 Xcode 是精简安装，**没有 `Simulator.app`**，
所以锁不了屏（`simctl` 也没有 lock 命令，`simctl io screenshot` 里连灵动岛本身都不渲染）。
**真机这条路走通了** —— 而且**不需要付费开发者账号**：免费档能签 widget 扩展（实测），
见 `tool/ios-device-run.sh` 与那份指南里的实测结论。

### ② 本地提醒 —— ✅ **已实现**（2026-10-04）

* **不引通知插件，自己写两个平台的原生**（理由见 `docs/tech-decisions.md` 那一行）：
  Android 用 `AlarmManager.setAndAllowWhileIdle` + `ReminderReceiver`（**非精确**闹钟，
  因此不需要 `SCHEDULE_EXACT_ALARM` 那个特殊权限），iOS 用 `UNCalendarNotificationTrigger`；
* 通道 `lianleme/reminder`（isAllowed / requestPermission / schedule / cancel / scheduledAtMs），
  Dart 侧 `app/lib/features/profile/reminder_bridge.dart`；
* **排程时刻由 Dart 算**（`reminder.dart` 的 `nextReminderAtMs`，纯函数 + 6 条测试）：
  "到点了还没练就提醒一次；练过了顺延到明天" —— 两个平台各算一遍时间迟早会分叉；
* 新表 `reminder_setting`（**v17** 起：enabled + minutes_of_day。⭐ 当前库版本 **v18**，加的是埋点表那一列 `legacy_purged_at`，与本表无关）。**刻意不塞 `user_profile`**：
  那张表每个 setter 都要把整行带回来，塞进去就会被"改显示单位"顺手抹掉；
* 设置页「我 → 偏好设置 → 训练提醒」：开关 + 时间。**打开时才向系统要权限**，
  被拒时开关**弹回去**并说清去哪里开（`app/test/reminder_screen_test.dart` 钉着）；
* 合规面同步四处：`privacy-facts.json`（权限 + `localNotifications` 块）、中英政策 §四、
  商店表单（`check-store-forms` 过）、应用内收集清单（生成物已重出）。

**验证**（2026-10-04 · Redmi `flourite` / Android 16）：

| 验到了什么 | 怎么验的 |
|---|---|
| 打开开关 → 系统权限被授予 | `dumpsys package … POST_NOTIFICATIONS: granted=true, flags=USER_SET` |
| 提醒真的排进了系统 | `dumpsys alarm`：`RTC_WAKEUP … com.sdknwdtvpv.lianleme/.ReminderReceiver`，`origWhen` = 选的那个钟点 |
| 改时间会**撤销旧的那条** | 旧闹钟在 `dumpsys alarm` 的取消历史里记为 `alarm_cancelled` |
| 到点**真的弹出来** | `dumpsys notification`：`NotificationRecord(pkg=… id=4702 channel=lianleme_training_reminder …)`，`vis=PUBLIC`。第一次（13:56 那条）**晚了 2 分 26 秒**；第二次（14:13 那条）在**深度休眠里被系统压住**，直到唤醒手机那一刻才补发 —— 这正是"非精确闹钟 + Doze"的真实行为：**你拿起手机时它就在那儿**，但别指望它在休眠中精确到分钟 |
| ⚠️ 锁屏上**亲眼看到**那一张 | **没拍到**：这台 MIUI 的锁屏**不渲染第三方 App 的通知**（系统那条「USB 调试」显示，我们那条不显示）。已排查过不是我们这边的问题：`lock_screen_show_notifications=1`、`lock_screen_allow_private_notifications=1`、`appops POST_NOTIFICATION: allow`、通知本身 `vis=PUBLIC`、渠道 `mLockscreenVisibility=-1000`（不覆盖）。结论：**ROM 行为**，要在真机上看到得去 MIUI 的「设置 → 通知 → 锁屏通知」里放开这个 App |
| ⚠️ **一处只有真机才发现的问题** | 通知默认是 `VISIBILITY_PRIVATE`，**安全锁屏下整条都不显示**（真机上"锁屏只有系统那条通知"就是这么来的）。而"提醒"的全部价值就是用户不打开 App 也看得见 —— 已显式改成 `VISIBILITY_PUBLIC` 并重新出包重装 |
| 关掉开关会撤销 | 代码路径 + `app/test/reminder_test.dart`（服务那三条）；真机上"关掉之后系统里没有闹钟"这一次没单独截屏 |

**2026-10-04 iPhone 上的两条反馈 → v1.42.1 当天修**（这一节是"真机才知道"的又一次印证）：

| 反馈 | 真实原因 | 改法 |
|---|---|---|
| "设置时间太难用、填写根本用不了" | Material 的 `showTimePicker` 表盘要一格格转，切"输入模式"后**键盘挡住对话框下半截**（截图为证） | 换成**闹钟式双滚轮**（`CupertinoPicker` × 2）。⚠️ 顺手抓到一个**会静默失效的 bug**：`looping` 的 picker 返回值**不取模**，拨到 33 时 → 33×60 分钟越界 → 排程返回 null → **提醒永远不响且不报错**。现在取模 + `save()` 对越界值当场抛错 |
| "设了闹钟但没响" | **行为是对的**：设的 17:58 确认时已过、且当天记过一组 → 规则把时间顺延到**明天**。问题在**界面一个字都没说** | 开关下面多一行「下次提醒：今天/明天 xx:xx（为什么）」—— 由纯函数 `reminderHint()` 算，4 条测试盯着 |
