class_name ProductionSystem
extends Node
## Grants rewards for player and future helper collection.


func collect_drop(drop: Dictionary, screen_pos: Vector2) -> void:
    if drop.is_empty():
        return
    var amount: int = int(drop.get("reward_count", GameState.get_bottles_per_collect()))
    var base_cash: float = float(drop.get("cash", GameState.BASE_BOTTLE_VALUE))
    var cash_amount: float = GameState.get_drop_cash_value(base_cash) * float(amount)
    _grant_collectable(amount, cash_amount, String(drop.get("name", "回收物")), screen_pos)
    AudioManager.play_sfx("click")


func _grant_collectable(bottle_amount: int, cash_amount: float, drop_name: String, screen_pos: Vector2) -> void:
    if bottle_amount <= 0:
        return
    GameState.add_bottles(bottle_amount)
    GameState.add_currency(cash_amount)
    EventBus.bottle_collected.emit(bottle_amount, cash_amount, screen_pos)
    EventBus.drop_collected.emit(drop_name, bottle_amount, cash_amount, screen_pos)
    if screen_pos != Vector2.ZERO:
        EventBus.number_popup.emit(
            screen_pos,
            "+%d %s +%s 元" % [bottle_amount, drop_name, BigNumber.format(cash_amount)],
            Color(0.4, 0.95, 0.55)
        )
