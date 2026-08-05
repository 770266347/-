extends Node
## 音频门面。
##
## 玩法代码只提交音效或音乐 ID，不直接持有 AudioStream、总线或播放器。
## 当前版本保留空实现；后续接入真实资源时只需修改此 Autoload，
## 不需要改动生产、升级、天赋等业务系统。


func play_sfx(_id: String) -> void:
    ## 播放一次性音效。未知 ID 应静默忽略，避免资源缺失阻断玩法。
    pass


func play_music(_id: String) -> void:
    ## 切换背景音乐。正式实现应处理重复播放、淡入淡出和总线音量。
    pass
