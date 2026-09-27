-- PartyServer (Script SERVIDOR) - Sco Fase B - sistema de PARTY en el LOBBY.
-- Jugadores del mismo server se agrupan (invitar/aceptar/salir/kick). El LIDER da PLAY y la party
-- entera se teletransporta junta al place de JUEGO (ese cableado va en otro sitio, cuando haya PlaceId).
-- Modelo: cada jugador tiene un LIDER (por defecto el mismo = party de 1). miembros[lider] = {jugadores}.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local partyAction = remotes:WaitForChild("PartyAction")
local partySync = remotes:WaitForChild("PartySync")

local MAX_PARTY = 4
local INVITE_TTL = 30 -- segundos que dura una invitacion

local lider = {}      -- [player] = player lider de su party (por defecto: el mismo)
local miembros = {}   -- [liderPlayer] = { player, ... }
local invitacion = {} -- [invitedPlayer] = { from = liderPlayer, hasta = os.clock()+TTL }

local PartyServer = {}

local function liderDe(p) return lider[p] or p end
local function listaMiembros(l) return miembros[l] or { l } end

-- Foto segura para el cliente (nombres + userids), + la invitacion pendiente si la hay.
local function estadoPara(p)
	local l = liderDe(p)
	local ms = {}
	for _, m in ipairs(listaMiembros(l)) do
		ms[#ms + 1] = { name = m.DisplayName, userId = m.UserId, esLider = (m == l) }
	end
	local inv = invitacion[p]
	local invData = nil
	if inv and inv.from and inv.from.Parent then invData = { fromName = inv.from.DisplayName, fromUserId = inv.from.UserId } end
	return { lider = l.UserId, esLider = (l == p), miembros = ms, invitacion = invData, maxParty = MAX_PARTY }
end

local function sync(p)
	if p and p.Parent then partySync:FireClient(p, estadoPara(p)) end
end
local function syncParty(l)
	for _, m in ipairs(listaMiembros(l)) do sync(m) end
end

-- Inicializa a un jugador como su propia party (de 1).
local function iniciar(p)
	lider[p] = p
	miembros[p] = { p }
	sync(p)
end

-- Saca a 'p' de su party actual (queda como party de 1). Devuelve el lider viejo.
local function salirDeParty(p)
	local l = liderDe(p)
	local lista = miembros[l]
	if lista then
		for i, m in ipairs(lista) do if m == p then table.remove(lista, i); break end end
		-- si el que sale era el LIDER, pasa el liderazgo al siguiente (si queda alguien)
		if p == l and #lista > 0 then
			local nuevo = lista[1]
			miembros[nuevo] = lista
			for _, m in ipairs(lista) do lider[m] = nuevo end
			miembros[l] = nil
			syncParty(nuevo)
		elseif #lista == 0 then
			miembros[l] = nil
		else
			syncParty(l)
		end
	end
	-- p pasa a ser su propia party de 1
	lider[p] = p
	miembros[p] = { p }
	return l
end

partyAction.OnServerEvent:Connect(function(player, accion, targetUserId)
	if type(accion) ~= "string" then return end
	local target = targetUserId and Players:GetPlayerByUserId(targetUserId) or nil

	if accion == "invite" then
		-- solo el LIDER invita; el invitado debe estar solo (party de 1) y en el server; party no llena
		if liderDe(player) ~= player then return end
		if not target or target == player then return end
		if #listaMiembros(player) >= MAX_PARTY then return end
		if #listaMiembros(liderDe(target)) > 1 then return end -- ya esta en una party
		invitacion[target] = { from = player, hasta = os.clock() + INVITE_TTL }
		sync(target)

	elseif accion == "accept" then
		local inv = invitacion[player]
		if not inv or not inv.from or not inv.from.Parent then invitacion[player] = nil; sync(player); return end
		if os.clock() > inv.hasta then invitacion[player] = nil; sync(player); return end
		local l = liderDe(inv.from)
		if #listaMiembros(l) >= MAX_PARTY then invitacion[player] = nil; sync(player); return end
		salirDeParty(player) -- por si acaso estaba en otra
		invitacion[player] = nil
		miembros[player] = nil
		lider[player] = l
		table.insert(miembros[l], player)
		syncParty(l)

	elseif accion == "decline" then
		invitacion[player] = nil
		sync(player)

	elseif accion == "leave" then
		local viejoLider = salirDeParty(player)
		sync(player)
		if viejoLider ~= player then syncParty(liderDe(viejoLider)) end

	elseif accion == "kick" then
		-- solo el lider echa a un miembro
		if liderDe(player) ~= player or not target or target == player then return end
		if liderDe(target) ~= player then return end
		salirDeParty(target)
		sync(target)
		syncParty(player)
	end
end)

-- REHIDRATAR la party al volver del place de JUEGO. Sin esto cada jugador entraba como party de 1 y el grupo se
-- DISOLVIA despues de CADA acto (~12 min), obligando a re-invitarse una y otra vez. GameManager manda en el
-- TeleportData de vuelta { party = {userIds}, lider = userId }.
-- Lo reconstruye SOLO el LIDER: una unica corrutina tocando las tablas = sin carreras entre miembros. Los demas
-- se quedan como party de 1 hasta que el lider los engancha (si el lider no llega nunca, todo sigue como antes).
local function rehidratarParty(p)
	local ok, jd = pcall(function() return p:GetJoinData() end)
	local td = ok and jd and jd.TeleportData
	if type(td) ~= "table" or type(td.party) ~= "table" then return end
	if td.lider ~= p.UserId then return end -- solo el lider reconstruye
	local esperados = {}
	for _, uid in ipairs(td.party) do
		if type(uid) == "number" and uid ~= p.UserId then esperados[uid] = true end
	end
	if not next(esperados) then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 15 and p.Parent do -- los miembros van llegando de a poco tras el teleport
			local faltan, cambio = false, false
			for uid in pairs(esperados) do
				local m = Players:GetPlayerByUserId(uid)
				if m and m.Parent then
					-- Solo lo enganchamos si sigue SOLO: si ya se metio en otra party, NO se la robamos.
					if liderDe(m) == m and #listaMiembros(m) == 1 and #listaMiembros(p) < MAX_PARTY then
						miembros[m] = nil
						lider[m] = p
						table.insert(miembros[p], m)
						cambio = true
					end
					esperados[uid] = nil
				else
					faltan = true
				end
			end
			if cambio then syncParty(p) end
			if not faltan then break end
			task.wait(0.5)
		end
	end)
end

Players.PlayerAdded:Connect(function(p)
	iniciar(p) -- por defecto party de 1 (estado seguro)
	rehidratarParty(p) -- ...y si volvemos de una run, el lider reconstruye el grupo
end)
for _, p in ipairs(Players:GetPlayers()) do iniciar(p); rehidratarParty(p) end

Players.PlayerRemoving:Connect(function(p)
	invitacion[p] = nil
	salirDeParty(p)
	lider[p] = nil
	miembros[p] = nil
end)

-- Para el teleport (cuando haya PlaceId): la lista de jugadores de la party de 'p'.
function PartyServer.miembrosDe(p) return listaMiembros(liderDe(p)) end
function PartyServer.esLider(p) return liderDe(p) == p end
function PartyServer.liderDe(p) return liderDe(p) end -- co-op: lider de la party de p (el propio p si va solo)
_G.PartyServer = PartyServer -- accesible desde el flujo de PLAY sin require (mismo server)
return PartyServer
