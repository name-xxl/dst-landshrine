--[[
    土地庙传送 —— 主入口
    已实现：按地形建造（每种地形一座）、上香激活、地图点选传送、随身地图
    尚未实现：跨分片

    本文件只做「必须在 mod 环境执行」的注册（AddAction / AddRecipe2 / RPC / PostInit 等）；
    数值与规则在 scripts/landshrine_config.lua，跨端查询工具在 scripts/landshrine_util.lua，
    文本在 scripts/landshrine_strings.lua，控制台调试入口在 scripts/landshrine_debug.lua。
]]

local require = GLOBAL.require

PrefabFiles = { "landshrine", "landshrine_portablemap" }

-- 预加载土地庙的动画资源（放置器是客户端实体，可能会先于土地庙出现）
Assets = {
    Asset("ANIM", "anim/landshrine.zip"),
    Asset("ATLAS", "images/inventoryimages.xml"), -- 自制图标图集（建庙配方等）
    Asset("IMAGE", "images/inventoryimages.tex"),
    Asset("ATLAS", "images/station_icons.xml"),   -- 商店站钉栏图标（原版规范 255x255，见 AddPrototyperDef）
    Asset("IMAGE", "images/station_icons.tex"),
    Asset("IMAGE", "minimap/landshrine.tex"),     -- 自制小地图图标图集
    Asset("ATLAS", "minimap/landshrine.xml"),
}

-- 小地图图标图集必须显式注册（原版 MINIMAP_IMAGE 是打进引擎图集的，mod 散 png 不生效）
AddMinimapAtlas("minimap/landshrine.xml")

-- 让客机也能拿到土地庙的激活状态、以及「已被占用的地形槽」小表
AddReplicableComponent("landshrine")
AddReplicableComponent("landshrinesync")

local LandShrineConfig = require("landshrine_config")
local LandShrineUtil = require("landshrine_util")

--------------------------------------------------------------------------
-- 把配置模块需要的依赖注入进去。
--
-- ★ 原因（踩过的坑）：landshrine_config.lua 是被 require 进来的模块，运行在游戏环境（_G）里，
--   而原版 scripts/strict.lua 给 _G 装了严格检查：读取未声明的全局名会直接抛错，
--   所以模块里不能出现 GLOBAL（它是 mod 环境专有名字，模块里读会失败），
--   也不能读运行时新建的全局名。GROUND / TheWorld / 日志 / 调试开关一律从这里注入。
--------------------------------------------------------------------------
local dev_flags = {
    skip_all_checks = GetModConfigData("DevBuildAnywhere") == true,
    skip_slot_check = not (GetModConfigData("EnforceTerrainSlots") == true),
}

-- 仅供控制台查看当前开关状态；配置模块不读它
GLOBAL.LANDSHRINE_DEV = dev_flags

LandShrineConfig:Init({
    GROUND = GLOBAL.GROUND,
    GetWorld = function() return GLOBAL.TheWorld end,
    Log = GLOBAL.print,
    Dev = dev_flags,
    PortableMapEnabled = GetModConfigData("PortableMapEnabled") == true,
})

--------------------------------------------------------------------------
-- 随身地图：自定义科技树 + 商店型科技站（原版鸦年华奖品摊位同款机制）
--   TECH.LANDSHRINE_ONE         配方的科技门槛
--   PROTOTYPER_TREES.LANDSHRINE 庙激活后挂的 prototyper 组件用它开门
--   AddPrototyperDef            制作栏钉栏上庙的站图标与提示文本
--
-- ★ 自定义科技必须登记进 TechTree.AVAILABLE_TECH：
--   builder.lua 的 CopyTechTrees 和 player_classified 的科技同步
--   （builder_replica.lua SetTechTrees、player_classified.lua:1534）
--   都只遍历这张表。不登记的话，树值永远进不了 accessible_tech_trees，
--   配方会一直是锁着的（制作栏里灰到底，且不报任何错）。
--
-- ★★ 但登记之后还必须回填已有配方，否则客户端开制作栏直接崩：
--   recipe.lua:115 的 Recipe 构造是 `self.level = TechTree.Create(level)`，
--   按**配方创建那一刻**的 AVAILABLE_TECH 填零。插入新键之前就已创建的原版配方
--   （原版脚本先于 modmain 加载）的 level 表里没有 LANDSHRINE 这个键，而
--   builder_replica.lua:335 会遍历 AVAILABLE_TECH 直接做 `recipe.level[v] > 0`，
--   缺键就是 "attempt to compare number with nil"。
--   插入之后创建的配方走 TechTree.Create 会自动带上，不需要回填。
--------------------------------------------------------------------------
local TechTree = GLOBAL.require("techtree")
if not table.contains(TechTree.AVAILABLE_TECH, "LANDSHRINE") then
    table.insert(TechTree.AVAILABLE_TECH, "LANDSHRINE")

    local all_recipes = GLOBAL.AllRecipes
    if all_recipes ~= nil then
        for _, recipe in pairs(all_recipes) do
            if recipe.level ~= nil and recipe.level.LANDSHRINE == nil then
                recipe.level.LANDSHRINE = 0
            end
        end
    end
end

GLOBAL.TECH.LANDSHRINE_ONE = { LANDSHRINE = 1 }
GLOBAL.TUNING.PROTOTYPER_TREES.LANDSHRINE = TechTree.Create({ LANDSHRINE = 1 })

AddPrototyperDef("landshrine", {
    icon_atlas = "images/station_icons.xml",
    icon_image = "station_landshrine.tex", -- 自制站图标（255x255：钉栏按原生素材尺寸渲染，64 格会只有原版 1/4 大小）
    is_crafting_station = true,
    action_str = "TRADE",
    filter_text = "土地庙",
})

--------------------------------------------------------------------------
-- 文本（全部文案集中在 scripts/landshrine_strings.lua）
--------------------------------------------------------------------------
require("landshrine_strings").Apply()

--------------------------------------------------------------------------
-- 配方（材料数值后置，开发期用便于获取的材料）
--------------------------------------------------------------------------
local function MakeIngredients(list)
    local ingredients = {}
    for _, v in ipairs(list) do
        table.insert(ingredients, Ingredient(v[1], v[2]))
    end
    return ingredients
end

-- 服务端权威校验：在扣材料之前被 builder:DoBuild 调用
-- 返回 false, 原因字符串 —— 玩家会自动说出对应的 ACTIONFAIL 台词
local function CanBuildLandShrine(recipe, builder, pt, rotation, station, skin)
    if builder == nil then
        return true
    end

    -- pt 可能为 nil：原版 DoBuild 内部同样会回退到建造者所在位置
    local pos = pt or builder:GetPosition()
    if pos == nil then
        return true
    end

    local net = LandShrineUtil.GetNetworkComponent()
    local isoccupied = function(key)
        return net ~= nil and net:IsKeyOccupied(key)
    end

    return LandShrineConfig:ValidateBuildPoint(pos.x, pos.z, isoccupied)
end

AddRecipe2("landshrine", MakeIngredients(LandShrineConfig.SHRINE_INGREDIENTS), GLOBAL.TECH.NONE, {
    placer = "landshrine_placer",
    min_spacing = 2,
    image = "landshrine.tex", -- 自制图标（images/inventoryimages.xml 图集）
    atlas = "images/inventoryimages.xml",
    canbuild = CanBuildLandShrine,
}, { "STRUCTURES" })

--------------------------------------------------------------------------
-- 随身地图配方：挂在土地庙的自定义科技树上，只能站在已激活的庙旁制作
-- nounlock 让它进「制作站」分类（AddRecipe2 自动归类，见 modutil.lua:739-743），
-- 不会出现在常驻的 MODS 分类里
--------------------------------------------------------------------------
if LandShrineConfig.portablemap_enabled then
    AddRecipe2("landshrine_portablemap", MakeIngredients(LandShrineConfig.PORTABLEMAP_INGREDIENTS), GLOBAL.TECH.LANDSHRINE_ONE, {
        nounlock = true,
        sg_state = "give",
        image = "landshrine_portablemap.tex", -- 自制图标（images/inventoryimages.xml 图集）
        atlas = "images/inventoryimages.xml",
    })
end

--------------------------------------------------------------------------
-- 世界网络组件（仅服务端）+ 玩家身上的同步组件
--------------------------------------------------------------------------
AddPrefabPostInit("world", function(inst)
    if inst.ismastersim then
        inst:AddComponent("landshrinenetwork")
    end
end)

AddPlayerPostInit(function(inst)
    local world = GLOBAL.TheWorld
    if world == nil or not world.ismastersim then
        return
    end

    inst:AddComponent("landshrinesync")

    -- 玩家出现 / 重连后主动拉一次占用表（覆盖房主与后加入的玩家）
    inst:DoTaskInTime(0, function()
        local net = LandShrineUtil.GetNetworkComponent()
        if net ~= nil then
            net:PushToPlayer(inst)
        end
    end)
end)

--------------------------------------------------------------------------
-- 打开世界地图（客户端）。条件与守卫照原版按 M 键开图那条路抄。
-- 带重试：刚做完动作时控制器可能被临时禁用（IsMapControlsEnabled 为 false），过一会儿再来。
--------------------------------------------------------------------------
local function TryOpenLandShrineMap(player, attempts)
    if player == nil or not player:IsValid() or player.HUD == nil or GLOBAL.TheFrontEnd == nil then
        return
    end

    if GLOBAL.GetGameModeProperty("no_minimap") then
        print("[土地庙] 自动开图跳过：当前游戏模式禁用小地图")
        return
    end

    if player.HUD:IsMapScreenOpen() then
        return -- 已经开着，不用重复开
    end

    local playercontroller = player.components.playercontroller
    if playercontroller ~= nil and playercontroller:IsMapControlsEnabled() then
        if player.HUD:IsStatusScreenOpen() then
            GLOBAL.TheFrontEnd:PopScreen()
        end
        GLOBAL.TheFrontEnd:PushScreen(GLOBAL.require("screens/mapscreen")(player))
        print("[土地庙] 已打开世界地图")
        return
    end

    if attempts > 1 then
        player:DoTaskInTime(0.25, function()
            TryOpenLandShrineMap(player, attempts - 1)
        end)
    else
        print("[土地庙] 自动开图失败：控制器长时间不可用（IsMapControlsEnabled 一直为 false）")
    end
end

--------------------------------------------------------------------------
-- 「已激活的庙上香完成后自动开图」的链路：
--   服务端 DoWorship 判定成功 → 模组 RPC 通知该玩家 → 客户端打开地图
-- （走 RPC 而不是客户端动作回调，是因为服务端才真正知道"这次上香发生了什么"）
--------------------------------------------------------------------------
if GLOBAL.TheNet:GetIsServer() then
    -- 服务端侧只需注册，不实现
    AddClientModRPCHandler("landshrine", "openshrinemap", function() end)
end

if GLOBAL.TheNet:GetIsClient() then
    AddClientModRPCHandler("landshrine", "openshrinemap", function()
        print("[土地庙] 收到服务端通知：打开地图")
        TryOpenLandShrineMap(GLOBAL.ThePlayer, 8)
    end)
end

-- 给土地庙组件注入"上香成功后通知玩家"的回调
-- （回调在 mod 环境里创建，所以可以安全使用 GLOBAL./SendModRPCToClient/CLIENT_MOD_RPC）
AddComponentPostInit("landshrine", function(self)
    self.onworshipedfn = function(shrine, doer)
        if doer == nil or not doer:IsValid() or not doer:HasTag("player") then
            return
        end
        print(string.format("[土地庙] 已激活的庙被上香，通知 %s 打开地图", tostring(doer)))
        SendModRPCToClient(CLIENT_MOD_RPC["landshrine"]["openshrinemap"], doer.userid, doer)
    end
end)

--------------------------------------------------------------------------
-- 土地庙交互动作：未激活的庙 = 上香；已激活的庙 = 打开地图
--------------------------------------------------------------------------
local function DoLandShrineWorship(act)
    local target, doer = act.target, act.doer
    if target == nil or doer == nil then
        return false
    end

    -- 服务端：权威判定。
    -- 未激活 → 激活；已激活 → 什么都不做（这次交互只是为了在客户端把地图打开）
    if GLOBAL.TheWorld.ismastersim and target.components.landshrine ~= nil then
        return target.components.landshrine:DoWorship(doer)
    end

    -- 客户端：保守预测即可。
    -- 「已激活时自动开图」不在这里做——由服务端 DoWorship 判定成功后用模组 RPC 通知客户端，
    -- 见上面 openshrinemap 那条链路（服务端才真正知道这次上香发生了什么）。
    local replica = target.replica.landshrine
    return replica ~= nil and doer:IsNear(target, LandShrineConfig.WORSHIP_RADIUS)
end

AddAction("LAND_SHRINE_WORSHIP", "上香", DoLandShrineWorship)
GLOBAL.ACTIONS.LAND_SHRINE_WORSHIP.priority = 5
GLOBAL.ACTIONS.LAND_SHRINE_WORSHIP.mount_valid = true

AddComponentAction("SCENE", "landshrine", function(inst, doer, actions, right)
    if right and inst.replica.landshrine ~= nil and not inst:HasTag("burnt") then
        -- 未激活 → 激活它；已激活 → 不改变状态，只是顺势打开地图，两者都叫「上香」
        table.insert(actions, GLOBAL.ACTIONS.LAND_SHRINE_WORSHIP)
    end
end)

-- 借用原版「递东西」的角色动作状态（后续换成专属上香动作）
AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(GLOBAL.ACTIONS.LAND_SHRINE_WORSHIP, "give"))
AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(GLOBAL.ACTIONS.LAND_SHRINE_WORSHIP, "give"))

--------------------------------------------------------------------------
-- 缩地：站在已激活的土地庙旁（或带着随身地图），在世界地图上点选另一座庙传送
--
-- 原版范式：地图里点某个东西 → 走一个 map_only 动作
--（保险库传送球、沃比快递、虫洞标记都是这套），我们照同一条路走：
--   1) 每座已激活的庙在地图上挂一个穿雾可见的图标实体（见 landshrine 组件）
--   2) 地图界面每帧问 playercontroller:GetMapActions()「光标处能干什么」
--   3) 我们包装它：光标附近有庙图标、且玩家自己站在庙旁时，返回传送动作
--   4) 点击后原版会带着动作码重跑一次 GetMapActions（带 actiondef 那条路），
--      自动完成校验、地形检查、客户端→服务端 RPC 与执行
--
-- 动作不是 instant：它映射到原版 crushitemcast_trigger 状态（wilson / wilson_client
-- 双端都有，保险库传送球 VAULTORBTELEPORT_MAP 同款）。传送在该状态内执行，
-- 客户端状态负责 locomotor:Stop() + FlattenMovementPrediction() ——
-- 这是被预测的客户端接受服务端传送后位置、丢弃预测状态的标准机制；
-- instant 动作绕过状态机，正是之前"传送后走回原地"的结构性根因。
--------------------------------------------------------------------------
local function DoLandShrineMapTeleport(act)
    local player = act.doer
    if player == nil then
        return false
    end

    -- 1) 硬规则：站在已激活的土地庙旁发起，或身上带着随身地图
    if not LandShrineUtil.CanStartTeleport(player) then
        print("[土地庙] 传送被拒：不在已激活的土地庙旁，且没有随身地图")
        return false, "LANDSHRINE_NOTATSHRINE"
    end

    -- 2) 目标 = 动作点附近那座图标所跟踪的庙（只有服务端能读到）
    local pos = act:GetActionPoint()
    if pos == nil then
        return false, "LANDSHRINE_NOTARGET"
    end

    local icon = LandShrineUtil.FindLandShrineIconAt(pos.x, pos.z)
    local target = LandShrineUtil.GetShrineFromMapIcon(icon)
    if target == nil or not target:IsValid() then
        print(string.format("[土地庙] 传送被拒：动作点 (%.1f, %.1f) 附近没有土地庙图标", pos.x, pos.z))
        return false, "LANDSHRINE_NOTARGET"
    end

    local comp = target.components.landshrine
    if comp == nil or not comp.activated then
        return false, "LANDSHRINE_NOTARGET"
    end

    local net = LandShrineUtil.GetNetworkComponent()
    if net == nil then
        return false, "LANDSHRINE_NOTARGET"
    end

    return net:TeleportPlayerToShrine(player, target)
end

AddAction("LAND_SHRINE_TELEPORT_MAP", "传送", DoLandShrineMapTeleport)

local teleport_map_action = GLOBAL.ACTIONS.LAND_SHRINE_TELEPORT_MAP
teleport_map_action.priority = 10            -- 与原版地图动作同级（原版 HIGH_ACTION_PRIORITY = 10）
teleport_map_action.rmb = true               -- 地图上右键触发（左键留给拖动地图）
teleport_map_action.map_only = true          -- 只在地图界面存在
teleport_map_action.map_works_on_unexplored = true
teleport_map_action.closes_map = true        -- 传送后关闭地图
-- 等价原版 ArriveAnywhere：非 instant 的无目标动作必需，
-- 让客户端 preview 立即"到达"，而不是真的走向地图点击点
teleport_map_action.customarrivecheck = function() return true end

-- 地图 UI 用它判断「光标这里能不能传送」并给出目标坐标
teleport_map_action.maponly_checkvalidpos_fn = function(act)
    local pos = act ~= nil and act:GetActionPoint() or nil
    if pos == nil then
        return false
    end

    local icon = LandShrineUtil.FindLandShrineIconAt(pos.x, pos.z)
    if icon == nil then
        return false, "LANDSHRINE_NOTARGET"
    end

    local x, y, z = icon.Transform:GetWorldPosition()
    return true, nil, x, z, icon
end

-- 走原版 crushitemcast_trigger 状态（保险库传送球 VAULTORBTELEPORT_MAP 同款）：
-- 双端状态里完成 locomotor:Stop()、执行动作函数、FlattenMovementPrediction()，
-- 不需要我们自己清理任何移动状态
AddStategraphActionHandler("wilson", GLOBAL.ActionHandler(GLOBAL.ACTIONS.LAND_SHRINE_TELEPORT_MAP, "crushitemcast_trigger"))
AddStategraphActionHandler("wilson_client", GLOBAL.ActionHandler(GLOBAL.ACTIONS.LAND_SHRINE_TELEPORT_MAP, "crushitemcast_trigger"))

AddComponentPostInit("playercontroller", function(self)
    local old_getmapactions = self.GetMapActions
    if old_getmapactions == nil then
        return
    end

    self.GetMapActions = function(_self, position, maptarget, actiondef)
        local lmb, rmb = old_getmapactions(_self, position, maptarget, actiondef)

        -- 带 actiondef 的是"点击执行"那条路，交给原版，避免干扰其它地图动作
        if actiondef ~= nil or position == nil then
            return lmb, rmb
        end

        local player = _self.inst
        if not LandShrineUtil.CanStartTeleport(player) then
            return lmb, rmb
        end

        if LandShrineUtil.FindLandShrineIconAt(position.x, position.z) == nil then
            return lmb, rmb
        end

        rmb = GLOBAL.BufferedAction(player, nil, GLOBAL.ACTIONS.LAND_SHRINE_TELEPORT_MAP, nil, position)
        return lmb, rmb
    end
end)

--------------------------------------------------------------------------
-- 调试与游戏内场景测试（控制台执行，注意要切到「远程：」；
-- 命令清单见 scripts/landshrine_debug.lua 与 scripts/landshrine_test.lua 的头注释）
--------------------------------------------------------------------------
GLOBAL.LandShrineDebug = require("landshrine_debug")
GLOBAL.LandShrineTest = require("landshrine_test")
