extends Node
## GameState 的持久化协调器。
##
## 负责自动保存节奏、JSON 序列化和版本迁移入口；实际读写由 PlatformBridge 完成。
## 默认值与字段合法性由 GameState 负责，避免迁移规则散落在 UI 中。

const LATEST_VERSION: int = 11

var autosave_interval: float = 15.0
var _timer: float = 0.0


func _ready() -> void:
    ## 启动时先读档；没有有效存档才创建默认状态。
    if not load_game():
        GameState.reset_to_default()
    EventBus.save_loaded.emit()
    set_process(true)


func _process(delta: float) -> void:
    ## 累计前台运行时间，到达间隔后保存一次完整快照。
    _timer += delta
    if _timer >= autosave_interval:
        _timer = 0.0
        save_game()


func _notification(what: int) -> void:
    ## 窗口关闭或移动端返回前尽量保存，减少最后一段进度丢失。
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
        save_game()


func save_game() -> void:
    ## 写入当前快照，并统一覆盖为最新存档版本号。
    var dict: Dictionary = GameState.to_dict()
    dict["save_version"] = LATEST_VERSION
    if not PlatformBridge.write_save_text(JSON.stringify(dict, "\t")):
        return


func load_game() -> bool:
    ## 读取、解析、迁移并校验；任一步失败都返回 false。
    if not PlatformBridge.has_save():
        return false
    var raw: String = PlatformBridge.load_save_text()
    var parsed = JSON.parse_string(raw)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Save file corrupted, resetting.")
        return false
    GameState.from_dict(_migrate(parsed))
    return true


func delete_save() -> void:
    ## 只删持久化文件，调用方仍需显式重置 GameState。
    PlatformBridge.delete_save()


func _migrate(d: Dictionary) -> Dictionary:
    ## 跨版本字段转换集中在此，并应按版本从旧到新依次执行。
    var v: int = int(d.get("save_version", 0))
    if v > LATEST_VERSION:
        push_warning("Save from a newer version (%d) than current (%d)" % [v, LATEST_VERSION])
    return d
