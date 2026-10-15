extends HBoxContainer
func configure(name_text: String, value: int, max_value: int = 5) -> void:
	$Name.text = name_text
	$Value.max_value = max_value
	$Value.value = value
	$Amount.text = "%d/%d" % [value, max_value]
