--[[
    随身地图（prefab）
    在已激活的土地庙旁通过制作栏「购买」（商店型科技站配方，见 modmain）。
    永久持有、无限次使用：身上带着它，在任意位置打开世界地图即可点选已激活的庙传送
    （判定在 modmain 的传送门条件里，道具本身只是门票）。

    开发期外观：借用原版指南针的动画与物品图标，正式版替换为自制美术。
]]

local assets =
{
    Asset("ANIM", "anim/compass.zip"),
}

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()

    MakeInventoryPhysics(inst)

    inst.AnimState:SetBank("compass")
    inst.AnimState:SetBuild("compass")
    inst.AnimState:PlayAnimation("idle")

    inst:AddTag("landshrine_portablemap")

    MakeInventoryFloatable(inst, "med", 0.1, 0.6)

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("inspectable")

    inst:AddComponent("inventoryitem")
    -- 占位图标：借用原版指南针，正式版替换为自制贴图
    inst.components.inventoryitem:ChangeImageName("compass")

    return inst
end

return Prefab("landshrine_portablemap", fn, assets)
