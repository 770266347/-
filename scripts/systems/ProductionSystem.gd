class_name ProductionSystem
extends Node
## 统一的回收物结算系统。
##
## 玩家点击和帮手拾取都必须走此入口，确保现金倍率、分类统计、总回收量、
## 音效和飘字只结算一次。本系统不负责寻找目标或移除画面节点。


func collect_drop(drop: Dictionary, screen_pos: Vector2) -> void:
    ## 根据静态配置计算最终数量与现金，再提交统一发奖。
    ## screen_pos 为零时仍结算资源，但不生成飘字。
    if drop.is_empty():
        return
    var amount: int = int(drop.get("reward_count", GameState.get_bottles_per_collect()))
    var base_cash: float = float(drop.get("cash", GameState.BASE_BOTTLE_VALUE))
    var cash_amount: float = GameState.get_drop_cash_value(base_cash) * float(amount)
    _grant_collectable(
        String(drop.get("id", "")),
        amount,
        cash_amount,
        String(drop.get("name", "回收物")),
        screen_pos
    )
    AudioManager.play_sfx("click")


func _grant_collectable(drop_id: String, bottle_amount: int, cash_amount: float, drop_name: String, screen_pos: Vector2) -> void:
    ## 先写入权威状态再广播事件，保证监听者读到的是更新后的总量。
    if bottle_amount <= 0:
        return
    GameState.record_drop_collection(drop_id, bottle_amount)
    GameState.add_bottles(bottle_amount)
    GameState.add_currency(cash_amount)
    EventBus.bottle_collected.emit(bottle_amount, cash_amount, screen_pos)
    EventBus.drop_collected.emit(drop_name, bottle_amount, cash_amount, screen_pos)
    if screen_pos != Vector2.ZERO:
        EventBus.number_popup.emit(
            screen_pos,
            "+%d %s +%s 元" % [bottle_amount, drop_name, BigNumber.format(cash_amount)],
            Color(0.4, 0.95, 0.55)
        )
