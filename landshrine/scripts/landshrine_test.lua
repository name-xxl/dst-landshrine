--[[
    土地庙：游戏内场景测试（控制台执行，注意要切到「远程：」）

      LandShrineTest.RunAll()   顺序跑全部场景，聊天栏播报 PASS/FAIL/SKIP 汇总

    与离线单元测试（tools/test/）的分工：
      离线测纯逻辑（协议、白名单、校验规则）；这里测引擎胶水——
      真实建造、激活表现、传送落点、拆庙后槽位释放（实体生命周期，离线测不到）。

    场景会在玩家脚下真实建造一座庙再拆掉，请在安全的测试档里跑。
    运行在游戏环境（TheNet / ThePlayer / print 都是原版全局）。

    modmain 里用 GLOBAL.LandShrineTest = require("landshrine_test") 挂到控制台。
]]

local LandShrineConfig = require("landshrine_config")
local LandShrineUtil = require("landshrine_util")

local results = {}

local function Report(msg)
    print(msg)
    if TheNet ~= nil and TheNet:GetIsServer() then
        TheNet:Announce(msg)
    end
end

local function Record(name, ok, note)
    local status = ok == nil and "SKIP" or (ok and "PASS" or "FAIL")
    table.insert(results, string.format("[%s] %s%s", status, name,
        note ~= nil and (" —— " .. note) or ""))
    return ok == true
end

--------------------------------------------------------------------------
-- 各场景：返回 ok(bool) / nil(跳过), 备注
--------------------------------------------------------------------------

-- 场景 1：真实建造（复用调试入口的强行建造，材料自备）
local function ScenarioBuild(player)
    local builder = player.components.builder
    if builder == nil then
        return nil, "没有 builder 组件"
    end
    if not builder:HasIngredients("landshrine") then
        return nil, "身上材料不够建庙（配方见 config，测试档可先刷材料）"
    end

    local x, y, z = player.Transform:GetWorldPosition()
    local ok, reason = builder:DoBuild("landshrine", Vector3(x, 0, z), 0, nil)
    if not ok then
        -- 脚下地形不在白名单或槽位被占：本次跑不了后续场景，不算失败
        return nil, "建造被拒（" .. tostring(reason) .. "），换个白名单地形再跑"
    end

    local net = LandShrineUtil.GetNetworkComponent()
    local shrine = net ~= nil and net:GetNearestShrine(player) or nil
    if shrine == nil then
        return false, "DoBuild 返回成功但网络组件里找不到庙"
    end
    return true, "已在脚下建成一座，后续场景围绕它进行"
end

-- 场景 2：激活（状态翻转 + 落库字段）
local function ScenarioActivate(shrine)
    local comp = shrine.components.landshrine
    if comp == nil then
        return false, "庙上没有 landshrine 组件"
    end
    if not comp.activated then
        comp:SetActivated(true)
    end
    if not comp.activated then
        return false, "SetActivated(true) 后 activated 仍为 false"
    end
    if shrine.replica.landshrine == nil or not shrine.replica.landshrine:IsActivated() then
        return false, "replica 激活状态未同步"
    end
    return true
end

-- 场景 3：传送（传送到最近的庙，落点应落在庙的落点搜索半径内）
local function ScenarioTeleport(player, shrine)
    local net = LandShrineUtil.GetNetworkComponent()
    if net == nil then
        return nil, "不是主机，跳过"
    end

    local ok, reason = net:TeleportPlayerToShrine(player, shrine)
    if not ok then
        return false, "传送被拒：" .. tostring(reason)
    end

    local dist = math.sqrt(player:GetDistanceSqToInst(shrine))
    local maxdist = LandShrineConfig.TELEPORT_ARRIVE_MAX_DIST + 2 -- 落点半径 + 随从错位的余量
    if dist > maxdist then
        return false, string.format("落点离庙 %.1f，超出上限 %.1f", dist, maxdist)
    end
    return true, string.format("落点距庙 %.1f", dist)
end

-- 场景 4：拆庙释放槽位（走实体 Remove 流程，验证组件 OnRemoveEntity 注销路径）
local function ScenarioBreakReleasesSlot(shrine)
    local comp = shrine.components.landshrine
    local key = comp ~= nil and comp.terrainkey or nil
    if key == nil then
        return nil, "这座庙没占地形槽（可能刷在白名单外）"
    end

    comp:BreakShrine(nil)

    local net = LandShrineUtil.GetNetworkComponent()
    if net ~= nil and net:IsKeyOccupied(key) then
        return false, "庙已拆除但槽位 " .. tostring(key) .. " 仍被占用（注销路径失效！）"
    end
    return true, "槽位 " .. tostring(key) .. " 已释放，可原地重建"
end

--------------------------------------------------------------------------
local function RunAll()
    results = {}

    local player = ThePlayer
    local net = LandShrineUtil.GetNetworkComponent()
    if player == nil or net == nil then
        Report("[土地庙测试] 请以玩家身份、在主机上用「远程：」模式执行")
        return
    end

    -- 若脚下已有现成的庙就直接用，否则现场建一座
    local shrine = net:GetNearestShrine(player)
    local owned = shrine ~= nil and player:IsNear(shrine, LandShrineConfig.TELEPORT_FROM_RADIUS)

    if not owned then
        local ok, note = ScenarioBuild(player)
        Record("场景1 建造占槽", ok, note)
        if not ok then
            Report(table.concat(results, "\n"))
            return
        end
        shrine = net:GetNearestShrine(player)
    else
        Record("场景1 建造占槽", nil, "复用附近已有的庙（注意：场景4 会拆掉它，材料会原地掉落）")
    end

    if shrine ~= nil then
        Record("场景2 上香激活（含 replica 同步）", ScenarioActivate(shrine))
        Record("场景3 地图传送落点", ScenarioTeleport(player, shrine))
        Record("场景4 拆庙释放槽位", ScenarioBreakReleasesSlot(shrine))
    end

    table.insert(results, "—— 场景测试结束 ——")
    Report(table.concat(results, "\n"))
end

return { RunAll = RunAll }
