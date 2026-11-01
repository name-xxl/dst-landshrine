#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把工作目录里的 mod 以「目录联接（junction）」的方式挂进游戏 mods 目录，
这样在工作目录里改代码，游戏里立刻生效，不需要来回复制。

⚠ 这个脚本会写入游戏安装目录（游戏目录之外），请按需自行执行。

用法：
    python tools/install_dev_link.py            # 创建（或确认已存在）
    python tools/install_dev_link.py --status   # 只看状态
    python tools/install_dev_link.py --remove   # 移除联接（只删除联接，不会删除工作目录）

安全约定：
    * 只有当目标路径不存在、或已是指向本 mod 的联接时才动手
    * 目标路径若是一个真实目录（可能放着别的 mod），一律拒绝操作并提示
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

MOD_SRC = Path(__file__).resolve().parent.parent
GAME_MODS = Path(r"D:\SteamLibrary\steamapps\common\Don't Starve Together\mods")


def link_state(dst: Path) -> str:
    """返回：missing / linked / other"""
    if not dst.exists() and not os.path.islink(dst):
        return "missing"
    try:
        if os.path.realpath(dst) == os.path.realpath(MOD_SRC):
            return "linked"
    except OSError:
        pass
    return "other"


def create_junction(src: Path, dst: Path) -> None:
    import _winapi  # 仅 Windows 可用

    _winapi.CreateJunction(str(src), str(dst))


def main() -> int:
    args = set(sys.argv[1:])
    dst = GAME_MODS / MOD_SRC.name

    if not GAME_MODS.is_dir():
        print(f"[错误] 找不到游戏 mods 目录：{GAME_MODS}")
        print("       请修改本脚本顶部的 GAME_MODS 为你的实际安装路径。")
        return 1

    state = link_state(dst)
    print(f"工作目录：{MOD_SRC}")
    print(f"游戏目录：{dst}")
    print(f"当前状态：{state}")

    if "--status" in args:
        return 0

    if "--remove" in args:
        if state == "linked":
            os.rmdir(dst)  # 只删除联接，不删除目标内容
            print("[完成] 已移除联接（工作目录内容未受影响）")
            return 0
        print("[跳过] 当前不是指向本 mod 的联接，未做任何改动")
        return 1

    if state == "linked":
        print("[完成] 联接已存在，无需重复创建")
        return 0

    if state == "other":
        print("[拒绝] 目标路径已存在且不是指向本 mod 的联接。")
        print("       请先自行确认该目录里是什么，再决定是否删除。脚本不会动它。")
        return 1

    try:
        create_junction(MOD_SRC, dst)
    except Exception as e:  # noqa: BLE001
        print(f"[失败] 创建联接出错：{e}")
        print("       可改用管理员权限，或手动执行：")
        print(f'       mklink /J "{dst}" "{MOD_SRC}"')
        return 1

    print("[完成] 已创建联接。现在可以在游戏「模组」菜单里启用「土地庙传送」。")
    return 0


if __name__ == "__main__":
    sys.exit(main())