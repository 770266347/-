extends Node
## 桌面端、Web 和未来小游戏壳之间的平台边界。
##
## 上层系统只调用统一的存档和平台查询接口，不读取 OS 名称或直接访问文件。
## 小程序 SDK 接入时应在这里替换持久化实现，保持 SaveManager 与玩法代码不变。

const SAVE_KEY: String = "garbage_collector_save_v1"
const SAVE_PATH: String = "user://garbage_collector_save_v1.json"
const MINI_GAME_FEATURE: String = "mini_game"

var target_name: String = "desktop"


func _ready() -> void:
    ## 冷启动时只检测一次目标平台；运行过程中 target_name 保持稳定。
    target_name = _detect_target_name()
    print("[PlatformBridge] target=%s" % target_name)


func is_web() -> bool:
    ## Web 导出和小游戏壳都可能基于 Web，此判断只代表引擎环境。
    return OS.has_feature("web")


func is_mobile() -> bool:
    ## 返回 Godot 是否报告移动端系统，不包含普通桌面触摸屏。
    return OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")


func is_desktop() -> bool:
    ## 桌面测试窗口和桌面专用调试行为使用此入口判断。
    return not is_web() and not is_mobile()


func is_mini_game_shell() -> bool:
    ## 通过自定义 feature 标记识别未来的小游戏适配壳。
    return OS.has_feature(MINI_GAME_FEATURE)


func is_touch_preferred() -> bool:
    ## UI 可据此选择触摸优先交互，但不能因此禁用鼠标输入。
    return is_mobile() or OS.has_feature("web_android") or OS.has_feature("web_ios")


func get_platform_summary() -> Dictionary:
    ## 返回调试摘要，不应作为玩家进度写入存档。
    return {
        "target": target_name,
        "os": OS.get_name(),
        "web": is_web(),
        "mobile": is_mobile(),
        "mini_game_shell": is_mini_game_shell(),
        "touch_preferred": is_touch_preferred(),
    }


func has_save() -> bool:
    ## 查询当前平台持久化层是否存在游戏存档。
    return FileAccess.file_exists(SAVE_PATH)


func load_save_text() -> String:
    ## 读取原始 JSON；不存在或读取失败时返回空字符串。
    if not has_save():
        return ""
    return FileAccess.get_file_as_string(SAVE_PATH)


func write_save_text(raw: String) -> bool:
    ## 返回 false 表示本次保存没有成功落盘。
    var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if f == null:
        push_error("Could not open save file for write: %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()])
        return false
    f.store_string(raw)
    f.close()
    return true


func delete_save() -> void:
    ## 只删除持久化存档，不负责重置内存中的 GameState。
    if not has_save():
        return
    var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
    if err != OK:
        push_warning("Could not delete save file: %s (error %d)" % [SAVE_PATH, err])


func _detect_target_name() -> String:
    ## 将 Godot 平台信息归一化为项目内部稳定名称。
    if is_mini_game_shell():
        return "mini_game"
    if is_web():
        return "web"
    if is_mobile():
        return "mobile"
    return "desktop"
