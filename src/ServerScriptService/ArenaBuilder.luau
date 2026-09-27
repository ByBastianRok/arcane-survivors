-- ArenaBuilder (ModuleScript del SERVIDOR) · Sju - construye la ARENA del mundo en curso a partir de WorldArt.
-- Antes los 3 mundos compartian el Baseplate por defecto con un tinte, asi que Frost y Ember se sentian
-- exactamente igual que Woods. Esto le da a cada mundo su suelo, su cielo, su niebla, su terreno y su clima.
--
-- Por que Parts y no Terrain de Roblox (decision con Bastian): el terreno voxel pesa bastante mas en movil y su
-- relieve TAPA la horda. En un survivors tu unica defensa es moverte, asi que necesitas ver de donde te viene
-- todo: un suelo legible gana a uno bonito que esconde enemigos.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local WorldArt = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WorldArt"))
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local ArenaBuilder = {}
local PROPS = ServerStorage:FindFirstChild("WorldProps")

-- Estado del sitio al que hay que VOLVER al acabar la run: si no, vuelves del mundo de hielo y el lobby se
-- queda con niebla azul y de noche para siempre.
--
-- OJO CON EL CUANDO, que aqui me la pegue: esto se guardaba al CARGAR EL MODULO. Y el modulo se carga cuando
-- GameManager hace su require, o sea ANTES de que LobbyBuilder monte el lobby y le ponga SU luz (hora dorada,
-- ambiente calido y la niebla floja que deja ver el archipielago). Resultado: al terminar la primera run,
-- limpiar() "restauraba" la luz de ANTES del lobby y el lobby perdia su aspecto hasta reiniciar el server.
-- Sin ningun error, y solo se ve si acabas una partida y vuelves.
-- Ahora la foto se toma en la PRIMERA construccion de arena, cuando el lobby ya esta montado y su luz puesta.
local LUZ_BASE, ATMO_BASE
local BASE_ORIG
-- El Atmosphere es quien manda de verdad sobre la niebla (su sola presencia anula Fog*), asi que hay que
-- guardarlo y restaurarlo igual que el resto de la luz.
local ATMO = Lighting:FindFirstChildOfClass("Atmosphere")

local function guardarBaseUnaVez()
	if LUZ_BASE then return end
	LUZ_BASE = {
		FogColor = Lighting.FogColor, FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd,
		Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness,
	}
	ATMO_BASE = ATMO and {
		Density = ATMO.Density, Haze = ATMO.Haze, Glare = ATMO.Glare,
		Color = ATMO.Color, Decay = ATMO.Decay,
	} or nil
end

-- PELIGROS activos del mundo en curso + bucle que aplica su dano. 'generacion' mata el bucle viejo cuando se
-- reconstruye la arena o se limpia: si no, al encadenar actos quedarian varios bucles vivos haciendo dano a la vez.
local peligros = {}
local generacion = 0

local function arrancarBuclePeligros()
	generacion += 1
	local mia = generacion
	task.spawn(function()
		while mia == generacion do
			task.wait(0.35) -- el dano es POR SEGUNDO, no hace falta afinar mas (y asi cuesta nada)
			-- Congelado = oferta de cartas abierta: el jugador NO puede moverse, asi que cobrarle dano ahi
			-- seria dano inevitable. Se salta.
			if workspace:GetAttribute("Congelado") then continue end
			for _, pl in ipairs(Players:GetPlayers()) do
				local ch = pl.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				-- ALTURA: la comprobacion es en XZ, asi que sin este filtro cualquiera cuyo X/Z caiga sobre un
				-- charco recibe dano AUNQUE NO ESTE EN LA ARENA. Y pasa de verdad: el LOBBY esta en
				-- (300, 52, 0), a solo 300 studs del centro en XZ, o sea DENTRO del disco de radio 600 -> los
				-- jugadores perdian vida estando quietos en el lobby. Los peligros estan a ras de suelo (y~0),
				-- asi que basta con exigir que el jugador este a la altura del suelo de la arena.
				if hrp and hum and hum.Health > 0 and math.abs(hrp.Position.Y) < 14 then
					local px, pz = hrp.Position.X, hrp.Position.Z
					for _, pel in ipairs(peligros) do
						local dx, dz = px - pel.pos.X, pz - pel.pos.Z
						if dx * dx + dz * dz <= pel.r * pel.r then
							hum:TakeDamage(pel.dano * 0.35) -- dano/segundo prorrateado al tick
							break -- solo UNO por tick: dos charcos solapados no deben doblar el dano
						end
					end
				end
			end
		end
	end)
end

local function quitarArena()
	local vieja = workspace:FindFirstChild("Arena")
	if vieja then vieja:Destroy() end
end

function ArenaBuilder.limpiar()
	generacion += 1 -- mata el bucle de peligros
	table.clear(peligros)
	quitarArena()
	for prop, valor in pairs(LUZ_BASE) do Lighting[prop] = valor end
	if ATMO and ATMO.Parent and ATMO_BASE then
		for prop, valor in pairs(ATMO_BASE) do ATMO[prop] = valor end
	end
	local base = workspace:FindFirstChild("Baseplate")
	if base and base:IsA("BasePart") and BASE_ORIG then
		base.Color = BASE_ORIG.Color
		base.Material = BASE_ORIG.Material
		-- La transparencia tambien: en el place del lobby volvia invisible (es la placa gris que se ve desde
		-- la isla flotante) y en el de juego se queda visible, porque ahi su valor original ya era 0.
		base.Transparency = BASE_ORIG.Transparency or 0
	end
	workspace:SetAttribute("MundoArte", nil) -- el cliente apaga el clima al ver esto
end

-- Punto aleatorio dentro del disco jugable, EXCLUYENDO el centro (ahi arranca la run y debe estar despejado).
-- El sqrt es lo que reparte por AREA: sin el, todo se amontona en el centro.
local function puntoEnDisco(rng, centro)
	local r = WorldArt.RadioLimpio + math.sqrt(rng:NextNumber()) * (WorldArt.RadioArena - WorldArt.RadioLimpio)
	local a = rng:NextNumber() * math.pi * 2
	return centro.X + math.cos(a) * r, centro.Z + math.sin(a) * r
end

function ArenaBuilder.construir(worldId)
	-- ANTES de tocar una sola propiedad de Lighting: esta es la foto a la que volvera limpiar().
	guardarBaseUnaVez()
	quitarArena()
	local art = WorldArt.de(worldId)
	local centro = Config.ArenaPos
	local R = WorldArt.RadioArena
	local carpeta = Instance.new("Folder")
	carpeta.Name = "Arena"
	carpeta.Parent = workspace

	-- Semilla FIJA por mundo: el mapa sale siempre igual (un sitio reconocible), no ruido nuevo cada partida.
	-- Endless pasa la clave string "endless" (tonumber -> nil): le damos su propia semilla fija (47) para que su
	-- distribucion NO calque la de Woods (seria el mismo mapa con otro tinte).
	local rng = Random.new(9000 + (tonumber(worldId) or 47))

	-- SUELO: disco. Su cara superior queda a y=0.05, JUSTO por encima del techo del Baseplate (y=0). Esos 5
	-- centesimos son imperceptibles y no tocan spawns ni teleports, pero son imprescindibles: a y=0 exacto las
	-- dos superficies quedan COPLANARES -> z-fighting y se ve el grid gris de Studio en vez del suelo del mundo.
	local suelo = Instance.new("Part")
	suelo.Name = "Suelo"
	suelo.Shape = Enum.PartType.Cylinder
	suelo.Size = Vector3.new(2, R * 2, R * 2)
	suelo.CFrame = CFrame.new(centro.X, -0.95, centro.Z) * CFrame.Angles(0, 0, math.rad(90))
	suelo.Anchored = true
	suelo.Color = art.suelo.color
	suelo.Material = art.suelo.material
	suelo.TopSurface = Enum.SurfaceType.Smooth
	suelo.Parent = carpeta

	-- PARCHES de terreno: manchas planas de otro material repartidas por el suelo. Sin esto el disco es una
	-- superficie lisa gigante y se nota muchisimo que es una pieza. En Ember son CHARCOS DE LAVA (Neon) y dan
	-- practicamente todo el caracter del mundo. Van a y=0.07, justo encima del suelo.
	local pa = art.parches
	if pa then
		for _ = 1, pa.n do
			local x, z = puntoEnDisco(rng, centro)
			local p = Instance.new("Part")
			p.Name = "Parche"
			p.Shape = Enum.PartType.Cylinder
			local d = rng:NextNumber(pa.radioMin, pa.radioMax) * 2
			p.Size = Vector3.new(0.6, d, d)
			p.CFrame = CFrame.new(x, -0.23, z) * CFrame.Angles(0, 0, math.rad(90))
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			p.CastShadow = false -- ~300 adornos proyectando sombra dinamica es coste puro en movil, y no aportan nada
			p.Color = pa.color
			p.Material = pa.material
			p.Parent = carpeta
		end
	end

	-- PROPS por CLUSTERES. Un bucle de angulos equiespaciados se lee como una VALLA; grupos irregulares a
	-- distancias distintas se leen como un sitio. Sin colision: pueden estar dentro del area de juego sin
	-- atascar a los enemigos (que no tienen pathfinding).
	local puestos = 0
	if PROPS then
		for _, grupo in ipairs(art.props) do
			local plantilla = PROPS:FindFirstChild(grupo.mesh)
			if plantilla then
				for _ = 1, grupo.clusters do
					local cx, cz = puntoEnDisco(rng, centro)
					for _ = 1, rng:NextInteger(grupo.porCluster[1], grupo.porCluster[2]) do
						local ja = rng:NextNumber() * math.pi * 2
						local jr = rng:NextNumber() * grupo.radioCluster
						local escala = rng:NextNumber(grupo.escala[1], grupo.escala[2])
						local p = plantilla:Clone()
						p.Size = plantilla.Size * escala
						p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
						p.CastShadow = false -- ~1000 props con sombra dinamica hunden el movil, y son adornos de fondo
						if grupo.tinte then p.Color = grupo.tinte end
						p.CFrame = CFrame.new(cx + math.cos(ja) * jr, p.Size.Y / 2 - 0.4, cz + math.sin(ja) * jr)
							* CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0) -- rotacion libre: no se repite la silueta
						p.Parent = carpeta
						puestos += 1
					end
				end
			end
		end
	end

	-- PELIGROS: charcos que hacen dano MIENTRAS los pisas, pero que NO bloquean (se cruzan). Ver WorldArt para
	-- el porque: un obstaculo solido rompe la IA (sin pathfinding) y te acorrala en un genero donde moverte es
	-- tu unica defensa. Al ser dano POR SEGUNDO, cruzarlos rapido cuesta poco -> es una DECISION (atajo caro vs
	-- rodeo lento), no una trampa.
	-- SIN PointLight a proposito: 55 luces dinamicas se cargan el movil, y el material Neon ya brilla solo.
	table.clear(peligros)
	local pe = art.peligros
	if pe then
		for _ = 1, pe.n do
			local x, z = puntoEnDisco(rng, centro)
			local radio = rng:NextNumber(pe.radioMin, pe.radioMax)
			local p = Instance.new("Part")
			p.Name = "Peligro"
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.5, radio * 2, radio * 2)
			p.CFrame = CFrame.new(x, -0.12, z) * CFrame.Angles(0, 0, math.rad(90)) -- por encima de parches y suelo
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			p.CastShadow = false -- ~300 adornos proyectando sombra dinamica es coste puro en movil, y no aportan nada
			p.Color = pe.color
			p.Material = pe.material
			p:SetAttribute("Dano", pe.dano)
			p:SetAttribute("Peligro", pe.nombre)
			p.Parent = carpeta
			peligros[#peligros + 1] = { pos = Vector3.new(x, 0, z), r = radio, dano = pe.dano }
		end
		arrancarBuclePeligros()
	end

	-- GRIETAS NEON (decorativas, aura de nivel final): vetas de energia PLANAS sobre el suelo, sin colision. Una
	-- fraccion se marca "Palpita" (+fase aleatoria) para que RiftPulseClient las pulse. Neon brilla solo (movil-safe).
	local gr = art.grietas
	if gr then
		for _ = 1, gr.n do
			local x, z = puntoEnDisco(rng, centro)
			local p = Instance.new("Part")
			p.Name = "Grieta"
			p.Size = Vector3.new(rng:NextNumber(gr.largoMin, gr.largoMax), 0.35, rng:NextNumber(gr.anchoMin, gr.anchoMax))
			p.CFrame = CFrame.new(x, -0.10, z) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			p.Material = gr.material; p.Color = gr.color
			if rng:NextNumber() < (gr.palpitaFrac or 0) then p:SetAttribute("Palpita", rng:NextNumber() * math.pi * 2) end
			p.Parent = carpeta
		end
	end
	-- ESQUIRLAS DE ENERGIA (Neon) que SOBRESALEN del suelo: los cristales luminosos del Rift. Algunas palpitan.
	local cn = art.cristalesNeon
	if cn then
		for _ = 1, cn.n do
			local x, z = puntoEnDisco(rng, centro)
			local alto = rng:NextNumber(cn.altoMin, cn.altoMax)
			local gro = rng:NextNumber(cn.grosorMin, cn.grosorMax)
			local p = Instance.new("Part")
			p.Name = "EsquirlaRift"
			p.Size = Vector3.new(gro, alto, gro)
			p.CFrame = CFrame.new(x, alto / 2 - 0.6, z) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber() * math.pi * 2, rng:NextNumber(-0.35, 0.35))
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			p.Material = Enum.Material.Neon; p.Color = cn.colores[rng:NextInteger(1, #cn.colores)]
			if rng:NextNumber() < (cn.palpitaFrac or 0) then p:SetAttribute("Palpita", rng:NextNumber() * math.pi * 2) end
			p.Parent = carpeta
		end
	end

	-- LUZ, NIEBLA y CIELO del mundo (Lighting se replica solo, no hace falta remote).
	-- La niebla REAL va por el Atmosphere: mientras exista uno, Roblox ignora del todo las propiedades Fog*.
	-- Se dejan puestas igualmente por si algun dia se quita el Atmosphere, pero las que se ven son estas de abajo.
	if ATMO and ATMO.Parent and art.atmosfera then
		ATMO.Density = art.atmosfera.densidad
		ATMO.Haze = art.atmosfera.neblina
		ATMO.Glare = art.atmosfera.brillo or 0
		ATMO.Color = art.atmosfera.color
		ATMO.Decay = art.atmosfera.decaimiento
	end
	Lighting.FogColor = art.niebla.color
	Lighting.FogStart = art.niebla.inicio
	Lighting.FogEnd = art.niebla.fin
	Lighting.Ambient = art.ambiente
	Lighting.OutdoorAmbient = art.ambiente
	if art.cielo then
		Lighting.ClockTime = art.cielo.hora   -- Ember va de NOCHE: el cielo azul brillante cantaba en un volcan
		Lighting.Brightness = art.cielo.brillo
	end

	-- El Baseplate es el suelo infinito que rodea la arena: sin el, la arena parece una isla flotando sobre el
	-- vacio. Se tine con el color del mundo durante la run y se devuelve en limpiar().
	local base = workspace:FindFirstChild("Baseplate")
	if base and base:IsA("BasePart") then
		-- Se guarda TAMBIEN la transparencia, y no es un detalle: en el place del LOBBY, LobbyBuilder deja el
		-- Baseplate invisible (ahi es la placa gris fea que se ve desde la isla). Si la arena no lo vuelve a
		-- encender, la run se juega sobre el VACIO. Y al terminar hay que devolverlo a como estaba, o el lobby
		-- se queda con la placa puesta.
		if BASE_ORIG == nil then
			BASE_ORIG = { Color = base.Color, Material = base.Material, Transparency = base.Transparency }
		end
		base.Transparency = 0
		base.Color = art.borde.color:Lerp(Color3.fromRGB(0, 0, 0), 0.35)
		base.Material = art.borde.material
		-- Y SE LE QUITA LA CUADRICULA. El Baseplate de la plantilla de Studio lleva un HIJO Texture con el
		-- grid gris (rbxassetid://6372755229), y los hijos NO heredan ni el Color ni la transparencia del
		-- Part: se quedan pintando la rejilla ENCIMA del tinte. Resultado, y es lo que reporto Bastian
		-- jugando: media pantalla del mundo 1 con una cuadricula VERDE de horizonte a horizonte.
		-- Se apagan (no se borran) para que sea reversible.
		for _, hijo in ipairs(base:GetChildren()) do
			if hijo:IsA("Texture") or hijo:IsA("Decal") then hijo.Transparency = 1 end
		end
	end

	workspace:SetAttribute("MundoArte", worldId) -- el cliente lo lee para montar el CLIMA
	return puestos
end

return ArenaBuilder
