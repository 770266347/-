class_name ProductionSystem
extends Node
## Manual click and passive production loop.

var _auto_bottle_buffer: float = 0.0


func _process(delta: float) -> void:
    var per_second: float = GameState.get_production_per_second()
    if per_second <= 0.0:
        return
    _auto_bottle_buffer += per_second * delta
    var bottle_amount: int = int(floor(_auto_bottle_buffer))
    if bottle_amount <= 0:
        return
    _auto_bottle_buffer -= float(bottle_amount)
    _grant_bottles(bottle_amount, Vector2.ZERO)


func manual_click() -> void:
    var popup_pos: Vector2 = get_viewport().get_visible_rect().size * 0.5
    collect_bottle(popup_pos)


func collect_bottle(screen_pos: Vector2) -> void:
    _grant_bottles(GameState.get_bottles_per_collect(), screen_pos)
    AudioManager.play_sfx("click")


func _grant_bottles(bottle_amount: int, screen_pos: Vector2) -> void:
    if bottle_amount <= 0:
        return
    var cash_amount: float = GameState.get_bottle_cash_value() * float(bottle_amount)
    GameState.add_bottles(bottle_amount)
    GameState.add_currency(cash_amount)
    EventBus.manual_gain.emit(cash_amount)
    EventBus.bottle_collected.emit(bottle_amount, cash_amount, screen_pos)
    if screen_pos != Vector2.ZERO:
        EventBus.number_popup.emit(
            screen_pos,
            "+%d 瓶 +%s 元" % [bottle_amount, BigNumber.format(cash_amount)],
            Color(0.4, 0.95, 0.55)
        )
