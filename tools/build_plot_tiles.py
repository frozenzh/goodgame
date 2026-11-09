from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
WORLD = ROOT / "assets" / "world"
OUTPUT = WORLD / "plots"
CANVAS_SIZE = (80, 90)
CONTENT_SIZE = (76, 86)

# Crop one complete, repeatable plot from the processed strip resources. Keeping
# this deterministic means regenerated tiles retain identical anchors and scale.
STATES = {
    # The active strip is 350 px wide. The 88 px cuts share the original
    # boundaries, while left/right keep the authored outer caps.
    "plot_active_left": ("world_land_active.png", (0, 50, 88, 150)),
    "plot_active_middle": ("world_land_active.png", (88, 50, 176, 150)),
    "plot_active_right": ("world_land_active.png", (262, 50, 350, 150)),
    # The locked strip uses 90 px quarters; resize them to the same 88 px
    # content width so both states keep an identical anchor and seam spacing.
    "plot_locked_left": ("world_land_locked.png", (0, 50, 90, 150)),
    "plot_locked_middle": ("world_land_locked.png", (90, 50, 180, 150)),
    "plot_locked_right": ("world_land_locked.png", (270, 50, 360, 150)),
}


# 构建 tile，供调用方继续处理。
def build_tile(output_name: str, source_name: str, crop_box: tuple[int, int, int, int]) -> None:
    source = Image.open(WORLD / source_name).convert("RGBA")
    tile = source.crop(crop_box)
    tile = tile.resize(CONTENT_SIZE, Image.Resampling.NEAREST)
    alpha = tile.getchannel("A").point(lambda value: 0 if value < 24 else value)
    tile.putalpha(alpha)

    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    x = (CANVAS_SIZE[0] - tile.width) // 2
    y = CANVAS_SIZE[1] - tile.height
    canvas.alpha_composite(tile, (x, y))
    canvas.save(OUTPUT / f"{output_name}.png", optimize=True)


# 组织工具的输入、处理和输出流程。
def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for output_name, (source_name, crop_box) in STATES.items():
        build_tile(output_name, source_name, crop_box)
        print(f"created {OUTPUT / (output_name + '.png')}")


if __name__ == "__main__":
    main()
