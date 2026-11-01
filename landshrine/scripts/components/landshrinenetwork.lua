--[[
    土地庙网络（世界级组件，仅服务端）
    职责：
      1) 登记每座土地庙占用的地形槽（每种地形全档只能有一座）
      2) 把「已占用的地形槽」压缩成一个字符串，推送给所有玩家的 landshrinesync 组件
         —— 客机的放置器靠它把幽灵变红，服务端的 canbuild 才是权威判定
]]

local LandShrineNetwork = Class(function(self, inst)
    self.inst = inst
    self.shrines = {}     -- [shrine] = true
    self.occupied = {}    -- [地形槽 key] = shrine
    self.published = nil  -- 上次推送的字符串，避免重复推送

    -- 开局后自动往日志里写一行本局状态：
    -- 这样每次退出重进都能直接从日志核对「庙还在不在、槽位还占不占、激活态保没保住」，
    -- 不需要手动敲调试命令。新世界没有庙就不打印，避免噪音。
    inst:DoTaskInTime(5, function()
        if inst:IsValid() and next(self.shrines) ~= nil then
            print(self:GetDebugString())
        end
    end)
end)

--------------------------------------------------------------------------

function LandShrineNetwork:Register(shrine)
    if shrine == nil or self.shrines[shrine] ~= nil then
        return
    end
    self.shrines[shrine] = true

    local comp = shrine.components.landshrine
    local key = comp ~= nil and comp.terrainkey or nil
    if key ~= nil then
        local other = self.occupied[key]
        if other ~= nil and other ~= shrine and other:IsValid() then
            print(string.format("[土地庙] 地形槽冲突：槽 %s 已有土地庙 %s", tostring(key), tostring(other)))
        end
        self.occupied[key] = shrine
    end

    shrine._landshrine_network_onremove = function()
        self:Unregister(shrine)
    end
    self.inst:ListenForEvent("onremove", shrine._landshrine_network_onremove, shrine)

    self:Publish()
end

function LandShrineNetwork:Unregister(shrine)
    if shrine == nil or self.shrines[shrine] == nil then
        return
    end
    self.shrines[shrine] = nil

    if shrine._landshrine_network_onremove ~= nil then
        self.inst:RemoveEventCallback("onremove", shrine._landshrine_network_onremove, shrine)
        shrine._landshrine_network_onremove = nil
    end

    for key, other in pairs(self.occupied) do
        if other == shrine then
            self.occupied[key] = nil
        end
    end

    self:Publish()
end

function LandShrineNetwork:OnRemoveFromEntity()
    for shrine in pairs(self.shrines) do
        shrine._landshrine_network_onremove = nil
    end
    self.shrines = {}
    self.occupied = {}
end

--------------------------------------------------------------------------

function LandShrineNetwork:IsKeyOccupied(key)
    local shrine = self.occupied[key]
    return shrine ~= nil and shrine:IsValid()
end

-- 玩家是否站在某座「已激活」的土地庙旁边（地图传送的硬性前置条件）
function LandShrineNetwork:IsPlayerAtActivatedShrine(player, radius)
    if player == nil or not player:IsValid() then
        return false
    end

    for shrine in pairs(self.shrines) do
        if shrine:IsValid() then
            local comp = shrine.components.landshrine
            if comp ~= nil and comp.activated and player:IsNear(shrine, radius) then
                return true
            end
        end
    end
    return false
end

local function MoveBodyWithPlayer(ent, x, y, z)
    if ent == nil or not ent:IsValid() then
        return
    end
    if ent.Physics ~= nil then
        ent.Physics:Teleport(x, y, z)
    else
        ent.Transform:SetPosition(x, y, z)
    end
end

-- 传送执行：门禁校验 + 找落点 + 把跟随者/随身随从一起搬过去
-- （搬运这部分照原版木牌传送的做法）
function LandShrineNetwork:TeleportPlayerToShrine(player, shrine)
    if not (player ~= nil and player:IsValid() and shrine ~= nil and shrine:IsValid()) then
        return false, "LANDSHRINE_NOTARGET"
    end

    local tx, ty, tz = shrine.Transform:GetWorldPosition()
    local px, py, pz = player.Transform:GetWorldPosition()

    -- 原版传送门禁：挡住跨越 PvP 竞技场屏障、进出封闭房间（远古圣殿/中庭）等情况
    if not IsTeleportingPermittedFromPointToPoint(px, py, pz, tx, ty, tz) then
        print("[土地庙] 传送被原版门禁拦下（封闭区域或不允许传送的方向）")
        return false, "LANDSHRINE_BLOCKED"
    end

    -- 在庙旁边找一个能站人的落点。
    -- 注意：原版那些 FindWalkableOffset(..., NoHoles) 调用里的 NoHoles 是 componentutil.lua 里的
    -- 局部函数，mod 文件里读不到（strict.lua 会报 "variable 'NoHoles' is not declared"），
    -- 所以这里不传那第七个参数（customcheckfn 允许为 nil）。
    local offset = FindWalkableOffset(Vector3(tx, 0, tz), math.random() * TWOPI, 2, 8, false, true)
    if offset == nil then
        print("[土地庙] 传送失败：目标土地庙旁找不到能站人的落点")
        return false, "LANDSHRINE_NOSPACE"
    end
    tx, tz = tx + offset.x, tz + offset.z

    -- 跟随者（切斯特、宠物、猪人等）
    local leader = player.components.leader
    if leader ~= nil and leader.followers ~= nil then
        for follower in pairs(leader.followers) do
            MoveBodyWithPlayer(follower, tx + 1, 0, tz)
        end
    end

    -- 背包里、以及背包外容器里携带的随从（例如眼骨带来的切斯特）
    local inventory = player.components.inventory
    if inventory ~= nil then
        for _, item in pairs(inventory.itemslots) do
            local item_leader = item.components.leader
            if item_leader ~= nil and item_leader.followers ~= nil then
                for follower in pairs(item_leader.followers) do
                    MoveBodyWithPlayer(follower, tx, 0, tz + 1)
                end
            end
        end

        local container = inventory:GetOverflowContainer()
        if container ~= nil then
            for _, item in pairs(container.slots) do
                local item_leader = item.components.leader
                if item_leader ~= nil and item_leader.followers ~= nil then
                    for follower in pairs(item_leader.followers) do
                        MoveBodyWithPlayer(follower, tx, 0, tz - 1)
                    end
                end
            end
        end
    end

    if player.Physics ~= nil then
        player.Physics:Teleport(tx, 0, tz)
    else
        player.Transform:SetPosition(tx, 0, tz)
    end
    player:PushEvent("teleported")

    -- 防御性清理服务端移动状态。
    -- 正常链路（地图点选）走 crushitemcast_trigger 状态，进入状态时服务端已 locomotor:Stop()，
    -- 这里是冗余的；但 LandShrineDebug.TestTeleport() 绕过状态机直接调本函数，仍需这一步。
    -- Clear 会动到当前 bufferedaction，所以放到下一帧做；ResetPath 与 StopMoving 立即做是安全的。
    local locomotor = player.components.locomotor
    if locomotor ~= nil then
        locomotor:StopMoving()
        locomotor:ResetPath()
        player:DoTaskInTime(0, function()
            local loco = player.components.locomotor
            if loco ~= nil then
                loco:StopMoving()
                loco:Clear()
                loco:ResetPath()
            end
        end)
    end

    print(string.format("[土地庙] 已把 %s 缩地到土地庙 (%.1f, %.1f)", tostring(player), tx, tz))

    return true
end

-- 找离指定玩家最近的一座土地庙（调试用）
function LandShrineNetwork:GetNearestShrine(player)
    if player == nil then
        return nil
    end

    local nearest, mindsq
    for shrine in pairs(self.shrines) do
        if shrine:IsValid() then
            local dsq = player:GetDistanceSqToInst(shrine)
            if mindsq == nil or dsq < mindsq then
                nearest, mindsq = shrine, dsq
            end
        end
    end
    return nearest
end

-- 把占用的地形槽压缩成 "5,6,8" 这样的字符串
function LandShrineNetwork:GetOccupiedString()
    local ids = {}
    for key, shrine in pairs(self.occupied) do
        if shrine:IsValid() then
            table.insert(ids, key)
        end
    end
    table.sort(ids)

    local strs = {}
    for _, id in ipairs(ids) do
        table.insert(strs, tostring(id))
    end
    return table.concat(strs, ",")
end

function LandShrineNetwork:Publish()
    local str = self:GetOccupiedString()
    if str == self.published then
        return
    end
    self.published = str

    for _, player in ipairs(AllPlayers) do
        self:PushToPlayer(player)
    end
end

function LandShrineNetwork:PushToPlayer(player)
    local sync = player ~= nil and player.replica.landshrinesync or nil
    if sync ~= nil then
        sync:SetOccupied(self:GetOccupiedString())
    end
end

--------------------------------------------------------------------------
-- 调试用（控制台入口见 modmain 的 LandShrineDebug）
--------------------------------------------------------------------------

-- 解除全部登记：本次会话内可在同一地形重复建造，便于测试
function LandShrineNetwork:DebugUnregisterAll()
    local list = {}
    for shrine in pairs(self.shrines) do
        table.insert(list, shrine)
    end
    for _, shrine in ipairs(list) do
        self:Unregister(shrine)
    end
    return #list
end

function LandShrineNetwork:DebugActivateAll()
    local n = 0
    for shrine in pairs(self.shrines) do
        local comp = shrine.components.landshrine
        if comp ~= nil and not comp.activated then
            comp:SetActivated(true)
            n = n + 1
        end
    end
    return n
end

function LandShrineNetwork:GetDebugString()
    local count, activated = 0, 0
    for shrine in pairs(self.shrines) do
        count = count + 1
        local comp = shrine.components.landshrine
        if comp ~= nil and comp.activated then
            activated = activated + 1
        end
    end

    local keys = {}
    for key, shrine in pairs(self.occupied) do
        local comp = shrine.components.landshrine
        table.insert(keys, string.format("%s(%s%s)",
            tostring(key),
            shrine:IsValid() and "ok" or "已失效",
            comp ~= nil and (comp.activated and ",已激活" or ",未激活") or ""))
    end
    table.sort(keys)

    -- 没占槽的（例如调试时刷在白名单外的地形上）单独说一声，免得数字对不上
    local noslot = count - #keys

    return string.format("[土地庙] 已登记 %d 座（已激活 %d 座）；占用槽：%s%s；同步字符串：\"%s\"",
        count, activated,
        #keys > 0 and table.concat(keys, ", ") or "无",
        noslot > 0 and string.format("；另有 %d 座未占槽", noslot) or "",
        self:GetOccupiedString())
end

return LandShrineNetwork