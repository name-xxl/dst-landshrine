--[[
    土地庙：地形槽的纯逻辑（零引擎依赖，可离线单元测试）

    这里只操作普通 Lua 表，不碰 TheWorld / TheSim 等游戏全局，
    因此可以用本机 Lua 5.1 解释器直接跑测试（见 tools/test/）。

    职责：
      1) 把「地形白名单 + 别名归并」解析成 [地形 id] = 槽位 key 的查找表
      2) 占用槽字符串协议：服务端编码 "5,6,8"，客机解码 —— 两端共用这一份实现，
         改协议时不会出现只改一端的脱节
]]

local Slots = {}

--------------------------------------------------------------------------
-- 白名单解析
--   ground   ：地形名 -> 地形 id 的表（游戏里是 GROUND，测试里喂假表）
--   allowed  ：Config.ALLOWED_TERRAIN（地形名列表）
--   aliases  ：Config.TERRAIN_ALIASES（地形名 -> 归并目标地形名）
--   warnfn   ：function(msg)，未知地形名的警告出口；可为 nil
-- 返回：[地形 id] = 槽位 key
--------------------------------------------------------------------------
function Slots.BuildWhitelist(ground, allowed, aliases, warnfn)
    local whitelist = {}
    if ground == nil then
        return whitelist
    end

    local warn = function(msg)
        if warnfn ~= nil then
            warnfn(msg)
        end
    end

    for name, base in pairs(aliases or {}) do
        local id, base_id = ground[name], ground[base]
        if id == nil then
            warn("[土地庙] 未知地形名（别名）：" .. tostring(name))
        elseif base_id == nil then
            warn("[土地庙] 未知地形名（别名目标）：" .. tostring(base))
        else
            whitelist[id] = base_id
        end
    end

    for _, name in ipairs(allowed or {}) do
        local id = ground[name]
        if id == nil then
            warn("[土地庙] 未知地形名：" .. tostring(name))
        else
            whitelist[id] = id
        end
    end

    return whitelist
end

--------------------------------------------------------------------------
-- 占用槽字符串协议："5,6,8"
--   Encode：槽位 key 数组 -> 字符串（排序后拼接，保证同一份数据产出同一字符串，
--           网络组件靠字符串比较来判断"有没有变化、要不要推送"）
--   Decode：字符串 -> { [key] = true }；空串/nil 解出空表，非数字段自动跳过
--------------------------------------------------------------------------
function Slots.Encode(keys)
    local ids = {}
    for _, key in ipairs(keys) do
        table.insert(ids, key)
    end
    table.sort(ids)

    local strs = {}
    for _, id in ipairs(ids) do
        table.insert(strs, tostring(id))
    end
    return table.concat(strs, ",")
end

function Slots.Decode(raw)
    local keys = {}
    if raw ~= nil and raw ~= "" then
        for s in string.gmatch(raw, "[^,]+") do
            local n = tonumber(s)
            if n ~= nil then
                keys[n] = true
            end
        end
    end
    return keys
end

return Slots
