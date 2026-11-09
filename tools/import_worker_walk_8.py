"""Build aligned walk frames from the regenerated transparent animation sheets.

The right-facing sheet is mirrored for left-facing motion so both directions
share exactly the same gait. Each output stays on the existing 1024px canvas;
Worker.tscn keeps its original sprite position and scale.
"""

from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source"
OUTPUT = ROOT / "assets/hd/worker/frames"
PREVIEW = ROOT / "assets/previews/worker_walk_8_preview.png"
MOTION_PREVIEW = ROOT / "assets/previews/worker_walk_8_motion.gif"
SHEETS = {
    "down": SOURCE / "worker_walk_regenerated_down.png",
    "right": SOURCE / "worker_walk_regenerated_right.png",
    "up": SOURCE / "worker_walk_regenerated_up.png",
}
CANVAS_SIZE = 1024
CONTENT_HEIGHT = 840
FOOT_Y = 940


# 封装 split 的处理，供相关流程复用。
def split(sheet_path: Path) -> list[Image.Image]:
    sheet = Image.open(sheet_path).convert("RGBA")
    width, height = sheet.size
    frames: list[Image.Image] = []
    for row in range(2):
        for col in range(4):
            cell = sheet.crop((round(col * width / 4), round(row * height / 2),
                               round((col + 1) * width / 4), round((row + 1) * height / 2)))
            alpha = cell.getchannel("A")
            # Ignore tiny semitransparent specks outside the character.
            bounds = alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()
            if bounds is None:
                raise ValueError(f"Empty sprite at row {row}, column {col}: {sheet_path}")
            pad = 2
            bounds = (max(0, bounds[0] - pad), max(0, bounds[1] - pad),
                      min(cell.width, bounds[2] + pad), min(cell.height, bounds[3] + pad))
            cut = cell.crop(bounds)
            cut.putalpha(cut.getchannel("A").point(lambda value: value if value >= 24 else 0))
            cut = cut.crop(cut.getbbox())
            frames.append(cut)
    return frames


# 封装 register 的处理，供相关流程复用。
def register(cuts: list[Image.Image]) -> list[Image.Image]:
    scale = CONTENT_HEIGHT / max(cut.height for cut in cuts)
    result: list[Image.Image] = []
    for cut in cuts:
        sprite = cut.resize((round(cut.width * scale), round(cut.height * scale)),
                            Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
        frame.alpha_composite(sprite, ((CANVAS_SIZE - sprite.width) // 2,
                                       FOOT_Y - sprite.height))
        result.append(frame)
    return result


# 组织工具的输入、处理和输出流程。
def main() -> None:
    frames = {direction: register(split(path)) for direction, path in SHEETS.items()}
    frames["left"] = [ImageOps.mirror(frame) for frame in frames["right"]]
    preview = Image.new("RGBA", (4 * 128, 8 * 128), (0, 0, 0, 0))
    motion: list[Image.Image] = []
    for col, direction in enumerate(("down", "left", "right", "up")):
        for row, frame in enumerate(frames[direction]):
            frame.save(OUTPUT / f"actor_{direction}_{row + 1:02d}.png")
            preview.alpha_composite(frame.resize((128, 128), Image.Resampling.NEAREST),
                                    (col * 128, row * 128))
        print(f"{direction}: {len(frames[direction])} frames")
    preview.save(PREVIEW)
    for row in range(8):
        strip = Image.new("RGBA", (4 * 128, 128), (232, 222, 198, 255))
        for col, direction in enumerate(("down", "left", "right", "up")):
            strip.alpha_composite(frames[direction][row].resize((128, 128), Image.Resampling.NEAREST),
                                  (col * 128, 0))
        motion.append(strip.convert("RGB"))
    motion[0].save(MOTION_PREVIEW, save_all=True, append_images=motion[1:],
                   duration=100, loop=0, optimize=False)


if __name__ == "__main__":
    main()
