# 高清资源（当前场景使用）

- `world/`：草地长背景、小屋、工具台、鱼塘，以及空地、共享生长阶段和各作物成熟地块。
- `worker/`：主角四方向行走 16 帧、钓鱼 8 帧、待机 8 帧；每帧独立 PNG。
- `ui/`：木牌与 HUD 图标；图标和木牌仍是独立静态节点。
- `atlases/`：基于原始精灵图生成的高清主图，供重新裁切/锚点配准。

`assets/source/` 与 `assets/ui/` 中保留原始资源作为参照；游戏场景已改为引用这里的高清资源。`tools/process_hd_atlases.gd` 可从 `atlases/` 重建地块和角色单帧，`tools/process_hd_remaining.gd` 可重建 UI 资源。长背景以 `assets/source/background_2k_generated.png` 为生成源图，由 `tools/process_seamless_background.gd` 裁去透明画布、校准左右接缝并输出 2048×256 的 `world/background.png`；不要再用旧背景处理流程覆盖它。

所有地块状态在 `PlotTile.tscn/StateVisuals` 下。`plot_seed.png` 和 `plot_leaf.png` 被六种作物共用；成熟图按作物分别使用 `mature_*.png`。`tools/process_mature_crops.gd` 用空地的可见边界对齐所有状态资源，防止种植前后地块跳位。运行时已开垦地块始终显示 `ClearedSprite` 作为草边底图，种子、叶片和六种成熟图统一缩至其内部土地区域（当前统一缩放为 0.115、偏移为 4/-2，使四侧均保留土壤过渡）。选中任一 `PlotTile` 实例，在 Inspector 设置 `preview_stage`、`preview_crop` 预览；打开 `preview_alignment_overlay` 可叠加空地与当前状态来校准，再移动 `StateVisuals` 或其中单个 Sprite。已种植地块的阶段进度小窗是 `Main.tscn/PlotProgressAnchor` 静态节点，位置与尺寸可在其 `Panel` 子节点调整。

保持旧的 1280×230 逻辑坐标与静态节点位置，采用 `canvas_items` 在实际窗口分辨率绘制；桌面实际窗口可等比放大到 2048×368。要微调位置，请在 `scenes/world/StaticWorldStrip.tscn`、`scenes/world/PlotTile.tscn`、`scenes/world/Worker.tscn` 和 `scenes/main/Main.tscn` 中调整各独立节点。

小屋四级静态外观在 `StaticWorldStrip/ResourceNodes/House/LevelVisuals/Level1–4`：1 级茅草房使用 `world/house_level_0_thatch.png`，2 级使用用户提供的 `world/house_level_1_reference.png`，3 级使用整修版 `world/house_level_2_matching.png`，4 级使用加高版 `world/house_level_3_matching.png`。各等级可在静态节点中分别调整。建筑底边可通过独立的 `GroundContact` 和 `FrontGrass` 节点对齐。

新增植物的成熟期九宫格在 `PlotTile/StateVisuals/Mature_<植物ID>_Cells`，20 种植物各有独立静态组；可调组位置，也可调九个 `Cell_行_列` 的位置。选择 `PlotTile`，勾选 `unlocked`，将 `preview_stage` 设为 `mature`、`preview_crop` 填植物 ID，即可在编辑器预览对应图片。运行时只替换图片和按植物表计算大小，不覆盖静态节点位置。

鱼铺在 `StaticWorldStrip/ResourceNodes/ShopBuilding/LevelVisuals/Level1–3` 也有静态可调节点。1 级使用 `ui/shop_v04/fish_shop_level_1_topdown_v3.png`（与小屋相同的双斜屋面视角）；2、3 级保留原外观。游戏按 `shop_level` 切换可见性。工具台使用缩短台面纵深的 `world/workbench_topdown_v3.png`，可在独立的 `Sprite` 节点调整。
