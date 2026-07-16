extends Node
## Runtime mutable player state. Persisted by SaveManager.

const SAVE_VERSION: int = 3
const BASE_BOTTLE_VALUE: float = 1.0

var save_version: int = SAVE_VERSION
var bottles: int = 0
var total_bottles: int = 0
var currency: float = 0.0
var total_earned: float = 0.0
var current_scene_id: String = "street"

## upgrade_id -> level
var upgrades: Dictionary = {}
## drop_id -> true
var unlocked_drops: Dictionary = {}


func reset_to_default() -> void:
    save_version = SAVE_VERSION
    bottles = 0
    total_bottles = 0
    currency = 0.0
    total_earned = 0.0
    current_scene_id = ConfigDB.get_default_scene_id()
    upgrades.clear()
    unlocked_drops = _drop_set(ConfigDB.get_default_unlocked_drops())
    EventBus.bottle_changed.emit(bottles, 0)
    EventBus.currency_changed.emit(currency, 0.0)
    EventBus.scene_changed.emit(current_scene_id)
    EventBus.unlocked_drops_changed.emit()


func add_bottles(amount: int) -> void:
    if amount == 0:
        return
    bottles = maxi(bottles + amount, 0)
    if amount > 0:
        total_bottles += amount
    EventBus.bottle_changed.emit(bottles, amount)


func add_currency(amount: float) -> void:
    if amount == 0.0:
        return
    currency = maxf(currency + amount, 0.0)
    if amount > 0.0:
        total_earned += amount
    EventBus.currency_changed.emit(currency, amount)


func can_afford(cost: float) -> bool:
    return currency >= cost


func spend_currency(cost: float) -> bool:
    if not can_afford(cost):
        return false
    add_currency(-cost)
    return true


func get_upgrade_level(upgrade_id) -> int:
    return int(upgrades.get(upgrade_id, 0))


func set_upgrade_level(upgrade_id, level: int) -> void:
    upgrades[upgrade_id] = level


func get_bottles_per_collect() -> int:
    return 1


func get_drop_cash_value(base_cash: float) -> float:
    return base_cash


func set_current_scene_id(scene_id: String) -> bool:
    if ConfigDB.get_scene(scene_id).is_empty():
        return false
    if current_scene_id == scene_id:
        return true
    current_scene_id = scene_id
    EventBus.scene_changed.emit(current_scene_id)
    return true


func cycle_scene() -> void:
    set_current_scene_id(ConfigDB.get_next_scene_id(current_scene_id))


func is_drop_unlocked(drop_id: String) -> bool:
    return bool(unlocked_drops.get(drop_id, false))


func unlock_drop(drop_id: String) -> bool:
    if drop_id.is_empty() or ConfigDB.get_drop(drop_id).is_empty():
        return false
    if is_drop_unlocked(drop_id):
        return false
    unlocked_drops[drop_id] = true
    EventBus.unlocked_drops_changed.emit()
    return true


func get_unlocked_drop_ids() -> Array:
    return unlocked_drops.keys()


func to_dict() -> Dictionary:
    return {
        "save_version": save_version,
        "bottles": bottles,
        "total_bottles": total_bottles,
        "currency": currency,
        "total_earned": total_earned,
        "current_scene_id": current_scene_id,
        "upgrades": upgrades,
        "unlocked_drops": unlocked_drops,
    }


func from_dict(d: Dictionary) -> void:
    save_version = int(d.get("save_version", SAVE_VERSION))
    bottles = int(d.get("bottles", 0))
    total_bottles = int(d.get("total_bottles", bottles))
    currency = float(d.get("currency", 0.0))
    total_earned = float(d.get("total_earned", 0.0))
    current_scene_id = String(d.get("current_scene_id", ConfigDB.get_default_scene_id()))
    if ConfigDB.get_scene(current_scene_id).is_empty():
        current_scene_id = ConfigDB.get_default_scene_id()
    upgrades = _mixed_key_level_dict(d.get("upgrades", {}))
    unlocked_drops = _bool_key_dict(d.get("unlocked_drops", {}))
    _merge_default_unlocked_drops()
    EventBus.bottle_changed.emit(bottles, 0)
    EventBus.currency_changed.emit(currency, 0.0)
    EventBus.scene_changed.emit(current_scene_id)
    EventBus.unlocked_drops_changed.emit()


static func _mixed_key_level_dict(d: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for k in d.keys():
        var key_variant = k
        if typeof(k) == TYPE_STRING and k.is_valid_int():
            key_variant = int(k)
        out[key_variant] = int(d[k])
    return out


static func _bool_key_dict(d: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for k in d.keys():
        out[String(k)] = bool(d[k])
    return out


static func _drop_set(drop_ids: Array) -> Dictionary:
    var out: Dictionary = {}
    for drop_id in drop_ids:
        out[String(drop_id)] = true
    return out


func _merge_default_unlocked_drops() -> void:
    for drop_id in ConfigDB.get_default_unlocked_drops():
        unlocked_drops[String(drop_id)] = true
