-- Util (ModuleScript) - helpers compartidos cliente+servidor.
local Util = {}

-- 1234 -> "1.2K", 1500000 -> "1.5M". Para HUD/tienda.
function Util.formatNumber(n)
	local abs = math.abs(n)
	if abs >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif abs >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

-- Random ponderado: weightedRandom({comun=70, raro=25, epico=5}) -> una clave según su peso.
function Util.weightedRandom(pesos)
	local total = 0
	for _, p in pairs(pesos) do total += p end
	if total <= 0 then return nil end
	local r = math.random() * total
	for clave, p in pairs(pesos) do
		r -= p
		if r <= 0 then return clave end
	end
end

return Util
