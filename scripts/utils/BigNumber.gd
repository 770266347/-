class_name BigNumber
extends RefCounted
## 增量游戏统一数字格式化器，例如 1.23 K、4.56 M、7.89 B。
##
## 只改变显示字符串，不损失实际数值精度。资源栏、价格和统计应共享此实现。

const UNITS: PackedStringArray = [
    "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"
]


static func format(value: float, digits: int = 2) -> String:
    ## 按 1000 进位缩写有限数值，并保留指定小数位。
    if is_nan(value) or is_inf(value):
        return "∞"
    var sign: String = "-" if value < 0.0 else ""
    var v: float = abs(value)
    if v < 1000.0:
        return sign + _trim(v, digits)
    var idx: int = int(floor(log(v) / log(1000.0)))
    if idx <= 0:
        return sign + _trim(v, digits)
    var scaled: float = v / pow(1000.0, float(idx))
    return "%s%s %s" % [sign, _trim(scaled, digits), _suffix_for(idx)]


static func _suffix_for(idx: int) -> String:
    ## 内置单位用完后生成双字母后缀，使极大数仍可显示。
    if idx < UNITS.size():
        return UNITS[idx]
    var offset: int = idx - UNITS.size()
    var first: int = offset / 26
    var second: int = offset % 26
    return "%c%c" % [97 + first, 97 + second]


static func _trim(v: float, digits: int) -> String:
    ## 去掉末尾无意义的零和小数点，减少 UI 占宽。
    var s: String = String.num(v, digits)
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s
