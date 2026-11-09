"""One-time, pixel-preserving exports from the supplied opaque sprite sheets.

The checker pattern is baked into RGB pixels. Flood-filling only near-neutral
checker pixels from each crop edge keeps enclosed light details (flowers, eyes)
while giving every exported sprite a real alpha channel.
"""

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1] / "assets" / "source"
RESOURCE = Image.open(ROOT / "资源精灵图.png").convert("RGB")
ACTOR = Image.open(ROOT / "角色四向动画帧.png").convert("RGB")


# 封装 cut 的处理，供相关流程复用。
def cut(source: Image.Image, box: tuple[int, int, int, int], name: str, trim: bool = True) -> None:
    rgb = np.asarray(source.crop(box), dtype=np.uint8)
    hi = rgb.max(axis=2).astype(np.int16)
    lo = rgb.min(axis=2).astype(np.int16)
    mean = rgb.mean(axis=2)
    checker = (hi - lo <= 12) & (mean >= 208) & (mean <= 249)
    height, width = checker.shape
    exterior = np.zeros((height, width), dtype=bool)
    queue = deque()
    for x in range(width):
        if checker[0, x]:
            queue.append((0, x))
        if checker[height - 1, x]:
            queue.append((height - 1, x))
    for y in range(height):
        if checker[y, 0]:
            queue.append((y, 0))
        if checker[y, width - 1]:
            queue.append((y, width - 1))
    while queue:
        y, x = queue.popleft()
        if exterior[y, x] or not checker[y, x]:
            continue
        exterior[y, x] = True
        if y > 0:
            queue.append((y - 1, x))
        if y + 1 < height:
            queue.append((y + 1, x))
        if x > 0:
            queue.append((y, x - 1))
        if x + 1 < width:
            queue.append((y, x + 1))
    alpha = np.where(exterior, 0, 255).astype(np.uint8)
    rgba = Image.fromarray(np.dstack((rgb, alpha)), "RGBA")
    if trim:
        bounds = rgba.getbbox()
        if bounds:
            rgba = rgba.crop(bounds)
    rgba.save(ROOT / name)
    print(f"{name}: {rgba.size}")


RESOURCE_BOXES = {
    "new_house.png": (77, 91, 339, 260),
    "new_workbench.png": (422, 108, 566, 259),
    "new_farmer_front.png": (673, 116, 757, 239),
    "new_pond.png": (858, 89, 1210, 260),
    # Equal canvas dimensions keep all land states registered at one origin.
    "new_plot_locked.png": (50, 300, 218, 458),
    "new_plot_cleared.png": (274, 300, 442, 458),
    "new_carrot_seed.png": (488, 300, 656, 458),
    "new_carrot_leaf.png": (704, 300, 872, 458),
    "new_carrot_mature.png": (914, 300, 1082, 458),
    "new_background.png": (2, 494, 1278, 657),
}

for filename, bounds in RESOURCE_BOXES.items():
    cut(RESOURCE, bounds, filename,
        trim=not filename.startswith(("new_plot_", "new_carrot_")))

X_CENTERS = (405, 575, 747, 918)
ROWS = {"down": 186, "left": 326, "right": 469, "up": 618}
for direction, bottom in ROWS.items():
    for number, center in enumerate(X_CENTERS, 1):
        cut(ACTOR, (center - 48, bottom - 128, center + 48, bottom),
            f"actor_{direction}_{number:02d}.png", trim=False)
