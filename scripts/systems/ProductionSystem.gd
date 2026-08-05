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
    ## 自动装袋只按实际拾取数推进；奖励会增加对应产物数量但不增加现金，
    ## 也不会再次传入进度函数，因此不会递归触发下一次装袋。
    if bottle_amount <= 0:
        return
    var bag_bonus: int = GameState.advance_auto_bag_progress(bottle_amount)
    var total_bottle_amount: int = bottle_amount + bag_bonus
    GameState.record_drop_collection(drop_id, total_bottle_amount)
    GameState.add_bottles(total_bottle_amount)
    GameState.add_currency(cash_amount)
    EventBus.bottle_collected.emit(total_bottle_amount, cash_amount, screen_pos)
    EventBus.drop_collected.emit(drop_name, total_bottle_amount, cash_amount, screen_pos)
    if screen_pos != Vector2.ZERO:
        var bag_text: String = "（装袋 +%d）" % bag_bonus if bag_bonus > 0 else ""
        EventBus.number_popup.emit(
            screen_pos,
            "+%d %s%s +%s 元" % [total_bottle_amount, drop_name, bag_text, BigNumber.format(cash_amount)],
            Color(0.4, 0.95, 0.55)
        )
