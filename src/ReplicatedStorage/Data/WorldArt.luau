-- WorldArt (ModuleScript, ReplicatedStorage.Data) · Sju - ASPECTO de cada mundo (data-driven).
-- Antes los 3 mundos eran la MISMA arena con un tinte, asi que Frost y Ember se sentian iguales que Woods con
-- un filtro. Aqui vive todo lo visual: suelo, niebla, cielo, parches, decoracion, PELIGROS y clima.
-- Anadir un mundo nuevo = anadir una entrada aqui (el constructor es generico).
--
-- DECISIONES DE DISENO (importantes, no tocar sin leerlas):
--  · MAPA GRANDE (Bastian, 21 jul): radio 600. A velocidad 16 son ~38s del centro al borde y ~75s cruzarlo.
--  · DENSIDAD: la camara es CENITAL y ve ~140 studs de ancho. Con 240 props en un disco de radio 600 salia un
--    prop cada ~68 studs -> 2-3 en pantalla y sensacion de vacio (feedback de Bastian). Las cifras de abajo
--    apuntan a ~1000 props por mundo = ~1 cada 34 studs = 8-12 en pantalla. Si hay que recortar por
--    rendimiento, se bajan 'clusters' aqui y ya: el constructor no cambia.
--  · Decoracion por CLUSTERES con semilla FIJA por mundo: un bucle de angulos se lee como una valla; los
--    grupos irregulares se leen como un sitio. Semilla fija = mapa reconocible, no ruido nuevo cada partida.
--  · Los props NO tienen colision, por eso pueden estar DENTRO del area de juego: los enemigos no tienen
--    pathfinding (van en linea recta) y un obstaculo SOLIDO los dejaria atascados dejando al jugador invulnerable.
--  · Los PELIGROS por lo mismo se CRUZAN: hacen dano mientras los pisas, pero nunca bloquean el paso. Asi ni
--    rompen la IA ni te acorralan en un genero donde moverte es tu unica defensa. Y como el dano es por SEGUNDO,
--    cruzarlos rapido cuesta poco: es una DECISION (atajo caro vs rodeo lento), no una trampa.

local WorldArt = {}

WorldArt.RadioArena = 600  -- radio jugable
WorldArt.RadioLimpio = 55  -- alrededor del centro no se planta nada: ahi arrancas la run

WorldArt.Mundos = {
	[1] = { -- 🌲 Whispering Woods
		nombre = "Whispering Woods",
		suelo = { color = Color3.fromRGB(74, 112, 62), material = Enum.Material.Grass },
		borde = { color = Color3.fromRGB(52, 80, 44), material = Enum.Material.Slate },
		niebla = { color = Color3.fromRGB(120, 155, 120), inicio = 90, fin = 420 },
		-- El place tiene un Atmosphere en Lighting, y con un Atmosphere presente Roblox IGNORA por completo la
		-- niebla legacy (Fog*). O sea que la 'niebla' de arriba no pintaba NADA: los 3 mundos compartian la
		-- misma atmosfera gris-azulada. La identidad de cada mundo va aqui.
		atmosfera = { densidad = 0.34, neblina = 1.6, color = Color3.fromRGB(178, 196, 170), decaimiento = Color3.fromRGB(92, 112, 88), brillo = 0 },
		ambiente = Color3.fromRGB(105, 120, 100),
		cielo = { hora = 15.5, brillo = 2.2 },
		clima = { color = Color3.fromRGB(150, 200, 120), rate = 14, velocidad = -6, tam = 0.5, transparencia = 0.35, giro = 90 },
		parches = { n = 220, color = Color3.fromRGB(96, 82, 54), material = Enum.Material.Ground, radioMin = 10, radioMax = 40 },
		props = {
			{ mesh = "ArbolWoods", clusters = 130, porCluster = { 3, 8 }, radioCluster = 30, escala = { 0.8, 1.9 } },
			{ mesh = "Arbusto",    clusters = 110, porCluster = { 3, 7 }, radioCluster = 24, escala = { 0.7, 1.6 } },
			{ mesh = "RocaNieve",  clusters = 40,  porCluster = { 2, 5 }, radioCluster = 22, escala = { 0.7, 1.4 }, tinte = Color3.fromRGB(96, 96, 88) }, -- reusada como pedrusco de bosque
		},
		-- ZARZAS: pinchan poco pero constante. Son las mas suaves de los 3 mundos (es el mundo inicial).
		peligros = { n = 34, dano = 5, color = Color3.fromRGB(74, 40, 62), material = Enum.Material.Grass,
			radioMin = 9, radioMax = 20, brillo = false, nombre = "Thorns" },
	},
	[2] = { -- ❄️ Frostfell Caverns
		nombre = "Frostfell Caverns",
		suelo = { color = Color3.fromRGB(196, 220, 236), material = Enum.Material.Glacier },
		borde = { color = Color3.fromRGB(120, 150, 175), material = Enum.Material.Ice },
		niebla = { color = Color3.fromRGB(178, 205, 228), inicio = 60, fin = 330 },
		-- la mas CERRADA de las tres: es una cueva helada, tiene que sentirse claustrofobica
		atmosfera = { densidad = 0.52, neblina = 3.2, color = Color3.fromRGB(206, 226, 244), decaimiento = Color3.fromRGB(120, 150, 180), brillo = 0.1 },
		ambiente = Color3.fromRGB(120, 140, 165),
		cielo = { hora = 8.0, brillo = 1.8 },
		clima = { color = Color3.fromRGB(255, 255, 255), rate = 34, velocidad = -9, tam = 0.35, transparencia = 0.15, giro = 20 },
		parches = { n = 240, color = Color3.fromRGB(245, 250, 255), material = Enum.Material.Snow, radioMin = 12, radioMax = 46 },
		props = {
			{ mesh = "CristalHielo", clusters = 120, porCluster = { 2, 7 }, radioCluster = 28, escala = { 0.7, 2.2 } },
			{ mesh = "RocaNieve",    clusters = 100, porCluster = { 3, 7 }, radioCluster = 24, escala = { 0.8, 1.7 } },
			{ mesh = "ArbolHelado",  clusters = 80,  porCluster = { 2, 6 }, radioCluster = 30, escala = { 0.8, 1.7 } },
		},
		-- GRIETAS HELADAS: congelan mas fuerte que las zarzas (mundo 2).
		peligros = { n = 40, dano = 8, color = Color3.fromRGB(120, 205, 255), material = Enum.Material.Ice,
			radioMin = 10, radioMax = 22, brillo = true, nombre = "Frozen Crack" },
	},
	[3] = { -- 🌋 Emberforge Depths
		nombre = "Emberforge Depths",
		suelo = { color = Color3.fromRGB(72, 52, 48), material = Enum.Material.Basalt },
		borde = { color = Color3.fromRGB(48, 32, 30), material = Enum.Material.Rock },
		niebla = { color = Color3.fromRGB(120, 62, 40), inicio = 70, fin = 350 },
		-- humo volcanico: denso y calido, y con algo de brillo por la lava
		atmosfera = { densidad = 0.46, neblina = 2.6, color = Color3.fromRGB(190, 120, 82), decaimiento = Color3.fromRGB(96, 44, 28), brillo = 0.25 },
		ambiente = Color3.fromRGB(120, 80, 65),
		cielo = { hora = 1.5, brillo = 1.4 }, -- de NOCHE: un volcan con cielo azul brillante cantaba muchisimo
		clima = { color = Color3.fromRGB(255, 150, 60), rate = 22, velocidad = 7, tam = 0.3, transparencia = 0.2, giro = 45 },
		parches = { n = 200, color = Color3.fromRGB(38, 30, 30), material = Enum.Material.Slate, radioMin = 12, radioMax = 44 },
		props = {
			{ mesh = "RocaLava",  clusters = 140, porCluster = { 3, 8 }, radioCluster = 28, escala = { 0.7, 2.2 } },
			{ mesh = "RocaNieve", clusters = 90,  porCluster = { 3, 6 }, radioCluster = 24, escala = { 0.9, 1.9 }, tinte = Color3.fromRGB(46, 40, 40) },
		},
		-- CHARCOS DE LAVA: los mas peligrosos (mundo 3) y ademas son los que dan el caracter al mundo.
		peligros = { n = 55, dano = 12, color = Color3.fromRGB(255, 110, 30), material = Enum.Material.Neon,
			radioMin = 10, radioMax = 26, brillo = true, nombre = "Lava" },
	},
	-- 🌀 Endless Rift · el ENDGAME. Reusaba el aspecto de Woods (se veia "otra vez el bosque para siempre");
	-- ahora es un vacio COSMICO propio: obsidiana morada, niebla violeta con algo de brillo (es una grieta),
	-- pavesas violetas que SUBEN y esquirlas de cristal teñidas. Alto contraste a proposito: es donde mas horda
	-- hay (jefe cada pocas oleadas), asi que el suelo oscuro deja leer a los enemigos claros por encima.
	-- Clave STRING "endless" (no numerica): WorldArt.de la resuelve igual y GameManager la pasa tal cual.
	endless = {
		nombre = "Endless Rift",
		suelo = { color = Color3.fromRGB(28, 22, 42), material = Enum.Material.Basalt },
		borde = { color = Color3.fromRGB(16, 12, 26), material = Enum.Material.Slate },
		niebla = { color = Color3.fromRGB(120, 80, 190), inicio = 75, fin = 360 },
		atmosfera = { densidad = 0.42, neblina = 2.4, color = Color3.fromRGB(160, 120, 225), decaimiento = Color3.fromRGB(70, 40, 110), brillo = 0.3 },
		ambiente = Color3.fromRGB(95, 72, 135),
		cielo = { hora = 0, brillo = 1.5 }, -- medianoche cerrada: es una grieta en el vacio, no hay cielo
		clima = { color = Color3.fromRGB(200, 140, 255), rate = 24, velocidad = 6, tam = 0.3, transparencia = 0.2, giro = 60 }, -- velocidad +: las motas SUBEN (energia de la grieta)
		parches = { n = 210, color = Color3.fromRGB(22, 16, 36), material = Enum.Material.Slate, radioMin = 12, radioMax = 44 },
		props = {
			{ mesh = "CristalHielo", clusters = 165, porCluster = { 3, 7 }, radioCluster = 30, escala = { 0.8, 2.9 }, tinte = Color3.fromRGB(170, 112, 245) }, -- cristal reusado como esquirla del vacio (mas, mas grandes, mas brillo)
			{ mesh = "RocaNieve",    clusters = 80,  porCluster = { 3, 6 }, radioCluster = 24, escala = { 0.8, 1.8 }, tinte = Color3.fromRGB(40, 30, 58) },
		},
		-- GRIETAS NEON en el suelo (aura de nivel final, Bastian): vetas de energia que rajan la obsidiana. NO dañan
		-- (decorativas). Una fraccion PALPITA (el cliente las pulsa). Neon = brilla solo, sin PointLight (movil-safe).
		grietas = { n = 64, color = Color3.fromRGB(196, 84, 255), material = Enum.Material.Neon,
			anchoMin = 0.7, anchoMax = 1.9, largoMin = 8, largoMax = 34, palpitaFrac = 0.5 },
		-- ESQUIRLAS DE ENERGIA (Neon) que sobresalen del suelo: cristales luminosos del Rift. Algunas palpitan.
		cristalesNeon = { n = 95, palpitaFrac = 0.45, altoMin = 3, altoMax = 12, grosorMin = 0.45, grosorMax = 1.5,
			colores = { Color3.fromRGB(176, 96, 255), Color3.fromRGB(120, 96, 255), Color3.fromRGB(214, 104, 240) } },
		-- DESGARROS DEL VACIO: brillan magenta y hacen dano al pisarlos (como la lava, pero del Rift).
		peligros = { n = 44, dano = 10, color = Color3.fromRGB(210, 70, 255), material = Enum.Material.Neon,
			radioMin = 10, radioMax = 24, brillo = true, nombre = "Void Tear" },
	},
}

-- Endless usa la clave "endless"; cualquier id desconocido reusa el aspecto del Mundo 1.
function WorldArt.de(worldId)
	return WorldArt.Mundos[worldId] or WorldArt.Mundos[1]
end

return WorldArt
