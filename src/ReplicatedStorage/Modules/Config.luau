-- Config (ModuleScript) - TODOS los números de balance global en un sitio.
-- Tocar el equilibrio del juego = editar AQUÍ, no buscar por los scripts.
local Config = {}

-- Oleadas y recompensas (las usa GameManager)
Config.Waves = {
	RecompensaBase = 50,      -- (legacy) ya no se da Cash por oleada; ahora Cash = score al morir
	RecompensaPorOleada = 25, -- (legacy)
	Descanso = 3,             -- segundos de descanso entre oleadas (survivors: corto)
	RadioSpawn = 44,          -- a qué distancia del JUGADOR aparecen (justo fuera de vista)
	IntervaloSpawn = 0.25,    -- segundos entre cada enemigo (survivors: hordas, ritmo calmado de salida)
}

-- Enemigos
Config.Enemigos = {
	RangoAtaque = 5, -- distancia (studs) a la que el enemigo puede golpear al jugador
}

-- Jefes
Config.Boss = {
	CadaOleadas = 5, -- aparece un jefe cada X oleadas
}

-- Mutaciones ALEATORIAS de enemigos (elites). Cada partida es distinta.
Config.Mutaciones = {
	OleadaInicio = 3,      -- a partir de esta oleada empiezan a aparecer
	ChanceBase = 0.08,     -- prob. en la OleadaInicio de que un enemigo normal mute
	ChancePorOleada = 0.02,  -- la prob. sube esto por cada oleada extra
	ChanceMax = 0.50,      -- tope: en rondas altas casi la mitad mutan
	ChanceDoble = 0.12,    -- de los que mutan, % con un 2do afijo (RARO: Swift Tank, Giant Chaser...)
	ChanceTriple = 0.03,   -- de los dobles, % con un 3er afijo (RARISIMO)
	ChanceCuadruple = 0.04, -- de los triples, % con los 4 afijos a la vez (ULTRA raro)
	-- Afijo -> oleada minima en la que puede salir (se elige aleatorio entre los desbloqueados).
	Desbloqueo = { Veloz = 3, Regenerante = 5, Explosivo = 6, Gigante = 7, Vampiro = 8, Acorazado = 9, Frenetico = 11 },
}

-- Economía
Config.DineroInicial = 0 -- con cuánto Cash empieza un jugador nuevo

-- Co-op Fase B: arquitectura de 2 places (mismo universo). El PLAY del lider en el LOBBY reserva un
-- server del GAME place y teletransporta a la party; el GAME place lee TeleportData y arranca la run.
Config.LobbyPlaceId = 100000016 -- start place (el lobby). El nombre del place aun es legacy: renombrarlo va en la checklist de lanzamiento
Config.GamePlaceId = 100000017  -- place de juego (donde corren las runs de party)
Config.MinEvoLevel = 7 -- Evo gating: la carta dorada de evolucion solo se ofrece desde este nivel de EQUIPO (arregla la curva early)
Config.CoinsPorKill = 6  -- Coins (moneda POR-PARTIDA) por matar un enemigo (fallback si el enemigo no trae valor)

-- Lobby <-> Arena (bucle roguelite): el lobby es un sitio APARTE; PLAY te lleva a la arena.
Config.LobbyPos = Vector3.new(300, 52, 0) -- donde reapareces (lobby)
Config.ArenaPos = Vector3.new(0, 8, 0)    -- donde te teleporta PLAY para empezar la partida

-- Puntuacion de la run -> Cash al TERMINAR (se gasta en el lobby; Cash NO se gana en plena run).
Config.Puntuacion = {
	PorKill = 5,      -- score por enemigo matado
	PorOleada = 100,  -- score por limpiar una oleada (x numero de oleada)
	PorJefe = 1000,   -- score por derrotar un jefe
	CashPorPunto = 0.1, -- Cash ganado al morir = score * esto (10 de score = 1 Cash)
}

-- Elementos de armas (efectos de estado sobre los enemigos)
Config.Elementos = {
	Fuego = { Duracion = 3, DanoPorSegundo = 8 },  -- quemar (daño por tiempo)
	Veneno = { Duracion = 5, DanoPorSegundo = 5 }, -- veneno (DoT más largo)
	Hielo = { Duracion = 2.5, Ralentizar = 0.5 },  -- ralentiza al 50% de velocidad
}

return Config
