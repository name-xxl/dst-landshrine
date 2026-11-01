#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Lua 轻量自检（本机没有 Lua 解释器时的兜底）：

  1) 剥离注释与字符串（含长括号形式），检查 () [] {} 是否配平
  2) 检查块关键字是否配对：function/if/for/while/do 与 end（repeat/until 单独配对）
  3) 环境规则：非 modmain.lua 的文件不得出现 GLOBAL / _G
     —— 这些文件运行在游戏环境并受原版 scripts/strict.lua 的严格全局检查，
        读未声明的全局名会抛 "variable 'X' is not declared"，导致整个 mod 加载失败
  4) 原版局部名规则：非 modmain.lua 的文件里，如果某个名字在原版里只以 local 形式存在
     （例如 NoHoles、ArriveAnywhere），那么 mod 里裸用它会触发 strict.lua 报错。
     这一条是靠扫描 ../原版脚本参考/scripts 建符号表来判定的，结果会缓存到
     tools/vanilla_symbols.json（用 --rebuild-symbols 强制重建）。

用法：python lua_check.py <目录或文件> ...  [--rebuild-symbols]
"""
import json
import re
import sys
from pathlib import Path

LONG_OPEN = re.compile(r"\[(=*)\[")

# 允许使用 GLOBAL 的文件（mod 环境）
ENV_RULE_EXEMPT = {"modmain.lua"}
FORBIDDEN_ENV_NAMES = ("GLOBAL", "_G")

HERE = Path(__file__).resolve().parent
MOD_ROOT = HERE.parent
WORKSPACE = MOD_ROOT.parent
VANILLA_DIR = WORKSPACE / "原版脚本参考" / "scripts"
SYMBOL_CACHE = HERE / "vanilla_symbols.json"

# Lua 关键字与内置名，永远不会被误判
LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if",
    "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
    "self", "assert", "error", "pairs", "ipairs", "next", "print", "type", "tostring", "tonumber",
    "select", "unpack", "rawget", "rawset", "setmetatable", "getmetatable", "pcall", "xpcall",
    "require", "loadstring", "load", "loadfile", "dofile", "collectgarbage", "coroutine", "string",
    "table", "math", "os", "io", "debug", "package", "_G", "_VERSION", "module", "tonumber",
}

RE_LOCAL_FUNC = re.compile(r"^\s*local\s+function\s+([A-Za-z_]\w*)", re.M)
RE_LOCAL_ASSIGN = re.compile(r"^\s*local\s+([A-Za-z_][A-Za-z0-9_, ]*?)\s*=", re.M)
RE_GLOBAL_FUNC = re.compile(r"^function\s+([A-Za-z_]\w*)", re.M)
RE_GLOBAL_ASSIGN = re.compile(r"^([A-Za-z_]\w*)\s*=", re.M)
RE_GLOBAL_DECLARE = re.compile(r"global\(\s*\"([^\"]+)\"")
RE_BARE_IDENT = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)")
RE_DECLARED_IN_FILE = re.compile(
    r"^\s*local\s+function\s+([A-Za-z_]\w*)"                    # local function f
    r"|^\s*local\s+([A-Za-z_][A-Za-z0-9_, ]*?)\s*="             # local a, b = ...
    r"|^\s*local\s+([A-Za-z_][A-Za-z0-9_, ]*?)\s*$"             # local a, b（没有初始化）
    r"|^\s*function\s+([A-Za-z_]\w*)\s*[:.]"                    # function Table:Method（Table 是本地表）
    r"|^\s*function\s+([A-Za-z_]\w*)\s*\("                      # function GlobalName(
    , re.M)
RE_PARAMS = re.compile(r"function\s*[\w.:]*\s*\(([^)]*)\)")     # 函数参数
RE_FOR_VARS = re.compile(r"\bfor\s+([A-Za-z_][\w\s,]*?)\s*(?:in|=)")  # for 循环变量


def strip_lua(code: str) -> str:
    """把注释与字符串替换为占位（保留换行以维持行号感）。"""
    out = []
    i, n = 0, len(code)
    while i < n:
        c = code[i]

        # 长注释 --[[ ... ]] / --[==[ ... ]==]
        if code.startswith("--", i):
            m = LONG_OPEN.match(code, i + 2)
            if m:
                eq = m.group(1)
                closer = "]" + eq + "]"
                j = code.find(closer, m.end())
                if j == -1:
                    out.append("--UNTERMINATED-LONG-COMMENT")
                    break
                out.append("\n" * code.count("\n", i, j + len(closer)))
                i = j + len(closer)
                continue
            j = code.find("\n", i)
            if j == -1:
                break
            out.append("\n")
            i = j + 1
            continue

        # 长字符串 [[ ... ]]
        m = LONG_OPEN.match(code, i)
        if m:
            eq = m.group(1)
            closer = "]" + eq + "]"
            j = code.find(closer, m.end())
            if j == -1:
                out.append('"UNTERMINATED-LONG-STRING"')
                break
            out.append('""' + "\n" * code.count("\n", i, j + len(closer)))
            i = j + len(closer)
            continue

        # 普通字符串
        if c in "\"'":
            j = i + 1
            while j < n:
                if code[j] == "\\":
                    j += 2
                    continue
                if code[j] == c:
                    break
                if code[j] == "\n":
                    out.append('"UNTERMINATED-STRING"')
                    break
                j += 1
            out.append('""')
            i = j + 1
            continue

        out.append(c)
        i += 1
    return "".join(out)


def build_vanilla_symbols() -> dict:
    """扫描原版脚本，收集「只以 local 形式存在的名字」与「原版全局名」。"""
    if not VANILLA_DIR.is_dir():
        return {}

    vanilla_locals: set[str] = set()
    vanilla_globals: set[str] = set()

    files = sorted(VANILLA_DIR.rglob("*.lua"))
    for f in files:
        try:
            text = f.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        for m in RE_LOCAL_FUNC.finditer(text):
            vanilla_locals.add(m.group(1))
        for m in RE_LOCAL_ASSIGN.finditer(text):
            for name in m.group(1).split(","):
                name = name.strip()
                if name:
                    vanilla_locals.add(name)

        for m in RE_GLOBAL_FUNC.finditer(text):
            vanilla_globals.add(m.group(1))
        for m in RE_GLOBAL_ASSIGN.finditer(text):
            vanilla_globals.add(m.group(1))
        for m in RE_GLOBAL_DECLARE.finditer(text):
            vanilla_globals.add(m.group(1))

    data = {
        "file_count": len(files),
        "only_local": sorted(vanilla_locals - vanilla_globals),
        "globals": sorted(vanilla_globals),
    }
    try:
        SYMBOL_CACHE.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass
    return data


def build_modenv_names() -> list[str]:
    """从 modutil.lua 里收集「mod 环境」里直接可用的名字（AddRecipe2、Asset、Ingredient…）"""
    names: set[str] = set()
    modutil = VANILLA_DIR / "modutil.lua"
    if modutil.is_file():
        try:
            text = modutil.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return []
        for m in re.finditer(r"\benv\.([A-Za-z_]\w*)\s*=", text):
            names.add(m.group(1))
    return sorted(names)


def load_vanilla_symbols(rebuild: bool = False) -> dict:
    if not rebuild and SYMBOL_CACHE.is_file():
        try:
            data = json.loads(SYMBOL_CACHE.read_text(encoding="utf-8"))
            if "globals" in data:
                data["modenv"] = build_modenv_names()
                return data
        except (OSError, json.JSONDecodeError):
            pass
    print(f"（首次运行：正在扫描原版脚本建立符号表 {VANILLA_DIR} …）")
    data = build_vanilla_symbols()
    data["modenv"] = build_modenv_names()
    return data


def check_modmain_globals(clean: str, vanilla_globals: set, modenv: set) -> list[str]:
    """modmain 运行在「mod 环境」里：裸读原版全局会得到 nil（不是报错），调用它就直接崩。
    所以 modmain 里凡是原版全局名都必须写成 GLOBAL.xxx。"""
    if not vanilla_globals:
        return []

    declared = declared_names_in(clean)
    offenders = set()
    for m in RE_BARE_IDENT.finditer(clean):
        name = m.group(1)
        if (name in LUA_KEYWORDS or name in declared
                or name in modenv or name not in vanilla_globals):
            continue
        # 赋值（如 PrefabFiles = {...}）是在往 mod 环境里写变量，属于正常写法
        tail = clean[m.end():m.end() + 3]
        if re.match(r"\s*=[^=]", tail):
            continue
        offenders.add(name)

    if offenders:
        return [
            "modmain 里裸用了原版全局名：" + ", ".join(sorted(offenders)) +
            " —— modmain 运行在 mod 环境，裸读这些名字得到的是 nil（不是报错），一调用就会崩。"
            "请写成 GLOBAL.xxx"
        ]
    return []


def declared_names_in(code: str) -> set[str]:
    """本文件里"声明过"的名字：local 定义、函数名、函数参数、for 循环变量。
    这些名字即使与原版某个局部同名，也是本文件自己的东西，不算误用。"""
    names: set[str] = set()

    for m in RE_DECLARED_IN_FILE.finditer(code):
        for g in m.groups():
            if g:
                for name in g.split(","):
                    name = name.strip()
                    if name:
                        names.add(name)

    for m in RE_PARAMS.finditer(code):
        for name in m.group(1).split(","):
            name = name.strip()
            if name and re.fullmatch(r"[A-Za-z_]\w*", name):
                names.add(name)

    for m in RE_FOR_VARS.finditer(code):
        for name in m.group(1).split(","):
            name = name.strip()
            if name and re.fullmatch(r"[A-Za-z_]\w*", name):
                names.add(name)

    return names


def check_file(path: Path, only_local: set[str], vanilla_globals: set, modenv: set) -> list[str]:
    code = path.read_text(encoding="utf-8")
    clean = strip_lua(code)
    problems = []

    for opener, closer in (("(", ")"), ("[", "]"), ("{", "}")):
        if clean.count(opener) != clean.count(closer):
            problems.append(
                f"{opener}{closer} 不配平：{clean.count(opener)} 个 {opener} / {clean.count(closer)} 个 {closer}"
            )

    openers = 0
    closers = 0
    pending_loop_do = False
    for m in re.finditer(r"\b(function|if|for|while|do|repeat|end|until)\b", clean):
        kw = m.group(1)
        if kw in ("function", "if", "repeat"):
            openers += 1
        elif kw in ("for", "while"):
            openers += 1
            pending_loop_do = True
        elif kw == "do":
            if pending_loop_do:
                pending_loop_do = False
            else:
                openers += 1
        else:
            closers += 1
    if openers != closers:
        problems.append(f"块关键字不配对：开 {openers} 个 / 关 {closers} 个（end/until）")

    for marker in ("UNTERMINATED-LONG-COMMENT", "UNTERMINATED-LONG-STRING", "UNTERMINATED-STRING"):
        if marker in clean:
            problems.append(f"存在未闭合：{marker}")

    if path.name not in ENV_RULE_EXEMPT:
        for name in FORBIDDEN_ENV_NAMES:
            if re.search(r"(?<!\w)" + re.escape(name) + r"(?!\w)", clean):
                problems.append(
                    f"出现了 {name}：本文件运行在游戏环境里并受原版 strict.lua 严格检查，"
                    f"读取 {name} 会报 \"variable '{name}' is not declared\"，导致 mod 加载失败。"
                    f"需要的依赖请在 modmain.lua 里注入（参考 landshrine_config.lua 的 Init）"
                )

        # 原版局部名检查
        if only_local:
            declared = declared_names_in(clean)
            used = set()
            for m in RE_BARE_IDENT.finditer(clean):
                name = m.group(1)
                if name in LUA_KEYWORDS or name in declared:
                    continue
                # 排除 as-table-key / assignment（形如  name = ...）
                tail = clean[m.end():m.end() + 3]
                if re.match(r"\s*=[^=]", tail):
                    continue
                used.add(name)

            bad = sorted(used & only_local)
            if bad:
                problems.append(
                    "使用了原版里只以 local 形式存在的名字：" + ", ".join(bad) +
                    " —— mod 文件读不到它们，strict.lua 会报 \"variable 'X' is not declared\"。"
                    "请在原版源码里确认它们的定义（例如 componentutil.lua 的局部函数 NoHoles），"
                    "改传 nil 或用自己的实现"
                )

    if path.name == "modmain.lua":
        problems.extend(check_modmain_globals(clean, vanilla_globals, modenv))

    return problems


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    rebuild = "--rebuild-symbols" in sys.argv

    symbols = load_vanilla_symbols(rebuild)
    only_local = set(symbols.get("only_local", []))
    vanilla_globals = set(symbols.get("globals", []))
    modenv = set(symbols.get("modenv", []))
    print(f"原版符号表：扫描 {symbols.get('file_count', 0)} 个文件，"
          f"只以 local 存在的名字 {len(only_local)} 个，原版全局名 {len(vanilla_globals)} 个，"
          f"mod 环境名字 {len(modenv)} 个")

    targets = [Path(p) for p in args]
    files: list[Path] = []
    for t in targets:
        if t.is_dir():
            files.extend(sorted(t.rglob("*.lua")))
        else:
            files.append(t)

    bad = 0
    for f in files:
        try:
            problems = check_file(f, only_local, vanilla_globals, modenv)
        except Exception as e:  # noqa: BLE001
            problems = [f"读取失败：{e}"]
        if problems:
            bad += 1
            print(f"[FAIL] {f}")
            for p in problems:
                print(f"       - {p}")
        else:
            print(f"[ ok ] {f}")
    print(f"\n共检查 {len(files)} 个文件，{bad} 个有问题")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())