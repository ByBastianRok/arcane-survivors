-- WorldsServer (Script SERVIDOR) - Smo Fase B - datos del MENU de mundos.
-- Manda al cliente la lista de mundos + actos + dificultades CON su estado de desbloqueo/superado,
-- para pintar el selector. El arranque real lo valida GameManager.startMatch (server-authoritative),
-- asi que esto es SOLO para mostrar (no se confia en ello para nada de logica).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WorldData"))
local MetaStore = require(ServerScriptService:WaitForChild("MetaStore"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local worldsSync = remotes:WaitForChild("WorldsSync")

-- Una dificultad se desbloquea con haber superado AL MENOS UN ACTO en la inferior (Trial->Torment->Oblivion).
--
-- Antes hacia falta completar el MUNDO ENTERO (los 4 actos). Cambiado por Bastian el 21-jul: "hagamoslo q
-- cuando t pases un mapa t deje jugar la siguiente dificultad".
-- El motivo de fondo es bueno: con la regla vieja, si te atascabas en un acto (a el le pasaba en el 3 del
-- mundo 1) NUNCA llegabas a ver otra dificultad, asi que atascarse no te dejaba ninguna otra cosa que hacer.
-- Ahora atascarte te abre una via lateral: repetir en mas dificil da mas Cash y mas materiales, que es
-- justo lo que necesitas para desatascarte.
-- OJO: esto NO permite saltarse actos. Dentro de cada dificultad sigue mandando actoDesbloqueado (el acto N
-- necesita el N-1 superado EN ESA dificultad), asi que entrar en Torment te pone igualmente en su acto 1.
local function difDesbloqueada(player, w, difId)
	if difId == "normal" then return true end
	if difId == "hard" then return MetaStore.actoMax(player, w.id, "normal") >= 1 end
	if difId == "nightmare" then return MetaStore.actoMax(player, w.id, "hard") >= 1 end
	return false
end

local function construirDatos(player)
	local worlds = {}
	for _, w in ipairs(WorldData.Lista) do
		local prev = WorldData.porId(w.id - 1)
		local entry = {
			id = w.id, nombre = w.nombre, color = w.color, twist = w.twist,
			numActos = w.numActos, oleadasActo = w.oleadasActo, jefe = w.jefe,
			primeraGems = w.primeraGems, repiteCash = w.repiteCash,
			desbloqueado = MetaStore.mundoDesbloqueado(player, w.id, prev and prev.numActos or 4),
			dif = {},
		}
		for _, d in ipairs(WorldData.Dificultades) do
			local actos = {}
			local maxActo = MetaStore.actoMax(player, w.id, d.id)
			for act = 1, w.numActos do
				actos[act] = {
					desbloqueado = MetaStore.actoDesbloqueado(player, w.id, act, d.id),
					superado = maxActo >= act,
				}
			end
			entry.dif[d.id] = {
				desbloqueada = difDesbloqueada(player, w, d.id),
				completo = MetaStore.mundoCompleto(player, w.id, d.id, w.numActos),
				actos = actos,
			}
		end
		worlds[#worlds + 1] = entry
	end
	local ultimo = WorldData.Lista[#WorldData.Lista]
	return {
		worlds = worlds,
		dificultades = WorldData.Dificultades,
		endless = { -- Endless: desbloqueado al completar el ULTIMO mundo en Normal (= todos)
			nombre = WorldData.Endless.nombre, color = WorldData.Endless.color,
			desbloqueado = MetaStore.mundoCompleto(player, ultimo.id, "normal", ultimo.numActos),
		},
	}
end

-- El cliente pide los datos al abrir el selector (FireServer sin args).
worldsSync.OnServerEvent:Connect(function(player)
	worldsSync:FireClient(player, construirDatos(player))
end)
