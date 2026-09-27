-- BossData (ModuleScript) - cada jefe definido como DATOS.
-- El motor (Boss) ejecuta las HABILIDADES de cada FASE: "pisoton", "rafaga",
-- "megaProyectil", "invocar". Fases ordenadas de mayor a menor umbral de vida (fracción).
local BossData = {}

BossData.ForestWarden = {
	Nombre = "Forest Warden",
	Vida = 32000, -- HP x7 (los jefes morian en ~8s en co-op con builds fuertes). OJO: ademas escala con coopBoss (+100%/jugador)
	Velocidad = 8,
	Dano = 35,             -- daño por contacto cercano
	EnfriamientoDano = 1,
	Tam = Vector3.new(7, 9, 7),
	TamCabeza = Vector3.new(5, 5, 5),
	ColorCuerpo = Color3.fromRGB(90, 20, 130),
	ColorCabeza = Color3.fromRGB(150, 50, 190),
	RadioPisoton = 10,
	DanoPisoton = 35,
	DanoLinea = 32, LargoLinea = 70, AnchoLinea = 7,
	TiempoTelegraph = 1.4, -- segundos de aviso antes del golpe (margen para esquivar)
	PrimeraHabilidad = 3,
	TipoMinion = "Swarmer",
	MinionsPorInvocacion = 3,
	TerremotoDiscos = 9, TerremotoRadio = 18,
	RecompensaMult = 3,    -- la recompensa de la oleada x3
	Fases = {
		{ umbral = 1.0, habilidades = { "pisoton", "invocar" }, cadencia = 3 },
		{ umbral = 0.5, habilidades = { "invocar", "terremoto", "ondaExpansiva" }, cadencia = 1.5 },
	},
}

BossData.GlacialSentinel = {
	Nombre = "Glacial Sentinel",
	Vida = 36000, Velocidad = 7, Dano = 25, EnfriamientoDano = 1, -- HP x7
	Tam = Vector3.new(6, 7, 6), TamCabeza = Vector3.new(4.5, 4.5, 4.5),
	ColorCuerpo = Color3.fromRGB(30, 90, 150), ColorCabeza = Color3.fromRGB(60, 140, 210),
	RafagaProyectiles = 14, VelProyectil = 45, DanoProyectil = 18, VidaProyectil = 4,
	ColorProyectil = Color3.fromRGB(120, 200, 255),
	RadioPisoton = 10, DanoPisoton = 30, TiempoTelegraph = 1.4,
	DanoLinea = 30, LargoLinea = 75, AnchoLinea = 7,
	TipoMinion = "Ranged", MinionsPorInvocacion = 2, LluviaDiscos = 7,
	PrimeraHabilidad = 2.5, RecompensaMult = 3,
	Fases = {
		{ umbral = 1.0, habilidades = { "rafaga", "lineaBarrido" }, cadencia = 2.6 },
		{ umbral = 0.5, habilidades = { "rafaga", "lluvia", "lineaBarrido" }, cadencia = 1.3 },
	},
}

BossData.MagmaColossus = {
	Nombre = "Magma Colossus",
	Vida = 45000, Velocidad = 9, Dano = 45, EnfriamientoDano = 0.9, -- HP x7 (en co-op se cepillaba en ~8s). Escala ademas con coopBoss (+100%/jugador)
	Tam = Vector3.new(9, 12, 9), TamCabeza = Vector3.new(6, 6, 6),
	ColorCuerpo = Color3.fromRGB(140, 20, 40), ColorCabeza = Color3.fromRGB(200, 50, 70),
	RadioPisoton = 11, DanoPisoton = 45, TiempoTelegraph = 1.3,
	DanoLinea = 40, LargoLinea = 80, AnchoLinea = 8, LineasAbanico = 3,
	VelMega = 16, VidaMega = 8, ColorProyectil = Color3.fromRGB(255, 90, 90),
	TipoMinion = "Tank", MinionsPorInvocacion = 2, EmbestidaMult = 3.2, DuracionEmbestida = 1.3,
	PrimeraHabilidad = 2.5, RecompensaMult = 5,
	Fases = {
		{ umbral = 1.0, habilidades = { "embestida", "pisoton" }, cadencia = 3 },
		{ umbral = 0.66, habilidades = { "embestida", "megaProyectil" }, cadencia = 1.9 },
		{ umbral = 0.33, habilidades = { "embestida", "megaProyectil", "ondaExpansiva" }, cadencia = 1.3 },
	},
}

return BossData
