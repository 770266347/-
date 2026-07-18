extends Node
## Handles load/save of GameState to user://.

const LATEST_VERSION: int = 5

var autosave_interval: float = 15.0
var _timer: float = 0.0


func _ready() -> void:
    if not load_game():
        GameState.reset_to_default()
    EventBus.save_loaded.emit()
    set_process(true)


func _process(delta: float) -> void:
    _timer += delta
    if _timer >= autosave_interval:
        _timer = 0.0
        save_game()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
        save_game()


func save_game() -> void:
    var dict: Dictionary = GameState.to_dict()
    dict["save_version"] = LATEST_VERSION
    if not PlatformBridge.write_save_text(JSON.stringify(dict, "\t")):
        return


func load_game() -> bool:
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
    PlatformBridge.delete_save()


func _migrate(d: Dictionary) -> Dictionary:
    var v: int = int(d.get("save_version", 0))
    if v > LATEST_VERSION:
        push_warning("Save from a newer version (%d) than current (%d)" % [v, LATEST_VERSION])
    return d
