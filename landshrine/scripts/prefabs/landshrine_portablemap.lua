--[[
    随身地图（prefab）
    在已激活的土地庙旁通过制作栏「购买」（商店型科技站配方，见 modmain）。
    永久持有、无限次使用：身上带着它，在任意位置打开世界地图即可点选已激活的庙传送
    （判定在 modmain 的传送门条件里，道具本身只是门票）。

    外观：世界模型与物品图标均为自制（anim/landshrine_portablemap.zip，单帧 idle）。
]]

local assets =
{
    Asset("ANIM", "anim/landshrine_portablemap.zip"),
    Asset("ATLAS", "images/inventoryimages.xml"), -- 自制物品图标图集
}

local BUILD_NAME = "landshrine_portablemap"

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank(BUILD_NAME)
    inst.AnimState:SetBuild(BUILD_NAME)
    inst.AnimState:PlayAnimation("idle", true)

    inst:AddTag("landshrine_portablemap")

    MakeInventoryFloatable(inst, "med", 0.1, 0.6)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname = "images/inventoryimages.xml" -- 注意是 atlasname（联网同步字段），atlas 无效
    inst.components.inventoryitem:ChangeImageName("landshrine_portablemap")

    return inst
end

return Prefab("landshrine_portablemap", fn, assets)
