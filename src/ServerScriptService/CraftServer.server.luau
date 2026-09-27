-- CraftServer (Script SERVIDOR) - Scr - forja de RELIQUIAS por receta + equipar (slots).
-- Valida materiales en el SERVIDOR, muta el perfil (MetaStore) y guarda. El cliente usa el remote
-- Craft: FireServer() sin args = pedir datos; ("forge"/"levelup"/"equip"/"unequip", id) = accion.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CraftData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("CraftData"))
local MetaStore = require(ServerScriptService:WaitForChild("MetaStore"))
local ClassData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ClassData"))
local EvolutionData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("EvolutionData")) -- Evo gating (pestana Evolutions)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
-- crea los remotes si BuildInstances no los creo (robusto)
local function remote(nombre)
	local r = remotes:FindFirstChild(nombre)
	if not r then r = Instance.new("RemoteEvent"); r.Name = nombre; r.Parent = remotes end
	return r
end
local craftSync = remote("CraftSync")
local craft = remote("Craft")

local function tieneMateriales(d, coste)
	for mat, n in pairs(coste) do
		if (d.materiales[mat] or 0) < n then return false end
	end
	return true
end
local function gastarMateriales(d, coste)
	for mat, n in pairs(coste) do d.materiales[mat] = (d.materiales[mat] or 0) - n end
end

-- Info de las CLASES que el jugador POSEE (del gacha): nivel + shards + costes (pestana Classes).
local function clasesInfo(d)
	local out = {}
	for _, c in ipairs(ClassData.Lista) do
		local nivel = (d.claseNivel and d.claseNivel[c.id]) or 0
		if nivel >= 1 then
			out[#out + 1] = {
				id = c.id, nombre = c.nombre, color = c.color, nivel = nivel, max = ClassData.NivelMax,
				shards = (d.claseShards and d.claseShards[c.id]) or 0,
				costoSubir = (nivel < ClassData.NivelMax) and ClassData.ShardsParaSubir[nivel] or nil,
				costoShard = CraftData.CosteShard, pasivaDesc = c.pasivaDesc,
			}
		end
	end
	return out
end

-- Smn: ranuras de reliquia = base + 1 con el gamepass Extra Relic Slot
local function slotsDe(player) return CraftData.Slots + (player:GetAttribute("Pass_extraslot") and 1 or 0) end

-- Info de las EVOLUCIONES para la pestana Evolutions (receta + coste + estado de desbloqueo).
local function evosInfo(d)
	local out, desbloq = {}, d.evoDesbloq or {}
	for _, e in ipairs(EvolutionData.Lista) do
		out[#out + 1] = {
			id = e.id, nombre = e.nombre, clase = e.clase, color = e.color, desc = e.desc,
			receta = e.receta, -- power-ids (el cliente los mapea a nombre via PowerData)
			costeGems = e.costeGems, recetaMat = e.recetaMat, regalo = e.regalo,
			desbloqueada = desbloq[e.id] and true or false,
			tieneClase = (d.claseNivel and (d.claseNivel[e.clase] or 0) >= 1) or false,
		}
	end
	return out
end

local function sync(player)
	local d = MetaStore.get(player)
	craftSync:FireClient(player, {
		materiales = d.materiales or {},
		reliquias = CraftData.infoDe(d.reliquias or {}, d.equipadas or {}),
		equipadas = d.equipadas or {},
		slots = slotsDe(player),
		clases = clasesInfo(d),
		consumibles = CraftData.consumiblesInfo(d.consumibles or {}, d.consumiblesUsar or {}),
		evos = evosInfo(d), -- Evo gating: pestana Evolutions
	})
end

craft.OnServerEvent:Connect(function(player, accion, id, arg2)
	local d = MetaStore.get(player)
	d.materiales = d.materiales or {}
	d.reliquias = d.reliquias or {}
	d.equipadas = d.equipadas or {}
	-- GATE (audit): en sesion de SOLO-LECTURA (fallo al cargar el perfil) NO mutar nada -> no persistiria y la UI
	-- mostraria un exito falso. Comun a TODAS las acciones (antes solo lo tenia 'evo'): sincroniza el estado real y sale.
	if not MetaStore.puedeOperar(player) then sync(player); return end
	local r = CraftData.porId(id)

	if accion == "forge" then
		if r and (d.reliquias[id] or 0) == 0 and tieneMateriales(d, r.receta) then
			gastarMateriales(d, r.receta)
			d.reliquias[id] = 1
			if #d.equipadas < slotsDe(player) then d.equipadas[#d.equipadas + 1] = id end -- auto-equipa si hay hueco
			MetaStore.guardar(player)
		end
	elseif accion == "levelup" then
		local lvl = d.reliquias[id] or 0
		if r and lvl > 0 and lvl < r.maxNivel then
			local coste = CraftData.costeSubir(r, lvl)
			if tieneMateriales(d, coste) then
				gastarMateriales(d, coste)
				d.reliquias[id] = lvl + 1
				MetaStore.guardar(player)
			end
		end
	elseif accion == "equip" then
		if r and (d.reliquias[id] or 0) > 0 and #d.equipadas < slotsDe(player) then
			local yaEq = false
			for _, e in ipairs(d.equipadas) do if e == id then yaEq = true end end
			if not yaEq then d.equipadas[#d.equipadas + 1] = id; MetaStore.guardar(player) end
		end
	elseif accion == "unequip" then
		for i, e in ipairs(d.equipadas) do
			if e == id then table.remove(d.equipadas, i); MetaStore.guardar(player); break end
		end
	elseif accion == "shard" then -- id = claseId: craftea 1 shard (gasta materiales) y sube nivel al llegar al coste
		local c = ClassData.porId(id)
		d.claseNivel = d.claseNivel or {}
		d.claseShards = d.claseShards or {}
		local nivel = d.claseNivel[id] or 0
		if c and nivel >= 1 and nivel < ClassData.NivelMax and tieneMateriales(d, CraftData.CosteShard) then
			gastarMateriales(d, CraftData.CosteShard)
			d.claseShards[id] = (d.claseShards[id] or 0) + 1
			local costo = ClassData.ShardsParaSubir[nivel]
			if costo and d.claseShards[id] >= costo then
				d.claseShards[id] -= costo
				d.claseNivel[id] = nivel + 1
			end
			MetaStore.guardar(player)
		end
	elseif accion == "consumible" then -- id = consumibleId: craftea 1 (gasta materiales)
		local cons = CraftData.consumiblePorId(id)
		d.consumibles = d.consumibles or {}
		if cons and tieneMateriales(d, cons.receta) then
			gastarMateriales(d, cons.receta)
			d.consumibles[id] = (d.consumibles[id] or 0) + 1
			MetaStore.guardar(player)
		end
	elseif accion == "usar" then -- id = consumibleId: toggle llevarlo a la run
		local cons = CraftData.consumiblePorId(id)
		if cons then
			d.consumiblesUsar = d.consumiblesUsar or {}
			local i = table.find(d.consumiblesUsar, id)
			if i then table.remove(d.consumiblesUsar, i) else d.consumiblesUsar[#d.consumiblesUsar + 1] = id end
			MetaStore.guardar(player)
		end
	elseif accion == "evo" then -- id = evoId, arg2 = "gems"|"craft": desbloquear una evolucion (gate meta-unlock)
		local evo = EvolutionData.porId(id) -- (el gate de solo-lectura ya se aplico arriba, comun a todas las acciones)
		d.evoDesbloq = d.evoDesbloq or {}
		local claseOk = evo and d.claseNivel and (d.claseNivel[evo.clase] or 0) >= 1 -- debes POSEER la clase (gacha)
		if evo and not evo.regalo and not d.evoDesbloq[id] and claseOk then
			if arg2 == "gems" and evo.costeGems then
				local ls = player:FindFirstChild("leaderstats")
				local gems = ls and ls:FindFirstChild("Gems")
				if gems and gems.Value >= evo.costeGems then
					gems.Value -= evo.costeGems
					d.evoDesbloq[id] = true
					MetaStore.guardar(player)
				end
			elseif arg2 == "craft" and evo.recetaMat and tieneMateriales(d, evo.recetaMat) then
				gastarMateriales(d, evo.recetaMat)
				d.evoDesbloq[id] = true
				MetaStore.guardar(player)
			end
		end
	end

	sync(player) -- siempre devuelve el estado actualizado (sin accion = solo pedir datos)
end)
