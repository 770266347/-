extends Node
## 全局事件总线。
##
## GameState 和业务系统发出事实事件，UI 只订阅并刷新显示，双方不互相持有。
## delta 表示本次变化量，new_amount 表示变化后的权威总量。
## 此脚本不保存状态，也不执行玩法逻辑。

# 核心资源与收集结算事件。

signal currency_changed(new_amount: float, delta: float)
signal bottle_changed(new_amount: int, delta: int)

signal bottle_collected(bottle_amount: int, cash_amount: float, screen_pos: Vector2)
signal drop_collected(drop_name: String, amount: int, cash_amount: float, screen_pos: Vector2)
signal drop_collection_count_changed(drop_id: String, new_amount: int, delta: int)

# 永久成长、帮手和场景状态事件。
signal upgrade_purchased(upgrade_id, new_level: int)
signal upgrade_maxed(upgrade_id)
signal helper_purchased(helper_id: String)
signal helper_active_changed(helper_id: String, active: bool)
signal talent_unlocked(talent_id: String)
signal talents_reset()
signal scene_unlocked(scene_id: String)
signal scene_switch_requested(offset: int)
signal scene_transition_started()
signal scene_transition_finished(scene_id: String)
signal scene_changed(scene_id: String)
signal scene_inventory_changed(scene_id: String)
signal unlocked_drops_changed()

# 街区防守模式事件。
signal defense_mode_requested()
signal defense_mode_exit_requested()
signal defense_level_completed(level_id: int)

# 生命周期与通用视觉反馈事件。
signal save_loaded()
signal number_popup(screen_pos: Vector2, text: String, color: Color)
