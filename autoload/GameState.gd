extends Node
## Runtime mutable player state. Persisted by SaveManager.

const SAVE_VERSION: int = 2
const UPGRADE_CLICK_MULT: int = 1
const UPGRADE_PRODUCTION_MULT: int = 2
const BASE_BOTTLE_VALUE: float = 1.0

var save_version: int = SAVE_VERSION
var bottles: int = 0
var total_bottles: int = 0
var currency: float = 0.0
var total_earned: float = 0.0

## generator_id -> level
var generators: Dictionary = {}
## upgrade_id -> level
var upgrades: Dictionary = {}

var _derived_dirty: bool = true
var click_multiplier: float = 1.0
var production_multiplier: float = 1.0


func reset_to_default() -> void:
    save_version = SAVE_VERSION
    bottles = 0
    total_bottles = 0
    currency = 0.0
    total_earned = 0.0
    generators.clear()
    upgrades.clear()
    _derived_dirty = true
    EventBus.bottle_changed.emit(bottles, 0)
    EventBus.currency_changed.emit(currency, 0.0)
    EventBus.production_changed.emit(get_production_per_second())


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


func get_generator_level(generator_id: int) -> int:
    return int(generators.get(generator_id, 0))


func set_generator_level(generator_id: int, level: int) -> void:
    generators[generator_id] = level
    EventBus.production_changed.emit(get_production_per_second())


func get_upgrade_level(upgrade_id: int) -> int:
    return int(upgrades.get(upgrade_id, 0))


func set_upgrade_level(upgrade_id: int, level: int) -> void:
    upgrades[upgrade_id] = level
    _derived_dirty = true
    EventBus.production_changed.emit(get_production_per_second())


func get_click_value() -> float:
    _ensure_derived()
    return 1.0 * click_multiplier


func get_bottles_per_collect() -> int:
    return 1


func get_bottle_cash_value() -> float:
    _ensure_derived()
    return BASE_BOTTLE_VALUE * click_multiplier


func get_generator_production(generator_id: int) -> float:
    _ensure_derived()
    var level: int = get_generator_level(generator_id)
    return ConfigDB.get_generator_rate(generator_id) * float(level) * production_multiplier


func get_production_per_second() -> float:
    _ensure_derived()
    var total: float = 0.0
    for generator_id in generators.keys():
        total += ConfigDB.get_generator_rate(int(generator_id)) * float(generators[generator_id])
    return total * production_multiplier


func _ensure_derived() -> void:
    if not _derived_dirty:
        return
    click_multiplier = 1.0
    production_multiplier = 1.0
    for upgrade_id in upgrades.keys():
        var row: Dictionary = ConfigDB.get_upgrade(int(upgrade_id))
        if row.is_empty():
            continue
        var level: int = int(upgrades[upgrade_id])
        var effect: float = float(row.get("effect_per_level", 0.0)) * float(level)
        match int(row.get("effect_type", 0)):
            UPGRADE_CLICK_MULT:
                click_multiplier += effect
            UPGRADE_PRODUCTION_MULT:
                production_multiplier += effect
    _derived_dirty = false


func to_dict() -> Dictionary:
    return {
        "save_version": save_version,
        "bottles": bottles,
        "total_bottles": total_bottles,
        "currency": currency,
        "total_earned": total_earned,
        "generators": generators,
        "upgrades": upgrades,
    }


func from_dict(d: Dictionary) -> void:
    save_version = int(d.get("save_version", SAVE_VERSION))
    bottles = int(d.get("bottles", 0))
    total_bottles = int(d.get("total_bottles", bottles))
    currency = float(d.get("currency", 0.0))
    total_earned = float(d.get("total_earned", 0.0))
    generators = _int_key_dict(d.get("generators", {}))
    upgrades = _int_key_dict(d.get("upgrades", {}))
    _derived_dirty = true
    EventBus.bottle_changed.emit(bottles, 0)
    EventBus.currency_changed.emit(currency, 0.0)
    EventBus.production_changed.emit(get_production_per_second())


static func _int_key_dict(d: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for k in d.keys():
        var key_variant = k
        if typeof(k) == TYPE_STRING and k.is_valid_int():
            key_variant = int(k)
        out[key_variant] = d[k]
    return out
