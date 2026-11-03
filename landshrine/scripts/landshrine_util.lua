--[[
    土地庙：跨端共用的查询工具
    运行在游戏环境（strict.lua 约束），只用原版全局（TheSim / TheWorld 等），
    供 modmain 的建造校验、传送门禁与地图钩子共同使用。
]]

local LandShrineConfig = require("landshrine_config")

local Util = {}

-- 世界网络组件（仅服务端存在；客机拿到 nil 时调用方要自行回退）
function Util.GetNetworkComponent()
    return TheWorld ~= nil and TheWorld.components.landshrinenetwork or nil
end

-- 地图光标附近的土地庙图标实体。
-- 已激活的庙会在地图上挂一个带 landshrineicon tag 的图标实体（跟随庙、穿雾可见）
function Util.FindLandShrineIconAt(x, z)
    return TheSim:FindEntities(x, 0, z, LandShrineConfig.MAP_TARGET_RADIUS,
        { "CLASSIFIED", LandShrineConfig.TAG_MAP_ICON })[1]
end

-- 读图标实体所跟踪的庙。
-- _target 是原版 globalmapiconseeable:TrackEntity 写入的内部字段，
-- 只有服务端能读到（图标是服务端实体）；原版若改字段名只需改这里。
function Util.GetShrineFromMapIcon(icon)
    return icon ~= nil and icon._target or nil
end

-- 玩家是否站在某座已激活的庙旁（双端可用）
function Util.IsAtActivatedShrine(player, radius)
    if player == nil or not player:IsValid() then
        return false
    end

    local net = Util.GetNetworkComponent()
    if net ~= nil then
        -- 服务端：查注册表（便宜且权威）
        return net:IsPlayerAtActivatedShrine(player, radius)
    end

    -- 客机：看附近的庙，读 replica 的激活状态
    local x, y, z = player.Transform:GetWorldPosition()
    for _, v in ipairs(TheSim:FindEntities(x, 0, z, radius, { "landshrine" }, { "INLIMBO" })) do
        local replica = v.replica.landshrine
        if replica ~= nil and replica:IsActivated() then
            return true
        end
    end
    return false
end

-- 随身地图：带着它就不必站在庙旁（连背包里也算）
function Util.HasPortableMap(player)
    if player == nil or not player:IsValid() then
        return false
    end
    local inventory = player.replica.inventory
    return inventory ~= nil and inventory:Has("landshrine_portablemap", 1, true)
end

-- 可以发起缩地的条件：站在已激活的庙旁，或身上带着随身地图
function Util.CanStartTeleport(player)
    return Util.IsAtActivatedShrine(player, LandShrineConfig.TELEPORT_FROM_RADIUS)
        or Util.HasPortableMap(player)
end

return Util
