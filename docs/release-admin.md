# 练了么 · 上架前的**行政前置**（软著 / App 备案 / 隐私政策 URL / 商店材料）

> 这份文件回答一个问题：**"技术上已经能出包了，为什么还不能上架？"**
> 答案是四件与代码无关的事。它们**按周计**，所以必须最早启动 ——
> 代码可以边等边改，行政流程不能。
>
> 事实性内容标注了来源与**核实日期（2026-09-29）**；政策类规定会变，
> 办理前请以官方渠道与目标商店的最新要求为准。

---

## 一、现状：我们有什么、缺什么

| 项 | 状态 | 说明 |
|---|---|---|
| 可安装的 release 包 | ✅ | `app/build/apk/lianleme-v1.12.0-release.apk`（debug 签名，仅供自测） |
| 正式签名接线 | ✅ **已验证** | 配了 `key.properties` 就用正式密钥；缺失时**硬失败**（见 `docs/release-checklist.md` §2） |
| 隐私政策文本 | 🟡 **草案** | `docs/privacy-policy.md`（+ 英文版）与代码**可对账**（`tool/privacy-audit.mjs` 已进门禁）；**未经法务审核** |
| 隐私政策**公网 URL** | 🟡 | 页面已生成并入库（见第四节）；**只差你选托管方式** |
| 软件著作权登记（软著） | 🟡 | 材料已起草（说明书 + 申请表 + 源代码 + 4 张截图）；差你的身份信息（见第三节） |
| App 备案 | ❌ | **小米自 2024-11-01 起强制**（见第二节） |
| 商店材料（图标/截图/描述） | 🟡 | **图标已做**；**截图 4 张已生成**（一条命令重跑，见 [`screenshots.md`](screenshots.md)）；差文案定稿 |
| 真机验收 | 🟡 | 开发者在真机上走过关键路径；**熟人短测（半天，定 `tap_count` 门槛）与"带手机去健身房练一次"未做**（`docs/usability-test-kit.md` §A）。正式 5 人测试**建议做、不卡上架** |

---

## 二、App 备案（**最硬的一条，先起**）

### 备案「苹果平台」包信息要填的三个值（2026-10-05）

腾讯云 APP 备案的「APP 特征信息 → **苹果平台** → 包信息」要 **Bundle ID / 公钥 / 签名MD5值**：

| 字段 | 值 |
|---|---|
| Bundle ID | `com.sdknwdtvpv.lianleme` |
| 签名MD5值 | **`9E04AFB3B662A8F6C6C518A066513328AC386DA9`** |
| 公钥（16 进制） | 见下面那个代码块（可直接复制） |


**公钥**（16 进制，直接复制；来源：钥匙串里的 `Apple Development` 证书）：

```text
30820122300d06092a864886f70d01010105000382010f003082010a0282010100e78308d0b02e67274f1f1e60b370724d4b58fbf60d85875409e0bdaf0931a304d8672b504bc9c2cf65a0db05f9ca61d9244a45ab7e3586b26fa674c87b71c1a294242d3aef539a79d1797c767ea633ce9d4ab2f7dd7e46f87ea1aec26cd1b153cf688ad2c32c97c30dd9d4f476a4bc7e4b550a17c6bde489c8ff4f49605e0dd4487953f15700560ef27a8e0b66bbef105c855898176428bc22bc47133c34574758cbd62820732483f1d44ff8307b28face0f5afc2456d29f40a8c8b4e4d1dd48d0d63af3ef78b4a998d02864bf74061b97f98cfbc515f24dbfdbc0042c8ce75a3f530940cd9c07ca542f62045512abf4cfc009c303cb58d2446eded40f0ed35b0203010001
```

> ⚠️ **这一栏最容易填错的地方**：名字叫「签名MD5值」，但按腾讯云
> [243/97789](https://cloud.tencent.cn/document/product/243/97789) 与阿里云
> [填写App特征信息](https://help.aliyun.com/zh/icp-filing/basic-icp-service/user-guide/fill-in-app-feature-information)
> 两份官方规范：**安卓填证书的 MD5，苹果填证书的 SHA-1**（都以 16 进制）。
> **iOS 填成 MD5 会被驳回。**

⚠️ **一个需要知道的边界**：上面那两个值取自**现有的苹果开发者证书**（免费 Personal Team 的
`Apple Development: 919500973@qq.com (FA5LCQQVX8)`，有效期到 2027-10-04）——
因为免费档拿不到 `Apple Distribution` 证书。备案规范说的是"登录开发者账号 → 证书 → 下载对应 App 证书"，
严格讲正式上架用的会是**分发证书**。两条路：
① **先用开发证书提交**（备案是长杆，先起跑；接入商一般只收集信息不校验证书类型），
   等拿到付费账号、生成分发证书后，若被要求再走**备案变更**；
② 先付费买账号、生成分发证书再填（一次到位，但备案往后推）。

**怎么复算**（macOS，证书在钥匙串里）：

```bash
security find-certificate -c "Apple Development" -p > /tmp/dev.pem
openssl x509 -in /tmp/dev.pem -noout -fingerprint -sha1      # → 签名MD5值那一栏（iOS 填 SHA-1）
openssl x509 -in /tmp/dev.pem -pubkey -noout | openssl pkey -pubin -outform DER | xxd -p   # → 公钥
```

### 密钥怎么备份（2026-10-05 实际跑过一遍）

**要备份的只有两样，但它们是"丢了就永久锁死"的那种**：
`app/android/upload-keystore.p12`（签名本身，**故意不入库**）+ **keystore 密码**（脚本把 key 密码设成与它相同）。
`key.properties` 里是**明文密码**，它只是给 gradle 读的便利文件 —— 丢了可以用密码重建，不必单独备份。

**① 做成加密磁盘映像**（已实测：产物是 AES-256 加密的，`hdiutil imageinfo` 里能看到 `CEncryptedEncoding`）：

```bash
cd app/android
STAGE="$(mktemp -d)/练了么-签名备份-$(date +%Y%m%d)"; mkdir -p "$STAGE"
cp upload-keystore.p12 key.properties "$STAGE/"
hdiutil create -encryption AES-256 -fs HFS+ -volname "lianleme-signing-backup" \
  -srcfolder "$STAGE" "$HOME/Desktop/lianleme-signing-backup-$(date +%Y%m%d).dmg"
rm -rf "$(dirname "$STAGE")"     # 清掉未加密的中间目录
```

⚠️ **仍用 `hdiutil`，不要换苹果推荐的 `diskutil image create from --encrypt`**（2026-10-05 实测）：
新写法确实也会加密（不给口令挂不上），但**我用同一个口令挂不回去**（`认证错误`）——
没验通之前不要把它当成替代品写进流程。`hdiutil` 那句 `is deprecated` 只是提醒，不影响结果。

> 中间目录放 `$(mktemp -d)` 而不是桌面：桌面可能被 iCloud 同步走**未加密**的那一份。

**② 校验备份可用**（这一步最容易省，也最容易自欺 —— "备份了但文件坏了/密码记错"）：

```bash
MP=$(hdiutil attach -nobrowse "$HOME/Desktop/lianleme-signing-backup-XXXX.dmg" | tail -1 | sed 's/.*\/Volumes/\/Volumes/')
keytool -list -v -keystore "$MP/upload-keystore.p12" | grep -E "别名|所有者"   # 会交互式问密码
diskutil eject "$MP"
```

**看到 `所有者: CN=李松, C=CN` 才算这份备份可用。**（故意不写 `-storepass`，让它交互式问 —— 密码不进 shell 历史。）

**③ 存三个地方**：密码管理器（密码 + 备注别名/包名）· **两块离线介质**（U 盘/移动硬盘，放不同地方）·
**一张手写的纸**（密码，放抽屉/保险柜 —— 密码管理器忘了主密码、介质坏了时，纸是最后一道）。

> ⚠️ 红线：不进 git（`.gitignore` 已挡）· **不发微信/网盘/云相册**（那是主动泄露，不是备份）·
> 不把密码写进任何仓库文件与对话。

### 备案「包信息」要填的三个值（2026-10-05 定稿，可直接照抄）

腾讯云 APP 备案的「APP 特征信息 → 安卓平台 → 包信息」要 **App 包名 / 公钥 / 签名MD5值**：

| 字段 | 值 |
|---|---|
| App 包名 | `com.sdknwdtvpv.lianleme` |
| 签名 MD5 | `2227a0109f73e388ce4986033b39fd85` |
| 公钥 | 见 `app/android/upload-keystore.p12` 导出（下面有命令） |

**为什么必须是这把密钥的**：备案里的签名要与**上架包**一致。2026-10-05 之前仓库里的包是
`CN=Android Debug` 的调试签名（MD5 `066e15f7…`），**用那个值去备案，等换成正式密钥出包就会对不上**。

**怎么复算**（三条命令，都不需要把密码写进 shell 历史）：

```bash
# 签名 MD5 / SHA-1 / SHA-256（从已签名产物，与备案口径一致）
apksigner verify --print-certs dist/练了么-v1.52.0.apk

# 公钥（base64 单行）
keytool -exportcert -rfc -alias upload -keystore app/android/upload-keystore.p12 \
  | openssl x509 -pubkey -noout | sed '1d;$d' | tr -d '\n'

# 证书指纹（独立复算，应为 MD5 2227a010…）
keytool -exportcert -rfc -alias upload -keystore app/android/upload-keystore.p12 \
  | openssl x509 -noout -fingerprint -md5
```

> ⚠️ **这三个值是公开信息**（它们在包里、也在备案页上），可以进仓库；
> **keystore 密码不是** —— 它只在你的密码管理器里，仓库里任何文件都不该出现它。



**依据**：《工业和信息化部关于开展移动互联网应用程序备案工作的通知》。
小米应用商店的标准修订于 2024-10-09 公示、**2024-11-01 正式生效**：
> 应用发布上架时，需按相关规定履行 APP 备案手续，且同一 APP，其 **APP 主办单位、APP 名称、
> APP 包名**均要与备案系统保持一致。未履行备案手续的，不得从事 APP 互联网信息服务。
> —— [小米应用商店：APP 备案标准](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1983)（核实于 2026-09-29）

**对我们意味着什么**：

- 备案是**主体**（个人或公司）行为，不是应用内的事 —— 需要你的实名信息/企业资质
- 备案信息里的 **名称与包名** 必须与商店里的一致。我们的是：
  - 包名 **`com.sdknwdtvpv.lianleme`**（真源：`app/android/app/build.gradle.kts` 的 `applicationId`；
    仓库名是 `sdknwdtvpv-sys`，拼写里是 **vpv** 不是 vp —— 提交前再核一次）
  - 应用名「练了么」
  - ⚠️ **一旦备案，包名就不能再改**（改了要重新备案）。所以先定包名、再备案
- 备案需要一个**可访问的服务**：本项目当前**没有后端**（`_NullTransport` / `InMemorySyncQueue`），
  但备案通常要求填写域名/服务器信息 —— 这一步需要你决定"有没有服务器"，
  没有的话以备案系统的"无服务器"情形与接入商指引为准
- 流程一般通过**接入服务商**（如阿里云/腾讯云备案系统）提交，
  参考：[APP 备案全流程解析（腾讯云）](https://developer.cloud.tencent.cn/article/2516021)
  —— 周期以备案系统与接入商的实际进度为准（请勿以本文估计为准）

---

## 二之三、核实过的硬要求（2026-09-30 逐条对过官方文档）

这几条都不是「听说」，出处写在每行后面 —— 前两轮正是靠这种核对发现了
「鉴别材料要 PDF 而不是 txt」与「软件全称必须与商店名称一致」两个坑。

| 要求 | 出处 | 对项目的影响 |
|---|---|---|
| **软著是所有应用上架的必备资质**，且「办理中不能先上架」 | 小米[应用资质FAQ](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2251) Q5 | 软著在**关键路径**上：30–75 工作日，别的事都得等它 |
| **APP 备案也是所有应用必备**；新应用自 2023-09-01 起须备案后才可上架 | 同上 + [备案指引](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1739) | 与软著并行办 |
| **软件名称 / 应用名称 / APP 备案名称三者必须一致** | [名称基本原则](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1796) | 三处统一用「练了么」；填错要重办 |
| **应用内需在显著位置展示 APP 备案编号，且编号可点击跳转备案系统** | 同上（第四节） | **这是一个 app 侧改动**，见下方待做 |
| 备案时限：省级通信管理局 **20 个工作日**；软著：自受理起 **60 日内**审查完成 | 同上 | 时间账：软著 30–75 工作日 ≫ 备案 20 工作日 |
| 应用名称每自然年**只能改 2 次**，更名需先改软著与备案 | 同上（第五节） | 名字现在就要定死 |
| 备案走**接入商**（华为云 / 阿里云 / 腾讯云）代办 | 同上（第四节） | 需要一个接入商账号；**本 App 没有服务器**，接入信息怎么填待定 |

### 待你确认的一个技术问题：没有服务器，备案的「接入信息」怎么填

备案要填「APP 接入信息」（服务地址 / 域名）。而本项目的设计是**完全离线**：
训练数据只在手机本地，上报通道默认没有地址（`_NullTransport`）。可能的走法：

1. 按「无服务器」申报（以接入商口径为准）；
2. 为备案买一个最小的云资源，作为接入信息；
3. 直接问接入商客服。

**这一条我没有把握，所以只列出来、不替你猜。** 建议在开工软著之前先问一次接入商。

### 待做（app 侧，等真机/模拟器可用 + 拿到备案号）

| 事项 | 说明 |
|---|---|
| 应用内展示 APP 备案编号 | 建议位置：「我」页的隐私/关于区块；编号必须**可点击跳转到备案系统**。拿到备案号后实现，并同步隐私政策 |

## 二之四、iOS 侧（「双端先上」的欠账）

**已与安卓对齐（2026-09-30，都不需要 Xcode 就能做）**：

| 项 | 状态 |
|---|---|
| bundle id | ✅ `com.sdknwdtvpv.lianleme`（与安卓一致，已不是模板的 `com.example.*`） |
| 应用图标 | ✅ 15 个 PNG 覆盖 **19 个槽位**（`iphone` 9 + `ipad` 9 + `ios-marketing` 1），满幅不透明、不切圆角（iOS 要求），由 `tool/gen-icons.py` 与安卓同源生成。**同一个 PNG 会被 iphone 和 ipad 两个 idiom 共用**，所以数文件会少算 |
| 启动屏 | ✅ 与 App 同色 `#0B0B0D` + 居中 volt「练」（原来是模板纯白，会白闪） |
| 显示名 | ✅ 「练了么」（原来是模板的 `Lianleme`） |
| 存相册权限 | ✅ `NSPhotoLibraryAddUsageDescription`（**只申请"仅新增"**，不读相册）。**故意不要** `NSPhotoLibraryUsageDescription`（读相册）|
| 相簿 | ⚠️ **与安卓有意不同**：iOS 上不建「练了么」相簿，分享卡落进「最近项目」。原因见下（`shareAlbumNameFor`）|
| 提审合规 | ✅ `ITSAppUsesNonExemptEncryption=false`；`UIUserInterfaceStyle=Dark` |
| 依赖的 iOS 可用性 | ✅ `tool/ios-deps.mjs`。**2026-09-30 补了原版漏掉的一类**：原版只读 pubspec 的 `plugin: platforms:`，于是"没有 plugin 段"被当成"纯 Dart、两端都能用" —— 可 `package:sqlite3` 3.x 恰恰没有 plugin 段，它把原生库交给 `hook/build.dart` **现编/现下**（Dart hooks / code assets）。它就是我们**唯一的数据库引擎**（经 `drift_flutter`），而且它连直接依赖都不是（传递依赖），原版守卫对它完全瞎。现在闭包里所有 hook 包都要有 iOS 证据，`sqlite3` 与 `objective_c` 各有一条 ✓。⚠️ 顺带查清：iOS 上 sqlite3 是**从源码编译**（hook 里带 `-install_name @rpath/libsqlite3.dylib` 与 `-headerpad_max_install_names`），所以要 Xcode 的 clang —— 这也解释了为什么装 Xcode 之前 iOS 一行都跑不了 |
| 守卫 | ✅ `tool/asset-check.mjs` 已覆盖 iOS：图标不是模板图、无透明、显示名、权限键、启动屏不是纯白、bundle id 不是模板的。**2026-09-30 补上的洞**：旧版守卫只遍历磁盘上的 PNG，**从没打开过 `Contents.json`**，而且只对 1024 那一张做过尺寸校验 —— 现在改成清单与磁盘**双向对账**：① 清单里写了但磁盘没有（对应机型缺图标）② 磁盘上有但清单没引用（那张 PNG 永远不进包）③ 声明尺寸×倍率 ≠ PNG 真实像素（图标发虚）④ 19 个必需槽位缺一。四条都负向验证过（临时改名 / 塞孤儿图 / 29px 顶替 180px / 删 ios-marketing 槽位）—— 各自都能红，还原后逐字节相同 |

**Apple 隐私清单（PrivacyInfo.xcprivacy）—— 2026-09-30 查清**：苹果要求"用到
required-reason API 就要在清单里声明理由"，并且**对着二进制扫**（邮件 ITMS-91053/91054）。
安卓侧完全看不到这件事。把依赖闭包扫了一遍，有 Apple 原生源码（`.swift`/`.m`/`.mm`）的
**非 dev** 包只有三个：

| 包 | Apple 原生源文件 | 自带清单？ |
|---|---|---|
| `share_plus`（直接依赖） | 4 | ✅ |
| `gal`（直接依赖） | 2 | ✅ |
| `objective_c`（**传递**：`drift_flutter → path_provider → path_provider_foundation → objective_c`） | 6 | ❌ **没有** |

`objective_c` 是 ObjC 运行时桥（`src/*.m`，经 `hook/build.dart` 编进包），上游确实不带清单。
它只碰 objc 运行时，不碰 UserDefaults / 文件时间戳 / 磁盘空间 / 开机时间这些 required-reason API ——
所以**大概率不需要声明**，但"大概率"不是证据。这条已经写成 `tool/ios-deps.mjs` 里的
**显式例外**（带着理由），并且在门禁里守着：一旦上游补了清单，例外会自己报"该删了"。

**✅ 2026-10-01 已定并做完**：app 自己那份清单**已经加上**，而且**在产物里验过**。

| 项 | 内容 |
|---|---|
| 文件 | `app/ios/Runner/PrivacyInfo.xcprivacy` |
| 怎么进包的 | 挂进 `project.pbxproj` 四处（FileReference + BuildFile + group + **Runner target 的 Copy Bundle Resources**）—— ⚠️ 第一次我挂到了 **RunnerTests** 的 Resources 阶段，包编得出来、但**清单根本没进去**；改到 Runner target 之后才在产物的 Runner.app 根目录里看到它 |
| 声明了什么 | `NSPrivacyTracking=false`、`NSPrivacyTrackingDomains=[]`、`NSPrivacyCollectedDataTypes=[]`（**当前发布版本**不外发数据）＋ 三类 required-reason API：`UserDefaults/CA92.1`、`FileTimestamp/C617.1`、`SystemBootTime/35F9.1`（每条的"为什么用得上"写在文件顶部的注释里） |
| 谁在守 | `tool/check-ios-app.mjs` 第 ⑩ 条：包里没有这份文件、或 `NSPrivacyTracking != false`、或一个原因码都没声明 → **判红**（两条负向用例：删掉文件、把追踪写成 true） |

**"上传后才需要决定"的那一件事，现在只剩这个**：如果 Apple 那封 ITMS 邮件
**点名了别的 API**（或多报了），**照报告增删这份清单里的条目** —— 判据从"猜测"变成了"照报告改"。

⚠️ **改这份清单时别忘了一处联动**：`NSPrivacyCollectedDataTypes = []` 对应的是
**变体 A（没配上报地址）**。一旦发布"配了上报地址"的包（变体 B），
这里与 App Privacy 标签（`docs/store-listing-ios.md` 的两个变体）必须**同时**改。

**2026-09-30 查出来的 iOS 专属缺陷（已修，v1.27.1）**：`saveToGallery()` 一直带着相簿名去存，
而 gal 建/找相簿要**读**相册（`.readWrite` 授权 = `NSPhotoLibraryUsageDescription`），
我们却只有 `.addOnly` —— **iOS 上「存相册」必然失败，而安卓一切正常、所有测试全绿**。
更糟的是它让政策里那句「只写入，从不读取你的相册」变成假话。
修法是**去掉 iOS 上做不到的那半件事**，而不是去申请读权限：
`shareAlbumNameFor(isIOS:)` 在 iOS 返回 `null`（不建相簿）。代价只是一个相簿分组。
`tool/asset-check.mjs` 里有一条**跨文件**守卫钉着这对互斥关系（没声明读权限就不许直接带相簿名），
三个分支都负向验证过。

**方向：手机锁竖屏（已做，v1.30.0）**。横屏实测（`wm size 2400x1080` 跑完整套截图脚本）：
首页 `today_screen.dart:46` 的 `Column` **`RenderFlex overflowed by 80 pixels`**，
还有一处 44 像素；现场能看到黄黑条纹、入口文字与底部导航重叠。既然没有横屏设计，
就明确只支持竖屏：安卓 `android:screenOrientation="portrait"`、
iOS 手机那份方向数组只留 Portrait。两端各有一条守卫钉着（缺一边 = 那一端转一下就坏）。

**iPad 支持：已拍板"只支持 iPhone"，`TARGETED_DEVICE_FAMILY = "1"`**（2026-09-30）。
决定依据是实测：把模拟器的分辨率与密度调到 iPad Pro 12.9 吋的规格
（`wm size 2048x2732` / `wm density 320`，约 4:3），跑完整套 11 步截图脚本：

| 项 | 结果 |
|---|---|
| 崩溃 / 布局溢出 | **0**（logcat 里 `overflowed` / `RenderFlex` 命中 0 次，11 步全过） |
| 观感 | **拉伸的手机布局**：大按钮变成通栏横条、内容靠左、大片空白 |
| 证据 | `docs/images/ipad-width-home.png`、`docs/images/ipad-width-workout.png` |

原来那个 `TARGETED_DEVICE_FAMILY = "1,2"` **能通过门禁**，但商店页会写「支持 iPad」，
而用户打开看到的是拉长的手机界面 —— 等于拿一个没验证过的承诺换一个标签。所以拍板：
**这一版只支持 iPhone**（`project.pbxproj` 三处都改成 `"1"`），并且把这条做成了**硬要求**：
`tool/check-ios-app.mjs` 现在看到产物里含 iPad（`UIDeviceFamily` 有 2）就**判红**
（在此之前只是提示）。等真的做了平板布局（两栏、更大的信息密度）再开 iPad ——
那时还要把这条判据改回去，并补 iPad 尺寸的截图。**iPad 13" 那档截图现在不需要了。**

**2026-09-30 更新（工具链状态变了）**：**Xcode 27.0 已经装好**
（`/Applications/Xcode.app`，`xcode-select` 已指向它）。现在卡住的只剩**许可证**：

* 许可证没接受时，`xcodebuild` / `xcrun` 一律被拒 —— 而且会**连带**
  `git`、`python3`、`flutter`、`dart` 一起挂（macOS 上 `/usr/bin/git` 与 `/usr/bin/python3`
  本身就是 xcrun 的壳）。`flutter test` 的原生资源构建也会去问 Apple SDK 路径
  （`objective_c` 的 hook 跑 `xcrun --show-sdk-path`），没许可证时它把那句错误信息当成了路径。
* 一条命令解决：**`sudo xcodebuild -license accept`**（装完第一次可顺手
  `sudo xcodebuild -runFirstLaunch`）。**这一步必须你来**（需要 sudo 密码）。

**在许可证接受之前，本机可以这样继续跑门禁与测试**（不是给 Xcode 开后门，而是绕开它去用
Command Line Tools —— 与 Xcode 装之前的状态等价）：把 `DEVELOPER_DIR` 固定成 CLT 的 `xcrun`
包一层、并直接调 `flutter_tools.snapshot` 与 `dart-sdk/bin/dart`。具体命令见
`docs/dev-environment.md` 的「Xcode 装了但许可证没接受时怎么办」。

**CocoaPods 不需要了（已查证，非推测）**：三条证据 —— ① `share_plus` 与 `gal` **都自带 `Package.swift`**；
② Flutter 已生成 `FlutterGeneratedPluginSwiftPackage`；③ **`app/ios/` 里没有 `Podfile`**，
`Runner.xcworkspace/contents.xcworkspacedata` 里对 Pods 的引用数是 **0**。
也就是说这个工程本来就是 **Swift Package Manager 路线**，`flutter doctor` 那句
"CocoaPods not installed" 是通用提示、与我们无关。
**仍然要在许可证接受后用一次真实构建做最终确认**（能编过即闭环）—— 结构上成立不代表编译器同意。

需要你：

1. 从 App Store 装 **Xcode**（约 20G，**只能装在 `/Applications`**，不能放 SSD）
   —— 装好后我做：模拟器跑通、用 integration_test 出 iOS 截图、逐屏差异走查
2. ~~装 **CocoaPods**~~ ✅ **不需要了**（同文件下一小节已查证，且 2026-09-30 的两次真实 iOS 构建
   都是**没有 CocoaPods** 编过的：模拟器包 183M、release 真机包 20.3M）。
   本机也**没有 Homebrew**，所以三条路：
   * `brew install cocoapods` —— 得先装 Homebrew（装到内置盘，约 1G）；
   * 系统自带的 Ruby 是 **2.6**（Apple 已不维护）→ `sudo gem install cocoapods`
     能用，但把依赖装进系统 Ruby；
   * 装一份自带 Ruby 3.x 到 SSD 再 `gem install`（最守"依赖都在 SSD"这条约定，也最费事）。
   **这一步需要你定用哪条路**（涉及装 Homebrew 或动系统 Ruby）；定好之后我来装并验证。
3. 注册 **Apple Developer 账号**（个人 ¥688/年）—— **「双端先上」就意味着这笔开销**，
   而且上架与真机调试都需要它（模拟器不需要）

## 二之四之一、第一次 iOS 构建会**改动几个受版本控制的文件**（先知道，别慌）

这一条是查出来的，不是猜的：Flutter 的 `cocoapods.dart` 里有个
`_addPodsDependencyToFlutterXcconfig`（`build` 时调用），**发现 xcconfig 里没有 Pods 那行就自己加**：

```
cocoapods.dart:307-310
  final include = '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.${mode}.xcconfig"';
  file.writeAsStringSync('$include\n$content', flush: true);
```

我们的 `ios/Flutter/{Debug,Release}.xcconfig` **现在只有** `#include "Generated.xcconfig"`，
所以第一次 `flutter build ios` / `pod install` 之后会变成：

| 文件 | 会发生什么 | 要不要提交 |
|---|---|---|
| `ios/Flutter/Debug.xcconfig`、`Release.xcconfig` | 被 Flutter 自动加一行 `#include? "Pods/…"`（`cocoapods.dart:303-310`） | **要**（不然下次构建又会被改一遍） |
| `ios/Flutter/AppFrameworkInfo.plist` | 被 Flutter 写入 `MinimumOSVersion`（`build_system/targets/ios.dart:742` 的 `_updateMinimumOSVersion`） | **要** |
| `ios/Podfile` | 由 `pod install` 新建 | **要**（团队/CI 都靠它复现依赖） |
| `ios/Podfile.lock` | 由 `pod install` 新建 | **要**（锁版本；不提交等于每次解析出不同版本） |
| `ios/Runner.xcworkspace/contents.xcworkspacedata` | `pod install` 会往工作区里加 `Pods/Pods.xcodeproj` 引用 | **要** |
| `ios/Pods/`、`Flutter/Generated.xcconfig`、`Flutter/ephemeral/` | 生成物 | **不要**（`ios/.gitignore` 已经忽略了） |

> 顺带核过两条**不会**发生的"惊喜"：① `IOSDeploymentTargetMigration` 只改**旧值**
> （8.0/9.0/11.0/12.0），我们的 `IPHONEOS_DEPLOYMENT_TARGET = 15.0` 与
> `AppFrameworkInfo.plist` 里根本没有这个键，所以它什么都不做；
> ② 我们的 `AppFrameworkInfo.plist` 与当前 Flutter 模板**逐字节同形**
> （模板这版确实不含 `MinimumOSVersion`，是构建时才写进去的）。

也就是说：**装好 Xcode 之后的第一次构建，会留下 6 个需要提交的改动**，
这是正常的、预期的。不写清楚的话，下一次 `git status` 会让人以为"谁动了工程文件"。

## 二之四之二、依赖的 iOS 可用性（静态核过，2026-09-30）

**结论：现在每个直接依赖都能在 iOS 上跑。** 判据是各包自己 pubspec 里的
`flutter: plugin: platforms:` 声明，由 `tool/ios-deps.mjs` 核（已进 `verify.sh`）：

| 依赖 | iOS 支持 | 依据 |
|---|---|---|
| `drift` / `drift_flutter` | ✅ | 纯 Dart 包（无 plugin 段） |
| `cryptography` | ✅ | 纯 Dart 包 —— 端到端加密那一层在 iOS 上不需要任何原生代码 |
| `share_plus` | ✅ | 声明 `ios`（拉起系统分享面板） |
| `gal` | ✅ | 声明 `ios`（存相册；iOS 侧用"仅新增"权限） |

**原生 SQLite 从哪来**（这条容易误会）：`sqlite3` 3.6.0 **自带各平台的预编译二进制**，
其中 iOS 是 `arm64`（真机）+ `arm64` / `x64`（模拟器）——见该包 README 的
"Supported platforms"。它通过 **hook（native assets）** 在构建时把库放进去，
所以**不需要单独的 `sqlite3_flutter_libs`**。
⚠️ 但 `drift_flutter` 至今**仍然传递依赖** `sqlite3_flutter_libs: ^0.6.0+eol`
（那个包现在只剩一个 Dart 壳、没有原生代码）—— 所以 pubspec 里那句"不要自己加它"
依然成立：它不是我们加的，也**不要**手动加。

**守卫**：`tool/ios-deps.mjs` 拦的是"顺手加一个只有 Android 实现的插件"这种事
（pub.dev 上大量 `xxx_android` 只有单平台）。它**负向验证过**
（把 `gal` 复制一份、删掉 `ios:` 声明 → 判红）。
⚠️ 它只能证明"根本不可能支持"的依赖进不来，**证明不了真的能编过** —— 那要 Xcode。

## 二之四之三、iOS 与安卓的差异清单

**静态核对**（现在就能确定）：

| 项 | 安卓 | iOS | 备注 |
|---|---|---|---|
| 显示名 | 练了么 | 练了么 | 与商店名一致（三处一致是硬要求） |
| 包标识 | `com.sdknwdtvpv.lianleme` | 同 | 上架后不能改 |
| 图标 / 启动屏 | 一套配方两端生成 | 同 | `tool/gen-icons.py` 出，`asset-check.mjs` 守着 |
| 相册权限 | `WRITE_EXTERNAL_STORAGE`（仅 API ≤29）；**Android 10+ 走 MediaStore 免权限** | `NSPhotoLibraryAddUsageDescription`（**仅新增**） | iOS 那边**更窄**：完全不读相册；两端**都验过**（见下方第 3 条） |
| 存相册的落点 | 建一个名为「练了么」的相册（`/sdcard/Pictures/练了么/`） | **不建相册**，直接进「最近项目」（`shareAlbumNameFor` 在 iOS 上返回 null） | 2026-09-30 两端**实拍**：安卓 `lianleme_20260930.png` 落在 `Pictures/练了么/`；iOS `IMG_0007.PNG` 落在相册根。iOS 不建相册是因为**建相册要读相册**，与"仅新增"的承诺冲突 |
| 其他权限 | INTERNET | 无（iOS 联网不需要声明） | |
| 最低系统 | `minSdk 24` | `IPHONEOS_DEPLOYMENT_TARGET = 15.0` | |
| 数据库 | `libsqlite3.so`（三 ABI，native assets） | sqlite3 预编译 `arm64` | 同一个 `sqlite3` 包，取库的方式不同 |
| 版本号 | `versionCode` / `versionName` | `CFBundleVersion` / `CFBundleShortVersionString` | 都由 pubspec 的 version 生成 |
| 出口合规 | 不涉及 | `ITSAppUsesNonExemptEncryption=false` | 已声明，免得每次提审都被问 |
| 商店表单 | 数据安全表单（Play）/ 各商店自有表单 | **App Privacy 隐私标签** | 见 `docs/store-listing-ios.md` |
| 设备族 | 手机（未锁方向） | **`TARGETED_DEVICE_FAMILY = "1"`（只支持 iPhone）** | 2026-09-30 拍板；产物核对里有硬要求（含 2 判红） |

**只有 Xcode 能给的答案（2026-09-30 逐条落地）**：

| # | 问题 | 现在的答案 | 证据 |
|---|---|---|---|
| 1 | 真的能编过吗 | ✅ 编过两次 | `flutter build ios --simulator` → 183M；`--release --no-codesign` → **20.3M / arm64 / 最低 iOS 15.0**；`tool/check-ios-app.mjs` 逐项核过 |
| 2 | 布局在 iOS 上长什么样 | ✅ 逐屏看过 | **13 张** App Store 截图（1320×2868，`store-assets/screenshots-ios/`）：首页、建议卡、选动作、训练屏、总结、进步、全部数据、我、身体数据、同意门、撤回入口都正常；汉字与字号正常，无溢出 |
| 3 | 分享面板与"存到相册"的真实行为（权限文案、被拒路径） | ✅ **iOS 两条权限路 + 安卓免权限那条，三条都走过** | 新增 `app/integration_test/share_card_gallery_test.dart`（宿主机预置 TCC / 安卓直接跑）：`revoke photos-add` → 先弹**说明目的**的框 → 「继续」→ 界面如实说「没有相册权限，没存成」且不崩；`grant photos-add` → **不再白问**（说明框不出现）→ 「已存进相册」，且**模拟器相册里真的多了一张卡**（`data/Media/DCIM/100APPLE/IMG_0007.PNG`，62 KB）。安卓（模拟器 API 36 / Android 16）：`LIANLEME_GALLERY_MODE=android` → **说明框不出现**（免权限就别白问）、「已存进相册」，图落在 `/sdcard/Pictures/练了么/lianleme_20260930.png`。⚠️ **系统分享面板本身**（选微信/存文件那一步）是系统 UI，自动化点不到 —— 那一步仍只能人工看 |
| 4 | 深色主题 + 启动屏的观感（有没有白闪） | 🟡 **部分** | 冷启动连拍 8 帧：**首帧就是启动屏本身**（深色卡片 + volt「练」，见下方截图描述），平均亮度 50.9 / 近白像素 0.1%，其后各帧 12.4（App 的深色界面）—— **没有偏白的帧**。⚠️ 采样间隔约 1 秒，**毫秒级白闪理论上仍可能漏过**；要彻底证明得录屏逐帧看 |
| 5 | 横屏 | ✅ 已锁竖屏 | v1.30.0 起两端都锁（曾经的欠账：横屏下首页 `RenderFlex overflowed by 80px`）；安卓侧守卫 + iOS 侧 `check-ios-app` 都在盯 |

> 第 3 条顺带验到一件与审核有关的事：**"申请权限前先说明目的"** 的逻辑在 iOS 上真的生效
> （已授权时不会白弹一次），而**被拒之后如实告知**而不是假装成功 —— 这正是小米 191 号文
> 与 OPPO 规范那类要求想看到的行为。

## 二之四之四、iPad：**已拍板只支持 iPhone**（2026-09-30）

`TARGETED_DEVICE_FAMILY` 是 Flutter 模板里给的默认值 `"1,2"`（iPhone + iPad 都支持）。
**已改成 `"1"`**：与"单手、在健身房站着用"这个定位一致，iPad 用户仍能在兼容模式
（放大显示）下用。理由很实在：**我们从没在 iPad 上看过任何一屏**，宣布"支持 iPad"
等于承诺一件没验证过的事；实测也只是把手机布局拉长（见上一节）。

配套的两件事都做了：① `docs/store-listing-ios.md` 的截图表里 **iPad 13" 那一档标成
"不需要"**；② `tool/check-ios-app.mjs` 里"产物含 iPad"从**提示**升级成**判红** ——
产物说的必须和商店页说的一致，改回去必须是有意的（改代码 + 改守卫，两处一起）。

**将来要开 iPad**：先做平板布局（两栏、更大的信息密度）、在 iPad 模拟器上逐屏走查
（大屏下 S4 那个 88pt 大按钮的位置、列表宽度、横屏布局），再补 iPad 尺寸截图，
最后把上面那条判据改回来。

**iOS 商店材料**：见 `docs/store-listing-ios.md`（与安卓那份组织方式一致，
含 App Privacy 标签的两个变体、截图规格、审核备注）。

## 二之五、应用内必须能读到隐私政策（小米的合规指引，2026-09-30 补）

**这条此前是缺的**：隐私政策只在仓库与商店页面里，**应用内一个字都没有**。
小米应用商店《隐私政策不合规的问题解析和修改指引》写得很直白：

> *"应用需要在**应用内**添加独立的隐私政策，且**尽量保证在四步操作之内**可以查看到"*；
> *"应用在应用内添加的独立的隐私政策**必须是可以正常打开和查看的状态**"*；
> 规则来源：国信办秘字〔2019〕191 号（同页还要求首次启动**主动弹窗**征求同意、
> 同意/拒绝按钮语义明确、**不得默认勾选**）。

现在做到了的：

| 项 | 状态 |
|---|---|
| 应用内独立的隐私政策 | ✅ 「我 → 隐私政策」＝**两次点击**（页面：`app/lib/features/profile/privacy_policy_screen.dart`） |
| 内容与公网那份同源 | ✅ 由 `tool/gen-privacy-page.mjs` 从 `docs/privacy-policy.md` **同一份 Markdown** 生成 `app/assets/privacy-policy.txt`，且**有防漂守卫**（改了政策没重生成 → 门禁判红） |
| 内容干净 | ✅ 内部注记（状态/待办/文件路径/核对命令）用一对标记圈起来，**三份生成物（公网中文页、英文页、应用内那份）都剥掉** |
| 备案号 | ⬜ 备案通过后填 `kAppFilingNumber`，那一行自动出现（空 = 不显示） |
| **首次启动的同意门** | ✅ 已做（v1.25.0）：整屏征求同意，`同意并继续` / `不同意` 两个按钮（**不设勾选框**，也就没有"默认勾选"与"点按钮等于勾上"这两种被禁的形态）；`阅读《隐私政策》` 可当场读全文；拒绝后给"再看一遍"与"退出"两条路，**且两种情况下都不收集**；同意状态落库（v11，`user_profile.privacy_consent_at_ms`），重启不再问 |
| **拒绝也能用** | ✅ v1.27.0：点「不同意」→ 照常进 App（离线功能本就不需要联网与权限），**但一条都不收集**；拒绝单独落库（`privacy_declined_at_ms`，v12），既不当成同意、也不再重复骚扰。191 号文四.2 禁止的"因不同意非必需收集而拒绝提供业务功能"由此消除。✅ **后半段也已收**（v1.28.0，用户点头后做）：匿名统计**默认关闭**，只有用户主动打开那个开关才会有数据发出去（schema v13 + 老库迁移把旧的 true 翻成 0）；政策中英与 `privacy-facts.json` 同步改写，硬门禁三处对账（事实源 ↔ 代码默认值 ↔ 政策正文）。改默认值时发现并修掉一条**漏接线**：启动时没人把库里的值同步进 analytics 对象 —— 以前两个默认值都是 true 所以看不出来，这一版若不修就是「开关显示关着、实际还在收集」 |
| **同意之前不收集** | ✅ 由启动顺序保证：`main.dart` 把 `_initAnalytics()` / 种子导入都放在同意**之后**；`privacy_consent_test.dart` 用 outbox 行数当证据（同意前 0 条，同意后才开始记 `app_open`） |
| **第三方依赖（SDK）清单** | ✅ 政策 §三之五（中英各一份）：**装进包里的每一个直接依赖**都列出名称、版本、功能、会不会收集信息、许可。同一份指引要求「集中展示第三方 SDK 的名称、功能及其处理个人信息的规则」—— 而加依赖在本仓库太容易（pubspec 加一行），所以 `privacy-audit` 会拿 pubspec 逐个核：**少一个就判红**（负向验证过）。⚠️ 但它的作用域是「`pubspec.yaml` 的**直接**依赖」——**不**检查政策里有没有多列、也不检查有没有链接（2026-09-30 一次对抗性审计指出的） |

## 三、软件著作权登记（软著）

**为什么**：国内主流安卓商店（华为、小米、OPPO、vivo 等）对**个人开发者**或**新主体**
上架通常要求提供软著证书；有公司主体时也常被要求。**具体要求以目标商店的开发者文档为准。**

> 2026-09-30 查证：**华为明确要求提交软著证书**；小米 / VIVO / OPPO 接受"软著证书 /
> App 电子版权证书 / 软件著作权认证证书"三选一。它们**还各自要求** ICP 备案、
> **App 安全评估报告**、**全国互联网安全管理服务平台（公安联网备案）审批截图** ——
> 完整清单与出处见 [`your-todo.md`](your-todo.md) §一之二。

**周期**：一般 **30–75 个工作日**，加急可显著缩短（
[来源](https://www.guozunlaw.com/m/news-81001.html)，非官方口径，**以中国版权保护中心与代办为准**）。

**通常要准备**（以及本项目现在的状态）：

| 材料 | 状态 | 位置 / 怎么来 |
|---|---|---|
| 鉴别材料 PDF（源程序 60 页） | ✅ 已能生成 | `node tool/copyright-pdf.mjs --owner "姓名"` → `dist/copyright/*.pdf`（A4 纵向、每页 50 行、页眉带版本与页码） |
| 鉴别材料 PDF（说明书） | ✅ 已能生成 | 同上，由 `docs/copyright-manual.md` 排版而来 |
| 软件说明书（用户手册） | ✅ 已起草（差 7 屏截图） | [`copyright-manual.md`](copyright-manual.md) |
| 申请表填写参考 | ✅ 已填好能核的字段 | [`copyright-application.md`](copyright-application.md) |
| 界面截图 | 🟡 已出 4 张 | [`screenshots.md`](screenshots.md) → `store-assets/screenshots/` |
| 主体证明材料（身份证 / 营业执照） | ⬜ **你的** | 只有你能提供 |

> 说明书与申请表不再是"待写"：2026-09-30 起草完成，**每一条事实都能在代码里核到**
> （写的时候发现我凭印象写的算法描述是错的 —— 引擎里 DELOAD 是保持重量而不是降 10% ——
> 已按 `engine/progression.mjs` 逐条改正）。剩下真正卡住的只有：你的身份信息、
> 以及真机安装放行后补齐其余 7 屏截图。
> 当前导出：**105 个源文件 / 26,353 行 → 528 页**，交前 30 页 + 后 30 页（含页码与文件定位）。
> （2026-09-30 起 `.py` 也收录 —— `tool/gen-icons.py` 是我们自己写的程序，之前被漏在外面。）
> 说明书草稿见 [`docs/store-listing.md`](store-listing.md) 第七节（你补真实截图即可）。
> **必须你做的**：实名、提交、缴费、拿证。

---

## 四、隐私政策的公网 URL

商店审核会**实际打开这个 URL**，所以它必须：公网可访问、内容与 App 内一致、有生效日期。

| 方案 | 优点 | 代价 |
|---|---|---|
| A. 仓库转公开 + GitHub Pages | 免费、随仓库更新 | 代码公开（本项目当前是私有仓库）；GitHub Pages 在国内访问不稳定 |
| B. 对象存储静态页（阿里云 OSS / 腾讯云 COS） | 国内访问快 | 若用自有域名，需域名+备案；用厂商默认域名则受限（以厂商规则为准） |
| C. 已有公司站点的 `/privacy` 路径 | 最专业 | 需要有站点 |

**建议**：如果本来就要做备案（第二节），顺手把域名/站点一起解决，用 **B** 或 **C**；
否则用 **A** 最快。**这一步需要你选一个方向** —— 页面本身已经生成好了（见下）。

### 页面已经做好，只差"放哪"

**2026-09-30 起，公开页面是生成物、且入库**：

| | |
|---|---|
| 文件 | `store-assets/privacy/index.html`（中文）+ `en.html`（英文） |
| 来源 | `docs/privacy-policy.md` / `.en.md` —— **唯一事实来源**，页面由它渲染 |
| 重新生成 | `node tool/gen-privacy-page.mjs` |
| 防漂移 | `node tool/gen-privacy-page.mjs --check`，已进 `verify.sh` 第 2 层：改了正文没重生成就红 |

页面是**自包含**的（样式内联、无外部资源、无 JS、无字体请求），
三种方案都直接能用：GitHub Pages 丢进仓库、对象存储上传单个文件、公司站点放进去
即可 —— 不需要构建步骤、不依赖任何 CDN。

> 为什么不直接手写一份 HTML：公开页与随包政策一旦各写各的，早晚对不上，
> 而这是最不该漂移的一类文本。生成 + 门禁是唯一能保证同源的做法。
> （第一次生成就抓到了英文版写着"339 个动作"和"4 个埋点事件"，实际是 351 与 9
> —— 当时两版不一致这件事**没有任何东西会发现**，因为检查只读中文版。）

同一份 URL 也会填进 Google Play / 华为 / 小米等各商店的表单（`docs/release-checklist.md` §7）。

### 怎么落地（2026-10-09：服务器那一侧已经写进仓库，剩下的是"传 + 跑"）

⚠️ **先分清哪条命令在哪台机器上跑**（第一次写这一节时没说清，用户当场就问了）：

| 命令 | 在哪跑 | 为什么 |
|---|---|---|
| `scp -r server/ root@<机器>:/tmp/lianleme-server/` | **你的电脑**（仓库里） | 把部署包（含新的 `Caddyfile` / `install.sh`）传上去 |
| `sudo … server/deploy/install.sh` | **云服务器**（root） | 它要写 systemd 单元、改 `/etc/caddy/Caddyfile`、`systemctl reload caddy` —— 这些只有在那台机器上才有意义 |
| `scp store-assets/privacy/*.html root@<机器>:/var/www/lianleme/privacy/` | **你的电脑** | 把两份生成好的页面传上去（页面不在部署包里） |
| `curl -s https://<域名>/privacy \| head -20` | 哪台都行 | 验收 |

**完整三步**（照你上次那套参数跑，只是多了一个 `WEB_ROOT`）：

```bash
# ① 你的电脑：把部署包传上去（这一步不能省 —— 新的 Caddyfile 与 install.sh 都在里面）
scp -r server/ root@<你的机器>:/tmp/lianleme-server/

# ② 云服务器：重跑安装脚本（caddy 模式会连同 /privacy 路由一起覆盖；existing 模式会把片段打印给你贴）
sudo DOMAIN=<你的域名> bash /tmp/lianleme-server/deploy/install.sh
#   ⚠️ 脚本会多出一步「5.5/7 放隐私政策的公开页」：
#      * 服务器上有整个仓库 → 它自己把两份 HTML 拷进 $WEB_ROOT/privacy/；
#      * 只有 server/ 这一个目录（常见）→ 它把下面这条命令原样打出来，你在**自己电脑**上跑：

# ③ 你的电脑：把两份页面传上去（② 已经拷过就跳过）
scp store-assets/privacy/index.html store-assets/privacy/en.html \
    root@<你的机器>:/var/www/lianleme/privacy/
```

传完**不用重启任何东西**（反代直接读目录）。**验收**：

```bash
curl -s https://<你的域名>/privacy | head -20     # 应当看到政策正文
curl -s https://<你的域名>/privacy/en | head -5   # 英文版
```

✅ **2026-10-09 已经在 `api.elliotli.work` 上生效**（那台机器跑的是 **nginx**，站点配置 `/etc/nginx/sites-available/lianleme-api` 里加了 `location /privacy`，页面放在 `/var/www/lianleme/privacy/`；两者的原文件都备份在 `/root/lianleme-api.bak*`）。
从公网实测：**`/privacy` → 200（41 KB 中文页）、`/privacy/` → 200、`/privacy/en` → 200（42 KB 英文页）**；
同时核过没碰坏别的东西：首页 `/` 仍是那句 `lianleme`、`/healthz` 仍是 200、
另外两个站（`hanzi-kids` / `teacher-dashboard`）的配置文件**一个字节没动**。
⚠️ 服务器上试出来两个 nginx 的细节（仓库模板已按这版改好）：`location` **不要写成带斜杠的
`/privacy/`**（那样 `/privacy` 会先 301 补斜杠），而且 `try_files` 要**先试 `$uri/index.html`**
（写 `$uri` 在前会先命中目录，照样 301）。

⚠️ **两个都做完才算完**（第一次写漏了这层）：**路由**（在反代配置里）+ **页面**（在 `$WEB_ROOT/privacy/`）。
只传页面不装路由 → 请求落到 catch-all 上，返回的是 **8 个字节的 `lianleme`**；
只装路由不传页面 → 404。**现在就处在这个状态**：`https://api.elliotli.work/privacy` 返回的还是那 8 个字节。

**为什么这条路由必须写进仓库的模板**（而不是让你手工加一次）：`install.sh` 在
`PROXY_MODE=caddy` 下会**整体覆盖** `/etc/caddy/Caddyfile`（我们自己的那份带
`# managed-by: lianleme-install` 标记时）——手工加的 /privacy 路由会在下一次部署时消失，
而那种失败只在审核当天才看得见。`PROXY_MODE=existing` 则相反：它**只打印**片段，
所以那一版要你**重新跑一次脚本、把新片段贴进去**（老的片段里没有 /privacy）。

**填进商店表单的 URL**：中文 `https://<你的域名>/privacy`、英文 `https://<你的域名>/privacy/en`
（`docs/release-checklist.md` §7 那张表里逐条对应）。

---

## 五、商店材料（清单）

| 材料 | 谁做 | 说明 |
|---|---|---|
| 应用图标 | ✅ 已做（我） | `store-assets/icon-512.png`；Android 全套（传统 5 密度 + 自适应 + 圆形 + 主题剪影） |
| 应用图标·怎么重做 | 一条命令 | `python3 tool/gen-icons.py`（**默认方向 D：用户给的橙色圆环主图**，直接缩放 `icon/AppIcon-1024x1024@1x.png`；白底角按瓦片色补满，启动页那张是按「自发光」抠出来的）；`--logo dumbbell` 是上一版（深底 + 白「练」 + 哑铃）。`tool/asset-check.mjs` 守着「不许是 Flutter 默认图」 |
| 截图 | 你（或设计师） | 主流要求 3–8 张；**注意**：截图必须来自真实 App，不能拿原型图充数 |
| 应用描述（短/长） | ✅ **已备好** | [`docs/store-listing.md`](store-listing.md) §2/§3，可直接粘贴 |
| 分类 / 内容分级 | ✅ **已备好答案** | [`docs/store-listing.md`](store-listing.md) §4（逐题答案，你确认即可） |
| 隐私政策 URL | 见第四节 | |
| 数据安全表单（Google Play / 国内商店的"个人信息收集清单"） | ✅ **已备好两套** | [`docs/store-listing.md`](store-listing.md) §5：**按"这个包有没有配上报地址"分 A/B 两版** —— 填错属申报不实 |
| 联系人 / 客服邮箱 | 你 | 商店必填 |

---

## 六、建议的启动顺序（并行，别串行）

**关键路径是软著**：商店明文规定「软著办理中不能先上架」，而它 30–75 工作日；
备案只要 20 工作日，反而在后面。所以顺序不是"哪个简单先做"，是**软著先起**。

```
第 1 天   ┌─ 你：确认三处名称都用「练了么」（App 名 / 软著 / 备案 —— 必须一致）
          ├─ 你：问一次接入商「没有服务器的 App 备案，接入信息怎么填」（见二之三）
          └─ 你：填身份信息 → 提交软著（**从今天开始算 30–75 工作日**）
            材料已就绪：node tool/copyright-pdf.mjs --owner "姓名"  → 两份 PDF
第 1 周   ├─ 你：软著受理后，并行起 App 备案（20 工作日，需要接入商账号）
          ├─ 你 + 我：熟人短测（半天，3–5 个熟人 × 5 分钟）与"带手机去健身房练一次"
          ├─ 你 + 我：（建议做、不卡上架）正式 5 人可用性测试（约一天）
          └─ 你：选隐私政策托管方式并上传（✅ 页面已生成，见第四节）
拿到软著后 ┌─ 你：生成真密钥并备份（✅ 接线与脚本已验证）
          ├─ 我：实现"应用内展示备案编号"（小改动，切版 + 装真机）
          └─ 你 + 我：商店提交（图标与 11 屏截图已就绪）
```

---

## 附：这份文件本身怎么保持不过期

- 事实性条目**都标了来源与核实日期**；规定变化时改这一处，不要散落在别处
- 与代码有关的部分（签名、隐私政策事实、权限）由工具守：
  `node tool/privacy-audit.mjs`（已进 `./verify.sh`）
