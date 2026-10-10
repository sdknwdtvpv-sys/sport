# 动作示意图素材调研（2026-10-11）

> 用户原话：「先去 GitHub 上看一下有没有开源的动作示意图，**不要太 low 的，要高级一点的**」。
> 这一页是那次调研的结论 + 我的推荐 + **明确不能碰的清单**。
> **它只是调研，没有接入任何素材**；首版的留白已经用**我们自己的「动作要领」**填上了
> （`docs/screens.md` §S4，纯文本、零版权风险），图是**下一版**的事。

---

## 〇、先说三条结论（这三条决定了后面怎么选）

1. **最容易被搜到的那两个库，图是不能用的** —— `yuhonas/free-exercise-db` 与 `wrkout/exercises.json`
   的图片不是"许可不明"，是**已知侵权**：维护者 issue 原话「I actually have no idea where the images
   are from … usage would be at your own risk」，上游 README 更直接写了
   「these have been scraped off the internet … would advise against using them in commercial projects
   … reverse image search suggests bodybuilding.com」。**画面里还有 Life Fitness / TuffStuff 的器械商标**。
   两个仓库的 Unlicense 徽章**只覆盖 JSON/代码，不覆盖图片**。
   ⚠️ 顺带：`gengyueworks/gym-exercise-guide` 把这批图二次标成 Unlicense，而实测图与上游**不是同一张**
   —— 它的**中文要点文本**值得看，图不能信。
2. **"高级"与"可信"在这一题上是冲突的**。观感最好的那套（`hitmanrepo/open-exercise-illustrations`，
   CC0、3D 渲染风、768×1024、796 张）**是 AI 生成且作者自述"未经专业教练审核"**
   （握法、钢索走向、器械几何可能不准）。一个教动作的产品放出**画错的示意图**，
   比不放图更糟；而且中国《人工智能生成合成内容标识办法》（2025-09-01 施行）要求对 AI 生成内容作标识。
3. **真矢量（SVG）那套必须接受 CC BY-SA 的 share-alike**：改色/裁切之后的图**必须以 BY-SA 继续发布**
   （只约束图片资产本身，不传染代码）。好处是**可以完美适配我们的深色主题**、文件小到每张 ≈16KB。

---

## 一、候选对照（许可都读过原文）

| 资源 | 形态 | 许可 | 商用要求 | 覆盖 | 体积 | 观感（诚实评价） |
|---|---|---|---|---|---|---|
| **RepDB/exercise-dataset**（Free Tier） | 扁平插画 WebP 512px | 自定义「RepDB Free Tier License v1.0」 | **明确允许商用**；须可见署名「Exercise data by RepDB (repdb.co)」；禁止当数据集再分发；允许改尺寸/裁切/改色 | 637 动作（免费层 523 图） | webp 共 **8.6MB** | 统一干净，一致性高、不廉价（比 CC0 那套"平"一点） |
| **hitmanrepo/open-exercise-illustrations** | 3D 渲染风 WebP 768×1024 | **CC0 1.0** | 无任何义务（可商用可改） | 415 动作 / 796 图 | ≈24MB | **最好看**（无脸苍白人形 + 炭黑棚光 + 器械很细）——但 **AI 生成、未审核** |
| **bryllim/workout-guide** | **真矢量 SVG**（+512 PNG） | 代码 MIT / **资产 CC BY-SA 4.0** | 署名 + 标注改动 + **改编物须继续 BY-SA 4.0** | 302 动作 × 3 帧 = 906 张 | SVG ≈16KB/张 ≈ **14.5MB** | 白单路径剪影 + 粗描边，干净可任意改色，但**偏漫画/贴纸感** |
| `everkinetic/data`（上游） | 黑白矢量线稿 SVG | **CC BY-SA 4.0** | 同 bryllim | 1109 SVG | ≈28MB | 经典但有年代感 |
| `wger` 图片库 | 混合（真人照 + 线稿 + 42 张 AI） | **逐图不同**（291 张 4.0 / 88 张 3.0） | 逐图署名，实务上不可维护 | 仅 379 图 / 920 动作（≈41%） | — | 风格不统一 |
| `jaysan0330/musclemap`（**付费**） | **手绘**解剖插画 240×240 WebP | Gumroad **个人授权 ≈$99**（sample 明确 evaluation only） | ⚠️ **"个人授权"是否允许商业 App 内嵌必须先核实** | 552 动作 × 1104 张 | 小 | **艺术水准最高一档**（非 AI、手绘） |
| Mixamo（3D） | 3D 角色 + 骨骼动画 FBX | Adobe FAQ 说免费商用 | ⚠️ **不支持 China 国家码账号**；只有 FBX；杠铃动作基本没有 | 泛用动作 | 1.5–3.5MB/角色 | 好看，但工程 + 合规成本高、国内不可用 |

## 二、明确不能碰（附理由，省得下次又找一遍）

| 资源 | 为什么不能碰 |
|---|---|
| `yuhonas/free-exercise-db` · `wrkout/exercises.json` 的**图** | **已知侵权**（抓的 bodybuilding.com / ExRx），画面含器械商标；JSON 可用、图不可用 |
| `gengyueworks/gym-exercise-guide` 的图 | 自称源自上面那批 + Unlicense，实测不符 → 来源无法核实（**中文文本可取**） |
| `hasaneyldrm/exercises-dataset`（22.6k★） | MEDIA 例外原文「Cloning this repository does not grant you any license to the media」，媒体版权属 Gym visual |
| **ExerciseDB / exercisedb.io API** | 条款禁止缓存、禁止留存、终止后须删除、禁止做竞品 → **完全不能打包进产品** |
| MuscleWiki | 专有内容（按 all-rights-reserved 处理） |
| GymBells | CC BY-**NC** 4.0 → 商用禁止 |
| MuscleMap **sample** | 明确 evaluation only |
| AMASS / Human3.6M / SMPL-X | 仅学术非商用（SMPL-X Body 虽 CC BY 4.0，但受专利阴影，且它是角色格式不是动作） |
| LottieFiles 免费动画 | Lottie Simple License 带 share-alike，且两份官方帮助页对"免费版能否商用"**自相矛盾** |
| `three_dart` / `flutter_gl` | 已停更 4 年 |

## 三、Flutter 落地与体积（真要接的时候看这一段）

* **SVG（bryllim / everkinetic）**：`flutter_svg` 直读；**只打包我们要的那批动作的帧**
  （全量 906 张 ≈14.5MB；取 2–3 帧大约 5–11MB）；**可运行时改色**适配深色主题 ——
  但改色即改编，触发 share-alike。
* **WebP（RepDB / hitmanrepo）**：Flutter 原生支持、离线最稳、不新增依赖；按动作 id 分目录打包，
  或走"首次进入时下载缓存"（`path_provider`）。**不要用 GIF**（体积是 WebP 的 3–8 倍且不能改色）。
* **3D**：Flutter 没有一方蒙皮动画运行时；`flutter_scene` 要 Flutter ≥3.47 + 实验性 Flutter GPU
  （1–3 周、API 易变），`model_viewer_plus` 是 WebView 播 GLB（最便宜但性能/可控性差）。
  **为"填空"这个目的，3D 不划算。**

## 四、如果要接，必须做的三件事（都是这个仓库的既有规矩）

1. **署名写进「我 → 隐私与关于 → 开源许可」**（我们已经有那一页，且 `docs/privacy-policy.md`
   §三之五 是第三方清单的唯一真源）：
   * CC0（hitmanrepo）：法律上无义务，仍建议写一行来源；**并按《AI 生成合成内容标识办法》评估"AI 生成"标注**；
   * RepDB：可见链接「Exercise data by RepDB (repdb.co)」；
   * CC BY-SA（bryllim / everkinetic）：作者 + 许可名称与版本 + 链接 + **是否修改** + 保留原许可声明
     （例：「动作插画：Everkinetic / Bryl Lim《Workout Guide》，依 CC BY-SA 4.0 使用，已调整尺寸与配色」）。
2. **软著材料别把第三方素材写成自研**：登记的是我们自己的源代码；图片以**独立资产**随包分发
   （集合 ≠ 改编），但**我们改过的图必须 BY-SA**、并在许可页留痕。
3. **抽检**：无论选哪套，先抽 20 个我们动作库里最常见的动作（卧推 / 深蹲 / 硬拉 / 引体 / 划船 /
   推举 / 弯举 / 臂屈伸 / 腿举 / 腿弯举 / 飞鸟 / 侧平举）**对一遍动作是否画对** ——
   教动作的产品，画错比不画更伤人。

## 五、我的推荐（等你拍板）

| 方案 | 内容 | 代价 | 我的判断 |
|---|---|---|---|
| **A（推荐）** | **RepDB Free Tier**：许可最清晰（明确可商用、**无 share-alike**）、8.6MB、可改色裁切，配一行署名 | 512px 在 3× 屏上略软；无中文；免费层不含透明背景与动画 | ✅ **先做这个**：风险最低、体积最小、义务只有一行署名 |
| **B** | **bryllim SVG**：无限清晰、**可完美适配深色主题**、每张 16KB | 接受 **BY-SA share-alike**（改过的图要以 BY-SA 发布）+ 漫画感 | 🟡 若 A 的观感不够、且你接受 share-alike，再上这条 |
| **C** | **musclemap 付费 ¥700 左右（$99）**：手绘、非 AI、艺术水准最高 | ⚠️ **"个人授权"是否允许商业 App 内嵌必须先核实**；买前先问作者 | 🟡 **只在核实授权之后**才考虑 |
| **D** | 不做图，只保留我们自己的**动作要领文本**（首版已经这样做） | 少一个卖点 | ✅ 首版就这样；图是"锦上添花"，不是"能不能用" |

**我建议的顺序**：首版照现在的样子（只有文本要领）→ 下一版先试 **A**（RepDB，免费、许可干净）→
若观感不够，再评估 **B**（可改色、更像我们的深色语言）→ 若都不满意且你愿意花钱，
**先核实 C 的授权**再买。

**另外一条不影响上面的判断**：只给**常见动作**配图（前 60–80 个），不必 351 个全配 ——
体积、抽检成本、以及"冷门动作根本找不到对得上的图"这三件事都会因此小很多。
