-- RunUpgradeData (ModuleScript) · FASE 6 - mejoras de RUN (temporales), se compran con COINS.
-- Coins = moneda POR-PARTIDA (se gana matando, se reinicia cada run). Estas mejoras se aplican
-- a la build de ESTA partida (RunState) y desaparecen al empezar otra. Baratas y apilables.
-- El cliente LEE textos/coste; SOLO el servidor llama a aplicar(). aplicar(m) = un escalon.
local RunUpgradeData = {}

RunUpgradeData.Lista = {
	{ id = "rdano",  nombre = "Sharpen",   desc = "+5% damage",      maxLevel = 8, costBase = 40, costMult = 1.55,
		aplicar = function(m) m.danoMult *= 1.05 end },
	{ id = "rcad",   nombre = "Overclock", desc = "+4% fire rate",   maxLevel = 8, costBase = 40, costMult = 1.55,
		aplicar = function(m) m.cadenciaMult *= 0.96 end },
	{ id = "rvida",  nombre = "Vigor",     desc = "+8% max health",  maxLevel = 8, costBase = 50, costMult = 1.55,
		aplicar = function(m) m.vidaMult *= 1.08 end },
	{ id = "rcrit",  nombre = "Keen Eye",  desc = "+3% crit chance", maxLevel = 8, costBase = 60, costMult = 1.6,
		aplicar = function(m) m.critChance = math.min(1, m.critChance + 0.03) end },
	{ id = "rvelo",  nombre = "Sprint",    desc = "+8% move speed",  maxLevel = 8, costBase = 50, costMult = 1.6,
		aplicar = function(m) m.velocidadMult *= 1.08 end },
	{ id = "rrobo",  nombre = "Leech",     desc = "+2% lifesteal",   maxLevel = 6, costBase = 70, costMult = 1.6,
		aplicar = function(m) m.roboVida += 0.02 end },
}

local porId = {}
for _, u in ipairs(RunUpgradeData.Lista) do porId[u.id] = u end
function RunUpgradeData.porId(id) return porId[id] end

-- Redondea a numeros "bonitos" segun magnitud (precios mas limpios en la tienda).
local function redondear(n)
	if n < 100 then return math.floor(n / 5 + 0.5) * 5
	elseif n < 1000 then return math.floor(n / 25 + 0.5) * 25
	else return math.floor(n / 100 + 0.5) * 100 end
end

-- Coste para subir del nivel actual 'lvl' al siguiente (en Coins).
function RunUpgradeData.costDe(up, lvl)
	return redondear(up.costBase * (up.costMult ^ lvl))
end

-- Info SEGURA para el cliente (textos + coste del siguiente nivel).
function RunUpgradeData.infoDe(niveles)
	local out = {}
	for _, u in ipairs(RunUpgradeData.Lista) do
		local lvl = (niveles and niveles[u.id]) or 0
		out[#out + 1] = {
			id = u.id, nombre = u.nombre, desc = u.desc,
			level = lvl, maxLevel = u.maxLevel,
			cost = (lvl < u.maxLevel) and RunUpgradeData.costDe(u, lvl) or nil,
		}
	end
	return out
end

return RunUpgradeData
