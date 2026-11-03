--[[
    landshrine_config 规则测试：建造校验 ValidateBuildPoint
    注入假的 GROUND / 世界 / 日志，模拟双端共用同一套规则的各种分支
]]

local Config = require("landshrine_config")

local FAKE_GROUND = { GRASS = 1, FOREST = 2, OCEAN = 99 }

-- 当前脚下地形（测试里随时换）
local current_tile = FAKE_GROUND.GRASS

local fake_world = {
    Map = {
        GetTileAtPoint = function(self, x, y, z)
            return current_tile
        end,
    },
}

local function Setup(opts)
    opts = opts or {}
    current_tile = opts.tile or FAKE_GROUND.GRASS
    -- no_ground 模拟"拿不到 GROUND 常量表"（modinfo 之外的退化场景）
    local ground = FAKE_GROUND
    if opts.no_ground then
        ground = nil
    end
    Config:Init({
        GROUND = ground,
        GetWorld = function() return fake_world end,
        Log = function() end,
        Dev = opts.dev or {},
        PortableMapEnabled = true,
    })
end

T.test("校验：白名单地形且槽位空闲 → 放行并返回槽位 key", function()
    Setup()
    local ok, reason, key = Config:ValidateBuildPoint(0, 0, function() return false end)
    T.eq(ok, true, "应放行")
    T.eq(key, FAKE_GROUND.GRASS, "槽位 key 应为当前地形")
end)

T.test("校验：非白名单地形 → 拒绝 TERRAIN", function()
    Setup({ tile = FAKE_GROUND.OCEAN })
    local ok, reason = Config:ValidateBuildPoint(0, 0, function() return false end)
    T.eq(ok, false, "应拒绝")
    T.eq(reason, "LANDSHRINE_TERRAIN", "失败原因")
end)

T.test("校验：槽位被占 → 拒绝 TAKEN", function()
    Setup()
    local ok, reason = Config:ValidateBuildPoint(0, 0, function(key) return key == FAKE_GROUND.GRASS end)
    T.eq(ok, false, "应拒绝")
    T.eq(reason, "LANDSHRINE_TAKEN", "失败原因")
end)

T.test("校验：skip_slot_check 时占槽也放行，但白名单仍生效", function()
    Setup({ dev = { skip_slot_check = true } })
    local ok = Config:ValidateBuildPoint(0, 0, function() return true end)
    T.eq(ok, true, "占槽应放行")

    Setup({ dev = { skip_slot_check = true }, tile = FAKE_GROUND.OCEAN })
    local ok2, reason2 = Config:ValidateBuildPoint(0, 0, function() return true end)
    T.eq(ok2, false, "白名单外仍应拒绝")
    T.eq(reason2, "LANDSHRINE_TERRAIN", "失败原因")
end)

T.test("校验：skip_all_checks 时全部放行", function()
    Setup({ dev = { skip_all_checks = true }, tile = FAKE_GROUND.OCEAN })
    local ok = Config:ValidateBuildPoint(0, 0, function() return true end)
    T.eq(ok, true, "应放行")
end)

T.test("校验：未初始化（拿不到 GROUND）→ 宁可拒绝", function()
    Setup({ no_ground = true })
    T.eq(Config:IsReady(), false, "应处于未就绪")
    local ok, reason = Config:ValidateBuildPoint(0, 0, function() return false end)
    T.eq(ok, false, "应拒绝")
    T.eq(reason, "LANDSHRINE_TERRAIN", "失败原因")

    Setup() -- 还原，避免影响可能追加在后面的用例
end)
