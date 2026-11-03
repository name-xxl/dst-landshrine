--[[
    离线单元测试运行器（本机 Lua 5.1，不需要游戏）

    用法（仓库任意目录下都行，路径按本文件自身位置解析）：
        lua tools/test/run_tests.lua
    或直接双击 run_tests.cmd（解释器不在 PATH 时先 set LUA_EXE=你的 lua.exe 路径）。

    新增测试文件时：在 tools/test/ 下加 test_xxx.lua（用全局 T 注册用例），
    并把文件名加进下面的 TEST_FILES。
]]

-- 按本文件位置把 mod 的 scripts/ 与 tools/test/ 加进模块搜索路径
local here = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]+$")
package.path = table.concat({
    here .. "/../../scripts/?.lua",
    here .. "/?.lua",
    package.path,
}, ";")

-- 全局测试工具：T.test 注册用例，T.ok / T.eq 断言
T = { tests = {}, passed = 0, failed = 0 }

function T.test(name, fn)
    table.insert(T.tests, { name = name, fn = fn })
end

function T.ok(cond, msg)
    if not cond then
        error(msg or "断言失败：期望为真", 2)
    end
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s：期望 %s，实际 %s",
            msg or "断言失败", tostring(expected), tostring(actual)), 2)
    end
end

local TEST_FILES = {
    "test_slots",
    "test_config",
}

for _, file in ipairs(TEST_FILES) do
    require(file)
end

for _, t in ipairs(T.tests) do
    local ok, err = pcall(t.fn)
    if ok then
        T.passed = T.passed + 1
        print("[PASS] " .. t.name)
    else
        T.failed = T.failed + 1
        print("[FAIL] " .. t.name .. " -> " .. tostring(err))
    end
end

print(string.format("共 %d 项：通过 %d，失败 %d", T.passed + T.failed, T.passed, T.failed))
os.exit(T.failed > 0 and 1 or 0)
