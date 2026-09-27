-- GameManager (Script del SERVIDOR) · bucle LOBBY <-> PARTIDA.
-- En el LOBBY gastas Cash (permanentes/armas, otros scripts) y pulsas PLAY. PLAY te lleva a la
-- ARENA y empiezan las oleadas. Matando ganas Coins (run upgrades). Al MORIR ganas Cash segun
-- tu PUNTUACION y vuelves al lobby. Cash NO se gana en plena run (eso arregla la incongruencia).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enemy = require(ServerScriptService:WaitForChild("Enemy"))
local Boss = require(ServerScriptService:WaitForChild("Boss"))
local RunState = require(ServerScriptService:WaitForChild("RunState"))
local PowerData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("PowerData"))
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponData")) -- filtro de talentos por arma
local EnemyData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("EnemyData")) -- filtro del afijo Leech por tipo de enemigo
local EvolutionData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("EvolutionData"))
local MetaStore = require(ServerScriptService:WaitForChild("MetaStore"))
local Badges = require(ServerScriptService:WaitForChild("Badges")) -- logros (badges de Roblox)
local RunShop = require(ServerScriptService:WaitForChild("RunShop"))
local Combat = require(ServerScriptService:WaitForChild("Combat")) -- Sco: medidor de dano co-op (lee danoAcum)
local ArenaBuilder = require(ServerScriptService:WaitForChild("ArenaBuilder")) -- Sju: arena tematica por mundo
local LobbyBuilder = require(ServerScriptService:WaitForChild("LobbyBuilder")) -- Sju: el hub social (plaza, brasero, props)
local WeaponVisuals = require(ServerScriptService:WaitForChild("WeaponVisuals")) -- Sju: mesh + agarre de cada arma (y de sus evos)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local hudUpdate = remotes:WaitForChild("HudUpdate")
local offerPowers = remotes:WaitForChild("OfferPowers")
local pickPower = remotes:WaitForChild("PickPower")
local startMatch = remotes:WaitForChild("StartMatch")
local matchState = remotes:WaitForChild("MatchState")
local matchEnd = remotes:WaitForChild("MatchEnd")
local matchError = remotes:WaitForChild("MatchError") -- co-op: avisa al cliente si el teleport falla (para reintentar/toast)
local reviveOffer = remotes:WaitForChild("ReviveOffer")       -- Smn: oferta de revivir al morir (server->client)
local reviveDecision = remotes:WaitForChild("ReviveDecision") -- Smn: decision del jugador (buy/cancel/giveup)
local reviveCompradoEvt = ServerScriptService:WaitForChild("ReviveComprado") -- Smn: la compra del consumible avisa aqui (server->server)
local REVIVE_TIMEOUT = 10 -- segundos para decidir antes de que acabe la run
local REVIVE_INVULN = 3   -- invuln al revivir para no morir al instante

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local WaveData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WaveData"))
local WorldData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WorldData"))
local Quests = require(script.Parent:WaitForChild("Quests")) -- Fase D (misiones diarias + racha)
local W = Config.Waves
local DESCANSO = W.Descanso
local RADIO_SPAWN = W.RadioSpawn
local INTERVALO_SPAWN = W.IntervaloSpawn
local BOSS_CADA = Config.Boss.CadaOleadas
local MUT = Config.Mutaciones
local SCORE = Config.Puntuacion
local LOBBY_POS = Config.LobbyPos

-- Co-op Fase B (2 places): decidir si esta run corre AQUI o el PLAY teletransporta a la party.
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local esStudio = RunService:IsStudio()
local esPlaceJuego = (game.PlaceId == Config.GamePlaceId) -- somos el place de JUEGO (recibe partys teletransportadas)
local esReservado = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0) -- server RESERVADO (ReserveServer), NO publico ni VIP
local correrLocal = esStudio or esPlaceJuego -- true = la run corre aqui; false = lobby publicado -> el PLAY teletransporta
local teleportando = {} -- [lider] = true mientras su reserve+teleport esta EN VUELO (anti doble-PLAY)
-- Co-op, en el place de JUEGO: con quien llegamos. Sirve para (a) enganchar rezagados y (b) devolver la PARTY
-- entera al lobby (si no, PartyServer reinicia a cada uno como party de 1 y el grupo se disuelve CADA acto).
local rosterRun = {} -- [userId] = true
local liderRun = nil -- UserId del lider de esa party

-- Teleport con REINTENTOS (backoff): TeleportAsync puede fallar por rate-limit/red; reintenta antes de rendirse.
local function teleportarSeguro(placeId, jugadores, opciones)
	if type(jugadores) == "table" and #jugadores == 0 then return false end
	for intento = 1, 5 do
		local ok, err = pcall(function() TeleportService:TeleportAsync(placeId, jugadores, opciones) end)
		if ok then return true end
		warn("[Coop] TeleportAsync fallo (intento " .. intento .. "):", err)
		task.wait(math.min(2 ^ (intento - 1), 8)) -- 1s, 2s, 4s, 8s, 8s
	end
	return false
end

-- Al acabar la run en el place de JUEGO publicado, devolver a todos al LOBBY (place de inicio).
local function volverAlLobby()
	if esPlaceJuego and not esStudio then
		task.wait(4.5) -- deja LEER la pantalla de fin de run (era 2.5, muy corto)
		-- Devolvemos tambien la PARTY: sin esto el PartyServer del lobby reinicia a cada uno como party de 1 y
		-- el grupo se DISOLVIA despues de cada acto (~12 min), obligando a re-invitarse una y otra vez.
		local opciones
		if liderRun then
			local ids = {}
			for uid in pairs(rosterRun) do ids[#ids + 1] = uid end
			if #ids > 1 then -- en solo no hay party que reconstruir
				opciones = Instance.new("TeleportOptions")
				opciones:SetTeleportData({ party = ids, lider = liderRun })
			end
		end
		teleportarSeguro(Config.LobbyPlaceId, Players:GetPlayers(), opciones)
	end
end
-- Sju: monta el lobby decorado al arrancar el server. Solo donde HAY lobby: en el place de JUEGO publicado los
-- jugadores llegan teletransportados directos a la arena y se van al acabar, asi que ahi seria decorado inutil.
if not (esPlaceJuego and not esStudio) then
	task.spawn(function()
		local ok, err = pcall(LobbyBuilder.construir)
		if not ok then warn("[Lobby] no se pudo construir:", err) end
	end)
end

local ARENA_POS = Config.ArenaPos
local BOSSES = { "ForestWarden", "GlacialSentinel", "MagmaColossus" }

Players.CharacterAutoLoads = false

-- K: ocultar CUALQUIER SpawnLocation (la losa blanca 10x10 con su calcomania). Nadie los usa (CharacterAutoLoads=false:
-- posicionamos a los jugadores a mano), son legacy decorativos. En el LOBBY ya lo hace LobbyBuilder; aqui cubrimos
-- tambien el place de JUEGO (arena), donde LobbyBuilder NO corre y quedaba un spawnpoint blanco en medio del mapa.
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("SpawnLocation") then
		d.Transparency = 1
		for _, ch in ipairs(d:GetChildren()) do if ch:IsA("Decal") or ch:IsA("Texture") then ch.Transparency = 1 end end
	end
end

local oleadaActual = 0
local enemigosVivos = 0
local corriendo = false
local puntuacion = 0

local function construirListaSpawn(composicion, mult)
	mult = mult or 1 -- co-op: multiplica la CANTIDAD de enemigos por n de jugadores
	local grupos, total = {}, 0
	for _, g in ipairs(composicion) do
		local n = math.ceil(g.cantidad * mult)
		grupos[#grupos + 1] = { tipo = g.tipo, afijo = g.elite, n = n }
		total += n
	end
	local lista = {}
	local quedan = true
	while quedan do
		quedan = false
		for _, g in ipairs(grupos) do
			if g.n > 0 then
				lista[#lista + 1] = { tipo = g.tipo, afijo = g.afijo }
				g.n -= 1
				quedan = true
			end
		end
	end
	return lista, total
end

local function tirarMutacion(oleada, tipo)
	if oleada < MUT.OleadaInicio then return nil end
	local chance = math.min(MUT.ChanceMax, MUT.ChanceBase + (oleada - MUT.OleadaInicio) * MUT.ChancePorOleada)
	chance = chance * (workspace:GetAttribute("WorldEliteBoost") or 1) -- modificador de mundo "masElites"
	if math.random() > chance then return nil end
	local base = tipo and EnemyData[tipo]
	local esMelee = base and (base.Dano or 0) > 0 and not (base.Ranged or base.Explosivo or base.Healer or base.Invoca) -- Leech (Vampiro) solo cura en golpe MELEE (Enemy.luau)
	local pool = {}
	for afijo, minOleada in pairs(MUT.Desbloqueo) do
		if oleada >= minOleada and not (afijo == "Vampiro" and not esMelee) then pool[#pool + 1] = afijo end -- no ofrecer Leech a Spitter/Bomber/Mender/Warlock (afijo muerto ahi)
	end
	if #pool == 0 then return nil end
	-- 1 afijo seguro; 2do RARO; 3ro RARISIMO (mezcla: Swift Giant Tank, etc.)
	local elegidos = { pool[math.random(1, #pool)] }
	if #pool >= 2 and math.random() < (MUT.ChanceDoble or 0) then
		local otro
		repeat otro = pool[math.random(1, #pool)] until otro ~= elegidos[1]
		elegidos[#elegidos + 1] = otro
		if #pool >= 3 and math.random() < (MUT.ChanceTriple or 0) then
			local tercero
			repeat tercero = pool[math.random(1, #pool)] until tercero ~= elegidos[1] and tercero ~= elegidos[2]
			elegidos[#elegidos + 1] = tercero
			if #pool >= 4 and math.random() < (MUT.ChanceCuadruple or 0) then
				local cuarto
				repeat cuarto = pool[math.random(1, #pool)] until cuarto ~= elegidos[1] and cuarto ~= elegidos[2] and cuarto ~= elegidos[3]
				elegidos[#elegidos + 1] = cuarto
			end
		end
	end
	return elegidos
end

local function posicionDeAparicion()
	-- Survivors: la horda aparece alrededor de UN jugador VIVO al AZAR (co-op: repartida entre todos), no del centro fijo.
	local vivos = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then vivos[#vivos + 1] = hrp.Position end
	end
	local centro = (#vivos > 0) and vivos[math.random(#vivos)] or ARENA_POS
	local ang = math.random() * math.pi * 2
	return Vector3.new(centro.X + math.cos(ang) * RADIO_SPAWN, 5, centro.Z + math.sin(ang) * RADIO_SPAWN)
end

-- Posicion del JEFE/champion: como la de la horda pero algo mas lejos (entrada mas teatral).
-- CRITICO que sea relativa a un JUGADOR VIVO y no una posicion fija del mundo. Antes era Vector3(0, 8, -44),
-- o sea pegada al origen: con la arena pequena daba igual, pero con el mapa GRANDE (radio 600) el jefe
-- aparecia en el centro del mapa mientras tu estabas a 400 studs -> te quedabas esperando eternamente a un
-- jefe que no ibas a ver nunca y la run se colgaba.
local function posicionDeJefe()
	local vivos = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then vivos[#vivos + 1] = hrp.Position end
	end
	local centro = (#vivos > 0) and vivos[math.random(#vivos)] or ARENA_POS
	-- R (fix): elegir un punto DESPEJADO. Antes caia aleatorio y a veces DENTRO de un arbol/prop colisionable ->
	-- el jefe spawneaba ATASCADO (inmovil) y se fulminaba gratis en 3s. Ahora se comprueba que no haya prop solido.
	local function despejado(pos)
		for _, p in ipairs(workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(11, 7, 11))) do
			if p.CanCollide and p.Anchored and not p:IsDescendantOf(workspace.Terrain) then return false end
		end
		return true
	end
	for _ = 1, 16 do
		local ang = math.random() * math.pi * 2
		local dist = RADIO_SPAWN + math.random() * 14
		local pos = Vector3.new(centro.X + math.cos(ang) * dist, centro.Y + 3, centro.Z + math.sin(ang) * dist)
		if despejado(pos) then return pos end
	end
	return Vector3.new(centro.X, centro.Y + 3, centro.Z) -- fallback: junto al jugador (suelo despejado seguro)
end

local function teleportar(player, pos)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = CFrame.new(pos) end
end

-- Co-op: reparte a los jugadores en un ANILLO alrededor del centro (no apilados en el mismo punto).
local function teleportarTodosAlAnillo(jugadores, centro)
	local n = #jugadores
	for i, pl in ipairs(jugadores) do
		if n <= 1 then teleportar(pl, centro)
		else
			local ang = (i - 1) / n * math.pi * 2
			teleportar(pl, centro + Vector3.new(math.cos(ang) * 8, 0, math.sin(ang) * 8))
		end
	end
end

local function avisarEstado(player, estado)
	matchState:FireClient(player, { state = estado })
end

local function hayJugadorVivo()
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then return true end
	end
	return false
end

-- Auditoria B3: PARTICIPANTES de la run (los presentes al empezar). Solo ellos cuentan para terminar
-- la run y para las recompensas (antes se contaba/premiaba a CUALQUIERA del servidor -> leech/carry).
local enRun = {}
local function hayParticipanteVivo()
	for pl in pairs(enRun) do
		if pl.Parent then
			local ch = pl.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then return true end
		end
	end
	return false
end

local function limpiarEnemigos()
	local carpeta = workspace:FindFirstChild("Enemies") -- todos los enemigos viven aqui (ver Enemy.luau)
	for _, m in ipairs(carpeta and carpeta:GetChildren() or {}) do
		if m.Name == "BrainrotEnemy" then m:Destroy() end
	end
	enemigosVivos = 0
end

-- ===== Roguelite: oferta de poderes "elige 1 de 3" entre oleadas =====
local picks = {}
-- Aplica la eleccion: EVOLUCION de arma -> muta el arma; si no -> aplica la carta normal.
-- Le pone al arma equipada la cara de su evolucion.
--
-- Esto era `h.Color = evo.color`, y funcionaba cuando el Handle era una caja de color. Desde que las armas son
-- MeshParts CON TEXTURA el tinte NO SE VE (la textura tapa el .Color), asi que evolucionar -- que es el
-- "momento clip" del juego -- se habia quedado sin ningun cambio visual, y sin dar ningun error.
-- WeaponVisuals cambia el mesh EN SITIO con ApplyMesh: imprescindible aqui, porque el arma esta EQUIPADA y
-- soldada a la mano y sustituir la instancia del Handle rompe el agarre.
local function evolucionarArma(player, evo)
	RunState.get(player).evolucionado = true
	local ch = player.Character
	local tool = ch and ch:FindFirstChildOfClass("Tool")
	if tool then
		tool.Name = evo.armaEvo -- el auto-fuego usa WeaponData[tool.Name]
		if not WeaponVisuals.aplicar(tool, evo.armaEvo) then
			-- Respaldo por si algun dia falta el mesh de esa evolucion: al menos el tinte de siempre.
			local h = tool:FindFirstChild("Handle")
			if h then h.Color = evo.color end
		end
	end
	RunState.sync(player)
end
local function aplicarEleccion(player, id)
	local evo = EvolutionData.porId(id)
	if evo then evolucionarArma(player, evo) else RunState.aplicar(player, id) end
end
-- Construye las cartas; si hay receta de evolucion cumplida, inyecta la CARTA DORADA (y muta 'ids').
local function ofertaCartas(player, ids, mods, nivel)
	local cards = PowerData.infoDe(ids)
	local d = MetaStore.get(player)
	local evo, locked = EvolutionData.disponible(d.claseActual, mods.poderes, mods.evolucionado, d.evoDesbloq)
	-- Gate A (meta-unlock): solo si la evo esta DESBLOQUEADA (Forge o regalo). Gate B (curva): solo desde nivel de equipo >= MinEvoLevel.
	if evo and not locked and (nivel or 0) >= Config.MinEvoLevel then
		ids[1] = evo.id
		cards[1] = { id = evo.id, nombre = evo.nombre, desc = evo.desc, categoria = "WEAPON", rareza = "EVOLUTION", color = evo.color, evo = true }
	end
	return cards
end
pickPower.OnServerEvent:Connect(function(player, id)
	local p = picks[player]
	if not p or p.done then return end
	local valido = false
	for _, cid in ipairs(p.ids) do
		if cid == id then valido = true; break end
	end
	if not valido then return end
	p.done = true
	aplicarEleccion(player, id)
end)

-- ===== XP + NIVEL de EQUIPO (co-op): matar da XP al POZO del equipo; al subir, TODOS eligen carta =====
-- XP COMPARTIDA (decision Bastian 3 jul): un solo nivel de equipo -> suben juntos -> pausa sincronizada.
-- Cada jugador elige SU propia carta (builds individuales). En solo = equipo de 1 (identico a antes).
local xpEquipo, nivelEquipo = 0, 1
local ofreciendo = false -- true mientras hay una oferta de cartas abierta (evita ofertas solapadas)
local nivelesPendientes = 0 -- niveles subidos MIENTRAS habia una oferta abierta: se ofrecen despues (no se pierden)
local escalaXP = 1 -- n de participantes CONGELADO al arrancar la run (ver xpNecesario)
local XP_TIPO = { Tank = 4, Exploder = 2, Ranged = 2 } -- XP por tipo de enemigo (resto = 1)
-- Umbral escala por n de jugadores: 4 jugadores = 4x kills al pozo -> 4x umbral = mismo ritmo que en solo.
local function numRun() local n = 0; for _ in pairs(enRun) do n += 1 end; return math.max(1, n) end
-- El umbral escala con 'escalaXP' = MISMO factor que la cantidad de enemigos (coopCount), congelado al arrancar
-- la run. Dos motivos: (1) con numRun() el umbral subia x4 con 4 jugadores pero la horda solo x2.8 -> en co-op
-- se subia de nivel mas LENTO que en solo; (2) leyendolo en VIVO, si alguien se iba a mitad el umbral bajaba de
-- golpe (la XP acumulada no se reescala) y el equipo se comia varios niveles gratis de una tacada.
local function xpNecesario(n) return (4 + n * 4) * escalaXP end -- lvl1->2 = 8 por jugador, progresivo
-- Escalado CO-OP por n de jugadores (TUNABLE; a Config en el pase de balanceo). N=1 (solo) => todo x1.
local function coopHP()    return 1 + 0.30 * (numRun() - 1) end -- +vida de enemigos
local function coopCount() return 1 + 0.60 * (numRun() - 1) end -- +cantidad de enemigos
local function coopBoss()  return 1 + 1.0 * (numRun() - 1) end -- +vida del jefe: 1.0/jugador = escala CON el equipo (no se derrite en co-op); era 0.7 -> el jefe moria MAS rapido con mas gente

-- Oferta de cartas a TODO el equipo a la vez: cada jugador vivo recibe SU propia oferta de 3 cartas
-- DISTINTA + elige independiente. El mundo se CONGELA (una pausa sincronizada) hasta que TODOS eligen.
local function ofrecerPoderes()
	if ofreciendo then return end
	ofreciendo = true
	local jugadores = {}
	for pl in pairs(enRun) do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local mods = RunState.get(pl)
			local tool = pl.Character and pl.Character:FindFirstChildOfClass("Tool") -- filtro por arma (no ofrecer talentos inutiles)
			local ids = PowerData.elegir(3, mods, tool and WeaponData[tool.Name]) -- cartas PROPIAS de cada jugador (distintas entre si)
			picks[pl] = { ids = ids, done = false, vel = hum.WalkSpeed }
			pl:SetAttribute("Eligiendo", true) -- pausa su auto-fuego
			mods.invulnEligiendo = true          -- invuln mientras elige (flag propio)
			hum.WalkSpeed = 0
			offerPowers:FireClient(pl, { cards = ofertaCartas(pl, ids, mods, nivelEquipo) })
			jugadores[#jugadores + 1] = pl
		end
	end
	if #jugadores == 0 then ofreciendo = false; return end
	workspace:SetAttribute("Congelado", true) -- UNA congelacion para todo el equipo
	local limite = os.clock() + 180
	while corriendo and os.clock() < limite do
		local faltan = false
		for _, pl in ipairs(jugadores) do
			if picks[pl] and not picks[pl].done then faltan = true; break end
		end
		if not faltan then break end
		task.wait(0.15)
	end
	for _, pl in ipairs(jugadores) do
		local p = picks[pl]
		if p and not p.done then p.done = true; aplicarEleccion(pl, p.ids[1]) end -- timeout -> auto-pick 1a
		offerPowers:FireClient(pl, { close = true })
		picks[pl] = nil
		pl:SetAttribute("Eligiendo", nil)
		RunState.get(pl).invulnEligiendo = false
		local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Parent and p then hum.WalkSpeed = p.vel end
	end
	workspace:SetAttribute("Congelado", false) -- descongela cuando TODOS eligieron
	ofreciendo = false
	if nivelesPendientes > 0 and corriendo then -- niveles que subieron durante ESTA oferta: se ofrecen ahora
		nivelesPendientes -= 1
		task.spawn(ofrecerPoderes)
	end
end

-- Smn: estado de la oferta de revivir-pagando (consumible), por jugador.
local revEsperando, revPagado, revRendido, revComprando = {}, {}, {}, {}
-- reviveCredito PERSISTE ahora en el perfil (MetaStore.addReviveCredito/useReviveCredito), no en memoria:
-- un revive PAGADO que no se pudo aplicar ya NO se pierde al salir del server (antes: Robux cobrado sin nada).

-- (ofrecerPoderesA individual ELIMINADO: co-op usa ofrecerPoderes de EQUIPO, definido arriba)

local function ganarXP(player, n)
	n = n * (RunState.get(player).xpMult or 1) -- S2: Scholar del que mata aporta mas al POZO del equipo
	xpEquipo += n
	local subidas = 0
	while xpEquipo >= xpNecesario(nivelEquipo) do
		xpEquipo -= xpNecesario(nivelEquipo)
		nivelEquipo += 1
		subidas += 1
	end
	local xpMax = xpNecesario(nivelEquipo)
	for pl in pairs(enRun) do hudUpdate:FireClient(pl, { xp = xpEquipo, xpMax = xpMax, level = nivelEquipo }) end -- barra de EQUIPO a todos
	if subidas > 0 then
		-- Los niveles que suben con una oferta YA abierta no se tiran: se ENCOLAN y se ofrecen al cerrarse.
		-- (Durante el freeze el DoT sigue matando, asi que en co-op se subia de nivel sin recibir carta.)
		if ofreciendo then
			nivelesPendientes += subidas
		else
			nivelesPendientes += subidas - 1 -- la primera se ofrece ya; las demas quedan en cola
			task.spawn(ofrecerPoderes)
		end
	end
end

local runInicio = 0 -- os.clock() al empezar la run (para el tiempo jugado de por vida)
local difActual -- dificultad de la run en curso (para escalar recompensas/materiales)

-- Valida que un jugador tenga desbloqueado el mundo/acto/dificultad (mismo gateo que startMatch): en co-op,
-- por-participante, para que un jugador ARRASTRADO no desbloquee/cobre contenido que no habia ganado.
local function accesoLegitimo(player, mundo, actId, difId)
	if type(mundo) ~= "table" or type(mundo.id) ~= "number" then return true end -- sin mundo campaña: sin gateo
	-- E (fix, OK Bastian): en co-op un participante REAL cobra Gems + progreso por lo que SUPERA con la party,
	-- aunque no lo tuviera desbloqueado en solo (antes se negaba mundoDesbloqueado/actoDesbloqueado -> un participante
	-- no recibia el first-clear). Se MANTIENE solo el gate de DIFICULTAD: no te llevas premios de Hard/Nightmare
	-- sin haber completado la dificultad inferior (evita el boost directo a lo dificil).
	if difId == "hard" and not MetaStore.mundoCompleto(player, mundo.id, "normal", mundo.numActos) then return false end
	if difId == "nightmare" and not MetaStore.mundoCompleto(player, mundo.id, "hard", mundo.numActos) then return false end
	return true
end

-- ACTO superado: el jugador batio al jefe del acto. Recompensa + marca el progreso + de vuelta al lobby.
local function actoSuperado(mundo, actId, dif, esFinal)
	corriendo = false
	limpiarEnemigos()
	-- (ArenaBuilder.limpiar se movio al FINAL: fix del "mapa gris al ganar", ver abajo.)
	-- SNAPSHOT de participantes ANTES de repartir: las llamadas de premio hacen YIELD (marcarActo -> guardar ->
	-- UpdateAsync) y en ese hueco el bucle de revive de un jugador MUERTO ve corriendo=false, se borra a si mismo
	-- de enRun y se va al lobby -> con pairs(enRun) en vivo se quedaba SIN progreso ni recompensa del acto.
	-- (Ademas, mutar la tabla en mitad de un pairs() es fragil de por si.)
	local participantes = {}
	for pl in pairs(enRun) do participantes[#participantes + 1] = pl end
	for _, pl in ipairs(participantes) do -- B3: solo participantes de la run (antes: cualquiera del servidor -> leech/carry)
		if not pl.Parent then continue end
		if not accesoLegitimo(pl, mundo, actId, dif.id) then
			-- sin acceso: no cobra ni desbloquea, pero SI merece saber por que (antes se iba al lobby sin ninguna pantalla)
			matchEnd:FireClient(pl, { cleared = true, locked = true, world = mundo.nombre, act = actId, wave = oleadaActual, score = puntuacion, cash = 0, gems = 0 })
			continue
		end
		local primera = MetaStore.marcarActo(pl, mundo.id, actId, dif.id) -- record de este acto/dificultad
		if esFinal and mundo.id == 1 then MetaStore.desbloquearEvo(pl, "evoInferno") end -- REGALO: la 1a evo (Mage/Inferno) al superar el Mundo 1 (SIN 'primera': idempotente, tambien a quien YA lo paso antes)
		Quests.progreso(pl, "acts", 1); Quests.progreso(pl, "wave", oleadaActual) -- Fase D
		local ls = pl:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Cash")
		local gems = ls and ls:FindFirstChild("Gems")
		local cashMult = RunState.get(pl).cashMult or 1
		local recompMult = dif.recompensaMult or 1
		-- El acto tambien multiplica: antes 'repiteCash' era un numero POR MUNDO, asi que los 4 actos pagaban
		-- lo mismo pese a que los enemigos escalan acto a acto (lo cazo Bastian jugando). La tabla esta en
		-- WorldData.ActoMult para poder tocar la economia desde un solo sitio.
		local actoMult = WorldData.ActoMult and WorldData.ActoMult[actId] or 1
		local cashGan = math.floor((mundo.repiteCash or 100) * actoMult * recompMult * cashMult + puntuacion * SCORE.CashPorPunto * cashMult)
		if cash then cash.Value += cashGan end
		local gemsGan = 0
		if primera and gems then -- Gems en el 1er clear de CADA acto (por acto+dificultad; NO repetible = no farmeable).
			-- El JEFE del mundo (esFinal) da el premio GORDO; los actos normales dan una probadita. Escala con la
			-- dificultad (recompMult): pasarlo en Oblivion vale mas que en Trial. (Antes solo el jefe del mundo; Bastian
			-- lo cambio para que el co-op y los novatos noten recompensa acto a acto sin romper la venta premium.)
			local baseGems = esFinal and (mundo.primeraGems or 25) or (mundo.actoGems or 8)
			gemsGan = math.floor(baseGems * recompMult)
			if pl:GetAttribute("Pass_gems2x") then gemsGan *= 2 end -- Smn: gamepass 2x Gems
			gems.Value += gemsGan
		end
		-- Scr: materiales de crafteo (tematicos del mundo, escalan con matMult de la dificultad)
		local matWorld = WorldData.materialDe(mundo.id)
		if matWorld then
			local matMult = dif.matMult or 1
			local extraMat = pl:GetAttribute("Pass_extradrop") and 1.5 or 1 -- gamepass Extra Materials (+50%)
			-- Cantidad DOBLADA el 22-jul (Bastian: "solo te dan un material que no sirve"). Ahora act1=12, act2=16,
			-- act3=20, act4=24 (antes 6/8/10/12). Con las reliquias/consumibles nuevos (CraftData) cada material
			-- del mundo tiene ya varias recetas -> deja de acumularse sin uso.
			MetaStore.darMaterial(pl, matWorld, math.floor((8 + actId * 4) * matMult * extraMat))
			MetaStore.darMaterial(pl, "dust", math.floor((14 + actId * 5) * matMult * extraMat)) -- 22-jul: Arcane Dust (relleno comun), generoso: act1=19, act4=34
			if esFinal then MetaStore.darMaterial(pl, "rare", math.floor(6 * matMult * extraMat)) end -- el jefe del mundo da material raro (3->6)
		end
		-- LOGROS (badges de Roblox): hitos de progresion. Los ids reales los pone Bastian en Badges.IDS; 0 = no otorga.
		Badges.otorgar(pl, "primerActo")
		if esFinal then -- superado el JEFE del mundo
			Badges.otorgar(pl, ({ [1] = "woods", [2] = "frost", [3] = "ember" })[mundo.id])
			if dif.id == "nightmare" then Badges.otorgar(pl, "nightmare") end -- Oblivion = id interno "nightmare"
		end
		matchEnd:FireClient(pl, { cleared = true, world = mundo.nombre, act = actId, finalAct = esFinal, wave = oleadaActual, score = puntuacion, cash = cashGan, gems = gemsGan, firstClear = primera }) -- honesto: gemsGan ya ES lo que recibe (0 si repites; los Gems del mundo ya no son repetibles)
		MetaStore.addPlayTime(pl, os.clock() - runInicio)
		task.spawn(MetaStore.registrarResultado, pl, oleadaActual, puntuacion)
		if not (esPlaceJuego and not esStudio) then pl:LoadCharacter() end -- single-place/Studio reaparece; zona de juego se TELEPORTA (volverAlLobby)
	end
	ArenaBuilder.limpiar() -- FIX (mapa gris al ganar): limpiar la arena AQUI, al FINAL. Antes se borraba el suelo ANTES de los yields de guardado -> la camara miraba el hueco vacio (void gris) hasta reaparecer. Ahora se quita tras volver al lobby.
	volverAlLobby() -- co-op 2 places: de vuelta al lobby si estamos en el place de juego publicado
end

-- Champion de cada acto no-final (1-3): un mini-jefe con IDENTIDAD propia. Antes los 3 actos usaban el
-- MISMO Tank+afijos (repetitivo, y ademas identico en los 3 mundos). Ahora cada acto es un bicho distinto.
local CHAMPIONS = {
	{ tipo = "Charger", afijos = { "Gigante", "Acorazado", "Frenetico" } },             -- acto 1: embiste, agresivo (~780 HP tras bajar bases)
	{ tipo = "Summoner", afijos = { "Gigante", "Acorazado", "Regenerante" } },          -- acto 2: invoca Chasers, aguante (~778 HP)
	{ tipo = "Tank", afijos = { "Gigante", "Acorazado", "Frenetico" } },                -- acto 3: muro que pega duro (~1489 HP; era 2978. Se quito Regenerante: forzaba un DPS minimo y hacia la pelea eterna, es donde Bastian moria siempre)
}

-- Setup por-jugador al ENTRAR en una run. Lo usan correrPartida (arranque) y el enganche EN CALIENTE de un
-- rezagado. OJO: NO toca xpEquipo/nivelEquipo (es estado de EQUIPO, lo resetea correrPartida una sola vez) y
-- manda al HUD la XP/nivel ACTUALES, para que quien entra tarde vea la barra del equipo y no una a 0.
local function prepararParticipante(pl)
	enRun[pl] = true
	RunState.reset(pl)
	MetaStore.aplicarA(pl)
	Quests.preparar(pl) -- genera las misiones del dia ANTES de la run (si no, el tracking de kills no cuenta)
	MetaStore.addRun(pl)
	RunShop.reset(pl)
	pl:SetAttribute("RunDamage", 0) -- Sco: medidor de dano co-op (reset)
	hudUpdate:FireClient(pl, { xp = xpEquipo, xpMax = xpNecesario(nivelEquipo), level = nivelEquipo })
	avisarEstado(pl, "match")
	-- Perfil en SOLO LECTURA: DataService no pudo tomar el session-lock (lo normal: el server de LOBBY del que
	-- venimos aun no lo habia soltado). La run se juega igual, pero al final el guardado se descarta EN SILENCIO
	-- -> 12 minutos tirados sin enterarte. Avisamos YA para que pueda salir y reentrar. (En Studio no avisamos:
	-- sin "Studio Access to API Services" siempre seria solo-lectura y solo haria ruido al testear.)
	if not esStudio and not MetaStore.puedeOperar(pl) then
		warn("[Coop] perfil en SOLO LECTURA para", pl.Name, "- el progreso de esta run NO se guardara")
		task.delay(2, function()
			if pl.Parent then hudUpdate:FireClient(pl, { message = "DATA LOCKED - progress won't save. Rejoin!" }) end
		end)
	end
end

local function correrPartida(worldId, actId, difId)
	corriendo = true
	table.clear(enRun)
	for _, pl in ipairs(Players:GetPlayers()) do enRun[pl] = true end -- participantes = los presentes (el teleport ya ESPERO al roster antes de arrancar); coopHP/coopBoss lo necesitan poblado YA
	runInicio = os.clock()
	oleadaActual = 0
	workspace:SetAttribute("EnemyHPMult", 1) -- reset del escalado de vida por jefe
	local mundo = WorldData.porId(worldId or 1)
	local esEndless = (mundo == nil) or (mundo.id == "endless")
	local dif = WorldData.dificultad(difId)
	difActual = dif
	-- Sju: monta la arena TEMATICA del mundo (suelo, borde, decoracion, niebla, luz) + avisa al cliente para
	-- el clima. Endless tiene su propio aspecto (el Rift cosmico), clave "endless" en WorldArt.
	ArenaBuilder.construir(esEndless and "endless" or ((mundo and mundo.id) or 1))
	local actoActual = esEndless and 0 or (actId or 1)
	local numActos = (mundo and mundo.numActos) or 4
	local oleadasActo = (mundo and mundo.oleadasActo) or 15
	local actoEscala = 1 + (math.max(1, actoActual) - 1) * 0.12 -- los actos escalan dentro del mundo
	workspace:SetAttribute("WorldVidaMult", ((mundo and mundo.vidaMult) or 1) * actoEscala * dif.vidaMult * coopHP()) -- *coopHP = +vida enemigos por n de jugadores
	workspace:SetAttribute("WorldDanoMult", ((mundo and mundo.danoMult) or 1) * actoEscala * dif.danoMult)
	workspace:SetAttribute("WorldVeloMult", (mundo and mundo.veloMult) or 1)
	workspace:SetAttribute("WorldEliteBoost", (mundo and mundo.eliteBoost) or 1)
	workspace:SetAttribute("WorldMatMult", dif.matMult) -- materiales (crafteo) escalan con la dificultad
	workspace:SetAttribute("CoopBossMult", coopBoss()) -- co-op: +vida del jefe por n de jugadores
	workspace:SetAttribute("BossVidaMult", ((mundo and mundo.vidaMult) or 1) * actoEscala * dif.vidaMult) -- Fix D: el JEFE (acto 4 / Endless) escala con mundo/acto/dificultad (el coop va aparte, via CoopBossMult)
	workspace:SetAttribute("BossDanoMult", ((mundo and mundo.danoMult) or 1) * actoEscala * dif.danoMult) -- Fix D: el dano del jefe escala con dificultad (Nightmare = jefe brutal)
	workspace:SetAttribute("EsEndless", esEndless) -- Boss: el x1.8 de vida por oleada SOLO aplica en Endless (en campana el 4600 nominal engañaba: salia 11k)
	puntuacion = 0
	table.clear(revEsperando); table.clear(revPagado); table.clear(revRendido); table.clear(revComprando) -- Smn: limpia ofertas de revive al empezar run
	-- CRITICO (fix co-op): esperar a que TODOS los perfiles esten CARGADOS antes de aplicar upgrades. En el teleport
	-- lobby->juego la carga es lenta; sin esto aplicarA corre sobre un perfil VACIO -> upgrades permanentes NO cuentan.
	local tCarga = os.clock()
	while os.clock() - tCarga < 8 do
		local todos = true
		for _, pl in ipairs(Players:GetPlayers()) do if not MetaStore.perfilListo(pl) then todos = false; break end end
		if todos then break end
		task.wait(0.1)
	end
	xpEquipo = 0; nivelEquipo = 1; nivelesPendientes = 0 -- XP de EQUIPO: reset UNA vez al empezar la run
	-- El umbral usa el MISMO factor que la CANTIDAD de enemigos (coopCount), NO numRun(): con numRun() el umbral
	-- subia x4 con 4 jugadores mientras la horda solo x2.8, asi que en co-op se subia de nivel MAS LENTO que en
	-- solo (justo lo contrario de lo que queremos). Se congela al arrancar: no debe moverse a mitad de run.
	escalaXP = coopCount()
	for _, pl in ipairs(Players:GetPlayers()) do prepararParticipante(pl) end
	Combat.resetDano() -- Sco: medidor de dano co-op
	task.spawn(function() while corriendo do for pl in pairs(enRun) do pl:SetAttribute("RunDamage", math.floor(Combat.danoAcum[pl] or 0)) end task.wait(0.5) end end) -- sincroniza el dano a atributo (replica al cliente)
	-- Intro cinematografica (22-jul): el cliente (HudClient) la pinta al ver subir IntroTick. Nombre del mundo +
	-- dificultad + acto, con una pausa de ~3.4s para que respire antes de la 1a oleada.
	workspace:SetAttribute("RunMundo", esEndless and "Endless Rift" or ((mundo and mundo.nombre) or "Unknown"))
	workspace:SetAttribute("RunDif", (dif and dif.nombre) or "")
	workspace:SetAttribute("RunActo", actoActual)
	workspace:SetAttribute("IntroTick", (workspace:GetAttribute("IntroTick") or 0) + 1)
	if esEndless then for pl in pairs(enRun) do Badges.otorgar(pl, "endless") end end -- logro: entrar en Endless
	task.wait(3.4)
	if not corriendo then return end -- por si abandonan durante la intro
	while corriendo do
		oleadaActual += 1
		workspace:SetAttribute("Oleada", oleadaActual) -- Drops escala el dropeo en rondas altas
		local esJefe = (esEndless and oleadaActual % BOSS_CADA == 0) or ((not esEndless) and oleadaActual == oleadasActo)
		if esJefe then
			local esFinal = (not esEndless) and (actoActual >= numActos) -- el ULTIMO acto trae al JEFE del mundo
			hudUpdate:FireAllClients({ wave = oleadaActual, enemiesLeft = 1, message = esEndless and "BOSS INCOMING!" or (esFinal and "WORLD BOSS!" or "ACT BOSS!") })
			task.wait(1.5)
			if not corriendo then break end
			-- Refrescar el escalado co-op JUSTO antes del jefe: si alguien se fue (o se engancho) a mitad del
			-- acto, los que quedan peleaban un jefe dimensionado para la party ORIGINAL.
			workspace:SetAttribute("CoopBossMult", coopBoss())
			local bossHum
			if esEndless then
				local _, h = Boss.spawn(BOSSES[((oleadaActual // BOSS_CADA) - 1) % #BOSSES + 1], posicionDeJefe()); bossHum = h
			elseif esFinal then
				local _, h = Boss.spawn((mundo and mundo.jefe) or BOSSES[1], posicionDeJefe()); bossHum = h
			else
				local champ = CHAMPIONS[math.clamp(actoActual, 1, #CHAMPIONS)] or CHAMPIONS[1] -- champion propio de cada acto (1-3)
				-- El champion sale por Enemy.spawn, que solo aplica WorldVidaMult (curva coopHP, +30%/jugador),
				-- mientras que el jefe del acto 4 usa Boss.spawn con CoopBossMult (+100%/jugador): en co-op el
				-- champion se derretia en 3 de cada 4 actos. Le aplicamos la MISMA curva co-op que al jefe.
				local hpPrev = workspace:GetAttribute("EnemyHPMult") or 1
				local cHP = coopHP()
				workspace:SetAttribute("EnemyHPMult", hpPrev * (coopBoss() / (cHP > 0 and cHP or 1)))
				local _, h = Enemy.spawn(champ.tipo, posicionDeJefe(), champ.afijos); bossHum = h
				workspace:SetAttribute("EnemyHPMult", hpPrev) -- restaurar para el resto de la horda
			end
			while corriendo and bossHum.Parent and bossHum.Health > 0 do
				task.wait(0.3)
			end
			limpiarEnemigos()
			if not corriendo then break end
			puntuacion += SCORE.PorJefe
			-- XP de EQUIPO: una sola vez (no por jugador; con XP compartida sumaba N veces). Se atribuye a QUIEN
			-- REMATA al jefe, para que su Scholar cuente (antes iba a un participante ARBITRARIO, next(enRun)).
			local repJefe = Combat.ultimoAtacante[bossHum]
			if not (repJefe and enRun[repJefe]) then repJefe = next(enRun) end
			if repJefe then ganarXP(repJefe, 40 + oleadaActual * 5) end
			-- (Los Gems del jefe de mundo YA NO son repetibles: se pagan SOLO en el 1er clear, dentro de actoSuperado,
			--  escalados por dificultad. Repetir un mundo da Cash + materiales, NO Gems. Decision de Bastian ("Gems
			--  solo de hitos") + hallazgo de la auditoria: antes aqui se regalaba bossGems en CADA clear = faucet de premium.)
			if not esEndless then actoSuperado(mundo, actoActual, difActual, esFinal); return end -- ACTO superado, fin de la run
			workspace:SetAttribute("EnemyHPMult", (workspace:GetAttribute("EnemyHPMult") or 1) * 1.18)
			-- CHICHA DEL ENDLESS (hito): cada jefe del Rift suelta MATERIALES escalando con la profundidad. Los
			-- materiales NO se venden por Robux -> premiar generoso aqui es puro combustible de Forge, sin tocar la
			-- economia premium. Los GEMS se dejan FUERA del faucet A PROPOSITO (decision de economia pendiente de
			-- Un grifo de premium en un modo INFINITO hay que vetarlo con el).
			-- Persisten al morir (terminarPartida -> registrarResultado -> guardar) y se ven al abrir la Forge.
			local bossNum = oleadaActual // BOSS_CADA -- que jefe del Rift es (1, 2, 3...): el Endless spawnea uno cada BOSS_CADA
			local esc = math.min(bossNum, 12) -- CAP (auditoria): el faucet de materiales NO escala infinito. A bossNum alto imprimia miles/sentada (rare -> shards de clase). Tope en el jefe 12.
			for pl in pairs(enRun) do
				local ph = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
				if ph and ph.Health > 0 then -- anti-leech: solo participantes VIVOS reciben
					local extraMat = pl:GetAttribute("Pass_extradrop") and 1.5 or 1 -- gamepass Extra Materials (+50%)
					MetaStore.darMaterial(pl, "dust", math.floor((10 + esc * 6) * extraMat))
					MetaStore.darMaterial(pl, "rare", math.floor((1 + esc) * extraMat))
					local temas = { "woods", "frost", "ember" } -- rota el tematico: el Rift alimenta TODAS las recetas
					MetaStore.darMaterial(pl, temas[(bossNum - 1) % 3 + 1], math.floor((6 + esc * 3) * extraMat))
				end
			end
			hudUpdate:FireAllClients({ wave = oleadaActual, enemiesLeft = 0, score = puntuacion, message = "RIFT BOSS DOWN - materials!" })
		else
			local lista, total = construirListaSpawn(WaveData.get(oleadaActual), coopCount())
			hudUpdate:FireAllClients({ wave = oleadaActual, enemiesLeft = total, score = puntuacion, message = esEndless and ("Wave " .. oleadaActual) or ("Act " .. actoActual .. " - Wave " .. oleadaActual) })
			for _, e in ipairs(lista) do
				if not corriendo then break end
				local afijo
				if e.afijo then -- elites FIJOS: su afijo + pueden mutar MAS (Giant Tank doble/triple)
					afijo = { e.afijo }
					local extra = tirarMutacion(oleadaActual, e.tipo)
					if extra then for _, a in ipairs(extra) do if a ~= e.afijo then afijo[#afijo + 1] = a end end end
				else
					afijo = tirarMutacion(oleadaActual, e.tipo)
				end
				-- No spawnear mientras alguien elige talento (Congelado): antes seguian APARECIENDO enemigos
				-- durante la pantalla de mejora, y parecia que el freeze no funcionaba (detectado en playtest).
				while corriendo and workspace:GetAttribute("Congelado") do task.wait(0.1) end
				if not corriendo then break end
				local modelo, humano = Enemy.spawn(e.tipo, posicionDeAparicion(), afijo)
				local recompensaCoins = modelo:GetAttribute("Cash")
				if not recompensaCoins or recompensaCoins <= 0 then recompensaCoins = Config.CoinsPorKill end
				enemigosVivos += 1
				humano.Died:Connect(function()
					enemigosVivos -= 1
					RunShop.darCoins(recompensaCoins) -- Coins por matar (run economy)
					puntuacion += SCORE.PorKill        -- score (-> Cash al terminar)
					local xpKill = XP_TIPO[e.tipo] or 1
					if afijo then xpKill *= (2 + #afijo) end -- elites dan mas XP (x3 simple / x4 doble / x5 triple)
					-- XP de EQUIPO: una sola vez por kill (con XP compartida sumaba N veces). Se atribuye a QUIEN
					-- MATA, para que su Scholar cuente solo por SUS kills (antes: participante ARBITRARIO).
					local repKill = Combat.ultimoAtacante[humano]
					if not (repKill and enRun[repKill]) then repKill = next(enRun) end
					if repKill then ganarXP(repKill, xpKill) end
					for pl in pairs(enRun) do -- kills/misiones SOLO a PARTICIPANTES vivos (anti-leech)
						local ph = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
						if ph and ph.Health > 0 then MetaStore.addKill(pl); Quests.progreso(pl, "kills", 1) end
					end
				end)
				task.wait(INTERVALO_SPAWN) -- Perf C: el HUD lo refresca el loop de conteo (~3/s), no por cada spawn/muerte (antes = decenas de remotes/frame con hordas)
			end
			while corriendo do
				local vivos = 0
				local carpeta = workspace:FindFirstChild("Enemies")
				for _, m in ipairs(carpeta and carpeta:GetChildren() or {}) do
					if m.Name == "BrainrotEnemy" then
						local h = m:FindFirstChildOfClass("Humanoid")
						if h and h.Health > 0 then vivos += 1 end
					end
				end
				enemigosVivos = vivos
				if vivos == 0 then break end
				hudUpdate:FireAllClients({ wave = oleadaActual, enemiesLeft = vivos, score = puntuacion })
				task.wait(0.3)
			end
			if not corriendo then break end
			puntuacion += SCORE.PorOleada * oleadaActual
			hudUpdate:FireAllClients({ wave = oleadaActual, enemiesLeft = 0, score = puntuacion, message = "Wave " .. oleadaActual .. " cleared!" })
		end
		-- (S1.2: los poderes ya NO salen por oleada; salen al subir de NIVEL con XP. Ver ganarXP.)
		for t = DESCANSO, 1, -1 do
			if not corriendo then break end
			hudUpdate:FireAllClients({ wave = oleadaActual, enemiesLeft = 0, score = puntuacion, message = "Next wave in " .. t .. "..." })
			task.wait(1)
		end
	end
end

local function terminarPartida()
	if not corriendo then return end
	corriendo = false
	limpiarEnemigos()
	-- (ArenaBuilder.limpiar se movio al FINAL: fix del "mapa gris al morir", ver abajo.)
	-- SNAPSHOT igual que en actoSuperado: aqui tambien hay yields (LoadCharacter, quests) y enRun no debe
	-- mutar en mitad del reparto.
	local participantes = {}
	for pl in pairs(enRun) do participantes[#participantes + 1] = pl end
	for _, pl in ipairs(participantes) do -- B3: solo participantes de la run
		if not pl.Parent then continue end
		local mult = RunState.get(pl).cashMult or 1
		local earned = math.floor(puntuacion * SCORE.CashPorPunto * mult)
		local ls = pl:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Cash")
		if cash then cash.Value += earned end
		matchEnd:FireClient(pl, { wave = oleadaActual, score = puntuacion, cash = earned })
		MetaStore.addPlayTime(pl, os.clock() - runInicio) -- tiempo jugado de por vida
		task.spawn(MetaStore.registrarResultado, pl, oleadaActual, puntuacion) -- mejor oleada/score + guardar
		Quests.progreso(pl, "wave", oleadaActual) -- Fase D: mision de oleada
		if not (esPlaceJuego and not esStudio) then pl:LoadCharacter() end -- single-place/Studio: reaparece en el LOBBY; zona de juego: se TELEPORTA directo (volverAlLobby, abajo)
	end
	ArenaBuilder.limpiar() -- FIX (mapa gris al morir): igual que en actoSuperado, limpiar al FINAL (tras reaparecer), no antes de los yields.
	volverAlLobby() -- co-op 2 places: de vuelta al lobby si estamos en el place de juego publicado
end

-- Co-op 2 places: reserva un server del place de JUEGO y teletransporta a la party del lider (con mundo/acto/dif).
local function iniciarTeleportParty(lider, wid, aid, difId)
	if _G.PartyServer and not _G.PartyServer.esLider(lider) then return end -- solo el lider dispara el teleport
	if teleportando[lider] then return end -- anti doble-PLAY: ya hay un teleport de esta party en vuelo
	teleportando[lider] = true
	-- SNAPSHOT estable: copia inmediata (NO pasar la tabla VIVA de PartyServer a un API async que hace yield -> podria mutar)
	local party = {}
	for _, m in ipairs((_G.PartyServer and _G.PartyServer.miembrosDe(lider)) or { lider }) do
		if m and m.Parent then party[#party + 1] = m end
	end
	local function avisarFallo()
		teleportando[lider] = nil
		for _, m in ipairs(party) do if m and m.Parent then matchError:FireClient(m, { reason = "teleport" }) end end
	end
	if #party == 0 then teleportando[lider] = nil; return end
	local code
	for intento = 1, 3 do
		local ok, res = pcall(function() return TeleportService:ReserveServer(Config.GamePlaceId) end)
		if ok and res then code = res; break end
		warn("[Coop] ReserveServer fallo (intento " .. intento .. "):", res)
		task.wait(intento) -- backoff 1s, 2s
	end
	if not code then avisarFallo(); return end
	-- re-filtrar por Parent tras el yield del reserve (alguien pudo salir del server)
	local vivos = {}
	for _, m in ipairs(party) do if m.Parent then vivos[#vivos + 1] = m end end
	if #vivos == 0 then teleportando[lider] = nil; return end
	-- El roster se construye con los que REALMENTE se teletransportan (tras el re-filtrado). Calculandolo ANTES
	-- del yield de ReserveServer, el place de juego se quedaba esperando 12s por alguien que ya se habia ido.
	local ids = {}
	for _, m in ipairs(vivos) do ids[#ids + 1] = m.UserId end
	local opciones = Instance.new("TeleportOptions")
	opciones.ReservedServerAccessCode = code
	-- roster = a quienes ESPERA el place de juego (fix del rezagado); lider = para poder RECONSTRUIR la party al volver
	opciones:SetTeleportData({ world = wid, act = aid, dif = difId, roster = ids, lider = lider.UserId })
	local ok2, err = pcall(function() TeleportService:TeleportAsync(Config.GamePlaceId, vivos, opciones) end)
	if not ok2 then warn("[Coop] TeleportAsync fallo:", err); avisarFallo(); return end
	task.delay(12, function() teleportando[lider] = nil end) -- failsafe: libera el lock por si el teleport no completa
end

-- PLAY: empezar la partida (teleporta a la arena y arranca las oleadas).
startMatch.OnServerEvent:Connect(function(player, worldId, actId, difId)
	-- CO-OP: en el place de JUEGO la run SOLO puede nacer del teleport (arrancarDesdeTeleport). Si se aceptara
	-- un PLAY aqui, entre que arrancarDesdeTeleport pone arrancado=true y correrPartida pone corriendo=true hay
	-- ~30s de esperas: un click lanzaba una SEGUNDA run en paralelo (doble oleadas/jefe, enRun borrado a mitad,
	-- doble premio) y ademas con el mundo/acto equivocados.
	if esPlaceJuego and not esStudio then return end
	if corriendo then return end
	if not hayJugadorVivo() then return end
	local wid = worldId or 1
	local aid = actId or 1
	if type(aid) ~= "number" or aid < 1 then return end -- B3: acto invalido
	difId = (type(difId) == "string") and difId or "normal" -- B3: dificultad debe ser string valido
	if type(wid) == "number" then
		local mundo = WorldData.porId(wid)
		if mundo == nil then return end -- B3: mundo inexistente (wid 0/negativo -> antes arrancaba Endless gratis)
		if aid > (mundo.numActos or 4) then return end -- acto fuera de rango del mundo
		if difId ~= "normal" and difId ~= "hard" and difId ~= "nightmare" then return end -- dificultad desconocida
		local wPrev = WorldData.porId(wid - 1)
		if not MetaStore.mundoDesbloqueado(player, wid, wPrev and wPrev.numActos) then return end -- mundo bloqueado
		if not MetaStore.actoDesbloqueado(player, wid, aid, difId) then return end -- acto bloqueado
		-- B3: gateo de DIFICULTAD server-side (antes solo estaba en la UI): Hard exige Normal completo; Nightmare exige Hard
		if difId == "hard" and not MetaStore.mundoCompleto(player, wid, "normal", mundo.numActos) then return end
		if difId == "nightmare" and not MetaStore.mundoCompleto(player, wid, "hard", mundo.numActos) then return end
	elseif wid == "endless" then
		local ultimo = WorldData.Lista[#WorldData.Lista]
		if not MetaStore.mundoCompleto(player, ultimo.id, "normal", ultimo.numActos) then return end -- Endless bloqueado (faltan mundos)
	else
		return -- worldId desconocido
	end
	if not correrLocal then -- lobby PUBLICADO: el PLAY del lider reserva un server del place de juego y teletransporta a la party
		iniciarTeleportParty(player, wid, aid, difId)
		return
	end
	teleportarTodosAlAnillo(Players:GetPlayers(), ARENA_POS)
	task.spawn(correrPartida, wid, aid, difId)
end)

-- Co-op 2 places: en el place de JUEGO publicado, al llegar la party (con TeleportData) arranca la run.
if correrLocal and not esStudio then
	local arrancado = false   -- ya se decidio arrancar (one-shot, NUNCA se resetea: solo evita arranques dobles)
	local arrancando = false  -- estamos DENTRO de la ventana de arranque (esperas de perfil/roster/personajes).
	                          -- Es el que mira el watchdog: 'arrancado' lo dejaria muerto para siempre.
	-- REZAGADO: si la run YA arranco y este jugador venia en el roster, engancharlo EN CALIENTE. Antes se
	-- quedaba de FANTASMA la run entera: fuera de enRun (sin HUD, sin cartas, sin premios) pero los enemigos
	-- SI le atacaban. Si no venia en el roster, se le devuelve al lobby en vez de dejarlo suelto en la arena.
	local function engancharRezagado(pl)
		if not corriendo or enRun[pl] then return end
		if not rosterRun[pl.UserId] then
			task.spawn(teleportarSeguro, Config.LobbyPlaceId, { pl }) -- no era de esta party: fuera del server reservado
			return
		end
		local tP = os.clock() -- su perfil tambien tiene que cargar o entraria sin sus upgrades permanentes
		while os.clock() - tP < 20 and not MetaStore.perfilListo(pl) do task.wait(0.15) end
		if not corriendo or enRun[pl] or not pl.Parent then return end
		prepararParticipante(pl) -- enRun + upgrades + misiones + HUD con la XP/nivel ACTUALES del equipo
		pl:LoadCharacter()
		local tC = os.clock()
		while os.clock() - tC < 6 and not (pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")) do task.wait(0.15) end
		if pl.Parent and corriendo then teleportarTodosAlAnillo({ pl }, ARENA_POS) end
	end
	local function arrancarDesdeTeleport(pl)
		if arrancado or corriendo then return end
		if not esReservado then return end -- SOLO en servers RESERVADOS: los publicos del place de juego NO arrancan runs (anti-entrada directa)
		local jd = pl:GetJoinData()
		local data = jd and jd.TeleportData
		if type(data) ~= "table" or data.world == nil then return end
		-- ESPERAR a que cargue el perfil real antes de revalidar: accesoLegitimo lee el progreso de mundos;
		-- si el perfil aun no cargo de DataStore, MetaStore.get() da uno VACIO -> rebotaria a quien SI tiene
		-- el acto desbloqueado (bug: entras a Act 2+ y te devuelve al lobby porque cree que esta bloqueado).
		-- OJO con el timeout: al teletransportar, el server de JUEGO choca con el session-lock que el LOBBY
		-- aun no ha soltado, y DataService.load puede tardar ~13-18s en resolverlo. 10s se quedaba corto.
		local tPerf = os.clock()
		while os.clock() - tPerf < 25 and not MetaStore.perfilListo(pl) do task.wait(0.15) end
		if arrancado or corriendo then return end -- otro jugador ya arranco la run mientras esperabamos el perfil
		-- Si el perfil NO llego a cargar, NO evaluar accesoLegitimo sobre datos vacios: se confundiria
		-- "no cargo el perfil" con "no tienes acceso" y este jugador no arrancaria la run por un falso negativo.
		-- Que la arranque otro miembro; si no puede nadie, el watchdog anti-zombi los devuelve al lobby.
		if not MetaStore.perfilListo(pl) then
			warn("[Coop] perfil no cargado a tiempo para", pl.Name, "- este jugador no arranca la run")
			return
		end
		-- TeleportData es SPOOFEABLE: sanitizar TIPOS + revalidar desbloqueo (server-authoritative, como startMatch)
		local wid = data.world
		local aid = (type(data.act) == "number" and data.act >= 1) and math.floor(data.act) or 1
		local difId = (data.dif == "hard" or data.dif == "nightmare") and data.dif or "normal"
		if type(wid) == "number" then
			local mundo = WorldData.porId(wid)
			if mundo == nil then return end -- world invalido/forjado -> este jugador no arranca (el watchdog anti-zombi devuelve al lobby)
			if aid > (mundo.numActos or 4) then aid = mundo.numActos or 4 end
			-- sin acceso: NO rebotar. En co-op un miembro sin el acto no debe echar a TODA la party; simplemente
			-- no arranca EL la run (el lider con acceso la arranca) y el gateo por-participante de actoSuperado
			-- ya le niega premios/desbloqueos. Si NADIE tiene acceso (data forjada), el watchdog anti-zombi rebota.
			if not accesoLegitimo(pl, mundo, aid, difId) then return end
		elseif wid ~= "endless" then
			return
		end
		arrancado = true
		arrancando = true -- abre la ventana de arranque: el watchdog no rebota a nadie mientras dure
		-- esperar a que llegue TODO el ROSTER (o timeout) antes de arrancar -> nadie de la party queda fuera de enRun
		local roster = (type(data.roster) == "table") and data.roster or {}
		table.clear(rosterRun)
		for _, uid in ipairs(roster) do if type(uid) == "number" then rosterRun[uid] = true end end -- para enganchar rezagados
		liderRun = (type(data.lider) == "number") and data.lider or nil -- para reconstruir la party al volver al lobby
		local tRoster = os.clock()
		while os.clock() - tRoster < 12 do
			local faltan = false
			for _, uid in ipairs(roster) do if not Players:GetPlayerByUserId(uid) then faltan = true; break end end
			if not faltan then break end
			task.wait(0.2)
		end
		-- personaje FRESCO para cada uno: el char teletransportado a veces llega sin control/camara (bug 'todo congelado')
		for _, p in ipairs(Players:GetPlayers()) do p:LoadCharacter() end
		local t0 = os.clock()
		while os.clock() - t0 < 6 do -- espera a que TODOS respawneen (HRP listo) o timeout
			local listos = true
			for _, p in ipairs(Players:GetPlayers()) do
				if not (p.Character and p.Character:FindFirstChild("HumanoidRootPart")) then listos = false; break end
			end
			if listos then break end
			task.wait(0.15)
		end
		task.wait(0.4) -- buffer para que el cliente ate camara/control al personaje fresco
		if corriendo then arrancando = false; return end -- alguien mas ya arranco durante nuestras esperas
		if #Players:GetPlayers() == 0 then arrancando = false; return end -- se fueron todos mientras esperabamos
		teleportarTodosAlAnillo(Players:GetPlayers(), ARENA_POS)
		task.spawn(correrPartida, wid, aid, difId) -- valores YA saneados (no data.* crudos)
		arrancando = false -- el arranque termino: a partir de aqui manda 'corriendo' y el watchdog vuelve a vigilar
	end
	-- Si la run YA corre, el que entra es un REZAGADO (se engancha en caliente o vuelve al lobby); si no, es
	-- parte del arranque normal.
	Players.PlayerAdded:Connect(function(pl)
		if corriendo then task.spawn(engancharRezagado, pl) else arrancarDesdeTeleport(pl) end
	end)
	for _, pl in ipairs(Players:GetPlayers()) do task.spawn(arrancarDesdeTeleport, pl) end

	-- Fallo ASINCRONO del teleport (Flooded/GameEnded/red): TeleportInitFailed (los pcall solo cazan el fallo SINCRONO).
	TeleportService.TeleportInitFailed:Connect(function(p2, resultado, msg)
		warn("[Coop] TeleportInitFailed:", p2 and p2.Name, tostring(resultado), msg)
		if p2 and p2.Parent then task.wait(2); teleportarSeguro(Config.LobbyPlaceId, { p2 }) end
	end)
	-- Anti-zombi: si NO corre run y quedan jugadores demasiado tiempo en el server reservado, devolverlos al lobby.
	-- OJO: tiene que respetar 'arrancado'. El arranque real puede tardar ~30s (perfil hasta 25s + roster 12s +
	-- personajes 6s), y mirando solo 'corriendo' el watchdog rebotaba a TODA la party en plena preparacion.
	-- OJO: se vigila 'arrancando' (que se apaga al terminar el arranque), NO 'arrancado'. 'arrancado' se pone a
	-- true una vez y NUNCA se resetea, asi que usarlo aqui dejaba el watchdog MUERTO PARA SIEMPRE en cuanto
	-- empezaba la primera run: si luego el teleport de vuelta al lobby agotaba sus 5 reintentos, la party se
	-- quedaba atrapada en un server reservado sin arena, sin run y sin nadie que los rescatara.
	task.spawn(function()
		task.wait(60) -- primer tick largo: cubre el peor caso de arranque sin falsos positivos
		while true do
			if not corriendo and not arrancando and #Players:GetPlayers() > 0 then
				teleportarSeguro(Config.LobbyPlaceId, Players:GetPlayers())
			end
			task.wait(30)
		end
	end)
end

-- LOBBY: el teleport lobby->juego lo INICIA este server, asi que el fallo ASINCRONO (Flooded/GameEnded/red)
-- llega AQUI, no en el place de juego. Sin este handler el lock 'teleportando' se quedaba pegado hasta el
-- failsafe de 12s y la party no recibia ningun aviso: el boton PLAY parecia muerto y sin explicacion.
if not correrLocal then
	TeleportService.TeleportInitFailed:Connect(function(p2, resultado, msg)
		warn("[Coop] TeleportInitFailed (lobby):", p2 and p2.Name, tostring(resultado), msg)
		if not (p2 and p2.Parent) then return end
		local lid = (_G.PartyServer and _G.PartyServer.liderDe(p2)) or p2
		teleportando[lid] = nil -- libera YA el anti-doble-PLAY para poder reintentar sin esperar los 12s
		matchError:FireClient(p2, { reason = "teleport" }) -- reabre el selector con aviso
	end)
end

-- El cliente pide el estado actual al cargar.
matchState.OnServerEvent:Connect(function(player)
	avisarEstado(player, (corriendo and enRun[player]) and "match" or "lobby") -- co-op: solo 'match' si es PARTICIPANTE (si no, lobby -> no fantasma)
end)

-- ===== ADMIN / DEV MENU (solo Bastian o en Studio) - testeo rapido =====
local ADMIN_ID = 0 -- configura tu UserId de Roblox (0 = menu admin solo en Studio)
-- crear-si-falta: el remote "Admin" se quito al limpiar el admin para lanzar, pero este WaitForChild en el
-- CUERPO del script colgaba TODO GameManager (yield infinito) -> el lobby/bucle no arrancaba. Nunca hagas
-- WaitForChild en el cuerpo de un script de algo que pueda faltar en un place.
local adminRemote = remotes:FindFirstChild("Admin") or Instance.new("RemoteEvent")
adminRemote.Name = "Admin"; adminRemote.Parent = remotes
local function esAdmin(p) return game:GetService("RunService"):IsStudio() or p.UserId == ADMIN_ID end
adminRemote.OnServerEvent:Connect(function(player, accion, valor, valor2, valor3)
	if not esAdmin(player) then return end
	if accion == "xp" then
		ganarXP(player, valor or 200)
	elseif accion == "cash" then
		local ls = player:FindFirstChild("leaderstats"); local c = ls and ls:FindFirstChild("Cash")
		if c then c.Value += (valor or 10000) end
	elseif accion == "gems" then
		local ls = player:FindFirstChild("leaderstats"); local g = ls and ls:FindFirstChild("Gems")
		if g then g.Value += (valor or 1000) end
	elseif accion == "combo" then
		RunState.aplicar(player, "fuego"); RunState.aplicar(player, "tamano1") -- receta evo Mage
	elseif accion == "evo" then -- valor = clase: cambia a esa clase + da su receta de evolucion
		local evo = EvolutionData.porClase(valor)
		if evo then
			local d = MetaStore.get(player)
			d.claseActual = evo.clase
			d.claseNivel[evo.clase] = math.max(d.claseNivel[evo.clase] or 0, 1)
			local ch = player.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if ch then for _, t in ipairs(ch:GetChildren()) do if t:IsA("Tool") then t:Destroy() end end end
			local bp = player:FindFirstChildOfClass("Backpack")
			if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then t:Destroy() end end end
			MetaStore.darArmas(player)
			local nuevaTool = bp and bp:FindFirstChildOfClass("Tool")
			if hum and nuevaTool then hum:EquipTool(nuevaTool) end
			for _, id in ipairs(evo.receta) do RunState.aplicar(player, id) end
		end
	elseif accion == "luck" then
		local m = RunState.get(player); m.suerte = (m.suerte or 0) + (valor or 25); RunState.sync(player)
	elseif accion == "god" then
		local m = RunState.get(player); m.invulnerable = not m.invulnerable; RunState.sync(player)
	elseif accion == "killall" then
		limpiarEnemigos()
	elseif accion == "mat" then -- TESTEO: da materiales de crafteo (valor = cantidad de cada uno)
		for _, mm in ipairs({ "woods", "frost", "ember", "rare" }) do MetaStore.darMaterial(player, mm, valor or 50) end
		MetaStore.guardar(player)
	elseif accion == "unlockevos" then -- DEV: desbloquea TODAS las evos (probar la Forge/gate)
		for _, e in ipairs(EvolutionData.Lista) do MetaStore.desbloquearEvo(player, e.id) end
	elseif accion == "boss" then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local pos = hrp and (hrp.Position + Vector3.new(0, 6, 28)) or Vector3.new(0, 8, -RADIO_SPAWN)
		Boss.spawn(BOSSES[valor or 1], pos)
	elseif accion == "resetperks" then -- quita TODAS las mejoras permanentes (testeo de balance limpio)
		local d = MetaStore.get(player)
		d.upgrades = {}
		MetaStore.sync(player)
		MetaStore.guardar(player)
	elseif accion == "size" then -- FUN: escala el personaje (valor = multiplicador; 1 = normal). Se resetea al reaparecer.
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then
			local s = math.clamp(valor or 1, 0.2, 12)
			for _, n in ipairs({ "BodyDepthScale", "BodyHeightScale", "BodyWidthScale", "HeadScale" }) do
				local v = hum:FindFirstChild(n)
				if v and v:IsA("NumberValue") then v.Value = s end
			end
		end
	elseif accion == "speed" then -- FUN: velocidad de caminar (valor = walkspeed). Se resetea al reaparecer.
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = math.clamp(valor or 16, 0, 250) end
	elseif accion == "heal" then -- FUN/util: cura al maximo
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = hum.MaxHealth end
	elseif accion == "world" then -- TESTEO: arranca un MUNDO concreto (valor = id del mundo)
		if not corriendo and hayJugadorVivo() then
			teleportarTodosAlAnillo(Players:GetPlayers(), ARENA_POS)
			task.spawn(correrPartida, valor or 1, valor2 or 1, valor3)
		end
	end
end)

-- ===== Smn: REVIVIR PAGANDO al morir (consumible, developer product) =====
local function revivirJugador(player)
	if not player or not player.Parent then return end
	hudUpdate:FireClient(player, { message = "REVIVED!" })
	player:LoadCharacter()
	task.wait(0.3) -- darAlSpawn (CharacterAdded) re-da el arma sola
	-- Antes esto era teleportar(player, ARENA_POS), o sea el CENTRO del mapa. Con la arena pequena valia, pero
	-- ahora el radio es 600 y en un survivors kiteas hacia fuera todo el acto: revivias SOLO y a cientos de
	-- studs de la pelea. Y peor: posicionDeAparicion() elige un jugador vivo al azar como ancla, asi que te
	-- spawneaba tu cuota de horda encima estando aislado. Ahora reapareces JUNTO A UN COMPANERO VIVO.
	local destino = ARENA_POS
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player and enRun[pl] then
			local ohrp = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			local ohum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
			if ohrp and ohum and ohum.Health > 0 then destino = ohrp.Position + Vector3.new(6, 0, 6); break end
		end
	end
	teleportar(player, destino)
	RunState.aplicarAlPersonaje(player) -- restaura vida/velocidad del build
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = hum.MaxHealth end
	-- B4: re-aplicar la EVOLUCION del arma si el build la tenia (antes el revive daba el arma BASE y ya no re-evolucionaba)
	if RunState.get(player).evolucionado then
		local evo = EvolutionData.porClase(MetaStore.get(player).claseActual)
		local toolEvo = player.Character and player.Character:FindFirstChildOfClass("Tool")
		if evo and toolEvo then
			toolEvo.Name = evo.armaEvo
			if not WeaponVisuals.aplicar(toolEvo, evo.armaEvo) then
				local h = toolEvo:FindFirstChild("Handle")
				if h then h.Color = evo.color end
			end
		end
	end
	local m = RunState.get(player); m.invulnerable = true
	task.delay(REVIVE_INVULN, function() m.invulnerable = false end)
end

-- Al morir en plena run: ofrece revivir pagando. Espera la decision sin terminar la run de golpe.
local function ofrecerContinuar(player)
	if not corriendo then return end
	if not enRun[player] then return end -- no es participante (rezagado/fantasma): no ofrecerle revive de PAGO
	if revEsperando[player] then return end
	if MetaStore.useReviveCredito(player) then -- B4: usar un revive PAGADO pendiente (persistente) sin volver a cobrar
		revivirJugador(player)
		return
	end
	revEsperando[player] = true
	revPagado[player] = nil; revRendido[player] = nil; revComprando[player] = nil
	reviveOffer:FireClient(player, { segundos = REVIVE_TIMEOUT })
	local t0 = os.clock()
	while revEsperando[player] and corriendo do
		if revPagado[player] then
			revEsperando[player] = nil
			reviveOffer:FireClient(player, { close = true })
			revivirJugador(player)
			return
		end
		if revRendido[player] then break end
		local limite = revComprando[player] and 40 or REVIVE_TIMEOUT -- si esta comprando, espera mas a que resuelva el pago
		if (os.clock() - t0) >= limite then break end
		task.wait(0.15)
	end
	revEsperando[player] = nil
	reviveOffer:FireClient(player, { close = true })
	-- Si la RUN ya termino mientras esperabamos (acto superado / game over), NO tocar nada aqui: el flujo de fin
	-- de run (actoSuperado/terminarPartida) ya premia a los participantes y los devuelve al lobby. Cayendo a la
	-- rama de abajo nos borrabamos de enRun y nos teleportabamos EN MITAD del reparto -> se perdia el clear del
	-- acto y toda su recompensa (Cash/Gems/materiales/progreso).
	if not corriendo then return end
	if not hayParticipanteVivo() then
		terminarPartida() -- nadie vivo en la run -> fin (recompensa + LoadCharacter a los participantes)
	elseif player.Parent then
		enRun[player] = nil -- co-op: se rindio -> FUERA de la run (ya no cuenta para fin/premios)
		if esPlaceJuego and not esStudio then
			task.spawn(teleportarSeguro, Config.LobbyPlaceId, { player }) -- co-op 2 places: DIRECTO al lobby real (con reintentos)
		else
			player:LoadCharacter() -- Studio/single-place: reaparece en el area del lobby
			task.spawn(function()
				player.CharacterAdded:Wait(); task.wait(0.2)
				if player.Parent then teleportar(player, LOBBY_POS); avisarEstado(player, "lobby") end
			end)
		end
	end
end

-- Decision del cliente: buy (inicio compra), cancel (cerro el popup), giveup (rendirse).
reviveDecision.OnServerEvent:Connect(function(player, accion)
	if accion == "buy" then revComprando[player] = true
	elseif accion == "cancel" then revComprando[player] = nil
	elseif accion == "giveup" then revRendido[player] = true end
end)

-- La compra del consumible (ProcessReceipt en MonetizationServer) avisa aqui.
reviveCompradoEvt.Event:Connect(function(player)
	if revEsperando[player] then
		revPagado[player] = true -- el loop de ofrecerContinuar lo recoge
	elseif corriendo and enRun[player] then
		revivirJugador(player) -- compro justo despues de cerrarse la oferta pero sigue en la run
	else
		-- B4: no se puede revivir ahora (run acabada / no en run) -> revive GRATIS para la proxima muerte
		MetaStore.addReviveCredito(player, 1) -- persiste en el perfil (no se pierde al salir)
		hudUpdate:FireClient(player, { message = "Free revive saved for next death!" })
	end
end)

local function configurarPersonaje(player, char)
	for _, p in ipairs(char:GetDescendants()) do -- colision: el jugador a su grupo "Jugadores" (los enemigos lo ATRAVIESAN, no lo empujan -> fix del tiron al acercarse)
		if p:IsA("BasePart") then p.CollisionGroup = "Jugadores" end
	end
	char.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then d.CollisionGroup = "Jugadores" end end)
	local hum = char:WaitForChild("Humanoid")
	hum.Died:Connect(function()
		-- Smn: al morir en plena run -> ofrece revivir pagando (consumible) en vez de terminar de golpe.
		if corriendo then
			task.spawn(ofrecerContinuar, player)
			return
		end
		task.wait(0.2)
		if not hayParticipanteVivo() then terminarPartida() end
	end)
	task.wait(0.4)
	avisarEstado(player, (corriendo and enRun[player]) and "match" or "lobby") -- solo 'match' si es PARTICIPANTE (no fantasma que pelea sin cobrar)
end

local function configurarJugador(player)
	player.CharacterAdded:Connect(function(char) configurarPersonaje(player, char) end)
	if player.Character then
		task.spawn(configurarPersonaje, player, player.Character)
	else
		player:LoadCharacter()
	end
end

Players.PlayerAdded:Connect(configurarJugador)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(configurarJugador, pl)
end

-- Auditoria B2: al SALIR un jugador, limpiar su estado por-run y evitar run fantasma / juego congelado.
Players.PlayerRemoving:Connect(function(player)
	picks[player] = nil        -- corta su bucle de eleccion de carta -> el cleanup de ofrecerPoderes lo salta y descongela
	revEsperando[player] = nil  -- corta su oferta de revive si estaba abierta
	revPagado[player] = nil
	revRendido[player] = nil
	revComprando[player] = nil
	enRun[player] = nil -- B3: sale de la lista de participantes
	teleportando[player] = nil -- co-op: libera el lock de teleport si el lider se va
	-- reviveCredito ya no vive en memoria (persiste en el perfil)
	-- si se va y la run se queda sin NADIE vivo, terminarla (si no, corriendo=true + enemigos eternos = run zombi)
	if corriendo then
		task.delay(1.5, function() -- espera a que el jugador salga de Players y su Character se destruya
			if corriendo and not hayParticipanteVivo() then terminarPartida() end
		end)
	end
end)
