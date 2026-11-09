#!/usr/bin/env python3
"""Export parameter and catalog workbooks to Godot JSON using only the Python standard library.

Usage: python3 excel/export.py [--check]
"""

from __future__ import annotations

import argparse
import json
import math
import posixpath
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parent.parent
EXCEL_DIR = ROOT / "excel"
OUTPUT_DIR = ROOT / "data" / "config"
CATALOG_DIR = ROOT / "data" / "catalog"
TEXT_DIR = ROOT / "data" / "text"
WORKBOOKS = {
    "角色.xlsx": "worker",
    "钓鱼.xlsx": "fishing",
    "种植.xlsx": "farming",
    "随机事件.xlsx": "random_events",
    "时间存档.xlsx": "time_save",
    "界面.xlsx": "ui",
    "商店.xlsx": "shop",
    "天气.xlsx": "weather",
    "牧场.xlsx": "pasture",
}
HEADERS = ("key", "中文备注", "value", "type", "min", "max", "description")
TEXT_HEADERS = ("id", "中文", "English", "来源备注")
CROP_COLUMNS = (
    "id", "中文备注", "display_name", "grow_seconds", "plant_cost",
    "harvest_amount", "bait_type", "bait_links", "growth_stage_count",
    "initially_unlocked", "seed_resource", "leaf_resource",
    "mature_resource", "icon_resource", "rarity",
    "mutation_chance", "mature_visual_width", "mature_visual_height",
    "unlock_crop_1", "unlock_amount_1", "unlock_crop_2", "unlock_amount_2",
    "unlock_crop_3", "unlock_amount_3",
    "sell_price",
)
FISH_COLUMNS = (
    "id", "中文备注", "display_name", "rarity", "preferred_bait_type",
    "base_weight", "sell_price", "icon_resource", "icon_region_x",
    "icon_region_y", "icon_region_width", "icon_region_height", "favorite_bait_id",
)
CATALOG_WORKBOOKS = {
    "植物.xlsx": ("crops", CROP_COLUMNS),
    "鱼.xlsx": ("fish", FISH_COLUMNS),
}
WORKBENCH_BAIT_COLUMNS = (
    "id", "中文备注", "display_name", "rarity", "bait_type", "source_crop",
    "ingredient_1_id", "ingredient_1_count", "ingredient_2_id", "ingredient_2_count",
    "ingredient_3_id", "ingredient_3_count", "charges_per_batch", "craft_seconds",
    "required_workbench_tier", "icon_resource",
)
WORKBENCH_ROD_COLUMNS = (
    "id", "中文备注", "display_name", "tier", "rarity", "max_fish_rarity",
    "upgrade_cost", "icon_resource",
)
ACHIEVEMENT_COLUMNS = (
    "id", "中文备注", "stage", "sort_order", "name", "description",
    "metric", "target", "icon_locked", "icon_unlocked",
)
PASTURE_PRODUCT_COLUMNS = (
    "id", "中文备注", "display_name", "source_animal", "sell_price", "icon_resource", "rarity",
)
ACHIEVEMENT_STAGES = {"beginner", "development", "formed"}
ACHIEVEMENT_METRICS = {
    "harvest_successes", "bait_craft_successes", "fish_catch_successes",
    "fish_sale_successes", "crafted_bait_variety", "fish_species",
    "cottage_level", "unlocked_plots", "upgraded_rod_catches",
}
BAIT_TYPES = {"grain", "root", "fruit", "leaf"}
ITEM_RARITIES = {"common", "good", "rare", "epic"}
NS = {
    "m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "p": "http://schemas.openxmlformats.org/package/2006/relationships",
}
PAIR_CHECKS = {
    "worker": (
        ("world_x_min", "world_x_max"),
        ("world_y_min", "world_y_max"),
        ("wander_walk_min_seconds", "wander_walk_max_seconds"),
        ("wander_rest_min_seconds", "wander_rest_max_seconds"),
        ("fish_break_min_count", "fish_break_max_count"),
        ("fish_break_min_seconds", "fish_break_max_seconds"),
        ("fish_retry_min_seconds", "fish_retry_max_seconds"),
    ),
    "fishing": (
        ("cast_min_seconds", "cast_max_seconds"),
        ("common_size_min_cm", "common_size_max_cm"),
        ("good_size_min_cm", "good_size_max_cm"),
        ("rare_size_min_cm", "rare_size_max_cm"),
        ("epic_size_min_cm", "epic_size_max_cm"),
    ),
    "random_events": (("delay_min_seconds", "delay_max_seconds"),),
    "shop": (
        ("level_1_multiplier_min", "level_1_multiplier_max"),
        ("level_2_multiplier_min", "level_2_multiplier_max"),
        ("level_3_multiplier_min", "level_3_multiplier_max"),
    ),
    "weather": (("duration_min_seconds", "duration_max_seconds"), ("wind_gust_min_seconds", "wind_gust_max_seconds")),
}


# 封装 column_number 的处理，供相关流程复用。
def _column_number(reference: str) -> int:
    letters = re.match(r"[A-Z]+", reference)
    if letters is None:
        raise ValueError(f"Invalid cell reference: {reference}")
    number = 0
    for char in letters.group():
        number = number * 26 + ord(char) - ord("A") + 1
    return number - 1


# 封装 sheet_rows 的处理，供相关流程复用。
def _sheet_rows(path: Path, sheet_name: str = "参数", column_count: int = len(HEADERS)) -> list[list[object | None]]:
    with ZipFile(path) as archive:
        strings: list[str] = []
        if "xl/sharedStrings.xml" in archive.namelist():
            shared = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            strings = ["".join(node.text or "" for node in item.findall(".//m:t", NS)) for item in shared.findall("m:si", NS)]
        workbook = ET.fromstring(archive.read("xl/workbook.xml"))
        sheets = workbook.findall("m:sheets/m:sheet", NS)
        target_sheet = next((sheet for sheet in sheets if sheet.attrib.get("name") == sheet_name), None)
        if target_sheet is None:
            raise ValueError(f"{path.name}: missing sheet {sheet_name}")
        relationship_id = target_sheet.attrib[f"{{{NS['r']}}}id"]
        relationships = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        target = next((rel.attrib["Target"] for rel in relationships if rel.attrib.get("Id") == relationship_id), None)
        if target is None:
            raise ValueError(f"{path.name}: broken sheet relationship")
        sheet_path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        sheet_path = posixpath.normpath(sheet_path)
        worksheet = ET.fromstring(archive.read(sheet_path))
        result: list[list[object | None]] = []
        for row in worksheet.findall("m:sheetData/m:row", NS):
            values: list[object | None] = [None] * column_count
            for cell in row.findall("m:c", NS):
                column = _column_number(cell.attrib.get("r", ""))
                if column >= column_count:
                    continue
                if cell.find("m:f", NS) is not None:
                    raise ValueError(f"{path.name}!{cell.attrib['r']}: formulas are not supported in config values")
                raw = cell.find("m:v", NS)
                kind = cell.attrib.get("t", "n")
                if kind == "inlineStr":
                    inline = cell.find("m:is", NS)
                    value: object | None = "".join(node.text or "" for node in inline.findall(".//m:t", NS)) if inline is not None else ""
                elif raw is None:
                    value = None
                elif kind == "s":
                    value = strings[int(raw.text or "0")]
                elif kind == "b":
                    value = raw.text == "1"
                elif kind in ("str", "e"):
                    value = raw.text or ""
                else:
                    number = float(raw.text or "0")
                    value = int(number) if number.is_integer() else number
                values[column] = value
            result.append(values)
        return result


# 封装 number 的处理，供相关流程复用。
def _number(value: object | None, where: str) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise ValueError(f"{where}: enter a numeric Excel value, not text")
    return value


# 读取 module，供调用方继续处理。
def _read_module(path: Path, module: str) -> dict[str, object]:
    rows = _sheet_rows(path)
    if not rows or tuple(rows[0]) != HEADERS:
        raise ValueError(f"{path.name}: first row must be {', '.join(HEADERS)}")
    values: dict[str, object] = {}
    for row_number, row in enumerate(rows[1:], start=2):
        key, chinese_note, raw, value_type, minimum, maximum, _description = row
        if key is None and all(value is None for value in row):
            continue
        where = f"{path.name}!{row_number}"
        if not isinstance(key, str) or re.fullmatch(r"[a-z][a-z0-9_]*", key) is None:
            raise ValueError(f"{where}: key must use lowercase letters, digits and underscores")
        if key in values:
            raise ValueError(f"{where}: duplicate key {key}")
        if not isinstance(chinese_note, str) or not chinese_note.strip():
            raise ValueError(f"{where}: 中文备注 must be non-empty text")
        if value_type == "int":
            number = _number(raw, where)
            if int(number) != number:
                raise ValueError(f"{where}: {key} must be an integer")
            value: object = int(number)
        elif value_type == "float":
            value = float(_number(raw, where))
        elif value_type == "bool":
            if not isinstance(raw, bool):
                raise ValueError(f"{where}: {key} must be an Excel boolean")
            value = raw
        elif value_type == "string":
            if not isinstance(raw, str):
                raise ValueError(f"{where}: {key} must be text")
            value = raw
        else:
            raise ValueError(f"{where}: unsupported type {value_type!r}")
        if value_type in ("int", "float"):
            if minimum is not None and float(value) < _number(minimum, where + " min"):
                raise ValueError(f"{where}: {key} below minimum {minimum}")
            if maximum is not None and float(value) > _number(maximum, where + " max"):
                raise ValueError(f"{where}: {key} above maximum {maximum}")
        values[key] = value
    for low, high in PAIR_CHECKS.get(module, ()):
        if low not in values or high not in values or values[low] > values[high]:
            raise ValueError(f"{path.name}: expected {low} <= {high}")
    if module == "worker" and not values["world_y_min"] <= values["safe_lane_y"] <= values["world_y_max"]:
        raise ValueError(f"{path.name}: safe_lane_y must be inside the world Y limits")
    if module == "weather":
        if sum(int(values[key]) for key in ("sunny_weight", "rain_weight", "snow_weight", "wind_weight")) <= 0:
            raise ValueError(f"{path.name}: at least one weather weight must be positive")
        for kind in ("rain", "snow"):
            if values[f"{kind}_particles_low"] > values[f"{kind}_particles_standard"]:
                raise ValueError(f"{path.name}: {kind}_particles_low cannot exceed standard")
    if not values:
        raise ValueError(f"{path.name}: no parameters found")
    return values


# 封装 text 的处理，供相关流程复用。
def _text(value: object | None, where: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{where}: enter non-empty text")
    return value.strip()


# 封装 integer 的处理，供相关流程复用。
def _integer(value: object | None, where: str, minimum: int = 0) -> int:
    number = _number(value, where)
    if int(number) != number or number < minimum:
        raise ValueError(f"{where}: enter an integer >= {minimum}")
    return int(number)


# 封装 resource 的处理，供相关流程复用。
def _resource(value: object | None, where: str) -> str:
    resource = _text(value, where)
    asset_root = (ROOT / "assets").resolve()
    asset_path = (ROOT / resource.removeprefix("res://")).resolve()
    if not resource.startswith("res://assets/") or not asset_path.is_relative_to(asset_root) or not asset_path.is_file():
        raise ValueError(f"{where}: resource must be an existing res://assets/ file")
    if Path(resource).suffix.lower() not in {".png", ".webp", ".jpg", ".jpeg", ".svg"}:
        raise ValueError(f"{where}: resource must be an image")
    return resource


# 读取 texts，供调用方继续处理。
def _read_texts(path: Path) -> dict[str, dict[str, str]]:
    rows = _sheet_rows(path, "文本", len(TEXT_HEADERS))
    if not rows or tuple(rows[0]) != TEXT_HEADERS:
        raise ValueError(f"{path.name}: first row must be {', '.join(TEXT_HEADERS)}")
    texts: dict[str, dict[str, str]] = {}
    placeholder = re.compile(r"(?<!%)%(?!%)(?:[-+0 #]*\d*(?:\.\d+)?)?[disf]")
    for row_number, row in enumerate(rows[1:], 2):
        if all(value is None for value in row):
            continue
        key, chinese, english, _source = row
        where = f"{path.name}!{row_number}"
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_.-]*", key):
            raise ValueError(f"{where}: invalid text id")
        if key in texts:
            raise ValueError(f"{where}: duplicate text id {key}")
        if not isinstance(chinese, str) or not chinese.strip():
            raise ValueError(f"{where}: 中文 must be non-empty")
        if not isinstance(english, str) or not english.strip():
            raise ValueError(f"{where}: English must be non-empty")
        if sorted(placeholder.findall(chinese)) != sorted(placeholder.findall(english)):
            raise ValueError(f"{where}: English placeholders do not match Chinese placeholders")
        texts[key] = {"zh": chinese, "en": english}
    if not texts:
        raise ValueError(f"{path.name}: no texts found")
    return texts


# 校验 text_sources，供调用方继续处理。
def _validate_text_sources(texts: dict[str, dict[str, str]]) -> None:
    """Catch new Chinese UI copy that was added without a text-table ID."""
    quoted = re.compile(r'"(?:\\.|[^"\\])*"')
    chinese = re.compile(r"[\u3400-\u9fff]")
    scene_property = re.compile(r'^(text|placeholder_text|tooltip_text|title) = ("(?:\\.|[^"\\])*")$')
    for path in (ROOT / "scripts").rglob("*.gd"):
        if path.name == "pond_content_preview.gd":
            continue  # Editor-only preview choices are not game copy.
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith(("#", "@export", "editor_description")):
                continue
            for match in quoted.finditer(line):
                value = json.loads(match.group())
                if chinese.search(value):
                    raise ValueError(f"{path.relative_to(ROOT)}:{line_number}: use a text ID for player-facing Chinese")
                if value.startswith("ui.") and value not in texts:
                    raise ValueError(f"{path.relative_to(ROOT)}:{line_number}: missing text ID {value}")
    for path in (ROOT / "scenes").rglob("*.tscn"):
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            matched = scene_property.match(line)
            if matched and chinese.search(json.loads(matched.group(2))):
                expected = f"metadata/l10n_{matched.group(1)} = "
                metadata_line = None
                for following in lines[index + 1:]:
                    if following.startswith("["):
                        break
                    if following.startswith(expected):
                        metadata_line = following
                        break
                if metadata_line is None:
                    raise ValueError(f"{path.relative_to(ROOT)}:{index + 1}: add {expected.strip()} with an ID")
                key = json.loads(metadata_line.partition(" = ")[2])
                if key in texts and texts[key]["zh"] != json.loads(matched.group(2)):
                    raise ValueError(f"{path.relative_to(ROOT)}:{index + 1}: scene preview differs from {key} 中文")
            if line.startswith("metadata/l10n_"):
                key = json.loads(line.partition(" = ")[2])
                if key not in texts:
                    raise ValueError(f"{path.relative_to(ROOT)}:{index + 1}: missing text ID {key}")


# 读取 catalog，供调用方继续处理。
def _read_catalog(path: Path, category: str, columns: tuple[str, ...]) -> list[dict[str, object]]:
    rows = _sheet_rows(path, "数据", len(columns))
    if len(rows) < 3 or tuple(rows[0]) != columns:
        raise ValueError(f"{path.name}: first row must be {', '.join(columns)}")
    if any(not isinstance(note, str) or not note.strip() for note in rows[1]):
        raise ValueError(f"{path.name}: second row must explain every column in Chinese")
    items: list[dict[str, object]] = []
    ids: set[str] = set()
    for row_number, row in enumerate(rows[2:], start=3):
        if all(value is None for value in row):
            continue
        where = f"{path.name}!{row_number}"
        entry = dict(zip(columns, row))
        entry_id = _text(entry["id"], where + " id")
        if re.fullmatch(r"[a-z][a-z0-9_]*", entry_id) is None or entry_id in ids:
            raise ValueError(f"{where}: id must be unique lowercase letters/digits/underscores")
        ids.add(entry_id)
        item: dict[str, object] = {
            "id": entry_id,
            "display_name": _text(entry["display_name"], where + " display_name"),
        }
        _text(entry["中文备注"], where + " 中文备注")
        if category == "crops":
            rarity = _text(entry["rarity"], where + " rarity")
            if rarity not in ITEM_RARITIES:
                raise ValueError(f"{where}: rarity must be one of {sorted(ITEM_RARITIES)}")
            item["rarity"] = rarity
            item["grow_seconds"] = _integer(entry["grow_seconds"], where + " grow_seconds", 1)
            item["plant_cost"] = _integer(entry["plant_cost"], where + " plant_cost")
            item["harvest_amount"] = _integer(entry["harvest_amount"], where + " harvest_amount", 1)
            item["sell_price"] = _integer(entry["sell_price"], where + " sell_price", 1)
            if item["sell_price"] * item["harvest_amount"] <= item["plant_cost"]:
                raise ValueError(f"{where}: one plant's sale revenue must exceed planting cost")
            mutation_chance = float(_number(entry["mutation_chance"], where + " mutation_chance"))
            if mutation_chance < 0.0 or mutation_chance > 1.0:
                raise ValueError(f"{where}: mutation_chance must be between 0 and 1")
            item["mutation_chance"] = mutation_chance
            item["mature_visual_width"] = _integer(entry["mature_visual_width"], where + " mature_visual_width", 1)
            item["mature_visual_height"] = _integer(entry["mature_visual_height"], where + " mature_visual_height", 1)
            bait_type = _text(entry["bait_type"], where + " bait_type")
            if bait_type not in BAIT_TYPES:
                raise ValueError(f"{where}: bait_type must be one of {sorted(BAIT_TYPES)}")
            item["bait_type"] = bait_type
            links = entry["bait_links"]
            if links is not None and not isinstance(links, str):
                raise ValueError(f"{where}: bait_links must be comma-separated text or blank")
            item["bait_links"] = [part.strip() for part in (links or "").replace(";", ",").split(",") if part.strip()]
            item["growth_stage_count"] = _integer(entry["growth_stage_count"], where + " growth_stage_count", 3)
            if item["growth_stage_count"] != 3:
                raise ValueError(f"{where}: current visual system supports exactly 3 growth stages")
            if not isinstance(entry["initially_unlocked"], bool):
                raise ValueError(f"{where}: initially_unlocked must be an Excel boolean")
            item["initially_unlocked"] = entry["initially_unlocked"]
            requirements: list[dict[str, object]] = []
            requirement_ids: set[str] = set()
            for index in range(1, 4):
                required_crop = entry[f"unlock_crop_{index}"]
                required_amount = entry[f"unlock_amount_{index}"]
                if required_crop in (None, ""):
                    if required_amount not in (None, 0):
                        raise ValueError(f"{where}: unlock_amount_{index} requires unlock_crop_{index}")
                    continue
                required_id = _text(required_crop, where + f" unlock_crop_{index}")
                if re.fullmatch(r"[a-z][a-z0-9_]*", required_id) is None or required_id in requirement_ids:
                    raise ValueError(f"{where}: prerequisite crop IDs must be unique lowercase identifiers")
                requirement_ids.add(required_id)
                requirements.append({
                    "crop_id": required_id,
                    "harvest_amount": _integer(required_amount, where + f" unlock_amount_{index}", 1),
                })
            if item["initially_unlocked"] and requirements:
                raise ValueError(f"{where}: initially unlocked crops cannot have harvest requirements")
            if not item["initially_unlocked"] and not requirements:
                raise ValueError(f"{where}: locked crops need at least one harvest requirement")
            item["unlock_requirements"] = requirements
            for field in ("seed_resource", "leaf_resource", "mature_resource", "icon_resource"):
                item[field] = _resource(entry[field], where + " " + field)
        else:
            rarity = _text(entry["rarity"], where + " rarity")
            if rarity not in ITEM_RARITIES:
                raise ValueError(f"{where}: rarity must be one of {sorted(ITEM_RARITIES)}")
            item["rarity"] = rarity
            bait_type = _text(entry["preferred_bait_type"], where + " preferred_bait_type")
            if bait_type not in BAIT_TYPES:
                raise ValueError(f"{where}: preferred_bait_type must be one of {sorted(BAIT_TYPES)}")
            item["preferred_bait_type"] = bait_type
            item["favorite_bait_id"] = _text(entry["favorite_bait_id"], where + " favorite_bait_id")
            weight = float(_number(entry["base_weight"], where + " base_weight"))
            if weight <= 0:
                raise ValueError(f"{where}: base_weight must be > 0")
            item["base_weight"] = weight
            item["sell_price"] = _integer(entry["sell_price"], where + " sell_price")
            item["icon_resource"] = _resource(entry["icon_resource"], where + " icon_resource")
            for field in ("icon_region_x", "icon_region_y", "icon_region_width", "icon_region_height"):
                item[field] = _integer(entry[field], where + " " + field)
            if (item["icon_region_width"] == 0) != (item["icon_region_height"] == 0):
                raise ValueError(f"{where}: icon region width and height must both be zero or positive")
        items.append(item)
    if not items:
        raise ValueError(f"{path.name}: no catalog entries found")
    if category == "crops":
        positions = {str(item["id"]): index for index, item in enumerate(items)}
        for index, item in enumerate(items):
            for requirement in item["unlock_requirements"]:
                source_id = str(requirement["crop_id"])
                if source_id not in positions:
                    raise ValueError(f"{path.name}: {item['id']} requires missing crop {source_id}")
                if positions[source_id] >= index:
                    raise ValueError(f"{path.name}: {item['id']} must require a crop on an earlier row: {source_id}")
    return items


# 封装 workbench_rows 的处理，供相关流程复用。
def _workbench_rows(path: Path, sheet_name: str, columns: tuple[str, ...]) -> list[list[object | None]]:
    rows = _sheet_rows(path, sheet_name, len(columns))
    if len(rows) < 3 or tuple(rows[0]) != columns:
        raise ValueError(f"{path.name}/{sheet_name}: first row must be {', '.join(columns)}")
    if any(not isinstance(note, str) or not note.strip() for note in rows[1]):
        raise ValueError(f"{path.name}/{sheet_name}: second row must explain every column in Chinese")
    return rows[2:]


# 读取 pasture_products，供调用方继续处理。
def _read_pasture_products(path: Path) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []
    ids: set[str] = set()
    for row_number, row in enumerate(_workbench_rows(path, "农产品", PASTURE_PRODUCT_COLUMNS), start=3):
        if all(value is None for value in row):
            continue
        entry = dict(zip(PASTURE_PRODUCT_COLUMNS, row))
        where = f"{path.name}/农产品!{row_number}"
        item_id = _text(entry["id"], where + " id")
        if re.fullmatch(r"[a-z][a-z0-9_]*", item_id) is None or item_id in ids:
            raise ValueError(f"{where}: invalid or duplicate product ID")
        ids.add(item_id)
        _text(entry["中文备注"], where + " 中文备注")
        animal = _text(entry["source_animal"], where + " source_animal")
        rarity = _text(entry["rarity"], where + " rarity")
        if animal not in {"chicken", "pig", "sheep", "cow"} or rarity not in ITEM_RARITIES:
            raise ValueError(f"{where}: invalid source animal or rarity")
        icon = _text(entry["icon_resource"], where + " icon_resource")
        asset_path = (ROOT / icon.removeprefix("res://")).resolve()
        if not icon.startswith("res://assets/") or not asset_path.is_relative_to((ROOT / "assets").resolve()) or not asset_path.is_file() or asset_path.suffix.lower() not in {".png", ".tres"}:
            raise ValueError(f"{where}: icon_resource must be an existing texture resource")
        items.append({
            "id": item_id,
            "display_name": _text(entry["display_name"], where + " display_name"),
            "source_animal": animal,
            "sell_price": _integer(entry["sell_price"], where + " sell_price", 1),
            "icon_resource": icon,
            "rarity": rarity,
        })
    if {str(item["source_animal"]) for item in items} != {"chicken", "pig", "sheep", "cow"} or len(items) != 4:
        raise ValueError(f"{path.name}/农产品: configure one product for each of the four animals")
    return items


# 读取 workbench_baits，供调用方继续处理。
def _read_workbench_baits(path: Path, crop_ids: set[str]) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []
    ids: set[str] = set()
    for row_number, row in enumerate(_workbench_rows(path, "鱼饵", WORKBENCH_BAIT_COLUMNS), start=3):
        if all(value is None for value in row):
            continue
        entry = dict(zip(WORKBENCH_BAIT_COLUMNS, row))
        where = f"{path.name}/鱼饵!{row_number}"
        bait_id = _text(entry["id"], where + " id")
        if re.fullmatch(r"[a-z][a-z0-9_]*", bait_id) is None or bait_id in ids:
            raise ValueError(f"{where}: id must be unique lowercase letters/digits/underscores")
        ids.add(bait_id)
        _text(entry["中文备注"], where + " 中文备注")
        rarity = _text(entry["rarity"], where + " rarity")
        bait_type = _text(entry["bait_type"], where + " bait_type")
        source_crop = _text(entry["source_crop"], where + " source_crop")
        bait_tags = [part.strip() for part in bait_type.split(";")]
        if rarity not in ITEM_RARITIES or not 1 <= len(bait_tags) <= 2 or any(tag not in BAIT_TYPES for tag in bait_tags) or len(set(bait_tags)) != len(bait_tags) or source_crop not in crop_ids:
            raise ValueError(f"{where}: invalid rarity, bait type, or source crop")
        bait_type = ";".join(bait_tags)
        recipe: dict[str, int] = {}
        for index in range(1, 4):
            ingredient = entry[f"ingredient_{index}_id"]
            amount = entry[f"ingredient_{index}_count"]
            if ingredient is None or ingredient == "":
                if amount not in (None, 0):
                    raise ValueError(f"{where}: ingredient_{index}_count requires an ingredient ID")
                continue
            ingredient_id = _text(ingredient, where + f" ingredient_{index}_id")
            if re.fullmatch(r"[a-z][a-z0-9_]*", ingredient_id) is None or ingredient_id in recipe:
                raise ValueError(f"{where}: ingredient IDs must be unique lowercase identifiers")
            recipe[ingredient_id] = _integer(amount, where + f" ingredient_{index}_count", 1)
        if not recipe:
            raise ValueError(f"{where}: at least one ingredient is required")
        craft_seconds = float(_number(entry["craft_seconds"], where + " craft_seconds"))
        if craft_seconds <= 0:
            raise ValueError(f"{where}: craft_seconds must be greater than zero")
        item: dict[str, object] = {
            "id": bait_id,
            "display_name": _text(entry["display_name"], where + " display_name"),
            "rarity": rarity,
            "bait_type": bait_type,
            "source_crop": source_crop,
            "recipe": recipe,
            "charges_per_batch": _integer(entry["charges_per_batch"], where + " charges_per_batch", 1),
            "craft_seconds": craft_seconds,
            "required_workbench_tier": _integer(entry["required_workbench_tier"], where + " required_workbench_tier", 1),
            "icon_resource": _resource(entry["icon_resource"], where + " icon_resource"),
        }
        items.append(item)
    if not items:
        raise ValueError(f"{path.name}/鱼饵: no bait entries")
    return items


# 读取 workbench_rods，供调用方继续处理。
def _read_workbench_rods(path: Path) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []
    ids: set[str] = set()
    tiers: set[int] = set()
    for row_number, row in enumerate(_workbench_rows(path, "鱼竿", WORKBENCH_ROD_COLUMNS), start=3):
        if all(value is None for value in row):
            continue
        entry = dict(zip(WORKBENCH_ROD_COLUMNS, row))
        where = f"{path.name}/鱼竿!{row_number}"
        rod_id = _text(entry["id"], where + " id")
        tier = _integer(entry["tier"], where + " tier", 1)
        if re.fullmatch(r"[a-z][a-z0-9_]*", rod_id) is None or rod_id in ids or tier in tiers:
            raise ValueError(f"{where}: id and tier must be unique")
        ids.add(rod_id)
        tiers.add(tier)
        _text(entry["中文备注"], where + " 中文备注")
        rarity = _text(entry["rarity"], where + " rarity")
        max_rarity = _text(entry["max_fish_rarity"], where + " max_fish_rarity")
        if rarity not in ITEM_RARITIES or max_rarity not in ITEM_RARITIES:
            raise ValueError(f"{where}: invalid rod or fish rarity")
        item: dict[str, object] = {
            "id": rod_id,
            "display_name": _text(entry["display_name"], where + " display_name"),
            "tier": tier,
            "rarity": rarity,
            "max_fish_rarity": max_rarity,
            "upgrade_cost": _integer(entry["upgrade_cost"], where + " upgrade_cost"),
            "icon_resource": _resource(entry["icon_resource"], where + " icon_resource"),
        }
        items.append(item)
    if not any(item["id"] == "basic_rod" and item["tier"] == 1 for item in items):
        raise ValueError(f"{path.name}/鱼竿: basic_rod at tier 1 is required")
    return items


# 读取 achievements，供调用方继续处理。
def _read_achievements(path: Path) -> list[dict[str, object]]:
    rows = _sheet_rows(path, "数据", len(ACHIEVEMENT_COLUMNS))
    if len(rows) < 3 or tuple(rows[0]) != ACHIEVEMENT_COLUMNS:
        raise ValueError(f"{path.name}: first row must be {', '.join(ACHIEVEMENT_COLUMNS)}")
    if any(not isinstance(note, str) or not note.strip() for note in rows[1]):
        raise ValueError(f"{path.name}: second row must explain every column in Chinese")
    items: list[dict[str, object]] = []
    ids: set[str] = set()
    positions: set[int] = set()
    for row_number, row in enumerate(rows[2:], start=3):
        if all(value is None for value in row):
            continue
        entry = dict(zip(ACHIEVEMENT_COLUMNS, row))
        where = f"{path.name}!{row_number}"
        entry_id = _text(entry["id"], where + " id")
        if re.fullmatch(r"ACH_[A-Z0-9_]+", entry_id) is None or entry_id in ids:
            raise ValueError(f"{where}: achievement ID must be unique ACH_ uppercase identifier")
        ids.add(entry_id)
        _text(entry["中文备注"], where + " 中文备注")
        stage = _text(entry["stage"], where + " stage")
        metric = _text(entry["metric"], where + " metric")
        if stage not in ACHIEVEMENT_STAGES or metric not in ACHIEVEMENT_METRICS:
            raise ValueError(f"{where}: invalid achievement stage or metric")
        position = _integer(entry["sort_order"], where + " sort_order", 1)
        if position in positions:
            raise ValueError(f"{where}: sort_order must be unique")
        positions.add(position)
        items.append({
            "id": entry_id,
            "stage": stage,
            "sort_order": position,
            "name": _text(entry["name"], where + " name"),
            "description": _text(entry["description"], where + " description"),
            "metric": metric,
            "target": _integer(entry["target"], where + " target", 1),
            "icon_locked": _resource(entry["icon_locked"], where + " icon_locked"),
            "icon_unlocked": _resource(entry["icon_unlocked"], where + " icon_unlocked"),
        })
    if not items:
        raise ValueError(f"{path.name}: no achievement entries found")
    return items


# 组织工具的输入、处理和输出流程。
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate without writing JSON")
    args = parser.parse_args()
    documents: dict[str, dict[str, object]] = {}
    catalogs: dict[str, dict[str, object]] = {}
    texts: dict[str, dict[str, str]] = {}
    try:
        texts = _read_texts(EXCEL_DIR / "文本.xlsx")
        for filename, module in WORKBOOKS.items():
            path = EXCEL_DIR / filename
            if not path.is_file():
                raise ValueError(f"Missing workbook: {path}")
            documents[module] = {"module": module, "values": _read_module(path, module)}
        for filename, (category, columns) in CATALOG_WORKBOOKS.items():
            path = EXCEL_DIR / filename
            if not path.is_file():
                raise ValueError(f"Missing workbook: {path}")
            catalogs[category] = {"schema_version": 2, "catalog_type": category, "items": _read_catalog(path, category, columns)}
        workbench_path = EXCEL_DIR / "工作台.xlsx"
        if not workbench_path.is_file():
            raise ValueError(f"Missing workbook: {workbench_path}")
        crop_ids = {str(item["id"]) for item in catalogs["crops"]["items"]}
        catalogs["baits"] = {"schema_version": 2, "catalog_type": "baits", "items": _read_workbench_baits(workbench_path, crop_ids)}
        baits_by_id = {str(item["id"]): item for item in catalogs["baits"]["items"]}
        for fish in catalogs["fish"]["items"]:
            bait_id = str(fish["favorite_bait_id"])
            if bait_id not in baits_by_id:
                raise ValueError(f"鱼.xlsx: {fish['id']} favorite_bait_id references missing bait {bait_id}")
            bait_types = str(baits_by_id[bait_id]["bait_type"]).split(";")
            if fish["preferred_bait_type"] not in bait_types:
                raise ValueError(f"鱼.xlsx: {fish['id']} favorite_bait_id {bait_id} does not match preferred_bait_type")
        catalogs["rods"] = {"schema_version": 2, "catalog_type": "rods", "items": _read_workbench_rods(workbench_path)}
        catalogs["achievements"] = {"schema_version": 1, "catalog_type": "achievements", "items": _read_achievements(EXCEL_DIR / "成就.xlsx")}
        catalogs["pasture_products"] = {"schema_version": 1, "catalog_type": "pasture_products", "items": _read_pasture_products(EXCEL_DIR / "牧场.xlsx")}
        # Construction prices are spreadsheet-owned; structural fields stay in catalogs.
        construction = _read_module(EXCEL_DIR / "建设.xlsx", "construction")
        expected = {f"cottage_{level}_upgrade_cost" for level in (2, 3, 4)} | {
            f"unlock_plot_index_{index}_cost" for index in range(5)
        }
        if set(construction) != expected:
            raise ValueError("建设.xlsx: construction keys must include three cottage costs and five individual plot costs")
        for key, value in construction.items():
            _integer(value, f"建设.xlsx:{key}")
        for category in ("cottage_levels", "upgrades"):
            document = json.loads((CATALOG_DIR / f"{category}.json").read_text(encoding="utf-8"))
            found = set()
            for item in document["items"]:
                key = (f"cottage_{item['level']}_upgrade_cost" if category == "cottage_levels"
                       else f"{item['id']}_cost")
                if key in construction:
                    item["upgrade_cost" if category == "cottage_levels" else "cost"] = construction[key]
                    found.add(key)
            required = {key for key in expected if key.startswith("cottage_") == (category == "cottage_levels")}
            if found != required:
                raise ValueError(f"{category}: missing construction upgrade targets")
            catalogs[category] = document
        for category, document in catalogs.items():
            for item in document["items"]:
                for field in ("display_name", "name", "description"):
                    value = item.get(field)
                    if isinstance(value, str) and value:
                        key = f"catalog.{category}.{item['id']}.{field}"
                        if key not in texts:
                            raise ValueError(f"文本.xlsx: missing {key}")
                        if texts[key]["zh"] != value:
                            raise ValueError(f"文本.xlsx: {key} 中文 differs from the catalog workbook")
        tutorial = json.loads((ROOT / "data/tutorial/intro.json").read_text(encoding="utf-8"))
        for step in tutorial.get("steps", []):
            for field in ("title", "text"):
                key = f"tutorial.{step['id']}.{field}"
                if key not in texts:
                    raise ValueError(f"文本.xlsx: missing {key}")
        _validate_text_sources(texts)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"Export failed: {error}\n")
    if not args.check:
        TEXT_DIR.mkdir(parents=True, exist_ok=True)
        text_payload = json.dumps(texts, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=TEXT_DIR, prefix=".texts.", suffix=".tmp", delete=False) as handle:
            handle.write(text_payload)
            temporary = Path(handle.name)
        temporary.replace(TEXT_DIR / "texts.json")
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        for module, document in documents.items():
            payload = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=OUTPUT_DIR, prefix=f".{module}.", suffix=".tmp", delete=False) as handle:
                handle.write(payload)
                temporary = Path(handle.name)
            temporary.replace(OUTPUT_DIR / f"{module}.json")
        for category, document in catalogs.items():
            payload = json.dumps(document, ensure_ascii=False, indent=2) + "\n"
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=CATALOG_DIR, prefix=f".{category}.", suffix=".tmp", delete=False) as handle:
                handle.write(payload)
                temporary = Path(handle.name)
            temporary.replace(CATALOG_DIR / f"{category}.json")
    action = "Validated" if args.check else "Exported"
    print(f"{action} {len(documents)} modules, {sum(len(doc['values']) for doc in documents.values())} parameters, {sum(len(doc['items']) for doc in catalogs.values())} catalog entries, {len(texts)} texts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
