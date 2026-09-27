-- WorldData (ModuleScript) - modo CAMPANA por MUNDOS (fantasia).
-- Cada Mundo reusa el motor de waves; cambia el mapa (tinte placeholder hasta fase arte), el
-- escalado de enemigos, el JEFE final, el modificador y las recompensas.
-- Cada Mundo = su propia RUN: lo eliges, construyes desde 0, superas sus waves + jefe = limpiado.
local WorldData = {}

WorldData.Lista = {
	{
		id = 1,
		nombre = "Whispering Woods",
		color = Color3.fromRGB(70, 120, 70),
		numActos = 4, oleadasActo = 11, -- oleadasActo era 15 (partidas duraban mucho; ~11 => sesion ~8-10 min)
		jefe = "ForestWarden",     -- Forest Warden
		vidaMult = 1.0, danoMult = 1.0,
		desbloqueoTras = nil,      -- el primero: abierto
		primeraGems = 15,          -- Gems la 1a vez que superas el MUNDO (HONESTO: es justo lo que muestra la UI y lo que se paga)
		repiteCash = 120,          -- Cash al repetirlo
		modificador = nil, veloMult = 1.0, eliteBoost = 1.0, twist = "Balanced",
	},
	{
		id = 2,
		nombre = "Frostfell Caverns",
		color = Color3.fromRGB(120, 185, 225),
		numActos = 4, oleadasActo = 12, -- era 16
		jefe = "GlacialSentinel",  -- Glacial Sentinel
		vidaMult = 1.5, danoMult = 1.2,
		desbloqueoTras = 1,
		primeraGems = 30,
		repiteCash = 200,
		veloMult = 0.88, eliteBoost = 1.8, twist = "Tanky + Elites", -- lentos pero gordos, muchas mutaciones
	},
	{
		id = 3,
		nombre = "Emberforge Depths",
		color = Color3.fromRGB(205, 90, 50),
		numActos = 4, oleadasActo = 13, -- era 18
		jefe = "MagmaColossus",    -- Magma Colossus
		vidaMult = 1.9, danoMult = 1.4,
		desbloqueoTras = 2,
		primeraGems = 50,
		repiteCash = 320,
		veloMult = 1.3, eliteBoost = 1.15, twist = "Fast + Explosive", -- veloces
	},
}

-- ===== RECOMPENSA POR ACTO =====
-- Bastian, jugando: "no tiene sentido q el acto 2 y 3 den la misma recompensa si son mas dificiles". Y tenia
-- razon: la recompensa salia de 'repiteCash', que es un numero POR MUNDO, asi que los 4 actos pagaban lo
-- mismo aunque los enemigos escalen acto a acto. El unico premio que crecia eran las Gems del acto final.
--
-- Esto multiplica el Cash base segun el acto. El 4 salta mas que el resto a proposito: es el del JEFE del
-- mundo, dura mas y es donde de verdad te puedes dejar la run.
-- Si hay que tocar el ritmo de la economia, se toca AQUI y en un solo sitio.
WorldData.ActoMult = { 1.0, 1.35, 1.75, 2.4 }

-- Endless: se desbloquea al superar el ultimo mundo. Generador infinito + leaderboard.
WorldData.Endless = {
	id = "endless",
	nombre = "Endless Rift",
	color = Color3.fromRGB(150, 80, 200),
	vidaMult = 2.4, danoMult = 1.5,
}

-- Dificultad elegida al ENTRAR a un mundo: multiplica el escalado de enemigos y las recompensas/materiales.
-- Hard se desbloquea al pasar Normal; Nightmare al pasar Hard (el gateo se valida en el server).
WorldData.Dificultades = {
	-- OJO: el 'id' NO se toca NUNCA. Va escrito en el perfil guardado de cada jugador (que dificultades lleva
	-- superadas por mundo), asi que cambiarlo borraria el progreso de todo el mundo. Lo que se ve en pantalla
	-- es 'nombre', y ese si es libre.
	--
	-- Nombres con caracter en vez de Normal/Hard/Nightmare (Bastian, 21-jul): "Normal" no es un nombre, es una
	-- etiqueta de menu de opciones. Trial / Torment / Oblivion se leen en escalada y pegan con el tema, y
	-- siguen siendo cortos, que importa porque van en pestanas.
	-- gems/bossGems ELIMINADOS (22-jul): 'gems' nunca se leia (dead) y 'bossGems' era el faucet repetible de premium.
	-- Los Gems ahora salen SOLO del 1er clear (primeraGems * recompensaMult, en GameManager) + el top semanal.
	{ id = "normal",    nombre = "Trial",    vidaMult = 1.0, danoMult = 1.0, recompensaMult = 1.0, matMult = 1.0, color = Color3.fromRGB(120, 200, 120) },
	{ id = "hard",      nombre = "Torment",  vidaMult = 1.6, danoMult = 1.3, recompensaMult = 1.8, matMult = 2.2, color = Color3.fromRGB(245, 180, 70) },
	{ id = "nightmare", nombre = "Oblivion", vidaMult = 2.5, danoMult = 1.7, recompensaMult = 3.0, matMult = 4.0, color = Color3.fromRGB(230, 70, 90) },
}

function WorldData.dificultad(id)
	for _, d in ipairs(WorldData.Dificultades) do
		if d.id == id then return d end
	end
	return WorldData.Dificultades[1] -- Normal por defecto
end

-- Material que suelta cada mundo (crafteo, ver CraftData). Endless/desconocido -> nil (da material raro aparte).
local MAT_POR_MUNDO = { [1] = "woods", [2] = "frost", [3] = "ember" }
function WorldData.materialDe(worldId) return MAT_POR_MUNDO[worldId] end

function WorldData.porId(id)
	if id == "endless" then return WorldData.Endless end
	for _, w in ipairs(WorldData.Lista) do
		if w.id == id then return w end
	end
	return nil
end

return WorldData
