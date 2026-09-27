-- EvolutionData (ModuleScript) · S2 - EVOLUCIONES de arma (el "momento clip").
-- Si el jugador (de cierta CLASE) tiene la RECETA de talentos, aparece una CARTA DORADA en el
-- "elige 1 de 3" que MUTA su arma a la version evolucionada (nuevo comportamiento + visual).
-- Receta = ids de cartas de PowerData. armaEvo = key en WeaponData del arma resultante.
local EvolutionData = {}

EvolutionData.Lista = {
	{
		id = "evoInferno",
		clase = "Mage",
		armaEvo = "Inferno Orb",
		nombre = "Inferno Orb",
		desc = "EVOLUTION - huge fireballs that EXPLODE and burn everything",
		receta = { "fuego", "tamano1" }, -- Incendiary Rounds + Giant Bolt
		color = Color3.fromRGB(255, 140, 40),
		regalo = true, -- REGALO: se desbloquea al pasar el Mundo 1 (no se compra en la Forge)
	},
	{
		id = "evoStorm",
		clase = "Archer",
		armaEvo = "Storm Bow",
		nombre = "Storm Bow",
		desc = "EVOLUTION - a storm of piercing arrows that CHILL everything",
		receta = { "balas2", "hielo" }, -- Twin Cast + Frostbite
		color = Color3.fromRGB(120, 220, 255),
		costeGems = 1000, recetaMat = { woods = 80, frost = 80, ember = 80, rare = 15 }, -- atajo pago (Gems) O craft gratis
	},
	{
		id = "evoDoom",
		clase = "Knight",
		armaEvo = "Doom Greatsword",
		nombre = "Doom Greatsword",
		desc = "EVOLUTION - a giant cleave that LIFESTEALS on every hit",
		receta = { "tamano1", "robo" }, -- Giant Bolt + Vampirism
		color = Color3.fromRGB(255, 80, 80),
		costeGems = 1000, recetaMat = { woods = 80, frost = 80, ember = 80, rare = 15 },
	},
	{
		id = "evoBlood",
		clase = "Bloodreaver",
		armaEvo = "Blood Harvest",
		nombre = "Blood Harvest",
		desc = "EVOLUTION - a monstrous cleave that DRAINS life from all it reaps",
		receta = { "robo", "fuego" }, -- Vampirism + Incendiary
		color = Color3.fromRGB(255, 40, 50),
		costeGems = 1000, recetaMat = { woods = 80, frost = 80, ember = 80, rare = 15 },
	},
	{
		id = "evoBlade",
		clase = "Trickster",
		armaEvo = "Bladestorm",
		nombre = "Bladestorm",
		desc = "EVOLUTION - three returning chakrams: a whirling storm of blades",
		receta = { "balas2", "tamano1" }, -- Twin Cast + Giant Bolt
		color = Color3.fromRGB(120, 255, 235),
		costeGems = 1000, recetaMat = { woods = 80, frost = 80, ember = 80, rare = 15 },
	},
}

local porId = {}
for _, e in ipairs(EvolutionData.Lista) do porId[e.id] = e end
function EvolutionData.porId(id) return porId[id] end
function EvolutionData.porClase(clase)
	for _, e in ipairs(EvolutionData.Lista) do if e.clase == clase then return e end end
end

-- ¿La clase + talentos tomados cumplen alguna receta NO usada aun? Devuelve la evo o nil.
-- Devuelve (evo, locked). locked=true = receta cumplida pero NO desbloqueada aun (gate meta-unlock) -> teaser/no jugable.
function EvolutionData.disponible(claseActual, poderesTomados, yaEvolucionado, desbloqueadas)
	if yaEvolucionado then return nil end
	local tiene = {}
	for _, id in ipairs(poderesTomados or {}) do tiene[id] = true end
	for _, e in ipairs(EvolutionData.Lista) do
		if e.clase == claseActual then
			local completa = true
			for _, req in ipairs(e.receta) do
				if not tiene[req] then completa = false; break end
			end
			if completa then
				local desbloqueada = desbloqueadas and desbloqueadas[e.id]
				return e, not desbloqueada
			end
		end
	end
	return nil
end

return EvolutionData
