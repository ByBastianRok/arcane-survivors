-- Quests (ModuleScript SERVIDOR) - Fase D - misiones diarias + racha de login.
-- Guarda el progreso en el perfil (MetaStore). Da Gems al reclamar. El cliente lo abre con
-- QuestsSync (sin args = pedir datos; "quest"+i = reclamar mision; "racha" = reclamar racha).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("QuestData"))
local MetaStore = require(ServerScriptService:WaitForChild("MetaStore"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local questsSync = remotes:WaitForChild("QuestsSync")

local Quests = {}

local function hoy() return math.floor(os.time() / 86400) end

local function generarMisiones()
	local out = {}
	for _, p in ipairs(QuestData.Pool) do
		out[#out + 1] = {
			tipo = p.tipo, desc = p.desc, gems = p.gems,
			target = p.targets[math.random(#p.targets)], prog = 0, claimed = false,
		}
	end
	return out
end

-- Asegura misiones de HOY + avanza la racha de login (1 vez al dia).
local function asegurarDia(player)
	local d = MetaStore.get(player)
	local h = hoy()
	if (d.questDay or 0) ~= h then
		d.questDay = h
		d.quests = generarMisiones()
	end
	if (d.lastLogin or 0) ~= h then
		if (d.lastLogin or 0) == h - 1 then
			d.streak = (d.streak or 0) + 1
		else
			d.streak = 1 -- racha rota (o primer login)
		end
		d.lastLogin = h
	end
end

-- Suma progreso a las misiones del 'tipo' (lo llama GameManager en kills/actos/oleada).
function Quests.progreso(player, tipo, valor)
	local d = MetaStore.get(player)
	if not d.quests then return end
	for _, q in ipairs(d.quests) do
		if q.tipo == tipo and not q.claimed then
			if tipo == "wave" then
				if valor > (q.prog or 0) then q.prog = valor end -- "alcanzar la oleada X" (set-max)
			else
				q.prog = (q.prog or 0) + valor
			end
		end
	end
end

local function construirDatos(player)
	asegurarDia(player)
	local d = MetaStore.get(player)
	local diaCiclo = ((d.streak or 1) - 1) % QuestData.RachaDias + 1
	local misiones = {}
	for _, q in ipairs(d.quests or {}) do
		misiones[#misiones + 1] = {
			desc = string.format(q.desc, q.target),
			prog = math.min(q.prog or 0, q.target), target = q.target,
			completa = (q.prog or 0) >= q.target, claimed = q.claimed, gems = q.gems,
		}
	end
	return {
		racha = {
			dia = diaCiclo, streak = d.streak or 1, premios = QuestData.RachaGems,
			reclamableHoy = (d.streakClaim or 0) ~= hoy(),
		},
		misiones = misiones,
	}
end

function Quests.sync(player)
	questsSync:FireClient(player, construirDatos(player))
end

questsSync.OnServerEvent:Connect(function(player, accion, dato)
	asegurarDia(player)
	local d = MetaStore.get(player)
	-- ===== POR QUE SE MARCA ANTES DE PAGAR Y NO DESPUES =====
	-- darGems GUARDA en el DataStore, y guardar CEDE (yield): de 100 ms a varios segundos, y hasta 3 intentos
	-- con esperas si el DataStore falla. Cada :FireServer llega en SU PROPIA corrutina, asi que con el orden
	-- de antes ("paga y luego marca") un segundo toque entraba mientras el primero seguia dentro de
	-- UpdateAsync, veia claimed todavia en false, y VOLVIA A PAGAR.
	-- Dos toques rapidos en CLAIM = Gems x2. Y las Gems se venden por Robux: era imprimir dinero gratis.
	-- Ahora se marca PRIMERO (no hay yield entre la comprobacion y la marca, asi que nadie se cuela) y si el
	-- pago no llega a persistir se DESHACE la marca, para que el jugador pueda reintentar sin perder nada.
	if accion == "quest" then
		local q = d.quests and d.quests[tonumber(dato)]
		if q and not q.claimed and (q.prog or 0) >= q.target then
			q.claimed = true
			if not MetaStore.darGems(player, q.gems) then q.claimed = false end
		end
	elseif accion == "racha" then
		if (d.streakClaim or 0) ~= hoy() then
			local diaCiclo = ((d.streak or 1) - 1) % QuestData.RachaDias + 1
			local marcaPrevia = d.streakClaim
			d.streakClaim = hoy()
			if not MetaStore.darGems(player, QuestData.RachaGems[diaCiclo] or 10) then d.streakClaim = marcaPrevia end
		end
	end
	Quests.sync(player)
end)

-- Genera las misiones del dia + avanza la racha al EMPEZAR la run (asi el tracking de
-- kills/oleada/actos cuenta aunque el jugador no haya abierto el panel de quests). Idempotente por dia.
function Quests.preparar(player)
	asegurarDia(player)
end

return Quests
