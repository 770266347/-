class_name BigNumber
extends RefCounted
## Incremental-game number formatter: 1.23 K, 4.56 M, 7.89 B...

const UNITS: PackedStringArray = [
    "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"
]


static func format(value: float, digits: int = 2) -> String:
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
    if idx < UNITS.size():
        return UNITS[idx]
    var offset: int = idx - UNITS.size()
    var first: int = offset / 26
    var second: int = offset % 26
    return "%c%c" % [97 + first, 97 + second]


static func _trim(v: float, digits: int) -> String:
    var s: String = String.num(v, digits)
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s
