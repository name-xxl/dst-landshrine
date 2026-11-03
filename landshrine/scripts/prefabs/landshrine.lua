--[[
    土地庙（prefab）
    自制美术版动画（anim/landshrine.zip，bank/build 均为 landshrine）：
      * idle_off —— 未激活（默认，静态单帧）
      * idle_on —— 已激活（静态单帧）
      * activate —— 上香激活动画（off 停留后切到 on）
      * place —— 落成动画（缩放弹入）
      * hit_off —— 被敲击（摇晃）
    动画工程源文件在 exported/landshrine/landshrine.scml，
    用 tools/DSTModTool（纯 Python 打包器）编译：见 art_src/make_scml.py。
]]

require "prefabutil"

local LandShrineConfig = require("landshrine_config")

local assets =
{
    Asset("ANIM", "anim/landshrine.zip"),
}

local prefabs =
{
    "collapse_small",
}

--------------------------------------------------------------------------
-- 放置器校验（只在客户端执行）
--   1) 先跑原版的基础校验（playercontroller 在开始放置时写入 placer.testfn）
--   2) 再查地形白名单 + 地形槽是否已被占用
--------------------------------------------------------------------------
local function IsKeyOccupiedLocally(key)
    local player = ThePlayer
    local sync = player ~= nil and player.replica.landshrinesync or nil
    if sync == nil then
        -- 同步数据还没到，先不拦（服务端会做权威判定）
        return false
    end
    return sync:IsKeyOccupied(key)
end

local function PlacerOverrideTestFn(inst)
    local placer = inst.components.placer

    local can_build, mouse_blocked = true, false
    if placer.testfn ~= nil then
        can_build, mouse_blocked = placer.testfn(inst:GetPosition(), inst:GetRotation())
    end

    if can_build then
        local x, y, z = inst.Transform:GetWorldPosition()
        can_build = LandShrineConfig:ValidateBuildPoint(x, z, IsKeyOccupiedLocally)
    end

    return can_build, mouse_blocked
end

local function PlacerPostInit(inst)
    if inst.components.placer ~= nil then
        -- 必须用 override_testfn：testfn 会在开始放置时被 playercontroller 覆盖
        inst.components.placer.override_testfn = PlacerOverrideTestFn
    end
end

--------------------------------------------------------------------------
-- 土地庙本体
--------------------------------------------------------------------------
local function CurrentStateAnim(inst)
    local comp = inst.components.landshrine
    return (comp ~= nil and comp.activated) and "idle_on" or "idle_off"
end

local function OnHit(inst, worker)
    if not inst:HasTag("burnt") then
        inst.AnimState:PlayAnimation("hit_off")
        inst.AnimState:PushAnimation(CurrentStateAnim(inst), true)
    end
end

local function OnHammered(inst, worker)
    -- 掉材料 + 倒塌特效 + 移除的逻辑与调试拆庙共用，统一走组件；
    -- 距离由 workable 组件把关，这里传 nil 跳过重复检查
    local comp = inst.components.landshrine
    if comp ~= nil then
        comp:BreakShrine(nil)
    else
        inst:Remove()
    end
end

local function OnDeconstructed(inst, data)
    -- 解构法杖会自行返还配方材料，这里只负责移除（移除后地形槽自动释放）
    inst:Remove()
end

local function OnBuilt(inst, data)
    -- 立刻登记地形槽，避免同一帧内两座土地庙抢同一个地形槽
    local comp = inst.components.landshrine
    if comp ~= nil then
        comp:ClaimSlot(data ~= nil and data.pos or nil)
    end

    inst.AnimState:PlayAnimation("place")
    inst.AnimState:PushAnimation("idle_off", true)
    inst.SoundEmitter:PlaySound(LandShrineConfig.SOUND_PLACE)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddMiniMapEntity()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()

    inst:SetDeploySmartRadius(1)
    MakeObstaclePhysics(inst, 0.6)

    -- 小地图图标：未激活灰暗 / 已激活点亮，切换逻辑在 landshrine 组件 SyncActivated
    inst.MiniMapEntity:SetPriority(5)
    inst.MiniMapEntity:SetIcon(LandShrineConfig.MINIMAP_ICON_OFF)

    -- 客机侧的状态跟随：激活状态是 net_bool（见 landshrine_replica），
    -- 服务端组件里的 SetIcon 不会同步到客机，客机必须自己监听变更切图标
    if not TheWorld.ismastersim then
        local ApplyMiniMapIcon = function(inst)
            local on = inst.replica.landshrine ~= nil and inst.replica.landshrine:IsActivated()
            inst.MiniMapEntity:SetIcon(on and LandShrineConfig.MINIMAP_ICON_ON or LandShrineConfig.MINIMAP_ICON_OFF)
        end
        inst:ListenForEvent(LandShrineConfig.EVENT_ACTIVATED_DIRTY, ApplyMiniMapIcon)
        -- net_bool 的初始值不触发 dirty 事件：重进存档、或已激活的庙首次进入
        -- 网络视野时，必须按 replica 当前值主动设一次（原版 revealable_Init 同款兜底）
        inst:DoTaskInTime(0, ApplyMiniMapIcon)
    end

    inst.AnimState:SetBank("landshrine")
    inst.AnimState:SetBuild("landshrine")
    inst.AnimState:PlayAnimation("idle_off", true)

    inst:AddTag("structure")
    inst:AddTag("landshrine")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("lootdropper")
    -- 锤子拆除时按配方材料返还（原版会打 5 折：TUNING.HAMMER_LOOT_PERCENT = .5，
    -- 且 math.ceil 保证每种至少返 1 个）。
    -- 用 droprecipeloot 而不是硬写 SetLoot：这样将来把配方改成正式材料时，返还自动跟着变，
    -- 不会出现"配方改了、返还还是老材料"的脱节。
    -- （解构法杖那条路不受这里影响：法杖自己按配方返还材料，见 prefabs/staff_common.lua）
    inst.components.lootdropper.droprecipeloot = true

    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnWorkCallback(OnHit)
    inst.components.workable:SetOnFinishCallback(OnHammered)

    -- 地形槽登记、上香激活、存档都在这个组件里
    inst:AddComponent("landshrine")

    inst:ListenForEvent("onbuilt", OnBuilt)
    inst:ListenForEvent("ondeconstructstructure", OnDeconstructed)

    return inst
end

return Prefab("landshrine", fn, assets, prefabs),
    MakePlacer("landshrine_placer", "landshrine", "landshrine", "idle_off", false, false, false, 1, nil, nil, PlacerPostInit)