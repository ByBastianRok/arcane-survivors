-- MonetizationData (ModuleScript) · S2 - IDs de gamepasses + productos de Gems (Robux).
-- Gamepasses = compra unica (desbloquean x3/autospin; las tiradas siguen costando Gems).
-- GemsProducts = developer products (consumibles): productId -> Gems que da.
local MonetizationData = {}

MonetizationData.Gamepasses = { autospin = 0, x3 = 0, extradrop = 0, vip = 0, cash2x = 0, gems2x = 0, extraslot = 0 } -- extradrop=More Materials, vip=VIP; cash2x/gems2x/extraslot = gamepasses de PODER.
-- IDs a 0 = sin crear (no se ofrece la compra). Pon los de tu juego (Creator Dashboard > Monetization). Los reales no se publican.

-- Extra Life ahora es CONSUMIBLE (developer product): pagar al morir para revivir. NO es gamepass.
MonetizationData.ReviveProduct = 0
MonetizationData.RevivePrecio = 99 -- solo para mostrar en la UI (el cobro real lo fija Roblox)

MonetizationData.GemsProducts = {
	[0] = 200,
	[0] = 500,
	[0] = 2000,
}

-- Packs ordenados (para la UI de tienda de Gems).
MonetizationData.GemsPacks = {
	{ productId = 0, gems = 200 },
	{ productId = 0, gems = 500 },
	{ productId = 0, gems = 2000 },
}

return MonetizationData
