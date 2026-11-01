--[[
    土地庙（复制组件 / replica）
    客机通过 inst.replica.landshrine 读取土地庙的激活状态
]]

local LandShrine = Class(function(self, inst)
    self.inst = inst
    -- 激活状态：客机用它决定右键菜单是否显示「上香」，以及后续地图图标的状态
    self._activated = net_bool(inst.GUID, "landshrine._activated", "landshrineactivateddirty")
end)

function LandShrine:SetActivated(activated)
    if TheWorld.ismastersim then
        self._activated:set(activated and true or false)
    end
end

function LandShrine:IsActivated()
    return self._activated:value()
end

return LandShrine