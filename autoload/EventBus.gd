extends Node
## Global signal bus. Systems and UI stay decoupled through these signals.

signal currency_changed(new_amount: float, delta: float)
signal bottle_changed(new_amount: int, delta: int)

signal bottle_collected(bottle_amount: int, cash_amount: float, screen_pos: Vector2)
signal drop_collected(drop_name: String, amount: int, cash_amount: float, screen_pos: Vector2)
signal upgrade_purchased(upgrade_id, new_level: int)
signal upgrade_maxed(upgrade_id)
signal helper_purchased(helper_id: String)
signal scene_unlocked(scene_id: String)
signal scene_changed(scene_id: String)
signal unlocked_drops_changed()

signal save_loaded()
signal number_popup(screen_pos: Vector2, text: String, color: Color)
