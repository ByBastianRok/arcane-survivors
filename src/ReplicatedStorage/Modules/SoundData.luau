-- SoundData (ModuleScript, ReplicatedStorage.Modules) · FASE 11 - IDs de sonido por evento.
-- TODOS los IDs son audio GRATIS de la Creator Store (verificados que cargan). Para cambiar un
-- sonido, solo edita su 'id' aqui.
--
-- Campos por sonido (Sju, pase de sonido):
--   volume   = volumen base (se multiplica por el ajuste SFX del jugador)
--   pitch    = variacion ALEATORIA de tono (+/-). Sin esto, oir el MISMO sample 20 veces seguidas "raya".
--   minGap   = segundos minimos entre dos reproducciones del mismo sonido. Es lo que evita la METRALLETA
--              cuando mueren 20 enemigos a la vez: suena uno limpio en vez de 20 superpuestos (que ademas
--              suman volumen y saturan).
--   maxVoces = tope de copias sonando A LA VEZ (segunda red de seguridad para sonidos largos).
local SoundData = {
	shoot       = { id = "rbxassetid://9057742352",      volume = 0.35, pitch = 0.10, minGap = 0.04, maxVoces = 5 }, -- 0.9s
	dash        = { id = "rbxassetid://101681679767521", volume = 0.45, pitch = 0.08, minGap = 0.10, maxVoces = 2 }, -- whoosh corto (Energy Wind)
	nova        = { id = "rbxassetid://138533090376585", volume = 0.55, pitch = 0.08, minGap = 0.09, maxVoces = 3 }, -- reusa el explosion
	melee       = { id = "rbxassetid://131370398099954", volume = 0.45, pitch = 0.10, minGap = 0.06, maxVoces = 3 }, -- tajo de espada (Knight), corto
	shootMage   = { id = "rbxassetid://88350532436520",  volume = 0.20, pitch = 0.10, minGap = 0.04, maxVoces = 5 }, -- disparo del Mago (mas flojo)
	shootArcher = { id = "rbxassetid://88491018935197",  volume = 0.40, pitch = 0.12, minGap = 0.04, maxVoces = 5 }, -- disparo del Arquero (flecha)
	hurt        = { id = "rbxassetid://96359585058783",  volume = 0.55, pitch = 0.06, minGap = 0.15, maxVoces = 2 }, -- que te rodeen 5 bichos no debe sonar x5
	explosion   = { id = "rbxassetid://138533090376585", volume = 0.50, pitch = 0.10, minGap = 0.09, maxVoces = 3 },
	enemyDeath  = { id = "rbxassetid://125263516385547", volume = 0.40, pitch = 0.15, minGap = 0.07, maxVoces = 4 }, -- el que mas se repite: horda entera muriendo
	reload      = { id = "rbxassetid://117963160131194", volume = 0.50, pitch = 0.06, minGap = 0.10, maxVoces = 2 },
	pickup      = { id = "rbxassetid://93529351909119",  volume = 0.50, pitch = 0.12, minGap = 0.05, maxVoces = 4 },
	-- Juice de CARTAS (Sju): al salir la oferta de mejora, sonido SEGUN rareza (dopamina al elegir).
	cardCommon  = { id = "rbxassetid://93529351909119",  volume = 0.35, pitch = 0.06, minGap = 0.05, maxVoces = 2 },
	cardRare    = { id = "rbxassetid://117963160131194", volume = 0.45, pitch = 0.05, minGap = 0.05, maxVoces = 2 },
	cardEpic    = { id = "rbxassetid://101681679767521", volume = 0.55, pitch = 0.04, minGap = 0.05, maxVoces = 2 },
	cardLegend  = { id = "rbxassetid://138533090376585", volume = 0.65, minGap = 0.05, maxVoces = 2 }, -- sin pitch: el "momentazo" suena SIEMPRE igual
	cardPick    = { id = "rbxassetid://93529351909119",  volume = 0.60, pitch = 0.05, minGap = 0.03, maxVoces = 2 }, -- CONFIRMACION al elegir la carta (el poder "se absorbe")
	-- Sju: la del lobby NO pegaba con un lobby tranquilo (feedback de Bastian). Cambiada a cuerdas cinematicas
	-- calmadas de APM (libreria oficial de Roblox = uso seguro), 180s de loop. Candidatos verificados que TAMBIEN
	-- cargan, por si quieres probar otra: 9039623281 (ambiente de templo + drones), 9046912294 (Floating Along
	-- With You), 9046393108 (Southern Winds), 1840937627 (Amoria). La anterior era 1837768013.
	-- Rotacion de musica (L). IDs de DistrokidOfficial (musica CON LICENCIA para experiencias de Roblox). El
	-- MusicClient elige una pista aleatoria del pool (sin repetir la anterior) al entrar en cada estado.
	musicLobby  = { id = "rbxassetid://136984033293818", volume = 0.30, ids = { -- HUB: Celtic tranquila
		"rbxassetid://136984033293818", -- Heart of Wood
		"rbxassetid://134408981528456", -- Icy Stream
	} },
	musicCombat = { id = "rbxassetid://124027970389012", volume = 0.35, ids = { -- COMBATE: epicas, rota por partida
		"rbxassetid://124027970389012", -- Rise of the Heroes
		"rbxassetid://100277718098342", -- Battle Cry of the Free
		"rbxassetid://114403249324975", -- Victory in the Making
		"rbxassetid://132688859323444", -- All Our Strength
	} },
	musicBoss   = { id = "rbxassetid://123189523284320", volume = 0.42, ids = { -- JEFE: intensas
		"rbxassetid://123189523284320", -- Shadow Crown
		"rbxassetid://101989542921934", -- Lord of Rings
		"rbxassetid://133640590337552", -- Raven Call
	} },
}
return SoundData
