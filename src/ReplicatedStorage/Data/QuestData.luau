-- QuestData (ModuleScript) - Fase D - misiones diarias + premios de la RACHA de login.
-- Pool de misiones (Bastian eligio: kills / oleada / actos). Cada dia se generan 3 (una por
-- entrada del pool) con un target al azar. La racha de login da Gems crecientes (ciclo de 7 dias).
local QuestData = {}

QuestData.RachaDias = 7
QuestData.RachaGems = { 10, 15, 20, 25, 30, 40, 100 } -- Gems por dia de racha (1..7; luego cicla)

-- Pool de misiones diarias. tipo = como se trackea; targets = posibles objetivos (random); gems = premio.
QuestData.Pool = {
	{ tipo = "kills", desc = "Kill %d enemies",        targets = { 100, 150, 200 }, gems = 15 },
	{ tipo = "wave",  desc = "Reach wave %d in a run", targets = { 8, 10, 12 },     gems = 20 },
	{ tipo = "acts",  desc = "Clear %d acts",          targets = { 1, 2 },          gems = 25 },
}

return QuestData
