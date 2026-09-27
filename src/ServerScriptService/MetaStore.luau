-- MetaStore (ModuleScript del SERVIDOR) · FASE 6 - progreso PERMANENTE entre partidas.
-- Guarda por jugador: niveles de mejoras (UpgradeData) y armas compradas. Lo gasta el
-- jugador con Cash (server-authoritative). Al empezar partida, aplica las mejoras como
-- BASE de la build (RunState). De momento es EN MEMORIA; la Fase 7 lo enchufa a DataService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local UpgradeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("UpgradeData"))
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponData"))
local ClassData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ClassData"))
local Badges = require(script.Parent:WaitForChild("Badges")) -- logros (badges de Roblox)
local RunState = require(ServerScriptService:WaitForChild("RunState"))
local DataService = require(ServerScriptService:WaitForChild("DataService"))
local Leaderboard = require(ServerScriptService:WaitForChild("Leaderboard"))
local CraftData = require(game:GetService("ReplicatedStorage"):WaitForChild("Data"):WaitForChild("CraftData"))
local templates = game:GetService("ServerStorage"):WaitForChild("WeaponTemplates")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shopSync = remotes:WaitForChild("ShopSync")
local buyUpgrade = remotes:WaitForChild("BuyUpgrade")
local buyWeapon = remotes:WaitForChild("BuyWeapon")
local selectClass = remotes:WaitForChild("SelectClass")
local gachaSpin = remotes:WaitForChild("GachaSpin")
local gachaSync = remotes:WaitForChild("GachaSync")
local profileSync = remotes:WaitForChild("ProfileSync")
-- OJO: aqui NO se puede usar WaitForChild. Esta linea corre en el CUERPO del modulo, asi que si el remote no
-- existe en ese place, require(MetaStore) NUNCA retorna y arrastra a GameManager, CraftServer y
-- MonetizationServer con el: el server se queda muerto sin un solo error. Y es un riesgo real, no teorico: el
-- co-op son DOS places (lobby + juego) = dos datamodels distintos, y SettingsSync se creo A MANO en uno solo
-- (BuildInstances no corre en runtime). Se usa el mismo patron seguro que rankReward: crearlo si falta.
local settingsSync = remotes:FindFirstChild("SettingsSync") or Instance.new("RemoteEvent")
settingsSync.Name = "SettingsSync"; settingsSync.Parent = remotes
local rankReward = remotes:FindFirstChild("RankReward") or Instance.new("RemoteEvent") -- premio de ranking semanal (server->client popup)
rankReward.Name = "RankReward"; rankReward.Parent = remotes

-- ===== Gacha (S2 / Parte B) =====
local SPIN_COST = 100      -- Gems por tirada
local STARTING_SPINS = 2   -- tiradas GRATIS de regalo para cuentas nuevas (en vez de Gems)
local BOSS_GEMS = 25       -- Gems por derrotar un jefe
local PITY = 8             -- tiradas seguidas sin clase nueva -> garantiza una no poseida

local MetaStore = {}
local datos = {} -- datos[player] = { upgrades = {id=nivel}, ownedWeapons = {Nombre=true}, bestWave, bestScore }
local cargadoOk = {} -- cargadoOk[player] = la carga de DataStore fue bien (si no, NO guardar)
local listo = {} -- listo[player] = init() termino de cargar (no guardar/operar antes)

local function nuevo()
	-- S2: empiezas con tu CLASE (no armas de fuego). ownedWeapons queda como legacy.
	return { upgrades = {}, ownedWeapons = {}, claseActual = ClassData.PorDefecto,
		claseNivel = { [ClassData.PorDefecto] = 1 }, claseShards = {}, spinsSinNueva = 0,
		tiradasGratis = STARTING_SPINS, ultimoDiario = 0,
		totalKills = 0, runsPlayed = 0, playTime = 0, comprasHechas = {}, mundosSuperados = {}, progresoMundos = {}, materiales = {}, reliquias = {}, equipadas = {}, consumibles = {}, consumiblesUsar = {}, packsComprados = {}, semanaPremiada = 0, reviveCredito = 0, evoDesbloq = {}, ajustes = {} } -- arrancas con Mage nivel 1 + 2 tiradas gratis
end

function MetaStore.get(player)
	if not datos[player] then datos[player] = nuevo() end -- (Fase 7: cargar de DataService)
	return datos[player]
end

-- Evo gating: ¿el perfil esta cargado y en modo ESCRITURA? (para no gastar Gems/materiales que no persistirian)
function MetaStore.puedeOperar(player)
	return listo[player] == true and cargadoOk[player] == true
end
-- Perfil CARGADO (init termino), aunque sea solo-lectura. Para ESPERAR antes de aplicar upgrades (fix co-op).
function MetaStore.perfilListo(player)
	return listo[player] == true
end
-- Evo gating: desbloquea permanentemente una evolucion (por evo.id). Idempotente + persiste.
function MetaStore.desbloquearEvo(player, evoId)
	local d = MetaStore.get(player)
	d.evoDesbloq = d.evoDesbloq or {}
	if not d.evoDesbloq[evoId] then
		d.evoDesbloq[evoId] = true
		Badges.otorgar(player, "evo") -- logro: primera evolucion de arma desbloqueada
		MetaStore.guardar(player)
	end
	return true
end

function MetaStore.tieneArma(player, nombre)
	return MetaStore.get(player).ownedWeapons[nombre] == true
end

-- Da un arma (clona la plantilla a la mochila) si no la tiene ya guardada/equipada.
local function darUnArma(player, nombre)
	local tpl = templates:FindFirstChild(nombre)
	local bp = player:FindFirstChildOfClass("Backpack")
	if not (tpl and bp) then return end
	local tool = (player.Character and player.Character:FindFirstChild(nombre)) or bp:FindFirstChild(nombre)
	if not tool then tool = tpl:Clone(); tool.Parent = bp end
	-- auto-equipar: survivors = siempre con el arma en mano, nunca spawneas sin arma
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and tool.Parent ~= player.Character then hum:EquipTool(tool) end
end

-- S2: da el ARMA DE LA CLASE actual (al reaparecer). Las clases REEMPLAZAN a las armas de fuego.
function MetaStore.darArmas(player)
	local d = MetaStore.get(player)
	local clase = ClassData.porId(d.claseActual) or ClassData.porId(ClassData.PorDefecto)
	if clase then darUnArma(player, clase.arma) end
end

-- Aplica TODAS las mejoras como BASE de la build (sobre RunState) + refleja en el personaje.
function MetaStore.aplicarA(player)
	if not listo[player] then return end -- CRITICO: no aplicar sobre un perfil a MEDIO cargar (aplicaria upgrades vacias -> danoMult=1)
	local m = RunState.get(player)
	local d = MetaStore.get(player)
	for _, up in ipairs(UpgradeData.Lista) do
		local lvl = d.upgrades[up.id] or 0
		if lvl > 0 then up.aplicar(m, lvl) end
	end
	-- Scr: reliquias equipadas (bonus permanente, escala por nivel)
	for _, id in ipairs(d.equipadas or {}) do
		local r = CraftData.porId(id)
		if r then r.aplicar(m, (d.reliquias and d.reliquias[id]) or 1) end
	end
	-- Scr: consumibles activados (boost de 1 RUN): consume 1 + aplica (aplicarA = inicio de run)
	for _, id in ipairs(d.consumiblesUsar or {}) do
		if d.consumibles and (d.consumibles[id] or 0) > 0 then
			local cons = CraftData.consumiblePorId(id)
			if cons then cons.aplicar(m); d.consumibles[id] = d.consumibles[id] - 1 end
		end
	end
	-- S2: pasiva de la CLASE (escala por nivel; los duplicados del gacha suben el nivel).
	local clase = ClassData.porId(d.claseActual)
	if clase then
		clase.pasiva(m, d.claseNivel[d.claseActual] or 1)
		if clase.velMult then m.velocidadMult *= clase.velMult end -- velocidad base de la clase (no escala por nivel)
	end
	if player:GetAttribute("Pass_cash2x") then m.cashMult = (m.cashMult or 1) * 2 end -- Smn: gamepass 2x Cash (dobla el Cash meta de la run)
	RunState.aplicarAlPersonaje(player)
	RunState.sync(player)
end

-- Scr: suma materiales de crafteo (lo llama GameManager al superar acto/jefe). NO guarda aqui
-- (el flujo de fin de run ya guarda); solo muta el perfil en memoria.
function MetaStore.darMaterial(player, tipo, cantidad)
	if not tipo or cantidad <= 0 then return end
	local d = MetaStore.get(player)
	d.materiales = d.materiales or {}
	d.materiales[tipo] = (d.materiales[tipo] or 0) + cantidad
end

-- Avisa al cliente del estado de su tienda (niveles de mejoras + armas).
function MetaStore.sync(player)
	local d = MetaStore.get(player)
	shopSync:FireClient(player, {
		upgrades = UpgradeData.infoDe(d.upgrades),
		ownedWeapons = d.ownedWeapons,
	})
end

-- Construye el perfil actual y lo guarda (no sobreescribe si la carga fallo).
function MetaStore.guardar(player)
	local d = datos[player]
	if not d then return false end
	if not listo[player] then return false end -- no guardar un perfil a medio cargar
	-- Sincroniza el espejo desde leaderstats.Value (SIEMPRE actual, aun con SignalBehavior=Deferred que retrasa
	-- el .Changed): un grant reciente (gems.Value += n) + guardar() en el mismo frame guardaria el valor VIEJO.
	local lsSync = player:FindFirstChild("leaderstats")
	if lsSync then
		local c = lsSync:FindFirstChild("Cash"); if c then d.cash = c.Value end
		local g = lsSync:FindFirstChild("Gems"); if g then d.gems = g.Value end
	end
	return DataService.save(player, {
		version = 1,
		cash = d.cash or 0,   -- espejo en 'd', no leaderstats (puede no existir al salir -> guardaria 0)
		gems = d.gems or 0,
		upgrades = d.upgrades,
		ownedWeapons = d.ownedWeapons,
		claseActual = d.claseActual,
		claseNivel = d.claseNivel,
		claseShards = d.claseShards,
		spinsSinNueva = d.spinsSinNueva,
		tiradasGratis = d.tiradasGratis,
		ultimoDiario = d.ultimoDiario,
		totalKills = d.totalKills,
		runsPlayed = d.runsPlayed,
		playTime = d.playTime,
		comprasHechas = d.comprasHechas,
		bestWave = d.bestWave or 0,
		bestScore = d.bestScore or 0,
		mundosSuperados = d.mundosSuperados or {},
		progresoMundos = d.progresoMundos or {},
		packsComprados = d.packsComprados or {},
		semanaPremiada = d.semanaPremiada or 0,
		reviveCredito = d.reviveCredito or 0,
		evoDesbloq = d.evoDesbloq or {}, -- Evo gating: evoluciones desbloqueadas (por evo.id)
		ajustes = d.ajustes or {}, -- Sju: volumen/toggles del jugador (antes se perdian al salir)
		streak = d.streak, lastLogin = d.lastLogin, streakClaim = d.streakClaim,
		questDay = d.questDay, quests = d.quests, -- Fase D (racha + misiones)
		materiales = d.materiales, reliquias = d.reliquias, equipadas = d.equipadas,
		consumibles = d.consumibles, consumiblesUsar = d.consumiblesUsar, -- Scr (crafteo)
	}, cargadoOk[player])
end

-- Al terminar una run: actualiza mejor oleada/score, sube al ranking y guarda.
function MetaStore.registrarResultado(player, wave, score)
	local d = MetaStore.get(player)
	if wave and wave > (d.bestWave or 0) then d.bestWave = wave end
	if score and score > (d.bestScore or 0) then d.bestScore = score end -- record de por vida (perfil)
	if score and score > 0 then Leaderboard.registrar(player.UserId, score) end -- SIEMPRE al ranking (weekly/all-time UpdateAsync max = mejor de cada periodo)
	-- Boards MULTIPLES (semicirculo del lobby): records (score/wave) + balances actuales (gems/horas/runs).
	local lsRR = player:FindFirstChild("leaderstats")
	local gemsRR = (lsRR and lsRR:FindFirstChild("Gems") and lsRR.Gems.Value) or d.gems or 0
	Leaderboard.registrarStats(player.UserId, {
		score = d.bestScore, wave = d.bestWave, gems = gemsRR,
		minutos = math.floor((d.playTime or 0) / 60), runs = d.runsPlayed or 0,
	})
	MetaStore.guardar(player)
end

-- Comprar una subida de mejora permanente (valida Cash en el SERVIDOR).
buyUpgrade.OnServerEvent:Connect(function(player, id)
	if not listo[player] or not cargadoOk[player] then return end -- perfil cargando / solo-lectura: no gastar (no persistiria)
	local up = UpgradeData.porId(id)
	if not up then return end
	local d = MetaStore.get(player)
	local lvl = d.upgrades[id] or 0
	if lvl >= up.maxLevel then return end
	local cost = UpgradeData.costDe(up, lvl)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if not cash or cash.Value < cost then return end
	cash.Value -= cost
	d.upgrades[id] = lvl + 1
	MetaStore.sync(player)
end)

-- Comprar un ARMA con Cash (server-authoritative): valida, descuenta, marca y la entrega ya.
buyWeapon.OnServerEvent:Connect(function(player, nombre)
	do return end -- B5: armas de fuego LEGACY deshabilitadas (el handler permitia darse un arma gratis via remote; la pestana de armas es inalcanzable). Se limpia del todo en B6.
	if not listo[player] or not cargadoOk[player] then return end -- perfil cargando / solo-lectura: no gastar
	local arma = WeaponData[nombre]
	if not arma then return end
	local d = MetaStore.get(player)
	if d.ownedWeapons[nombre] then return end -- ya la tienes
	local precio = arma.Precio or 0
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	if not cash or cash.Value < precio then return end
	cash.Value -= precio
	d.ownedWeapons[nombre] = true
	darUnArma(player, nombre)
	MetaStore.sync(player)
end)

-- S2 (selector temporal de clase): el jugador elige su CLASE en el lobby; le damos su arma al momento.
selectClass.OnServerEvent:Connect(function(player, claseId)
	if not listo[player] then return end -- perfil aun cargando: no operar
	if ClassData.porId(claseId) == nil then return end
	local d = MetaStore.get(player)
	if (d.claseNivel[claseId] or 0) < 1 then return end -- solo puedes equipar clases que POSEES (gacha)
	d.claseActual = claseId
	local ch = player.Character
	if ch then for _, t in ipairs(ch:GetChildren()) do if t:IsA("Tool") then t:Destroy() end end end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then t:Destroy() end end end
	MetaStore.darArmas(player)
	MetaStore.sync(player)
end)

-- ===== GACHA (Parte B): tirada server-authoritative + sync de coleccion =====
-- Envia al cliente su coleccion (clases con nivel + shards), Gems y la clase equipada.
-- Smn: recompensas DIARIAS del gamepass VIP (se reclaman en el daily del gacha).
local VIP_GEMS_DIA = 50 -- +50 Gems al dia
function MetaStore.syncGacha(player)
	local d = MetaStore.get(player)
	-- DIARIO: 1 tirada gratis por dia (se reclama al abrir el gacha)
	local dia = math.floor(os.time() / 86400)
	local dailyNuevo = false
	if dia > (d.ultimoDiario or 0) then
		d.ultimoDiario = dia
		d.tiradasGratis = (d.tiradasGratis or 0) + 1
		dailyNuevo = true
		if player:GetAttribute("Pass_vip") then -- Smn: recompensas diarias del VIP (gamepass)
			-- CUMPLIMIENTO paid random items: la tirada gratis diaria del VIP es un OBJETO ALEATORIO, y a un
			-- jugador restringido no se le puede entregar como parte del valor de un producto de PAGO. Las Gems
			-- diarias si se le dan: son moneda, y ademas sirven para desbloquear evoluciones en la Forja, que
			-- no tienen nada de aleatorio.
			-- El atributo lo pone PolicyServer consultando a PolicyService, con default TRUE (restringido)
			-- hasta que Roblox conteste: si algo falla, se peca de prudente.
			if player:GetAttribute("PaidRandomRestricted") == false then
				d.tiradasGratis += 1
			end
			local ls = player:FindFirstChild("leaderstats"); local gems = ls and ls:FindFirstChild("Gems")
			if gems then gems.Value += VIP_GEMS_DIA end
		end
		MetaStore.guardar(player)
	end
	gachaSync:FireClient(player, { nivel = d.claseNivel, shards = d.claseShards, claseActual = d.claseActual,
		tiradasGratis = d.tiradasGratis, spinsSinNueva = d.spinsSinNueva or 0, pity = PITY, dailyNuevo = dailyNuevo })
end

-- Una tirada: cobra Gems, elige clase (con pity), aplica a la coleccion. Devuelve el resultado (o nil).
local function hacerSpin(player)
	local d = MetaStore.get(player)
	-- primero gasta una tirada GRATIS si la tiene; si no, cobra Gems
	if (d.tiradasGratis or 0) > 0 then
		d.tiradasGratis -= 1
	else
		local ls = player:FindFirstChild("leaderstats")
		local gems = ls and ls:FindFirstChild("Gems")
		if not gems or gems.Value < SPIN_COST then return nil end
		gems.Value -= SPIN_COST
	end
	-- pity: si lleva PITY tiradas sin clase nueva y hay no poseidas, fuerza una no poseida
	local noPoseidas = {}
	for _, c in ipairs(ClassData.Lista) do
		if (d.claseNivel[c.id] or 0) < 1 then noPoseidas[#noPoseidas + 1] = c.id end
	end
	local claseId
	if (d.spinsSinNueva or 0) >= PITY and #noPoseidas > 0 then
		claseId = noPoseidas[math.random(#noPoseidas)]
	else
		claseId = ClassData.elegirAleatoria()
	end
	-- aplicar: clase nueva -> desbloquea; repetida -> shard (y sube nivel si llega al coste)
	local res = { claseId = claseId, isNew = false, leveledUp = false }
	local nivelAntes = d.claseNivel[claseId] or 0
	if nivelAntes < 1 then
		d.claseNivel[claseId] = 1
		d.spinsSinNueva = 0
		res.isNew = true
	else
		d.spinsSinNueva = (d.spinsSinNueva or 0) + 1
		d.claseShards[claseId] = (d.claseShards[claseId] or 0) + 1
		local costo = ClassData.ShardsParaSubir[nivelAntes]
		if costo and nivelAntes < ClassData.NivelMax and d.claseShards[claseId] >= costo then
			d.claseShards[claseId] -= costo
			d.claseNivel[claseId] = nivelAntes + 1
			res.leveledUp = true
		end
	end
	res.nivel = d.claseNivel[claseId]
	res.shards = d.claseShards[claseId] or 0
	local c = ClassData.porId(claseId)
	res.rareza = c and c.rareza
	res.nombre = c and c.nombre
	res.color = c and c.color
	res.tiradasGratis = d.tiradasGratis
	-- LOGROS (badges de Roblox): 1a clase Legendary, subir una al MAX, tenerlas todas. Ids en Badges.IDS (0 = no otorga).
	if res.isNew and c and c.rareza == "Legendary" then Badges.otorgar(player, "legendary") end
	if (res.nivel or 0) >= ClassData.NivelMax then Badges.otorgar(player, "maxClase") end
	local todas = true
	for _, cl in ipairs(ClassData.Lista) do if (d.claseNivel[cl.id] or 0) < 1 then todas = false; break end end
	if todas then Badges.otorgar(player, "todasClases") end
	return res -- guardar lo hace el handler (1 sola vez, tambien en x10)
end

gachaSpin.OnServerEvent:Connect(function(player, count)
	if player:GetAttribute("PaidRandomRestricted") ~= false then gachaSpin:FireClient(player, nil); return end -- CUMPLIMIENTO paid random items: bloquea el gacha a jugadores restringidos (o antes de comprobar la policy). Solo pasa si es explicitamente false
	if not listo[player] or not cargadoOk[player] then gachaSpin:FireClient(player, nil); return end -- perfil cargando / solo-lectura: no gastar Gems que no persistirian (el cliente no se queda en ROLLING eterno)
	local maxSpins = player:GetAttribute("Pass_x3") and 10 or 1 -- x10 SOLO con el gamepass x3 (server-authoritative, no fiarse del cliente)
	count = math.clamp(tonumber(count) or 1, 1, maxSpins)
	if count == 1 then
		local res = hacerSpin(player)
		if res then MetaStore.guardar(player) end
		gachaSpin:FireClient(player, res) -- nil = sin Gems/tiradas
		if res then MetaStore.syncGacha(player) end
	else
		local results = {}
		for _ = 1, count do
			local r = hacerSpin(player)
			if not r then break end
			results[#results + 1] = r
		end
		if #results > 0 then MetaStore.guardar(player) end
		gachaSpin:FireClient(player, { multi = results })
		MetaStore.syncGacha(player)
	end
end)

gachaSync.OnServerEvent:Connect(function(player)
	MetaStore.syncGacha(player)
end)

-- Gems por derrotar un jefe (lo llama GameManager).
function MetaStore.darGemsJefe(player, cantidad)
	local ls = player:FindFirstChild("leaderstats")
	local gems = ls and ls:FindFirstChild("Gems")
	local mult = player:GetAttribute("Pass_gems2x") and 2 or 1 -- Smn: gamepass 2x Gems
	if gems then gems.Value += (cantidad or BOSS_GEMS) * mult end -- cantidad = Gems del jefe escaladas por dificultad (20/30/45); repetible
end

-- Smn: credito de revive PAGADO que no se pudo aplicar (persistente en el perfil, no se pierde al salir).
function MetaStore.addReviveCredito(player, n)
	local d = datos[player]; if not d then return end
	d.reviveCredito = (d.reviveCredito or 0) + (n or 1)
	MetaStore.guardar(player)
end
function MetaStore.useReviveCredito(player)
	local d = datos[player]; if not d or (d.reviveCredito or 0) <= 0 then return false end
	d.reviveCredito -= 1
	MetaStore.guardar(player)
	return true
end

-- Da Gems al jugador (compra con Robux). IDEMPOTENTE por PurchaseId. Devuelve true si OK.
function MetaStore.darGems(player, cantidad, purchaseId)
	if not listo[player] or not cargadoOk[player] then return false end -- perfil no cargado / solo lectura: que Roblox reintente el recibo
	local d = MetaStore.get(player)
	d.comprasHechas = d.comprasHechas or {}
	if purchaseId and d.comprasHechas[purchaseId] then return true end -- ya procesada (no duplicar)
	local ls = player:FindFirstChild("leaderstats")
	local gems = ls and ls:FindFirstChild("Gems")
	if not gems then return false end
	gems.Value += cantidad
	if purchaseId then d.comprasHechas[purchaseId] = true end
	if not MetaStore.guardar(player) then
		-- NO revertir ni limpiar la marca (audit): si los Gems se GASTARON durante el yield de guardar, revertir
		-- (clamp a 0) + reintentar el recibo DUPLICABA. Dejamos Gems + marca en memoria; el reintento de Roblox
		-- vera la marca (return true de arriba) y NO re-otorga, y los Gems persisten en el proximo guardado
		-- (compra / fin de run / salida -> PlayerRemoving guarda antes de irse). Preferimos NO duplicar.
		return false
	end
	return true
end

-- Para productos de EFECTO sin moneda (revive): marca el recibo como procesado, IDEMPOTENTE por PurchaseId.
-- Devuelve "nuevo" (1a vez -> aplicar el efecto), "repetido" (ya procesado -> NO reaplicar) o "reintentar"
-- (perfil no cargado). Si guardar falla NO limpia la marca (evita doble-efecto en el reintento del recibo).
function MetaStore.marcarReciboEfecto(player, purchaseId)
	if not listo[player] or not cargadoOk[player] then return "reintentar" end
	local d = MetaStore.get(player)
	d.comprasHechas = d.comprasHechas or {}
	if purchaseId and d.comprasHechas[purchaseId] then return "repetido" end
	if purchaseId then d.comprasHechas[purchaseId] = true end
	MetaStore.guardar(player) -- si falla, la marca queda en memoria (el reintento la vera como "repetido")
	return "nuevo"
end

-- Entrega el contenido de un PACK de la tienda (dev product). IDEMPOTENTE por purchaseId. oneTime = solo 1 vez.
function MetaStore.darPack(player, pack, purchaseId)
	if not listo[player] or not cargadoOk[player] then return false end -- perfil no cargado / solo lectura: que Roblox reintente el recibo
	local d = MetaStore.get(player)
	d.comprasHechas = d.comprasHechas or {}
	if purchaseId and d.comprasHechas[purchaseId] then return true end -- recibo ya procesado
	d.packsComprados = d.packsComprados or {}
	if pack.oneTime and d.packsComprados[pack.id] then
		if purchaseId then d.comprasHechas[purchaseId] = true end -- consume el recibo pero NO da de nuevo
		if not MetaStore.guardar(player) then if purchaseId then d.comprasHechas[purchaseId] = nil end return false end
		return true
	end
	local ls = player:FindFirstChild("leaderstats")
	local gemsSt = ls and ls:FindFirstChild("Gems")
	local cashSt = ls and ls:FindFirstChild("Cash")
	for k, v in pairs(pack.da) do
		if k == "gems" then if gemsSt then gemsSt.Value += v end
		elseif k == "cash" then if cashSt then cashSt.Value += v end
		else MetaStore.darMaterial(player, k, v) end -- materiales (woods/frost/ember/rare)
	end
	d.packsComprados[pack.id] = true
	player:SetAttribute("Pack_" .. pack.id, true) -- B4: la tienda oculta packs oneTime ya comprados
	if purchaseId then d.comprasHechas[purchaseId] = true end
	if not MetaStore.guardar(player) then -- no persistio: revertir TODO el contenido dado (clamp a 0 por si gasto durante el yield)
		for k, v in pairs(pack.da) do
			if k == "gems" then if gemsSt then gemsSt.Value = math.max(0, gemsSt.Value - v) end
			elseif k == "cash" then if cashSt then cashSt.Value = math.max(0, cashSt.Value - v) end
			elseif d.materiales then d.materiales[k] = math.max(0, (d.materiales[k] or 0) - v) end
		end
		d.packsComprados[pack.id] = nil
		player:SetAttribute("Pack_" .. pack.id, nil)
		if purchaseId then d.comprasHechas[purchaseId] = nil end
		return false
	end
	return true
end

function MetaStore.packComprado(player, packId)
	local d = MetaStore.get(player)
	return d.packsComprados ~= nil and d.packsComprados[packId] == true
end

-- ===== PLAYER INFO (S2): contadores de por vida + stats meta (de los perks) + records =====
function MetaStore.addKill(player) local d = MetaStore.get(player); d.totalKills = (d.totalKills or 0) + 1 end
function MetaStore.addRun(player) local d = MetaStore.get(player); d.runsPlayed = (d.runsPlayed or 0) + 1 end
function MetaStore.addPlayTime(player, secs) local d = MetaStore.get(player); d.playTime = (d.playTime or 0) + secs end

-- ===== MUNDOS (modo campana) =====
-- Guardamos las ids como STRING (los DataStores serializan raro las keys numericas).
function MetaStore.mundoSuperado(player, id)
	local d = MetaStore.get(player)
	return d.mundosSuperados ~= nil and d.mundosSuperados[tostring(id)] == true
end

-- Marca un mundo como superado. Devuelve true si era la PRIMERA vez.
function MetaStore.marcarMundo(player, id)
	local d = MetaStore.get(player)
	d.mundosSuperados = d.mundosSuperados or {}
	local primera = not d.mundosSuperados[tostring(id)]
	d.mundosSuperados[tostring(id)] = true
	MetaStore.guardar(player)
	return primera
end

-- ===== PROGRESO POR ACTO (campana v3: cada acto es una run) =====
-- progresoMundos[worldKey][difKey] = numero del acto MAS ALTO superado en esa dificultad.
function MetaStore.actoMax(player, worldId, difId)
	local d = MetaStore.get(player)
	local p = d.progresoMundos and d.progresoMundos[tostring(worldId)]
	return (p and p[tostring(difId)]) or 0
end

-- Marca un acto como superado. Devuelve true si es un acto NUEVO (record).
function MetaStore.marcarActo(player, worldId, actId, difId)
	local d = MetaStore.get(player)
	d.progresoMundos = d.progresoMundos or {}
	local k = tostring(worldId)
	d.progresoMundos[k] = d.progresoMundos[k] or {}
	local dk = tostring(difId)
	local prev = d.progresoMundos[k][dk] or 0
	local primera = actId > prev
	if primera then d.progresoMundos[k][dk] = actId end
	MetaStore.guardar(player)
	return primera
end

-- Un MUNDO esta completo en una dificultad si se superaron TODOS sus actos.
function MetaStore.mundoCompleto(player, worldId, difId, numActos)
	return MetaStore.actoMax(player, worldId, difId) >= numActos
end

-- Un ACTO esta desbloqueado si es el 1o, o si el anterior ya se supero en esa dificultad.
function MetaStore.actoDesbloqueado(player, worldId, actId, difId)
	if actId <= 1 then return true end
	return MetaStore.actoMax(player, worldId, difId) >= (actId - 1)
end

-- Un MUNDO esta desbloqueado si es el 1o, o si el anterior se completo en Normal.
function MetaStore.mundoDesbloqueado(player, worldId, numActosAnterior)
	if worldId <= 1 then return true end
	return MetaStore.mundoCompleto(player, worldId - 1, "normal", numActosAnterior or 4)
end

function MetaStore.syncProfile(player)
	local d = MetaStore.get(player)
	-- stats META: aplica SOLO los perks (UpgradeData) a un mods fresco y lee los multiplicadores
	local m = RunState.modsBase()
	for _, up in ipairs(UpgradeData.Lista) do
		local lvl = d.upgrades[up.id] or 0
		if lvl > 0 then up.aplicar(m, lvl) end
	end
	local stats = {
		damage = (m.danoMult - 1) * 100, hp = (m.vidaMult - 1) * 100, fireRate = (1 - m.cadenciaMult) * 100,
		crit = m.critChance * 100, critDmg = (m.critMult - 2) * 100, speed = (m.velocidadMult - 1) * 100,
		armor = (1 - m.danoRecibidoMult) * 100, lifesteal = m.roboVida * 100, luck = m.suerte,
	}
	local poseidas = 0
	for _, c in ipairs(ClassData.Lista) do if (d.claseNivel[c.id] or 0) >= 1 then poseidas += 1 end end
	local clase = ClassData.porId(d.claseActual)
	-- rankings (cacheados ~120s en memoria para no spamear el DataStore)
	local ahora = os.clock()
	if not d.rankT or ahora - d.rankT > 120 then
		d.rankG = Leaderboard.rankDe(player.UserId, false)
		d.rankW = Leaderboard.rankDe(player.UserId, true)
		d.rankT = ahora
	end
	profileSync:FireClient(player, {
		stats = stats,
		records = { bestWave = d.bestWave or 0, bestScore = d.bestScore or 0, clasesOwned = poseidas,
			clasesTotal = #ClassData.Lista, totalKills = d.totalKills or 0, runsPlayed = d.runsPlayed or 0, playTime = d.playTime or 0,
			rankGlobal = d.rankG, rankWeekly = d.rankW },
		clase = clase and { nombre = clase.nombre, nivel = d.claseNivel[d.claseActual] or 1, buff = clase.pasivaDesc, color = clase.color, rareza = clase.rareza },
	})
end

-- ===== AJUSTES del jugador (Sju) =====
-- Antes vivian SOLO en la sesion (atributos Setting*) y se reseteaban cada vez que entrabas. Ahora PERSISTEN en
-- el perfil. Server-authoritative: solo se aceptan estas claves, con su tipo y rango (el cliente no manda nada raro).
local AJUSTES_DEF = {
	MusicVol      = { tipo = "number",  def = 70, min = 0, max = 100 },
	SfxVol        = { tipo = "number",  def = 80, min = 0, max = 100 },
	DamageNumbers = { tipo = "boolean", def = true },
	ScreenFlash   = { tipo = "boolean", def = true },
	CameraShake   = { tipo = "boolean", def = true },
}

-- Vuelca los ajustes guardados a atributos Setting* (que es lo que leen los scripts de cliente).
function MetaStore.aplicarAjustes(player)
	local d = MetaStore.get(player)
	d.ajustes = d.ajustes or {}
	for clave, def in pairs(AJUSTES_DEF) do
		local v = d.ajustes[clave]
		if v == nil then v = def.def end
		player:SetAttribute("Setting" .. clave, v)
	end
end

-- Guardado DEBOUNCED: mover un volumen dispara muchos cambios seguidos; no se puede llamar al DataStore en cada uno.
-- OJO con el numero: DataStore limita las escrituras por CLAVE a ~1 cada 6s. Con 5s estabamos POR DEBAJO del
-- limite, y bastaba alternar dos valores validos (subir/bajar volumen) para mantener una escritura permanente
-- cada 5s por jugador y comerse la cuota. Se sube a 10s y ademas se respeta un minimo real entre guardados.
local ajustesPendientes = {}
local ultimoGuardado = {}
local function guardarAjustesPronto(player)
	if ajustesPendientes[player] then return end
	ajustesPendientes[player] = true
	task.delay(10, function()
		ajustesPendientes[player] = nil
		if not player.Parent then return end
		local ahora = os.clock()
		if ahora - (ultimoGuardado[player] or -math.huge) < 8 then return end -- suelo duro, pase lo que pase
		ultimoGuardado[player] = ahora
		MetaStore.guardar(player)
	end)
end

settingsSync.OnServerEvent:Connect(function(player, clave, valor)
	if clave == nil then MetaStore.aplicarAjustes(player); return end -- el cliente pide el estado actual
	local def = (type(clave) == "string") and AJUSTES_DEF[clave]
	if not def then return end
	if def.tipo == "number" then
		if type(valor) ~= "number" or valor ~= valor then return end -- descarta NaN
		valor = math.clamp(math.floor(valor + 0.5), def.min, def.max)
	elseif def.tipo == "boolean" then
		if type(valor) ~= "boolean" then return end
	end
	local d = MetaStore.get(player)
	d.ajustes = d.ajustes or {}
	if d.ajustes[clave] == valor then return end
	d.ajustes[clave] = valor
	player:SetAttribute("Setting" .. clave, valor)
	-- Persistir SOLO si el perfil esta cargado y en modo escritura. Si no, el ajuste igual se APLICA en esta
	-- sesion (si no, mover el volumen no haria nada y pareceria roto): simplemente no sobrevive al salir.
	if MetaStore.puedeOperar(player) then guardarAjustesPronto(player) end
end)

profileSync.OnServerEvent:Connect(function(player) MetaStore.syncProfile(player) end)

-- El cliente pide su estado al cargar (FireServer sin args).
shopSync.OnServerEvent:Connect(function(player)
	MetaStore.sync(player)
end)

local function darAlSpawn(player)
	player:WaitForChild("Backpack", 5)
	MetaStore.darArmas(player)
end
local function init(player)
	-- Cargar el perfil de DataStore (puede tardar; corre en su propio hilo del PlayerAdded).
	cargadoOk[player] = false -- por defecto NO se puede guardar hasta confirmar la carga
	local prof, ok = DataService.load(player)
	if not player:IsDescendantOf(game) then DataService.liberar(player); return end -- se fue durante la carga: soltar el lock que tomamos (no dejar sesion zombi)
	cargadoOk[player] = ok
	datos[player] = {
		upgrades = prof.upgrades or {},
		ownedWeapons = prof.ownedWeapons or {},
		claseActual = prof.claseActual or ClassData.PorDefecto,
		claseNivel = prof.claseNivel or { [ClassData.PorDefecto] = 1 },
		claseShards = prof.claseShards or {},
		spinsSinNueva = prof.spinsSinNueva or 0,
		tiradasGratis = prof.tiradasGratis or STARTING_SPINS,
		ultimoDiario = prof.ultimoDiario or 0,
		totalKills = prof.totalKills or 0,
		runsPlayed = prof.runsPlayed or 0,
		playTime = prof.playTime or 0,
		comprasHechas = prof.comprasHechas or {},
		bestWave = prof.bestWave or 0,
		bestScore = prof.bestScore or 0,
		mundosSuperados = prof.mundosSuperados or {},
		progresoMundos = prof.progresoMundos or {},
		packsComprados = prof.packsComprados or {},
		streak = prof.streak or 0, lastLogin = prof.lastLogin or 0, streakClaim = prof.streakClaim or 0,
		questDay = prof.questDay or 0, quests = prof.quests or {}, -- Fase D (racha + misiones)
		materiales = prof.materiales or {}, reliquias = prof.reliquias or {}, equipadas = prof.equipadas or {},
		consumibles = prof.consumibles or {}, consumiblesUsar = prof.consumiblesUsar or {}, -- Scr (crafteo)
		semanaPremiada = prof.semanaPremiada or 0, -- Sga: ultima semana de ranking premiada (anti doble-cobro)
		reviveCredito = prof.reviveCredito or 0, -- Smn: revives pagados pendientes (persistente, no se pierden al salir)
		evoDesbloq = prof.evoDesbloq or {}, -- Evo gating: evoluciones desbloqueadas (por evo.id)
		ajustes = prof.ajustes or {}, -- Sju: ajustes persistentes (volumen, damage numbers, screen flash, camera shake)
	}
	-- Espejo de Cash/Gems en datos[player] (FUENTE DE VERDAD al guardar) + volcado al leaderstats.
	local d = datos[player]
	d.cash = prof.cash or 0
	d.gems = prof.gems or 0
	local ls = player:WaitForChild("leaderstats", 10)
	if ls then
		local cash = ls:WaitForChild("Cash", 5)
		if cash then cash.Value = d.cash; cash.Changed:Connect(function(v) d.cash = v end) end
		local gems = ls:WaitForChild("Gems", 5)
		if gems then gems.Value = d.gems; gems.Changed:Connect(function(v) d.gems = v end) end
	end
	for id in pairs(d.packsComprados) do player:SetAttribute("Pack_" .. id, true) end -- B4: restaura marca de packs comprados (la tienda oculta los oneTime)
	player.CharacterAdded:Connect(function() task.spawn(darAlSpawn, player) end)
	if player.Character then task.spawn(darAlSpawn, player) end
	listo[player] = true -- ya cargado: a partir de aqui se puede guardar/operar
	MetaStore.aplicarAjustes(player) -- Sju: vuelca sus ajustes guardados a los atributos Setting* que lee el cliente
	MetaStore.sync(player)
	-- Sga: premios de ranking de semanas PASADAS no cobradas (si quedo en el top) -> Gems al entrar.
	task.spawn(function()
		local d = datos[player]
		if not d then return end
		local prevSemana = Leaderboard.semana() - 1
		local desde = math.max((d.semanaPremiada or 0) + 1, prevSemana - 5) -- barre hasta 6 semanas atras (no infinito)
		local cambio = false
		for wk = desde, prevSemana do
			if (d.semanaPremiada or 0) >= wk then continue end
			local rank, scanOk, total = Leaderboard.rankEnSemana(player.UserId, wk)
			if not scanOk then break end -- fallo de DataStore: NO marcar, reintentar en el proximo login
			d.semanaPremiada = wk; cambio = true -- comprobada de verdad (escaneo OK)
			local premio = Leaderboard.premioPara(rank, total) -- tabla { gems, cash, mats } o nil; Gems SOLO con competencia real
			if premio then
				local ls = player:FindFirstChild("leaderstats")
				local gems = ls and ls:FindFirstChild("Gems")
				local cash = ls and ls:FindFirstChild("Cash")
				local gemsGan = (premio.gems or 0) * (player:GetAttribute("Pass_gems2x") and 2 or 1) -- Smn: gamepass 2x Gems (solo sobre los Gems del podio)
				if gems and gemsGan > 0 then gems.Value += gemsGan end -- d.gems se sincroniza en guardar()
				if cash and (premio.cash or 0) > 0 then cash.Value += premio.cash end
				if (premio.mats or 0) > 0 then MetaStore.darMaterial(player, "rare", premio.mats) end
				rankReward:FireClient(player, { rank = rank, gems = gemsGan, cash = premio.cash or 0, mats = premio.mats or 0 })
			end
		end
		if cambio then MetaStore.guardar(player) end
	end)
end
Players.PlayerAdded:Connect(init)
for _, pl in ipairs(Players:GetPlayers()) do task.spawn(init, pl) end

Players.PlayerRemoving:Connect(function(player)
	local dSal = datos[player]
	if dSal then -- registrar stats finales en los boards del semicirculo (gems/horas/runs pueden haber cambiado sin fin de run)
		local lsS = player:FindFirstChild("leaderstats")
		local gemsS = (lsS and lsS:FindFirstChild("Gems") and lsS.Gems.Value) or dSal.gems or 0
		Leaderboard.registrarStats(player.UserId, { score = dSal.bestScore, wave = dSal.bestWave, gems = gemsS, minutos = math.floor((dSal.playTime or 0) / 60), runs = dSal.runsPlayed or 0 })
	end
	MetaStore.guardar(player)
	DataService.liberar(player) -- soltar el session-lock para la proxima sesion
	datos[player] = nil
	cargadoOk[player] = nil
	listo[player] = nil
end)

-- Autosave periodico (por si el servidor cae sin un PlayerRemoving limpio).
task.spawn(function()
	while true do
		task.wait(60)
		for _, pl in ipairs(Players:GetPlayers()) do
			MetaStore.guardar(pl)
		end
	end
end)

-- Al cerrar el servidor, guardar a todos (con margen para los SetAsync).
game:BindToClose(function()
	local pendientes = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		pendientes += 1
		task.spawn(function()
			MetaStore.guardar(pl)
			DataService.liberar(pl)
			pendientes -= 1
		end)
	end
	local t0 = os.clock()
	while pendientes > 0 and os.clock() - t0 < 25 do task.wait() end -- esperar a que terminen (Roblox da 30s)
end)

return MetaStore
