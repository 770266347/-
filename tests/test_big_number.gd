extends RefCounted
## BigNumber 最小回归样例，覆盖不缩写、K 和 M 三个数量级。


func test_big_number_examples() -> void:
    ## 固定玩家可见格式，防止格式化调整意外改变既有文案。
    assert(BigNumber.format(999.0) == "999")
    assert(BigNumber.format(1500.0) == "1.5 K")
    assert(BigNumber.format(2500000.0) == "2.5 M")
