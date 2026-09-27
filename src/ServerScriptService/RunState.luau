-- RunState (ModuleScript) · FASE 5A - la "build" de la partida de cada jugador.
-- Guarda los modificadores que van acumulando las cartas de poder (dano, vida, etc.).
-- Se REINICIA al empezar una partida nueva. Lo leen WeaponServer (dano/balas/robo de
-- vida/cadencia) y GameManager (Cash). Vida y velocidad se aplican al personaje.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PowerData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("PowerData"))
local statsSync = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StatsSync")

local RunState = {}

local VIDA_BASE = 100 -- MaxHealth por defecto de un Humanoid
local VEL_BASE = 16   -- WalkSpeed por defecto

local estados = {} -- estados[player] = mods

local function nuevo()
	return {
		danoMult = 1,
		cadenciaMult = 1,     -- multiplica la Cadencia (menor = dispara mas rapido)
		balasExtra = 0,
		perforante = false,
		critChance = 0,       -- probabilidad de critico (0..1)
		critMult = 2,         -- multiplicador de dano en critico
		elementosExtra = {},  -- SET de elementos extra ({Fuego=true,...}); se ACUMULAN (Incendiary/Toxic/Frostbite)
		roboVida = 0,         -- fraccion del dano que cura al jugador
		regen = 0,            -- HP curados por segundo
		vidaMult = 1,
		danoRecibidoMult = 1, -- <1 = recibe menos dano (armadura)
		velocidadMult = 1,
		recargaMult = 1,      -- multiplica el tiempo de recarga (menor = recarga antes)
		cashMult = 1,
		suerte = 0,           -- influye en la prob. de drops (Fase 5B; mejoras futuras)
		tamanoMult = 1,       -- S2: tamano del proyectil (mas grande = mas area)
		xpMult = 1,           -- S2: XP ganada por kill
		esquivar = 0,         -- S2: prob. de esquivar dano (0..1)
		spreadExtra = 0,      -- S2: grados de dispersion extra (abrir el abanico)
		rangoMult = 1,        -- Longshot: alcance del auto-ataque
		ejecutarUmbral = 0,   -- Execute: umbral de vida (fraccion) por debajo del cual pega mas
		ejecutarBonus = 1,    -- Execute: multiplicador de dano a enemigos con poca vida
		cdMult = 1,           -- Adrenaline: multiplica el cooldown de habilidades (menor = antes)
		-- power-ups TEMPORALES (Fase 5B; se revierten solos):
		buffDanoMult = 1,     -- DAMAGE x2
		buffCadenciaMult = 1, -- RAPID FIRE
		invulnerable = false, -- INVINCIBLE (temporal: revive/dash/drops/god)
		invulnEligiendo = false, -- invuln SOLO mientras eliges mejora (flag propio: no pisa el invuln temporal)
		poderes = {},         -- ids de cartas tomadas (para no repetir unicas / depurar)
		evolucionado = false, -- S2: el arma ya evoluciono esta run (no re-ofrecer la receta)
	}
end

-- Devuelve un set de mods FRESCO (para calcular stats meta sin tocar a ningun jugador).
function RunState.modsBase() return nuevo() end

function RunState.get(player)
	if not estados[player] then estados[player] = nuevo() end
	return estados[player]
end

-- Envia al cliente una foto de la build actual (la pinta el panel RUN STATS).
function RunState.sync(player)
	if typeof(player) ~= "Instance" then return end -- ignora 'dummies' de test
	local m = RunState.get(player)
	player:SetAttribute("AbilityCdMult", m.cdMult) -- Adrenaline: el gate del cooldown de habilidad vive en el CLIENTE; se lo pasamos por atributo
	statsSync:FireClient(player, {
		danoMult = m.danoMult, cadenciaMult = m.cadenciaMult, balasExtra = m.balasExtra,
		perforante = m.perforante, critChance = m.critChance, critMult = m.critMult,
		elementosExtra = m.elementosExtra, roboVida = m.roboVida, regen = m.regen,
		vidaMult = m.vidaMult, danoRecibidoMult = m.danoRecibidoMult, velocidadMult = m.velocidadMult,
		recargaMult = m.recargaMult, cashMult = m.cashMult, suerte = m.suerte,
		tamanoMult = m.tamanoMult, xpMult = m.xpMult, esquivar = m.esquivar, spreadExtra = m.spreadExtra,
		rangoMult = m.rangoMult, ejecutarBonus = m.ejecutarBonus, ejecutarUmbral = m.ejecutarUmbral, cdMult = m.cdMult,
		buffDanoMult = m.buffDanoMult, buffCadenciaMult = m.buffCadenciaMult, invulnerable = m.invulnerable,
	})
end

-- Aplica los stats "de cuerpo" (vida maxima, velocidad) al personaje actual.
function RunState.aplicarAlPersonaje(player)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local m = RunState.get(player)
	local maxNueva = VIDA_BASE * m.vidaMult
	local frac = (hum.MaxHealth > 0) and (hum.Health / hum.MaxHealth) or 1
	hum.MaxHealth = maxNueva
	hum.Health = math.clamp(maxNueva * frac, 1, maxNueva)
	hum.WalkSpeed = VEL_BASE * m.velocidadMult
end

-- Reinicia la build del jugador (partida nueva) y la refleja en el personaje.
function RunState.reset(player)
	estados[player] = nuevo()
	RunState.aplicarAlPersonaje(player)
	RunState.sync(player)
end

-- Aplica una carta por id: muta los mods y refleja vida/velocidad. Devuelve true si valio.
function RunState.aplicar(player, id)
	local carta = PowerData.porId(id)
	if not carta then return false end
	local m = RunState.get(player)
	carta.aplicar(m)
	m.poderes[#m.poderes + 1] = id
	RunState.aplicarAlPersonaje(player)
	RunState.sync(player)
	return true
end

-- Power-up TEMPORAL (Fase 5B): pone m[campo]=valor y lo revierte tras 'duracion'.
-- Si se recoge otro igual, refresca la duracion (token) sin romper el contador.
local buffTokens = {} -- buffTokens[player][campo] = contador
function RunState.aplicarBuff(player, campo, valor, duracion)
	local m = RunState.get(player)
	m[campo] = valor
	buffTokens[player] = buffTokens[player] or {}
	buffTokens[player][campo] = (buffTokens[player][campo] or 0) + 1
	local token = buffTokens[player][campo]
	RunState.sync(player)
	task.delay(duracion, function()
		if buffTokens[player] and buffTokens[player][campo] == token then
			-- revertir al valor por defecto (OJO: 'x and false or 1' daria 1; hay que usar if/else)
			if campo == "invulnerable" then
				m[campo] = false
			else
				m[campo] = 1
			end
			RunState.sync(player)
		end
	end)
end

-- Regeneracion de vida (carta Regeneration): cada segundo cura a quien tenga regen > 0.
task.spawn(function()
	while true do
		task.wait(1)
		for player, m in pairs(estados) do
			if m.regen and m.regen > 0 then
				local ch = player.Character
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * m.regen) -- regen = fraccion de vida MAX por segundo
				end
			end
		end
	end
end)

-- El cliente pide su build al cargar (para el panel RUN STATS).
statsSync.OnServerEvent:Connect(function(player)
	RunState.sync(player)
end)

-- Limpieza al salir.
Players.PlayerRemoving:Connect(function(player)
	estados[player] = nil
	buffTokens[player] = nil
end)

return RunState
