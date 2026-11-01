--[[
    土地庙（服务端组件）
    职责：记录占用的地形槽、上香激活、把激活状态同步给客机、存档
]]

local LandShrineConfig = require("landshrine_config")

local LandShrine = Class(function(self, inst)
    self.inst = inst
    self.activated = false
    self.terrainkey = nil   -- 占用的地形槽；nil 表示不占槽（例如调试时刷在白名单外）
    self.network = nil      -- 注册到的世界网络组件

    -- 等实体（含存档数据）完全就绪后再初始化：
    -- 这样控制台刷出来的土地庙也能按当前位置取到地形
    inst:DoTaskInTime(0, function()
        if inst:IsValid() then
            self:OnPostInit()
        end
    end)
end)

function LandShrine:OnPostInit()
    self:SyncActivated()
    self:ClaimSlot()
end

--------------------------------------------------------------------------

-- 登记占用的地形槽。
-- 落成时（onbuilt）会被同步调用一次，避免同一帧两座土地庙抢同一个地形槽；
-- 从存档或控制台生成时则由 OnPostInit 兜底。
function LandShrine:ClaimSlot(pos)
    if self.network ~= nil then
        return
    end

    if self.terrainkey == nil then
        local x, y, z
        if pos ~= nil then
            x, y, z = pos.x, pos.y, pos.z
        else
            x, y, z = self.inst.Transform:GetWorldPosition()
        end
        self.terrainkey = LandShrineConfig:GetTerrainKey(x, z)
    end

    self:Register()
end

function LandShrine:Register()
    if self.network ~= nil then
        return
    end

    local net = TheWorld ~= nil and TheWorld.components.landshrinenetwork or nil
    if net == nil then
        return
    end

    self.network = net
    net:Register(self.inst)
end

function LandShrine:Unregister()
    if self.network ~= nil then
        self.network:Unregister(self.inst)
        self.network = nil
    end
end

function LandShrine:OnRemoveFromEntity()
    self:Unregister()
end

LandShrine.OnRemoveEntity = LandShrine.OnRemoveFromEntity

--------------------------------------------------------------------------

-- 把激活状态同步给客机（replica）与动画
function LandShrine:SyncActivated()
    local replica = self.inst.replica.landshrine
    if replica ~= nil then
        replica:SetActivated(self.activated)
    end

    -- 未激活时不去动动画：让落成动作（place）能自然播完
    if self.activated then
        if self.inst.AnimState ~= nil then
            self.inst.AnimState:PlayAnimation("idle_on", true)
        end
        self:SpawnMapIcon()
        self:BecomeShop()
    end
end

-- 已激活的庙兼作「随身地图」的购买处：挂 prototyper（原版商店型科技站，
-- 鸦年华奖品摊位同款），站在庙旁时制作栏会出现随身地图的配方。
-- 树表由 modmain 在加载时注册进 TUNING.PROTOTYPER_TREES。
function LandShrine:BecomeShop()
    if not LandShrineConfig.portablemap_enabled then
        return
    end

    if self.inst.components.prototyper == nil and TUNING.PROTOTYPER_TREES.LANDSHRINE ~= nil then
        local prototyper = self.inst:AddComponent("prototyper")
        prototyper.trees = TUNING.PROTOTYPER_TREES.LANDSHRINE
    end
end

-- 已激活的庙在世界地图上常亮显示（穿雾），未激活的只靠普通建筑图标
-- 复用原版 globalmapiconseeable（虫洞、触手柱的"显示在地图上"用的是同一个）
function LandShrine:SpawnMapIcon()
    if self.mapicon ~= nil and self.mapicon:IsValid() then
        return
    end

    self.mapicon = SpawnPrefab("globalmapiconseeable")
    if self.mapicon == nil then
        return
    end

    self.mapicon.MiniMapEntity:SetPriority(MINIMAP_DECORATION_PRIORITY)
    self.mapicon:AddTag("landshrineicon")   -- 客机靠这个 tag 在地图上认出土地庙
    self.mapicon:TrackEntity(self.inst)     -- 跟随庙的位置；庙被拆掉时图标会自动消失
end

function LandShrine:SetActivated(activated)
    activated = activated and true or false
    if self.activated == activated then
        return
    end

    self.activated = activated
    self:SyncActivated()
    self.inst:PushEvent("landshrineactivated", { shrine = self.inst })
end

-- 上香：未激活 -> 已激活；已激活 -> 状态不变，只是通知玩家打开地图
function LandShrine:DoWorship(doer)
    if doer == nil or not doer:IsValid() or not self.inst:IsValid() or not doer:IsNear(self.inst, 4) then
        return false, "LANDSHRINE_TOOFAR"
    end

    if self.activated then
        -- 已激活：这次交互的作用是"在庙旁打开地图"。
        -- 回调由 modmain 注入（组件运行在游戏环境，不能直接使用 mod 环境的 RPC 工具）
        if self.onworshipedfn ~= nil then
            self.onworshipedfn(self.inst, doer)
        end
        return true
    end

    self:SetActivated(true)

    if self.inst.AnimState ~= nil then
        -- 激活动画（覆盖 SyncActivated 立刻切到的 idle_on）
        self.inst.AnimState:PlayAnimation("activate")
        self.inst.AnimState:PushAnimation("idle_on", true)
    end

    if self.inst.SoundEmitter ~= nil then
        self.inst.SoundEmitter:PlaySound("yoth_2026/shrine/activate")
    end

    return true
end

--------------------------------------------------------------------------

-- 调试用：徒手拆除（掉落材料并释放地形槽）。
-- 由 mod 配置项「调试：允许徒手拆除」开启后出现在右键菜单里，不需要锤子。
function LandShrine:DevRemove(doer)
    if not self.inst:IsValid() then
        return false
    end

    if doer ~= nil and doer:IsValid() and not doer:IsNear(self.inst, 4) then
        return false, "LANDSHRINE_TOOFAR"
    end

    if self.inst.components.lootdropper ~= nil then
        self.inst.components.lootdropper:DropLoot()
    end

    local fx = SpawnPrefab("collapse_small")
    if fx ~= nil then
        fx.Transform:SetPosition(self.inst.Transform:GetWorldPosition())
        fx:SetMaterial("stone")
    end

    self.inst:Remove()
    return true
end

--------------------------------------------------------------------------

function LandShrine:OnSave()
    return {
        activated = self.activated or nil,
        terrainkey = self.terrainkey,
    }
end

function LandShrine:OnLoad(data)
    if data == nil then
        return
    end

    self.terrainkey = data.terrainkey
    self.activated = data.activated and true or false
end

--------------------------------------------------------------------------

function LandShrine:GetDebugString()
    local x, y, z = self.inst.Transform:GetWorldPosition()
    return string.format("[土地庙] 地形槽=%s 已激活=%s 位置=(%.1f, %.1f)",
        tostring(self.terrainkey), tostring(self.activated), x, z)
end

return LandShrine