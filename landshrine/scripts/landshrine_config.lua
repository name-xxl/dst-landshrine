--[[
    土地庙：全部可调数值与规则 —— 这是「改数值只改这里」的唯一入口。

    ★ 环境约束（改这个文件前务必读）：
    本文件由 modmain 通过 require 加载，运行在**游戏环境**里，并被原版 scripts/strict.lua
    的严格全局检查约束：读取未声明的全局名会直接报错。
    因此这里**不能**引用 GLOBAL / _G 这类 mod 环境专有的名字，也不要引用运行时新建的全局
    （例如 LANDSHRINE_DEV）。需要用到的外部依赖（GROUND 表、TheWorld、日志函数、调试开关）
    一律由 modmain 在 Init() 里注入。

    * 可改：ALLOWED_TERRAIN / TERRAIN_ALIASES / SHRINE_INGREDIENTS
    * 勿改：下面的 Init 与规则逻辑
]]

local Config = {}

--------------------------------------------------------------------------
-- 地形白名单：白名单内的每种地形，全档只能建一座土地庙
-- 增删地形只需改这里的字符串（未知名字会在加载时打印警告）
--------------------------------------------------------------------------
Config.ALLOWED_TERRAIN = {
    -- 地表（11 种）
    "GRASS",        -- 长草地皮
    "FOREST",       -- 森林地皮
    "SAVANNA",      -- 热带草原地皮
    "DECIDUOUS",    -- 落叶林地皮
    "MARSH",        -- 沼泽地皮
    "ROCKY",        -- 岩石地皮
    "DIRT",         -- 泥土地皮
    "DESERT_DIRT",  -- 沙漠地皮
    "PEBBLEBEACH",  -- 岩石海滩地皮
    "SHELLBEACH",   -- 贝壳海滩地皮
    "METEOR",       -- 月球环形山地皮
    -- 洞穴（7 种）
    "CAVE",         -- 鸟粪地皮
    "UNDERROCK",    -- 洞穴岩石地皮
    "MUD",          -- 泥泞地皮
    "FUNGUS",       -- 真菌地皮（蓝）
    "FUNGUSGREEN",  -- 真菌地皮（绿）
    "FUNGUSRED",    -- 真菌地皮（红）
    "FUNGUSMOON",   -- 变异真菌地皮
    -- 遗迹（3 种）
    "BRICK",        -- 远古地面
    "TILES",        -- 远古瓷砖
    "TRIM",         -- 远古砖雕
}

-- 这些地形归并到基础地形，与基础地形共用同一个槽位
-- （发光版与基础版肉眼几乎一样，分开算会让玩家无法自行验证规则）
Config.TERRAIN_ALIASES = {
    BRICK_GLOW = "BRICK",
    TILES_GLOW = "TILES",
    TRIM_GLOW  = "TRIM",
}

--------------------------------------------------------------------------
-- 建造配方（开发期：便于获取；正式数值后置）
--------------------------------------------------------------------------
Config.SHRINE_INGREDIENTS = {
    { "cutgrass", 1 },
    { "twigs", 1 },
}

-- 随身地图的「购买」配方（在已激活的庙旁通过制作栏制作）
-- 正式提案：金块 × 2 + 纸莎草 × 4 + 齿轮 × 1
Config.PORTABLEMAP_INGREDIENTS = {
    { "cutgrass", 1 },
}

--------------------------------------------------------------------------
-- 运行时依赖：由 modmain 注入，勿手改
--------------------------------------------------------------------------
Config.ground = nil              -- GROUND 常量表
Config.getworld = nil            -- function() -> TheWorld
Config.logfn = nil               -- function(...)
Config.dev = {}                  -- { skip_all_checks = bool, skip_slot_check = bool }
Config.portablemap_enabled = true -- 是否提供随身地图（mod 配置项）

local whitelist = {}       -- [地形 id] = 归并后的槽位 key
local ready = false

function Config:Init(opts)
    opts = opts or {}
    self.ground = opts.GROUND
    self.getworld = opts.GetWorld
    self.logfn = opts.Log
    self.dev = opts.Dev or {}
    self.portablemap_enabled = opts.PortableMapEnabled ~= false
    self:BuildWhitelist()
end

function Config:BuildWhitelist()
    whitelist = {}
    ready = false

    local ground = self.ground
    local logfn = self.logfn
    if ground == nil then
        if logfn ~= nil then
            logfn("[土地庙] 未拿到 GROUND 常量表，地形白名单无法解析")
        end
        return
    end

    local function warn(msg)
        if logfn ~= nil then
            logfn(msg)
        end
    end

    for name, base in pairs(Config.TERRAIN_ALIASES) do
        local id, base_id = ground[name], ground[base]
        if id == nil then
            warn("[土地庙] 未知地形名（别名）：" .. tostring(name))
        elseif base_id == nil then
            warn("[土地庙] 未知地形名（别名目标）：" .. tostring(base))
        else
            whitelist[id] = base_id
        end
    end

    for _, name in ipairs(Config.ALLOWED_TERRAIN) do
        local id = ground[name]
        if id == nil then
            warn("[土地庙] 未知地形名：" .. tostring(name))
        else
            whitelist[id] = id
        end
    end

    ready = true
end

function Config:IsReady()
    return ready
end

--------------------------------------------------------------------------
-- 取某点所属的地形槽 key；返回 nil 表示该地形不在白名单内
function Config:GetTerrainKey(x, z)
    if not ready then
        return nil
    end

    local world = self.getworld ~= nil and self.getworld() or nil
    if x == nil or z == nil or world == nil or world.Map == nil then
        return nil
    end

    return whitelist[world.Map:GetTileAtPoint(x, 0, z)]
end

--------------------------------------------------------------------------
-- 统一的建造校验：客户端（放置幽灵变红）与服务端（权威判定）共用同一套规则
--   is_key_occupied：function(key) -> bool，由调用方提供
--     客户端查「玩家身上的占用表同步数据」，服务端查世界网络组件
-- 返回：ok, 失败原因, 地形槽 key
function Config:ValidateBuildPoint(x, z, is_key_occupied)
    if self.dev.skip_all_checks then
        return true
    end

    if not ready then
        -- 未初始化时宁可拒绝，也不要在日志缺失的情况下悄悄放行
        if self.logfn ~= nil then
            self.logfn("[土地庙] 配置未初始化，跳过建造校验前拒绝本次建造")
        end
        return false, "LANDSHRINE_TERRAIN"
    end

    local key = self:GetTerrainKey(x, z)
    if key == nil then
        return false, "LANDSHRINE_TERRAIN"
    end

    if not self.dev.skip_slot_check and is_key_occupied ~= nil and is_key_occupied(key) then
        return false, "LANDSHRINE_TAKEN"
    end

    return true, nil, key
end

return Config