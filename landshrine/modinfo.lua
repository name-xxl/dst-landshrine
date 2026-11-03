--[[
    土地庙传送 —— mod 信息与配置项
    已实现：按地形建造（每种地形一座）、上香激活、地图点选传送、随身地图
    尚未实现：跨分片
]]

name = "土地庙传送"
description = [[用材料在每种地形上建立一座土地庙（每种地形全档一座），上香激活后可在地图上点选传送；
在已激活的庙旁还能制作随身地图，带着它随时随地缩地回庙。

【开发中】跨分片传送尚未实现。]]
author = "name_xxl、羽临捉千秋"
version = "0.5.0"

forumthread = ""

icon_atlas = "modicon.xml"
icon = "modicon.tex"

api_version = 10
dst_compatible = true
client_only_mod = false
all_clients_require_mod = true

server_filter_tags = { "landshrine", "土地庙" }

configuration_options = {
    {
        name = "DevBuildAnywhere",
        label = "调试：任意位置可建",
        hover = "开启后跳过地形白名单与地形槽位校验，方便原地反复测试放置流程",
        options = {
            { description = "关闭", data = false },
            { description = "开启", data = true },
        },
        default = false,
    },
    {
        name = "EnforceTerrainSlots",
        label = "每种地形只能建一座",
        hover = "关闭后仍保留地形白名单，但允许在同一种地形上建多座（测试用）",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
    {
        name = "PortableMapEnabled",
        label = "随身地图",
        hover = "在已激活的庙旁可以制作随身地图；带着它就能在任意位置缩地回庙",
        options = {
            { description = "开启", data = true },
            { description = "关闭", data = false },
        },
        default = true,
    },
}