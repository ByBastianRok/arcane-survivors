-- EnemyData (ModuleScript) - cada tipo de enemigo definido como DATOS.
-- Añadir un enemigo nuevo = añadir una tabla aquí (y referenciarlo en WaveData).
--
-- Campos:
--   Nombre                         nombre que se ve en el nameplate (INGLES, player-facing)
--   Vida / Velocidad / Dano        básicos (el jugador corre a 16)
--   EnfriamientoDano               segundos entre golpes al jugador
--   TamCuerpo / TamCabeza          tamaño (Vector3)
--   ColorCuerpo / ColorCabeza      visual
--   Cash                           recompensa por matarlo (para Fase 6)
--   Explosivo + RadioExplosion + DanoExplosion   (solo Exploder: revienta al acercarse)
local EnemyData = {}

EnemyData.Chaser = {
	Nombre = "Chaser",
	Vida = 34, Velocidad = 12, Dano = 14, EnfriamientoDano = 1, -- Vida 100->58->34 (hordas 22-jul: muere de 1 toque de Varita = satisfactorio)
	TamCuerpo = Vector3.new(2, 3, 2), TamCabeza = Vector3.new(2, 2, 2),
	ColorCuerpo = Color3.fromRGB(120, 40, 160), ColorCabeza = Color3.fromRGB(170, 80, 210),
	Cash = 10,
}

EnemyData.Swarmer = {
	Nombre = "Swarmer",
	Vida = 12, Velocidad = 15, Dano = 9, EnfriamientoDano = 0.8, -- Vida 30->18->12 (muere de 1 toque)
	TamCuerpo = Vector3.new(1.2, 1.8, 1.2), TamCabeza = Vector3.new(1.2, 1.2, 1.2),
	ColorCuerpo = Color3.fromRGB(210, 120, 40), ColorCabeza = Color3.fromRGB(245, 170, 70),
	Cash = 5,
}

EnemyData.Tank = {
	Nombre = "Tank",
	Vida = 170, Velocidad = 6, Dano = 42, EnfriamientoDano = 1.5, -- Vida 280->210->170 (sigue siendo la PARED, pero menos esponja)
	TamCuerpo = Vector3.new(4, 5.5, 4), TamCabeza = Vector3.new(3, 3, 3),
	ColorCuerpo = Color3.fromRGB(55, 55, 65), ColorCabeza = Color3.fromRGB(90, 90, 105),
	Cash = 30,
}

EnemyData.Exploder = {
	Nombre = "Bomber",
	Vida = 24, Velocidad = 15, Dano = 0, EnfriamientoDano = 1, -- Vida 50->40->24 (revientalo antes de que llegue)
	Explosivo = true, RadioExplosion = 12, DanoExplosion = 38, -- DanoExplosion era 55 (castigaba demasiado al principio; ojo: NO escala con acto/dificultad)
	TamCuerpo = Vector3.new(2.4, 2.4, 2.4), TamCabeza = Vector3.new(1.8, 1.8, 1.8),
	ColorCuerpo = Color3.fromRGB(200, 40, 40), ColorCabeza = Color3.fromRGB(255, 90, 60),
	Cash = 15,
}

EnemyData.Ranged = {
	Nombre = "Spitter",
	Vida = 28, Velocidad = 7, Dano = 0, EnfriamientoDano = 1, -- Vida 60->42->28
	Ranged = true,
	AlcancePreferido = 32,   -- intenta mantenerse a esta distancia del jugador
	CadenciaDisparo = 2,     -- segundos entre disparos
	DanoDisparo = 15,        -- daño de su proyectil al jugador (era 20; NO escala con acto/dificultad)
	VelocidadDisparo = 90,
	VidaProyectil = 4,
	TamCuerpo = Vector3.new(2, 2.6, 2), TamCabeza = Vector3.new(1.6, 1.6, 1.6),
	ColorCuerpo = Color3.fromRGB(40, 140, 130), ColorCabeza = Color3.fromRGB(70, 200, 180),
	ColorDisparo = Color3.fromRGB(120, 255, 230),
	Cash = 12,
}

EnemyData.Splitter = {  -- al MORIR se divide en varios Swarmers (horda repentina)
	Nombre = "Brood",
	Vida = 52, Velocidad = 11, Dano = 12, EnfriamientoDano = 1, -- Vida 120->80->52
	DivideEn = 3, TipoHijo = "MiniBrood",
	TamCuerpo = Vector3.new(2.6, 3.2, 2.6), TamCabeza = Vector3.new(2, 2, 2),
	ColorCuerpo = Color3.fromRGB(80, 180, 90), ColorCabeza = Color3.fromRGB(120, 230, 130),
	Cash = 14,
}

EnemyData.Healer = {  -- mantiene distancia y CURA a los enemigos cercanos (target prioritario)
	Nombre = "Mender",
	Vida = 42, Velocidad = 8, Dano = 0, EnfriamientoDano = 1, -- Vida 90->60->42 (target prioritario)
	Healer = true, AlcancePreferido = 28, Cura = 12, RadioCura = 26, CadenciaCura = 1.5,
	TamCuerpo = Vector3.new(2, 2.6, 2), TamCabeza = Vector3.new(1.6, 1.6, 1.6),
	ColorCuerpo = Color3.fromRGB(80, 220, 200), ColorCabeza = Color3.fromRGB(140, 255, 230),
	Cash = 16,
}

EnemyData.Charger = {  -- cada pocos segundos EMBISTE (rafaga de velocidad) hacia el jugador
	Nombre = "Bull",
	Vida = 78, Velocidad = 9, Dano = 28, EnfriamientoDano = 1.2, -- Vida 150->110->78
	Carga = true, CargaMult = 3, CargaDuracion = 0.8, CargaCooldown = 3,
	TamCuerpo = Vector3.new(3, 3.6, 3), TamCabeza = Vector3.new(2.2, 2.2, 2.2),
	ColorCuerpo = Color3.fromRGB(180, 90, 40), ColorCabeza = Color3.fromRGB(230, 130, 60),
	Cash = 20,
}

EnemyData.MiniBrood = {  -- hijo del Brood: mas pequeno, se divide en 2 Swarmers (hereda el afijo del padre)
	Nombre = "Mini Brood",
	Vida = 18, Velocidad = 12, Dano = 8, EnfriamientoDano = 1, -- Vida 45->28->18
	DivideEn = 2, TipoHijo = "Swarmer",
	TamCuerpo = Vector3.new(1.6, 2, 1.6), TamCabeza = Vector3.new(1.3, 1.3, 1.3),
	ColorCuerpo = Color3.fromRGB(90, 190, 100), ColorCabeza = Color3.fromRGB(130, 235, 140),
	Cash = 6,
}

EnemyData.Summoner = {  -- mantiene distancia e INVOCA enemigos cada pocos segundos
	Nombre = "Warlock",
	Vida = 66, Velocidad = 7, Dano = 0, EnfriamientoDano = 1, -- Vida 140->95->66
	Invoca = true, AlcancePreferido = 32, InvocaCada = 5, InvocaTipo = "Chaser", InvocaCantidad = 2,
	TamCuerpo = Vector3.new(2.2, 3, 2.2), TamCabeza = Vector3.new(1.8, 1.8, 1.8),
	ColorCuerpo = Color3.fromRGB(120, 40, 180), ColorCabeza = Color3.fromRGB(170, 80, 230),
	Cash = 22,
}

return EnemyData
