-- Leaderboard (ModuleScript del SERVIDOR) · FASE 7 - ranking por mejor SCORE.
-- Usa OrderedDataStore: uno ALL-TIME y uno SEMANAL (clave por numero de semana, asi 'resetea'
-- solo cada semana sin borrar nada). El reparto de PREMIOS de temporada se hara en LiveOps.
local DataStoreService = game:GetService("DataStoreService")

local Leaderboard = {}

local allTime = DataStoreService:GetOrderedDataStore("LB_Score_AllTime_v1")

-- BOARDS MULTIPLES (22-jul, Bastian: varias tablas en semicirculo). Cada uno su OrderedDataStore, valores ENTEROS.
-- score/wave = RECORDS (UpdateAsync max). gems/horas/runs = valor ACTUAL/acumulado (UpdateAsync fija).
local boards = {
	score = allTime,                                                 -- record de score all-time (ya existia)
	wave  = DataStoreService:GetOrderedDataStore("LB_Wave_v1"),      -- record de mejor oleada (Endless)
	gems  = DataStoreService:GetOrderedDataStore("LB_Gems_v1"),      -- balance actual de Gems (mas ricos)
	horas = DataStoreService:GetOrderedDataStore("LB_Mins_v1"),      -- minutos jugados (se muestran como horas)
	runs  = DataStoreService:GetOrderedDataStore("LB_Runs_v1"),      -- partidas jugadas
}
Leaderboard.BOARDS = { "wave", "gems", "score", "horas", "runs" } -- 'score' en el centro (grande) en el tablero

local function semanaActual()
	return math.floor(os.time() / (7 * 24 * 3600)) -- semanas desde epoch
end
function Leaderboard.semana() return semanaActual() end

local function weeklyStore()
	return DataStoreService:GetOrderedDataStore("LB_Score_Week_" .. semanaActual())
end

-- Sube el score a los rankings all-time Y semanal (UpdateAsync(max) = mejor de cada periodo). El caller
-- debe llamar SIEMPRE (no solo en record all-time): si no, el store semanal se queda vacio al resetear.
function Leaderboard.registrar(userId, score)
	if type(score) ~= "number" or score <= 0 then return end
	local k = tostring(userId)
	-- UpdateAsync(max): un score MENOR nunca pisa uno mayor (evita regresion del ranking).
	pcall(function() allTime:UpdateAsync(k, function(old) return math.max(old or 0, score) end) end)
	pcall(function() weeklyStore():UpdateAsync(k, function(old) return math.max(old or 0, score) end) end)
end

-- Top N (descendente). weekly=true para el ranking semanal. Devuelve { {userId, score}, ... }.
function Leaderboard.top(n, weekly)
	local s = weekly and weeklyStore() or allTime
	local ok, pages = pcall(function()
		return s:GetSortedAsync(false, math.clamp(n or 10, 1, 100))
	end)
	if not ok then return {} end
	local out = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		out[#out + 1] = { userId = tonumber(entry.key), score = entry.value }
	end
	return out
end

-- Rango (posicion 1-based) del jugador en el ranking (all-time o semanal). nil = fuera del top ~200.
-- DataStore-pesado: el caller deberia cachearlo (no llamar a cada rato).
function Leaderboard.rankDe(userId, weekly)
	local s = weekly and weeklyStore() or allTime
	local k = tostring(userId)
	local ok, pages = pcall(function() return s:GetSortedAsync(false, 100) end)
	if not ok then return nil end
	local rank = 0
	for _ = 1, 2 do -- escanea hasta 200 (2 paginas)
		for _, entry in ipairs(pages:GetCurrentPage()) do
			rank += 1
			if entry.key == k then return rank end
		end
		if pages.IsFinished then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
	end
	return nil
end

-- Premio por posicion en el ranking SEMANAL. Devuelve una TABLA { gems, cash, mats } (o nil = fuera de premios).
-- SUAVIZADO (22-jul, decision de Bastian + auditoria HIGH): antes pagaba 500 Gems al rank 1 SIN mirar cuanta
-- gente competia -> con el tablero vacio del lanzamiento, cualquiera era rank 1 cada semana y farmeaba premium
-- gratis. Ahora:
--   · Los GEMS (premium) SOLO los da el podio (top 3), y SOLO si hubo competencia real (>= MIN_COMPET jugadores
--     distintos esa semana). Con el tablero pequeño del arranque = 0 Gems (nadie farmea premium).
--   · Los tramos bajos (top 25) cobran Cash/materiales (moneda blanda, sin riesgo de economia).
-- VISION FUTURA (cuando haya poblacion, subir los numeros del podio a "cosas rotas" como querias): rank1 ~300-500
-- Gems + skin/relic exclusiva; escalar los tramos por percentiles (top 50%/20%...). De momento, suave.
Leaderboard.MIN_COMPET_GEMS = 12 -- por debajo de esto el tablero es demasiado chico para pagar GEMS (anti-faucet)
function Leaderboard.premioPara(rank, totalParticipantes)
	if not rank then return nil end
	local hayCompeticion = (totalParticipantes or 0) >= Leaderboard.MIN_COMPET_GEMS
	local p
	if rank == 1 then p = { gems = 100, cash = 800, mats = 5 }
	elseif rank == 2 then p = { gems = 60, cash = 500, mats = 3 }
	elseif rank == 3 then p = { gems = 35, cash = 350, mats = 2 }
	elseif rank <= 10 then p = { gems = 0, cash = 150, mats = 1 }
	elseif rank <= 25 then p = { gems = 0, cash = 60, mats = 0 }
	else return nil end
	if not hayCompeticion then p.gems = 0 end -- sin competencia real: NADA de premium (solo Cash/mats)
	return p
end

-- Rango (1-based) del jugador en una SEMANA concreta (num = numero de semana). nil = fuera del top ~200.
-- Para repartir premios de la semana PASADA al entrar (nadie esta online al cambiar de semana).
-- Devuelve (rank, scanOk). scanOk=false = fallo de DataStore (antes indistinto de 'fuera del top'):
-- el caller NO debe marcar la semana como comprobada -> se reintenta en el proximo login.
function Leaderboard.rankEnSemana(userId, num)
	local s = DataStoreService:GetOrderedDataStore("LB_Score_Week_" .. num)
	local k = tostring(userId)
	local ok, pages = pcall(function() return s:GetSortedAsync(false, 100) end)
	if not ok then return nil, false, 0 end -- escaneo FALLO -> reintentar
	local total, miRank = 0, nil
	for _ = 1, 2 do -- escanea hasta 200 (2 paginas)
		for _, entry in ipairs(pages:GetCurrentPage()) do
			total += 1
			if entry.key == k and not miRank then miRank = total end -- mi posicion, pero SIGO contando (total = tamaño del tablero, para el guard de competencia)
		end
		if pages.IsFinished then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
	end
	return miRank, true, total -- miRank nil = fuera del top; total = participantes contados (hasta ~200)
end

-- Registra las stats del jugador en sus boards. records (score/wave) con max; balances/acumulados (gems/horas/
-- runs) con el valor actual. Todo ENTERO. Se llama al terminar run y al salir (NO en cada save: hay rate limits).
function Leaderboard.registrarStats(userId, s)
	if not userId or type(s) ~= "table" then return end
	local k = tostring(userId)
	local function subeMax(store, v) if type(v) == "number" and v > 0 then pcall(function() store:UpdateAsync(k, function(old) return math.max(old or 0, math.floor(v)) end) end) end end
	local function fija(store, v) if type(v) == "number" and v >= 0 then pcall(function() store:UpdateAsync(k, function() return math.floor(v) end) end) end end
	subeMax(boards.score, s.score)
	subeMax(boards.wave, s.wave)
	fija(boards.gems, s.gems)
	fija(boards.horas, s.minutos)
	fija(boards.runs, s.runs)
end

-- Top N de un board concreto ("wave"/"score"/"gems"/"horas"/"runs"). Devuelve { {userId, valor}, ... }.
function Leaderboard.topDe(cual, n)
	local store = boards[cual]
	if not store then return {} end
	local ok, pages = pcall(function() return store:GetSortedAsync(false, math.clamp(n or 10, 1, 100)) end)
	if not ok then return {} end
	local out = {}
	for _, e in ipairs(pages:GetCurrentPage()) do out[#out + 1] = { userId = tonumber(e.key), valor = e.value } end
	return out
end

return Leaderboard
