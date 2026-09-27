-- ClassData (ModuleScript) · S2 - las CLASES jugables. Cada clase = un arma INICIAL (de WeaponData)
-- + una PASIVA que escala por NIVEL (los duplicados del gacha suben el nivel de la clase) + una
-- RAREZA (para el gacha). Player-facing en INGLES. Anadir una clase = anadir una fila aqui.
local ClassData = {}

ClassData.PorDefecto = "Mage" -- clase de arranque (hasta que el gacha de otra)
ClassData.NivelMax = 3        -- tope de nivel de pasiva (dupes del gacha)

ClassData.Lista = {
	{
		id = "Mage", nombre = "Mage", arma = "Arcane Wand", rareza = "Common",
		desc = "Arcane caster. Hits hard at range.",
		pasivaDesc = "Arcane power: +12% damage & +6% projectile size / level",
		-- pasiva(mods, nivel): el nivel de CLASE del Mago SOLO daba tamano de proyectil -> 0 dano, 0 vida:
		-- un Mago lvl3 sobrevivia EXACTAMENTE igual que uno lvl1 (lo detecto el audit; es la clase que "siempre
		-- muere"). Ahora da DANO real por nivel (+12/24/36%) + algo de tamano, a la altura de las otras clases
		-- (Knight da vida, Bloodreaver da dano+robo, Trickster crit, Archer cadencia).
		pasiva = function(m, nivel) m.danoMult *= (1 + 0.12 * nivel); m.tamanoMult *= (1 + 0.06 * nivel) end,
		color = Color3.fromRGB(170, 90, 255),
	},
	{
		id = "Archer", nombre = "Archer", arma = "Hunter Bow", rareza = "Rare",
		desc = "Rapid piercing arrows.",
		pasivaDesc = "Faster attacks (+6% fire rate / level)",
		-- +8/16/24% cadencia por nivel
		pasiva = function(m, nivel) m.cadenciaMult *= (1 - 0.06 * nivel) end,
		color = Color3.fromRGB(120, 230, 120),
	},
	{
		id = "Knight", nombre = "Knight", arma = "War Blade", rareza = "Epic", velMult = 0.8, -- LENTO/HEAVY de verdad (~12.8): no huye, FACETANKEA y siega. Supervivencia = tankiness de base (abajo) + Dash + cleave, no velocidad.
		desc = "Melee bruiser. Cleaves all nearby foes.",
		pasivaDesc = "Heavy plating: +30% HP & -15% dmg taken BASE (+12% HP, -3% dmg / level)",
		-- BASE +30% vida y -15% dano recibido (para FACETANKEAR siendo lento) + escala por nivel
		pasiva = function(m, nivel) m.vidaMult *= (1.30 + 0.12 * nivel); m.danoRecibidoMult *= (0.85 - 0.03 * nivel) end,
		color = Color3.fromRGB(220, 235, 255),
	},
	{
		id = "Bloodreaver", nombre = "Bloodreaver", arma = "Reaver Scythe", rareza = "Legendary", peso = 1, -- peso DENTRO de Legendary (sube/baja para hacerla mas/menos comun que otras legendarias)
		desc = "Blood-crazed reaper. Melee glass-cannon: hits hard + lifesteals, but fragile.",
		pasivaDesc = "Bloodthirst: +15% dmg & +10% lifesteal / level, but -20% HP",
		-- glass cannon: mucho dano + robo de vida (sobrevives pegando), pero fragil de base
		pasiva = function(m, nivel) m.danoMult *= (1 + 0.15 * nivel); m.roboVida = (m.roboVida or 0) + 0.10 * nivel; m.vidaMult *= 0.8 end,
		color = Color3.fromRGB(180, 30, 45),
	},
	{
		id = "Trickster", nombre = "Trickster", arma = "Chakram", rareza = "Legendary", peso = 1,
		desc = "Boomerang chakrams that strike twice. A crit-fishing gambler.",
		pasivaDesc = "Sleight of hand: +10% crit chance & +0.2 crit dmg / level",
		-- identidad CRIT: sube prob. de critico y el multiplicador (rafaga/burst)
		pasiva = function(m, nivel) m.critChance = (m.critChance or 0) + 0.10 * nivel; m.critMult = (m.critMult or 2) + 0.20 * nivel end,
		color = Color3.fromRGB(80, 240, 220),
	},
}

local porId = {}
for _, c in ipairs(ClassData.Lista) do porId[c.id] = c end
function ClassData.porId(id) return porId[id] end

-- Pesos de rareza para el GACHA (prob. relativa de salir en un spin).
ClassData.PesoRareza = { Common = 60, Rare = 28, Epic = 10, Legendary = 2 }

-- Elige una clase al azar para el gacha (2 PASOS): 1) RAREZA ponderada por PesoRareza,
-- 2) CLASE dentro de esa rareza ponderada por su 'peso' (default 1). Asi anadir clases a una
-- rareza NO infla la prob. de esa rareza; solo reparte DENTRO. Devuelve el id.
function ClassData.elegirAleatoria()
	local rarPresente, clasesPorRar = {}, {}
	for _, c in ipairs(ClassData.Lista) do
		if not clasesPorRar[c.rareza] then clasesPorRar[c.rareza] = {}; rarPresente[#rarPresente + 1] = c.rareza end
		table.insert(clasesPorRar[c.rareza], c)
	end
	local total = 0
	for _, rar in ipairs(rarPresente) do total += (ClassData.PesoRareza[rar] or 1) end
	local r = math.random() * total
	local elegida
	for _, rar in ipairs(rarPresente) do
		r -= (ClassData.PesoRareza[rar] or 1)
		if r <= 0 then elegida = rar; break end
	end
	elegida = elegida or rarPresente[1]
	local grupo = clasesPorRar[elegida]
	local tot2 = 0
	for _, c in ipairs(grupo) do tot2 += (c.peso or 1) end
	local r2 = math.random() * tot2
	for _, c in ipairs(grupo) do
		r2 -= (c.peso or 1)
		if r2 <= 0 then return c.id end
	end
	return grupo[1].id
end

-- Probabilidad TOTAL (0..1) de cada clase en un spin = (peso rareza / suma rarezas) * (peso clase / suma pesos de SU rareza).
-- Para mostrar los % en el menu del gacha. Devuelve { id = fraccion }.
function ClassData.probabilidades()
	local pesoRar, sumaClase = {}, {}
	for _, c in ipairs(ClassData.Lista) do
		pesoRar[c.rareza] = ClassData.PesoRareza[c.rareza] or 1
		sumaClase[c.rareza] = (sumaClase[c.rareza] or 0) + (c.peso or 1)
	end
	local totalRar = 0
	for _, w in pairs(pesoRar) do totalRar += w end
	local out = {}
	for _, c in ipairs(ClassData.Lista) do
		out[c.id] = (pesoRar[c.rareza] / totalRar) * ((c.peso or 1) / sumaClase[c.rareza])
	end
	return out
end

-- Shards necesarios para subir del nivel dado al siguiente (index = nivel actual). nil = tope.
ClassData.ShardsParaSubir = { 6, 14 } -- nivel 1->2 cuesta 6 shards, 2->3 cuesta 14 (mas grind; antes 3/5 = max en ~15 min). TUNABLE.

-- Info SEGURA para el cliente (sin funciones): para el gacha / selector de clase.
function ClassData.infoLista()
	local out = {}
	for _, c in ipairs(ClassData.Lista) do
		out[#out + 1] = { id = c.id, nombre = c.nombre, arma = c.arma, rareza = c.rareza, desc = c.desc, pasivaDesc = c.pasivaDesc, color = c.color }
	end
	return out
end

return ClassData
