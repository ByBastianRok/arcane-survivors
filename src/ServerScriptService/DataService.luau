-- DataService (ModuleScript del SERVIDOR) · FASE 7 - persistencia con DataStore.
-- Guarda/carga el perfil del jugador (Cash, Gems, mejoras, armas, mejor oleada/score).
-- REGLAS DE ORO: reintentos en error, y NUNCA sobreescribir datos reales con un perfil por
-- defecto si la carga FALLO (se devuelve cargadoOk=false y save() se niega a escribir).
local DataStoreService = game:GetService("DataStoreService")

local DataService = {}

local VERSION = 1
local store = DataStoreService:GetDataStore("PlayerData_v1")
local LOCK_CADUCA = 120 -- seg: > autosave (60s) para que el lock no caduque entre saves. Un lock mas viejo = sesion muerta -> se puede robar.

-- Perfil por defecto (jugador nuevo). Copia FRESCA cada vez (no compartir tablas).
local function nuevoPerfil()
	return {
		version = VERSION,
		cash = 0,
		gems = 0,
		upgrades = {},                 -- mejoras permanentes { id = nivel }
		ownedWeapons = { Pistol = true }, -- armas compradas
		bestWave = 0,
		bestScore = 0,
	}
end
DataService.nuevoPerfil = nuevoPerfil

-- Migracion por version: transforma perfiles viejos al esquema actual antes de usarlos.
local function migrar(p)
	-- (cuando suba VERSION, aqui van las transformaciones segun p.version)
	p.version = VERSION
	return p
end

-- Carga el perfil. Devuelve (perfil, cargadoOk).
--   cargadoOk=true  -> datos validos (o jugador nuevo): se PUEDE guardar.
--   cargadoOk=false -> fallo de DataStore o lock ajeno: NO guardar (para no borrar datos reales).
-- Reintenta adquirir el session-lock varias veces (rejoin rapido: la sesion anterior puede tardar
-- unos segundos en soltarlo) antes de rendirse a modo SOLO LECTURA.
function DataService.load(player)
	local key = "Player_" .. player.UserId
	local jobId = game.JobId
	for intento = 1, 6 do
		local perfil = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				local viejo, lock
				if old == nil then
					viejo = nil
				elseif old.perfil ~= nil then
					viejo, lock = old.perfil, old.lock -- formato nuevo (con envoltura)
				else
					viejo = old -- formato antiguo (perfil pelado)
				end
				-- Si OTRA sesion tiene el lock y esta fresco, no robamos (abortar sin escribir).
				if lock and lock.jobId ~= jobId and (os.time() - (lock.t or 0)) < LOCK_CADUCA then
					return nil
				end
				perfil = viejo and migrar(viejo) or nuevoPerfil()
				return { perfil = perfil, lock = { jobId = jobId, t = os.time() } } -- tomamos el lock
			end)
		end)
		if not ok then
			warn("[DataService] load intento " .. intento .. " FALLO para " .. player.Name .. ": " .. tostring(err))
			task.wait(2)
		elseif perfil ~= nil then
			-- lock adquirido: rellenar defaults sobre un perfil fresco
			local prof = nuevoPerfil()
			for k, v in pairs(perfil) do prof[k] = v end
			prof.upgrades = perfil.upgrades or {}
			prof.ownedWeapons = perfil.ownedWeapons or { Pistol = true }
			return prof, true
		elseif intento < 6 then
			-- lock ajeno fresco: esperar y reintentar (la sesion anterior deberia soltarlo pronto)
			task.wait(2)
		end
	end
	-- Tras los reintentos el lock sigue ocupado: SOLO LECTURA (no guardar, para no pisar la otra sesion).
	warn("[DataService] " .. player.Name .. " bloqueado por otra sesion tras reintentos (solo lectura)")
	local _, leido = pcall(function() return store:GetAsync(key) end)
	local p = (type(leido) == "table" and (leido.perfil or leido)) or nuevoPerfil()
	return migrar(p), false
end

-- Guarda el perfil (con reintentos). No escribe si cargadoOk == false. Devuelve true SOLO si se escribio.
function DataService.save(player, data, cargadoOk)
	if cargadoOk == false then return false end -- nunca sobreescribir datos no cargados
	if type(data) ~= "table" then return false end
	data.version = VERSION
	local key = "Player_" .. player.UserId
	local jobId = game.JobId
	for intento = 1, 3 do
		local escrito = false
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				-- si otra sesion tomo el lock (y esta fresco), NO sobreescribimos.
				if old and old.lock and old.lock.jobId ~= jobId and (os.time() - (old.lock.t or 0)) < LOCK_CADUCA then
					return nil
				end
				escrito = true
				return { perfil = data, lock = { jobId = jobId, t = os.time() } }
			end)
		end)
		if ok and escrito then return true end
		if ok and not escrito then -- UpdateAsync abortado por lock ajeno: no se escribio nada, no reintentar
			warn("[DataService] save ABORTADO por lock ajeno (" .. player.Name .. "): datos NO guardados")
			return false
		end
		warn("[DataService] save intento " .. intento .. " fallo (" .. player.Name .. "): " .. tostring(err))
		task.wait(1.5)
	end
	return false
end

-- Libera nuestro lock (al salir / cerrar) para que la proxima sesion no espere LOCK_CADUCA.
function DataService.liberar(player)
	local key = "Player_" .. player.UserId
	local jobId = game.JobId
	pcall(function()
		store:UpdateAsync(key, function(old)
			if old and old.lock and old.lock.jobId == jobId then old.lock = nil end
			return old
		end)
	end)
end

return DataService
