# MVP JSON 数据规范

本规范定义 `data/catalog/` 下的静态配置与初始状态格式。目标是让 Godot 4.x 通过 `FileAccess.get_file_as_string()` 与 `JSON.parse_string()` 直接加载，无需自定义文本预处理器。

## 1. 通用约定

- 编码：UTF-8；标准 JSON；不允许注释、尾随逗号、`NaN` 或 `Infinity`。
- ID：稳定的英文 `snake_case` 字符串；存档只保存 ID，不保存显示名。
- 根对象：目录表使用 `schema_version`、`catalog_type`、`items`；扩展表可以在根对象增加具名数组。
- 数值：时间统一为秒；价格、数量、等级为非负整数；权重和倍率为非负 JSON number。
- 字典：库存、配方和倍率表使用 `{string: number}`；缺少键时读取为 0 或默认倍率 1.0。
- 引用：所有跨表引用必须指向存在的 ID；加载后应构建 `id -> item` 字典并拒绝重复 ID。
- 兼容：增加可选字段时递增 `schema_version` 仅在旧读取器无法安全忽略新字段时进行；存档迁移由 `save_version` 单独控制。

Godot 加载示例：

```gdscript
func load_json(path: String) -> Dictionary:
    var text := FileAccess.get_file_as_string(path)
    var parsed: Variant = JSON.parse_string(text)
    assert(parsed is Dictionary, "Invalid JSON root: %s" % path)
    return parsed as Dictionary
```

## 2. 文件清单

| 文件 | `catalog_type` | 主用途 |
|---|---|---|
| `crops.json` | `crops` | 作物成本、时间、产量与配方关系 |
| `baits.json` | `baits` | 制作配方、批量次数与掉落权重修正 |
| `fish.json` | `fish` | 鱼基础权重、价值、池塘等级与图鉴线索 |
| `upgrades.json` | `upgrades` | 开垦、鱼竿、池塘、里程碑与肥沃度；小屋另见 `cottage_levels.json` |
| `shop_items.json` | `shop_items` | 鱼铺可购买物品 |
| `initial_state.json` | `initial_state` | 新存档完整默认值，不是静态条目列表 |
| `cottage_levels.json` | `cottage_levels` | 小屋三级外观、升级价格、作物仓库容量与工作台等级 |

## 3. 通用条件对象

`unlock_condition` 是带 `type` 的对象。MVP 支持以下形态：

```json
{"type": "initial"}
{"type": "shop_unlocked"}
{"type": "fish_codex_count", "value": 4}
{"type": "upgrade_owned", "id": "unlock_plot_5"}
```

条件判断必须集中在 UnlockSystem 或等价模块，内容脚本不得按具体 ID 写分支。

## 4. crops.json

每个 `items[]` 为一个作物：

| 字段 | 类型 | 必需 | 规则 |
|---|---|---:|---|
| `id` | String | 是 | 全局唯一作物 ID |
| `display_name` | String | 是 | UI 名称 |
| `grow_seconds` | int | 是 | 基础生长秒数，必须大于 0 |
| `plant_cost` | int | 是 | 每地块播种金币 |
| `harvest_amount` | int | 是 | 每块成熟地每次收获获得的作物道具数量，必须大于 0；来源为 `excel/植物.xlsx` |
| `unlock_condition` | Dictionary | 是 | 通用条件对象 |
| `codex_hint` | String | 是 | 未解锁/未发现时可展示线索 |
| `codex_desc` | String | 是 | 已发现说明 |
| `bait_links` | Array[String] | 是 | 可制作的鱼饵 ID |
| `growth_stage_count` | int | 是 | 美术生长阶段数，MVP 为 3 |

实际成熟时间：`grow_seconds * fertility.grow_time_multiplier`，结果按整秒取整且最少为 1。

## 5. baits.json

| 字段 | 类型 | 必需 | 规则 |
|---|---|---:|---|
| `id` | String | 是 | 全局唯一鱼饵 ID |
| `display_name` | String | 是 | UI 名称 |
| `source` | String | 是 | `craft` 或 `shop` |
| `required_workbench_tier` | int | 否 | 制作所需的最低工作台等级；缺省为 1 |
| `recipe` | Dictionary[String,int] | 是 | 制作材料；商店饵为空对象 |
| `charges_per_batch` | int | 是 | 制成或买到一包后增加的出杆次数 |
| `craft_seconds` | int | 是 | 工作表现时间；商店饵为 0 |
| `unlock_condition` | Dictionary | 是 | 配方或购买资格 |
| `tag_weight_multipliers` | Dictionary[String,float] | 是 | 按鱼标签相乘 |
| `fish_weight_multipliers` | Dictionary[String,float] | 是 | 对指定鱼再相乘 |
| `codex_hint` | String | 是 | 未发现线索 |
| `codex_desc` | String | 是 | 已发现说明 |

某条鱼的最终权重按以下顺序计算：

```text
weight = fish.base_weight
weight *= bait.tag_weight_multipliers 中该鱼每个标签对应倍率，缺省 1.0
weight *= bait.fish_weight_multipliers[fish.id]，缺省 1.0
weight *= rod.rare_weight_multiplier，仅 rarity 为 rare/special 时应用
```

仅将 `fish.unlock_pond_level <= state.pond_level` 且最终权重大于 0 的鱼加入抽取池。标签倍率采用逐项相乘，因此同一鱼命中多个标签时会形成更强偏向；这是有意设计。

## 6. fish.json

| 字段 | 类型 | 必需 | 规则 |
|---|---|---:|---|
| `id` | String | 是 | 全局唯一鱼 ID |
| `display_name` | String | 是 | UI 名称 |
| `rarity` | String | 是 | `common`、`uncommon`、`rare`、`special` |
| `base_weight` | float | 是 | 大于 0 的基础抽取权重，不是百分比 |
| `sell_price` | int | 是 | 鱼铺单条售价 |
| `fertilizer_value` | int | 是 | 制肥贡献值 |
| `unlock_pond_level` | int | 是 | 1 或 2 |
| `tags` | Array[String] | 是 | 鱼饵倍率匹配标签 |
| `preferred_baits` | Array[String] | 是 | 图鉴展示与验证用鱼饵 ID |
| `codex_hint` | String | 是 | 未发现时的可行动线索 |
| `codex_desc` | String | 是 | 已发现说明 |

权重表只决定相对概率。抽取时对所有候选权重求和，再使用 `[0, total_weight)` 的随机值选择。

## 7. upgrades.json

### 7.1 upgrades.items

| 字段 | 类型 | 必需 | 规则 |
|---|---|---:|---|
| `id` | String | 是 | 升级 ID，也写入 `owned_upgrades` |
| `display_name` | String | 是 | UI 名称 |
| `category` | String | 是 | `plot_unlock`、`rod`、`cottage`、`pond` |
| `cost` | int | 是 | 金币价格 |
| `prerequisites` | Array[String] | 是 | 必须已经拥有的升级 ID |
| `unlock_condition` | Dictionary | 是 | 额外显示/购买条件 |
| `effects` | Array[Dictionary] | 是 | 购买成功后按顺序应用 |
| `repeatable` | bool | 是 | MVP 全为 false |

支持的 `effects[].type`：`unlock_plots`、`unlock_rod`、`fish_interval_multiplier`、`rare_weight_multiplier`、`fertilizer_yield_multiplier`、`set_pond_level`、`set_base_fish_interval_seconds`。小屋升级统一由 `cottage_levels.json` 定义并通过小屋交互执行。

### 7.2 rods

鱼竿字段为 `id`、`display_name`、`fish_interval_multiplier`、`rare_weight_multiplier`、`unlock_condition`。最终出杆间隔：

```text
state.base_fish_interval_seconds * selected_rod.fish_interval_multiplier
```

### 7.3 codex_milestones

`fish_count` 是首次发现鱼数量门槛；`rewards` 支持 `unlock_crops`、`unlock_baits`、`unlock_upgrade`、`coins`、`set_flag`。发放后将数字写入 `claimed_codex_milestones`，禁止重复领取。

### 7.4 fertility_levels

`level` 从 0 连续递增；`grow_time_multiplier` 作用于基础生长时间；`fertilizer_cost` 是将单块地从前一级提升到该级所需鱼肥。

## 8. shop_items.json

| 字段 | 类型 | 必需 | 规则 |
|---|---|---:|---|
| `id` | String | 是 | 商店条目 ID |
| `item_type` | String | 是 | MVP 为 `bait` |
| `item_id` | String | 是 | `baits.json` 中的鱼饵 ID |
| `buy_price` | int | 是 | 每包金币价格 |
| `pack_amount` | int | 是 | 购买后加入库存的次数 |
| `unlock_condition` | Dictionary | 是 | MVP 为鱼铺已解锁 |
| `shop_only` | bool | 是 | 为 true 时禁止工作台制作 |
| `repeatable` | bool | 是 | 是否可重复购买 |
| `sort_order` | int | 是 | UI 排序 |
| `description` | String | 是 | UI 简述 |

购买必须是原子操作：先验证金币与条件，再扣金币并增加 `inventory[item_id]`，随后发出一次购买事件。

## 9. initial_state.json

这是新存档模板，字段必须深拷贝后再运行，不能直接修改 DataRegistry 中的模板对象。

| 字段组 | 说明 |
|---|---|
| `save_version` | 运行存档迁移的版本号 |
| `coins` | 当前金币 |
| `inventory` | 作物、鱼饵、鱼肥库存；鱼不放在这里 |
| `fish_basket` | `{fish_id: count}`；初始为空对象 |
| `discovered_*` | 图鉴永久发现 ID 数组 |
| `claimed_codex_milestones` | 已领取的 4/8/12 数字数组 |
| `unlocked_*` | 当前可种作物、可制作/选择鱼饵、可选鱼竿 |
| `owned_upgrades` | 已购买升级 ID |
| `plots` | 固定 7 个地块状态；默认仅最右侧两块（ID 5、6）解锁 |
| `pond_level`、`cottage_level` | 建筑等级 |
| `workbench_unlocked`、`shop_unlocked` | 默认均为 false；首次解锁植物 / 鱼类图鉴后，点击对应建筑木牌并等待角色完成操作才置 true |
| `selected_bait`、`selected_rod` | 当前配置；空鱼饵为 `""` |
| `base_fish_interval_seconds` | 当前池塘基础出杆间隔 |
| `offline_cap_seconds` | 28800，即 8 小时 |
| `last_save_unix` | 首次创建后立即写入当前 Unix 秒 |
| `flags` | 一次性流程标记 |
| `settings` | 窗口、动画和音频默认值 |

地块对象字段：`plot_id`、`unlocked`、`state`、`crop_id`、`planted_at`、`mature_at`、`fertility_level`。`state` 只允许 `LOCKED`、`EMPTY`、`GROWING`、`HARVEST_FX`；只有 `GROWING` 可以拥有非空 `crop_id` 和大于 0 的时间戳。

## 10. 加载后验证

DataRegistry 完成全部文件加载后必须执行以下检查；任一失败应在开发构建中中止启动并打印文件与 ID：

1. 每个目录内 ID 唯一，且数量固定为作物 6、鱼饵 4、鱼 12。
2. `bait_links`、`preferred_baits`、配方材料、商店 `item_id` 和所有升级前置引用均存在。
3. 每个鱼饵至少产生一个大于 0 的可捕获鱼权重；每条鱼至少有一个合法鱼饵与池塘等级组合。
4. 作物时间、产量、售价、批量、升级价格均为正数；倍率大于 0。
5. 初始状态恰有 7 个连续 `plot_id`，其中 0–4 锁定、最右侧的 5–6 解锁。
6. `selected_rod` 已解锁；非空 `selected_bait` 必须已解锁且库存大于 0。
7. 初始金币足以在 4 块田至少种一轮小麦；第一批面团饵可在 5 分钟左右取得材料。
8. 保存时不写回静态目录对象；缺失的新字段通过 `initial_state.json` 默认值补齐。
