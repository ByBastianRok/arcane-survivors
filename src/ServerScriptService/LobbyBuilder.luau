-- LobbyBuilder (ModuleScript del SERVIDOR) · Sju - construye el LOBBY (el hub social).
-- Es lo PRIMERO que ve alguien que entra al juego: decide si se queda.
--
-- POR QUE POR SCRIPT y no a mano en Studio:
-- lo construido a mano vive SOLO en el archivo del place y NO entra en git (ya casi perdimos los 19 meshes por
-- eso). Siendo codigo: va versionado, se reproduce solo, y aparece igual en los DOS places del co-op sin tener
-- que montarlo dos veces a mano.
--
-- === HISTORIAL DE LO QUE NO FUNCIONO (para no repetirlo) ===
-- 1. Era un CIRCULO. Un Cylinder es una linea de codigo y repartir cosas en anillo es cos/sin: comodidad mia,
--    no diseno. Una plaza-disco con todo a distancias iguales es lo que canta a generado.
-- 2. Luego el patio entero losa a losa (13x9 piezas). Se veia como un tablero de ajedrez gigante: una losa de
--    11 studs son tres metros, a esa escala las juntas no se leen como juntas.
-- 3. Y sobre todo: Cesped y PatioBase tenian los DOS su cara superior en SUELO_Y -> coplanares -> z-fighting,
--    ganaba el cesped y el patio de piedra NO SE VEIA. De ahi la tabla Y de mas abajo.
-- Ahora: superficie solida, detalle en el BORDE (que si va losa a losa y con piezas que faltan), y la escala
-- se da por VERTICAL (arco, columnata desigual) y por FONDO (nubes e islas), no agrandando la planta a lo tonto.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local LobbyBuilder = {}
local PROPS = ServerStorage:FindFirstChild("WorldProps")

local SUELO_Y = 50 -- altura de la cara superior: la MISMA que tenia LobbyFloor, para no romper spawn ni teleports

-- Rejilla del patio. La junta es FINA a proposito: si se separan mucho las losas dejan de leerse como un suelo
-- y parecen baldosas sueltas tiradas por el cesped.
local LOSA, JUNTA = 11.3, 0.4
local PASO = LOSA + JUNTA
local COLS, FILAS = 15, 11 -- 175 x 129 studs de patio
local ANCHO, FONDO = COLS * PASO, FILAS * PASO

-- La isla es bastante mas grande que el patio: empedrado en medio, arboleda alrededor, y TODO con suelo debajo
-- (antes la vegetacion se plantaba mas alla del borde y media arboleda salia flotando en el vacio).
local COLISION_X, COLISION_Z = ANCHO + 90, FONDO + 80

-- ===== COTAS DE LAS CAPAS DEL SUELO =====
-- Dos superficies a la MISMA altura son coplanares: Roblox no sabe cual pintar, parpadean y gana la que le da
-- la gana (z-fighting). Aqui me comio tres bugs de golpe y ninguno da error en consola: el patio invisible bajo
-- el cesped, las losas sueltas ENTERRADAS, y las dos runas a 0.01 la una de la otra.
-- Por eso cada capa tiene su cota escrita, en orden, y todas POR ENCIMA de SUELO_Y (donde esta la colision de
-- LobbyFloor, que no se toca). El jugador se hunde 0.16 studs en el patio: imperceptible.
local Y = {
	cesped  = SUELO_Y + 0.06,
	suelta  = SUELO_Y + 0.12,
	losa    = SUELO_Y + 0.14,
	patio   = SUELO_Y + 0.16,
	avenida = SUELO_Y + 0.22,
	cenefa  = SUELO_Y + 0.26,
	parche  = SUELO_Y + 0.30, -- manchas de desgaste: SIEMPRE encima de todo lo demas del suelo
	runa    = SUELO_Y + 0.38,
	runaInt = SUELO_Y + 0.46,
}

local function crearPieza(clase, nombre, padre)
	local p = Instance.new(clase)
	p.Name = nombre
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false -- decoracion de fondo: sombra dinamica aqui es coste gratis en movil
	p.Parent = padre
	return p
end

-- Red de seguridad del borde: si te caes de la isla, te devuelve al centro del patio en vez de dejarte caer
-- medio minuto hasta morir. Se arranca UNA sola vez aunque construir() se llame varias veces.
local rescateEnMarcha = false
local function arrancarRescate()
	if rescateEnMarcha then return end
	rescateEnMarcha = true
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, pl in ipairs(Players:GetPlayers()) do
				local pers = pl.Character
				local hrp = pers and pers:FindFirstChild("HumanoidRootPart")
				if hrp and hrp.Position.Y < SUELO_Y - 55 then
					pers:PivotTo(CFrame.new(Config.LobbyPos + Vector3.new(0, 4, 0)))
					-- Sin esto llega arriba con toda la velocidad de la caida acumulada y se vuelve a hundir.
					hrp.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
	end)
end

function LobbyBuilder.construir()
	local vieja = workspace:FindFirstChild("LobbyDeco")
	if vieja then vieja:Destroy() end

	local centro = Config.LobbyPos
	local raiz = Instance.new("Folder")
	raiz.Name = "LobbyDeco"
	raiz.Parent = workspace

	-- Semilla fija: el lobby sale SIEMPRE igual. Es el sitio al que vuelves entre partidas, tiene que ser
	-- reconocible, no un decorado distinto cada vez.
	local rng = Random.new(4242)
	local esLobbyPlace = (game.PlaceId == Config.LobbyPlaceId)

	-- ===== CARTEL: FUERA =====
	-- Tenia el nombre del juego flotando en un cartel en mitad del lobby. El nombre va en la thumbnail y en el
	-- titulo de la pagina; dentro de su PROPIO lobby no aporta nada y canta a juego amateur. No se borra (es una
	-- instancia persistida del place, la crea BuildInstances): se apaga, asi es reversible.
	local cartel = workspace:FindFirstChild("LobbyTitle")
	if cartel then
		if cartel:IsA("BasePart") then cartel.Transparency = 1 end
		for _, d in ipairs(cartel:GetDescendants()) do
			if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then d.Enabled = false end
		end
	end

	-- ===== EL SUELO GRIS DE ABAJO =====
	-- El Baseplate por defecto de Studio (2048x2048 a y=-8) se ve perfectamente desde la isla y es LO que mas
	-- canta a "proyecto de Studio a medio hacer".
	-- OJO, solo en el place del LOBBY: en el place de JUEGO ese mismo Baseplate lo usa ArenaBuilder, que lo TINE
	-- con el color del mundo mientras dura la run (si no, la arena parece flotar sobre la cuadricula gris).
	if esLobbyPlace then
		local bp = workspace:FindFirstChild("Baseplate")
		if bp and bp:IsA("BasePart") then
			bp.Transparency = 1
			-- Y SIN colision, no solo invisible: si se deja solido, quien se caiga de la isla aterriza sobre un
			-- suelo invisible 58 studs mas abajo y se queda ahi tirado sin forma de volver.
			bp.CanCollide = false
			bp.CanQuery = false
			bp.CanTouch = false
			-- OJO: el Baseplate de la plantilla de Studio lleva un HIJO Texture con la cuadricula gris
			-- (rbxassetid://6372755229). Poner el Part a Transparency=1 NO oculta a sus hijos Texture/Decal:
			-- tienen su propia transparencia. Estuve un rato buscando que superficie era la cuadricula que
			-- seguia llenando el fondo, y era esta, con el Part ya invisible.
			for _, hijo in ipairs(bp:GetChildren()) do
				if hijo:IsA("Texture") or hijo:IsA("Decal") then hijo.Transparency = 1 end
			end
		end
		-- Aqui me estrelle: intente subir workspace.FallenPartsDestroyHeight y NO se puede, es de solo lectura
		-- para un Script del servidor ("lacking capability Plugin"). Peor: la excepcion se comio el resto de
		-- construir() y el lobby se quedo en la losa de madera pelada. Ahora, en vez de morir, te DEVUELVE.
		arrancarRescate()
	end

	-- La losa de MADERA original asoma por debajo del patio y canta muchisimo. No se borra (es la que TIENE
	-- colision y sostiene al jugador): se le quita el aspecto de tablon y se agranda para que la isla entera
	-- sea pisable.
	local losa = workspace:FindFirstChild("LobbyFloor")
	if losa and losa:IsA("BasePart") then
		losa.Color = Color3.fromRGB(58, 62, 54)
		losa.Material = Enum.Material.Slate
		losa.Size = Vector3.new(COLISION_X, losa.Size.Y, COLISION_Z)
		losa.Position = Vector3.new(centro.X, SUELO_Y - losa.Size.Y / 2, centro.Z)
	end

	-- Apareces mirando a -Z, o sea de lado a todo. Girado a +X lo primero que ves es: la runa a los pies, la
	-- avenida, los braseros y el arco de salida al fondo. La misma escena, un cuarto de vuelta, gratis.
	local spawn = workspace:FindFirstChild("LobbySpawn")
	if spawn and spawn:IsA("BasePart") then
		spawn.CFrame = CFrame.new(spawn.Position, spawn.Position + Vector3.new(1, 0, 0))
		-- Y se hace INVISIBLE: el SpawnLocation por defecto es una losa blanca de 10x10 con su calcomania, y se
		-- veia como un cuadrado blanco encendido en mitad de la runa. El sitio ya lo marca la runa.
		spawn.Transparency = 1
		local calco = spawn:FindFirstChildOfClass("Decal")
		if calco then calco.Transparency = 1 end
	end

	-- ===== CESPED =====
	local cesped = crearPieza("Part", "Cesped", raiz)
	cesped.Size = Vector3.new(COLISION_X, 1, COLISION_Z)
	cesped.Position = Vector3.new(centro.X, Y.cesped - 0.5, centro.Z)
	cesped.Color = Color3.fromRGB(62, 76, 52)
	cesped.Material = Enum.Material.Grass

	-- ===== QUILLA (los bajos de la isla) =====
	-- Antes eran 3 cajas concentricas cada vez mas pequenas. Visto de lado era una TARTA DE BODAS, que es
	-- justo el tell de "esto lo ha puesto un bucle". Ahora: dos estratos DESPLAZADOS y girados, y una espina
	-- que baja 100 studs desviandose cada vez mas, de modo que la punta acaba descentrada. Mas 4 pedruscos
	-- sueltos flotando al lado, arrancados.
	local ROCA = Color3.fromRGB(66, 62, 56)
	for _, c in ipairs({
		{ sx = COLISION_X - 26, sy = 11, sz = COLISION_Z - 22, dx = -5,  dy = 6,   dz = 4,  rot = 0.00, tono = 1.00 },
		{ sx = COLISION_X - 118, sy = 18, sz = COLISION_Z - 96, dx = -24, dy = 19,  dz = 15, rot = 0.14, tono = 0.86 },
		{ sx = 74,  sy = 32, sz = 62, dx = -42, dy = 43,  dz = 27, rot = 0.26, tono = 0.74 },
		{ sx = 42,  sy = 34, sz = 34, dx = -55, dy = 74,  dz = 38, rot = 0.41, tono = 0.62 },
		{ sx = 19,  sy = 30, sz = 16, dx = -63, dy = 101, dz = 46, rot = 0.55, tono = 0.52 },
	}) do
		local r = crearPieza("Part", "Quilla", raiz)
		r.Size = Vector3.new(c.sx, c.sy, c.sz)
		r.CFrame = CFrame.new(centro.X + c.dx, SUELO_Y - c.dy, centro.Z + c.dz) * CFrame.Angles(0, c.rot, 0)
		r.Color = ROCA:Lerp(Color3.new(0, 0, 0), 1 - c.tono)
		r.Material = Enum.Material.Rock
	end
	-- Pedruscos desprendidos: flotan sueltos al lado de la quilla. Dicen "esto se rompio" sin coste ninguno.
	if PROPS and PROPS:FindFirstChild("RocaNieve") then
		for i = 1, 5 do
			local p = PROPS.RocaNieve:Clone()
			p.Name = "Desprendido"
			p.Size = PROPS.RocaNieve.Size * rng:NextNumber(2.4, 5.5)
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			p.Color = ROCA:Lerp(Color3.new(0, 0, 0), 0.2)
			p.CFrame = CFrame.new(
				centro.X + rng:NextNumber(-COLISION_X / 2 - 20, COLISION_X / 2 + 10),
				SUELO_Y - rng:NextNumber(14, 70),
				centro.Z + rng:NextNumber(-COLISION_Z / 2 - 18, COLISION_Z / 2 + 18)
			) * CFrame.Angles(rng:NextNumber() * 3, rng:NextNumber() * 3, rng:NextNumber() * 3)
			p.Parent = raiz
		end
	end

	-- ===== PATIO =====
	local BASE_X, BASE_Z = ANCHO - 2 * PASO, FONDO - 2 * PASO

	local base = crearPieza("Part", "PatioBase", raiz)
	base.Size = Vector3.new(BASE_X, 0.6, BASE_Z)
	base.Position = Vector3.new(centro.X, Y.patio - 0.3, centro.Z)
	base.Color = Color3.fromRGB(118, 115, 107)
	base.Material = Enum.Material.Slate

	-- Avenida a la salida (+X): franja de piedra oscura. Rompe la simetria y dice por donde se sale sin
	-- necesidad de una flecha ni un cartel.
	local largoAv = BASE_X / 2
	local avenida = crearPieza("Part", "Camino", raiz)
	avenida.Size = Vector3.new(largoAv, 0.62, 3 * PASO)
	avenida.Position = Vector3.new(centro.X + largoAv / 2, Y.avenida - 0.31, centro.Z)
	avenida.Color = Color3.fromRGB(82, 78, 70)
	avenida.Material = Enum.Material.Slate

	-- Cenefa: marco fino de piedra oscura embutido en el suelo. Cuatro piezas, y es LO que separa "una losa
	-- grande de piedra" de "un patio que alguien diseno".
	local CEN_M, CEN_W = 14, 1.4
	for _, c in ipairs({
		{ sx = BASE_X - CEN_M * 2, sz = CEN_W, dx = 0, dz = -(BASE_Z / 2 - CEN_M) },
		{ sx = BASE_X - CEN_M * 2, sz = CEN_W, dx = 0, dz = BASE_Z / 2 - CEN_M },
		{ sx = CEN_W, sz = BASE_Z - CEN_M * 2, dx = -(BASE_X / 2 - CEN_M), dz = 0 },
		{ sx = CEN_W, sz = BASE_Z - CEN_M * 2, dx = BASE_X / 2 - CEN_M, dz = 0 },
	}) do
		local cen = crearPieza("Part", "Cenefa", raiz)
		cen.Size = Vector3.new(c.sx, 0.64, c.sz)
		cen.Position = Vector3.new(centro.X + c.dx, Y.cenefa - 0.32, centro.Z + c.dz)
		cen.Color = Color3.fromRGB(74, 71, 64)
		cen.Material = Enum.Material.Slate
	end

	-- ===== BORDE losa a losa =====
	-- El anillo exterior de la rejilla, con las 4 esquinas siempre fuera y 3 de cada 10 losas caidas. Cada una
	-- desplazada y girada un pelin: es lo que hace que el borde parezca gastado y no recortado con tijera.
	local mitadC, mitadF = (COLS - 1) / 2, (FILAS - 1) / 2
	for ix = 0, COLS - 1 do
		for iz = 0, FILAS - 1 do
			local dx, dz = math.abs((ix - mitadC) / mitadC), math.abs((iz - mitadF) / mitadF) -- 0..1
			if math.max(dx, dz) < 0.99 then continue end   -- el interior ya lo cubre PatioBase
			if dx > 0.99 and dz > 0.99 then continue end   -- las 4 esquinas, siempre fuera
			if rng:NextNumber() < 0.3 then continue end    -- y 3 de cada 10 losas del borde

			local t = crearPieza("Part", "Losa", raiz)
			t.Size = Vector3.new(LOSA * rng:NextNumber(0.94, 1.02), 0.6, LOSA * rng:NextNumber(0.94, 1.02))
			local g = rng:NextInteger(104, 124)
			t.Color = Color3.fromRGB(g, g - 3, g - 9)
			t.Material = Enum.Material.Slate
			t.CFrame = CFrame.new(
				centro.X + (ix - mitadC) * PASO + rng:NextNumber(-0.7, 0.7),
				Y.losa - 0.3 + rng:NextNumber(-0.03, 0.03),
				centro.Z + (iz - mitadF) * PASO + rng:NextNumber(-0.7, 0.7)
			) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0)
		end
	end

	-- Losas sueltas ya en el cesped, como caidas del borde.
	for _ = 1, 18 do
		local ladoX = rng:NextNumber() < 0.5
		local t = crearPieza("Part", "LosaSuelta", raiz)
		t.Size = Vector3.new(LOSA * rng:NextNumber(0.5, 0.85), 0.5, LOSA * rng:NextNumber(0.5, 0.85))
		local g = rng:NextInteger(96, 116)
		t.Color = Color3.fromRGB(g, g - 3, g - 9)
		t.Material = Enum.Material.Slate
		local x = ladoX and (centro.X + (rng:NextNumber() < 0.5 and -1 or 1) * (ANCHO / 2 + rng:NextNumber(3, 18)))
			or (centro.X + rng:NextNumber(-ANCHO / 2, ANCHO / 2))
		local z = ladoX and (centro.Z + rng:NextNumber(-FONDO / 2, FONDO / 2))
			or (centro.Z + (rng:NextNumber() < 0.5 and -1 or 1) * (FONDO / 2 + rng:NextNumber(3, 16)))
		t.CFrame = CFrame.new(x, Y.suelta - 0.25, z) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
	end

	-- ===== RUNA del centro =====
	-- Marca el punto donde apareces. Un ROMBO (cuadrado girado 45 grados), no otro circulo: mas arcano y rompe
	-- con la rejilla ortogonal del patio.
	-- Neon + los DOS BloomEffect que hay en Lighting hacian que esto DESLUMBRARA: parecia una piscina de cian
	-- en mitad del patio. Y subir la transparencia no arregla un Neon, porque tambien apaga el brillo.
	-- Lo que manda en un material Neon es lo CLARO que sea el color: con un azul oscuro emite poco, y con el
	-- bloom encima queda como una veta de luz embutida en la piedra, que es lo que se buscaba.
	-- El rombo grande es piedra teñida (nada de Neon) y solo el interior brilla.
	local runa = crearPieza("Part", "Runa", raiz)
	runa.Size = Vector3.new(19, 0.4, 19)
	runa.CFrame = CFrame.new(centro.X, Y.runa - 0.2, centro.Z) * CFrame.Angles(0, math.rad(45), 0)
	runa.Color = Color3.fromRGB(58, 74, 88)
	runa.Material = Enum.Material.Slate

	-- Y el brillo va en TRAZO, no en mancha: cuatro barritas formando el contorno de un rombo. Una placa
	-- rellena (lo que tenia antes) se lee como un charco -- deslumbre si es clara, agujero si es oscura.
	-- Una LINEA fina se lee como algo grabado en la piedra, que es lo que es.
	local ejeRuna = CFrame.new(centro.X, Y.runaInt - 0.2, centro.Z) * CFrame.Angles(0, math.rad(45), 0)
	local LADO, GROSOR = 13, 0.8
	for _, d in ipairs({
		{ sx = LADO, sz = GROSOR, dx = 0, dz = LADO / 2 },
		{ sx = LADO, sz = GROSOR, dx = 0, dz = -LADO / 2 },
		{ sx = GROSOR, sz = LADO, dx = LADO / 2, dz = 0 },
		{ sx = GROSOR, sz = LADO, dx = -LADO / 2, dz = 0 },
	}) do
		local barra = crearPieza("Part", "RunaTrazo", raiz)
		barra.Size = Vector3.new(d.sx, 0.4, d.sz)
		barra.CFrame = ejeRuna * CFrame.new(d.dx, 0, d.dz)
		barra.Color = Color3.fromRGB(96, 190, 226)
		barra.Material = Enum.Material.Neon
	end

	-- ===== ARCO DE SALIDA =====
	-- Un marco en PRIMER PLANO por el que se ve el fondo es la forma mas barata que existe de crear profundidad:
	-- el ojo compara el arco (cerca, grande) con la isla del fondo (lejos, pequena) y deduce la distancia sola.
	-- Por eso es mejor que agrandar el patio, que solo lo dejaria mas vacio.
	-- Asimetrico A PROPOSITO: el remate de la derecha esta partido y su trozo tirado en el suelo.
	local ARCO_X = centro.X + ANCHO / 2 - 8
	local ARCO_Z, ARCO_H, JAMBA = 19, 31, 7
	local PIEDRA_ARCO = Color3.fromRGB(112, 108, 98)
	for lado = -1, 1, 2 do
		local jamba = crearPieza("Part", "ArcoJamba", raiz)
		jamba.Size = Vector3.new(JAMBA, ARCO_H, JAMBA)
		jamba.Position = Vector3.new(ARCO_X, SUELO_Y + ARCO_H / 2, centro.Z + lado * ARCO_Z)
		jamba.Color = PIEDRA_ARCO
		jamba.Material = Enum.Material.Slate
		jamba.CanCollide = true -- es arquitectura, no decorado: tiene que frenarte

		local zocalo = crearPieza("Part", "ArcoZocalo", raiz)
		zocalo.Size = Vector3.new(JAMBA + 3.5, 2.2, JAMBA + 3.5)
		zocalo.Position = Vector3.new(ARCO_X, SUELO_Y + 1.1, centro.Z + lado * ARCO_Z)
		zocalo.Color = Color3.fromRGB(96, 93, 86)
		zocalo.Material = Enum.Material.Slate
	end
	local dintel = crearPieza("Part", "ArcoDintel", raiz)
	dintel.Size = Vector3.new(JAMBA + 1.5, 5, ARCO_Z * 2 + JAMBA)
	dintel.Position = Vector3.new(ARCO_X, SUELO_Y + ARCO_H + 2.5, centro.Z)
	dintel.Color = PIEDRA_ARCO
	dintel.Material = Enum.Material.Slate
	-- Remate SOLO en el lado -Z: el otro se partio.
	local remate = crearPieza("Part", "ArcoRemate", raiz)
	remate.Size = Vector3.new(JAMBA + 3, 3.2, ARCO_Z + 4)
	remate.Position = Vector3.new(ARCO_X, SUELO_Y + ARCO_H + 6.6, centro.Z - ARCO_Z / 2 - 1)
	remate.Color = Color3.fromRGB(122, 118, 108)
	remate.Material = Enum.Material.Slate
	-- Y el trozo que le falta, tirado en el suelo y girado.
	local caido = crearPieza("Part", "ArcoCaido", raiz)
	caido.Size = Vector3.new(JAMBA + 2, 3, 13)
	caido.CFrame = CFrame.new(ARCO_X + 5, SUELO_Y + 1.4, centro.Z + ARCO_Z + 7)
		* CFrame.Angles(math.rad(6), math.rad(38), math.rad(11))
	caido.Color = Color3.fromRGB(116, 112, 103)
	caido.Material = Enum.Material.Slate

	-- ===== COLUMNATA =====
	-- En los DOS lados largos, no en anillo. Y a alturas DESIGUALES: las 2 mas cercanas a la salida son casi el
	-- doble de altas. Una hilera de columnas identicas y perfectamente verticales no parece construida por
	-- nadie; con alturas distintas ademas se lee perspectiva.
	local plantillaPilar = PROPS and PROPS:FindFirstChild("Pilar")
	if plantillaPilar then
		local rotas = { [3] = true, [9] = true, [12] = true } -- a mano: asimetricas entre los dos lados
		local n = 0
		for lado = -1, 1, 2 do
			for i = 0, 6 do
				n += 1
				local x = centro.X + (i - 3) * (ANCHO / 7)
				local z = centro.Z + lado * (FONDO / 2 + 3)
				local p = plantillaPilar:Clone()
				p.Name = "Pilar"
				-- El mesh mide 7.4 studs: a tamano nativo parece un taburete al lado de un personaje (que mide
				-- ~5). Se estira y se engorda a la vez, si no queda un palo.
				local cercaSalida = i >= 5
				local altura = rotas[n] and rng:NextNumber(0.35, 0.55)
					or (cercaSalida and rng:NextNumber(1.65, 1.85) or rng:NextNumber(0.95, 1.15))
				p.Size = Vector3.new(plantillaPilar.Size.X * 2, plantillaPilar.Size.Y * 2.8 * altura, plantillaPilar.Size.Z * 2)
				p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
				local inclina = rotas[n] and rng:NextNumber(-0.12, 0.12) or rng:NextNumber(-0.02, 0.02)
				p.CFrame = CFrame.new(x + rng:NextNumber(-1.5, 1.5), SUELO_Y + p.Size.Y / 2 - 0.5, z + rng:NextNumber(-1.5, 1.5))
					* CFrame.Angles(inclina, rng:NextNumber() * math.pi * 2, inclina * 0.6)
				p.Parent = raiz

				-- Base: una losa cuadrada debajo. Detalle barato que las ancla al suelo (sin ella parecen
				-- clavadas encima del empedrado).
				local baseP = crearPieza("Part", "PilarBase", raiz)
				baseP.Size = Vector3.new(p.Size.X * 1.45, 0.7, p.Size.Z * 1.45)
				baseP.Position = Vector3.new(p.Position.X, SUELO_Y + 0.2, p.Position.Z)
				baseP.Color = Color3.fromRGB(96, 94, 88)
				baseP.Material = Enum.Material.Slate
			end
		end

		-- Una columna TUMBADA cruzando el patio, medio hundida. Es el detalle que mas barato cuenta que esto es
		-- una ruina y no un decorado nuevo.
		local tumbada = plantillaPilar:Clone()
		tumbada.Name = "PilarTumbado"
		tumbada.Size = Vector3.new(plantillaPilar.Size.X * 2, plantillaPilar.Size.Y * 3.4, plantillaPilar.Size.Z * 2)
		tumbada.Anchored = true; tumbada.CanCollide = false; tumbada.CanQuery = false
		tumbada.CanTouch = false; tumbada.CastShadow = false
		tumbada.CFrame = CFrame.new(centro.X - ANCHO * 0.24, SUELO_Y + 2.4, centro.Z + FONDO * 0.27)
			* CFrame.Angles(0, math.rad(-24), math.rad(90))
		tumbada.Parent = raiz
	end

	-- ===== PARAPETO =====
	-- Muretes bajos SOLO en tres tramos: cierran el patio por donde no se sale y dejan abierta la salida.
	-- Colisionan a proposito: dan borde real, no un dibujo en el suelo.
	for i, t in ipairs({
		{ x = -ANCHO / 2 - 2, z = 0,              sx = 2.4, sz = FONDO * 0.62 },
		{ x = -ANCHO / 4,     z = -FONDO/2 - 4,   sx = ANCHO * 0.3,  sz = 2.4 },
		{ x = ANCHO / 4.5,    z = FONDO/2 + 4,    sx = ANCHO * 0.22, sz = 2.4 },
	}) do
		local m = crearPieza("Part", "Parapeto", raiz)
		m.Size = Vector3.new(t.sx, 3.2, t.sz)
		m.Position = Vector3.new(centro.X + t.x, SUELO_Y + 1.6, centro.Z + t.z)
		m.Color = Color3.fromRGB(102, 100, 92)
		m.Material = Enum.Material.Slate
		m.CanCollide = true
		-- Remate: una losa que sobresale por arriba. Es LO que diferencia un muro de un bloque.
		local rem = crearPieza("Part", "ParapetoRemate", raiz)
		rem.Size = Vector3.new(t.sx + 1.2, 0.6, t.sz + 1.2)
		rem.Position = m.Position + Vector3.new(0, 1.9, 0)
		rem.Color = Color3.fromRGB(i == 1 and 118 or 126, 123, 114)
		rem.Material = Enum.Material.Slate
	end

	-- ===== BRASEROS =====
	-- En las jambas del arco: encuadran la salida y la iluminan.
	local plantillaBrasero = PROPS and PROPS:FindFirstChild("Brasero")
	for lado = -1, 1, 2 do
		local pos = Vector3.new(ARCO_X - 9, SUELO_Y, centro.Z + lado * (ARCO_Z - 4))
		local brasero
		if plantillaBrasero then
			brasero = plantillaBrasero:Clone()
			brasero.Name = "Brasero"
			brasero.Size = plantillaBrasero.Size * 1.35 -- mismo motivo que los pilares: a tamano nativo se pierde
			brasero.Anchored = true; brasero.CanCollide = false; brasero.CanQuery = false
			brasero.CanTouch = false; brasero.CastShadow = false
			brasero.Position = pos + Vector3.new(0, brasero.Size.Y / 2, 0)
			brasero.Parent = raiz
		else -- fallback si aun no se ha generado el mesh
			brasero = crearPieza("Part", "Brasero", raiz)
			brasero.Size = Vector3.new(4, 4, 4)
			brasero.Position = pos + Vector3.new(0, 2, 0)
			brasero.Color = Color3.fromRGB(90, 88, 84)
			brasero.Material = Enum.Material.Slate
		end

		local fuego = Instance.new("Fire")
		fuego.Size = 11; fuego.Heat = 7
		fuego.Color = Color3.fromRGB(255, 170, 60)
		fuego.SecondaryColor = Color3.fromRGB(190, 70, 20)
		fuego.Parent = brasero
		-- UNA luz por brasero y ninguna mas en todo el lobby. Alcance CORTO: con Range 30 la luz se derramaba
		-- por el suelo plano y dejaba un manchurron naranja enorme en el cesped, peor que no tener luz.
		local luz = Instance.new("PointLight")
		luz.Color = Color3.fromRGB(255, 168, 80); luz.Range = 18; luz.Brightness = 1.3
		luz.Parent = brasero
	end

	-- ===== PARCHES DE DESGASTE =====
	-- Discos planos oscuros: hollin junto a los braseros y suelo pisado por donde de verdad se anda (la avenida
	-- y el centro). CONCENTRADOS, no repartidos: una mancha uniforme por todo el patio no es desgaste, es ruido.
	for _, foco in ipairs({
		{ x = ARCO_X - 9 - centro.X, z = ARCO_Z - 4,   r = 11, n = 7, c = 44, a = 0.45 }, -- hollin brasero 1
		{ x = ARCO_X - 9 - centro.X, z = -(ARCO_Z - 4), r = 11, n = 7, c = 44, a = 0.45 }, -- hollin brasero 2
		{ x = ANCHO * 0.22, z = 0,  r = 26, n = 9,  c = 92, a = 0.55 }, -- avenida pisada
		{ x = 0,            z = 0,  r = 22, n = 8,  c = 96, a = 0.6 },  -- alrededor de la runa
		{ x = -ANCHO * 0.3, z = -FONDO * 0.2, r = 20, n = 6, c = 88, a = 0.6 },
	}) do
		for _ = 1, foco.n do
			local ang, rad = rng:NextNumber() * math.pi * 2, math.sqrt(rng:NextNumber()) * foco.r
			local p = crearPieza("Part", "Parche", raiz)
			p.Shape = Enum.PartType.Cylinder
			local d = rng:NextNumber(6, 15)
			p.Size = Vector3.new(0.25, d, d * rng:NextNumber(0.7, 1.1))
			p.CFrame = CFrame.new(centro.X + foco.x + math.cos(ang) * rad, Y.parche, centro.Z + foco.z + math.sin(ang) * rad)
				* CFrame.Angles(0, rng:NextNumber() * math.pi, math.rad(90))
			p.Color = Color3.fromRGB(foco.c, foco.c - 3, foco.c - 8)
			p.Material = Enum.Material.Slate
			p.Transparency = foco.a
		end
	end

	-- ===== VEGETACION =====
	-- En GRUPOS alrededor de unos pocos focos, no repartida a intervalos iguales: la naturaleza crece a manchas.
	-- Los focos caen en la BANDA de cesped entre el patio y el borde de la isla. Espeso detras (-X), casi pelado
	-- en la salida (+X) para que se vea por donde se sale.
	local focos = {
		{ x = -ANCHO / 2 - 24, z = -FONDO * 0.38,   r = 26, peso = 1.0 },
		{ x = -ANCHO / 2 - 20, z = FONDO * 0.34,    r = 22, peso = 0.9 },
		{ x = -ANCHO * 0.14,   z = -FONDO / 2 - 22, r = 28, peso = 0.85 },
		{ x = ANCHO * 0.24,    z = FONDO / 2 + 21,  r = 24, peso = 0.7 },
		{ x = ANCHO / 2 + 22,  z = -FONDO * 0.52,   r = 20, peso = 0.5 },
		{ x = -ANCHO * 0.34,   z = FONDO / 2 + 19,  r = 19, peso = 0.45 },
	}
	-- El total se SUMA en vez de escribirlo a mano: antes estaba a pelo (3.8) y tocar un peso habria dejado el
	-- ultimo foco sin usarse nunca, en silencio.
	local pesoTotal = 0
	for _, f in ipairs(focos) do pesoTotal += f.peso end

	local puestos = 0
	if PROPS then
		for _, cfg in ipairs({
			{ mesh = "ArbolWoods", n = 60, escala = { 0.9, 2.0 } },
			{ mesh = "Arbusto",    n = 50, escala = { 0.7, 1.5 } },
			{ mesh = "RocaNieve",  n = 28, escala = { 0.7, 1.4 }, tinte = Color3.fromRGB(104, 102, 96) },
		}) do
			local plantilla = PROPS:FindFirstChild(cfg.mesh)
			if plantilla then
				for _ = 1, cfg.n do
					-- Foco por peso, y dentro del foco con sqrt: asi se apelotona hacia el centro del grupo en
					-- vez de quedar un disco de densidad uniforme (otra vez el mismo tell).
					local foco, tirada, acum = focos[1], rng:NextNumber() * pesoTotal, 0
					for _, f in ipairs(focos) do
						acum += f.peso
						if tirada <= acum then foco = f break end
					end
					local ang = rng:NextNumber() * math.pi * 2
					local r = math.sqrt(rng:NextNumber()) * foco.r
					local x = centro.X + foco.x + math.cos(ang) * r
					local z = centro.Z + foco.z + math.sin(ang) * r
					-- Nada dentro del patio: estropearia el paso y taparia el empedrado.
					if math.abs(x - centro.X) < ANCHO / 2 + 6 and math.abs(z - centro.Z) < FONDO / 2 + 6 then continue end
					-- Y NADA fuera de la isla: los focos caen cerca del borde, asi que sin esto buena parte de
					-- los arboles salen flotando sobre el vacio (se ve clarisimo desde arriba).
					if math.abs(x - centro.X) > COLISION_X / 2 - 7 or math.abs(z - centro.Z) > COLISION_Z / 2 - 7 then continue end

					local p = plantilla:Clone()
					p.Size = plantilla.Size * rng:NextNumber(cfg.escala[1], cfg.escala[2])
					p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
					if cfg.tinte then p.Color = cfg.tinte end
					p.CFrame = CFrame.new(x, SUELO_Y + p.Size.Y / 2 - 1.2, z)
						* CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
					p.Parent = raiz
					puestos += 1
				end
			end
		end
	end

	-- Enredaderas colgando del borde, en DOS tramos nada mas y a distancias irregulares. Marcan por donde te
	-- caes sin tener que poner una valla, y rompen la linea recta del canto de la isla.
	for _, tramo in ipairs({ { z = -COLISION_Z / 2 + 1, desde = -0.35, hasta = 0.1 }, { z = COLISION_Z / 2 - 1, desde = 0.05, hasta = 0.4 } }) do
		for _ = 1, 4 do
			local v = crearPieza("Part", "Enredadera", raiz)
			local largo = rng:NextNumber(10, 26)
			v.Size = Vector3.new(rng:NextNumber(1.4, 3), largo, 1.2)
			v.Position = Vector3.new(centro.X + rng:NextNumber(tramo.desde, tramo.hasta) * COLISION_X, SUELO_Y - largo / 2, centro.Z + tramo.z)
			v.Color = Color3.fromRGB(64, 92, 52)
			v.Material = Enum.Material.Grass
		end
	end

	-- ===== EL CIELO DE ABAJO (solo en el place del LOBBY) =====
	-- En el place de JUEGO no puede ir: alli la arena esta justo debajo, a y=0.
	if esLobbyPlace then
		-- NUBES. Dos capas, no tres: en movil lo caro de esto NO son las piezas, son los PIXELES. Una sola pieza
		-- transparente que llene la pantalla cuesta mas que 40 opacas, asi que nada de un plano gigante de
		-- cierre, misma transparencia dentro de cada capa, y ojo con apilarlas en profundidad.
		-- El JITTER vertical es obligatorio: una capa a Y constante, vista en angulo rasante (que es exactamente
		-- la camara del lobby), no parece nubes, parece una bandeja de porexpan.
		-- Primer intento: UN elipsoide por nube. Se veian HUEVOS flotando, no nubes. Dos motivos:
		--   · demasiado gruesas (el alto era ~1/4 del ancho; una nube real es mucho mas plana), y
		--   · sueltas: una nube no es una forma, es un GRUPO de bultos solapados con silueta irregular.
		-- Asi que cada "nube" son ahora 3 bultos aplastados que se pisan entre si, con el central mas grande.
		-- La transparencia es la MISMA en los tres a proposito: si varia, los bordes donde se solapan cantan.
		local function bulto(nombre, cx, cy, cz, sx, sy, sz, transp, calido)
			local n = crearPieza("Part", nombre, raiz)
			n.Shape = Enum.PartType.Ball -- con Size no uniforme, una bola es un elipsoide
			n.Size = Vector3.new(sx, sy, sz)
			n.Position = Vector3.new(cx, cy, cz)
			n.Material = Enum.Material.SmoothPlastic
			n.Color = Color3.fromRGB(250, 248, 246):Lerp(Color3.fromRGB(255, 224, 192), calido)
			n.Transparency = transp
			return n
		end
		local function banco(nombre, cx, cy, cz, ancho, transp, calido)
			local alto = ancho * 0.13 -- plana de verdad: esto es lo que la separa de un huevo
			for k = 1, 3 do
				local f = (k == 2) and 1 or rng:NextNumber(0.55, 0.8) -- el del medio manda, los otros lo rompen
				bulto(nombre,
					cx + (k - 2) * ancho * rng:NextNumber(0.26, 0.4),
					cy + rng:NextNumber(-alto * 0.35, alto * 0.35),
					cz + rng:NextNumber(-ancho * 0.14, ancho * 0.14),
					ancho * f, alto * f * rng:NextNumber(0.8, 1.2), ancho * 0.72 * f,
					transp, calido)
			end
		end

		-- Capa cercana: jirones sueltos. Uno cruza por debajo del borde -Z y TAPA un trozo de la quilla: eso
		-- solo ya lee "estamos dentro de las nubes".
		for i = 1, 5 do
			local ang = (i / 5) * math.pi * 2 + 0.7
			local rad = rng:NextNumber(120, 230)
			banco("NubeCerca", centro.X + math.cos(ang) * rad, SUELO_Y - 48 + rng:NextNumber(-34, 34),
				centro.Z + math.sin(ang) * rad * 0.8, rng:NextNumber(120, 190), 0.42, rng:NextNumber(0, 0.5))
		end
		banco("NubeCerca", centro.X - 30, SUELO_Y - 15, centro.Z - COLISION_Z / 2 - 16, 170, 0.42, 0.2)

		-- Capa cubierta, muy abajo. Con un POZO deliberado justo bajo la salida (+X): por ese hueco la vista cae
		-- hasta perderse, y es lo que dice "estamos altisimos" mejor que ninguna otra cosa.
		for _ = 1, 10 do
			local ang = rng:NextNumber() * math.pi * 2
			local rad = math.sqrt(rng:NextNumber()) * 660
			local x, z = centro.X + math.cos(ang) * rad, centro.Z + math.sin(ang) * rad
			if x - centro.X > 60 and math.abs(z - centro.Z) < 130 then continue end -- el pozo bajo la salida
			banco("NubeLejos", x, SUELO_Y - 185 + rng:NextNumber(-35, 35), z,
				rng:NextNumber(260, 420), 0.48, rng:NextNumber(0, 0.6))
		end
		-- Y 2 "torres" que sobresalen del plano de la capa: sin ellas la capa se lee como una bandeja.
		for _, t in ipairs({ { -420, -300 }, { 260, 470 } }) do
			for k = 0, 2 do
				banco("NubeTorre", centro.X + t[1] + k * rng:NextNumber(-30, 30), SUELO_Y - 178 + k * 44,
					centro.Z + t[2] + k * rng:NextNumber(-26, 26), 250 - k * 60, 0.48, 0.35)
			end
		end

		-- ISLAS. La HEROE va alineada con la avenida y encuadrada por el hueco del arco, y MAS BAJA que nosotros:
		-- mirarla desde arriba es lo que dice "estamos altisimos". Todo se apila a lo largo del rumbo de la
		-- avenida y se deja un cuadrante vacio a proposito: eso es lo contrario de lo que hace un generador.
		local function islote(nombre, dx, dy, dz, ancho, alto, fondo, tono)
			local m = crearPieza("Part", nombre, raiz)
			m.Size = Vector3.new(ancho, alto, fondo)
			m.CFrame = CFrame.new(centro.X + dx, SUELO_Y + dy, centro.Z + dz) * CFrame.Angles(0, dx * 0.004, 0)
			m.Color = Color3.fromRGB(74, 84, 70):Lerp(Color3.fromRGB(150, 168, 186), tono)
			m.Material = Enum.Material.Slate
			-- Cada islote lleva su quilla: sin ella son losas flotando, no islas.
			local q = crearPieza("Part", nombre .. "Quilla", raiz)
			q.Size = Vector3.new(ancho * 0.6, alto * 2.4, fondo * 0.55)
			q.CFrame = m.CFrame * CFrame.new(ancho * 0.08, -alto * 1.4, -fondo * 0.06)
			q.Color = Color3.fromRGB(56, 54, 50):Lerp(Color3.fromRGB(140, 158, 178), tono)
			q.Material = Enum.Material.Rock
			return m
		end

		-- La cadena que baja hacia la heroe: el ojo camina de piedra en piedra.
		islote("Islote", 250, -30, 22, 62, 11, 48, 0.18)
		islote("Islote", 430, -44, -36, 48, 9, 40, 0.28)
		islote("Islote", 640, -52, 34, 74, 13, 56, 0.40)
		islote("Islote", 830, -60, -18, 40, 8, 34, 0.50)

		-- La HEROE, con su skyline de 3 pilares estirados a alturas muy distintas.
		-- La puse primero 132 studs por debajo, con la idea de que mirarla desde arriba dijera "estamos
		-- altisimos". Y lo decia... cuando te asomabas al borde. Pero desde el SPAWN, que es la vista que
		-- importa, quedaba tan abajo que por el hueco del arco solo se veia cielo vacio: el marco no
		-- encuadraba nada. Ahora esta mas lejos y mas alta, justo por debajo de la linea del horizonte.
		local heroe = islote("IslaHeroe", 1150, -58, 34, 230, 30, 150, 0.55)
		if plantillaPilar then
			for k, h in ipairs({ 92, 124, 68 }) do
				local t = plantillaPilar:Clone()
				t.Name = "TorreLejana"
				t.Size = Vector3.new(14, h, 14)
				t.Anchored = true; t.CanCollide = false; t.CanQuery = false; t.CanTouch = false; t.CastShadow = false
				t.Color = Color3.fromRGB(150, 160, 176)
				t.CFrame = heroe.CFrame * CFrame.new((k - 2) * 42 + 10, 13 + h / 2, (k - 2) * 17)
				t.Parent = raiz
			end
		end

		-- Vecinas cercanas, en otras direcciones, para que no todo cuelgue del mismo eje.
		islote("Islote", -330, -58, 250, 66, 12, 52, 0.22)
		islote("Islote", 120, -86, -390, 58, 10, 46, 0.30)
		islote("Islote", -420, -40, -190, 44, 9, 38, 0.20)

		-- Siluetas muy lejanas: casi del color de la niebla. No son objetos, son SILUETA.
		for _, s in ipairs({ { 1650, -70, 620 }, { -1450, -150, 900 }, { 900, -210, -1500 }, { -1900, -90, -700 } }) do
			local sil = crearPieza("Part", "Silueta", raiz)
			sil.Size = Vector3.new(rng:NextNumber(220, 400), rng:NextNumber(30, 60), rng:NextNumber(180, 320))
			sil.Position = Vector3.new(centro.X + s[1], SUELO_Y + s[2], centro.Z + s[3])
			sil.Color = Color3.fromRGB(176, 190, 208)
			sil.Material = Enum.Material.Slate
		end

		-- Niebla: es lo que hace que las islas se lean como DISTANCIA y no como objetos diminutos. Pero me pase
		-- DOS veces: con Haze 2.4 desaparecio todo, y bajando solo el Haze seguia sin verse la isla lejana
		-- porque quien mas tapa a esa distancia es la DENSITY, no el haze. Con 0.12 se ve el archipielago
		-- entero y sigue habiendo sensacion de aire.
		local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmo then
			atmo.Density = 0.12
			atmo.Haze = 1.3
			atmo.Glare = 0
			atmo.Color = Color3.fromRGB(72, 82, 122)  -- niebla azul de noche
			atmo.Decay = Color3.fromRGB(28, 34, 58)
		end
		-- NOCHE ESTRELLADA (Bastian: el lobby se veia vacio -> noche con estrellas/constelacion de fondo).
		Lighting.ClockTime = 22   -- noche con luna
		Lighting.Brightness = 1.7 -- luz de luna: se ve la geometria sin quedar negro
		Lighting.OutdoorAmbient = Color3.fromRGB(60, 66, 98) -- azul noche
		Lighting.Ambient = Color3.fromRGB(38, 42, 64)
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if not sky then sky = Instance.new("Sky"); sky.Parent = Lighting end
		sky.StarCount = 3000            -- estrellas densas de fondo (Roblox las pinta gratis de noche)
		sky.CelestialBodiesShown = true -- luna
		-- CONSTELACION de acento: estrellas MAS brillantes en un patron alto en el cielo. Neon = brilla solo
		-- (movil-safe), Anchored, sin colision. Se reconstruye limpio cada arranque del lobby.
		local viejaC = workspace:FindFirstChild("ConstelacionLobby"); if viejaC then viejaC:Destroy() end
		local cielo = Instance.new("Folder"); cielo.Name = "ConstelacionLobby"; cielo.Parent = workspace
		local base = Vector3.new(560, 380, -140)
		local patron = { Vector3.new(0, 0, 0), Vector3.new(34, 26, -12), Vector3.new(70, 14, -26), Vector3.new(104, -8, -16), Vector3.new(58, -24, -42), Vector3.new(24, -8, -52), Vector3.new(-18, 30, -28) }
		for i, off in ipairs(patron) do
			local st = Instance.new("Part")
			st.Name = "Estrella"; st.Shape = Enum.PartType.Ball
			st.Size = Vector3.new(3.4, 3.4, 3.4) * ((i % 3 == 0) and 1.7 or 1)
			st.Anchored = true; st.CanCollide = false; st.CanQuery = false; st.CanTouch = false; st.CastShadow = false
			st.Material = Enum.Material.Neon; st.Color = Color3.fromRGB(206, 220, 255)
			st.CFrame = CFrame.new(base + off * 1.6)
			st.Parent = cielo
		end
	end

	return puestos
end

return LobbyBuilder
