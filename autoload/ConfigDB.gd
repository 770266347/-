extends Node
## Loads static JSON config tables into memory at startup.

const DATA_DIR: String = "res://data/"

var generators: Array = []
var generators_by_id: Dictionary = {}
var upgrades: Array = []
var upgrades_by_id: Dictionary = {}


func _ready() -> void:
    var t0: int = Time.get_ticks_msec()
    _load_generators()
    _load_upgrades()
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


func _load_generators() -> void:
    var data = _read_json(DATA_DIR + "generators.json")
    if data == null:
        return
    generators.clear()
    generators_by_id.clear()
    for row in data.get("generators", []):
        var id: int = int(row.get("id", 0))
        generators.append(row)
        generators_by_id[id] = row


func _load_upgrades() -> void:
    var data = _read_json(DATA_DIR + "upgrades.json")
    if data == null:
        return
    upgrades.clear()
    upgrades_by_id.clear()
    for row in data.get("upgrades", []):
        var id: int = int(row.get("id", 0))
        upgrades.append(row)
        upgrades_by_id[id] = row


func get_generators() -> Array:
    return generators


func get_generator(generator_id: int) -> Dictionary:
    return generators_by_id.get(generator_id, {})


func get_generator_cost(generator_id: int, target_level: int) -> float:
    var row: Dictionary = get_generator(generator_id)
    if row.is_empty():
        return INF
    var base: float = float(row.get("cost_base", 0.0))
    var growth: float = float(row.get("cost_growth", 1.0))
    return base * pow(growth, maxi(target_level - 1, 0))


func get_generator_rate(generator_id: int) -> float:
    var row: Dictionary = get_generator(generator_id)
    return float(row.get("base_rate", 0.0))


func get_upgrades() -> Array:
    return upgrades


func get_upgrade(upgrade_id: int) -> Dictionary:
    return upgrades_by_id.get(upgrade_id, {})


func get_upgrade_cost(upgrade_id: int, target_level: int) -> float:
    var row: Dictionary = get_upgrade(upgrade_id)
    if row.is_empty():
        return INF
    var base: float = float(row.get("cost_base", 0.0))
    var growth: float = float(row.get("cost_growth", 1.0))
    return base * pow(growth, maxi(target_level - 1, 0))
