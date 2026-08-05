class_name UpgradeSystem
extends Node
## 永久升级、场景解锁和帮手购买的交易系统。
##
## 交易遵循“完整校验、扣费、变更状态、广播事件”的顺序，
## 校验失败时不能产生部分扣费或部分解锁。


func can_buy(upgrade_id) -> bool:
    ## 检查配置、前置项、目标状态、等级上限和现金余额。
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    if row.is_empty():
        return false
    if not _requirements_met(row):
        return false
    match String(row.get("type", "")):
        "unlock_drop":
            if GameState.is_drop_unlocked(String(row.get("unlock_drop_id", ""))):
                return false
        "unlock_scene":
            if GameState.is_scene_unlocked(String(row.get("unlock_scene_id", ""))):
                return false
    var level: int = GameState.get_upgrade_level(upgrade_id)
    if level >= int(row.get("max_level", 1)):
        return false
    return GameState.can_afford(get_next_cost(upgrade_id))


func buy(upgrade_id) -> bool:
    ## 购买一级；解锁型升级会同步写入场景或产物状态。
    if not can_buy(upgrade_id):
        return false
    var level: int = GameState.get_upgrade_level(upgrade_id)
    var cost: float = get_next_cost(upgrade_id)
    if not GameState.spend_currency(cost):
        return false
    GameState.set_upgrade_level(upgrade_id, level + 1)
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    match String(row.get("type", "")):
        "unlock_drop":
            GameState.unlock_drop(String(row.get("unlock_drop_id", "")))
        "unlock_scene":
            GameState.unlock_scene(String(row.get("unlock_scene_id", "")))
            for drop_id in row.get("unlock_drop_ids", []):
                GameState.unlock_drop(String(drop_id))
    EventBus.upgrade_purchased.emit(upgrade_id, level + 1)
    AudioManager.play_sfx("cash")
    if level + 1 >= int(ConfigDB.get_upgrade(upgrade_id).get("max_level", 1)):
        EventBus.upgrade_maxed.emit(upgrade_id)
    return true


func get_next_cost(upgrade_id) -> float:
    ## 返回从当前等级升到下一级的配置化价格。
    return ConfigDB.get_upgrade_cost(upgrade_id, GameState.get_upgrade_level(upgrade_id) + 1)


func is_maxed(upgrade_id) -> bool:
    ## 判断当前等级是否已达到配置上限。
    var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
    return GameState.get_upgrade_level(upgrade_id) >= int(row.get("max_level", 1))


func can_buy_helper(helper_id: String) -> bool:
    ## 帮手为一次性购买，不使用升级等级。
    var row: Dictionary = ConfigDB.get_helper(helper_id)
    if row.is_empty() or GameState.has_helper(helper_id):
        return false
    return GameState.can_afford(float(row.get("cost", INF)))


func buy_helper(helper_id: String) -> bool:
    ## 购买成功后由 GameState 默认设置为上阵。
    if not can_buy_helper(helper_id):
        return false
    var row: Dictionary = ConfigDB.get_helper(helper_id)
    if not GameState.spend_currency(float(row.get("cost", INF))):
        return false
    if not GameState.purchase_helper(helper_id):
        return false
    AudioManager.play_sfx("cash")
    return true


func _requirements_met(row: Dictionary) -> bool:
    ## requires 保存升级 ID，任一前置等级为零即不满足。
    for required_upgrade_id in row.get("requires", []):
        if GameState.get_upgrade_level(required_upgrade_id) <= 0:
            return false
    return true
