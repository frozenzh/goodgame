# 塘边小日子 Godot MVP

这是根据《桌面挂机钓鱼种田 MVP 完整方案 v0.6》实现的 Godot 4.x 原型。游戏以桌面底部窄条运行，玩家负责种植、配饵、选饵和扩建，角色自动完成劳动。

## 启动

1. 使用 Godot 4.3 或更新的 Godot 4.x 版本导入本目录。
2. 运行主场景 `scenes/main/Main.tscn`。
3. 首次启动会加载 `data/catalog`，并在用户数据目录创建单槽存档。

本机可直接使用现有模拟器启动：

```bash
/Users/frozen/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/frozen/myfavorite
```

## 目录

- `data/catalog`：策划配置，JSON 可直接调参。
- `assets/world`：静态世界模块图，统一透明画布与底部基线。
- `docs`：玩法浓缩说明与数据字段约定。
- `scenes`：主场景、静态世界节点树与界面场景。
- `scripts/autoload`：全局状态、数据、时间与存档。
- `scripts/systems`：种植、制饵、钓鱼、商店、图鉴和任务逻辑。
- `scripts/ui`：场景表现与交互适配。
- `tests`：核心闭环烟测与界面捕获脚本。

静态世界由 `scenes/world/StaticWorldStrip.tscn` 组织，按背景表现、7 个独立地块、可调建筑和动态挂点分层。地块节点从右向左命名为 Plot01～Plot07，默认仅最右侧的 Plot01、Plot02 解锁。开垦 3～5 号地块需要小屋 2 级，开垦 6～7 号需要小屋 3 级；解锁费用与小屋等级要求记录在 `data/catalog/upgrades.json`。建筑、木牌和地块直接以可见图片的不透明像素响应点击；移动或缩放图片后，无需再调整独立热区。资源规格与替换约定见 `assets/PLACEHOLDERS.md`。

作物成熟后留在地里，点击任意成熟地块的“收获所有成熟地块”，角色会依次走到每块地收获；勾选过“收获后一直种植”的地块会在这一轮收获任务之后再播种。离线只推进成熟时间，不直接收获。角色工作时朝上播放动画，并在头顶显示半透明的 3 秒操作进度条；可在 `scenes/world/Worker.tscn` 调整其静态节点。

左侧四组货币 HUD 直接放在 `scenes/main/Main.tscn` 的 `Overlay` 下，分别为 `CoinGroup`、`CropGroup`、`FishGroup`、`BaitGroup`；每组只有 `Board`、`Icon`、`Amount` 三个静态子节点，移动组节点可整体调整，子节点也可单独微调。右侧图鉴和设置仍是独立静态节点及点击区。图标使用 `assets/ui/icon_*_simple.png` 和最近邻采样；脚本只刷新数值、连接按钮。旧的 `ResourceBar.tscn` 与 `UtilityButtons.tscn` 不再被主场景实例化。

主背景右上角的静态 `Main/GMButton` 打开 `scenes/ui/GMWindow.tscn` 原生子窗口。子窗口可按 ID 增加金币、鱼肥、配置表中的植物、鱼饵或鱼，催熟所有已种植且尚未成熟的地块，并切换晴、雨、雪。按钮、标签、输入框、位置与大小可直接在 GMWindow 场景中调整；旧的 Inspector 货币覆盖节点已经删除。

Godot 项目的默认视口为 2560×336。现有世界和 UI 保持 1280×168 的逻辑坐标，通过 2 倍画布缩放以 2K 宽度输出；桌面运行时仍按屏幕可用区域等比适配。

所有菜单面板以 `Overlay` 的实际可用区域为边界居中，标题和内容都放在同一个滚动区域，不再保留固定顶部；图鉴、工作台和种植菜单使用紧凑网格/列表。

设置弹窗内保留“重置进度”按钮，点击后仍需二次确认。GM 子窗口的资源操作仅在明确点击按钮后生效，不会在下次启动时重复覆盖存档。

钓鱼弹窗的“空闲时自动钓鱼”默认关闭；关闭时没有任务的角色只会闲逛，手动“开始钓鱼”仍可用。小屋升级先扣费进入修建阶段（时长在 `data/catalog/cottage_levels.json` 的 `build_seconds` 调整），修建叠层和木牌位于 `StaticWorldStrip/ResourceNodes/House/ConstructionVisual`。木牌变成“点击完成”后点它，才正式升级并播放闪光。

## MVP 闭环

种植并点击收获 → 工作台制饵与选饵 → 手动或勾选空闲自动钓鱼 → 鱼铺批量出售或制成鱼肥 → 扩地和修建小屋 → 根据鱼图鉴线索决定下一轮生产。

## 调试建议

- 输出警告和错误应使用 `push_warning` / `push_error`，便于在 Godot 调试器中定位。
- 运行时可从 **场景 → 远程** 检查节点状态。
- 存档相关测试前先备份 `user://save.json`。

核心闭环自动化检查：

```bash
/Users/frozen/Downloads/Godot.app/Contents/MacOS/Godot --headless --path /Users/frozen/myfavorite --script res://tests/smoke_test.gd
```
