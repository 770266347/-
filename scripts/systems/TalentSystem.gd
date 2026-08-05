class_name TalentSystem
extends Node
## Unlocks permanent talent nodes with points earned from collection milestones.


func can_unlock(talent_id: String) -> bool:
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
    if not can_unlock(talent_id):
        return false
    if not GameState.unlock_talent(talent_id):
        return false
    AudioManager.play_sfx("cash")
    return true


func get_lock_reason(talent_id: String) -> String:
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
    if not GameState.reset_talents():
        return false
    SaveManager.save_game()
    return true


func _collection_requirement_met(row: Dictionary) -> bool:
    var requirement: Dictionary = row.get("requires_collection", {})
    if requirement.is_empty():
        return true
    var drop_id: String = String(requirement.get("drop_id", ""))
    var required_amount: int = int(requirement.get("amount", 0))
    return GameState.get_drop_collection_count(drop_id) >= required_amount
