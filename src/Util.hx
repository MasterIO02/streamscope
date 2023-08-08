package src;

using StringTools;

function toTwoDigits(number:Int) {
	return Std.string(number).lpad("0", 2);
}
