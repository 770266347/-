extends Node
## 静态配置数据库。
##
## 启动时读取 data/ 下的 JSON，并建立按 ID 索引，供 GameState、业务系统和 UI
## 查询。这里不保存玩家进度，也不修改配置行；运行时变化统一放在 GameState。

const DATA_DIR: String = "res://data/"

# 原始配置数组保留顺序，用于 UI 展示；*_by_id 用于高频查询。
var upgrades: Array = []
var upgrades_by_id: Dictionary = {}
var helpers: Array = []
var helpers_by_id: Dictionary = {}
var scenes: Array = []
var scenes_by_id: Dictionary = {}
var drops_by_id: Dictionary = {}
var talents: Array = []
var talents_by_id: Dictionary = {}
var talent_point_milestones: Array = []
var default_scene_id: String = "street"
var defense_levels: Array = []
var defense_levels_by_id: Dictionary = {}
var defense_enemies_by_id: Dictionary = {}
var defense_max_level: int = 0
var defense_spawn_weights: Dictionary = {"top": 60.0, "left": 20.0, "right": 20.0}


func _ready() -> void:
    ## 按依赖顺序加载配置：产物先于天赋，防守关卡单独建立敌人索引。
    var t0: int = Time.get_ticks_msec()
    _load_upgrades()
    _load_helpers()
    _load_scenes()
    _load_talents()
    _load_defense_levels()
    print("[ConfigDB] loaded in %d ms" % (Time.get_ticks_msec() - t0))


func _read_json(path: String) -> Variant:
    ## 统一处理文件不存在、JSON 解析失败和原始数据返回。
    if not FileAccess.file_exists(path):
        push_error("Missing config file: %s" % path)
        return null
    var raw: String = FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(raw)
    if parsed == null:
        push_error("Failed to parse JSON: %s" % path)
    return parsed


func _load_upgrades() -> void:
    ## 读取通用升级、场景解锁和产物解锁表。
    upgrades.clear()
    upgrades_by_id.clear()
    _append_upgrades(DATA_DIR + "upgrades_unlocks.json")


func _load_helpers() -> void:
    ## 建立帮手数组和 helper_id 到配置行的索引。
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
    ## 兼容未来拆分多份升级表；重复 ID 以最后读取的配置为准。
    var data = _read_json(path)
    if data == null:
        return
    for row in data.get("upgrades", []):
        var id = _normalize_id(row.get("id", ""))
        row["id"] = id
        upgrades.append(row)
        upgrades_by_id[id] = row


func _load_scenes() -> void:
    ## 读取场景、产物池、背景和刷新参数，并补写每个产物的 scene_id。
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


func _load_talents() -> void:
    ## 读取天赋里程碑和四向节点，按 talent_id 建立快速索引。
    var data = _read_json(DATA_DIR + "talents.json")
    talents.clear()
    talents_by_id.clear()
    talent_point_milestones.clear()
    if data == null:
        return
    for milestone in data.get("point_milestones", []):
        talent_point_milestones.append(maxi(0, int(milestone)))
    talent_point_milestones.sort()
    for row in data.get("talents", []):
        var id: String = String(row.get("id", ""))
        if id.is_empty():
            continue
        talents.append(row)
        talents_by_id[id] = row


func _load_defense_levels() -> void:
    ## 读取敌人类型、出怪权重和关卡波次，计算可用的最高关卡编号。
    var data = _read_json(DATA_DIR + "defense_levels.json")
    defense_levels.clear()
    defense_levels_by_id.clear()
    defense_enemies_by_id.clear()
    defense_max_level = 0
    defense_spawn_weights = {"top": 60.0, "left": 20.0, "right": 20.0}
    if data == null:
        return
    if typeof(data.get("spawn_weights", {})) == TYPE_DICTIONARY:
        defense_spawn_weights = (data.get("spawn_weights", {}) as Dictionary).duplicate()
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
    ## 返回保持配置顺序的升级列表，调用方不应直接修改其中字段。
    return upgrades


func get_upgrade(upgrade_id) -> Dictionary:
    ## 按 ID 查询升级；未知 ID 返回空字典而不是 null。
    return upgrades_by_id.get(_normalize_id(upgrade_id), {})


func get_upgrade_cost(upgrade_id, target_level: int) -> float:
    ## 支持一次性解锁 cost 和等级成长 cost_base/cost_growth 两种价格模型。
    var row: Dictionary = get_upgrade(upgrade_id)
    if row.is_empty():
        return INF
    if row.has("cost"):
        return float(row.get("cost", INF))
    var base: float = float(row.get("cost_base", 0.0))
    var growth: float = float(row.get("cost_growth", 1.0))
    return base * pow(growth, maxi(target_level - 1, 0))


func get_helpers() -> Array:
    ## 返回帮手展示顺序。
    return helpers


func get_helper(helper_id: String) -> Dictionary:
    ## 查询单个帮手的静态能力和素材路径。
    return helpers_by_id.get(helper_id, {})


func get_scenes() -> Array:
    ## 返回场景顺序；场景切换和页签展示都依赖此顺序。
    return scenes


func get_default_scene_id() -> String:
    ## 返回新存档的默认场景 ID。
    return default_scene_id


func get_default_unlocked_scenes() -> Array:
    ## 收集所有标记 default_unlocked 的场景，至少保证默认场景存在。
    var out: Array = []
    for scene in scenes:
        if bool(scene.get("default_unlocked", false)):
            out.append(String(scene.get("id", "")))
    if out.is_empty() and not default_scene_id.is_empty():
        out.append(default_scene_id)
    return out


func get_scene(scene_id: String) -> Dictionary:
    ## 查询场景配置，包括库存上限和候选产物。
    return scenes_by_id.get(scene_id, {})


func get_scene_name(scene_id: String) -> String:
    ## 将内部 ID 转为 UI 名称；未知 ID 回退显示 ID 本身。
    return String(get_scene(scene_id).get("name", scene_id))


func get_scene_unlock_drop_ids(scene_id: String) -> Array:
    ## 返回解锁场景时自动开放的基础产物。
    var scene: Dictionary = get_scene(scene_id)
    var out: Array = []
    for drop_id in scene.get("default_unlock_drop_ids", []):
        out.append(String(drop_id))
    return out


func get_next_scene_id(scene_id: String) -> String:
    ## 按配置顺序循环查询下一个场景，供旧版循环切换使用。
    if scenes.is_empty():
        return default_scene_id
    for i in range(scenes.size()):
        if String(scenes[i].get("id", "")) == scene_id:
            return String(scenes[(i + 1) % scenes.size()].get("id", default_scene_id))
    return String(scenes[0].get("id", default_scene_id))


func get_scene_id_at_offset(scene_id: String, offset: int) -> String:
    ## 按绝对数组位置查询目标场景；越界返回空字符串而不循环。
    var index: int = get_scene_index(scene_id)
    if index < 0:
        return ""
    var target_index: int = index + offset
    if target_index < 0 or target_index >= scenes.size():
        return ""
    return String(scenes[target_index].get("id", ""))


func get_scene_index(scene_id: String) -> int:
    ## 返回场景在配置数组中的位置，未找到返回 -1。
    for i in range(scenes.size()):
        if String(scenes[i].get("id", "")) == scene_id:
            return i
    return -1


func get_scene_drops(scene_id: String) -> Array:
    ## 返回指定场景的全部候选产物，是否实际生成由 GameState 决定。
    var scene: Dictionary = get_scene(scene_id)
    return scene.get("drops", [])


func get_drop(drop_id: String) -> Dictionary:
    ## 从全局产物索引查询一条产物配置。
    return drops_by_id.get(drop_id, {})


func get_drop_name(drop_id: String) -> String:
    ## 提供统计弹窗和天赋条件共用的产物显示名。
    return String(get_drop(drop_id).get("name", drop_id))


func get_talents() -> Array:
    ## 返回按网格配置顺序排列的全部天赋节点。
    return talents


func get_talent(talent_id: String) -> Dictionary:
    ## 查询单个天赋节点的前置、产品条件和效果。
    return talents_by_id.get(talent_id, {})


func get_talent_point_milestones() -> Array:
    ## 返回里程碑副本，避免调用方排序时改变数据库内部顺序。
    return talent_point_milestones.duplicate()


func get_default_unlocked_drops() -> Array:
    ## 收集所有场景中默认开放的产物 ID。
    var out: Array = []
    for scene in scenes:
        for drop in scene.get("drops", []):
            if bool(drop.get("default_unlocked", false)):
                out.append(String(drop.get("id", "")))
    return out


func get_defense_levels() -> Array:
    ## 返回防守关卡配置顺序。
    return defense_levels


func get_defense_level(level_id: int) -> Dictionary:
    ## 查询单个防守关卡的波次和耐久配置。
    return defense_levels_by_id.get(level_id, {})


func get_defense_enemy(enemy_id: String) -> Dictionary:
    ## 查询单个敌人的速度、生命和素材配置。
    return defense_enemies_by_id.get(enemy_id, {})


func get_defense_max_level() -> int:
    ## 返回受配置 max_level 限制后的最高防守关卡。
    return defense_max_level


func get_defense_spawn_weights() -> Dictionary:
    ## 返回出怪口权重副本，避免战斗逻辑修改数据库。
    return defense_spawn_weights.duplicate()


func _normalize_id(id):
    ## 兼容 JSON 字典键在读档后变成字符串或数字的情况。
    match typeof(id):
        TYPE_FLOAT:
            return int(id)
        TYPE_STRING:
            if String(id).is_valid_int():
                return int(id)
            return String(id)
        _:
            return id
