# 饥荒联机版「土地庙」传送 Mod —— 设计方案

> 版本：**v2**（2026-11-01）
> v1 → v2 变化：**砍掉**调息、小怪刷新、代价系统、复活锚点（`attunable` 方案）、自定义滚动列表面板；**新增**地形槽位规则、随身地图、复用原版地图界面点选传送；材料数值全部后置。
> 依据：`资料/黑神话悟空-土地庙锚点机制.md`、`2119742489`（木牌传送 GUI 源码）、`饥荒Mod开发指南/dstmod-tutorial`、以及本机原版脚本（`scripts.zip` 已解包核对，§4 列出全部 file:line 依据）。

---

## 0. 定位与范围

**一句话**：让玩家用前期材料，在**每种地形上各建一座土地庙**（全档上限 21 座），上香激活后可在地图上点选传送；在庙里可花材料买一份**随身地图**，之后可随时随地点选传送。

**做**：按地形占位建造土地庙 → 上香激活 → 庙旁打开地图点选传送 → 庙旁购买随身地图 → 持地图后任意位置点选传送。

**不做**（明确排除）：调息、怪物刷新、任何传送代价、死亡复活锚点、跨分片传送（v2 之后再议）、自定义地图绘制。

**平衡逻辑**：限制不在材料成本，而在**地形槽位数量**。全档只有 21 个槽位且分散在各生物群系，所以建庙材料刻意保持廉价是安全的——玩家真正的门槛是"找到每种地形"。唯一的特权闸门是**随身地图**（持有后传送永久免费无限次），因此它的定价放在中期材料上。

---

## 1. 机制映射表（黑神话 → 饥荒）

| 黑神话机制 | 本 mod 实现 | 说明 |
|---|---|---|
| 土地庙本体 | 可制作建筑 + 放置器（可选皮肤） | 玩家自己建，不再是世界生成 |
| 每区域一座庙 | **每种地形类型一座**（全档 21 座） | 见 §2，替代原作的世界固定分布 |
| 上香激活 | 右键 → 上香动作 → 播放激活动画 → 激活态持久化 | 未激活的庙不能传送、不出现在地图可选目标里 |
| 缩地（庙内传送） | 庙旁右键 → 打开**原版地图界面**，点选已激活的庙 → 传送 | 复用原版地图，不自绘、不自建列表 |
| 行旅图（地图直传） | **随身地图**道具：在庙里花材料购买，永久持有 | 持有后在任意位置按地图键即可点选传送 |
| 金光引路 | 小地图/世界地图图标：未激活灰、已激活亮（穿迷雾） | 用原版全局地图图标机制 |
| 传送即刷新小怪 / 调息 | **不做** | —— |
| 死亡在最后上香的庙还魂 | **不做** | 技术上可挂（原版 `attunable` 现成），按需求排除 |
| 二周目重置锚点 | 不需要 | 饥荒没有二周目 |

---

## 2. 核心规则：地形槽位

### 2.1 四条筛选依据

每条对应一个会真实发生的坏情况：

1. **玩家能自由到达** —— 排除海洋、浮冰、岩壁、不可通行、假地面。庙必须有可站立落点，不能出现"进不去也出不来"的死点。
2. **不能由玩家凭空造出来** —— 排除所有人造/铺装地皮。**这是最关键的一条**：原版运行时没有"自然地形 vs 玩家铺的地皮"标记，地皮只有类型 id（`prefabs/turfs.lua` 的铺地皮动作直接 `map:SetTile(x, y, tile)` 改写地形）。若不排除，玩家铺一块木地板就能造出新槽位，"每种地形一座"的稀缺性立即失效。
3. **地形稳定，不会自行变化或消失** —— 排除裂隙造成的动态地形（月沼、暗影沼泽、查理藤）、活动区域（熔炉、暴食、远古圣殿）、以及封闭房间。
4. **玩家肉眼能辨认** —— 同一地形的"发光变体"与基础版合并成一个槽位（远古地面的发光版视觉几乎一致，分开算会导致玩家无法自验规则）。

**外加一条硬约束**：原版传送门禁 `IsTeleportingPermittedFromPointToPoint` 只对三类封闭房间生效——远古圣殿（VAULT）、其大厅（LOBBYVAULT）、中庭（ATRIUM）。即**只有这三个地方会出现"建得了但传不进去"**，直接排除；其余区域（含月岛洞穴、档案馆）技术上均可传送。

### 2.2 白名单（纯数据表，可随时增删）

| 分片 | 地形 id（`GROUND`） | 官方中文名 | 槽位 |
|---|---|---|---|
| 地表 | `GRASS` | 长草地皮 | 1 |
| 地表 | `FOREST` | 森林地皮 | 2 |
| 地表 | `SAVANNA` | 热带草原地皮 | 3 |
| 地表 | `DECIDUOUS` | 落叶林地皮 | 4 |
| 地表 | `MARSH` | 沼泽地皮 | 5 |
| 地表 | `ROCKY` | 岩石地皮 | 6 |
| 地表 | `DIRT` | 泥土地皮 | 7 |
| 地表 | `DESERT_DIRT` | 沙漠地皮 | 8 |
| 地表 | `PEBBLEBEACH` | 岩石海滩地皮 | 9 |
| 地表 | `SHELLBEACH` | 贝壳海滩地皮 | 10 |
| 地表 | `METEOR` | 月球环形山地皮 | 11 |
| 洞穴 | `CAVE` | 鸟粪地皮 | 12 |
| 洞穴 | `UNDERROCK` | 洞穴岩石地皮 | 13 |
| 洞穴 | `MUD` | 泥泞地皮 | 14 |
| 洞穴 | `FUNGUS` | 真菌地皮（蓝） | 15 |
| 洞穴 | `FUNGUSGREEN` | 真菌地皮（绿） | 16 |
| 洞穴 | `FUNGUSRED` | 真菌地皮（红） | 17 |
| 洞穴 | `FUNGUSMOON` | 变异真菌地皮 | 18 |
| 遗迹 | `BRICK`（含 `BRICK_GLOW`） | 远古地面 | 19 |
| 遗迹 | `TILES`（含 `TILES_GLOW`） | 远古瓷砖 | 20 |
| 遗迹 | `TRIM`（含 `TRIM_GLOW`） | 远古砖雕 | 21 |

**合计：地表 11 + 洞穴 7 + 遗迹 3 = 21 座/档。**

> 三处中文名注意：蓝/绿/红三种菌类地皮官方都译作"真菌地皮"，UI 提示必须带颜色（如"真菌地皮（红）已被占用"），否则违反第 4 条。
> 已定但可随时反转的边界项：月沼、暗影沼泽 → 排除（裂隙动态地形）；洞穴喷气孔地面 → 拟纳入（可选的洞穴第 8 槽）；海盗海滩 → 拟纳入（可选的地表第 12 槽）；黏滑地皮 → 排除；档案馆 → 排除（封闭区域）。

### 2.3 槽位判定与记录

- **判定时机**：建造那一刻取 `TheWorld.Map:GetTileAtPoint(x, 0, z)`，把地形 id **写进庙自己的存档**（`OnSave`）。此后不再重算——因为地皮可被任何人改写，实时重算会让规则变得不可预测。
- **合并规则**：发光变体在建庙时归并到基础 id（`BRICK_GLOW` → `BRICK`），保证同一地形只占一个槽。
- **占用表**：以地形 id 为键的 21 项小表。**不单独落盘**，单数据源 = 每座庙自身的存档；世界加载后遍历所有带 `landshrine` 标签的实体重建即可（原版 `wanderingtrader` 也是这样遍历 `Ents`）。
- **客户端同步**：放置器的红/绿校验在客户端执行（`placer.testfn`），而客户端看不到远处的庙，所以要把占用表打包成**一个短字符串**（如 `"5,6,8,12"`）通过网络变量同步给客户端，几十字节。服务端另做一次权威判定。
- **占用与激活解耦**：建造即占槽（未激活也占）；拆庙释放槽位。

---

## 3. 功能与交互流程

### 3.1 建造

- 配方：可制作建筑（`AddRecipe2` + `MakePlacer` + 放置器 prefab），科技等级 0。
- **材料**：开发期先用易得材料（见 §7），正式数值后置；数值全部集中在一张配置表里，改一处生效。
- **放置校验**（`placer.testfn`，客户端 + 服务端都跑）：
  1. 落点地形在白名单内；
  2. 该地形槽未被占用（查客户端同步的小表；服务端查权威数据）；
  3. 地面可建造（沿用原版 `CanDeployAtPoint` 的物理判定，即配方自带的放置规则）；
  4. 可选：不在某些禁建模板/特殊区域。
- **不合格时**：放置幽灵变红，且给出原因提示（原版放置器支持 `mouse_blocked` / 自定义提示）。服务端拒绝时不消耗材料、物品保留。
- 原版先例：`prefabs/yotr_rabbitshrine.lua` 用 `override_testfn` 实现"只能在特定地形上建"，是同一套写法。

### 3.2 上香激活

- 未激活的庙：`idle_off` 循环 + 灰色地图图标 + 无任何功能。
- 上香：右键 → 自定义动作 `WORSHIP`（服务端校验距离，例如 3 格内）→ 播放 `activate` → 停在 `idle_on` → 图标变亮 + 地图图标常亮（穿迷雾）。
- 激活态存入庙自身 `OnSave`；世界重载后恢复。
- **上香免费**，不消耗道具（也预留配置项，将来若要"香"道具挂钩即可）。
- 视觉模板：原版 `yoth_knightshrine` 自带 `idle_off` / `activate` / `idle_on` / `deactivate` / `place` / `hit_off` 全套状态，可直接借用其动画资源做占位（只借用 anim build，不复用其 prefab 逻辑）。备选 `resurrection_stone`（有 `idle_off` / `activate` / `idle_activate`）。

### 3.3 庙内地图传送（缩地）

1. 玩家在已激活的庙旁右键 → `打开地图` 动作（客户端发起）→ 打开**原版地图界面**。
2. 地图上每座已激活的庙显示为一个可点选的图标（§3.5 的图标机制）；未激活的庙只显示灰图标、不可点。
3. 点击图标 → 走原版的 `map_only` 动作 + `maponly_checkvalidpos_fn` 校验（原版保险库传送球就是这样做的）→ 把目标庙的实体引用发给服务端。
4. **服务端权威校验**（缺一不可）：
   - 目标庙存在、已激活、在同一分片；
   - 源端：玩家确实站在某座已激活的庙旁（距离阈值）；
   - `IsTeleportingPermittedFromPointToPoint(from, to)` 通过（挡住远古圣殿/中庭等封闭房间）；
   - 落点 `Map:IsPassableAtPoint` 可站立（配合原版 `FindWalkableOffset` 找精确落点）。
5. 传送执行：`Physics:Teleport`（含原版万达传送台那套"跟随者/背包内随从/身边重物一并搬运"的处理，可直接照抄 `travelable.lua` 的实现）。
6. 只有 `地图键` 或 `庙旁打开地图` 两种入口能触发传送动作；普通按 M 看地图时不可点选（除非持有随身地图）。

### 3.4 随身地图

- 获取方式：**在已激活的庙旁**用材料制作（方案 A：把庙设为原版科技建筑 `prototyper`，「随身地图」配方只在庙旁出现，材料不够则灰显——等于免费用上原版的"货殖"体验，零自定义 UI）。
- 属性：**永久持有、无限次使用**，不消耗。
- 效果：持有后在任意位置按地图键，即可点选任意已激活的庙传送（校验同上）。
- 定价：中期材料（提案见 §7），是整条传送网唯一的特权闸门。
- 备选方案 B（若方案 A 的科技分类在制作菜单里显示不理想）：做一个小的自定义"请一份地图"面板，显示所需材料，材料足够则可点击，消耗材料并把地图塞进背包。

### 3.5 地图图标（金光引路的等价物）

- 每座庙生成一个**全局地图图标**实体并跟随庙的位置，用原版机制实现：`RegisterGlobalMapIcon` / `GlobalMapIconsDB`，或原版现成的图标工厂 `MakeGlobalTrackingIcons(name, {icondata=...})`。
- 图标状态：未激活 = 灰暗（仅已探索区域可见）；已激活 = 常亮 + 穿迷雾（`SetDrawOverFogOfWar(true)`）。
- 选中态：原版图标支持 `selectedicon` 与 `mapselected` / `cancelmaptarget` 事件，正好用于"点选目的地"的反馈。
- 需要自制 2 张图标贴图（未激活/已激活，含选中态共 3 张），放进 mod 自己的 `minimap/` 目录并以 `MINIMAP_IMAGE` 声明。

---

## 4. 原版依据表（已逐条核对源码）

| 结论 | 原版依据 |
|---|---|
| 地块 = 4×4 世界单位 | `constants.lua:17 TILE_SCALE = 4`；`regrowthutil.lua:6` 注释 "each tile from worldgen is 4x4 game units" |
| 默认世界 425×425 格 | `map/forest_map.lua:472-484` |
| 取某点地形类型 | `TheWorld.Map:GetTileAtPoint(x, y, z)`（`componentactions.lua:2233`、`componentutil.lua:403`） |
| 取某点所在格坐标 / 改写地形 | `Map:GetTileCoordsAtPoint(pt)`、`Map:SetTile(x, y, tile)`（`prefabs/turfs.lua:12-14`） |
| 地形注册表（68 种，含发光变体与活动地板） | `tiledefs.lua`（`TileManager.AddTile`）；mod 侧亦有 `AddTile`（`modutil.lua:367`） |
| 地形 id 常量表 | `constants.lua:686 GROUND` |
| 地形官方中文名 | `scripts/languages/chinese_s.po`（`STRINGS.NAMES.TURF_*`） |
| 放置器自定义校验 | `components/placer.lua:8/24/233-236`（`testfn` / `override_testfn`）；原版先例 `prefabs/yotr_rabbitshrine.lua:457` |
| 可制作建筑 + 放置器 + 间距 | `AddRecipe2(..., {placer=..., min_spacing=...})`（`recipes.lua` 大量用例）；`constants.lua:2250-2265` 说明间距语义 |
| 「收货激活 + 状态持久化」模板 | `prefabs/yoth_knightshrine.lua`（trader/offering、`idle_off→activate→idle_on`、`OnSave/OnLoad`） |
| 自带激活前后动画的神庙资源 | `data/anim/yoth_knightshrine.zip`（含 `idle_off/activate/idle_on/deactivate1,2/hit_off/place`）；备选 `data/anim/resurrection_stone.zip` |
| 原版"地图点选传送"先例 | `screens/mapscreen.lua:376 ProcessStaticDecorations_VaultOrbTeleporter`（装饰图标 + 点击 + 传送合法性判定） |
| 地图专用动作注册 | `components/playercontroller.lua:5157-5221`（`map_only` + `maponly_checkvalidpos_fn` + `checkingmapactions`）；`screens/mapscreen.lua:577-600`（`SetNewMapTarget` / `SetInherentMapActions`） |
| 全局地图图标 | `simutil.lua:862 GlobalMapIconsDB` / `RegisterGlobalMapIcon`；`prefabs/globalmapicon.lua`（`MakeGlobalTrackingIcons`、`SetDrawOverFogOfWar`、`selectedicon`、`mapselected`） |
| 传送合法性门禁 | `componentutil.lua:1390 IsTeleportingPermittedFromPointToPoint`；封闭房间集合 `constants.lua:3053`（VAULT / LOBBYVAULT / ATRIUM） |
| 传送执行与"跟随物搬运"参考实现 | `2119742489/scripts/components/travelable.lua`（含跟随者、背包内随从、身边重物的搬运） |
| 客户端列表/状态同步写法 | `2119742489/scripts/components/travelable_replica.lua`（一个 `net_string` 打包整张表） |
| 世界级注册表（避免全图扫描） | `components/winonateleportpadmanager.lua`（`ms_register...` 事件 + `onremove` 回调） |
| RPC / replica / 动作 / SG 状态全套模板 | `2119742489/modmain.lua` |
| 距离程控与动作绑定 | `AddComponentAction("SCENE"...)`、`AddStategraphActionHandler("wilson"/"wilson_client", ActionHandler(...,"give"))` |
| mod 可用的分片通信（留给 v2 跨分片） | `modutil.lua:867-916`（`AddShardModRPCHandler` / `SendModRPCToShard`） |
| 跨分片显式坐标迁移（留给 v2） | `prefabs/player_common_extensions.lua` `DoMoveToRezPosition`（`ms_playerdespawnandmigrate{portalid=nil, x,y,z}`） |
| 区域级判定 API（若将来改"每区域一座"） | `TheSim:WorldPointInPoly(x, z, node.poly)` + `TheWorld.topology.nodes`（`regrowthutil.lua:11-16`、`wanderingtrader.lua:277`） |

---

## 5. 数据结构与文件清单

```
土地庙mod/
├── modinfo.lua                     配置项（§6）
├── modmain.lua                     注册 prefab / replica / RPC / 动作 / SG / 地图 hook / 配方
├── modicon.tex / .xml
├── minimap/                        landshrine_off.png / landshrine_on.png / ..._selected.png
├── scripts/
│   ├── landshrine_config.lua       ★ 白名单 + 材料 + 各项开关（唯一需要改数值的文件）
│   ├── prefabs/
│   │   ├── landshrine.lua          庙本体：动画状态、激活态、上香、打开地图
│   │   └── landshrine_placer.lua    放置器（含 testfn 槽位校验）
│   ├── components/
│   │   ├── landshrine.lua          服务端：激活、槽位占用、传送执行、传送校验
│   │   ├── landshrine_replica.lua  客户端：占用表同步（一个 net_string）
│   │   └── landshrinenetwork.lua   世界级：槽位占用表 + 目的地枚举 + 加载后重建
│   └── screens/
│       └── （不需要）              复用原版地图界面 + 图标装饰
└── strings.lua                     本地化（含带颜色的真菌提示）
```

数据流速览：

```
建造：放置器 testfn（地形白名单 + 槽位未占用，查客户端同步表）
      → 服务端权威复检 → 落成 → 记录地形 id 进庙存档 → 广播占用表

上香：右键 → WORSHIP 动作（服务端校验距离）→ activate 动画 → idle_on → 激活态存档

传送：庙旁/持图 → 打开原版地图 → 点选图标 → map_only 动作校验
      → 服务端复检（激活/同分片/源端在庙旁/门禁/落点可站）
      → Physics:Teleport（含跟随物搬运）

地图图标：每座庙挂一个全局图标实体，跟随其位置；未激活灰、已激活穿雾常亮
```

---

## 6. 配置项清单（`modinfo.lua`）

| 配置项 | 作用 | 默认 |
|---|---|---|
| `EnforceTerrainSlots` | 是否启用"每种地形一座" | 开 |
| `TerrainWhitelistExtra` | 追加允许的地形（逗号分隔 id） | 空 |
| `AllowDevBuildAnywhere` | **调试用**：关闭槽位与地形校验，任意位置可建 | 关 |
| `MustBeAtShrineToTeleport` | 庙内传送是否要求站在庙旁 | 开 |
| `PortableMapEnabled` | 是否提供随身地图 | 开 |
| `PortableMapCostTier` | 随身地图定价档位（廉价/中期/昂贵） | 中期 |
| `WorshipFree` | 上香是否免费 | 开 |
| `MoveFollowers` | 传送是否搬运跟随者/随从/重物 | 开 |
| `ShowInactiveOnMap` | 未激活的庙是否在地图显示灰图标 | 开 |
| `CrossShardTeleport` | 跨分片传送（v2，暂不出） | 关 |

材料数值统一放在 `landshrine_config.lua`，正式数值后置。

---

## 7. 开发期策略（材料与调试）

**原则**：材料数值不是现在的重点，先把功能链路和手感测通；所有配方集中一处、便于后期调参。

- **建庙**（开发期）：`干草 × 1 + 树枝 × 1`，科技 0。（正式值后置，提案：`木头 × 4 + 石头 × 6 + 干草 × 8`）
- **随身地图**（开发期）：同上，任意一种廉价材料 × 1。（正式提案：`金块 × 2 + 纸莎草 × 4 + 齿轮 × 1`）
- **必须保留"从制作栏建造"的完整流程**（不能只靠控制台刷庙），因为放置器校验本身就是要测的重点。
- **调试通道**（都要有）：
  1. 控制台：`c_spawn("landshrine")` 直接落一座庙、`c_give("portablemap")` 直接拿地图（跳过配方，用于测传送）；
  2. 配置项 `AllowDevBuildAnywhere`：临时关掉地形/槽位限制，用于快速迭代放置校验；
  3. 调试命令：清空占用表、强制激活/取消激活、打印当前占用表（测试时反复建拆必需）；
  4. 因为要测 21 种地形，用 `c_gonext("landshrine")` / 调试传送在各分片各生物群系之间快速跳。
- **测试清单**（每条对应一个已定规则）：
  1. 在沼泽建一座 → 再去另一处沼泽，幽灵应变红且提示"沼泽已有土地庙"；
  2. 铺一块木地板再建 → 应被拒（人造地皮不在白名单）；
  3. 建完不激活 → 地图上灰、不可点、不能传；
  4. 上香 → 动画播放、图标变亮、世界重载后仍是激活态；
  5. 庙旁点地图 → 能选中别的已激活庙并传送；落点可站立、随从一起过来；
  6. 未持地图时按 M → 只能看，不能点选传送；持地图后 → 任意位置可点选；
  7. 试着传进远古圣殿/中庭 → 应被门禁挡下并有提示；
  8. 拆庙 → 槽位释放（可在同地形再建）；多人同时在同一地形争抢 → 服务端只让一个成功。

---

## 8. 阶段计划

| 阶段 | 内容 | 完成标志 |
|---|---|---|
| **0** | 庙 prefab（占位美术）+ 放置器 + 地形槽位校验 + 客户端占用表同步 | 能按地形建庙、幽灵红绿正确、服务端拒绝不扣材料 |
| **1** | 上香激活 + 激活态持久化 + 图标双态 | 激活/未激活在地图上一眼可辨，重载后保持 |
| **2** | 地图点选传送（图标 + `map_only` 动作 + 服务端校验 + 落点与跟随物） | 庙旁可点选传送，门禁生效，作弊参数被服务端拒绝 |
| **3** | 随身地图（科技配方或自定义购买面板）+ 任意位置传送 | 购买链路走通，持有后任意位置可传 |
| **4** | 数值定稿 + 本地化 + modicon + 正式美术（自制土地庙替换占位） | 可发布 |
| **5**（后议） | 跨分片传送（地表↔洞穴，列表经分片 RPC 同步） | —— |

---

## 9. 风险与坑

| 风险 | 说明与应对 |
|---|---|
| 放置校验的客户端/服务端不一致 | 客户端只看到附近实体，必须靠同步的小表；服务端始终权威；服务端拒绝时不得扣材料 |
| 铺地皮造槽位 | 靠白名单排除人造地皮（运行时无法区分自然/人造）；这是已知的方案边界，如需彻底封堵只能改用世界生成的固定点位 |
| 地形记录被改写 | 判定只在建造时做一次并写入庙存档，之后不重算；避免"别人铺地皮导致规则漂移" |
| 先到先得引发争端 | 全服共享 21 个槽位；建议拆庙释放槽位 + 拆庙前提示"这是某人的传送点"；暂不做所有权 |
| 制作菜单里自定义科技不显示 | 方案 A 的主要不确定点；先用原版 `prototyper` + 自定义 `TECH` 试，不理想则降级到方案 B（自定义购买面板） |
| hook 原版地图界面的版本风险 | 地图装饰与 `map_only` 动作是 hook 式实现（原版 `mapscreen` / `playercontroller`），游戏大版本更新后需复测；改动集中在两个文件，影响面可控 |
| 图标资源 | 需要 3 张自制小地图贴图（未激活/已激活/选中）；`MakeGlobalTrackingIcons` 需要以 `MINIMAP_IMAGE` 声明 |
| 占位美术依赖活动资源 | 借用 `yoth_knightshrine` 动画做占位；它是随基础包分发的活动资源，低风险，但正式版仍应换自制美术 |
| 与其它传送 mod 冲突 | 自定义动作与状态用独立 id，不覆盖原版动作；SG 只添加不替换 |
| 跨分片 | v1 明确不做；`Shard_IsWorldAvailable` 判定与分片 RPC 的可行性已在 v1 设计稿中验证过，需要时可直接捡回来 |

---

## 10. 待定项

1. 建庙/随身地图的**正式材料数值**（开发期用廉价占位，§7）。
2. 随身地图的获取实现走**方案 A（原版科技配方）**还是**方案 B（自定义购买面板）**——建议先试 A。
3. 三个边界地形是否纳入：洞穴喷气孔地面、海盗海滩（月沼/暗影沼泽/黏滑地皮/档案馆已按"排除"处理）。
4. 是否长期保留 `AllowDevBuildAnywhere` 这类调试开关（建议保留但默认关）。