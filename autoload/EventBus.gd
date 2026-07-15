extends Node
## Global signal bus. Systems and UI stay decoupled through these signals.

signal currency_changed(new_amount: float, delta: float)
signal bottle_changed(new_amount: int, delta: int)
signal production_changed(per_second: float)

signal manual_gain(amount: float)
signal bottle_collected(bottle_amount: int, cash_amount: float, screen_pos: Vector2)
signal generator_purchased(generator_id: int, new_level: int)
signal upgrade_purchased(upgrade_id: int, new_level: int)
signal upgrade_maxed(upgrade_id: int)

signal save_loaded()
signal save_written()

signal toast(message: String)
signal number_popup(screen_pos: Vector2, text: String, color: Color)
