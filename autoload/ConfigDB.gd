extends Node
## Loads static JSON config tables into memory at startup.

const DATA_DIR: String = "res://data/"

var upgrades: Array = []
var upgrades_by_id: Dictionary = {}
var helpers: Array = []
var helpers_by_id: Dictionary = {}
var scenes: Array = []
var scenes_by_id: Dictionary = {}
var drops_by_id: Dictionary = {}
var default_scene_id: String = "street"
var defense_levels: Array = []
var defense_levels_by_id: Dictionary = {}
var defense_enemies_by_id: Dictionary = {}
var defense_max_level: int = 0


func _ready() -> void:
    var t0: int = Time.get_ticks_msec()
    _load_upgrades()
    _load_helpers()
    _load_scenes()
    _load_defense_levels()
    print("[ConfigDB] loaded in %d ms" % (Time.get_ticks_msec() - t0))


func _read_json(path: String) -> Variant:
    if not FileAccess.file_exists(path):
        push_error("Missing config file: %s" % path)
        return null
    var raw: String = FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(raw)
    if parsed == null:
        push_error("Failed to parse JSON: %s" % path)
    return parsed


func _load_upgrades() -> void:
    upgrades.clear()
    upgrades_by_id.clear()
    _append_upgrades(DATA_DIR + "upgrades_unlocks.json")


func _load_helpers() -> void:
    var data = _read_json(DATA_DIR + "helpers.json")
    if data == null:
        return
    helpers.clear()
    helpers_by_id.clear()
    for row in data.get("helpers", []):
        var id: String = String(row.get("id", ""))
        if id.is_empty():
            continue
        helpers.append(row)
        helpers_by_id[id] = row


func _append_upgrades(path: String) -> void:
    var data = _read_json(path)
    if data == null:
        return
    for row in data.get("upgrades", []):
        var id = _normalize_id(row.get("id", ""))
        row["id"] = id
        upgrades.append(row)
        upgrades_by_id[id] = row


func _load_scenes() -> void:
    var data = _read_json(DATA_DIR + "scenes.json")
    if data == null:
        return
    default_scene_id = String(data.get("default_scene_id", default_scene_id))
    scenes.clear()
    scenes_by_id.clear()
    drops_by_id.clear()
    for row in data.get("scenes", []):
        var id: String = String(row.get("id", ""))
        if id.is_empty():
            continue
        scenes.append(row)
        scenes_by_id[id] = row
        for drop in row.get("drops", []):
            var drop_id: String = String(drop.get("id", ""))
            if drop_id.is_empty():
                continue
            drop["scene_id"] = id
            drops_by_id[drop_id] = drop


func _load_defense_levels() -> void:
    var data = _read_json(DATA_DIR + "defense_levels.json")
    defense_levels.clear()
    defense_levels_by_id.clear()
    defense_enemies_by_id.clear()
    defense_max_level = 0
    if data == null:
        return
    for enemy in data.get("enemy_types", []):
        var enemy_id: String = String(enemy.get("id", ""))
        if not enemy_id.is_empty():
            defense_enemies_by_id[enemy_id] = enemy
    for level in data.get("levels", []):
        var level_id: int = int(level.get("id", 0))
        if level_id <= 0:
            continue
        defense_levels.append(level)
        defense_levels_by_id[level_id] = level
        defense_max_level = maxi(defense_max_level, level_id)
    defense_max_level = mini(defense_max_level, int(data.get("max_level", defense_max_level)))


func get_upgrades() -> Array:
    return upgrades


func get_upgrade(upgrade_id) -> Dictionary:
    return upgrades_by_id.get(_normalize_id(upgrade_id), {})


func get_upgrade_cost(upgrade_id, target_level: int) -> float:
    var row: Dictionary = get_upgrade(upgrade_id)
    if row.is_empty():
        return INF
    if row.has("cost"):
        return float(row.get("cost", INF))
    var base: float = float(row.get("cost_base", 0.0))
    var growth: float = float(row.get("cost_growth", 1.0))
    return base * pow(growth, maxi(target_level - 1, 0))


func get_helpers() -> Array:
    return helpers


func get_helper(helper_id: String) -> Dictionary:
    return helpers_by_id.get(helper_id, {})


func get_scenes() -> Array:
    return scenes


func get_default_scene_id() -> String:
    return default_scene_id


func get_default_unlocked_scenes() -> Array:
    var out: Array = []
    for scene in scenes:
        if bool(scene.get("default_unlocked", false)):
            out.append(String(scene.get("id", "")))
    if out.is_empty() and not default_scene_id.is_empty():
        out.append(default_scene_id)
    return out


func get_scene(scene_id: String) -> Dictionary:
    return scenes_by_id.get(scene_id, {})


func get_scene_name(scene_id: String) -> String:
    return String(get_scene(scene_id).get("name", scene_id))


func get_scene_unlock_drop_ids(scene_id: String) -> Array:
    var scene: Dictionary = get_scene(scene_id)
    var out: Array = []
    for drop_id in scene.get("default_unlock_drop_ids", []):
        out.append(String(drop_id))
    return out


func get_next_scene_id(scene_id: String) -> String:
    if scenes.is_empty():
        return default_scene_id
    for i in range(scenes.size()):
        if String(scenes[i].get("id", "")) == scene_id:
            return String(scenes[(i + 1) % scenes.size()].get("id", default_scene_id))
    return String(scenes[0].get("id", default_scene_id))


func get_scene_id_at_offset(scene_id: String, offset: int) -> String:
    var index: int = get_scene_index(scene_id)
    if index < 0:
        return ""
    var target_index: int = index + offset
    if target_index < 0 or target_index >= scenes.size():
        return ""
    return String(scenes[target_index].get("id", ""))


func get_scene_index(scene_id: String) -> int:
    for i in range(scenes.size()):
        if String(scenes[i].get("id", "")) == scene_id:
            return i
    return -1


func get_scene_drops(scene_id: String) -> Array:
    var scene: Dictionary = get_scene(scene_id)
    return scene.get("drops", [])


func get_drop(drop_id: String) -> Dictionary:
    return drops_by_id.get(drop_id, {})


func get_drop_name(drop_id: String) -> String:
    return String(get_drop(drop_id).get("name", drop_id))


func get_default_unlocked_drops() -> Array:
    var out: Array = []
    for scene in scenes:
        for drop in scene.get("drops", []):
            if bool(drop.get("default_unlocked", false)):
                out.append(String(drop.get("id", "")))
    return out


func get_defense_levels() -> Array:
    return defense_levels


func get_defense_level(level_id: int) -> Dictionary:
    return defense_levels_by_id.get(level_id, {})


func get_defense_enemy(enemy_id: String) -> Dictionary:
    return defense_enemies_by_id.get(enemy_id, {})


func get_defense_max_level() -> int:
    return defense_max_level


func _normalize_id(id):
    match typeof(id):
        TYPE_FLOAT:
            return int(id)
        TYPE_STRING:
            if String(id).is_valid_int():
                return int(id)
            return String(id)
        _:
            return id
