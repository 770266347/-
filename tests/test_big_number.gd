extends RefCounted


func test_big_number_examples() -> void:
    assert(BigNumber.format(999.0) == "999")
    assert(BigNumber.format(1500.0) == "1.5 K")
    assert(BigNumber.format(2500000.0) == "2.5 M")

