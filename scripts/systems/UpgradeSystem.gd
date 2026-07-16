class_name UpgradeSystem
extends Node
## Purchases permanent upgrades and drop unlocks.


func can_buy(upgrade_id) -> bool:
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    if row.is_empty():
        return false
    if not _requirements_met(row):
        return false
    if String(row.get("type", "")) == "unlock_drop" and GameState.is_drop_unlocked(String(row.get("unlock_drop_id", ""))):
        return false
    var level: int = GameState.get_upgrade_level(upgrade_id)
    if level >= int(row.get("max_level", 1)):
        return false
    return GameState.can_afford(get_next_cost(upgrade_id))


func buy(upgrade_id) -> bool:
    if not can_buy(upgrade_id):
        return false
    var level: int = GameState.get_upgrade_level(upgrade_id)
    var cost: float = get_next_cost(upgrade_id)
    if not GameState.spend_currency(cost):
        return false
    GameState.set_upgrade_level(upgrade_id, level + 1)
    if String(ConfigDB.get_upgrade(upgrade_id).get("type", "")) == "unlock_drop":
        var drop_id: String = String(ConfigDB.get_upgrade(upgrade_id).get("unlock_drop_id", ""))
        GameState.unlock_drop(drop_id)
    EventBus.upgrade_purchased.emit(upgrade_id, level + 1)
    AudioManager.play_sfx("cash")
    if level + 1 >= int(ConfigDB.get_upgrade(upgrade_id).get("max_level", 1)):
        EventBus.upgrade_maxed.emit(upgrade_id)
    return true


func get_next_cost(upgrade_id) -> float:
    return ConfigDB.get_upgrade_cost(upgrade_id, GameState.get_upgrade_level(upgrade_id) + 1)


func is_maxed(upgrade_id) -> bool:
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    return GameState.get_upgrade_level(upgrade_id) >= int(row.get("max_level", 1))


func _requirements_met(row: Dictionary) -> bool:
    for required_upgrade_id in row.get("requires", []):
        if GameState.get_upgrade_level(required_upgrade_id) <= 0:
            return false
    return true

