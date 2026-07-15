class_name GeneratorSystem
extends Node
## Purchases and level management for passive generators.


func can_buy(generator_id: int) -> bool:
    var row: Dictionary = ConfigDB.get_generator(generator_id)
    if row.is_empty():
        return false
    var level: int = GameState.get_generator_level(generator_id)
    var max_level: int = int(row.get("max_level", 0))
    if max_level > 0 and level >= max_level:
        return false
    return GameState.can_afford(get_next_cost(generator_id))


func buy(generator_id: int) -> bool:
    if not can_buy(generator_id):
        return false
    var level: int = GameState.get_generator_level(generator_id)
    var cost: float = get_next_cost(generator_id)
    if not GameState.spend_currency(cost):
        return false
    GameState.set_generator_level(generator_id, level + 1)
    EventBus.generator_purchased.emit(generator_id, level + 1)
    EventBus.toast.emit("已招募 %s Lv %d" % [ConfigDB.get_generator(generator_id).get("name", "帮手"), level + 1])
    AudioManager.play_sfx("cash")
    return true


func get_next_cost(generator_id: int) -> float:
    return ConfigDB.get_generator_cost(generator_id, GameState.get_generator_level(generator_id) + 1)
