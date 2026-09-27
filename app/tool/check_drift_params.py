#!/usr/bin/env python3
"""练了么 · drift 数据类必填参数检查

用法：python3 tool/check_drift_params.py

为什么需要这个脚本
------------------
drift 的 `withDefault()` **只给 SQL 层加 DEFAULT**，Dart 数据类里那个字段**仍然是 `required`**。
所以 `XxxData(...)` 少传一个带默认值的列，就会编译失败：

    error • The named parameter 'isPr' is required, but there's no corresponding argument

这个错我犯过**两次**（先是 `SetRecordData.isPr`，后是 `UserProfileData.unitPref`），
而两次都是跑完测试才发现的。所以把它变成脚本，不再靠记性。

做法：从生成文件 `db.g.dart` 读出每个 `XxxData` 的必填参数，
再去所有源码里找 `XxxData(...)` 的调用点，比对命名参数是否齐全。
**必须在代码生成之后跑**（脚本会自己检查生成文件是否落后于 `db.dart`）。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # app/
DB = ROOT / "lib" / "data" / "db.dart"
GEN = ROOT / "lib" / "data" / "db.g.dart"


def main() -> int:
    if not DB.exists():
        print("源码里没有 lib/data/db.dart，跳过")
        return 0
    if not GEN.exists():
        print("还没有 lib/data/db.g.dart —— 先跑 dart run build_runner build（跳过检查）")
        return 0

    if GEN.stat().st_mtime < DB.stat().st_mtime:
        print("⚠ db.g.dart 比 db.dart 旧 —— 先跑 dart run build_runner build")
        print("  （否则这次检查可能看不到新加的表）")
        return 0

    generated = GEN.read_text(encoding="utf-8")

    # 1) 解析每个 Data 类的必填参数
    required: dict[str, set[str]] = {}
    for m in re.finditer(r"const (\w+Data)\(\s*\{([^}]*)\}\)", generated, re.S):
        required[m.group(1)] = set(re.findall(r"required this\.(\w+)", m.group(2)))

    if not required:
        print("生成文件里没解析出任何 Data 类 —— drift 版本可能变了，请检查本脚本")
        return 1

    # 2) 在源码里逐调用点比对
    sources = [
        p
        for p in list((ROOT / "lib").rglob("*.dart")) + list((ROOT / "test").rglob("*.dart"))
        if ".tmpdir" not in str(p) and not str(p).endswith(".g.dart")
    ]

    problems: list[str] = []
    checked = 0
    for path in sources:
        src = path.read_text(encoding="utf-8")
        for cls, need in required.items():
            for m in re.finditer(r"\b" + cls + r"\(", src):
                # 从 '(' 扫到配平的 ')'
                i, depth = m.end(), 1
                while i < len(src) and depth:
                    if src[i] == "(":
                        depth += 1
                    elif src[i] == ")":
                        depth -= 1
                    i += 1
                given = set(re.findall(r"(\w+)\s*:", src[m.end() : i]))
                checked += 1
                missing = need - given
                if missing:
                    line = src[: m.start()].count("\n") + 1
                    rel = path.relative_to(ROOT)
                    problems.append(
                        f"{rel}:{line}  {cls} 缺必填参数: {', '.join(sorted(missing))}"
                    )

    if problems:
        print(f"✗ {len(problems)} 处 Data 调用缺必填参数（会编译失败）：")
        for p in problems:
            print(f"    {p}")
        print()
        print("  提醒：带 withDefault() 的列在 Dart 数据类里仍然是 required。")
        return 1

    print(f"✓ {len(required)} 个 drift 数据类、{checked} 处调用点，必填参数都齐了")
    return 0


if __name__ == "__main__":
    sys.exit(main())
