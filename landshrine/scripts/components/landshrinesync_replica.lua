--[[
    玩家侧的土地庙数据同步（复制组件 / replica）
    客机通过 ThePlayer.replica.landshrinesync 读取「哪些地形槽已被占用」，
    用于放置土地庙时把幽灵变红（服务端仍会做权威判定）。
]]

local LandShrineSync = Class(function(self, inst)
    self.inst = inst
    -- 内容形如 "5,6,8"（地形 id 列表），最多二十来项
    self._occupied = net_string(inst.GUID, "landshrinesync._occupied", "landshrinesyncdirty")
    self._keys = nil

    if not TheWorld.ismastersim then
        inst:ListenForEvent("landshrinesyncdirty", function()
            self._keys = nil
        end)
    end
end)

function LandShrineSync:SetOccupied(raw)
    if TheWorld.ismastersim then
        self._occupied:set(raw or "")
        self._keys = nil
    end
end

function LandShrineSync:GetKeys()
    if self._keys == nil then
        self._keys = {}
        local raw = self._occupied:value()
        if raw ~= nil and raw ~= "" then
            for s in string.gmatch(raw, "[^,]+") do
                local n = tonumber(s)
                if n ~= nil then
                    self._keys[n] = true
                end
            end
        end
    end
    return self._keys
end

function LandShrineSync:IsKeyOccupied(key)
    return key ~= nil and self:GetKeys()[key] == true
end

return LandShrineSync