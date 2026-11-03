--[[
    土地庙：调试入口（控制台执行，注意要切到「远程：」）
      LandShrineDebug.Summary()       查看已登记的土地庙与占用的地形槽
      LandShrineDebug.ActivateAll()   激活全部土地庙
      LandShrineDebug.RemoveNearest() 拆掉离自己最近的土地庙（释放地形槽，不需要锤子）
      LandShrineDebug.ClearSlots()    解除全部槽位注册（本次会话内可重复建）
      LandShrineDebug.TestBuild()     绕过客户端红绿判定，直接在服务端尝试建造一次
                                      —— 用来验证「服务端拒绝且不扣材料」
      LandShrineDebug.TestTeleport()  绕过地图界面直接传送一次（隔离"传送逻辑"与"地图 UI"）

    运行在游戏环境（TheNet / ThePlayer / print 都是原版全局）。
    远程执行的 print 只会写进服务端日志、屏幕上看不到，所以这里同时用
    TheNet:Announce 把结果播到聊天栏，方便在游戏里直接看到。

    modmain 里用 GLOBAL.LandShrineDebug = require("landshrine_debug") 挂到控制台。
]]

local LandShrineUtil = require("landshrine_util")

local function Report(msg)
    print(msg)
    if TheNet ~= nil and TheNet:GetIsServer() then
        TheNet:Announce(msg)
    end
end

-- 取「服务端网络组件 + 当前玩家」；不满足时播报原因并返回 nil
local function GetNetAndPlayer()
    local net = LandShrineUtil.GetNetworkComponent()
    local player = ThePlayer
    if net == nil or player == nil then
        Report("[土地庙] 当前不是主机，或找不到玩家")
        return nil, nil
    end
    return net, player
end

local LandShrineDebug = {}

function LandShrineDebug.Summary()
    local net = LandShrineUtil.GetNetworkComponent()
    Report(net ~= nil and net:GetDebugString() or "[土地庙] 当前不是主机，或网络组件不存在")
end

function LandShrineDebug.ClearSlots()
    local net = LandShrineUtil.GetNetworkComponent()
    if net ~= nil then
        Report(string.format("[土地庙] 已解除 %d 座土地庙的槽位注册（仅本次会话有效）", net:DebugUnregisterAll()))
    else
        Report("[土地庙] 当前不是主机，或网络组件不存在")
    end
end

function LandShrineDebug.ActivateAll()
    local net = LandShrineUtil.GetNetworkComponent()
    if net ~= nil then
        Report(string.format("[土地庙] 已激活 %d 座土地庙", net:DebugActivateAll()))
    else
        Report("[土地庙] 当前不是主机，或网络组件不存在")
    end
end

-- 徒手拆除最近的一座（包括未激活的），用于反复测试地形槽释放
function LandShrineDebug.RemoveNearest()
    local net, player = GetNetAndPlayer()
    if net == nil then
        return
    end

    local shrine = net:GetNearestShrine(player)
    if shrine == nil then
        Report("[土地庙] 附近没有已登记的土地庙")
        return
    end

    local comp = shrine.components.landshrine
    local key = comp ~= nil and comp.terrainkey or nil
    if comp ~= nil then
        comp:BreakShrine(player)
    elseif shrine:IsValid() then
        shrine:Remove()
    end

    Report(string.format("[土地庙] 已拆除最近的土地庙（原占用地形槽：%s）", tostring(key)))
end

-- 绕过客户端判定，直接在服务端跑一次真实的建造流程：
-- 被拒绝时应返回"被服务端拒绝"，且材料前后都可用（证明没扣材料）
function LandShrineDebug.TestBuild()
    local player = ThePlayer
    if player == nil or player.components.builder == nil then
        Report("[土地庙] 请以玩家身份、用「远程：」模式执行这条命令")
        return
    end

    local recipe = "landshrine"
    local builder = player.components.builder
    local x, y, z = player.Transform:GetWorldPosition()
    local pos = Vector3(x, 0, z)

    local before = builder:HasIngredients(recipe)
    local ok, reason = builder:DoBuild(recipe, pos, 0, nil)
    local after = builder:HasIngredients(recipe)

    Report(string.format("[土地庙] 强行建造测试：%s%s；材料可用：建造前=%s → 建造后=%s",
        ok and "成功（已在自己脚下建了一座）" or "被服务端拒绝",
        reason ~= nil and ("，原因 " .. tostring(reason)) or "",
        tostring(before), tostring(after)))
end

-- 绕过地图界面直接触发一次传送：用来隔离"传送逻辑"和"地图 UI"的问题
function LandShrineDebug.TestTeleport()
    local net, player = GetNetAndPlayer()
    if net == nil then
        return
    end

    local shrine = net:GetNearestShrine(player)
    if shrine == nil then
        Report("[土地庙] 附近没有已登记的土地庙")
        return
    end

    local ok, reason = net:TeleportPlayerToShrine(player, shrine)
    Report(string.format("[土地庙] 传送测试：%s%s",
        ok and "成功" or "失败",
        reason ~= nil and ("，原因 " .. tostring(reason)) or ""))
end

return LandShrineDebug
