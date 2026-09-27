-- Badges (ModuleScript, ServerScriptService) - LOGROS de Roblox (badges).
-- Los badges se CREAN en el dashboard de la experiencia (Create Badge, cuesta 100 Robux el primero, gratis
-- despues) y cada uno tiene su ID. Pega los IDs reales en Badges.IDS de abajo. 0 = aun no creado -> no se
-- otorga y NO peta (asi el juego funciona igual antes de crearlos).
--
-- Como se otorgan: los puntos de HITO (GameManager al superar mundo, MetaStore al subir/desbloquear clase o
-- evo) llaman a Badges.otorgar(player, "clave"). Este modulo comprueba que el id exista, que no lo tenga ya, y
-- lo concede. AwardBadge es idempotente en Roblox (no lo da dos veces), pero cacheamos para no llamar de mas.
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local Badges = {}

-- CLAVE -> id del badge en Roblox. PON AQUI los IDs del dashboard. 0 = sin crear (no otorga).
Badges.IDS = {
	primerActo  = 0, -- "First Blood"    - supera tu primer acto
	woods       = 0, -- "Woods Cleared"  - supera Whispering Woods (mundo 1)
	frost       = 0, -- "Frostbound"     - supera Frostfell Caverns (mundo 2)
	ember       = 0, -- "Emberforged"    - supera Emberforge Depths (mundo 3)
	nightmare   = 0, -- "Nightmare"      - supera un mundo en Oblivion (la dificultad mas alta)
	legendary   = 0, -- "Legendary Pull" - consigue tu primera clase Legendary (Bloodreaver/Trickster)
	maxClase    = 0, -- "Ascended"       - sube una clase al nivel MAX
	evo         = 0, -- "Evolved"        - desbloquea tu primera evolucion de arma
	todasClases = 0, -- "Collector"      - consigue las 5 clases
	endless     = 0, -- "Into the Rift"  - entra en Endless
}

-- Info para paneles/pagina (opcional): nombre + descripcion legibles por clave.
Badges.INFO = {
	primerActo  = { nombre = "First Blood",    desc = "Clear your first act." },
	woods       = { nombre = "Woods Cleared",  desc = "Beat Whispering Woods." },
	frost       = { nombre = "Frostbound",     desc = "Beat Frostfell Caverns." },
	ember       = { nombre = "Emberforged",    desc = "Beat Emberforge Depths." },
	nightmare   = { nombre = "Nightmare",      desc = "Beat a world on Oblivion." },
	legendary   = { nombre = "Legendary Pull", desc = "Unlock a Legendary class." },
	maxClase    = { nombre = "Ascended",       desc = "Take a class to max level." },
	evo         = { nombre = "Evolved",        desc = "Unlock a weapon evolution." },
	todasClases = { nombre = "Collector",      desc = "Own all classes." },
	endless     = { nombre = "Into the Rift",  desc = "Enter Endless." },
}

local otorgados = {} -- [player] = { clave = true } : cache por sesion para no llamar a AwardBadge de mas

function Badges.otorgar(player, clave)
	if not player or not player.Parent then return end
	local id = Badges.IDS[clave]
	if not id or id == 0 then return end -- badge no creado aun: no hace nada (y no peta)
	otorgados[player] = otorgados[player] or {}
	if otorgados[player][clave] then return end
	otorgados[player][clave] = true -- marca ANTES del yield (evita dobles por eventos seguidos)
	task.spawn(function()
		-- UserHasBadgeAsync + AwardBadge YIELDAN y pueden fallar (red): pcall en ambos.
		local okTiene, tiene = pcall(function() return BadgeService:UserHasBadgeAsync(player.UserId, id) end)
		if okTiene and tiene then return end -- ya lo tiene
		local okDar, err = pcall(function() return BadgeService:AwardBadge(player.UserId, id) end)
		if not okDar then
			otorgados[player][clave] = nil -- fallo la red: permite reintentar en el proximo hito
			warn("[Badges] AwardBadge fallo (" .. clave .. "):", err)
		end
	end)
end

Players.PlayerRemoving:Connect(function(p) otorgados[p] = nil end)

return Badges
