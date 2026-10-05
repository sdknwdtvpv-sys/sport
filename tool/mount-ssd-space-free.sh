#!/usr/bin/env bash
#
# 练了么 · 把 SSD 卷**另外**挂到一个没有空格的挂载点（方案 C）
#
# ─────────────────────────────────────────────────────────────────────────────
# 为什么需要这个脚本（三次受害者，都有出处）
#
# 这块外置 SSD 的**卷名**是 `Elliot's SSD` —— 里面有一个空格。Android 工具链不支持
# 带空格的 SDK 路径。已经咬了三次，每次症状都离根因很远：
#
#   1. `flutter build appbundle --release` 报
#      "Release app bundle failed to strip debug symbols from native libraries."，
#      而 .aab **其实正常产出**了 —— 真因在 `-v` 日志里：
#      `apkanalyzer` 是个 shell 脚本，没给 classpath 加引号，空格把路径劈成两段，
#      Java 去找一个叫 `SSD.harness-deps.android-sdk.cmdline-tools.latest` 的主类。
#      （见 `docs/dev-environment.md`「卷名里的空格会假装弄坏 AAB 构建」那一节，
#        以及 `tool/check-aab.mjs` 的文件头。）
#   2. `node tool/privacy-audit.mjs --apk` 空转（同根因）。
#   3. `sdkmanager` / `avdmanager` 直接报
#      `错误: 找不到或无法加载主类 SSD.harness-deps...` —— 连 --list 都跑不了。
#
# 用户 2026-10-05 拍板走**方案 C**：真源不动（还是 `/Volumes/Elliot's SSD`），
# 给工具链另外挂一个**路径里没有空格**的挂载点。这个脚本就是那一步。
#
# 为什么不去改 `tool/dev-env.sh` 里的 DEPS：**不要改**。真源路径是数据的家，
# 换了它就得搬 3.5G 的 SDK、4.8G 的 gradle 缓存，而且"仓库在 SSD 上"这件事
# 本身没变（没插盘连代码都没有）。这个脚本只加一个**别名路径**。
#
# ─────────────────────────────────────────────────────────────────────────────
# ⚠️ 哪些验证过、哪些没有（写这个脚本的那次会话没有被授予 sudo，所以用了别的办法把机制验掉）
#
# 那次会话跑 `sudo -n true` 返回 **126 Operation not permitted**，所以**不能替你把这块真 SSD
# 卸了再挂**（你有密码，这一步只能你来）。能验的都验了，验不了的写清楚 —— 下面就是验证边界：
#   * **验证过的**：卷的 UUID / 设备节点 / 文件系统（`diskutil info -plist` 真读到的）、
#     挂载点目录不存在、`diskutil mount` 支持 `-mountPoint`、
#     `/etc/fstab` 由 `diskarbitrationd` 认（`man diskarbitrationd`）、
#     **卷已挂载时 `mount_apfs` 拒绝第二次挂载**（rc=75 "Operation already in progress"）、
#     **`diskutil mount` 在卷已挂载时会打印 "mounted" 并返回 0 但什么都没做**（假成功）、
#     以及**"卸下来 → 换到一个自定义挂载点挂上"这个动作本身是可行的**——
#     后者是用一个临时 APFS 镜像（不需要 root）跑通对照实验证实的：
#     `diskutil unmount /Volumes/probevol` → `diskutil mount -mountPoint /tmp/probe-mnt-nospace <UUID>`
#     → 挂载表里真的出现 `on /private/tmp/probe-mnt-nospace`（实验后镜像已卸载删除）。
#   * **没验证过的**（两件，都只能你来跑）：
#     ① 在**这块真 SSD** 上卸下再挂上 —— 它是外置盘、又正被跑着的仓库/编辑器/终端占着，
#        卸不干净会连累正在跑的东西，不能拿去试（对照实验用的是另一块临时镜像）；
#     ② 挂上之后 `flutter build appbundle` 是否真的变绿。
#     跑完请回报：`--check` 的输出 + `flutter build appbundle --release` 的退出码
#     （以及那句 "failed to strip debug symbols" 还在不在）。
#   * 顺带一提：脚本里那个挂载判据（`is_mounted_at`）已经**双向**验过 —— 没挂时不会
#     假报"挂了"，挂了（哪怕挂载表记的是软链展开后的物理路径）也不会漏报"没挂"。
#
# ─────────────────────────────────────────────────────────────────────────────
# 只适用于 macOS。Windows / Linux 上**不要用**这个脚本：那边没有
# `diskutil` / `diskarbitrationd` / APFS，做法完全不同（Windows 是换个盘符，
# Linux 是 `/etc/fstab` 里写 `UUID=... /mnt/xxx apfs` 再 `mount -a`）。
#
# 用法（命令要让 sudo 能读到脚本，所以用仓库里的路径）：
#   sudo tool/mount-ssd-space-free.sh            # 挂载（幂等，已挂好就直接过）
#   tool/mount-ssd-space-free.sh --check         # 只读检查，**不需要 sudo**
#   sudo tool/mount-ssd-space-free.sh --unmount  # 卸掉这个别名挂载点
#   sudo tool/mount-ssd-space-free.sh --fstab    # 打印/写入重启后仍然生效的 fstab 条目
#
# 挂载点默认 `$HOME/HARNESS/ssd`，可覆盖：
#   sudo tool/mount-ssd-space-free.sh --mount-point /Users/you/ssd
#   MOUNT_POINT=/Users/you/ssd sudo tool/mount-ssd-space-free.sh

set -uo pipefail

# ── 真值（2026-10-05 用 `diskutil info -plist` 从这台机器上读到的） ────────────
# 只认 UUID，不认设备节点：`disk7s1` 是**这次插拔**的节点名，换一个 USB 口就会变成
# disk9s1 之类；UUID 是卷自己的身份，插哪儿都不变。fstab 那行也只能写 UUID。
VOLUME_UUID="C25E83A4-B93C-404E-8726-953F7DE08BD5"
VOLUME_NAME="Elliot's SSD"
SRC_DEFAULT="/Volumes/Elliot's SSD"
FSTYPE="apfs"

# 真源 / 挂载点：都允许用环境变量覆盖，方便换机器 / 换卷
SRC="${SRC:-$SRC_DEFAULT}"
MOUNT_POINT="${MOUNT_POINT:-$HOME/HARNESS/ssd}"

# 挂上之后，工具链要用的东西应当在这里出现（用来判断"这次挂得到底成没成"）
SENTINEL_REL="harness-deps/android-sdk"

# ── 输出：克制、中文、出错要喊 ───────────────────────────────────────────────
# 刻意不用颜色/进度条：这个脚本的输出会被贴进文档和 issue 里，越朴素越好抄。
say()  { printf '%s\n' "$*"; }
warn() { printf '警告: %s\n' "$*" >&2; }
die()  { printf '错误: %s\n' "$*" >&2; exit 1; }

# 每个失败路径都要给"下一步" —— 只报错不给出路，用户只能来问人。
die_with_hint() { printf '错误: %s\n' "$1" >&2; printf '下一步: %s\n' "$2" >&2; exit 1; }

# 路径里有没有空格/控制字符 —— 这就是整件事的判据
has_space() { case "$1" in *[[:space:]]*) return 0 ;; *) return 1 ;; esac; }

fatal_space() {
  has_space "$1" && die_with_hint \
    "路径里有空格：$1" \
    "挂载点自己不能带空格，否则换了等于没换。用 --mount-point 指一个纯 ASCII、无空格的目录。"
  return 0
}

# ── 只读事实：从 diskutil 读，读不到就说"解析不了" ───────────────────────────
# 刻意不写 `diskutil info -plist | grep`:plist 的输出格式不是给人解析的，
# PlistBuddy 才是 Apple 给的正规读法。读不到 key 时 PlistBuddy 返回 1。
plist_field() { # $1 = VolumeUUID 之类的 key
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null
}

read_volume_facts() {
  PLIST="$(mktemp -t lianleme-ssd-info)" || die "建不了临时文件（mktemp 失败）"
  # shellcheck disable=SC2064  # 立即展开，别等到 trap 触发时才求值
  trap "rm -f '$PLIST'" EXIT

  # 按 UUID 问：卷挂在哪儿、叫什么都问得出来，不依赖当前挂载点是否仍是默认值
  if ! diskutil info -plist "$VOLUME_UUID" >"$PLIST" 2>/dev/null; then
    die_with_hint \
      "diskutil 认不出卷 UUID ${VOLUME_UUID}" \
      "SSD 插上了吗？换过盘就是另一块盘了 —— 先跑 tool/mount-ssd-space-free.sh 里的 --check，或手工 diskutil info -plist \"/Volumes/Elliot's SSD\" 看 VolumeUUID，然后改本脚本顶部那三行真值。"
  fi

  V_UUID="$(plist_field VolumeUUID)"
  V_NAME="$(plist_field VolumeName)"
  V_DEVID="$(plist_field DeviceIdentifier)"
  V_FSTYPE="$(plist_field FilesystemType)"
  V_MOUNT="$(plist_field MountPoint)"

  [ -n "$V_UUID" ] || die_with_hint \
    "解析不了 diskutil 返回的设备信息里的 VolumeUUID" \
    "这台机器上的 diskutil 输出格式可能和预期不同；把 \`diskutil info -plist \\\"\$VOLUME_UUID\\\"\` 的原始输出贴出来。"
  [ -n "$V_DEVID" ] || die_with_hint "解析不了 Diskutil 返回的 DeviceIdentifier" "同上：把原始 plist 贴出来。"

  if [ "$V_UUID" != "$VOLUME_UUID" ]; then
    die_with_hint \
      "UUID 对不上：脚本里写的是 ${VOLUME_UUID}，diskutil 说是 ${V_UUID}" \
      "这是**另一块盘**或卷被重建过。确认后改本脚本顶部的 VOLUME_UUID（真值用 diskutil info -plist 读）。"
  fi
}

# 挂载表里找某个路径的挂载记录（`diskutil mount` 的输出不可信，见文件头）
mount_line_of() { mount | grep -F " on $1 (" ; }

# 路径的物理形态（软链会展开；目录不存在时原样返回）—— 必须看物理路径，理由见下
phys_of() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

# **判据必须同时看"你给的那条路径"和"它的物理路径"**。实测（2026-10-05，用一个临时
# APFS 镜像做的对照）：`diskutil mount -mountPoint /tmp/probe-link …`（probe-link 是指向
# /tmp/probe-real-dir 的软链）之后，**挂载表里记的是 /private/tmp/probe-real-dir** ——
# 你给的那条路径在表里查不到。只做字面比较的实现会把"挂好了"报成"没挂上"，
# 而报错信息会让用户以为是 APFS 不支持，方向全错。
is_mounted_at() {
  [ -n "$(mount_line_of "$1")" ] && return 0
  p="$(phys_of "$1")"
  [ "$p" != "$1" ] && [ -n "$(mount_line_of "$p")" ] && return 0
  return 1
}

# 同上，"这条路径上的挂载具体记在哪条路径"（给输出用；给不出就返回原路径）
recorded_mount_path() {
  [ -n "$(mount_line_of "$1")" ] && { printf '%s' "$1"; return; }
  p="$(phys_of "$1")"
  [ -n "$(mount_line_of "$p")" ] && { printf '%s' "$p"; return; }
  printf '%s' "$1"
}

# 某个**普通目录**是不是"真正的挂载点"：挂载表里有没有它
assert_real_mount() { # $1 = 路径
  is_mounted_at "$1" && return 0
  die_with_hint \
    "$1 看起来是个普通目录，但挂载表里没有它 —— 卷**没有**挂在上面" \
    "先跑 tool/mount-ssd-space-free.sh --check 看现状；再跑 sudo tool/mount-ssd-space-free.sh 挂载。"
}

# ── 模式：--check（只读，不需要 sudo） ───────────────────────────────────────
mode_check() {
  say "== 卷本身（真值来自 diskutil，不是猜的） =="
  read_volume_facts
  say "  卷名        : $V_NAME"
  say "  VolumeUUID  : $V_UUID"
  say "  设备节点    : /dev/$V_DEVID"
  say "  文件系统    : $V_FSTYPE"
  say "  现在挂载于  : ${V_MOUNT:-（未挂载）}"
  [ "$V_FSTYPE" = "$FSTYPE" ] || warn "文件系统是 ${V_FSTYPE}，脚本按 $FSTYPE 写死的；先确认一下再继续。"

  say
  say "== 真源路径（工具链现在用的） =="
  if has_space "$SRC"; then
    say "  $SRC"
    say "  ↑ **路径里有空格** —— 这就是要治的病"
  else
    say "  ${SRC}（没有空格；那其实不需要这个脚本了）"
  fi
  if [ -d "$SRC/$SENTINEL_REL" ]; then
    say "  $SENTINEL_REL: 在 ✅"
  else
    say "  $SENTINEL_REL: **看不到** ❌（真源没挂，或依赖被搬走了）"
  fi

  say
  say "== 无空格挂载点 =="
  say "  $MOUNT_POINT"
  if has_space "$MOUNT_POINT"; then
    say "  ↑ **挂载点自己带空格** —— 换了等于没换 ❌"
  else
    say "  挂载点无空格 ✅"
  fi

  if [ -e "$MOUNT_POINT" ] && [ ! -d "$MOUNT_POINT" ]; then
    say "  挂载点位置上是个**文件**，不是目录 ❌"
  elif is_mounted_at "$MOUNT_POINT"; then
    rec="$(recorded_mount_path "$MOUNT_POINT")"
    say "  已挂载 ✅：$(mount_line_of "$rec")"
    [ "$rec" != "$MOUNT_POINT" ] && say "  （挂载表记的是物理路径 ${rec} —— 你那条路径中间有软链，磁盘层面看的是它）"
    # 是不是同一个卷：比设备节点（同一个卷两次挂载时会拿到同一个 disk 节点）
    line="$(mount_line_of "$rec")"
    case "$line" in
      */dev/$V_DEVID\ on*) say "  挂的是**同一个卷**（${V_DEVID}）✅" ;;
      *) warn "挂在这个挂载点上的**不是** ${V_DEVID}，而是别的卷 —— 先看看这是谁" ;;
    esac
    if [ -d "$MOUNT_POINT/$SENTINEL_REL" ]; then
      say "  $SENTINEL_REL: 看得见 ✅"
      say
      say "结论：这条路已经通了。工具链路径例如"
      say "  ANDROID_SDK_ROOT=$MOUNT_POINT/$SENTINEL_REL"
    else
      say "  $SENTINEL_REL: **看不到** ❌（挂上了但不是那块盘，或者依赖不在顶层）"
    fi
  elif [ -d "$MOUNT_POINT" ]; then
    say "  目录在，但**不是挂载点**（普通目录）"
    if [ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]; then
      say "  而且里面**已经有别人的东西** ⚠️ 挂上去会被盖住 —— 先清空或换挂载点"
    fi
    say "  → 要挂：sudo tool/mount-ssd-space-free.sh"
  else
    say "  目录还不存在（挂载那一步会自动建）"
  fi

  say
  say "== 备注 =="
  say "  * 本脚本**没有**在本机验证过挂载那一步（这台机器没有 sudo 权限）。"
  say "  * \`diskutil mount\` 在卷已挂载时会**打印 \"Volume … mounted\" 并返回 0，但其实什么都没做** ——"
  say "    所以判断成败一律看挂载表，不看它的输出和退出码。"
}

# ── 模式：--unmount（卸这个别名挂载点） ──────────────────────────────────────
mode_unmount() {
  require_root "卸载"
  assert_real_mount "$MOUNT_POINT"

  say "正在卸载 $MOUNT_POINT …"
  if ! diskutil unmount "$MOUNT_POINT"; then
    die_with_hint \
      "卸载失败 —— 有程序正占着这个挂载点" \
      "把上面的报错（尤其 'dissented by PID …' 那些 PID）贴出来，先关掉占着它的程序再试。注意：**不要**去卸真源 ${SRC}，仓库正在那上面跑。"
  fi
  is_mounted_at "$MOUNT_POINT" && die_with_hint \
    "diskutil 说卸了，但挂载表里还在 $MOUNT_POINT" \
    "别信 diskutil 的话，先手工 mount | grep '$MOUNT_POINT' 看真实情况再决定。"
  say "已卸载。真源 ${SRC} 不受影响。"
}

# ── root 检查 ────────────────────────────────────────────────────────────────
require_root() { # $1 = 要干的事
  [ "$(id -u)" -eq 0 ] && return 0
  die_with_hint \
    "$1 需要 root（挂载/卸载/写 /etc/fstab 都是系统动作）" \
    "用 sudo 跑同一条命令，例如：sudo tool/mount-ssd-space-free.sh"
}

# ── 模式：挂载（默认） ───────────────────────────────────────────────────────
mode_mount() {
  require_root "挂载"

  fatal_space "$MOUNT_POINT"
  read_volume_facts

  # 幂等：已经挂在目标挂载点上，直接过
  if is_mounted_at "$MOUNT_POINT"; then
    if [ -d "$MOUNT_POINT/$SENTINEL_REL" ]; then
      say "已经挂好了：${MOUNT_POINT}（${V_DEVID}）—— 什么都不用做。"
      say "工具链路径：$MOUNT_POINT/$SENTINEL_REL"
    else
      die_with_hint \
        "$MOUNT_POINT 是挂载点，但看不到 $SENTINEL_REL" \
        "挂在上面的可能不是那块盘。跑 tool/mount-ssd-space-free.sh --check 看清楚。"
    fi
    return 0
  fi

  # 挂载点位置上不能有别人的东西（会被盖住，而且盖住之后你看不见自己删了什么）
  if [ -e "$MOUNT_POINT" ] && [ ! -d "$MOUNT_POINT" ]; then
    die_with_hint "$MOUNT_POINT 是个文件，不是目录" "删掉它或换一个 --mount-point。"
  fi
  if [ -d "$MOUNT_POINT" ] && [ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]; then
    die_with_hint \
      "挂载点 $MOUNT_POINT 里已经有东西了（非空目录）" \
      "挂上去会把里面的内容盖住。先清空这个目录，或用 --mount-point 换一个空目录。"
  fi
  [ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT" || die_with_hint \
    "建不了挂载点目录 $MOUNT_POINT" "检查父目录权限；或换 --mount-point。"

  # 路径里的空格就是病根，走到这一步必须确认它真的许给了工具链
  real="$(cd "$MOUNT_POINT" && pwd -P)"
  fatal_space "$real"

  # **关键事实**（本机实测）：卷已经挂在别处时，`mount_apfs` 拒绝第二次挂载
  #   rc=75  mount_apfs: volume could not be mounted: Operation already in progress
  # 所以要先把它从默认位置卸下来 —— 而卸载很可能被"正在使用"顶回来。
  if [ -n "$V_MOUNT" ] && [ "$V_MOUNT" != "$MOUNT_POINT" ]; then
    say "卷现在挂在 ${V_MOUNT}，要改挂到 ${MOUNT_POINT}，先卸载 …"
    # 提醒一件事：本脚本自己就在这块盘上（仓库在 $SRC 里），终端 cwd 也常常在这块盘上。
    # 卸载会因为"正在使用"失败 —— 那不是脚本坏了，是顺序问题。
    say "（提示：这是把盘整个卸下来再挂到别处。如果卸载失败，先把终端 cd 到盘外、"
    say "  关掉从 ${SRC} 出发的编辑器和构建进程 —— **别硬来**，这块盘是本项目的真源。）"
    if ! diskutil unmount "$V_MOUNT"; then
      die_with_hint \
        "卸载 $V_MOUNT 失败 —— 有程序正占着它（很可能就是你自己：仓库、编辑器、终端 cwd、本脚本所在的仓库都在这块盘上）" \
        "关掉从 $SRC 出发的终端/编辑器/构建进程（cd 到别处再关），确认 lsof +D \"$SRC\" 只剩系统进程后重试。**别硬来**：这是本项目的真源盘，卸不干净会让正在跑的东西出错。"
    fi
  fi

  say "挂载中：UUID=$VOLUME_UUID → $MOUNT_POINT"
  # 只用 UUID + -mountPoint，不用设备节点：节点名会随插拔变
  diskutil mount -mountPoint "$MOUNT_POINT" "$VOLUME_UUID" >/dev/null 2>&1

  # ⚠️ 不看上面那条命令的退出码和输出：本机实测它在"卷已挂载"时**打印 mounted 且返回 0**。
  # 唯一的判据是挂载表 —— 这也是"过期状态比没有状态更坏"在这里的具体含义。
  if ! is_mounted_at "$MOUNT_POINT"; then
    # 挂不上就尽量把真源恢复到默认位置，别把盘留在"哪儿都没挂"的状态
    if [ -n "$V_MOUNT" ] && [ "$V_MOUNT" != "$MOUNT_POINT" ] && ! is_mounted_at "$V_MOUNT"; then
      warn "挂载失败，正在把卷恢复到 $V_MOUNT …"
      diskutil mount "$VOLUME_UUID" >/dev/null 2>&1 || true
      if is_mounted_at "$V_MOUNT"; then
        warn "已恢复到 $V_MOUNT"
      else
        # 这是最坏的情况：真源既没挂在原处、也没挂在新处 —— 仓库整个"看不见"了
        warn "回不去 ${V_MOUNT} 了！先确认盘还在不在：diskutil list"
        warn "手工恢复：diskutil mount $VOLUME_UUID   （不带 -mountPoint 时会挂回 ${V_MOUNT}）"
      fi
    fi
    die_with_hint \
      "挂载**没有生效**（${MOUNT_POINT} 不在挂载表里）" \
      "把 \`diskutil mount -mountPoint '$MOUNT_POINT' $VOLUME_UUID\` 的完整输出贴出来（脚本把它的输出吞了，手工再跑一次）。可能原因：APFS 不允许同一个卷挂两处、或这个系统版本不支持 -mountPoint。备选做法见 docs/dev-environment.md「挂不了 / 没权限时用这几条」。"
  fi

  if [ ! -d "$MOUNT_POINT/$SENTINEL_REL" ]; then
    die_with_hint \
      "挂上了，但 $MOUNT_POINT/$SENTINEL_REL 看不到" \
      "挂的可能是空卷或别的卷。跑 tool/mount-ssd-space-free.sh --check 看清楚；实在不行 --unmount 把别名摘掉。"
  fi

  # 卸了旧的、挂上新的之后，回头确认真源那条路也还在 —— 不在就当面说破，
  # 别让人过两天才发现自己一直在看一个"过期状态"
  if [ -n "$V_MOUNT" ] && [ "$V_MOUNT" != "$MOUNT_POINT" ] && ! is_mounted_at "$V_MOUNT"; then
    warn "注意：${V_MOUNT} 现在**没有**挂载（卷只挂在新挂载点上）。"
    warn "  硬编码真源路径的 tool/dev-env.sh、verify.sh、tool/workbench.mjs、tool/asset-check.mjs 会红。"
    warn "  要么把它们指到 ${MOUNT_POINT}，要么先别用 --fstab 持久化（见 --fstab 的说明）。"
  fi

  say "成功："
  rec="$(recorded_mount_path "$MOUNT_POINT")"
  say "  $(mount_line_of "$rec")"
  if [ "$rec" != "$MOUNT_POINT" ]; then
    # 软链当挂载点会走到这里：挂载表记的是物理路径。不是故障，但必须说出来 ——
    # 以后有人 grep 挂载表找 $MOUNT_POINT 时会一无所获。
    say "  注意：挂载表记的是物理路径 ${rec}（你给的 $MOUNT_POINT 中间有软链）。"
    say "  $MOUNT_POINT 这条路上照样看得见卷里的东西。"
  fi
  say "  工具链路径（无空格）：$MOUNT_POINT/$SENTINEL_REL"
  say
  say "接下来要人做的一件事（脚本不替你做）："
  say "  把 ANDROID_SDK_ROOT 指到新路径之后跑一次真构建，看 AAB 那句误报还在不在："
  say "    source tool/dev-env.sh"
  say "    cd app && flutter build appbundle --release"
  say "  退出码 0 且不再打印 \"failed to strip debug symbols\" = 这个坑真的平了。"
  say "  重启后会掉（除非用 --fstab），届时重跑本脚本即可。"
}

# ── 模式：--fstab（重启后仍然挂上） ──────────────────────────────────────────
# 依据：`man diskarbitrationd` —— "/etc/fstab is consulted for user-defined mount points,
# indexed by filesystem, in the mount point determination for a filesystem. Each filesystem
# can be identified by its UUID or by its label" （见 `man fstab` 的 EXAMPLES）。
# 所以那一行的第一列**只能**写 UUID= 或 LABEL=（man 里明说 APFS 卷不要写块设备）。
#
# ⚠️ 两个**没在本机验证**的点，别当成已知：
#   (1) 生效之后，卷是**只**挂到你指定的挂载点、还是仍然同时出现在 /Volumes 下 —— 没验证。
#       如果它只在 ~/HARNESS/ssd，那 /Volumes/Elliot's SSD 会消失，硬编码真源的那些脚本
#       （`tool/dev-env.sh`、`verify.sh`、`tool/workbench.mjs`、`tool/asset-check.mjs`）
#       就会一起红。所以这一步别和 --mount 一起做，分开试。
#   (2) 卸掉这一行之后行为是否立刻恢复 —— 也没验证。
mode_fstab() {
  fatal_space "$MOUNT_POINT"
  entry="UUID=${VOLUME_UUID} ${MOUNT_POINT} ${FSTYPE} rw"

  say "要写进 /etc/fstab 的那一行（UUID 是真值，挂载点无空格）："
  say "  $entry"
  say
  say "写法出处：\`man diskarbitrationd\` 明说 /etc/fstab 被用于 user-defined mount points；"
  say "\`man fstab\` 明说 APFS 卷**不要**写块设备节点、只用 UUID 或 LABEL。"
  say
  say "⚠️ 本机**没有**验证过这一行 —— 包括'卷会不会只挂在挂载点、/Volumes 下就没了'。"
  say "   先只做 --mount（要不要 /etc/fstab 另说），确认工具链真的通了再考虑持久化。"
  say

  if [ ! -f /etc/fstab ]; then
    say "/etc/fstab 现在**不存在**（本机就是这样，不影响：这是个空文件即默认的系统）。"
  else
    say "当前 /etc/fstab 内容："
    sed 's/^/    /' /etc/fstab
    if grep -qF "$VOLUME_UUID" /etc/fstab; then
      say
      say "里面已经有这个 UUID 的条目了 —— **别重复写**，先看上面那行是不是你想要的。"
      return 0
    fi
  fi

  [ "$(id -u)" -eq 0 ] || die_with_hint \
    "写 /etc/fstab 需要 root（现在只是打印，没写）" \
    "想真的写：sudo tool/mount-ssd-space-free.sh --fstab；不想动系统文件就把上面那行手工加进去（用 sudo vifs）。"
  [ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT"

  # 用 vifs 而不是 >>/etc/fstab：man fstab 明说这个文件该由 vifs(8) 维护。
  # vifs 是交互的（像 vi），所以这里不自动改 —— 自动改一个系统文件、还改错了，
  # 是这个脚本最不该做的事。
  die_with_hint \
    "不自动改 /etc/fstab（刻意留给你手动，见下）" \
    "跑 \`sudo vifs\`，把上面那一行加进 /etc/fstab（开机会自动挂上）。要撤销就删掉那一行、重启或 diskutil unmount '$MOUNT_POINT'。"
}

# ── 入口 ─────────────────────────────────────────────────────────────────────
usage() {
  sed -n '/^# 用法/,/^#   MOUNT_POINT/p' "$0" | sed 's/^# \{0,1\}//'
  say ""
  say "环境变量：SRC=<真源路径>  MOUNT_POINT=<无空格挂载点>"
}

MODE="mount"
while [ $# -gt 0 ]; do
  case "$1" in
    --check)       MODE="check" ;;
    --unmount)     MODE="unmount" ;;
    --fstab)       MODE="fstab" ;;
    --mount-point) shift; [ $# -gt 0 ] || die "--mount-point 后面要跟一个路径"; MOUNT_POINT="$1" ;;
    -h|--help)     usage; exit 0 ;;
    *) die_with_hint "不认识的参数：$1" "跑 tool/mount-ssd-space-free.sh --help 看用法。" ;;
  esac
  shift
done

case "$MODE" in
  check)   mode_check ;;
  unmount) mode_unmount ;;
  fstab)   mode_fstab ;;
  mount)   mode_mount ;;
esac
