extends Control
## Right panel: upgrades.

var list: VBoxContainer
var buttons: Dictionary = {}
var panel_container: PanelContainer
var title_label: Label

const BASE_LOGICAL_WIDTH: float = 393.0


func _ready() -> void:
    _build()
    EventBus.currency_changed.connect(func(_a: float, _d: float): _refresh())
    EventBus.production_changed.connect(func(_p: float): _refresh())
    EventBus.upgrade_purchased.connect(func(_id: int, _lv: int): _refresh())
    _refresh()


func _build() -> void:
    panel_container = PanelContainer.new()
    panel_container.anchor_right = 1.0
    panel_container.anchor_bottom = 1.0
    add_child(panel_container)

    var box: VBoxContainer = VBoxContainer.new()
    box.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel_container.add_child(box)

    title_label = Label.new()
    title_label.text = "升级"
    box.add_child(title_label)

    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(scroll)

    list = VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(list)

    for row in ConfigDB.get_upgrades():
        var id: int = int(row.get("id", 0))
        var btn: Button = Button.new()
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.pressed.connect(_on_buy_pressed.bind(id))
        list.add_child(btn)
        buttons[id] = btn


func _refresh() -> void:
    var system: UpgradeSystem = get_tree().root.get_node_or_null("Main/Systems/UpgradeSystem") as UpgradeSystem
    for row in ConfigDB.get_upgrades():
        var id: int = int(row.get("id", 0))
        var btn: Button = buttons.get(id) as Button
        if btn == null:
            continue
        var level: int = GameState.get_upgrade_level(id)
        var max_level: int = int(row.get("max_level", 1))
        var next_cost: float = ConfigDB.get_upgrade_cost(id, level + 1)
        btn.text = "%s  Lv %d/%d\n%s\n花费 %s 元" % [
            String(row.get("name", "Upgrade")),
            level,
            max_level,
            String(row.get("description", "")),
            BigNumber.format(next_cost)
        ]
        btn.disabled = system == null or not system.can_buy(id)


func _on_buy_pressed(upgrade_id: int) -> void:
    var system: UpgradeSystem = get_tree().root.get_node_or_null("Main/Systems/UpgradeSystem") as UpgradeSystem
    if system != null:
        system.buy(upgrade_id)


func apply_layout(viewport_size: Vector2) -> void:
    var scale: float = _ui_scale(viewport_size)
    if panel_container != null:
        panel_container.add_theme_stylebox_override("panel", _panel_style(scale))
    if title_label != null:
        title_label.add_theme_font_size_override("font_size", int(18.0 * scale))
        title_label.add_theme_color_override("font_color", Color(0.34, 0.28, 0.45, 1.0))
    if list != null:
        list.add_theme_constant_override("separation", int(8.0 * scale))
    for btn_id in buttons.keys():
        var btn: Button = buttons[btn_id] as Button
        if btn == null:
            continue
        btn.custom_minimum_size = Vector2(0.0, 80.0 * scale)
        btn.add_theme_font_size_override("font_size", int(11.0 * scale))


func _ui_scale(viewport_size: Vector2) -> float:
    return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _panel_style(scale: float) -> StyleBoxFlat:
    var style: StyleBoxFlat = StyleBoxFlat.new()
    style.bg_color = Color(0.96, 0.94, 0.99, 0.98)
    style.border_color = Color(0.75, 0.68, 0.88, 1.0)
    style.set_border_width_all(int(2.0 * scale))
    style.set_corner_radius_all(int(12.0 * scale))
    style.content_margin_left = 10.0 * scale
    style.content_margin_right = 10.0 * scale
    style.content_margin_top = 10.0 * scale
    style.content_margin_bottom = 10.0 * scale
    return style
