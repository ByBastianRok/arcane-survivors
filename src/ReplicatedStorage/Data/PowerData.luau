-- PowerData (ModuleScript) · FASE 5A / S2 - cartas de poder del roguelite ("elige 1 de 3").
-- Cada carta = id, textos UI, categoria, rareza y aplicar(m) que MUTA los mods (RunState).
-- DISENO (S2): SOLO los stats BASICOS (dano, cadencia, crit, vida, velocidad) tienen 3 TIERS
-- (I/II/III a Common/Rare/Epic) -> la RAREZA = la potencia. Los talentos ESPECIFICOS (mecanicas,
-- stats de nicho) son cartas SUELTAS, cada una unica en su efecto.
local PowerData = {}

-- Peso (probabilidad relativa) y color de borde por rareza.
PowerData.Rarezas = {
	Common    = { peso = 60, color = Color3.fromRGB(180, 180, 180) },
	Rare      = { peso = 28, color = Color3.fromRGB(80, 160, 255) },
	Epic      = { peso = 10, color = Color3.fromRGB(190, 90, 255) },
	Legendary = { peso = 2,  color = Color3.fromRGB(255, 180, 40) },
}

PowerData.Cartas = {}

-- ===== Stats BASICOS con 3 TIERS (I/II/III). Solo los mas basicos; cada tier mas raro y fuerte. =====
local TIERS = { { "I", "Common" }, { "II", "Rare" }, { "III", "Epic" } }
local BASICOS = {
	{ id = "dano", nombre = "Power",     cat = "Offensive", txt = "+%d%% damage",      vals = { 0.15, 0.20, 0.30 }, fn = function(m, v) m.danoMult *= (1 + v) end },
	{ id = "cad",  nombre = "Haste",     cat = "Offensive", txt = "+%d%% fire rate",   vals = { 0.10, 0.15, 0.22 }, fn = function(m, v) m.cadenciaMult *= (1 - v) end },
	{ id = "crC",  nombre = "Precision", cat = "Offensive", txt = "+%d%% crit chance", vals = { 0.06, 0.10, 0.15 }, fn = function(m, v) m.critChance = math.min(1, m.critChance + v) end },
	{ id = "crD",  nombre = "Brutality", cat = "Offensive", txt = "+%d%% crit damage", vals = { 0.25, 0.40, 0.60 }, fn = function(m, v) m.critMult += v end },
	{ id = "vida", nombre = "Vitality",  cat = "Defensive", txt = "+%d%% max health",  vals = { 0.15, 0.22, 0.35 }, fn = function(m, v) m.vidaMult *= (1 + v) end },
	{ id = "velo", nombre = "Swiftness", cat = "Utility",   txt = "+%d%% move speed",  vals = { 0.05, 0.08, 0.12 }, fn = function(m, v) m.velocidadMult *= (1 + v) end },
}
for _, b in ipairs(BASICOS) do
	for i, t in ipairs(TIERS) do
		local v = b.vals[i]
		table.insert(PowerData.Cartas, {
			id = b.id .. i, nombre = b.nombre .. " " .. t[1], categoria = b.cat, rareza = t[2],
			desc = b.txt:format(math.round(v * 100)),
			aplicar = function(m) b.fn(m, v) end,
		})
	end
end

-- ===== Talentos ESPECIFICOS: cartas SUELTAS (mecanicas + stats de nicho). Cada una unica en su efecto. =====
local ESPECIALES = {
	-- Mecanicas (cambian COMO disparas)
	{ id = "balas2",  nombre = "Twin Cast",       desc = "+1 projectile per shot",                  categoria = "Offensive", rareza = "Epic",      aplicar = function(m) m.balasExtra += 1 end },
	{ id = "balas3",  nombre = "Triple Cast",     desc = "+2 projectiles per shot",                 categoria = "Offensive", rareza = "Legendary", aplicar = function(m) m.balasExtra += 2 end },
	{ id = "tamano1", nombre = "Giant Bolt",      desc = "+40% bigger projectiles (more area)",     categoria = "Offensive", rareza = "Rare",      aplicar = function(m) m.tamanoMult *= 1.40 end },
	{ id = "spread1", nombre = "Scattershot",     desc = "Projectiles spread out (great with multishot)", categoria = "Offensive", rareza = "Rare", aplicar = function(m) m.spreadExtra += 8 end },
	-- (V) carta "Piercing Rounds" QUITADA: perforar es un TRAIT del ARQUERO, no un talento universal.
	-- El Hunter Bow y el Storm Bow ya llevan Perforante=true en WeaponData; ninguna otra clase deberia perforar.
	{ id = "fuego",   nombre = "Incendiary Rounds", desc = "Your projectiles set enemies on fire",  categoria = "Offensive", rareza = "Epic", unica = true, elemento = true, aplicar = function(m) m.elementosExtra["Fuego"] = true end },
	{ id = "veneno",  nombre = "Toxic Rounds",    desc = "Your projectiles poison enemies",         categoria = "Offensive", rareza = "Epic", unica = true, elemento = true, aplicar = function(m) m.elementosExtra["Veneno"] = true end },
	{ id = "hielo",   nombre = "Frostbite",       desc = "Your projectiles chill & slow enemies",   categoria = "Offensive", rareza = "Epic", unica = true, elemento = true, aplicar = function(m) m.elementosExtra["Hielo"] = true end },
	{ id = "berserk", nombre = "Berserker",       desc = "+50% damage and +20% fire rate",          categoria = "Offensive", rareza = "Legendary", aplicar = function(m) m.danoMult *= 1.5; m.cadenciaMult *= 0.8 end },
	{ id = "glass",   nombre = "Glass Cannon",    desc = "+60% damage, but -20% max health",        categoria = "Offensive", rareza = "Legendary", unica = true, aplicar = function(m) m.danoMult *= 1.6; m.vidaMult *= 0.8 end },
	-- Stats de nicho (defensivos / utilidad)
	{ id = "regen",     nombre = "Regeneration",  desc = "Regenerate 1% of max HP per second",      categoria = "Defensive", rareza = "Rare",      aplicar = function(m) m.regen += 0.01 end },
	{ id = "esquiva1",  nombre = "Evasion",       desc = "+12% chance to dodge damage",             categoria = "Defensive", rareza = "Rare",      aplicar = function(m) m.esquivar = math.min(0.75, m.esquivar + 0.12) end },
	{ id = "armor",     nombre = "Thick Skin",    desc = "Take 22% less damage",                    categoria = "Defensive", rareza = "Epic",      aplicar = function(m) m.danoRecibidoMult *= 0.78 end },
	{ id = "robo",      nombre = "Vampirism",     desc = "Heal 4% of damage dealt (max 4% of your HP per hit)", categoria = "Defensive", rareza = "Epic",      aplicar = function(m) m.roboVida += 0.04 end },
	{ id = "fortaleza", nombre = "Stoneskin",     desc = "+30% max health and -10% damage taken",   categoria = "Defensive", rareza = "Epic",      aplicar = function(m) m.vidaMult *= 1.3; m.danoRecibidoMult *= 0.9 end },
	{ id = "xp1",       nombre = "Scholar",       desc = "+30% XP gained",                          categoria = "Utility",   rareza = "Common",    aplicar = function(m) m.xpMult *= 1.30 end },
	{ id = "cash1",     nombre = "Greed",         desc = "+30% Cash earned",                        categoria = "Utility",   rareza = "Rare",      aplicar = function(m) m.cashMult *= 1.3 end },
	{ id = "luck1",     nombre = "Lucky Charm",   desc = "+5 Luck: more & better drops and cards",  categoria = "Utility",   rareza = "Rare",      aplicar = function(m) m.suerte += 5 end },
	{ id = "luck2",     nombre = "Treasure Hunter", desc = "+10 Luck",                              categoria = "Utility",   rareza = "Epic",      aplicar = function(m) m.suerte += 10 end },
	-- Talentos NUEVOS (5 jul, con Bastian)
	{ id = "range1",    nombre = "Longshot",      desc = "+25% auto-attack range",                  categoria = "Offensive", rareza = "Rare",      aplicar = function(m) m.rangoMult *= 1.25 end },
	{ id = "exec",      nombre = "Execute",       desc = "+50% damage to enemies below 25% HP",     categoria = "Offensive", rareza = "Legendary", unica = true, aplicar = function(m) m.ejecutarUmbral = 0.25; m.ejecutarBonus = 1.5 end },
	{ id = "adren",     nombre = "Adrenaline",    desc = "-20% ability cooldown",                   categoria = "Utility",   rareza = "Epic",      aplicar = function(m) m.cdMult *= 0.8 end },
	-- Legendarias NUEVAS (playtest Bastian): ejes que aun no tenian Legendary (crit / tanque / movilidad / cadencia+multi). Todas unica = no apilan.
	{ id = "deadeye",   nombre = "Deadeye",       desc = "+30% crit chance and +75% crit damage",   categoria = "Offensive", rareza = "Legendary", unica = true, aplicar = function(m) m.critChance = math.min(1, m.critChance + 0.30); m.critMult += 0.75 end },
	{ id = "jugger",    nombre = "Juggernaut",    desc = "+50% max health and -30% damage taken",   categoria = "Defensive", rareza = "Legendary", unica = true, aplicar = function(m) m.vidaMult *= 1.5; m.danoRecibidoMult *= 0.7 end },
	{ id = "momentum",  nombre = "Momentum",      desc = "+30% move speed and +25% damage",         categoria = "Utility",   rareza = "Legendary", unica = true, aplicar = function(m) m.velocidadMult *= 1.3; m.danoMult *= 1.25 end },
	{ id = "onslaught", nombre = "Onslaught",     desc = "+1 projectile and +30% fire rate",        categoria = "Offensive", rareza = "Legendary", unica = true, aplicar = function(m) m.balasExtra += 1; m.cadenciaMult *= 0.7 end },
}
for _, c in ipairs(ESPECIALES) do
	table.insert(PowerData.Cartas, c)
end

-- Indice id -> carta.
local porId = {}
for _, c in ipairs(PowerData.Cartas) do porId[c.id] = c end
function PowerData.porId(id) return porId[id] end

-- Color del borde segun rareza (con respaldo).
function PowerData.colorRareza(rareza)
	local r = PowerData.Rarezas[rareza]
	return r and r.color or Color3.fromRGB(200, 200, 200)
end

local function pesoDe(carta, suerte)
	local r = PowerData.Rarezas[carta.rareza]
	local base = (r and r.peso) or 1
	-- la SUERTE favorece las cartas NO comunes (mejores builds)
	if carta.rareza ~= "Common" then
		-- cap de suerte efectiva: evita la bola de nieve (luck que genera mas luck). Max x1.6
		base = base * (1 + math.min(suerte or 0, 30) * 0.02)
	end
	return base
end

-- Elige n cartas DISTINTAS, ponderando por rareza, saltando las "unica" ya tomadas.
function PowerData.elegir(n, mods, arma)
	local tomadas = {}
	if mods and mods.poderes then
		for _, id in ipairs(mods.poderes) do tomadas[id] = true end
	end
	-- Filtro por ARMA: no ofrecer talentos que no le sirven a tu arma.
	local esMelee = arma and arma.TipoDisparo == "Melee"
	local balasExtra = (mods and mods.balasExtra) or 0
	local elemArma = arma and arma.Elemento -- no ofrecer la carta del elemento que el arma YA aplica (carta Epic muerta)
	local ELEM_ID = { fuego = "Fuego", veneno = "Veneno", hielo = "Hielo" }
	local pool = {}
	for _, c in ipairs(PowerData.Cartas) do
		local salta = c.unica and tomadas[c.id]
		if c.id == "spread1" and (esMelee or balasExtra == 0) then salta = true end -- Scattershot: solo util con multishot (proyectil)
		if ELEM_ID[c.id] and ELEM_ID[c.id] == elemArma then salta = true end -- carta de elemento REDUNDANTE con el del arma (Inferno/Shotgun=Fuego, Storm Bow/Sniper=Hielo)
		if not salta then pool[#pool + 1] = c end
	end
	local elegidas = {}
	local suerte = (mods and mods.suerte) or 0
	-- Elementos: se ACUMULAN (aplican todos), pero cuantos MAS tengas, MAS raro que salga otro (peso x1 -> x0.25 -> x0.1 ~ 10%/2.5%/1%).
	local nElem = 0
	for _, id in ipairs((mods and mods.poderes) or {}) do
		local c = porId[id]; if c and c.elemento then nElem += 1 end
	end
	local PENAL_ELEM = { [0] = 1, [1] = 0.25, [2] = 0.1 }
	-- X (fix): cuenta cuantas veces has tomado cada carta esta run (mods.poderes es la lista CON repeticiones)
	local veces = {}
	for _, id in ipairs((mods and mods.poderes) or {}) do veces[id] = (veces[id] or 0) + 1 end
	local function pesoFinal(c)
		local p = pesoDe(c, suerte)
		if c.elemento then p = p * (PENAL_ELEM[math.min(nElem, 2)] or 0.1) end
		-- las REPETIBLES salen cada vez MENOS (caida cuadratica): evita el Haste x14 -> spam de 8 proyectiles/s.
		-- 1 vez -> x0.71, 2 -> x0.38, 3 -> x0.22, 4 -> x0.14, 6 -> x0.06, 8 -> x0.04 (rara vez, no imposible)
		local rep = veces[c.id]
		if rep and rep > 0 then p = p / (1 + rep * rep * 0.4) end
		return p
	end
	n = math.min(n, #pool)
	for _ = 1, n do
		local total = 0
		for _, c in ipairs(pool) do total += pesoFinal(c) end
		local r = math.random() * total
		local idx = 1
		for i, c in ipairs(pool) do
			r -= pesoFinal(c)
			if r <= 0 then idx = i; break end
		end
		elegidas[#elegidas + 1] = pool[idx].id
		table.remove(pool, idx)
	end
	return elegidas
end

-- Info SEGURA para el cliente (sin funciones): textos + color de rareza.
function PowerData.infoDe(ids)
	local out = {}
	for _, id in ipairs(ids) do
		local c = porId[id]
		if c then
			out[#out + 1] = {
				id = c.id, nombre = c.nombre, desc = c.desc,
				categoria = c.categoria, rareza = c.rareza,
				color = PowerData.colorRareza(c.rareza),
			}
		end
	end
	return out
end

return PowerData
