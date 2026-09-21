class_name Money
extends RefCounted

## One rounding policy for the whole game, shared by revenue and the ledger so
## the two sides can never disagree by a cent.

const SCALE := 100.0


static func round(amount: float) -> float:
	# Half-up on magnitude, so a refund always mirrors its charge.
	if amount >= 0.0:
		return floorf(amount * SCALE + 0.5) / SCALE
	return ceilf(amount * SCALE - 0.5) / SCALE


static func format(amount: float) -> String:
	var negative := amount < 0.0
	var value := absf(amount)
	var whole := int(floorf(value))
	var cents := int(roundf((value - whole) * 100.0))
	if cents >= 100:
		whole += 1
		cents -= 100
	var grouped := _group(whole)
	var sign := "-" if negative else ""
	if cents == 0:
		return "%s$%s" % [sign, grouped]
	return "%s$%s.%02d" % [sign, grouped, cents]


static func format_compact(amount: float) -> String:
	var negative := amount < 0.0
	var value := absf(amount)
	var sign := "-" if negative else ""
	if value >= 1000000.0:
		return "%s$%.2fM" % [sign, value / 1000000.0]
	if value >= 10000.0:
		return "%s$%.0fk" % [sign, value / 1000.0]
	return format(amount)


static func _group(whole: int) -> String:
	var digits := str(whole)
	var out := ""
	var count := 0
	for index in range(digits.length() - 1, -1, -1):
		out = digits[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = "," + out
	return out
