--[[
    土地庙（prefab）
    开发期外观：借用原版骑士神庙（yoth_knightshrine）的动画资源
      * idle_off —— 未激活（默认）
      * activate -> idle_on —— 上香激活
      * hit_off / place —— 被敲击 / 落成
    正式版将替换为自制的土地庙美术，届时只需改本文件的 bank/build/anim 与 assets。
]]

require "prefabutil"

local LandShrineConfig = require("landshrine_config")

local assets =
{
    Asset("ANIM", "anim/yoth_knightshrine.zip"),
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
    inst.components.lootdropper:DropLoot()

    local fx = SpawnPrefab("collapse_small")
    fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
    fx:SetMaterial("stone")

    inst:Remove()
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
    inst.SoundEmitter:PlaySound("yoth_2026/shrine/place")
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

    -- 小地图图标：暂时借用原版骑士神庙的图标，正式版替换为自制图标（未激活/已激活两张）
    inst.MiniMapEntity:SetPriority(5)
    inst.MiniMapEntity:SetIcon("yoth_knightshrine.png")

    inst.AnimState:SetBank("yoth_knightshrine")
    inst.AnimState:SetBuild("yoth_knightshrine")
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
    MakePlacer("landshrine_placer", "yoth_knightshrine", "yoth_knightshrine", "idle_off", false, false, false, 1, nil, nil, PlacerPostInit)