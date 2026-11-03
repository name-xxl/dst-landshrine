--[[
    landshrine_slots 纯逻辑测试：白名单解析 + 占用槽字符串协议
    用假的 GROUND 表喂数据，不依赖游戏
]]

local Slots = require("landshrine_slots")

-- 假 GROUND：编号照原版风格随意取，只保证唯一
local FAKE_GROUND = {
    GRASS = 1,
    FOREST = 2,
    SAVANNA = 3,
    BRICK = 20,
    TILES = 21,
    BRICK_GLOW = 30,
    TILES_GLOW = 31,
}

local function CollectWarnings()
    local list = {}
    return list, function(msg) table.insert(list, msg) end
end

T.test("白名单：白名单地形映射到自身", function()
    local wl = Slots.BuildWhitelist(FAKE_GROUND, { "GRASS", "FOREST" }, {}, nil)
    T.eq(wl[FAKE_GROUND.GRASS], FAKE_GROUND.GRASS, "GRASS 槽位")
    T.eq(wl[FAKE_GROUND.FOREST], FAKE_GROUND.FOREST, "FOREST 槽位")
    T.eq(wl[FAKE_GROUND.SAVANNA], nil, "未列入的地形不进白名单")
end)

T.test("白名单：别名归并到基础地形", function()
    local wl = Slots.BuildWhitelist(FAKE_GROUND,
        { "BRICK" }, { BRICK_GLOW = "BRICK" }, nil)
    T.eq(wl[FAKE_GROUND.BRICK], FAKE_GROUND.BRICK, "基础地形槽位")
    T.eq(wl[FAKE_GROUND.BRICK_GLOW], FAKE_GROUND.BRICK, "发光版归并到基础地形")
end)

T.test("白名单：未知地形名触发警告且不影响其它项", function()
    local warnings, warn = CollectWarnings()
    local wl = Slots.BuildWhitelist(FAKE_GROUND,
        { "GRASS", "NOT_A_TILE" }, { GHOST_GLOW = "BRICK" }, warn)
    T.eq(wl[FAKE_GROUND.GRASS], FAKE_GROUND.GRASS, "已知地形照常入表")
    T.eq(#warnings, 2, "白名单与别名各警告一次")
end)

T.test("协议：Encode 排序后拼接（同数据必出同字符串）", function()
    T.eq(Slots.Encode({ 8, 5, 6 }), "5,6,8", "乱序输入")
    T.eq(Slots.Encode({ 6, 5, 8 }), "5,6,8", "另一种乱序输入")
    T.eq(Slots.Encode({}), "", "空表")
end)

T.test("协议：Decode 还原为集合", function()
    local keys = Slots.Decode("5,6,8")
    T.ok(keys[5] and keys[6] and keys[8], "三个槽位都在")
    T.eq(keys[7], nil, "不存在的槽位为 nil")
end)

T.test("协议：空串与 nil 解出空表", function()
    T.eq(next(Slots.Decode("")), nil, "空串")
    T.eq(next(Slots.Decode(nil)), nil, "nil")
end)

T.test("协议：非数字段自动跳过", function()
    local keys = Slots.Decode("5,abc,6")
    T.ok(keys[5] and keys[6], "数字段保留")
    T.eq(keys["abc"], nil, "非数字段丢弃")
end)

T.test("协议：Encode/Decode 往返一致", function()
    local origin = { 1, 20, 30 }
    local keys = Slots.Decode(Slots.Encode(origin))
    for _, id in ipairs(origin) do
        T.ok(keys[id], "往返后槽位 " .. id .. " 仍在")
    end
end)
