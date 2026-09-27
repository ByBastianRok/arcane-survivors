-- CraftData (ModuleScript) - Scr - MATERIALES + RELIQUIAS (crafteo por receta).
-- Materiales sueltan en la run (tematicos por mundo, escalan con la dificultad via WorldMatMult).
-- Reliquias = bonus pasivo PERMANENTE; equipas hasta CraftData.Slots a la vez (eliges build).
-- Forjas por RECETA (gastas materiales) y subes de nivel con mas materiales. aplicar(m,lvl) muta mods.
-- El cliente LEE textos/coste; SOLO el servidor valida y forja.
local CraftData = {}

CraftData.Slots = 3 -- reliquias equipables a la vez (no caben todas = eliges build)
CraftData.CosteShard = { rare = 3 } -- materiales por 1 shard de clase (crafteo; complementa el gacha). TUNABLE.

-- Materiales. id interno -> nombre (player) + color (UI). woods/frost/ember = 1 por mundo; rare = jefes/dificultad.
CraftData.Materiales = {
	{ id = "woods", nombre = "Verdant Essence", color = Color3.fromRGB(110, 200, 110) },
	{ id = "frost", nombre = "Frost Shard",     color = Color3.fromRGB(130, 205, 240) },
	{ id = "ember", nombre = "Ember Core",      color = Color3.fromRGB(240, 140, 70) },
	{ id = "rare",  nombre = "Ancient Core",    color = Color3.fromRGB(210, 130, 245) },
	{ id = "dust",  nombre = "Arcane Dust",     color = Color3.fromRGB(200, 195, 215) }, -- 22-jul: material de RELLENO comun (cae generoso cada acto). Base barata para potis rapidas.
}

-- Reliquias. receta = coste para FORJAR (nivel 1). subir = coste base por nivel extra. aplicar(m,lvl) muta los mods.
CraftData.Reliquias = {
	{ id = "rdano", nombre = "Warrior's Band", desc = "+6% damage per level", rareza = "Common", maxNivel = 5,
		receta = { woods = 8 }, subir = { woods = 6 },
		aplicar = function(m, lvl) m.danoMult *= (1 + 0.06 * lvl) end },
	{ id = "rvida", nombre = "Stoneheart", desc = "+10% max health per level", rareza = "Common", maxNivel = 5,
		receta = { frost = 8 }, subir = { frost = 6 },
		aplicar = function(m, lvl) m.vidaMult *= (1 + 0.10 * lvl) end },
	{ id = "rcrit", nombre = "Ember Lens", desc = "+3% crit chance per level", rareza = "Rare", maxNivel = 5,
		receta = { ember = 8 }, subir = { ember = 6 },
		aplicar = function(m, lvl) m.critChance = math.min(1, m.critChance + 0.03 * lvl) end },
	{ id = "rvelo", nombre = "Swiftfoot Charm", desc = "+3% move speed per level", rareza = "Rare", maxNivel = 5,
		receta = { woods = 6, frost = 6 }, subir = { woods = 4, frost = 4 },
		aplicar = function(m, lvl) m.velocidadMult *= (1 + 0.03 * lvl) end },
	{ id = "rsuerte", nombre = "Lucky Idol", desc = "+4 Luck per level", rareza = "Epic", maxNivel = 5,
		receta = { ember = 6, rare = 2 }, subir = { ember = 5, rare = 1 },
		aplicar = function(m, lvl) m.suerte += 4 * lvl end },
	{ id = "rcash", nombre = "Midas Charm", desc = "+6% Cash earned per level", rareza = "Epic", maxNivel = 5,
		receta = { frost = 6, rare = 2 }, subir = { frost = 5, rare = 1 },
		aplicar = function(m, lvl) m.cashMult *= (1 + 0.06 * lvl) end },
	-- --- Anadidas el 22-jul (Bastian: "mas crafteos"): mas variedad de build + cada material del mundo tiene
	-- --- ahora VARIAS recetas de un solo material, para que deje de sobrar (antes woods solo servia para el
	-- --- Warrior's Band). Todas usan campos de mods que ya existen y aplica el motor (cadenciaMult/roboVida/etc). ---
	{ id = "rcaden", nombre = "Hunter's Charm", desc = "+4% attack speed per level", rareza = "Common", maxNivel = 5,
		receta = { woods = 10 }, subir = { woods = 7 },
		aplicar = function(m, lvl) m.cadenciaMult *= (1 - 0.04 * lvl) end },
	{ id = "rarmor", nombre = "Aegis Sigil", desc = "-3% damage taken per level", rareza = "Rare", maxNivel = 5,
		receta = { frost = 10 }, subir = { frost = 7 },
		aplicar = function(m, lvl) m.danoRecibidoMult *= (1 - 0.03 * lvl) end },
	{ id = "rrobo", nombre = "Bloodgem", desc = "+2% lifesteal per level", rareza = "Rare", maxNivel = 5,
		receta = { ember = 10 }, subir = { ember = 7 },
		aplicar = function(m, lvl) m.roboVida = (m.roboVida or 0) + 0.02 * lvl end },
	{ id = "rrango", nombre = "Farsight Totem", desc = "+5% attack range per level", rareza = "Rare", maxNivel = 5,
		receta = { woods = 8, ember = 8 }, subir = { woods = 5, ember = 5 },
		aplicar = function(m, lvl) m.rangoMult = (m.rangoMult or 1) * (1 + 0.05 * lvl) end },
	{ id = "rxp", nombre = "Sage's Mark", desc = "+6% XP gain per level", rareza = "Epic", maxNivel = 5,
		receta = { frost = 8, ember = 8 }, subir = { frost = 5, ember = 5 },
		aplicar = function(m, lvl) m.xpMult = (m.xpMult or 1) * (1 + 0.06 * lvl) end },
	{ id = "rtitan", nombre = "Titan Core", desc = "+4% damage & +5% max HP per level", rareza = "Legendary", maxNivel = 5,
		receta = { rare = 4 }, subir = { rare = 2 },
		aplicar = function(m, lvl) m.danoMult *= (1 + 0.04 * lvl); m.vidaMult *= (1 + 0.05 * lvl) end },
}

local porId = {}
for _, r in ipairs(CraftData.Reliquias) do porId[r.id] = r end
function CraftData.porId(id) return porId[id] end

-- Coste para subir del nivel 'lvl' al siguiente (escala: subir * lvl).
function CraftData.costeSubir(r, lvl)
	local out = {}
	for mat, n in pairs(r.subir) do out[mat] = n * lvl end
	return out
end

-- Info SEGURA para el cliente (sin funciones): textos + receta + coste del siguiente nivel + estado.
function CraftData.infoDe(reliquias, equipadas)
	local equipSet = {}
	for _, id in ipairs(equipadas or {}) do equipSet[id] = true end
	local out = {}
	for _, r in ipairs(CraftData.Reliquias) do
		local lvl = (reliquias and reliquias[r.id]) or 0
		out[#out + 1] = {
			id = r.id, nombre = r.nombre, desc = r.desc, rareza = r.rareza,
			level = lvl, maxNivel = r.maxNivel, equipada = equipSet[r.id] == true,
			receta = r.receta,
			costeSubir = (lvl > 0 and lvl < r.maxNivel) and CraftData.costeSubir(r, lvl) or nil,
		}
	end
	return out
end

-- CONSUMIBLES: boosts de UNA run. Craftas (gastas materiales) y eliges cuales LLEVAR; al empezar
-- la run se CONSUMEN (1) y aplican sus mods. aplicar(m) muta los mods (igual que reliquias).
CraftData.Consumibles = {
	{ id = "power",   nombre = "Berserker Brew", desc = "+25% damage this run",  receta = { ember = 8 },            aplicar = function(m) m.danoMult *= 1.25 end },
	{ id = "ward",    nombre = "Iron Tonic",     desc = "+25% max HP this run",   receta = { frost = 8 },            aplicar = function(m) m.vidaMult *= 1.25 end },
	{ id = "fortune", nombre = "Clover Vial",    desc = "+15 Luck this run",      receta = { woods = 8 },            aplicar = function(m) m.suerte += 15 end },
	{ id = "greed",   nombre = "Gold Draught",   desc = "+50% Cash this run",     receta = { woods = 6, frost = 6 }, aplicar = function(m) m.cashMult *= 1.5 end },
	-- Anadidos el 22-jul (mas crafteos): mas potis de 1 run para gastar materiales.
	{ id = "crit",    nombre = "Keen Elixir",     desc = "+15% crit chance this run",  receta = { ember = 8 },            aplicar = function(m) m.critChance = math.min(1, (m.critChance or 0) + 0.15) end },
	{ id = "rapid",   nombre = "Haste Draught",   desc = "+20% attack speed this run", receta = { woods = 8 },            aplicar = function(m) m.cadenciaMult *= 0.82 end },
	{ id = "leech",   nombre = "Vampire Vial",    desc = "+8% lifesteal this run",     receta = { ember = 6, frost = 6 }, aplicar = function(m) m.roboVida = (m.roboVida or 0) + 0.08 end },
	{ id = "guard",   nombre = "Titan Tonic",     desc = "-20% damage taken this run", receta = { frost = 6, woods = 6 }, aplicar = function(m) m.danoRecibidoMult *= 0.8 end },
	-- Potis de RELLENO baratas (usan Arcane Dust, que cae a montones): para gastar el material comun.
	{ id = "dvigor",  nombre = "Dust of Vigor",   desc = "+12% max HP this run",       receta = { dust = 12 },            aplicar = function(m) m.vidaMult *= 1.12 end },
	{ id = "dmight",  nombre = "Dust of Might",   desc = "+12% damage this run",       receta = { dust = 12 },            aplicar = function(m) m.danoMult *= 1.12 end },
}

local consPorId = {}
for _, c in ipairs(CraftData.Consumibles) do consPorId[c.id] = c end
function CraftData.consumiblePorId(id) return consPorId[id] end

-- Info SEGURA para el cliente (sin funciones): count que tienes + si lo llevas a la run.
function CraftData.consumiblesInfo(consumibles, usar)
	local usarSet = {}
	for _, id in ipairs(usar or {}) do usarSet[id] = true end
	local out = {}
	for _, c in ipairs(CraftData.Consumibles) do
		out[#out + 1] = {
			id = c.id, nombre = c.nombre, desc = c.desc, receta = c.receta,
			count = (consumibles and consumibles[c.id]) or 0, usar = usarSet[c.id] == true,
		}
	end
	return out
end

return CraftData
