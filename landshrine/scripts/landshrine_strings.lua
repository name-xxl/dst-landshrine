--[[
    土地庙：全部显示文本
    运行在游戏环境，直接写原版 STRINGS 表；由 modmain 在加载时调用一次 Apply()。
]]

local Strings = {}

-- ACTIONFAIL 台词：每个角色都说同一句（没有角色专属文案）
local ACTIONFAIL_LINES = {
    LANDSHRINE_TERRAIN = "这地方不适合建土地庙。",
    LANDSHRINE_TAKEN = "这种地形已经有一座土地庙了。",
    LANDSHRINE_ALREADY = "这座土地庙已经上过香了。",
    LANDSHRINE_TOOFAR = "离土地庙太远了。",
    LANDSHRINE_NOTATSHRINE = "得站在土地庙旁边，或带着随身地图才能缩地。",
    LANDSHRINE_NOTARGET = "那座土地庙去不了。",
    LANDSHRINE_BLOCKED = "这里过不去。",
    LANDSHRINE_NOSPACE = "对面站不下人。",
}

function Strings.Apply()
    STRINGS.NAMES.LANDSHRINE = "土地庙"
    STRINGS.RECIPE_DESC.LANDSHRINE = "每种地形只能建一座。上香之后才能使用。"
    STRINGS.NAMES.LANDSHRINE_PORTABLEMAP = "随身地图"
    STRINGS.RECIPE_DESC.LANDSHRINE_PORTABLEMAP = "带着它，随时随地都能缩地回庙。"
    STRINGS.ACTIONS.LAND_SHRINE_WORSHIP = "上香"
    STRINGS.ACTIONS.LAND_SHRINE_TELEPORT_MAP = "传送"
    STRINGS.CHARACTERS.GENERIC.DESCRIBE.LANDSHRINE = "一座小小的土地庙。"
    STRINGS.CHARACTERS.GENERIC.DESCRIBE.LANDSHRINE_PORTABLEMAP = "土地爷给的行旅图。"

    for _, speech in pairs(STRINGS.CHARACTERS) do
        if speech.ACTIONFAIL ~= nil then
            for code, text in pairs(ACTIONFAIL_LINES) do
                speech.ACTIONFAIL[code] = text
            end
        end
    end
end

return Strings
