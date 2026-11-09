#!/usr/bin/env python3
"""Small shared weekly fish-size leaderboard for local/LAN development.

Run: python3 tools/leaderboard_server.py --host 127.0.0.1 --port 8765
The public/Steam service can later implement the same two HTTP endpoints.
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
FISH = {row["id"]: row for row in json.loads((ROOT / "data/catalog/fish.json").read_text())["items"]}
LIMITS = json.loads((ROOT / "data/config/fishing.json").read_text())["values"]
DB_PATH = ROOT / "server_data/leaderboard.sqlite3"


# 封装 week_start 的处理，供相关流程复用。
def week_start(now: int) -> int:
    dt = datetime.fromtimestamp(now, timezone.utc)
    monday = (dt - timedelta(days=dt.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    return int(monday.timestamp())


# 封装 connection 的处理，供相关流程复用。
def connection() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH)
    db.execute("CREATE TABLE IF NOT EXISTS catches (id INTEGER PRIMARY KEY, week_start INTEGER NOT NULL, player_id TEXT NOT NULL, display_name TEXT NOT NULL, fish_id TEXT NOT NULL, size_cm INTEGER NOT NULL, caught_at INTEGER NOT NULL)")
    db.execute("CREATE INDEX IF NOT EXISTS catches_week_player ON catches(week_start, player_id, size_cm DESC)")
    return db


# 定义 Handler 的状态和可用操作。
class Handler(BaseHTTPRequestHandler):
    # 封装 reply 的处理，供相关流程复用。
    def reply(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # 封装 do_GET 的处理，供相关流程复用。
    def do_GET(self) -> None:
        url = urlparse(self.path)
        if url.path != "/v1/weekly":
            self.reply(404, {"error": "not_found"})
            return
        limit = min(50, max(1, int(parse_qs(url.query).get("limit", [10])[0])))
        current_week = week_start(int(time.time()))
        with connection() as db:
            rows = db.execute("""
                SELECT player_id, display_name, fish_id, size_cm, caught_at FROM (
                    SELECT *, ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY size_cm DESC, caught_at ASC) AS rank_for_player
                    FROM catches WHERE week_start = ?
                ) WHERE rank_for_player = 1 ORDER BY size_cm DESC, caught_at ASC LIMIT ?
            """, (current_week, limit)).fetchall()
        entries = [dict(zip(("player_id", "display_name", "fish_id", "size_cm", "caught_at"), row)) for row in rows]
        self.reply(200, {"week_start": datetime.fromtimestamp(current_week, timezone.utc).strftime("%Y-%m-%d"), "entries": entries})

    # 封装 do_POST 的处理，供相关流程复用。
    def do_POST(self) -> None:
        if urlparse(self.path).path != "/v1/catches":
            self.reply(404, {"error": "not_found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 2048:
                raise ValueError("invalid body length")
            data = json.loads(self.rfile.read(length))
            player_id = str(data["player_id"])
            display_name = str(data["display_name"]).strip()[:24]
            fish_id = str(data["fish_id"])
            size_cm = data["size_cm"]
            if not re.fullmatch(r"[A-Za-z0-9_-]{8,80}", player_id) or not display_name or fish_id not in FISH or type(size_cm) is not int:
                raise ValueError("invalid catch")
            rarity = FISH[fish_id]["rarity"]
            if not LIMITS[f"{rarity}_size_min_cm"] <= size_cm <= LIMITS[f"{rarity}_size_max_cm"]:
                raise ValueError("size outside rarity limits")
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            self.reply(400, {"error": "invalid_catch"})
            return
        now = int(time.time())
        with connection() as db:
            db.execute("INSERT INTO catches(week_start, player_id, display_name, fish_id, size_cm, caught_at) VALUES(?,?,?,?,?,?)", (week_start(now), player_id, display_name, fish_id, size_cm, now))
        self.reply(201, {"accepted": True})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
