from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source"
OUTPUT = ROOT / "assets" / "world" / "plots7"

LOCKED_SOURCE = SOURCE / "plots7_locked_master_generated.png"
ACTIVE_SOURCE = SOURCE / "plots7_active_master_generated.png"

# Each box covers one soil rectangle plus the immediate fence area. Everything
# outside these boxes is copied from the locked master without modification.
PLOT_EDIT_BOXES = [
    (105, 245, 350, 418),
    (378, 245, 623, 418),
    (642, 245, 887, 418),
    (910, 245, 1155, 418),
    (1174, 245, 1419, 418),
    (1440, 245, 1685, 418),
    (1705, 245, 1950, 418),
]

# Cuts pass through the grass gaps between plots. Both states use exactly the
# same cuts, so all slice boundaries and outside decoration remain aligned.
SOURCE_CUTS = [0, 365, 634, 902, 1167, 1432, 1698, 2172]
SOURCE_CROP = (0, 190, 2172, 500)
VISIBLE_HEIGHT = 76
CANVAS_HEIGHT = 90


# 封装 normalize 的处理，供相关流程复用。
def normalize(image: Image.Image) -> Image.Image:
    cropped = image.crop(SOURCE_CROP)
    scale = VISIBLE_HEIGHT / cropped.height
    size = (round(cropped.width * scale), VISIBLE_HEIGHT)
    resized = cropped.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (resized.width, CANVAS_HEIGHT), (0, 0, 0, 0))
    canvas.alpha_composite(resized, (0, CANVAS_HEIGHT - VISIBLE_HEIGHT))
    return canvas


# 封装 scaled_x 的处理，供相关流程复用。
def scaled_x(source_x: int, output_width: int) -> int:
    return round((source_x - SOURCE_CROP[0]) * output_width / (SOURCE_CROP[2] - SOURCE_CROP[0]))


# 组织工具的输入、处理和输出流程。
def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    locked_source = Image.open(LOCKED_SOURCE).convert("RGBA")
    active_generated = Image.open(ACTIVE_SOURCE).convert("RGBA")
    if locked_source.size != active_generated.size:
        raise RuntimeError("Locked and active masters must share one source canvas")

    active_source = locked_source.copy()
    for box in PLOT_EDIT_BOXES:
        active_source.alpha_composite(active_generated.crop(box), (box[0], box[1]))

    locked_master = normalize(locked_source)
    active_master = normalize(active_source)
    locked_master.save(OUTPUT / "plots7_locked_master.png", optimize=True)
    active_master.save(OUTPUT / "plots7_active_master.png", optimize=True)

    cuts = [scaled_x(value, locked_master.width) for value in SOURCE_CUTS]
    cuts[0] = 0
    cuts[-1] = locked_master.width
    rebuilt_active = Image.new("RGBA", active_master.size, (0, 0, 0, 0))
    for index in range(7):
        box = (cuts[index], 0, cuts[index + 1], CANVAS_HEIGHT)
        active_slice = active_master.crop(box)
        active_slice.save(OUTPUT / f"plot_{index + 1:02d}_active.png", optimize=True)
        rebuilt_active.alpha_composite(active_slice, (cuts[index], 0))
        print(f"active plot {index + 1:02d}: x={cuts[index]}..{cuts[index + 1]}, width={box[2] - box[0]}")

    difference = Image.new("RGBA", active_master.size, (0, 0, 0, 0))
    difference = Image.frombytes(
        "RGBA",
        active_master.size,
        bytes(a ^ b for a, b in zip(active_master.tobytes(), rebuilt_active.tobytes())),
    )
    if difference.getbbox() is not None:
        raise RuntimeError("Active slices do not reconstruct the active master exactly")


if __name__ == "__main__":
    main()
