# 练了么 · 出 TestFlight 包（2026-10-12 加入 Apple Developer Program 之后）

> 用户 2026-10-12 已经**加入 Apple Developer Program**（付费）。这一页就是"怎么把它变成一个
> 能在 TestFlight 里装的包"—— 从账号、App Store Connect 记录，到归档、上传、分发。
>
> ⚠️ **这一页写的是流程，不是"已经跑通"的记录** —— 里面每一步都标了谁做、我能不能做。
> 跑通之后（真出了一个 TestFlight 构建）要在这一页顶部补一行实测证据（日期 / 版本 / build 号），
> 像 `docs/backend-hosting.md` 四之二那样。**没跑通之前不许写成"已通过"**。

---

## 一、先分清 TestFlight 与内测包（两条完全不同的路）

| | 免费档（我们现在做的） | 付费 / TestFlight（这一页） |
|---|---|---|
| bundle id | `com.sdknwdtvpv.lianleme.dev`（**必须带 `.dev`**，免费档只能用自己的 App ID） | `com.sdknwdtvpv.lianleme`（与安卓一致） |
| 签名 | `Apple Development` 证书（**7 天**过期） | `Apple Distribution` 证书（**1 年**） |
| 装法 | 插线 + `tool/ios-device-run.sh` | **TestFlight App 里点安装**（不用插线） |
| 谁要 | 只有插着线的这台机器 | 任何拿到邀请的人（最多 10000 人） |
| 上限 | 一台设备最多 3 个免费 App | iTunes Connect 记录 + 构建号递增 |

**结论**：真机自测那条路（`tool/ios-device-run.sh`）**继续留着**，它不需要 App Store Connect；
TestFlight 是给"别人也能装"用的。

---

## 二、四步流程（每步都写明"谁做"）

### 第 1 步：Xcode 里把账号登好（**只有你能做**）

`Settings…（⌘,）→ Accounts` → 加 Apple ID `919500973@qq.com` → 选中它，
右边 Team 那一栏应当能看到 **`Elliot LI`**，且**不再是 "Personal Team"**（付费后就是正式团队）。

⚠️ 这台 Mac 上有个**反复出现的老毛病**：账号会**自己从列表里消失**
（钥匙串里没留下 Xcode 的会话）。判据与解法在 `docs/ios-free-provisioning-guide.md` §四
最后一行 —— 症状是 `xcodebuild` 报 `No Accounts`，而你在界面上明明看得到那个 Apple ID。
**解法**：Accounts 里删掉 → **⌘Q 完全退出 Xcode** → 重开、重新登录 → **别关 Xcode**。

**验证**（你登完我可以马上核）：

```bash
plutil -p ~/Library/Preferences/com.apple.dt.Xcode.plist | grep -A3 AppleIDLists   # 列表非空
security find-identity -v -p codesigning | grep -i distribution                    # 有没有发行证书
```

### 第 2 步：App Store Connect 里建 App 记录（**只有你能做**，一次性）

<https://appstoreconnect.apple.com> → **我的 App** → **＋** → **新建 App**：

| 字段 | 填什么 | 依据 |
|---|---|---|
| 平台 | iOS | |
| 名称 | **练了么** | `docs/store-listing-ios.md` §一 |
| 主要语言 | 简体中文 | 同上 |
| 套装 ID（Bundle ID） | **`com.sdknwdtvpv.lianleme`** | 与安卓一致；与工程里那三处 `PRODUCT_BUNDLE_IDENTIFIER` 一致 |
| SKU | 任意唯一串（例：`lianleme-ios-001`） | Apple 内部用，用户看不到 |
| 用户访问权限 | 完全访问 | |

⚠️ **套装 ID 一旦用过就改不了**。别选 `…lianleme.dev`（那是免费档的内测 id）。
⚠️ 这一步会**自动在开发者后台建好 App ID**（`com.sdknwdtvpv.lianleme` + `.RestWidget` 扩展）——
有了它，第 3 步的自动签名才能签出版本。

**顺手把"出口合规"想清楚**（ASC 会在第一次上传后问你，也可以先填）：
`docs/store-listing-ios.md` §三 有一份**可复核的事实表**（包里有 AES-256-GCM / HKDF-SHA256，
全是公开标准算法、只服务默认关闭的云备份、`Info.plist` 里 `ITSAppUsesNonExemptEncryption=false`）。
结论现在仍是 **`false`**（标准算法、量产消费类用途），但**这是法律声明，只有你能签**。

### 第 3 步：归档 + 导出 IPA（**我可以跑**，要第 1、2 步先成立）

```bash
source ~/HARNESS/lianleme/flutter-env.sh
cd "/Volumes/Elliot's SSD/HARNESS/lianleme/sport/app"

# 出包（三个编译期常量一个都不能少 —— 与安卓同一个变体）
flutter build ipa --release \
  --export-method app-store \
  --dart-define=LIANLEME_BACKUP_URL=https://api.elliotli.work \
  --dart-define=LIANLEME_BACKUP_DISCLOSED=true \
  --dart-define=LIANLEME_ANALYTICS_URL=https://api.elliotli.work/v1/events
```

* 产物：`build/ios/archive/Runner.xcarchive` + `build/ios/ipa/练了么.ipa`；
* 缺 Team 时它**会红**并说"Select a development team" —— 那是**要你在 Xcode 里选一次 Team**
  （`Runner` 与 `RestWidget` 两个 target 的 Signing & Capabilities 都选 `Elliot LI`），
  选完 Xcode 会把 `DEVELOPMENT_TEAM = <团队 id>` 写进 `project.pbxproj`。
  ⚠️ **那处改动是本地改动，不许提交**（团队 id 属于个人账号，见 `tool/ios-device-run.sh` 的注释）；
  跑完我把它 `git checkout` 回去，并用 `grep -c DEVELOPMENT_TEAM` 核一遍（应为 0）。
* 归档后**立刻核一遍产物**（这一步以后要接进守卫）：

```bash
node tool/check-ios-app.mjs build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
```

### 第 4 步：上传到 App Store Connect（**我可以跑**，但要一把 API 密钥）

推荐用 **App Store Connect API Key**（比在 Xcode 里点 Organizer 稳、可复现、不进钥匙串）：

1. ASC → **用户和访问** → **集成 / App Store Connect API** → 生成密钥（角色 **App Manager** 即可）；
2. 下载 `.p8`（**只能下一次**）、记下 **Key ID** 与 **Issuer ID**；
3. 把它放到一个**不进仓库**的位置（例：`~/.appstoreconnect/private_keys/AuthKey_<KeyID>.p8`）；
4. 上传：

```bash
xcrun altool --upload-app -f build/ios/ipa/练了么.ipa -t ios \
  --apiKey <KeyID> --apiIssuer <IssuerID>
```

（`altool` 已被 Apple 标为"将由 `notarytool` 承担"但**上传 App Store 包的路径仍然可用**；
如果哪天它真的停了，等价的是 `xcrun iTMSTransporter`，两者都在 Xcode 里自带。）

**另一条路（不用 API 密钥）**：Xcode → **Window → Organizer** → 选中刚归档的 Archive →
**Distribute App → App Store Connect → Upload** —— 走的是界面里那份会话，
所以第 1 步必须处于"已登录"状态。

---

## 三、上传之后（在 App Store Connect 里做完才能装）

1. **处理构建**：等几分钟，ASC 里 **TestFlight → 构建版本** 会从「正在处理」变绿；
2. **出口合规**：第一次会问"是否使用了加密" —— 按 §第 2 步上面那张表回答；
3. **测试信息**：
   * **内部测试**（最多 100 人，团队内的 Apple ID）：建一个内部组，加上人，**立即可用**，不需要审核；
   * **外部测试**（最多 10000 人）：要填**测试内容说明** + **Beta App Review**（首次通常 1–2 天），
     并且**必须有隐私政策 URL**（我们已有：`https://api.elliotli.work/privacy`）；
4. 测试者装 **TestFlight** App → 收邀请 → 安装。

⚠️ **构建号（`CFBundleVersion`）不能重复**：同一个 `1.68.0` 再传一次必须把 `+83` 加一。
这条由 `tool/check-dist.mjs` 在安卓侧守着（"包比源码旧就判红"），iOS 侧目前**只有人记得**——
所以每次上传前先跑 `./verify.sh`，它会核对 `pubspec.yaml` 的 build number 与文档一致。

---

## 四、这一步与"上架"的距离

出 TestFlight 包**不等于**上架。剩的是 `docs/release-checklist.md` 里那几条硬门槛：

| 还差 | 在哪 |
|---|---|
| App Privacy 隐私标签（**变体 B** 那张表） | `docs/store-listing-ios.md` §三 |
| 截图（三套里 App Store 那套 15 张已重出，**必须是无 alpha 的 8 位**） | `store-assets/screenshots-ios/` |
| 支持 URL / 隐私政策 URL / 开发者名称 / 联系邮箱 | §一（隐私政策 URL 已可用） |
| 审核备注（给审核员看的说明，含"首版无内购"） | `docs/store-listing-ios.md` §五 |
| 备案号（大陆上架另需） | `docs/release-checklist.md` §7 |

---

## 五、这一页的边界（别把没做的说成做了）

* **没有**在 CI 里跑过 iOS 归档 —— 它需要 Xcode + 账号，ubuntu runner 上没有；
* `tool/check-ios-app.mjs` 现在核的是 `flutter build ios` 的产物，**归档产物的核对还没接**；
* TestFlight 的**外部测试**要 Apple 审核，**这一页没验过**（我们连一个构建都还没传）；
* 出口合规那一栏**只有你能签**，我给的是可复核的事实与建议，不是法律意见。
