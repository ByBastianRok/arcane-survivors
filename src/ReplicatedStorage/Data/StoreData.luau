-- StoreData (ModuleScript) · S-Smn - TIENDA: packs de valor (dev products) + gamepasses de conveniencia.
-- Cada pack/gamepass se CREA en el Creator Dashboard de Roblox y su ID va aqui (packs) o en MonetizationData (pases).
-- 'da' = lo que entrega el pack: gems / cash / <material> (woods/frost/ember/rare, ver CraftData).
-- 'valor' = precio "normal" en Robux (tachado en la UI) para que se vea el CHOLLO; 'robux' = precio real.
-- OJO: 'robux' DEBE coincidir con el precio puesto en Roblox (si no, la UI miente al jugador).
local StoreData = {}

-- ===== PACKS (developer products, se compran con Robux; repetibles salvo oneTime) =====
StoreData.Packs = {
	{
		id = "starter", nombre = "Starter Pack", productId = 0,
		robux = 99, valor = 350, oneTime = true, banner = "BEST VALUE",
		color = Color3.fromRGB(255, 205, 80),
		da = { gems = 250, woods = 40, frost = 40, ember = 40, cash = 5000 }, -- gancho de entrada: gems a buen precio + materiales + cash gratis
	},
	{
		id = "forge", nombre = "Forge Pack", productId = 0,
		robux = 199, valor = 450, limite = 10, banner = "SUPER OP",
		color = Color3.fromRGB(120, 200, 130),
		da = { woods = 80, frost = 80, ember = 80, rare = 12 }, -- pack de crafteo puro (para los que craftean reliquias/consumibles)
	},
	{
		id = "gems", nombre = "Gem Chest", productId = 0,
		robux = 299, valor = 600, limite = 20,
		color = Color3.fromRGB(150, 110, 245),
		da = { gems = 1200 }, -- 1200/299 = 4.0 gems/R$ -> mejor ratio que los packs chicos, peor que el de 2000 (escalera coherente)
	},
	{
		id = "mega", nombre = "Mega Pack", productId = 0,
		robux = 600, valor = 1500, limite = 10, banner = "SUPER OP",
		color = Color3.fromRGB(245, 130, 70),
		da = { gems = 1500, woods = 120, frost = 120, ember = 120, rare = 25, cash = 25000 }, -- el "todo en uno" tope de gama
	},
}

-- ===== GAMEPASSES de conveniencia (compra unica). El ID real va en MonetizationData.Gamepasses[id]. =====
-- El server pone el atributo Pass_<id> a los duenos; los efectos se aplican leyendo ese atributo.
-- 'nombre' = igual que en Roblox (lo que ve el jugador en el popup de compra).
StoreData.Gamepasses = {
	{ id = "extradrop",  nombre = "More Materials",  desc = "+50% material drops",        robux = 399 },
	{ id = "vip",        nombre = "VIP",             desc = "Daily Gems + free spin + VIP tag", robux = 499 },
	{ id = "cash2x",     nombre = "2x Cash",         desc = "DOUBLE all Cash earned in runs",   robux = 349 },
	{ id = "gems2x",     nombre = "2x Gems",         desc = "DOUBLE Gems earned by playing",    robux = 499 },
	{ id = "extraslot",  nombre = "Extra Relic Slot", desc = "+1 relic slot (equip 4 instead of 3)", robux = 449 },
}

function StoreData.packPorProducto(productId)
	if not productId or productId == 0 then return nil end
	for _, p in ipairs(StoreData.Packs) do
		if p.productId == productId then return p end
	end
	return nil
end

function StoreData.packPorId(id)
	for _, p in ipairs(StoreData.Packs) do
		if p.id == id then return p end
	end
	return nil
end

return StoreData
