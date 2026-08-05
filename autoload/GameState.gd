extends Node
## Runtime mutable player state. Persisted by SaveManager.

const SAVE_VERSION: int = 11
const BASE_BOTTLE_VALUE: float = 1.0
const GLOBAL_VALUE_UPGRADE_ID: String = "upgrade_global_value"
const GLOBAL_SPAWN_UPGRADE_ID: String = "upgrade_global_spawn"
const GLOBAL_CAPACITY_UPGRADE_ID: String = "upgrade_global_capacity"

var save_version: int = SAVE_VERSION
var bottles: int = 0
var total_bottles: int = 0
var currency: float = 0.0
var total_earned: float = 0.0
var current_scene_id: String = "street"

## upgrade_id -> level
var upgrades: Dictionary = {}
## scene_id -> true
var unlocked_scenes: Dictionary = {}
## drop_id -> true
var unlocked_drops: Dictionary = {}
## helper_id -> true
var purchased_helpers: Dictionary = {}
## helper_id -> true; missing purchased IDs are benched
var active_helpers: Dictionary = {}
## talent_id -> true
var unlocked_talents: Dictionary = {}
## scene_id -> Array[drop_id]
var scene_drop_inventories: Dictionary = {}
## scene_id -> Array[serial], aligned with scene_drop_inventories
var scene_drop_serials: Dictionary = {}
var next_scene_drop_serial: int = 1
var defense_highest_unlocked_level: int = 1
var defense_cleared_levels: Dictionary = {}
## drop_id -> lifetime collected amount
var drop_collection_counts: Dictionary = {}


func reset_to_default() -> void:
    save_version = SAVE_VERSION
    bottles = 0
    total_bottles = 0
    currency = 0.0
    total_earned = 0.0
    current_scene_id = ConfigDB.get_default_scene_id()
    upgrades.clear()
    unlocked_scenes = _scene_set(ConfigDB.get_default_unlocked_scenes())
    unlocked_drops = _drop_set(ConfigDB.get_default_unlocked_drops())
    purchased_helpers.clear()
    active_helpers.clear()
    unlocked_talents.clear()
    scene_drop_inventories.clear()
    scene_drop_serials.clear()
    next_scene_drop_serial = 1
    defense_highest_unlocked_level = 1
    defense_cleared_levels.clear()
    drop_collection_counts.clear()
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


func record_drop_collection(drop_id: String, amount: int) -> void:
    if amount <= 0 or ConfigDB.get_drop(drop_id).is_empty():
        return
    var new_amount: int = get_drop_collection_count(drop_id) + amount
    drop_collection_counts[drop_id] = new_amount
    EventBus.drop_collection_count_changed.emit(drop_id, new_amount, amount)


func get_drop_collection_count(drop_id: String) -> int:
    return maxi(0, int(drop_collection_counts.get(drop_id, 0)))


func get_drop_collection_counts() -> Dictionary:
    return drop_collection_counts.duplicate()


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
    return base_cash * (
        1.0
        + _upgrade_effect_total(GLOBAL_VALUE_UPGRADE_ID)
        + get_talent_effect_total("cash_bonus")
    )


func get_global_spawn_interval_multiplier() -> float:
    return maxf(
        0.3,
        1.0
        - _upgrade_effect_total(GLOBAL_SPAWN_UPGRADE_ID)
        - get_talent_effect_total("spawn_reduction")
    )


func get_global_capacity_bonus() -> int:
    return int(round(
        _upgrade_effect_total(GLOBAL_CAPACITY_UPGRADE_ID)
        + get_talent_effect_total("capacity_bonus")
    ))


func get_helper_speed_multiplier() -> float:
    return 1.0 + get_talent_effect_total("helper_speed_bonus")


func get_helper_cooldown_multiplier() -> float:
    return maxf(0.5, 1.0 - get_talent_effect_total("helper_cooldown_reduction"))


func set_current_scene_id(scene_id: String) -> bool:
    if ConfigDB.get_scene(scene_id).is_empty():
        return false
    if not is_scene_unlocked(scene_id):
        return false
    if current_scene_id == scene_id:
        return true
    current_scene_id = scene_id
    EventBus.scene_changed.emit(current_scene_id)
    return true


func cycle_scene() -> void:
    set_current_scene_id(ConfigDB.get_next_scene_id(current_scene_id))


func switch_scene_by_offset(offset: int) -> bool:
    var scene_id: String = ConfigDB.get_scene_id_at_offset(current_scene_id, offset)
    if scene_id.is_empty():
        return false
    return set_current_scene_id(scene_id)


func can_switch_scene_by_offset(offset: int) -> bool:
    var scene_id: String = ConfigDB.get_scene_id_at_offset(current_scene_id, offset)
    return not scene_id.is_empty() and is_scene_unlocked(scene_id)


func is_scene_unlocked(scene_id: String) -> bool:
    return bool(unlocked_scenes.get(scene_id, false))


func unlock_scene(scene_id: String) -> bool:
    if scene_id.is_empty() or ConfigDB.get_scene(scene_id).is_empty():
        return false
    if is_scene_unlocked(scene_id):
        return false
    unlocked_scenes[scene_id] = true
    for drop_id in ConfigDB.get_scene_unlock_drop_ids(scene_id):
        unlock_drop(String(drop_id))
    EventBus.scene_unlocked.emit(scene_id)
    return true


func get_unlocked_scene_ids() -> Array:
    return unlocked_scenes.keys()


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


func get_scene_drop_ids(scene_id: String) -> Array:
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    return inventory.duplicate()


func get_scene_drop_serial(scene_id: String, index: int) -> int:
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    if index < 0 or index >= inventory.size():
        return 0
    var serials: Array = _ensure_scene_drop_serials(scene_id, inventory.size())
    return int(serials[index])


func get_scene_drop_serials(scene_id: String) -> Array:
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    return _ensure_scene_drop_serials(scene_id, inventory.size()).duplicate()


func get_scene_drop_count(scene_id: String) -> int:
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    return inventory.size()


func get_scene_capacity(scene_id: String) -> int:
    var scene: Dictionary = ConfigDB.get_scene(scene_id)
    if scene.is_empty():
        return 0
    return maxi(0, int(scene.get("max_inventory", scene.get("max_on_screen", 0))) + get_global_capacity_bonus())


func add_scene_drop(scene_id: String, drop_id: String) -> bool:
    if not is_scene_unlocked(scene_id) or not is_drop_unlocked(drop_id):
        return false
    var drop: Dictionary = ConfigDB.get_drop(drop_id)
    if drop.is_empty() or String(drop.get("scene_id", "")) != scene_id:
        return false
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    if inventory.size() >= get_scene_capacity(scene_id):
        return false
    inventory.append(drop_id)
    scene_drop_inventories[scene_id] = inventory
    var serials: Array = _ensure_scene_drop_serials(scene_id, inventory.size() - 1)
    serials.append(_allocate_scene_drop_serial())
    scene_drop_serials[scene_id] = serials
    EventBus.scene_inventory_changed.emit(scene_id)
    return true


func consume_scene_drop(scene_id: String, drop_id: String) -> bool:
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    var index: int = inventory.find(drop_id)
    if index < 0:
        return false
    return _consume_scene_drop_at(scene_id, index)


func consume_scene_drop_instance(scene_id: String, serial: int, expected_drop_id: String = "") -> bool:
    if serial <= 0:
        return false
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    var serials: Array = _ensure_scene_drop_serials(scene_id, inventory.size())
    var index: int = serials.find(serial)
    if index < 0 or index >= inventory.size():
        return false
    if not expected_drop_id.is_empty() and String(inventory[index]) != expected_drop_id:
        return false
    return _consume_scene_drop_at(scene_id, index)


func _consume_scene_drop_at(scene_id: String, index: int) -> bool:
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    if index < 0 or index >= inventory.size():
        return false
    var serials: Array = _ensure_scene_drop_serials(scene_id, inventory.size())
    inventory.remove_at(index)
    serials.remove_at(index)
    if inventory.is_empty():
        scene_drop_inventories.erase(scene_id)
        scene_drop_serials.erase(scene_id)
    else:
        scene_drop_inventories[scene_id] = inventory
        scene_drop_serials[scene_id] = serials
    EventBus.scene_inventory_changed.emit(scene_id)
    return true


func has_helper(helper_id: String) -> bool:
    return bool(purchased_helpers.get(helper_id, false))


func is_helper_active(helper_id: String) -> bool:
    return has_helper(helper_id) and bool(active_helpers.get(helper_id, false))


func purchase_helper(helper_id: String) -> bool:
    if helper_id.is_empty() or ConfigDB.get_helper(helper_id).is_empty():
        return false
    if has_helper(helper_id):
        return false
    purchased_helpers[helper_id] = true
    active_helpers[helper_id] = true
    EventBus.helper_purchased.emit(helper_id)
    return true


func set_helper_active(helper_id: String, active: bool) -> bool:
    if not has_helper(helper_id):
        return false
    if is_helper_active(helper_id) == active:
        return false
    if active:
        active_helpers[helper_id] = true
    else:
        active_helpers.erase(helper_id)
    EventBus.helper_active_changed.emit(helper_id, active)
    return true


func is_talent_unlocked(talent_id: String) -> bool:
    return bool(unlocked_talents.get(talent_id, false))


func unlock_talent(talent_id: String) -> bool:
    if talent_id.is_empty() or ConfigDB.get_talent(talent_id).is_empty():
        return false
    if is_talent_unlocked(talent_id):
        return false
    unlocked_talents[talent_id] = true
    EventBus.talent_unlocked.emit(talent_id)
    return true


func reset_talents() -> bool:
    if unlocked_talents.is_empty():
        return false
    unlocked_talents.clear()
    EventBus.talents_reset.emit()
    return true


func get_talent_points_earned() -> int:
    var earned: int = 0
    for milestone in ConfigDB.get_talent_point_milestones():
        if total_bottles < int(milestone):
            break
        earned += 1
    return earned


func get_talent_points_spent() -> int:
    var spent: int = 0
    for talent_id in unlocked_talents.keys():
        var row: Dictionary = ConfigDB.get_talent(String(talent_id))
        spent += maxi(0, int(row.get("point_cost", 1)))
    return spent


func get_available_talent_points() -> int:
    return maxi(0, get_talent_points_earned() - get_talent_points_spent())


func get_next_talent_point_milestone() -> int:
    for milestone in ConfigDB.get_talent_point_milestones():
        if total_bottles < int(milestone):
            return int(milestone)
    return -1


func get_talent_effect_total(effect_id: String) -> float:
    var total: float = 0.0
    for talent_id in unlocked_talents.keys():
        var row: Dictionary = ConfigDB.get_talent(String(talent_id))
        var effects: Dictionary = row.get("effects", {})
        total += float(effects.get(effect_id, 0.0))
    return total


func is_defense_level_unlocked(level_id: int) -> bool:
    return level_id >= 1 and level_id <= defense_highest_unlocked_level and level_id <= ConfigDB.get_defense_max_level()


func is_defense_level_cleared(level_id: int) -> bool:
    return bool(defense_cleared_levels.get(level_id, false))


func complete_defense_level(level_id: int) -> bool:
    if not is_defense_level_unlocked(level_id) or ConfigDB.get_defense_level(level_id).is_empty():
        return false
    var first_clear: bool = not is_defense_level_cleared(level_id)
    defense_cleared_levels[level_id] = true
    if level_id < ConfigDB.get_defense_max_level():
        defense_highest_unlocked_level = maxi(defense_highest_unlocked_level, level_id + 1)
    if first_clear:
        EventBus.defense_level_completed.emit(level_id)
    return first_clear


func to_dict() -> Dictionary:
    return {
        "save_version": save_version,
        "bottles": bottles,
        "total_bottles": total_bottles,
        "currency": currency,
        "total_earned": total_earned,
        "current_scene_id": current_scene_id,
        "upgrades": upgrades,
        "unlocked_scenes": unlocked_scenes,
        "unlocked_drops": unlocked_drops,
        "purchased_helpers": purchased_helpers,
        "active_helpers": active_helpers,
        "unlocked_talents": unlocked_talents,
        "scene_drop_inventories": scene_drop_inventories,
        "scene_drop_serials": scene_drop_serials,
        "next_scene_drop_serial": next_scene_drop_serial,
        "defense_highest_unlocked_level": defense_highest_unlocked_level,
        "defense_cleared_levels": defense_cleared_levels,
        "drop_collection_counts": drop_collection_counts,
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
    unlocked_scenes = _bool_key_dict(d.get("unlocked_scenes", {}))
    unlocked_drops = _bool_key_dict(d.get("unlocked_drops", {}))
    purchased_helpers = _bool_key_dict(d.get("purchased_helpers", {}))
    if d.has("active_helpers"):
        active_helpers = _bool_key_dict(d.get("active_helpers", {}))
    else:
        active_helpers = purchased_helpers.duplicate()
    unlocked_talents = _bool_key_dict(d.get("unlocked_talents", {}))
    scene_drop_inventories = _scene_drop_inventory_dict(d.get("scene_drop_inventories", {}))
    scene_drop_serials = _scene_drop_serial_dict(d.get("scene_drop_serials", {}))
    next_scene_drop_serial = maxi(1, int(d.get("next_scene_drop_serial", 1)))
    defense_highest_unlocked_level = maxi(1, int(d.get("defense_highest_unlocked_level", 1)))
    defense_cleared_levels = _int_bool_key_dict(d.get("defense_cleared_levels", {}))
    drop_collection_counts = _string_int_count_dict(d.get("drop_collection_counts", {}))
    _merge_default_unlocked_scenes()
    _merge_default_unlocked_drops()
    _apply_unlock_upgrades_to_state()
    _sanitize_upgrade_levels()
    _sanitize_active_helpers()
    _sanitize_unlocked_talents()
    _sanitize_scene_drop_inventories()
    _sanitize_defense_progress()
    _sanitize_drop_collection_counts()
    if not is_scene_unlocked(current_scene_id):
        current_scene_id = ConfigDB.get_default_scene_id()
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


static func _int_bool_key_dict(d: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for k in d.keys():
        var level_id: int = int(k)
        if level_id > 0 and bool(d[k]):
            out[level_id] = true
    return out


static func _string_int_count_dict(value: Variant) -> Dictionary:
    var out: Dictionary = {}
    if typeof(value) != TYPE_DICTIONARY:
        return out
    var source: Dictionary = value as Dictionary
    for k in source.keys():
        var amount: int = maxi(0, int(source[k]))
        if amount > 0:
            out[String(k)] = amount
    return out


static func _drop_set(drop_ids: Array) -> Dictionary:
    var out: Dictionary = {}
    for drop_id in drop_ids:
        out[String(drop_id)] = true
    return out


static func _scene_set(scene_ids: Array) -> Dictionary:
    var out: Dictionary = {}
    for scene_id in scene_ids:
        out[String(scene_id)] = true
    return out


static func _scene_drop_inventory_dict(value: Variant) -> Dictionary:
    var out: Dictionary = {}
    if typeof(value) != TYPE_DICTIONARY:
        return out
    var source: Dictionary = value as Dictionary
    for scene_id in source.keys():
        if typeof(source[scene_id]) != TYPE_ARRAY:
            continue
        var drop_ids: Array = []
        for drop_id in source[scene_id]:
            drop_ids.append(String(drop_id))
        out[String(scene_id)] = drop_ids
    return out


static func _scene_drop_serial_dict(value: Variant) -> Dictionary:
    var out: Dictionary = {}
    if typeof(value) != TYPE_DICTIONARY:
        return out
    var source: Dictionary = value as Dictionary
    for scene_id in source.keys():
        if typeof(source[scene_id]) != TYPE_ARRAY:
            continue
        var serials: Array = []
        for serial in source[scene_id]:
            serials.append(int(serial))
        out[String(scene_id)] = serials
    return out


func _allocate_scene_drop_serial() -> int:
    var serial: int = maxi(1, next_scene_drop_serial)
    next_scene_drop_serial = serial + 1
    return serial


func _ensure_scene_drop_serials(scene_id: String, inventory_count: int) -> Array:
    var serials: Array = scene_drop_serials.get(scene_id, [])
    if serials.size() > inventory_count:
        serials.resize(inventory_count)
    while serials.size() < inventory_count:
        serials.append(_allocate_scene_drop_serial())
    if serials.is_empty():
        scene_drop_serials.erase(scene_id)
    else:
        scene_drop_serials[scene_id] = serials
    return serials


func _merge_default_unlocked_scenes() -> void:
    for scene_id in ConfigDB.get_default_unlocked_scenes():
        unlocked_scenes[String(scene_id)] = true


func _merge_default_unlocked_drops() -> void:
    for drop_id in ConfigDB.get_default_unlocked_drops():
        unlocked_drops[String(drop_id)] = true


func _apply_unlock_upgrades_to_state() -> void:
    if int(upgrades.get("unlock_bar_beer", 0)) > 0 and int(upgrades.get("unlock_bar_scene", 0)) <= 0:
        upgrades["unlock_bar_scene"] = 1

    for upgrade_id in upgrades.keys():
        if int(upgrades.get(upgrade_id, 0)) <= 0:
            continue
        var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
        if row.is_empty():
            continue
        match String(row.get("type", "")):
            "unlock_drop":
                var drop_id: String = String(row.get("unlock_drop_id", ""))
                if not drop_id.is_empty() and not ConfigDB.get_drop(drop_id).is_empty():
                    unlocked_drops[drop_id] = true
            "unlock_scene":
                var scene_id: String = String(row.get("unlock_scene_id", ""))
                if not scene_id.is_empty() and not ConfigDB.get_scene(scene_id).is_empty():
                    unlocked_scenes[scene_id] = true
                for drop_id in row.get("unlock_drop_ids", []):
                    var id: String = String(drop_id)
                    if not id.is_empty() and not ConfigDB.get_drop(id).is_empty():
                        unlocked_drops[id] = true


func _sanitize_scene_drop_inventories() -> void:
    var sanitized: Dictionary = {}
    var sanitized_serials: Dictionary = {}
    var used_serials: Dictionary = {}
    for serial_list_variant in scene_drop_serials.values():
        if typeof(serial_list_variant) != TYPE_ARRAY:
            continue
        for serial_variant in serial_list_variant:
            var serial: int = int(serial_variant)
            if serial > 0:
                next_scene_drop_serial = maxi(next_scene_drop_serial, serial + 1)
    for scene_id_variant in scene_drop_inventories.keys():
        var scene_id: String = String(scene_id_variant)
        if not is_scene_unlocked(scene_id) or ConfigDB.get_scene(scene_id).is_empty():
            continue
        var valid_drop_ids: Array = []
        var valid_serials: Array = []
        var source_drop_ids: Array = scene_drop_inventories.get(scene_id_variant, [])
        var source_serials: Array = scene_drop_serials.get(scene_id, [])
        var capacity: int = get_scene_capacity(scene_id)
        for index in range(source_drop_ids.size()):
            if valid_drop_ids.size() >= capacity:
                break
            var drop_id: String = String(source_drop_ids[index])
            var drop: Dictionary = ConfigDB.get_drop(drop_id)
            if not drop.is_empty() and is_drop_unlocked(drop_id) and String(drop.get("scene_id", "")) == scene_id:
                valid_drop_ids.append(drop_id)
                var serial: int = int(source_serials[index]) if index < source_serials.size() else 0
                if serial <= 0 or used_serials.has(serial):
                    serial = _allocate_scene_drop_serial()
                used_serials[serial] = true
                valid_serials.append(serial)
        if not valid_drop_ids.is_empty():
            sanitized[scene_id] = valid_drop_ids
            sanitized_serials[scene_id] = valid_serials
    scene_drop_inventories = sanitized
    scene_drop_serials = sanitized_serials


func _sanitize_active_helpers() -> void:
    var sanitized: Dictionary = {}
    for helper_id_variant in active_helpers.keys():
        var helper_id: String = String(helper_id_variant)
        if has_helper(helper_id) and not ConfigDB.get_helper(helper_id).is_empty():
            sanitized[helper_id] = true
    active_helpers = sanitized


func _sanitize_unlocked_talents() -> void:
    var sanitized: Dictionary = {}
    for row in ConfigDB.get_talents():
        var talent_id: String = String(row.get("id", ""))
        if not bool(unlocked_talents.get(talent_id, false)):
            continue
        var requirements_met: bool = true
        for required_id in row.get("requires", []):
            if not bool(sanitized.get(String(required_id), false)):
                requirements_met = false
                break
        if requirements_met:
            sanitized[talent_id] = true
    unlocked_talents = sanitized


func _sanitize_defense_progress() -> void:
    var max_level: int = maxi(1, ConfigDB.get_defense_max_level())
    defense_highest_unlocked_level = clampi(defense_highest_unlocked_level, 1, max_level)
    var sanitized: Dictionary = {}
    for level_id_variant in defense_cleared_levels.keys():
        var level_id: int = int(level_id_variant)
        if level_id >= 1 and level_id <= max_level:
            sanitized[level_id] = true
            defense_highest_unlocked_level = maxi(defense_highest_unlocked_level, mini(level_id + 1, max_level))
    defense_cleared_levels = sanitized


func _sanitize_drop_collection_counts() -> void:
    var sanitized: Dictionary = {}
    for drop_id_variant in drop_collection_counts.keys():
        var drop_id: String = String(drop_id_variant)
        var amount: int = maxi(0, int(drop_collection_counts.get(drop_id_variant, 0)))
        if amount > 0 and not ConfigDB.get_drop(drop_id).is_empty():
            sanitized[drop_id] = amount
    drop_collection_counts = sanitized


func _sanitize_upgrade_levels() -> void:
    var sanitized: Dictionary = {}
    for upgrade_id in upgrades.keys():
        var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
        if row.is_empty():
            continue
        var level: int = clampi(
            int(upgrades.get(upgrade_id, 0)),
            0,
            int(row.get("max_level", 1))
        )
        if level > 0:
            sanitized[upgrade_id] = level
    upgrades = sanitized


func _upgrade_effect_total(upgrade_id: String) -> float:
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    var level: int = clampi(get_upgrade_level(upgrade_id), 0, int(row.get("max_level", 0)))
    return float(level) * float(row.get("effect_per_level", 0.0))
