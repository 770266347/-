extends Node
## Platform-facing boundary. Keep publish-target checks and storage hooks here.

const SAVE_KEY: String = "garbage_collector_save_v1"
const SAVE_PATH: String = "user://garbage_collector_save_v1.json"
const MINI_GAME_FEATURE: String = "mini_game"

var target_name: String = "desktop"


func _ready() -> void:
    target_name = _detect_target_name()
    print("[PlatformBridge] target=%s" % target_name)


func is_web() -> bool:
    return OS.has_feature("web")


func is_mobile() -> bool:
    return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")


func is_desktop() -> bool:
    return not is_web() and not is_mobile()


func is_mini_game_shell() -> bool:
    return OS.has_feature(MINI_GAME_FEATURE)


func is_touch_preferred() -> bool:
    return is_mobile() or OS.has_feature("web_android") or OS.has_feature("web_ios")


func get_platform_summary() -> Dictionary:
    return {
        "target": target_name,
        "os": OS.get_name(),
        "web": is_web(),
        "mobile": is_mobile(),
        "mini_game_shell": is_mini_game_shell(),
        "touch_preferred": is_touch_preferred(),
    }


func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)


func load_save_text() -> String:
    if not has_save():
        return ""
    return FileAccess.get_file_as_string(SAVE_PATH)


func write_save_text(raw: String) -> bool:
    var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if f == null:
        push_error("Could not open save file for write: %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
        return false
    f.store_string(raw)
    f.close()
    return true


func delete_save() -> void:
    if not has_save():
        return
    var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
    if err != OK:
        push_warning("Could not delete save file: %s (error %d)" % [SAVE_PATH, err])


func _detect_target_name() -> String:
    if is_mini_game_shell():
        return "mini_game"
    if is_web():
        return "web"
    if is_mobile():
        return "mobile"
    return "desktop"
