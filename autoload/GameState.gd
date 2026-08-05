extends Node
## 玩家运行时权威状态。
##
## 这里保存会影响进度的最小数据集合，并由 SaveManager 持久化。
## UI 不应直接改字典；所有资源、解锁、库存和天赋变化都通过公开方法完成，
## 这样才能统一校验、统计和 EventBus 通知。

const SAVE_VERSION: int = 12
const BASE_BOTTLE_VALUE: float = 1.0
const FULL_LOAD_THRESHOLD: float = 0.8
const GLOBAL_VALUE_UPGRADE_ID: String = "upgrade_global_value"
const GLOBAL_SPAWN_UPGRADE_ID: String = "upgrade_global_spawn"
const GLOBAL_CAPACITY_UPGRADE_ID: String = "upgrade_global_capacity"

var save_version: int = SAVE_VERSION
var bottles: int = 0
var total_bottles: int = 0
var currency: float = 0.0
var total_earned: float = 0.0
var current_scene_id: String = "street"

# upgrade_id -> level；一次性解锁通常使用 1，等级升级使用 1..max_level。
var upgrades: Dictionary = {}
# scene_id -> true；未出现在字典中的场景视为未解锁。
var unlocked_scenes: Dictionary = {}
# drop_id -> true；分类累计统计不等同于当前场景库存。
var unlocked_drops: Dictionary = {}
# helper_id -> true；购买和上阵是两个独立状态。
var purchased_helpers: Dictionary = {}
# helper_id -> true；缺少已购买帮手的键时按下阵兼容处理。
var active_helpers: Dictionary = {}
# talent_id -> true；天赋点余额由里程碑减去这些节点的 point_cost 推导。
var unlocked_talents: Dictionary = {}
# 自动装袋只累计实际拾取量；奖励产物不会再次推进此进度。
var auto_bag_progress: int = 0
# scene_id -> Array[drop_id]；保存后台库存的真实顺序。
var scene_drop_inventories: Dictionary = {}
# scene_id -> Array[serial]；与产物数组一一对应，用于切场景后稳定复原位置。
var scene_drop_serials: Dictionary = {}
var next_scene_drop_serial: int = 1
var defense_highest_unlocked_level: int = 1
var defense_cleared_levels: Dictionary = {}
## drop_id -> lifetime collected amount
var drop_collection_counts: Dictionary = {}


func reset_to_default() -> void:
    ## 清除所有玩家进度并恢复配置中的默认场景、产物和初始防守关卡。
    ## 这是内存操作；GM/SaveManager 调用方负责随后保存。
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
    auto_bag_progress = 0
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
    ## 更新当前回收物和累计回收物。只有正向增加才推进里程碑。
    if amount == 0:
        return
    bottles = maxi(bottles + amount, 0)
    if amount > 0:
        total_bottles += amount
    EventBus.bottle_changed.emit(bottles, amount)


func add_currency(amount: float) -> void:
    ## 修改现金并累计总收入；负数只影响当前现金，不倒扣历史收入。
    if amount == 0.0:
        return
    currency = maxf(currency + amount, 0.0)
    if amount > 0.0:
        total_earned += amount
    EventBus.currency_changed.emit(currency, amount)


func record_drop_collection(drop_id: String, amount: int) -> void:
    ## 写入指定产物的终身分类统计，天赋条件和统计弹窗读取此数据。
    if amount <= 0 or ConfigDB.get_drop(drop_id).is_empty():
        return
    var new_amount: int = get_drop_collection_count(drop_id) + amount
    drop_collection_counts[drop_id] = new_amount
    EventBus.drop_collection_count_changed.emit(drop_id, new_amount, amount)


func get_drop_collection_count(drop_id: String) -> int:
    ## 返回单类产物的终身收集数量，未知或损坏值按零处理。
    return maxi(0, int(drop_collection_counts.get(drop_id, 0)))


func get_drop_collection_counts() -> Dictionary:
    ## 返回分类统计副本，防止 UI 直接修改权威字典。
    return drop_collection_counts.duplicate()


func can_afford(cost: float) -> bool:
    ## 只判断余额，不产生扣费副作用。
    return currency >= cost


func spend_currency(cost: float) -> bool:
    ## 原子扣费入口；余额不足时保持状态不变。
    if not can_afford(cost):
        return false
    add_currency(-cost)
    return true


func get_upgrade_level(upgrade_id) -> int:
    ## 查询升级等级；不存在的升级按零级处理。
    return int(upgrades.get(upgrade_id, 0))


func set_upgrade_level(upgrade_id, level: int) -> void:
    ## 写入升级等级。合法性由 UpgradeSystem 或读档清洗负责。
    upgrades[upgrade_id] = level


func get_bottles_per_collect() -> int:
    ## 统一返回一次点击/帮手收集的基础数量，预留未来多倍拾取扩展。
    return 1


func get_drop_cash_value(base_cash: float) -> float:
    ## 叠加通用升级与天赋的收益效果；产物配置中的 cash 始终是基础价。
    return base_cash * (
        1.0
        + _upgrade_effect_total(GLOBAL_VALUE_UPGRADE_ID)
        + get_talent_effect_total("cash_bonus")
    )


func get_global_spawn_interval_multiplier() -> float:
    ## 返回所有场景共用的刷新间隔倍率，并设置最低速度保护。
    return maxf(
        0.3,
        1.0
        - _upgrade_effect_total(GLOBAL_SPAWN_UPGRADE_ID)
        - get_talent_effect_total("spawn_reduction")
    )


func get_global_capacity_bonus() -> int:
    ## 汇总通用升级与天赋带来的后台库存容量增量。
    return int(round(
        _upgrade_effect_total(GLOBAL_CAPACITY_UPGRADE_ID)
        + get_talent_effect_total("capacity_bonus")
    ))


func get_helper_speed_multiplier() -> float:
    ## 返回帮手移动速度倍率；团队协作按当前上阵帮手数量额外叠加，最多 20%。
    var team_bonus: float = minf(
        get_talent_effect_total("helper_team_efficiency_bonus") * float(active_helpers.size()),
        0.2
    )
    return 1.0 + get_talent_effect_total("helper_speed_bonus") + team_bonus


func get_helper_cooldown_multiplier() -> float:
    ## 返回帮手收集冷却倍率；团队协作同样提升周转效率，并限制过低冷却。
    var team_bonus: float = minf(
        get_talent_effect_total("helper_team_efficiency_bonus") * float(active_helpers.size()),
        0.2
    )
    return maxf(0.5, 1.0 - get_talent_effect_total("helper_cooldown_reduction") - team_bonus)


func get_manual_hold_interval() -> float:
    ## 返回玩家长按连续拾取间隔；未点亮中心天赋时返回 -1 表示功能关闭。
    if get_talent_effect_total("manual_hold_enabled") <= 0.0:
        return -1.0
    var interval: float = 0.8 - get_talent_effect_total("manual_hold_interval_reduction")
    return maxf(0.25, interval)


func get_manual_input_dedup_multiplier() -> float:
    ## 返回玩家点击去重时间倍率，避免闪电拾取让同一输入重复结算。
    return maxf(0.4, 1.0 - get_talent_effect_total("manual_input_dedup_reduction"))


func get_manual_combo_speed_multiplier(combo_active: bool) -> float:
    ## 连点节奏激活期间缩短长按拾取间隔；没有激活时保持原速。
    if not combo_active:
        return 1.0
    return 1.0 + get_talent_effect_total("manual_combo_speed_bonus")


func get_manual_combo_requirement() -> int:
    ## 返回触发连点节奏所需的实际手动拾取次数。
    return maxi(0, int(round(get_talent_effect_total("manual_combo_requirement"))))


func get_manual_combo_duration() -> float:
    ## 返回连点节奏的持续秒数。
    return maxf(0.0, get_talent_effect_total("manual_combo_duration"))


func get_full_load_helper_speed_multiplier(scene_id: String) -> float:
    ## 满载加班只在指定场景库存达到容量 80% 时提供额外移动速度。
    var bonus: float = get_talent_effect_total("full_load_helper_speed_bonus")
    var capacity: int = get_scene_capacity(scene_id)
    if bonus <= 0.0 or capacity <= 0:
        return 1.0
    var load_ratio: float = float(get_scene_drop_count(scene_id)) / float(capacity)
    return 1.0 + bonus if load_ratio >= FULL_LOAD_THRESHOLD else 1.0


func set_current_scene_id(scene_id: String) -> bool:
    ## 在配置存在且已解锁时切换当前场景，并广播场景变化。
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
    ## 兼容旧循环切换入口；新 UI 使用带方向和解锁检查的 offset 接口。
    set_current_scene_id(ConfigDB.get_next_scene_id(current_scene_id))


func switch_scene_by_offset(offset: int) -> bool:
    ## 按配置顺序尝试切换，实际动画由 BottleSpawnArea 负责。
    var scene_id: String = ConfigDB.get_scene_id_at_offset(current_scene_id, offset)
    if scene_id.is_empty():
        return false
    return set_current_scene_id(scene_id)


func can_switch_scene_by_offset(offset: int) -> bool:
    ## 只做无副作用的场景切换可行性检查。
    var scene_id: String = ConfigDB.get_scene_id_at_offset(current_scene_id, offset)
    return not scene_id.is_empty() and is_scene_unlocked(scene_id)


func is_scene_unlocked(scene_id: String) -> bool:
    ## 查询场景解锁状态。
    return bool(unlocked_scenes.get(scene_id, false))


func unlock_scene(scene_id: String) -> bool:
    ## 解锁场景并同步开放该场景配置的默认产物。
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
    ## 返回已解锁场景 ID 列表，顺序不作为 UI 排序依据。
    return unlocked_scenes.keys()


func is_drop_unlocked(drop_id: String) -> bool:
    ## 查询产物是否已进入实际生成池。
    return bool(unlocked_drops.get(drop_id, false))


func unlock_drop(drop_id: String) -> bool:
    ## 开放一个产物并通知生成区域刷新候选池。
    if drop_id.is_empty() or ConfigDB.get_drop(drop_id).is_empty():
        return false
    if is_drop_unlocked(drop_id):
        return false
    unlocked_drops[drop_id] = true
    EventBus.unlocked_drops_changed.emit()
    return true


func get_unlocked_drop_ids() -> Array:
    ## 返回已开放产物 ID 列表副本。
    return unlocked_drops.keys()


func get_scene_drop_ids(scene_id: String) -> Array:
    ## 返回场景后台库存的产物 ID 顺序，不创建任何画面节点。
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    return inventory.duplicate()


func get_scene_drop_serial(scene_id: String, index: int) -> int:
    ## 查询库存项的稳定序列号；缺少旧序列号时补充分配。
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    if index < 0 or index >= inventory.size():
        return 0
    var serials: Array = _ensure_scene_drop_serials(scene_id, inventory.size())
    return int(serials[index])


func get_scene_drop_serials(scene_id: String) -> Array:
    ## 返回整个场景序列号副本，供画面恢复稳定位置。
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    return _ensure_scene_drop_serials(scene_id, inventory.size()).duplicate()


func get_scene_drop_count(scene_id: String) -> int:
    ## 返回后台库存数量，而不是当前画面上渲染的节点数量。
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    return inventory.size()


func get_scene_capacity(scene_id: String) -> int:
    ## 计算场景基础上限加通用升级和天赋容量奖励。
    var scene: Dictionary = ConfigDB.get_scene(scene_id)
    if scene.is_empty():
        return 0
    return maxi(0, int(scene.get("max_inventory", scene.get("max_on_screen", 0))) + get_global_capacity_bonus())


func add_scene_drop(scene_id: String, drop_id: String) -> bool:
    ## 将一个已解锁且归属正确的产物追加到后台库存，并分配稳定序列号。
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
    ## 按产物 ID 消耗一项，供不关心实例序列号的旧入口使用。
    var inventory: Array = scene_drop_inventories.get(scene_id, [])
    var index: int = inventory.find(drop_id)
    if index < 0:
        return false
    return _consume_scene_drop_at(scene_id, index)


func consume_scene_drop_instance(scene_id: String, serial: int, expected_drop_id: String = "") -> bool:
    ## 按稳定序列号消耗指定实例，避免相邻产物或切场景后误收集。
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
    ## 同步删除产物和对应序列号，保证两个数组始终对齐。
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
    ## 查询帮手是否已购买。
    return bool(purchased_helpers.get(helper_id, false))


func is_helper_active(helper_id: String) -> bool:
    ## 只有已购买且 active_helpers 中存在时才算上阵。
    return has_helper(helper_id) and bool(active_helpers.get(helper_id, false))


func purchase_helper(helper_id: String) -> bool:
    ## 标记帮手已购买，并按产品规则默认上阵。
    if helper_id.is_empty() or ConfigDB.get_helper(helper_id).is_empty():
        return false
    if has_helper(helper_id):
        return false
    purchased_helpers[helper_id] = true
    active_helpers[helper_id] = true
    EventBus.helper_purchased.emit(helper_id)
    return true


func set_helper_active(helper_id: String, active: bool) -> bool:
    ## 切换帮手上阵状态；场景过场禁用由 UI 层控制。
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
    ## 查询天赋节点是否已点亮。
    return bool(unlocked_talents.get(talent_id, false))


func unlock_talent(talent_id: String) -> bool:
    ## 写入天赋点亮状态并广播；前置、条件和点数校验由 TalentSystem 完成。
    if talent_id.is_empty() or ConfigDB.get_talent(talent_id).is_empty():
        return false
    if is_talent_unlocked(talent_id):
        return false
    unlocked_talents[talent_id] = true
    EventBus.talent_unlocked.emit(talent_id)
    return true


func reset_talents() -> bool:
    ## 清空天赋节点但保留累计回收数据，调用方可立即保存。
    if unlocked_talents.is_empty() and auto_bag_progress <= 0:
        return false
    unlocked_talents.clear()
    auto_bag_progress = 0
    EventBus.talents_reset.emit()
    return true


func get_talent_points_earned() -> int:
    ## 统计已达到的回收里程碑数量，零件里程碑也计入但不消耗现金。
    var earned: int = 0
    for milestone in ConfigDB.get_talent_point_milestones():
        if total_bottles < int(milestone):
            break
        earned += 1
    return earned


func get_talent_points_spent() -> int:
    ## 按节点配置的 point_cost 汇总已使用点数，而不是简单统计字典长度。
    var spent: int = 0
    for talent_id in unlocked_talents.keys():
        var row: Dictionary = ConfigDB.get_talent(String(talent_id))
        spent += maxi(0, int(row.get("point_cost", 1)))
    return spent


func get_available_talent_points() -> int:
    ## 返回可用点数，并防止异常存档产生负余额。
    return maxi(0, get_talent_points_earned() - get_talent_points_spent())


func get_next_talent_point_milestone() -> int:
    ## 返回下一个未达到的累计回收门槛，全部完成时返回 -1。
    for milestone in ConfigDB.get_talent_point_milestones():
        if total_bottles < int(milestone):
            return int(milestone)
    return -1


func get_talent_effect_total(effect_id: String) -> float:
    ## 汇总所有已点亮节点中同名 effects 字段，供各玩法入口读取。
    var total: float = 0.0
    for talent_id in unlocked_talents.keys():
        var row: Dictionary = ConfigDB.get_talent(String(talent_id))
        var effects: Dictionary = row.get("effects", {})
        total += float(effects.get(effect_id, 0.0))
    return total


func advance_auto_bag_progress(actual_collected_amount: int) -> int:
    ## 推进自动装袋计数并返回本次应奖励的对应产物数量。
    ## 传入值必须是实际拾取数，调用方不能把上次奖励再次传入。
    var interval: int = int(round(get_talent_effect_total("auto_bag_interval")))
    var bonus_per_trigger: int = int(round(get_talent_effect_total("auto_bag_bonus")))
    if interval <= 0 or bonus_per_trigger <= 0:
        auto_bag_progress = 0
        return 0
    auto_bag_progress += maxi(0, actual_collected_amount)
    var trigger_count: int = floori(float(auto_bag_progress) / float(interval))
    auto_bag_progress %= interval
    return trigger_count * bonus_per_trigger


func is_defense_level_unlocked(level_id: int) -> bool:
    ## 关卡必须同时满足玩家进度和配置上限。
    return level_id >= 1 and level_id <= defense_highest_unlocked_level and level_id <= ConfigDB.get_defense_max_level()


func is_defense_level_cleared(level_id: int) -> bool:
    ## 查询关卡是否曾经首次通关。
    return bool(defense_cleared_levels.get(level_id, false))


func complete_defense_level(level_id: int) -> bool:
    ## 记录首次通关并解锁下一关；重复通关不重复推进进度。
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
    ## 生成完整存档快照；SaveManager 会在序列化前覆盖版本号。
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
        "auto_bag_progress": auto_bag_progress,
        "scene_drop_inventories": scene_drop_inventories,
        "scene_drop_serials": scene_drop_serials,
        "next_scene_drop_serial": next_scene_drop_serial,
        "defense_highest_unlocked_level": defense_highest_unlocked_level,
        "defense_cleared_levels": defense_cleared_levels,
        "drop_collection_counts": drop_collection_counts,
    }


func from_dict(d: Dictionary) -> void:
    ## 读取旧/新存档，填充默认字段，再按配置清洗所有外部数据。
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
    auto_bag_progress = maxi(0, int(d.get("auto_bag_progress", 0)))
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
    _sanitize_auto_bag_progress()
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
    ## 将旧存档中可能被 JSON 转成字符串的数字键恢复为整数键。
    var out: Dictionary = {}
    for k in d.keys():
        var key_variant = k
        if typeof(k) == TYPE_STRING and k.is_valid_int():
            key_variant = int(k)
        out[key_variant] = int(d[k])
    return out


static func _bool_key_dict(d: Dictionary) -> Dictionary:
    ## 将任意字典键统一为字符串并转换为布尔值。
    var out: Dictionary = {}
    for k in d.keys():
        out[String(k)] = bool(d[k])
    return out


static func _int_bool_key_dict(d: Dictionary) -> Dictionary:
    ## 清洗防守关卡完成表，只保留正整数且值为真的记录。
    var out: Dictionary = {}
    for k in d.keys():
        var level_id: int = int(k)
        if level_id > 0 and bool(d[k]):
            out[level_id] = true
    return out


static func _string_int_count_dict(value: Variant) -> Dictionary:
    ## 清洗终身数量表，过滤负数、零值和非字典输入。
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
    ## 分配全局递增序列号；序列号只用于稳定身份，不代表产物价值。
    var serial: int = maxi(1, next_scene_drop_serial)
    next_scene_drop_serial = serial + 1
    return serial


func _ensure_scene_drop_serials(scene_id: String, inventory_count: int) -> Array:
    ## 兼容旧存档缺少序列号的库存，并修剪多余序列号。
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
    ## 读档后补回配置要求的默认场景，防止旧存档阻塞新版本入口。
    for scene_id in ConfigDB.get_default_unlocked_scenes():
        unlocked_scenes[String(scene_id)] = true


func _merge_default_unlocked_drops() -> void:
    ## 读档后补回配置要求的默认产物。
    for drop_id in ConfigDB.get_default_unlocked_drops():
        unlocked_drops[String(drop_id)] = true


func _apply_unlock_upgrades_to_state() -> void:
    ## 根据历史升级记录重建场景和产物解锁，兼容早期存档字段。
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
    ## 清除无效场景、未解锁产物和超出容量的库存，同时保持序列号对齐。
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
    ## 只保留已购买且仍存在配置的上阵帮手。
    var sanitized: Dictionary = {}
    for helper_id_variant in active_helpers.keys():
        var helper_id: String = String(helper_id_variant)
        if has_helper(helper_id) and not ConfigDB.get_helper(helper_id).is_empty():
            sanitized[helper_id] = true
    active_helpers = sanitized


func _sanitize_unlocked_talents() -> void:
    ## 只保留有效节点，并按配置顺序过滤未满足前置的孤立节点。
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


func _sanitize_auto_bag_progress() -> void:
    ## 旧存档没有自动装袋字段时使用零；未点亮节点时不能保留隐藏进度。
    var interval: int = int(round(get_talent_effect_total("auto_bag_interval")))
    if interval <= 0:
        auto_bag_progress = 0
        return
    auto_bag_progress = clampi(auto_bag_progress, 0, interval - 1)


func _sanitize_defense_progress() -> void:
    ## 将防守进度限制在当前配置的最大关卡范围内。
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
    ## 删除不存在产物的分类统计，防止配置删除后天赋条件卡死。
    var sanitized: Dictionary = {}
    for drop_id_variant in drop_collection_counts.keys():
        var drop_id: String = String(drop_id_variant)
        var amount: int = maxi(0, int(drop_collection_counts.get(drop_id_variant, 0)))
        if amount > 0 and not ConfigDB.get_drop(drop_id).is_empty():
            sanitized[drop_id] = amount
    drop_collection_counts = sanitized


func _sanitize_upgrade_levels() -> void:
    ## 将旧版本升级等级限制到新配置上限，并过滤未知升级 ID。
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
    ## 按当前配置效果值计算升级总效果，并再次限制读取到的等级。
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    var level: int = clampi(get_upgrade_level(upgrade_id), 0, int(row.get("max_level", 0)))
    return float(level) * float(row.get("effect_per_level", 0.0))
