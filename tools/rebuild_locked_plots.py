from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source"
PLOTS = ROOT / "assets" / "world" / "plots"

# The generated images contribute only the uncleared soil contents. Every pixel
# outside target_box is copied unchanged from the active plot template.
VARIANTS = {
    "left": {
        "generated": "plot_locked_left_generated_v2.png",
        "source_box": (400, 650, 1135, 1020),
        "target_box": (24, 41, 67, 59),
    },
    "middle": {
        "generated": "plot_locked_middle_generated_v2.png",
        "source_box": (295, 650, 1005, 985),
        "target_box": (15, 41, 66, 59),
    },
    "right": {
        "generated": "plot_locked_right_generated_v2.png",
        "source_box": (75, 690, 820, 1005),
        "target_box": (0, 41, 48, 59),
    },
}


# 封装 rebuild 的处理，供相关流程复用。
def rebuild(role: str, config: dict) -> None:
    active_path = PLOTS / f"plot_active_{role}.png"
    locked_path = PLOTS / f"plot_locked_{role}.png"
    active = Image.open(active_path).convert("RGBA")
    generated = Image.open(SOURCE / config["generated"]).convert("RGBA")

    target_box = config["target_box"]
    target_size = (target_box[2] - target_box[0], target_box[3] - target_box[1])
    soil = generated.crop(config["source_box"]).resize(target_size, Image.Resampling.NEAREST)

    result = active.copy()
    result.alpha_composite(soil, (target_box[0], target_box[1]))

    # Invariant: fence, side decorations and lower path must be byte-identical
    # to the active template. Only the inner soil rectangle may differ.
    active_pixels = active.load()
    result_pixels = result.load()
    for y in range(active.height):
        for x in range(active.width):
            inside = target_box[0] <= x < target_box[2] and target_box[1] <= y < target_box[3]
            if not inside and result_pixels[x, y] != active_pixels[x, y]:
                raise RuntimeError(f"{role}: non-soil pixel changed at {(x, y)}")

    result.save(locked_path, optimize=True)
    print(f"replaced {locked_path}")


# 组织工具的输入、处理和输出流程。
def main() -> None:
    for role, config in VARIANTS.items():
        rebuild(role, config)


if __name__ == "__main__":
    main()
