class_name TalentSystem
extends Node
## 天赋节点的规则校验与提交层。
##
## 天赋点余额由累计回收里程碑和已点亮节点实时推导，不单独保存货币字段。
## UI 只能通过本系统点亮或重置天赋，GameState 只提供底层状态变更。


func can_unlock(talent_id: String) -> bool:
    ## 检查节点有效性、重复状态、前置节点、指定产物数量和可用点数。
    var row: Dictionary = ConfigDB.get_talent(talent_id)
    if row.is_empty() or GameState.is_talent_unlocked(talent_id):
        return false
    for required_id in row.get("requires", []):
        if not GameState.is_talent_unlocked(String(required_id)):
            return false
    if not _collection_requirement_met(row):
        return false
    return GameState.get_available_talent_points() >= int(row.get("point_cost", 1))


func unlock(talent_id: String) -> bool:
    ## 校验通过后提交一次永久点亮；失败时状态完全不变。
    if not can_unlock(talent_id):
        return false
    if not GameState.unlock_talent(talent_id):
        return false
    AudioManager.play_sfx("cash")
    return true


func get_lock_reason(talent_id: String) -> String:
    ## 返回最优先的阻塞原因，检查顺序与 can_unlock 保持一致。
    var row: Dictionary = ConfigDB.get_talent(talent_id)
    if row.is_empty():
        return "无效天赋"
    if GameState.is_talent_unlocked(talent_id):
        return "已点亮"
    for required_id in row.get("requires", []):
        if not GameState.is_talent_unlocked(String(required_id)):
            var required: Dictionary = ConfigDB.get_talent(String(required_id))
            return "需要先点亮%s" % String(required.get("name", required_id))
    if not _collection_requirement_met(row):
        var requirement: Dictionary = row.get("requires_collection", {})
        var drop_id: String = String(requirement.get("drop_id", ""))
        var current: int = GameState.get_drop_collection_count(drop_id)
        var required_amount: int = int(requirement.get("amount", 0))
        return "需要收集%s %d/%d" % [ConfigDB.get_drop_name(drop_id), current, required_amount]
    var cost: int = int(row.get("point_cost", 1))
    if GameState.get_available_talent_points() < cost:
        return "天赋点不足"
    return "可以点亮"


func reset() -> bool:
    ## 清空天赋并立即保存；累计回收不变，因此点数自动返还。
    if not GameState.reset_talents():
        return false
    SaveManager.save_game()
    return true


func _collection_requirement_met(row: Dictionary) -> bool:
    ## 产品条件读取终身分类统计，而不是当前场景库存。
    var requirement: Dictionary = row.get("requires_collection", {})
    if requirement.is_empty():
        return true
    var drop_id: String = String(requirement.get("drop_id", ""))
    var required_amount: int = int(requirement.get("amount", 0))
    return GameState.get_drop_collection_count(drop_id) >= required_amount
