# 练了么 · App Store 上架材料（草稿 + 你必须补的部分）

> 与 `docs/store-listing.md`（国内安卓 / Google Play 那套表单）配套。
> 两份的**结构像、表单不一样**：Play 填"数据安全表单"，App Store 填 **App Privacy 隐私标签**
> 外加出口合规与审核备注。国内商店还要软著 / 备案，这里不需要。
>
> ⚠️ **和 Play 一样，先确认要发布那个包配了哪些地址** —— 这决定了隐私标签怎么填：
> ```bash
> grep -n "fromEnvironment" app/lib/main.dart app/lib/backup/backup_config.dart   # 两个默认值都该是空串
> grep -n enabledInDistributedBuild docs/privacy-facts.json                      # 云备份那一格
> # 打包后仍会带这两个 key，可以直接翻包核：
> unzip -p <你的.ipa或Runner.app>/Runner | strings | grep -c LIANLEME_BACKUP_URL
> unzip -p <你的.ipa或Runner.app>/Runner | strings | grep -c LIANLEME_BACKUP_DISCLOSED   # 两个都在才算配了
> ```
> * **都没配**（当前发布的包就是这种）→ 用 **变体 A：Data Not Collected**
> * **任一个配了** → 必须用 **变体 B**，并用英文政策（`docs/privacy-policy.en.md`）逐条对上

---

## 一、基本信息

| 字段 | 值 |
|---|---|
| 应用名称（≤30） | **练了么** |
| 副标题（≤30） | **一次点击记一组** |
| Bundle ID | **`com.sdknwdtvpv.lianleme`**（与安卓一致；上架后不能改） |
| 版本号 | 以 `app/pubspec.yaml` 为准（Flutter 会写进 `CFBundleShortVersionString` / `CFBundleVersion`） |
| 主分类 | **健康健美（Health & Fitness）** |
| 次分类 | 无（不选，避免额外的内容门槛） |
| 年龄分级 | **4+**（无暴力/成人/赌博/用户生成内容；分享卡是本地生成的图片，不经我们的服务） |
| 价格 | 免费（一期无内购 —— S14 已明确砍掉） |
| 语言 | 简体中文（`zh-Hans`）；**商店文案只备中文**，英文只用于隐私政策 |
| 支持 URL | ⬜ **你填**（可以先用仓库的 Issues 页或一个静态页） |
| 隐私政策 URL | ⬜ **你填**（必须公网可访问；`store-assets/privacy/index.html` 就是要放上去的页面） |
| 开发者名称 | ⬜ **你填**（个人主体写姓名，公司写公司名） |
| 联系邮箱 | ⬜ **你填** |

## 二、文案草稿（可直接粘贴）

**副标题**：`一次点击记一组`

**宣传文本（Promotional Text，≤170，可随时改）**：
> 把"记一组"从 4 次点击压到 1 次：首页按一下直接开练，重量和次数它替你算好。

**描述**：
> 练了么是一个**离线可用**的力量训练记录工具。
>
> · **一次点击记一组**：首页按一下直接进训练，下次的重量与次数已经替你填好
> · **它会替你算**：按你上次的成绩给出下一组的重量/次数，连续几次不行就自动减量
> · **完全离线**：健身房没信号也能记；没有账号、没有广告、没有推送
> · **数据在你手上**：记录只存在这台设备上，随时导出成文件；换手机可以导入
> · **351 个动作**：每个都有做法说明与常见错误，还能自己加动作
>
> 关于云备份：代码里已经写好（端到端加密、**默认关闭**），但它需要一台服务器；
> **当前发布的版本没有配服务器地址，因此界面上不会出现这个入口**，
> 你的数据不会被上传到任何地方。

**关键词（≤100 字符，逗号分隔，不要重复应用名）**：
`力量训练,健身记录,举铁,深蹲,卧推,硬拉,训练计划,增肌,健身日志,一组,渐进超负荷,离线`

## 三、App Privacy 隐私标签

### 变体 A：当前发布的包（两个地址都没配）→ **Data Not Collected**

Apple 对 "collect" 的定义是"把数据传出设备、且你能在实时服务之外访问它"
（[Apple 文档](https://developer.apple.com/app-store/app-privacy-details/)）。
当前包里：埋点通道是 `_NullTransport`（永远失败，事件只留在本机 outbox），
云备份入口不存在。**没有数据离开设备 → 选 "Data Not Collected"。**

这是本项目最硬的那句卖点，也是**可以自证**的：`docs/privacy-policy.md` 附录 B 给了命令。

### 变体 B：配了地址的包 → 按下表填

| Apple 类别 | 是否收集 | 用途 | 是否与身份关联 | 是否用于追踪 |
|---|---|---|---|---|
| **Identifiers → Device ID** | 是 | Analytics | 否（匿名随机 id，无账号） | **否** |
| **Usage Data → Product Interaction** | 是 | Analytics | 否 | **否** |
| **Health & Fitness → Fitness** | 是 | Analytics | 否 | **否** |
| **User Content → Other User Content** | ⚠️ 见下 | Analytics | 否 | **否** |

三点必须写清楚，否则这张表会填错：

1. **训练明细会随埋点出去**：`set_logged` 里带 `weight_kg` / `reps`（这是产品指标的核心），
   所以"健康与健身"和"用户内容"两栏都不能空着。**体重数值不发**（只发
   `has_weight` 这类布尔值，`docs/privacy-facts.json` 的 `neverCollected` 里写着）。
2. **云备份是端到端加密的**：服务端只有密文与 `account_id`、字节数、时间，
   **拿不到明文**。Apple 的定义里"你无法访问的数据不算收集"，
   所以理应按"不收集内容"填 —— 但这一条**建议先跟法务/Apple 文档确认**，
   它取决于"无法访问"的严格解释。无论如何，`account_id` 与备份的**存在与否**要如实披露。
3. **没有追踪**：没有广告 SDK、没有 IDFA、不做跨 App 关联 → "Used for Tracking" 全部选**否**，
   因此**不需要** App Tracking Transparency 弹窗。

## 四、截图与素材

| 项 | 规格 | 状态 |
|---|---|---|
| iPhone 6.9"/6.7" | 1290×2796 或 1320×2868 | ⬜ 待模拟器（`integration_test/screenshots_test.dart` 出图） |
| iPhone 6.5" | 1242×2688 | ⬜ 同上 |
| iPhone 5.5" | 1242×2208 | ⬜ 同上 |
| iPad 13" | 2064×2752 | ⬜ **取决于是否声明支持 iPad**（见 `docs/release-admin.md` §二之四 的待拍板项） |
| App 图标 | 1024×1024，**不带透明** | ✅ 已有（`tool/gen-icons.py` 出，`tool/asset-check.mjs` 守着） |

> ⚠️ **安卓那两套都不能直接拿来用**：Apple 按设备档位要**精确像素**（6.9"/6.7"、6.5"、5.5"），
> 而我们现在只有 1080×2400（20:9，国内商店）与 1080×1920（9:16，Play）两套 ——
> **两套都不是 Apple 要的尺寸**。等 Xcode + 模拟器跑通后，按档位各出一套
> （`integration_test/screenshots_test.dart` 是同一份脚本，iPhone 模拟器的逻辑分辨率是多少、
> 抓出来就是多少）。
| 启动屏 | 由 `LaunchScreen.storyboard` 提供，无需单独素材 | ✅ 已有（深色 + volt「练」） |

截图里那句"数据只在你手机上"属于**变体 A** 的措辞 —— 换变体时截图说明也要改
（`docs/store-listing.md` 末尾同样提醒过一次）。

## 五、审核备注（Review Notes，给审核员看的）

> 这个 App 不需要登录，也没有账号系统。
>
> · 相册权限（`NSPhotoLibraryAddUsageDescription`）只用于"把训练分享卡存进相册"，
>   是**仅新增**权限，我们**不读取**用户的任何照片或文件。触发路径：
>   训练结束 → 总结页 → 分享卡 → 存到相册。
> · 使用统计开关默认打开（「我」→ 帮助改进产品），但**当前发布的版本没有配上报地址，
>   因此不会发送任何数据**；关掉它不影响任何功能。
> · **云备份在当前版本不可用**（需要服务器地址，编译期决定），界面上不会出现入口；
>   若你在审核中看到相关代码，那是为后续版本准备的，默认关闭。
> · 无内购、无广告、无第三方登录。

## 六、你必须补的（与安卓那份共用同一批外部依赖）

| 项 | 谁 | 说明 |
|---|---|---|
| Apple Developer 账号 | 你 | 个人 ¥688/年。上架与真机调试都需要；**模拟器不需要** |
| Xcode（App Store，约 20G，只能装 `/Applications`） | 你 | 见 `docs/release-admin.md` §二之四 |
| **CocoaPods** | 你（或装好 Xcode 后我来） | ⚠️ **这台机器上没有**，而 `share_plus` / `gal` 都是插件 —— 没有它 iOS 构建必然失败（`flutter doctor` 原文：*Without CocoaPods, plugins will not work on iOS or macOS*）。本机也没有 Homebrew，两条路见 `docs/release-admin.md` §二之四 |
| 支持 URL / 隐私政策 URL | 你 | 隐私政策页面已生成在 `store-assets/privacy/`，需要放上公网 |
| 开发者名称 / 联系邮箱 | 你 | 商店与隐私政策里要一致 |
