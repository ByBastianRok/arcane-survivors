-- WeaponData (ModuleScript) - cada arma definida como DATOS.
-- El motor (WeaponServer) es genérico: añadir un arma = añadir una tabla aquí
-- + crear su Tool con el MISMO nombre (Handle + Muzzle) en ServerStorage.WeaponTemplates.
--
-- Campos:
--   Precio         Cash para desbloquearla en la tienda (0 = arma inicial)
--   Dano           daño por proyectil
--   VelocidadBala  studs/seg (vuela recta, sin caer)
--   Cadencia       segundos mínimos entre disparos
--   VidaBala       segundos que vive la bala (limita el alcance)
--   Balas          proyectiles por disparo (>1 = escopeta)
--   Spread         dispersión en grados (0 = preciso)
--   Automatico     true = dispara mientras mantengas el clic
--   Perforante     true = la bala atraviesa enemigos (no se destruye al 1er impacto)
--   Cargador       balas por cargador (antes de recargar)
--   TiempoRecarga  segundos que tarda en recargar
--   Explosivo      true = al impactar explota y daña en área (RadioExplosion/DanoExplosion)
--   Elemento       "Fuego"/"Veneno"/"Hielo" o nil (efecto de estado al impactar)
--   TamanoBala / ColorBala / ColorTracer  visual
-- NOTA: la CLAVE y el campo Nombre son texto que VE el jugador (hotbar) -> en INGLES.
local WeaponData = {}

WeaponData.Pistol = {
	Nombre = "Pistol",
	Precio = 0,        -- arma inicial (siempre la tienes)
	Dano = 25,
	VelocidadBala = 250,
	Cadencia = 0.6, -- survivors: auto-fuego calmado de salida (se mejora con talentos)
	VidaBala = 4,
	Balas = 1,
	Spread = 1,
	Automatico = false,
	Perforante = false,
	Cargador = 12,
	TiempoRecarga = 1.2,
	TamanoBala = 0.6, -- mas visible con la camara cenital
	ColorBala = Color3.fromRGB(255, 220, 80),
	ColorTracer = Color3.fromRGB(255, 230, 120),
}

WeaponData.Shotgun = {
	Nombre = "Shotgun",
	Precio = 400,      -- Cash para desbloquear en la tienda
	Dano = 14,            -- por perdigón (6 = 84 de cerca)
	VelocidadBala = 200,
	Cadencia = 0.75,
	VidaBala = 0.5,       -- corto alcance
	Balas = 6,
	Spread = 11,
	Automatico = false,
	Perforante = false,
	Cargador = 6,
	TiempoRecarga = 2.0,
	Elemento = "Fuego",   -- quema a los enemigos al impactar
	TamanoBala = 0.35,
	ColorBala = Color3.fromRGB(255, 150, 60),
	ColorTracer = Color3.fromRGB(255, 170, 90),
}

WeaponData.SMG = {
	Nombre = "SMG",
	Precio = 800,
	Dano = 10,
	VelocidadBala = 280,
	Cadencia = 0.1,
	VidaBala = 3,
	Balas = 1,
	Spread = 5,
	Automatico = true,
	Perforante = false,
	Cargador = 30,
	TiempoRecarga = 1.8,
	TamanoBala = 0.3,
	ColorBala = Color3.fromRGB(120, 220, 255),
	ColorTracer = Color3.fromRGB(150, 230, 255),
}

WeaponData.Sniper = {
	Nombre = "Sniper",
	Precio = 1500,
	Dano = 120,           -- one-shot al enemigo basico (100 vida) + margen
	VelocidadBala = 600,
	Cadencia = 1.3,
	VidaBala = 5,
	Balas = 1,
	Spread = 0,
	Automatico = false,
	Perforante = true,    -- atraviesa una fila de enemigos
	Cargador = 5,
	TiempoRecarga = 2.2,
	Elemento = "Hielo",   -- ralentiza al enemigo al impactar
	TamanoBala = 0.45,
	ColorBala = Color3.fromRGB(255, 90, 90),
	ColorTracer = Color3.fromRGB(255, 130, 130),
}

WeaponData["Rocket Launcher"] = {
	Nombre = "Rocket Launcher",
	Precio = 2500,
	Dano = 0,             -- el daño va por la explosión (AoE), no por impacto directo
	VelocidadBala = 110,  -- cohete lento, hay que prever el movimiento
	Cadencia = 1.4,
	VidaBala = 5,
	Balas = 1,
	Spread = 0,
	Automatico = false,
	Perforante = false,
	Explosivo = true,
	RadioExplosion = 16,  -- studs de radio de la explosión
	DanoExplosion = 70,   -- daño a TODOS los enemigos dentro del radio
	Cargador = 1,         -- un cohete; recargar tras cada disparo
	TiempoRecarga = 2.5,
	TamanoBala = 0.8,
	ColorBala = Color3.fromRGB(255, 120, 40),
	ColorTracer = Color3.fromRGB(255, 150, 70),
}

-- ============================================================================
-- CLASES (S2): armas INICIALES de fantasia. La "clase" del jugador decide con cual empieza.
--   Clase          etiqueta de la clase (Mage/Archer/Knight) -> la usa ClassData
--   TipoDisparo    "Proyectil" (defecto) o "Melee" (tajo en arco, sin bala)
--   AlcanceMelee   (Melee) studs de alcance del tajo
--   AnguloMelee    (Melee) arco frontal en grados (da a todos los enemigos dentro)
-- survivors: auto-fuego, sin municion real (Cargador alto, sin recarga).
-- ============================================================================
WeaponData["Arcane Wand"] = {  -- MAGE: bolt arcano que EXPLOTA en un radio PEQUENO (mini-AoE; la evo Inferno Orb lo agranda)
	Nombre = "Arcane Wand",
	Clase = "Mage",
	Precio = 0,
	Dano = 34, -- 30->34 (22-jul). Impacto DIRECTO al enemigo central; el splash da al resto del cluster
	VelocidadBala = 150,
	Cadencia = 0.85,
	VidaBala = 3,
	Balas = 1,
	Spread = 0,
	Explosivo = true, -- 22-jul (DOPAMINA, idea de Bastian): el Mago era single-target en un juego de HORDAS. En vez
	-- de perforar como el arco, sus bolts EXPLOTAN como la evo pero MUCHO mas ligero (radio 5 vs 13, splash 18 vs 50).
	-- Asi el Mago tiene identidad propia (mini-blasts arcanos) y escala hacia el Inferno Orb.
	RadioExplosion = 5,  -- radio PEQUENO (la evo es 13)
	DanoExplosion = 18,  -- splash ligero al resto del cluster (la evo es 50); mata swarmers (12 HP), ablanda chasers
	Cargador = 999, TiempoRecarga = 0,
	FormaBala = "orbe",   -- proyectil magico: esfera con estela
	TamanoBala = 0.7,
	ColorBala = Color3.fromRGB(170, 90, 255),
	ColorTracer = Color3.fromRGB(200, 140, 255),
	Sonido = "shootMage",
}

WeaponData["Hunter Bow"] = {  -- ARCHER: flechas rapidas que perforan, poco dano por flecha
	Nombre = "Hunter Bow",
	Clase = "Archer",
	Precio = 0,
	Dano = 20, -- subido de 16 (era la clase mas floja de dano). + el perforado ahora engancha de verdad (hitbox ancho en WeaponServer)
	VelocidadBala = 170, -- mas lento (era 240): server-owned + rapido se veia a saltos ("parece un frame"); a ~velocidad del Mago se ve fluido + el barrido perfora mejor
	Cadencia = 0.6, -- mas lento (antes 0.4 iba volando)
	VidaBala = 6, -- trayecto LARGO: la flecha cruza la arena y atraviesa toda la fila (era 3.5)
	Balas = 1,
	Spread = 1,
	Perforante = true,
	Cargador = 999, TiempoRecarga = 0,
	FormaBala = "flecha", -- se alarga y se orienta hacia donde vuela
	TamanoBala = 0.65, -- mas visible (era 0.45, la flecha se veia poco)
	ColorBala = Color3.fromRGB(120, 230, 120),
	ColorTracer = Color3.fromRGB(170, 245, 150),
	Sonido = "shootArcher",
}

WeaponData["War Blade"] = {  -- KNIGHT: melee, tajo en arco frontal que da a TODOS los de cerca
	Nombre = "War Blade",
	Clase = "Knight",
	Precio = 0,
	TipoDisparo = "Melee",
	Dano = 42,
	Cadencia = 1.15, -- 1.3->1.15 (22-jul, mejor feel: los tajos se sentian lentos). Sigue lento (cleave a todos + 42 dano)
	AlcanceMelee = 16,
	AnguloMelee = 150,
	Cargador = 999, TiempoRecarga = 0,
	ColorTajo = Color3.fromRGB(220, 235, 255),
}

WeaponData["Inferno Orb"] = {  -- MAGE EVO: bolas de fuego enormes que EXPLOTAN en area + queman
	Nombre = "Inferno Orb",
	Clase = "Mage",
	Precio = 0,
	Dano = 80,
	VelocidadBala = 105,
	Cadencia = 1.4, -- lento pero pega MUCHO mas que el proyectil base
	VidaBala = 3,
	Balas = 1,
	Spread = 0,
	Cargador = 999, TiempoRecarga = 0,
	FormaBala = "orbe", -- bola de fuego: esfera gorda, la explosion ya la pone WeaponServer
	TamanoBala = 2.4,
	Explosivo = true, -- (quitado Perforante=true: era dato muerto, la rama explosiva mata la bala al 1er impacto)
	RadioExplosion = 13,
	DanoExplosion = 50,
	Elemento = "Fuego",
	ColorBala = Color3.fromRGB(255, 130, 40),
	ColorTracer = Color3.fromRGB(255, 90, 30),
	Sonido = "shootMage",
}

WeaponData["Storm Bow"] = {  -- ARCHER EVO: tormenta de flechas perforantes que congelan
	Nombre = "Storm Bow",
	Clase = "Archer",
	Precio = 0,
	Dano = 20,
	VelocidadBala = 180, -- mas lento (era 220): fluido (server-owned) + perfora la fila mejor
	Cadencia = 0.5,
	VidaBala = 6, -- trayecto LARGO (era 3.5)
	Balas = 3,
	Spread = 12,
	Perforante = true,
	Elemento = "Hielo",
	Cargador = 999, TiempoRecarga = 0,
	FormaBala = "flecha",
	TamanoBala = 0.5,
	ColorBala = Color3.fromRGB(120, 220, 255),
	ColorTracer = Color3.fromRGB(170, 240, 255),
	Sonido = "shootArcher",
}

WeaponData["Doom Greatsword"] = {  -- KNIGHT EVO: tajo GIGANTE y brutal (con Vampirism cura un monton)
	Nombre = "Doom Greatsword",
	Clase = "Knight",
	Precio = 0,
	TipoDisparo = "Melee",
	Dano = 80,
	Cadencia = 1.5,
	AlcanceMelee = 24,
	AnguloMelee = 220,
	Cargador = 999, TiempoRecarga = 0,
	ColorTajo = Color3.fromRGB(255, 80, 80),
}

WeaponData["Reaver Scythe"] = {  -- BLOODREAVER: melee glass-cannon, rapido, cleave estrecho (el robo de vida va en la PASIVA)
	Nombre = "Reaver Scythe",
	Clase = "Bloodreaver",
	Precio = 0,
	TipoDisparo = "Melee",
	Dano = 48,
	Cadencia = 0.85, -- rapido y agresivo (glass cannon: pega DURO para justificar -20% HP + melee)
	AlcanceMelee = 13,
	AnguloMelee = 130,
	Cargador = 999, TiempoRecarga = 0,
	ColorTajo = Color3.fromRGB(220, 40, 60),
}

WeaponData["Blood Harvest"] = {  -- BLOODREAVER EVO: guadana brutal, cleave enorme (con Vampirism siega y cura muchisimo)
	Nombre = "Blood Harvest",
	Clase = "Bloodreaver",
	Precio = 0,
	TipoDisparo = "Melee",
	Dano = 90,
	Cadencia = 0.95,
	AlcanceMelee = 20,
	AnguloMelee = 200,
	Cargador = 999, TiempoRecarga = 0,
	ColorTajo = Color3.fromRGB(255, 40, 50),
}

WeaponData["Chakram"] = {  -- TRICKSTER: chakram que VA y VUELVE (bumerang), perforante, pega 2 veces
	Nombre = "Chakram",
	Clase = "Trickster",
	Precio = 0,
	Dano = 15, -- subido de 10 (10 se sentia flojo en early game); ojo: perfora + pega x2, vigilar DPS en hordas
	VelocidadBala = 72,
	Cadencia = 0.9,
	VidaBala = 1.6,
	Balas = 1,
	Spread = 0,
	Cargador = 999, TiempoRecarga = 0,
	FormaBala = "disco", -- anillo plano que GIRA sobre si mismo mientras vuela
	TamanoBala = 1.8,
	Perforante = true,
	Bumerang = true,
	ColorBala = Color3.fromRGB(80, 240, 220),
	ColorTracer = Color3.fromRGB(140, 255, 240),
	Sonido = "shootArcher",
}

WeaponData["Bladestorm"] = {  -- TRICKSTER EVO: TRES chakrams en abanico que vuelven = tormenta de cuchillas
	Nombre = "Bladestorm",
	Clase = "Trickster",
	Precio = 0,
	Dano = 13,
	VelocidadBala = 82,
	Cadencia = 1.0,
	VidaBala = 1.7,
	Balas = 3,
	Spread = 26,
	Cargador = 999, TiempoRecarga = 0,
	FormaBala = "disco",
	TamanoBala = 2.2,
	Perforante = true,
	Bumerang = true,
	ColorBala = Color3.fromRGB(120, 255, 235),
	ColorTracer = Color3.fromRGB(180, 255, 245),
	Sonido = "shootArcher",
}

return WeaponData
