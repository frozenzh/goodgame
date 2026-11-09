# 掉落发放与播报

游戏内获得物品时统一调用自动加载节点 `DropService`：

```gdscript
DropService.grant_item(crop_id, amount, "plot:%s" % plot_id, "crop")
DropService.grant_item(bait_id, charges, "workbench", "bait")
DropService.grant_fish(fish_id, 1, "pond")
DropService.grant_coins(coins, "shop")
DropService.grant_fertilizer(amount, "shop")
```

接口先修改 `GameState`，随后发出 `EventBus.item_dropped`。同一帧、同一来源的同一种道具会合并数量。只需要播报、无需再次发放时可调用 `DropService.announce(item_type, item_id, amount, source_key)`。退款和 GM 直接修改数量，不算掉落。

来源键：`plot:<地块ID>`、`pond`、`workbench`、`shop`、`house`、`worker`。`StaticWorldStrip` 将来源键对应到静态世界节点，并生成 [DropToast.tscn](../scenes/world/DropToast.tscn)；该场景的 `Icon`、`Name`、`Amount` 可分别在编辑器调整。新增掉落种类时，在 `StaticWorldStrip._on_item_dropped` 中补充名称与图标读取规则。
