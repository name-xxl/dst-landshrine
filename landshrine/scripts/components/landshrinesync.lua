--[[
    玩家侧的土地庙数据同步（服务端组件）
    真正的数据放在 replica 里；这里只是让世界网络组件有一个统一的推送入口。
]]

local LandShrineSync = Class(function(self, inst)
    self.inst = inst
end)

-- 由 LandShrineNetwork 调用：把「已占用的地形槽」字符串推送给这名玩家
function LandShrineSync:SetOccupied(raw)
    local replica = self.inst.replica.landshrinesync
    if replica ~= nil then
        replica:SetOccupied(raw)
    end
end

return LandShrineSync