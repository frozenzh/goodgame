# Godot 场景拼接与 UI 静态节点规范

本项目的视觉位置与尺寸由 Godot 场景负责，脚本只负责读取数据、填入文字或图标、切换可见状态、连接操作。策划和场景拼接人员应能打开 `.tscn`，不运行游戏就找到并调整主要画面元素。本规范适用于后续所有 UI、弹窗、建筑和可重复列表。

## 一、必须遵守的边界

1. **永久显示或反复打开的 UI 必须先有静态节点。** 背景、标题区、按钮区、滚动区、点击区、位置和尺寸保存在 `.tscn`。不要在 `_ready()` 或打开弹窗时用 `PanelContainer.new()`、`Button.new()` 拼出完整界面。
2. **每类弹窗独立占位。** 池塘、重置和离线弹窗在 `Main.tscn` 中保存位置和宽高；小屋、工作台、图鉴、鱼铺、种植、设置分别位于独立的 `*Window.tscn`。鱼详情直接填入图鉴右侧资料区。原生子窗口尺寸在各自根节点编辑。小屋和工作台默认跟随对应建筑，图鉴跟随池塘，鱼铺跟随鱼铺建筑。种植、图鉴、设置共用 `StaticPopupFrame.tscn`；小屋和工作台保留带滚动区的 `PopupFrame.tscn`。
3. **重复数据先使用静态槽位。** 种植、鱼饵、鱼铺和图鉴的现有条目在 `.tscn` 中预置可见卡片，运行时复用这些节点并只填名称、图标、数量、价格、倍率等数据；配置条目超过预置数量时，才从对应卡片模板补充实例。不得在打开窗口时清空静态槽位。
4. **建筑和地块都以图片为点击范围。** 图片、阴影、碰撞、特效锚点放在 `StaticWorldStrip.tscn`。小屋、工具台、鱼铺、池塘和七块地直接按当前可见 `Sprite2D` 的不透明像素响应点击，修建木牌按 `Board` 图片响应；移动或缩放图片后点击范围同步变化。角色前往点放在世界场景的 `DynamicAnchors/WorkerTargets`，仍须单独检查。
5. **允许少量跟随型 UI。** 地块进度提示跟随地块交互点；闪光特效是临时实例。这些元素的相对偏移和视觉结构仍必须可在场景中编辑。桌面窗口的整体等比缩放不属于场景内部拼接。
6. **目录从项目根目录到底最多四层文件夹。** 新 UI 模板放 `scenes/ui/`，世界资源放 `scenes/world/`，对应脚本放 `scripts/ui/` 或 `scripts/world/`；不要为单一功能建立多层嵌套目录。
7. **新逻辑替代旧逻辑时同步清理失效节点。** 完成功能修改后，核对场景节点的脚本引用、信号、碰撞层和实际用途；删除不再参与运行或编辑的旧节点、仅供它使用的资源与失效文档路径。保留编辑器预览节点时要说明其用途和运行时替换方式。
8. **嵌套场景只在所属场景调整内部布局。** `Main.tscn` 只挂载种植、小屋、工作台、鱼铺、图鉴、设置六个原生子窗口；这些实例不得开启“可编辑子节点”，主场景也不得保存窗口内部控件的属性覆盖。窗口内部拼接在各自的 `*Window.tscn` 和内容场景调整，卡片共同样式在卡片模板场景调整。保存主场景后可运行 `ruby tools/normalize_main_windows.rb --check` 检查是否误写覆盖。
9. **点击窗口外关闭当前弹窗，窗口内不穿透。** 主游戏内的池塘、重置、离线等弹窗由主窗口空白点击关闭；六个原生子窗口在点击主游戏或失去窗口焦点时关闭。`PopupFrame`、`StaticPopupFrame` 和作物进度面板接住内部鼠标事件；弹窗打开时主场景暂停建筑与地块的点击判定。

## 二、当前静态节点地图

| 功能 | 场景中可调的位置与尺寸 | 可调的内部结构 / 模板 |
| --- | --- | --- |
| 普通弹窗外框 | `scenes/main/Main.tscn` → `PondPopup`、`ResetPopup`、`OfflinePopup` | `scenes/ui/PopupFrame.tscn`，每个实例都开启了 Editable Children |
| 小屋原生子窗口 | `scenes/ui/CottageWindow.tscn` → `CottagePopup` | 木框和 `InfoActionsContent` 都可独立编辑；默认显示于小屋上方 |
| 工作台原生子窗口 | `scenes/ui/WorkbenchWindow.tscn` → `WorkbenchPopup/ContentSurface/WorkbenchContent` | 使用与图鉴相同的木框；`CategoryTabs` 是鱼饵/鱼竿一级菜单，`ItemsViewport/ItemGrid` 是四列八张静态条目卡，`DetailPanel` 内有目标图文、三个静态材料槽和数量/制作节点；默认显示于工具台上方 |
| 钓鱼选饵与选竿原生子窗口 | `scenes/ui/PondWindow.tscn` → `PondPopup/ContentSurface/PondContent` | `CategoryTabs/BaitTab` 与 `RodTab` 是静态一级菜单；`BaitViewport/BaitGrid` 预置八张鱼饵卡，`RodViewport/RodGrid` 预置四张鱼竿卡。选中态为 `PondBaitCard.tscn/SelectedCheck` 中心对勾；两页卡片区域可分别调整。 |
| 种植原生子窗口 | `PlantWindow.tscn/PlotPopup/ContentSurface/PlotContent/SelectionBoard/CropContainer/CropViewport/CropRow` | `CropSlot01～08` 在编辑器中可见；`CropContainer` 控制整排位置，`CropRow` 管理间距，单张卡片的图标与文字在 `CropChoiceCard.tscn` 调整 |
| 设置原生子窗口 | `scenes/ui/SettingsWindow.tscn` → `SettingsPopup/ContentSurface/SettingsContent` | 内板、开关行、重置和操作说明各可单独调整 |
| 小屋、池塘、重置、离线结算 | 各自弹窗的 `InfoActionsContent` 实例 | `InfoActionsContent.tscn`；每个实例可分别移动说明、选项和四个操作位 |
| 鱼铺原生子窗口 | `scenes/ui/ShopWindow.tscn` → `ShopPopup/…/Body/ShopContent` | `ShopContent.tscn` 的左右分栏、八张 `OwnedSlot` 鱼卡、三张 `OfferSlot` 高价卡、标题牌和按钮均为静态节点 |
| 图鉴原生子窗口 | `scenes/ui/CodexWindow.tscn` → `CodexPopup/ContentSurface/CodexContent` | `StaticPopupFrame.tscn` 浅木框；`CodexContent.tscn` 的顶部一级和二级筛选、左侧独立滚动卡片、右侧资料卡；鱼、植物、鱼饵和成就卡片各有模板 |
| 鱼详情 | `CodexWindow/CodexPopup/ContentSurface/CodexContent/PreviewPanel` | 点击鱼卡更新右侧 `PreviewName`、`PreviewIcon`、`PreviewInfo`、`PreviewStatus`；没有二级弹窗 |
| 通用操作按钮 | 各弹窗内容场景中的按钮实例 | `PrimaryButton.tscn`、`SecondaryButton.tscn` |
| 货币、图鉴/设置入口、提示条、土地进度 | `Main.tscn` → `Overlay`、`Notification`、`PlotProgressAnchor` | 木牌、图标、数值、按钮均为独立子节点 |
| 鱼塘成就提示条 | `Main.tscn` → `AchievementToast` | 位于鱼塘上方的 UI 层；在主场景调整整体位置和尺寸，在 `scenes/ui/AchievementToast.tscn` 调整木框、图标、标题与成就名；脚本只填图文和控制出现、消失。 |
| 天气显示条 | `Main.tscn/Overlay/WeatherBar` | `Sunny`、`Rain`、`Snow` 三个静态方块；每个方块都有独立的 `Icon`、`Dim` 灰色遮罩、`Highlight` 当前天气框、`Hover` 悬停框和 `HoverHit` 悬停范围。`HoverTooltip` 是可移动、可调整尺寸的静态提示框，文字分别在 `Content/Title`、`Content/Effect`；天气效果由 `WeatherSystem` 填入。 |
| 建筑和地块视觉 | `StaticWorldStrip.tscn` → `ResourceNodes`、`PlotLayer` | 小屋三级外观、工具台、鱼铺、池塘、地块状态、阴影和碰撞各自为静态节点 |
| 建筑点击范围 | `Main.tscn/StaticWorldStrip/ResourceNodes` → 各建筑的可见 `Sprite2D` | 贴图的不透明像素就是点击范围；直接移动、缩放资源图片即可，不另设建筑按钮 |
| 地块点击范围 | `Main.tscn/StaticWorldStrip/PlotLayer/PlotNodes` → `Plot01`～`Plot07` | 从右向左编号 1～7；当前显示的未开垦、已开垦及作物图片共同决定点击范围，移动整块 `PlotTile` 时范围同步 |

## 三、在编辑器中调整

打开 `scenes/main/Main.tscn`，在场景树选中普通 `*Popup`，于 Inspector 修改 `offset_left/top/right/bottom`。主场景的六个 `*Window` 只用于挂载实例；要调整内部节点，双击窗口场景图标打开对应的 `*Window.tscn`，不要在主场景开启“可编辑子节点”。图鉴请打开 `scenes/ui/CodexWindow.tscn`：选根节点调整原生子窗口宽高；“桌面定位 → Follow Pond”默认开启。“Gap To Main”控制子窗口底边与主游戏顶边的距离：`0` 为贴合，正数拉开，负数会重叠；“Pond Offset”用于微调，正 X 向右、正 Y 向下。若要设置绝对桌面位置，关闭 Follow Pond，再编辑根节点 `Window → Position`。选 `CodexPopup` 调木框，打开 `CodexContent.tscn` 调右侧 `PreviewPanel` 及其文字、图片节点。调整设置和种植窗口时，分别打开 `scenes/ui/SettingsWindow.tscn` 和 `scenes/ui/PlantWindow.tscn`，选根节点调整尺寸和 `Desktop Offset`，关闭 `Follow Main` 后可用 `Window → Position` 设桌面坐标。临时勾选弹窗的 **Visible** 预览，保存前取消。三个内容场景均直接位于对应弹窗的 `ContentSurface`，没有外层无用滚动槽。修改浅木框、标题木牌和关闭按钮请打开 `StaticPopupFrame.tscn`。种植作物卡请在 `PlantWindow.tscn` 展开 `PlotPopup/ContentSurface/PlotContent/SelectionBoard/CropContainer/CropViewport/CropRow`；八张 `CropSlot` 已有预览图片和文字。整体位置调 `CropContainer`，批量间距调 `CropRow` 的 Separation，单卡内部图标文字在 `CropChoiceCard.tscn` 中调整，八张卡片各自的预览数据在 `CropSelectionBoard.tscn` 中调整。

主场景中的 `*Window` 实例不要覆盖根节点的 `Force Native`、`Desktop Offset`、`Size` 等属性，否则主场景实例会与独立打开的窗口场景显示不同。设置窗口的这几项统一在 `SettingsWindow.tscn` 根节点调整；内容位置统一在该场景的静态子节点调整。

鱼铺请打开 `scenes/ui/ShopWindow.tscn`：根节点的 `Window → Size` 控制子窗口尺寸，默认 `840×380`；`桌面定位 → Follow Shop` 默认开启，窗口横向居中于 `StaticWorldStrip/ResourceNodes/ShopBuilding`，顶部纵坐标与图鉴一致。`Shop Offset` 可微调位置；关闭 Follow Shop 后，可直接用 `Window → Position` 固定桌面位置。编辑 `ShopPopup` 木框和 `ShopContent` 两栏时，保持根节点与弹窗默认不可见，避免启动时出现空窗口。

小屋和工作台分别打开 `CottageWindow.tscn`、`WorkbenchWindow.tscn`。根节点 `Window → Size` 控制子窗口尺寸；开启 `Follow Main` 时，窗口横向跟随对应建筑，显示在主游戏上方，`Desktop Offset` 可微调；关闭 `Follow Main` 后，用 `Window → Position` 设置绝对桌面位置。内容仍在 `CottagePopup/…/InfoActionsContent` 和 `WorkbenchPopup/…/WorkbenchContent` 静态节点中编辑。

工作台的顶部一级菜单在 `WorkbenchContent/CategoryTabs`，四列鱼饵或鱼竿卡在 `ItemsViewport/ItemGrid`，右侧大图和说明在 `DetailPanel`。八张 `ItemSlot`、三张 `Material`、数量加减按钮和制作按钮都已保存为静态节点；卡片内部的图标与名字分别在 `WorkbenchItemCard.tscn`、`WorkbenchMaterialCard.tscn` 调整。脚本只填写数据并控制显示状态，不改这些节点的位置或尺寸。

主窗口现在采用 `1280×168` 可见画布。`Main.tscn` 根节点保留原有 `230` 高度的场景坐标，并整体上移 `62`；因此场景内建筑、地块和锚点的相对位置无需重排。调整普通弹窗时，以实际可见窗口为界：其场景局部 Y 坐标须落在 `62～230` 内。地块的成熟/阶段提示位于 `Main.tscn/PlotProgressAnchor/Panel`，该静态节点默认显示在地块右侧；脚本仅移动锚点并确保整块面板留在可见范围。

鱼铺按文档的“左侧鱼背包 / 右侧三格高价收购”结构拼接。`ShopWindow.tscn/ShopPopup` 使用 `assets/hd/ui/shop_v04/shop_panel_blank.png` 整张透明木框；`ShopContent.tscn` 的 `OwnedSection`、`HighPriceSection`、标题牌、刷新倒计时、数量选择器及出售按钮都是静态可调节点。`ShopOwnedCard.tscn` 和 `ShopOfferCard.tscn` 使用独立的透明鱼卡图片，名称、图标、数量、价格、倍率由脚本填入，未烘焙在底图中。木框、鱼卡、绿色/金色按钮、刷新图标均位于 `assets/hd/ui/shop_v04/`，可以逐张替换。配置鱼铺等级增加到四、五个收购位时，卡片沿横向滚动，不压缩卡片。

`OwnedScroll/OwnedGrid` 的八个静态 `OwnedSlot` 与超过八种鱼后补充的运行时卡片共用 `ShopOwnedCard.tscn`。当前 `ShopWindow.tscn` 已把 `OwnedSlot01` 的鱼名、鱼图、库存木牌和价格行布局逐项复制给 `OwnedSlot02～08`，鱼图缩放也一致；各卡在 `OwnedGrid` 中的位置未改。`ShopOwnedCard.tscn` 同步保存这一布局，供运行时新增卡片使用。若以后只改窗口实例中的 `OwnedSlot01`，其他实例不会自动同步；需要全体长期同步时，应修改 `ShopOwnedCard.tscn`。

高价收购区的 `OfferSlot01～03` 同样以第一张卡当前的内部样式为基准：鱼名、鱼图、价格行、价格文字颜色和倍率木牌在三个静态槽中一致；`ShopOfferCard.tscn` 保存相同布局供超出三个槽位时实例化。`OffersRow` 中各卡的排列位置由容器管理，不靠复制第一张卡的根节点位置。

鱼铺的 `SellSelected` 与 `SellAll` 已采用 `Button/Background/Label` 静态结构。`Button` 自身的各状态样式为空，只处理点击；绿色和金色 UI 图片分别在子节点 `Background → Texture` 中，文字在 `Label` 中。更换单个按钮背景时直接替换该 `Texture` 资源，不需要修改共用的 `GreenButtonArt`、`GoldButtonArt`。运行时禁用按钮会将整组图片与文字轻微变淡。

图鉴的一级分类、鱼品质二级筛选和卡片内容是三块平级静态组件。打开 `CodexContent.tscn` 可分别移动顶部 `PrimaryMenu`、`SecondaryMenu` 和左侧 `EntriesViewport`，右侧 `PreviewPanel` 也可独立调整。两个菜单始终固定，只有 `EntriesViewport` 纵向滚动。点击鱼卡只刷新右侧资料区，列出鱼名、品质、偏好类型、喜爱鱼饵和售价，选中卡有绿色边框。`CodexEntries.tscn` 预置十二张鱼卡、八张植物卡和八张鱼饵卡；在编辑器中临时切换 `CropPage` / `BaitPage` 的 Visible 可查看对应布局。分别打开 `FishCodexCard.tscn`、`CropCodexCard.tscn`、`BaitCodexCard.tscn` 调整单卡图标与名称。浅木框资源位于 `assets/hd/ui/popup_frame_light.png`，标题牌和浅卡片同目录；图片外围为真实透明像素。

图鉴新增第四个一级页签 `AchievementTab`。成就使用同一右侧 `PreviewPanel`，左侧是独立的 `CodexContent/AchievementPage` 滚动区；在 `AchievementPage.tscn` 中可直接看到新手、发展、成型三个标题和十二张静态成就卡。单卡图标、名称、条件、进度条、完成标记与点击范围在 `AchievementCard.tscn` 调整。运行时只更新数据、图标和选中状态，不重排节点。运行资源在 `assets/ui/achievements/`，高分辨率制作源在 `assets/source/achievements/`。

图鉴筛选按钮在 `CodexPrimaryMenu.tscn` 和 `CodexSecondaryMenu.tscn` 中直接保存为 `按钮/Background/Label` 三层静态节点。选 `Background`，在 Inspector 的 **Texture** 替换平时的底图；选按钮根节点，在 **Selected Background** 替换悬停和当前选中时的底图；选 `Label` 调文字位置、字号、颜色。按钮本身仅保留点击范围，不绘制文字和背景。调整单个按钮的宽高请选其根节点修改 `Custom Minimum Size`，子节点会随之缩放。运行时仅更新 Label 内容和选中底图，不会重建节点。

建筑请在 `Main.tscn/StaticWorldStrip/ResourceNodes` 中编辑。鱼铺为 `ShopBuilding`，图片、`GroundShadow` 阴影和碰撞都在其子节点中；调整 `Sprite` 图片位置或缩放时，其实际可见部分的点击范围会自动同步。阴影与角色碰撞可单独移动。地块在 `StaticWorldStrip/PlotLayer/PlotNodes` 中直接调整，已经没有独立的 `FarmStrip` 按钮层。最后检查 `DynamicAnchors/WorkerTargets/ShopPoint` 角色目标点；其他建筑同理。旧版未被读取的 `FunctionalZones` 已删除。

## 四、改动验收清单

- 打开主场景后，所有持续存在的 UI 和建筑都能从场景树定位；每种弹窗有独立根节点。
- 修改弹窗内节点的位置和大小后，运行时不被脚本覆盖；原生子窗口的桌面位置由其 `Follow` 与偏移参数控制。
- 新列表先复用场景中可见的静态卡片槽，配置数量超出时才补卡；脚本不即时创建底板、标题牌或按钮皮肤。
- 普通弹窗不越过 1280×168 可见主画布；图鉴、鱼铺、设置和种植仅显示在独立原生子窗口；较长内容在静态 `ScrollContainer` 内滚动。
- 建筑移动后复查碰撞、角色目标点与特效锚点；建筑图片本身就是点击范围。
- 修改后运行 `tests/smoke_test.gd` 和 `tests/ui_scene_contract_test.gd` 的无窗口校验；视觉与手感仍需在 Godot 编辑器中人工查看。

鱼铺界面的木框、鱼卡和按钮现在全部使用静态图片资源拼接；脚本仅绑定鱼铺数据与点击逻辑。原有 `FarmStrip` 与其独立点击按钮已删除。
