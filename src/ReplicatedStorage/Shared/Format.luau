local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "950", 1234 -> "1.23K", 15600 -> "15.6K", 2500000 -> "2.5M"
function Format.short(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local i, v = 1, n
	while v >= 1000 and i < #SUFFIXES do
		v /= 1000
		i += 1
	end
	local s = if v >= 100 then string.format("%d", v) elseif v >= 10 then string.format("%.1f", v) else string.format("%.2f", v)
	if string.find(s, "%.") then
		s = string.gsub(string.gsub(s, "0+$", ""), "%.$", "")
	end
	return s .. SUFFIXES[i]
end

return Format
