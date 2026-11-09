# Static world asset contract

The seven plots are generated as two complete continuous master strips. The complete locked master remains visible as one Sprite2D, while the active master is cut into seven overlays using grass-gap boundaries. This keeps the locked state perfectly continuous and allows each opened plot to appear independently.

| File | Godot node | State |
|---|---|---|
| `plots7/plots7_locked_master.png` | `PlotLayer/LockedPlotsBase` | complete locked base |
| `plots7/plot_01_active.png` | `PlotNodes/Plot01/ActiveSprite` | left opened overlay |
| `plots7/plot_02_active.png` | `PlotNodes/Plot02/ActiveSprite` | opened overlay 02 |
| `plots7/plot_03_active.png` | `PlotNodes/Plot03/ActiveSprite` | opened overlay 03 |
| `plots7/plot_04_active.png` | `PlotNodes/Plot04/ActiveSprite` | opened overlay 04 |
| `plots7/plot_05_active.png` | `PlotNodes/Plot05/ActiveSprite` | opened overlay 05 |
| `plots7/plot_06_active.png` | `PlotNodes/Plot06/ActiveSprite` | opened overlay 06 |
| `plots7/plot_07_active.png` | `PlotNodes/Plot07/ActiveSprite` | right opened overlay |

The normalized masters are `plots7_locked_master.png` and `plots7_active_master.png`. Both use a 532×90 transparent canvas. Active slices have variable widths because cuts pass through natural grass gaps instead of through a plot.

Every `PlotXX` is an independent static `Node2D` containing `ActiveSprite`, `HitArea`, and `InteractionPoint`. Toggle the exported `unlocked` property to show or hide its active overlay. By default only Plot06 and Plot07 are unlocked.

The active master is assembled from the locked master: only the seven soil and immediate fence rectangles come from the active generation. The lower path and all surrounding grass, flowers and outer rocks remain pixel-identical. Rebuild the two masters and seven active overlays with `tools/build_seven_plot_states.py`.

Other world resources remain:

| File | Godot node | Baseline |
|---|---|---|
| `world_house.png` | `ResourceNodes/House` | bottom aligned |
| `world_workbench.png` | `ResourceNodes/Workbench` | bottom aligned |
| `world_pond.png` | `ResourceNodes/Pond` | bottom aligned |
| `world_tree.png` | `ResourceNodes/TreeDecoration` | bottom aligned |

All images use transparent backgrounds and Nearest texture filtering.
