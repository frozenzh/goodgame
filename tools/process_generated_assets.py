from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source"
OUTPUT = ROOT / "assets" / "world"

ASSETS = {
    "world_land_locked": ("world_land_locked_source.png", (360, 150)),
    "world_land_active": ("world_land_active_source.png", (350, 150)),
    "world_house": ("world_house_source.png", (165, 170)),
    "world_workbench": ("world_workbench_source.png", (150, 145)),
    "world_pond": ("world_pond_source.png", (390, 165)),
    "world_tree": ("world_tree_source.png", (120, 150)),
}


# 封装 process 的处理，供相关流程复用。
def process(source_name: str, target_size: tuple[int, int], output_name: str) -> None:
    image = Image.open(SOURCE / source_name).convert("RGBA")
    alpha = image.getchannel("A")
    solid_mask = alpha.point(lambda value: 255 if value >= 32 else 0)
    bbox = solid_mask.getbbox()
    if bbox is None:
        raise RuntimeError(f"No visible pixels in {source_name}")

    image = image.crop(bbox)
    alpha = image.getchannel("A").point(lambda value: 0 if value < 24 else value)
    image.putalpha(alpha)

    max_width = target_size[0] - 4
    max_height = target_size[1] - 4
    scale = min(max_width / image.width, max_height / image.height)
    resized_size = (
        max(1, round(image.width * scale)),
        max(1, round(image.height * scale)),
    )
    image = image.resize(resized_size, Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", target_size, (0, 0, 0, 0))
    x = (target_size[0] - image.width) // 2
    y = target_size[1] - image.height - 2
    canvas.alpha_composite(image, (x, y))
    canvas.save(OUTPUT / f"{output_name}.png", optimize=True)


# 组织工具的输入、处理和输出流程。
def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for output_name, (source_name, target_size) in ASSETS.items():
        process(source_name, target_size, output_name)
        print(f"created {OUTPUT / (output_name + '.png')}")


if __name__ == "__main__":
    main()
