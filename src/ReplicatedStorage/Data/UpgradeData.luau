-- UpgradeData (ModuleScript) · FASE 6 - mejoras PERMANENTES (meta) que compras con Cash.
-- Suben de nivel y se aplican como BASE de la build al empezar cada partida (sobre RunState).
-- El cliente LEE textos/coste; SOLO el servidor llama a aplicar(). Anadir mejora = anadir fila.
--   maxLevel  niveles maximos
--   costBase / costMult  coste para subir del nivel L a L+1 = floor(costBase * costMult^L)
--   aplicar(m, lvl)  muta los modificadores de la build segun el nivel
local UpgradeData = {}

UpgradeData.Lista = {
	{ id = "dano",      nombre = "Damage Up",    desc = "+8% damage per level",      maxLevel = 8, costBase = 250, costMult = 1.5,
		aplicar = function(m, lvl) m.danoMult *= (1 + 0.08 * lvl) end },
	{ id = "vida",      nombre = "Health Up",    desc = "+12% max health per level", maxLevel = 8, costBase = 250, costMult = 1.5,
		aplicar = function(m, lvl) m.vidaMult *= (1 + 0.12 * lvl) end },
	{ id = "velocidad", nombre = "Swiftness",    desc = "+4% move speed per level",  maxLevel = 8, costBase = 200, costMult = 1.5,
		aplicar = function(m, lvl) m.velocidadMult *= (1 + 0.04 * lvl) end },
	-- id "recarga" heredado: la recarga era INUTIL en auto-attack survivors; ahora da CRIT.
	{ id = "recarga",   nombre = "Sharpshooter", desc = "+2% crit chance per level", maxLevel = 8, costBase = 250, costMult = 1.5,
		aplicar = function(m, lvl) m.critChance = math.min(1, m.critChance + 0.02 * lvl) end },
	{ id = "suerte",    nombre = "Fortune",      desc = "+3 Luck per level",         maxLevel = 8, costBase = 300, costMult = 1.55,
		aplicar = function(m, lvl) m.suerte += 3 * lvl end },
	{ id = "cash",      nombre = "Cash Boost",   desc = "+8% Cash earned per level", maxLevel = 8, costBase = 300, costMult = 1.55,
		aplicar = function(m, lvl) m.cashMult *= (1 + 0.08 * lvl) end },
}

local porId = {}
for _, u in ipairs(UpgradeData.Lista) do porId[u.id] = u end
function UpgradeData.porId(id) return porId[id] end

-- Redondea a numeros "bonitos" segun magnitud (precios mas limpios en la tienda).
local function redondear(n)
	if n < 100 then return math.floor(n / 5 + 0.5) * 5
	elseif n < 1000 then return math.floor(n / 25 + 0.5) * 25
	elseif n < 5000 then return math.floor(n / 100 + 0.5) * 100
	else return math.floor(n / 500 + 0.5) * 500 end
end

-- Coste para subir del nivel actual 'lvl' al siguiente.
function UpgradeData.costDe(up, lvl)
	return redondear(up.costBase * (up.costMult ^ lvl))
end

-- Info SEGURA para el cliente (sin funciones): textos + coste del siguiente nivel.
function UpgradeData.infoDe(niveles)
	local out = {}
	for _, u in ipairs(UpgradeData.Lista) do
		local lvl = (niveles and niveles[u.id]) or 0
		out[#out + 1] = {
			id = u.id, nombre = u.nombre, desc = u.desc,
			level = lvl, maxLevel = u.maxLevel,
			cost = (lvl < u.maxLevel) and UpgradeData.costDe(u, lvl) or nil,
		}
	end
	return out
end

return UpgradeData
