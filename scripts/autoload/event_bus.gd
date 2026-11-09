extends Node

## Global, payload-only event hub. Gameplay systems own rules; this node only decouples them.

signal game_loaded
signal game_saved
signal game_reset
signal tick(now_unix: int, delta_seconds: int)
signal weather_changed(previous_id: String, current_id: String)
signal weather_preferences_changed

signal resource_changed(resource_type: String, value: int)
signal inventory_changed(item_id: String, delta: int, total: int)
signal fish_basket_changed(fish_id: String, delta: int, total: int)
signal item_dropped(item_type: String, item_id: String, amount: int, source_key: String)
signal achievement_action(event_id: int, action: String, payload: Dictionary)
signal achievements_unlocked(ids: Array, migrated: bool)

signal crop_planted(plot_id: String, crop_id: String, mature_at: int)
signal crop_harvested(crop_id: String, amount: int)
signal crop_unlocked(crop_id: String)
signal crop_watered(plot_id: String, cell_index: int, stage: String)
signal plot_unlocked(plot_id: String)
signal plot_fertilized(plot_id: String, fertility: int)
signal cottage_construction_started(target_level: int, ready_at: int)
signal cottage_upgrade_completed(level: int)

signal bait_crafted(bait_id: String, charges: int)
signal bait_changed(bait_id: String)
signal rod_changed(rod_id: String)
signal fish_cast_started(bait_id: String, ready_at: int)
signal fish_caught(fish_id: String, first_time: bool)
signal fish_caught_live(fish_id: String, first_time: bool)
signal fish_size_caught(fish_id: String, size_cm: int, is_minimum: bool, is_maximum: bool)
signal leaderboard_updated
signal fishing_stopped(reason: String)

signal codex_entry_unlocked(entry_type: String, entry_id: String)
signal codex_milestone_reached(entry_type: String, amount: int)
signal workbench_unlocked
signal shop_unlocked
signal fish_sold(fish_id: String, amount: int, coins: int)
signal bait_purchased(bait_id: String, amount: int, coins_spent: int)
signal fish_converted_to_fertilizer(fish_id: String, amount: int, fertilizer: int)

signal job_added(job: Dictionary)
signal job_started(job: Dictionary)
signal job_labor_started(job: Dictionary)
signal job_completed(job: Dictionary)
signal job_queue_changed

signal offline_settlement_requested(seconds: int, from_unix: int, to_unix: int)
signal offline_result_ready(result: Dictionary)
signal rare_event_started(event_id: String)
signal rare_event_resolved(success: bool, reward_id: String)
