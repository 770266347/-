class_name UpgradeSystem
extends Node
## Purchases permanent upgrades for click and production multipliers.


func can_buy(upgrade_id: int) -> bool:
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    if row.is_empty():
        return false
    var level: int = GameState.get_upgrade_level(upgrade_id)
    if level >= int(row.get("max_level", 1)):
        return false
    return GameState.can_afford(get_next_cost(upgrade_id))


func buy(upgrade_id: int) -> bool:
    if not can_buy(upgrade_id):
        return false
    var level: int = GameState.get_upgrade_level(upgrade_id)
    var cost: float = get_next_cost(upgrade_id)
    if not GameState.spend_currency(cost):
        return false
    GameState.set_upgrade_level(upgrade_id, level + 1)
    EventBus.upgrade_purchased.emit(upgrade_id, level + 1)
    EventBus.toast.emit("已升级 %s Lv %d" % [ConfigDB.get_upgrade(upgrade_id).get("name", "升级"), level + 1])
    AudioManager.play_sfx("cash")
    if level + 1 >= int(ConfigDB.get_upgrade(upgrade_id).get("max_level", 1)):
        EventBus.upgrade_maxed.emit(upgrade_id)
    return true


func get_next_cost(upgrade_id: int) -> float:
    return ConfigDB.get_upgrade_cost(upgrade_id, GameState.get_upgrade_level(upgrade_id) + 1)


func is_maxed(upgrade_id: int) -> bool:
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    return GameState.get_upgrade_level(upgrade_id) >= int(row.get("max_level", 1))
