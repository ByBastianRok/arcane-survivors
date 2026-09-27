-- WaveData (ModuleScript) - composición FIJA de cada oleada.
-- Cada oleada es siempre igual (determinista). Los tipos nuevos se "desbloquean" al
-- introducirse en una oleada. Más allá de la tabla, se genera por escalado (infinito).
-- Cada grupo: { tipo, cantidad, elite? } (elite = afijo opcional de EliteData).
local WaveData = {}

-- Survivors: hordas crecientes. Arranque SUAVE (chaser-heavy, lentos -> esquivables); los Swarmers
-- (rapidos) y los elites entran mas tarde. Se limpia la oleada y viene otra mayor.
WaveData.Oleadas = {
	-- Cantidades subidas ~40% el 22-jul (Bastian: "aumentaria la cantidad y reduciria la vida" = mow-down tipo
	-- Vampire Survivors). Con la vida baja mueren al instante, asi que NO se acumulan (kill-rate alto).
	[1] = { { tipo = "Chaser", cantidad = 8 }, { tipo = "Swarmer", cantidad = 4 } },
	[2] = { { tipo = "Chaser", cantidad = 11 }, { tipo = "Swarmer", cantidad = 6 } },
	[3] = { { tipo = "Chaser", cantidad = 13 }, { tipo = "Swarmer", cantidad = 8 }, { tipo = "Ranged", cantidad = 2 } },
	[4] = { { tipo = "Chaser", cantidad = 14 }, { tipo = "Swarmer", cantidad = 11 }, { tipo = "Tank", cantidad = 1 }, { tipo = "Ranged", cantidad = 2 }, { tipo = "Charger", cantidad = 1 } },
	[5] = { { tipo = "Chaser", cantidad = 16 }, { tipo = "Swarmer", cantidad = 14 }, { tipo = "Exploder", cantidad = 3 }, { tipo = "Ranged", cantidad = 3 }, { tipo = "Splitter", cantidad = 2 }, { tipo = "Healer", cantidad = 1 } },
	[6] = { { tipo = "Chaser", cantidad = 18 }, { tipo = "Swarmer", cantidad = 18 }, { tipo = "Tank", cantidad = 2 }, { tipo = "Exploder", cantidad = 3 }, { tipo = "Ranged", cantidad = 3 }, { tipo = "Swarmer", cantidad = 5, elite = "Veloz" }, { tipo = "Splitter", cantidad = 2 } },
	[7] = { { tipo = "Chaser", cantidad = 20 }, { tipo = "Swarmer", cantidad = 18 }, { tipo = "Tank", cantidad = 3 }, { tipo = "Exploder", cantidad = 4 }, { tipo = "Ranged", cantidad = 4 }, { tipo = "Tank", cantidad = 1, elite = "Gigante" }, { tipo = "Charger", cantidad = 2 }, { tipo = "Splitter", cantidad = 2 } },
	[8] = { { tipo = "Chaser", cantidad = 18 }, { tipo = "Swarmer", cantidad = 20 }, { tipo = "Tank", cantidad = 4 }, { tipo = "Exploder", cantidad = 5 }, { tipo = "Ranged", cantidad = 4 }, { tipo = "Chaser", cantidad = 4, elite = "Regenerante" }, { tipo = "Tank", cantidad = 1, elite = "Acorazado" }, { tipo = "Healer", cantidad = 2 }, { tipo = "Charger", cantidad = 2 }, { tipo = "Splitter", cantidad = 3 }, { tipo = "Summoner", cantidad = 1 } },
}

-- Escalado procedural para oleadas más allá de la tabla (sigue infinito).
local function generar(oleada)
	local extra = oleada - 8
	return {
		{ tipo = "Chaser", cantidad = 16 + math.floor(extra * 2) },
		{ tipo = "Swarmer", cantidad = 18 + math.floor(extra * 2) },
		{ tipo = "Tank", cantidad = 4 + math.floor(extra / 2) },
		{ tipo = "Exploder", cantidad = 5 + math.floor(extra / 2) },
		{ tipo = "Ranged", cantidad = 4 + math.floor(extra / 2) },
		{ tipo = "Tank", cantidad = 1 + math.floor(extra / 3), elite = "Gigante" },
		{ tipo = "Swarmer", cantidad = 5 + math.floor(extra / 2), elite = "Veloz" },
		{ tipo = "Splitter", cantidad = 2 + math.floor(extra / 2) },
		{ tipo = "Charger", cantidad = 1 + math.floor(extra / 3) },
		{ tipo = "Healer", cantidad = 1 + math.floor(extra / 4) },
		{ tipo = "Summoner", cantidad = 1 + math.floor(extra / 5) },
		{ tipo = "Chaser", cantidad = 1 + math.floor(extra / 4), elite = "Vampiro" },
		{ tipo = "Tank", cantidad = 1 + math.floor(extra / 6), elite = "Explosivo" },
		{ tipo = "Chaser", cantidad = 1 + math.floor(extra / 4), elite = "Frenetico" },
	}
end

-- Composición de una oleada (fija si está en la tabla; procedural si no).
function WaveData.get(oleada)
	return WaveData.Oleadas[oleada] or generar(oleada)
end

return WaveData
