-- Boss (ModuleScript del SERVIDOR) - motor genérico de jefes (data-driven).
-- Boss.spawn(tipo, posicion) -> (modelo, humanoid, def). Lee de BossData. El jefe persigue,
-- pega de cerca, y ejecuta HABILIDADES según su FASE de vida (definidas en BossData.Fases):
--   pisoton       = aviso telegrafiado en el suelo + daño en área (esquivable)
--   rafaga        = ráfaga radial de proyectiles (esquivar moviéndose)
--   megaProyectil = bola enorme lenta dirigida que insta-mata (esquivar de lado)
--   invocar       = invoca minions
-- Manda su vida al HUD (BossHealth) para la barra del jefe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")

-- Sju (arte): mesh por JEFE (ServerStorage.BossMeshes.<clave>). Aqui el presupuesto es mucho mas generoso que
-- en la horda (~3000 triangulos vs ~800) porque solo hay UN jefe en pantalla: el coste no se multiplica por 50.
local BOSS_MESHES = ServerStorage:FindFirstChild("BossMeshes")

local BossData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("BossData"))
local Enemy = require(script.Parent:WaitForChild("Enemy"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local bossHealth = remotes:WaitForChild("BossHealth")

local Boss = {}

local function jugadorMasCercano(desde)
	local mejor, distMin = nil, math.huge
	for _, jugador in ipairs(Players:GetPlayers()) do
		local pj = jugador.Character
		local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
		local hum = pj and pj:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - desde).Magnitude
			if d < distMin then distMin = d; mejor = hrp end
		end
	end
	return mejor
end

-- Disco AoE telegrafiado en el suelo: aviso 'tiempo' seg y estalla danando en area.
local function discoAoE(pos, radio, dano, tiempo, color)
	local aviso = Instance.new("Part")
	aviso.Name = "Telegraph"; aviso.Shape = Enum.PartType.Cylinder
	aviso.Size = Vector3.new(0.4, radio * 2, radio * 2)
	aviso.CFrame = CFrame.new(pos.X, 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	aviso.Anchored = true; aviso.CanCollide = false; aviso.CanQuery = false
	aviso.Material = Enum.Material.Neon; aviso.Color = color or Color3.fromRGB(255, 60, 60); aviso.Transparency = 0.65
	aviso.Parent = workspace
	task.delay(tiempo, function()
		for _, jugador in ipairs(Players:GetPlayers()) do
			local pj = jugador.Character
			local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
			local hum = pj and pj:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local d = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
				if d <= radio then Enemy.golpearJugador(hum, dano) end
			end
		end
		aviso.Transparency = 0.1
		TweenService:Create(aviso, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(aviso, 0.3)
	end)
end

-- Pisoton: un disco AoE bajo el jugador.
local function pisoton(pos, def)
	discoAoE(pos, def.RadioPisoton, def.DanoPisoton, def.TiempoTelegraph)
end

-- Terremoto (King): ANILLO de discos que erupcionan alrededor del jefe (esquivar entre ellos).
local function terremoto(centro, def)
	local n = def.TerremotoDiscos or 8
	local rAnillo = def.TerremotoRadio or 18
	for i = 1, n do
		local ang = (i / n) * math.pi * 2
		discoAoE(centro + Vector3.new(math.cos(ang) * rAnillo, 0, math.sin(ang) * rAnillo), 7, (def.DanoPisoton or 35) * 0.8, def.TiempoTelegraph, Color3.fromRGB(170, 110, 50))
	end
end

-- Lluvia (Cannon): varios discos caen alrededor del jugador (hay que moverse).
local function lluvia(objetivoHrp, def)
	local n = def.LluviaDiscos or 6
	local centro = objetivoHrp.Position
	for _ = 1, n do
		local off = Vector3.new(math.random(-22, 22), 0, math.random(-22, 22))
		discoAoE(centro + off, 6, (def.DanoPisoton or 30) * 0.85, (def.TiempoTelegraph or 1) * 0.9, Color3.fromRGB(80, 160, 255))
	end
end

-- Dibuja un ANILLO (banda/cordon) de radio 'radio' con segmentos neon. Devuelve las partes.
local function anilloBanda(centro, radio, grosor, color)
	local partes = {}
	local n = math.clamp(math.floor(radio * 0.8), 12, 26)
	local arco = (2 * math.pi * radio) / n + 0.6
	for k = 1, n do
		local ang = (k / n) * math.pi * 2
		local pos = centro + Vector3.new(math.cos(ang) * radio, 0.4, math.sin(ang) * radio)
		local p = Instance.new("Part")
		p.Name = "Telegraph"
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
		p.Material = Enum.Material.Neon; p.Color = color; p.Transparency = 0.4
		p.Size = Vector3.new(grosor * 2, 0.3, arco)
		p.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(ang), 0, math.cos(ang)))
		p.Parent = workspace
		partes[#partes + 1] = p
	end
	return partes
end

-- Onda expansiva (esquivable A PIE): NO es un circulo relleno, es un CORDON/anillo que se expande por
-- ticks de dentro hacia fuera. El CENTRO y los HUECOS entre anillos son seguros (melee aguanta cerca).
local function ondaExpansiva(centro, def)
	local pasos = def.OndaPasos or 4
	local paso = def.OndaPaso or 9
	local grosor = def.OndaGrosor or 3
	local intervalo = def.OndaIntervalo or 0.45
	local aviso = def.OndaAviso or 0.5
	local dano = (def.DanoPisoton or 35) * 0.7
	for i = 1, pasos do
		local radio = i * paso
		task.delay((i - 1) * intervalo, function()
			local partes = anilloBanda(centro, radio, grosor, Color3.fromRGB(255, 140, 40))
			task.delay(aviso, function()
				for _, jugador in ipairs(Players:GetPlayers()) do
					local pj = jugador.Character
					local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
					local h = pj and pj:FindFirstChildOfClass("Humanoid")
					if hrp and h and h.Health > 0 then
						local d = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(centro.X, 0, centro.Z)).Magnitude
						if math.abs(d - radio) <= grosor then Enemy.golpearJugador(h, dano) end
					end
				end
				for _, p in ipairs(partes) do
					p.Color = Color3.fromRGB(255, 60, 30)
					TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play()
					Debris:AddItem(p, 0.3)
				end
			end)
		end)
	end
end

-- Un proyectil del jefe: daña al JUGADOR, atraviesa enemigos, se para en el mundo.
local function bossProyectil(origen, dir, def)
	local b = Instance.new("Part")
	b.Name = "BalaEnemiga"
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(1.2, 1.2, 1.2)
	b.Color = def.ColorProyectil
	b.Material = Enum.Material.Neon
	b.CanCollide = false; b.CanQuery = false; b.CastShadow = false
	b.Position = origen + dir * 4
	b.Parent = workspace
	local att = Instance.new("Attachment"); att.Parent = b
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att; lv.RelativeTo = Enum.ActuatorRelativeTo.World; lv.MaxForce = math.huge
	lv.VectorVelocity = dir * (def.VelProyectil or 45); lv.Parent = b
	Debris:AddItem(b, def.VidaProyectil or 4)
	local hit = false
	b.Touched:Connect(function(otro)
		if hit then return end
		if otro.Name == "Bala" or otro.Name == "BalaEnemiga" then return end
		local modelo = otro:FindFirstAncestorOfClass("Model")
		if modelo and Players:GetPlayerFromCharacter(modelo) then
			local hum = modelo:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then hit = true; Enemy.golpearJugador(hum, def.DanoProyectil or 18); b:Destroy() end
			return
		end
		if modelo and modelo.Name == "BrainrotEnemy" then return end
		hit = true; b:Destroy()
	end)
end

-- Ráfaga radial: N proyectiles repartidos en círculo (esquivar moviéndose).
local function rafaga(origen, def)
	local n = def.RafagaProyectiles or 12
	for i = 1, n do
		local ang = (i / n) * math.pi * 2
		bossProyectil(origen + Vector3.new(0, 3, 0), Vector3.new(math.cos(ang), 0, math.sin(ang)), def)
	end
end

-- Mega proyectil: bola ENORME y LENTA dirigida al jugador que INSTA-MATA (esquívala de lado).
local function megaProyectil(origen, objetivoHrp, def)
	local dir = objetivoHrp.Position - origen
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit
	local b = Instance.new("Part")
	b.Name = "BalaEnemiga"
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(6, 6, 6)
	b.Color = def.ColorProyectil
	b.Material = Enum.Material.Neon
	b.CanCollide = false; b.CanQuery = false; b.CastShadow = false
	b.Position = origen + dir * 6
	b.Parent = workspace
	local att = Instance.new("Attachment"); att.Parent = b
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att; lv.RelativeTo = Enum.ActuatorRelativeTo.World; lv.MaxForce = math.huge
	lv.VectorVelocity = dir * (def.VelMega or 16); lv.Parent = b
	Debris:AddItem(b, def.VidaMega or 8)
	local hit = false
	b.Touched:Connect(function(otro)
		if hit then return end
		if otro.Name == "Bala" or otro.Name == "BalaEnemiga" then return end
		local modelo = otro:FindFirstAncestorOfClass("Model")
		if modelo and Players:GetPlayerFromCharacter(modelo) then
			local hum = modelo:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then hit = true; hum:TakeDamage(hum.MaxHealth * 10); b:Destroy() end
			return
		end
		if modelo and modelo.Name == "BrainrotEnemy" then return end
		hit = true; b:Destroy()
	end)
end

-- Linea/rayo telegrafiado: aviso largo y fino hacia el jugador; dana a lo largo de la linea.
-- def.LineasAbanico > 1 dispara un ABANICO de lineas (jefes finales = ataques menos sosos).
local function lineaLaser(origen, objetivoHrp, def)
	local hacia = objetivoHrp.Position - origen
	hacia = Vector3.new(hacia.X, 0, hacia.Z)
	if hacia.Magnitude < 0.1 then return end
	hacia = hacia.Unit
	local largo = def.LargoLinea or 70
	local ancho = def.AnchoLinea or 7
	local base = Vector3.new(origen.X, 0, origen.Z)
	local n = def.LineasAbanico or 1
	for i = 1, n do
		local off = (n == 1) and 0 or ((i - 1) / (n - 1) - 0.5) * math.rad(50)
		local c, s = math.cos(off), math.sin(off)
		local dir = Vector3.new(hacia.X * c - hacia.Z * s, 0, hacia.X * s + hacia.Z * c)
		local centro = Vector3.new(base.X, 0.3, base.Z) + dir * (largo / 2)
		local aviso = Instance.new("Part")
		aviso.Name = "Telegraph"
		aviso.Size = Vector3.new(ancho, 0.4, largo)
		aviso.CFrame = CFrame.lookAt(centro, centro + dir)
		aviso.Anchored = true; aviso.CanCollide = false; aviso.CanQuery = false
		aviso.Material = Enum.Material.Neon
		aviso.Color = Color3.fromRGB(255, 120, 40)
		aviso.Transparency = 0.6
		aviso.Parent = workspace
		task.delay(def.TiempoTelegraph, function()
			for _, jugador in ipairs(Players:GetPlayers()) do
				local pj = jugador.Character
				local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
				local hum = pj and pj:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local rel = Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - base
					local along = rel:Dot(dir)
					local perp = (rel - dir * along).Magnitude
					if along >= -2 and along <= largo and perp <= ancho / 2 then
						Enemy.golpearJugador(hum, def.DanoLinea or def.DanoPisoton or 35)
					end
				end
			end
			aviso.Transparency = 0.1
			TweenService:Create(aviso, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			Debris:AddItem(aviso, 0.3)
		end)
	end
end

-- Invoca minions alrededor del jefe.
local function invocar(origen, def)
	local n = def.MinionsPorInvocacion or 3
	for i = 1, n do
		local ang = (i / n) * math.pi * 2
		Enemy.spawn(def.TipoMinion, origen + Vector3.new(math.cos(ang) * 8, 2, math.sin(ang) * 8))
	end
end

-- Fase actual según la fracción de vida (Fases ordenadas de mayor a menor umbral).
local function faseActual(def, frac)
	local elegida = def.Fases[1]
	for _, f in ipairs(def.Fases) do
		if frac <= f.umbral then elegida = f end
	end
	return elegida
end

function Boss.spawn(tipo, posicion)
	local def = BossData[tipo] or BossData.ForestWarden

	local enemigo = Instance.new("Model")
	enemigo.Name = "BrainrotEnemy" -- así las armas y la limpieza lo tratan como enemigo
	enemigo:SetAttribute("Boss", true)
	enemigo:SetAttribute("Tipo", tipo)

	local raiz = Instance.new("Part")
	raiz.Name = "HumanoidRootPart"
	raiz.Size = def.Tam
	raiz.Color = def.ColorCuerpo
	raiz.Material = Enum.Material.SmoothPlastic
	raiz.Position = posicion
	raiz.Parent = enemigo

	local cabeza = Instance.new("Part")
	cabeza.Name = "Head"
	cabeza.Shape = Enum.PartType.Ball
	cabeza.Size = def.TamCabeza
	cabeza.Color = def.ColorCabeza
	cabeza.Position = posicion + Vector3.new(0, def.Tam.Y / 2 + def.TamCabeza.Y / 2, 0)
	cabeza.Parent = enemigo

	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = raiz
	soldadura.Part1 = cabeza
	soldadura.Parent = raiz

	-- Vida escalada + Fix D: escala con mundo/acto/DIFICULTAD. El x1.8 de oleada SOLO en Endless (en campana el 4600 nominal engañaba: salia 11k).
	local oleada = workspace:GetAttribute("Oleada") or 5
	local bDano = workspace:GetAttribute("BossDanoMult") or 1 -- Fix D: dano del jefe escala con dificultad (fijo esta run)
	local oleadaFactor = workspace:GetAttribute("EsEndless") and (1 + math.max(0, (oleada - 5) / 5) * 0.4) or 1 -- x1.8 por oleada SOLO en Endless
	local vidaEscalada = math.floor(def.Vida * oleadaFactor * (workspace:GetAttribute("CoopBossMult") or 1) * (workspace:GetAttribute("BossVidaMult") or 1)) -- co-op + Fix D: dificultad
	-- Fix D (completo): las HABILIDADES tambien escalan su dano con la dificultad. defEsc = def con los danos xbDano
	-- (metatabla: hereda TODOS los demas campos de def sin mutar la tabla COMPARTIDA de BossData).
	local defEsc = setmetatable({
		Dano = (def.Dano or 0) * bDano,
		DanoPisoton = (def.DanoPisoton or 0) * bDano,
		DanoProyectil = (def.DanoProyectil or 0) * bDano,
		DanoLinea = (def.DanoLinea or 0) * bDano,
	}, { __index = def })
	local humano = Instance.new("Humanoid")
	humano.MaxHealth = vidaEscalada
	humano.Health = vidaEscalada
	humano.WalkSpeed = def.Velocidad
	humano.Parent = enemigo

	-- VISUAL con mesh (Sju), igual que en Enemy: la raiz y la cabeza siguen siendo la fisica/hitbox y solo se
	-- vuelven invisibles. Aqui SI nos permitimos detalle (3000 triangulos frente a ~800 de la horda) porque solo
	-- hay UN jefe en pantalla; el coste no se multiplica por 50.
	local plantillaJefe = BOSS_MESHES and BOSS_MESHES:FindFirstChild(tipo)
	if plantillaJefe then
		local alturaObjetivo = def.Tam.Y + def.TamCabeza.Y
		local escala = alturaObjetivo / math.max(plantillaJefe.Size.Y, 0.1)
		local visual = plantillaJefe:Clone()
		visual.Name = "Visual"
		visual.Size = plantillaJefe.Size * escala
		visual.CanCollide = false
		visual.CanQuery = false
		visual.CanTouch = false
		visual.Massless = true
		visual.CastShadow = false -- igual que en Enemy: el mesh es lo unico visible y mueve el shadow map cada frame
		visual.Position = posicion + Vector3.new(0, -def.Tam.Y / 2 + visual.Size.Y / 2, 0)
		visual.Parent = enemigo
		local sv = Instance.new("WeldConstraint")
		sv.Part0 = raiz
		sv.Part1 = visual
		sv.Parent = raiz
		raiz.Transparency = 1
		cabeza.Transparency = 1
	end

	enemigo.PrimaryPart = raiz
	-- misma carpeta que la horda: todos los enemigos viven en workspace.Enemies (ver Enemy.luau)
	enemigo.Parent = workspace:FindFirstChild("Enemies") or workspace

	humano.Died:Connect(function()
		bossHealth:FireAllClients({ dead = true })
		task.wait(2)
		enemigo:Destroy()
	end)

	-- Barra de vida en pantalla (se actualiza mientras vive). Mandamos tambien los umbrales de FASE
	-- para que el HUD dibuje los segmentos divisorios + cambie el color de la barra por fase.
	local umbralesFase = {}
	for _, f in ipairs(def.Fases) do umbralesFase[#umbralesFase + 1] = f.umbral end
	task.spawn(function()
		while enemigo.Parent and humano.Health > 0 do
			bossHealth:FireAllClients({ name = def.Nombre, current = humano.Health, max = humano.MaxHealth, umbrales = umbralesFase })
			task.wait(0.15)
		end
	end)

	-- IA de movimiento + golpe por cercanía.
	local rango = (def.Tam.X / 2) + 4
	local puedeGolpear = true
	local cargandoBoss = false -- embestida (Mega): rafaga de velocidad
	local objetivoCarga = nil -- punto MAS ALLA del jugador al que embiste (overshoot)
	local atTop = Instance.new("Attachment"); atTop.Position = Vector3.new(0, def.Tam.Y / 2, 0); atTop.Parent = raiz
	local atBot = Instance.new("Attachment"); atBot.Position = Vector3.new(0, -def.Tam.Y / 2, 0); atBot.Parent = raiz
	local trailCarga = Instance.new("Trail")
	trailCarga.Attachment0 = atTop; trailCarga.Attachment1 = atBot
	trailCarga.Lifetime = 0.35; trailCarga.LightEmission = 1; trailCarga.FaceCamera = true
	trailCarga.Color = ColorSequence.new(def.ColorCabeza or Color3.fromRGB(255, 90, 90))
	trailCarga.WidthScale = NumberSequence.new(1, 0)
	trailCarga.Enabled = false
	trailCarga.Parent = raiz
	task.spawn(function()
		while enemigo.Parent and humano.Health > 0 do
			if workspace:GetAttribute("Congelado") then humano.WalkSpeed = 0; task.wait(0.15); continue end
			-- *SlowMult = Frostbite/Hielo: este bucle tambien reescribe WalkSpeed, asi que sin esto el jefe
			-- ignoraba por completo el ralentizado (igual que pasaba con los enemigos normales).
			humano.WalkSpeed = (cargandoBoss and (def.Velocidad * (def.EmbestidaMult or 3)) or def.Velocidad) * (enemigo:GetAttribute("SlowMult") or 1)
			local objetivo = jugadorMasCercano(raiz.Position)
			if objetivo then
				if cargandoBoss and objetivoCarga then humano:MoveTo(objetivoCarga) else humano:MoveTo(objetivo.Position) end
				local dist = (objetivo.Position - raiz.Position).Magnitude
				-- Mirar al jugador cuando esta CERCA/quieto. Persiguiendo de lejos ya gira solo (AutoRotate hacia
				-- el MoveTo), pero al llegar y quedarse quieto atacando el MoveTo apenas mueve -> el modelo se
				-- quedaba de lado (reportado en playtest). Cosmetico: solo cambiamos la ORIENTACION, no la
				-- posicion (CFrame.new(pos, objetivo) => misma pos, mira al jugador). No se toca en plena carga.
				if not cargandoBoss and dist <= rango + 3 then
					raiz.CFrame = CFrame.new(raiz.Position, Vector3.new(objetivo.Position.X, raiz.Position.Y, objetivo.Position.Z))
				end
				if dist <= rango and puedeGolpear then
					local pjHum = objetivo.Parent and objetivo.Parent:FindFirstChildOfClass("Humanoid")
					if pjHum and pjHum.Health > 0 then
						puedeGolpear = false
						Enemy.golpearJugador(pjHum, defEsc.Dano) -- Fix D: escala + mitigacion del jugador (armadura/esquivar/i-frames del Dash; antes el jefe pegaba directo)
						task.delay(def.EnfriamientoDano, function() puedeGolpear = true end)
					end
				end
			end
			task.wait(0.2)
		end
	end)

	-- Habilidades según la fase de vida.
	task.spawn(function()
		task.wait(def.PrimeraHabilidad or 3)
		local idx = 0
		while enemigo.Parent and humano.Health > 0 do
			if workspace:GetAttribute("Congelado") then task.wait(0.2); continue end
			local fase = faseActual(def, humano.Health / humano.MaxHealth)
			local habs = fase.habilidades
			idx = idx % #habs + 1
			local hab = habs[idx]
			local objetivo = jugadorMasCercano(raiz.Position)
			if hab == "pisoton" and objetivo then
				pisoton(objetivo.Position, defEsc)
			elseif hab == "rafaga" then
				rafaga(raiz.Position, defEsc)
			elseif hab == "megaProyectil" and objetivo then
				megaProyectil(raiz.Position + Vector3.new(0, 3, 0), objetivo, defEsc)
			elseif hab == "lineaBarrido" and objetivo then
				lineaLaser(raiz.Position, objetivo, defEsc)
			elseif hab == "invocar" then
				invocar(raiz.Position, defEsc)
			elseif hab == "terremoto" then
				terremoto(raiz.Position, defEsc)
			elseif hab == "lluvia" and objetivo then
				lluvia(objetivo, defEsc)
			elseif hab == "ondaExpansiva" then
				ondaExpansiva(raiz.Position, defEsc)
			elseif hab == "embestida" and objetivo then
				lineaLaser(raiz.Position, objetivo, defEsc) -- avisa el camino de la embestida
				local dCarga = objetivo.Position - raiz.Position
				dCarga = Vector3.new(dCarga.X, 0, dCarga.Z)
				dCarga = (dCarga.Magnitude < 0.1) and raiz.CFrame.LookVector or dCarga.Unit
				objetivoCarga = objetivo.Position + dCarga * (def.EmbestidaOvershoot or 26) -- se pasa del jugador
				trailCarga.Enabled = true
				cargandoBoss = true
				task.delay(def.DuracionEmbestida or 1.2, function() cargandoBoss = false; trailCarga.Enabled = false end)
			end
			task.wait(fase.cadencia or 3)
		end
	end)

	return enemigo, humano, def
end

return Boss
