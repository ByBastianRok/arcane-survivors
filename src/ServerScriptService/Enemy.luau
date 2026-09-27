-- Enemy  (ModuleScript del SERVIDOR)  ·  Fabrica GENERICA de enemigos de FANTASIA
-- Crea cualquier tipo definido en EnemyData. Persigue al jugador más cercano y le hace
-- daño por CERCANÍA (no por contacto: así, si te subes encima del enemigo, igual te ataca).
-- El GameManager lo usa: Enemy.spawn(tipo, posicion) -> (modelo, humanoid).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

-- Sju (arte): meshes low-poly por TIPO de enemigo (ServerStorage.EnemyMeshes.<Tipo>). Es UN MeshPart extra por
-- enemigo, NO un rig R15: con 50 bichos en pantalla en movil, un rig (6 partes + Motor6D + Animator cada uno)
-- se lleva por delante el presupuesto. Los tipos que aun no tienen mesh siguen saliendo con las partes de color
-- de siempre (fallback), asi que esto se puede ir completando poco a poco sin romper nada.
local MESHES = ServerStorage:FindFirstChild("EnemyMeshes")

-- Carpeta workspace.Enemies: TODOS los enemigos viven aqui. Antes colgaban sueltos del workspace y 9 scripts
-- los buscaban recorriendo workspace por NOMBRE ("BrainrotEnemy"). Eso era tolerable con un workspace vacio,
-- pero la arena por mundo mete ~1500 partes: BulletClient hacia workspace:GetDescendants() 5 VECES POR SEGUNDO
-- en cada cliente, o sea ~8750 objetos/segundo solo para localizar enemigos. Con la carpeta se recorren 50.
local function carpetaEnemigos()
	local f = workspace:FindFirstChild("Enemies")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Enemies"
		f.Parent = workspace
	end
	return f
end

local EnemyData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("EnemyData"))
local EliteData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("EliteData"))
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local RunState = require(script.Parent:WaitForChild("RunState"))
local Drops = require(script.Parent:WaitForChild("Drops"))
local juice = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Juice")

-- Grupos de COLISION: los enemigos NO chocan con el jugador NI entre si (survivors: hordas que se
-- SOLAPAN y pegan por CERCANIA). Siguen chocando con el suelo (grupo Default por defecto). Arregla el
-- "tiron al acercarse / como si te esquivara" (antes se empujaban fisicamente). pcall = idempotente.
local PhysicsService = game:GetService("PhysicsService")
pcall(function() PhysicsService:RegisterCollisionGroup("Enemigos") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Jugadores") end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Enemigos", "Enemigos", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Enemigos", "Jugadores", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Jugadores", "Jugadores", false) end) -- J: los jugadores se ATRAVIESAN entre si (co-op: se amontonan, no se empujan)

local Enemy = {}

-- i-frames tras recibir un golpe: en hordas DENSAS, sin esto 15 enemigos encima te derriten de golpe (~260
-- dano/seg = muerte en <0.5s desde vida llena = injusto, anti-dopamina). Con 0.2s de invuln el dano entrante
-- se capa a ~5 golpes/seg -> tienes tiempo de reaccionar/Dash. Un golpe LETAL de un solo impacto sigue matando
-- (los i-frames solo bloquean los golpes SIGUIENTES, no reducen el que entra). Aprobado por Bastian el 22-jul.
local IFRAME_GOLPE = 0.2
local ultimoGolpe = {} -- [player] = os.clock() del ultimo golpe que SI le entro
Players.PlayerRemoving:Connect(function(p) ultimoGolpe[p] = nil end)

-- Aplica dano a un jugador teniendo en cuenta su reduccion de dano (carta Thick Skin) + i-frames.
local function golpearJugador(hum, dano)
	local jugador = hum and Players:GetPlayerFromCharacter(hum.Parent)
	if jugador then local mm = RunState.get(jugador); if mm.invulnerable or mm.invulnEligiendo then return end end -- INVINCIBLE (temporal) o eligiendo mejora
	if jugador and math.random() < (RunState.get(jugador).esquivar or 0) then return end -- S2: esquivar (Evasion)
	if jugador then
		local ahora = os.clock()
		if ahora - (ultimoGolpe[jugador] or 0) < IFRAME_GOLPE then return end -- dentro de los i-frames: ignora el golpe
		ultimoGolpe[jugador] = ahora
	end
	local mult = math.max(0.3, (jugador and RunState.get(jugador).danoRecibidoMult) or 1) -- tope: max 70% reduccion (anti-inmortal)
	hum:TakeDamage(dano * mult)
end
Enemy.golpearJugador = golpearJugador -- exportada: Boss aplica la MISMA mitigacion (armadura/esquivar/i-frames) al dano de jefe (antes lo ignoraba: pegaba directo)

-- Perf (A1): HRPs de jugadores VIVOS cacheados (1 coroutine los refresca) en vez de escanear Players
-- por CADA enemigo en CADA tick de IA (con hordas eso era O(enemigos) escaneos/frame -> lag).
local hrpsVivos = {}
task.spawn(function()
	while true do
		local nuevos = {}
		for _, jugador in ipairs(Players:GetPlayers()) do
			local pj = jugador.Character
			local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
			local hum = pj and pj:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then nuevos[#nuevos + 1] = hrp end
		end
		hrpsVivos = nuevos
		task.wait(0.1)
	end
end)

-- HumanoidRootPart del jugador vivo más cercano a una posición (lee la lista cacheada).
local function objetivoMasCercano(desde)
	local mejor, distMin = nil, math.huge
	for _, hrp in ipairs(hrpsVivos) do
		if hrp.Parent then
			local d = (hrp.Position - desde).Magnitude
			if d < distMin then distMin = d; mejor = hrp end
		end
	end
	return mejor
end

-- Explosión del Exploder: daña a los JUGADORES cercanos y revienta.
local function explotarEnemigo(pos, def)
	-- Visual: esfera neon que se expande y desvanece. NO usamos Explosion de Roblox
	-- porque rompe las articulaciones del jugador y lo mata de golpe; el daño lo damos a mano.
	juice:FireAllClients({ kind = "explosion", pos = pos })
	local s = Instance.new("Part")
	s.Shape = Enum.PartType.Ball
	s.Material = Enum.Material.Neon
	s.Color = Color3.fromRGB(255, 120, 60)
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.Size = Vector3.new(2, 2, 2)
	s.Position = pos
	s.Parent = workspace
	game:GetService("TweenService"):Create(s, TweenInfo.new(0.3),
		{ Size = Vector3.new(def.RadioExplosion * 2, def.RadioExplosion * 2, def.RadioExplosion * 2), Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(s, 0.4)
	for _, jugador in ipairs(Players:GetPlayers()) do
		local pj = jugador.Character
		local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
		local hum = pj and pj:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and (hrp.Position - pos).Magnitude <= def.RadioExplosion then
			golpearJugador(hum, def.DanoExplosion)
		end
	end
end

-- Proyectil de un enemigo a distancia (Ranged): daña al JUGADOR, atraviesa a otros enemigos.
local function dispararProyectilEnemigo(raiz, objetivoHrp, def)
	local origen = raiz.Position + Vector3.new(0, 1, 0)
	local dir = objetivoHrp.Position - origen
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit

	local bala = Instance.new("Part")
	bala.Name = "BalaEnemiga"
	bala.Shape = Enum.PartType.Ball
	bala.Size = Vector3.new(0.8, 0.8, 0.8)
	bala.Color = def.ColorDisparo
	bala.Material = Enum.Material.Neon
	bala.CanCollide = false
	bala.CanQuery = false
	bala.CastShadow = false
	bala.Position = origen + dir * 3
	bala.Parent = workspace

	local att = Instance.new("Attachment")
	att.Parent = bala
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.VectorVelocity = dir * def.VelocidadDisparo
	lv.Parent = bala

	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.2, 0); a0.Parent = bala
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.2, 0); a1.Parent = bala
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(def.ColorDisparo)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = bala

	Debris:AddItem(bala, def.VidaProyectil)

	local impacto = false
	bala.Touched:Connect(function(otro)
		if impacto then return end
		if otro.Name == "Bala" or otro.Name == "BalaEnemiga" then return end
		local modelo = otro:FindFirstAncestorOfClass("Model")
		-- Jugador: daño y se destruye.
		if modelo and Players:GetPlayerFromCharacter(modelo) then
			local hum = modelo:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				impacto = true
				golpearJugador(hum, def.DanoDisparo)
				bala:Destroy()
			end
			return
		end
		-- Otro enemigo: lo atraviesa (no daña a los suyos).
		if modelo and modelo.Name == "BrainrotEnemy" then return end
		-- Mundo: se para.
		impacto = true
		bala:Destroy()
	end)
end

-- ============ IA CENTRAL (Perf A2) ============
-- Antes: 1 coroutine POR enemigo (con hordas = cientos de bucles -> el server se retrasa -> tirones).
-- Ahora: UN solo bucle recorre el REGISTRO de todos los enemigos. El estado por-enemigo (puedeGolpear,
-- cargando, windup) vive en la tabla del registro; el Charger escribe cargando/windup ahi.
local rango = Config.Enemigos.RangoAtaque
local activos = {} -- activos[modelo] = { raiz, humano, def, afijoDef, puedeGolpear, cargando, windup }

-- Nº de enemigos VIVOS O(n) sobre el registro (incluye minions/split); reemplaza el re-escaneo de workspace.
function Enemy.vivos()
	local n = 0
	for _ in pairs(activos) do n += 1 end
	return n
end

task.spawn(function()
	while true do
		task.wait(0.2)
		local congelado = workspace:GetAttribute("Congelado")
		for modelo, e in pairs(activos) do
			local humano = e.humano
			if not (modelo.Parent and humano.Health > 0) then activos[modelo] = nil; continue end
			if congelado then humano.WalkSpeed = 0; continue end -- juego congelado (subir de nivel): parar
			local raiz, def, afijoDef = e.raiz, e.def, e.afijoDef
			local velBase = e.cargando and (def.Velocidad * (def.CargaMult or 2.5)) or def.Velocidad
			if afijoDef and afijoDef.Frenetico then local fr = 1 - humano.Health / humano.MaxHealth; velBase = velBase * (1 + fr * 0.8) + fr * 8 end -- + piso PLANO: en bases lentas (Tank champion) el enrage ahora SI amenaza (casi muerto ~+8 studs, supera al jugador)
			-- *SlowMult = Frostbite/Hielo. Este bucle es el DUENO de WalkSpeed (lo reescribe cada 0.2s), asi que
			-- si no aplica el slow aqui, el ralentizado que puso StatusEffects se borraba al siguiente tick.
			humano.WalkSpeed = (e.windup and 0 or velBase) * (modelo:GetAttribute("SlowMult") or 1)
			local objetivo = objetivoMasCercano(raiz.Position)
			if objetivo then
				local dist = (objetivo.Position - raiz.Position).Magnitude
				if def.Ranged then
					-- Ranged: mantiene distancia y dispara proyectiles.
					if dist > def.AlcancePreferido then
						humano:Move((objetivo.Position - raiz.Position).Unit)
					else
						humano:Move(Vector3.zero)
						if e.puedeGolpear then
							e.puedeGolpear = false
							dispararProyectilEnemigo(raiz, objetivo, def)
							task.delay(def.CadenciaDisparo, function() e.puedeGolpear = true end)
						end
					end
				elseif def.Explosivo then
					-- Exploder: al acercarse, explota (daño en área) y muere.
					humano:Move((objetivo.Position - raiz.Position).Unit)
					if dist <= rango + 1 then explotarEnemigo(raiz.Position, def); humano.Health = 0 end
				elseif def.Healer or def.Invoca then
					-- Healer / Summoner: mantiene distancia (no ataca; cura/invoca aparte).
					if dist > (def.AlcancePreferido or 26) then
						humano:Move((objetivo.Position - raiz.Position).Unit)
					elseif dist < (def.AlcancePreferido or 26) * 0.7 then
						humano:Move((raiz.Position - objetivo.Position).Unit)
					else
						humano:Move(Vector3.zero)
					end
				else
					-- Melee: perseguir y golpear de cerca.
					humano:Move((objetivo.Position - raiz.Position).Unit)
					if dist <= rango and e.puedeGolpear then
						local pjHum = objetivo.Parent and objetivo.Parent:FindFirstChildOfClass("Humanoid")
						if pjHum and pjHum.Health > 0 then
							e.puedeGolpear = false
							golpearJugador(pjHum, def.Dano)
							if afijoDef and afijoDef.RoboVida then humano.Health = math.min(humano.MaxHealth, humano.Health + def.Dano * 0.6) end
							task.delay(def.EnfriamientoDano, function() e.puedeGolpear = true end)
						end
					end
				end
			end
		end
	end
end)

-- Congelar YA al subir de nivel: el bucle de arriba solo revisa Congelado cada 0.2s, asi que al abrirse la
-- pantalla de talento los enemigos se deslizaban un instante. Esto los para en el MISMO frame del freeze.
workspace:GetAttributeChangedSignal("Congelado"):Connect(function()
	if workspace:GetAttribute("Congelado") then
		for _, e in pairs(activos) do
			if e.humano and e.humano.Parent then e.humano.WalkSpeed = 0 end
		end
	end
end)

-- Crea un enemigo de tipo 'tipo' en 'posicion' y enciende su IA. Devuelve (modelo, humanoid).
function Enemy.spawn(tipo, posicion, afijo)
	local base = EnemyData[tipo] or EnemyData.Chaser
	-- Copia de los datos para poder modificarlos con el afijo de élite.
	local def = {}
	for k, v in pairs(base) do def[k] = v end

	-- Afijos de elite: acepta nil | "Veloz" | {"Veloz","Gigante",...} (MEZCLA de mutaciones).
	local afijos = (type(afijo) == "table" and afijo) or (type(afijo) == "string" and { afijo }) or nil
	if afijos and #afijos == 0 then afijos = nil end
	local afijoDef = nil
	if afijos then
		local vidaM, veloM, danoM, escalaM, cashM, regenT = 1, 1, 1, 1, 1, 0
		local explota, radioExpl, danoExpl, roboVida, frenetico = false, 0, 0, false, false
		local color, mejorCash, prefijos = nil, -1, {}
		for _, key in ipairs(afijos) do
			local a = EliteData[key]
			if a then
				vidaM *= (a.Vida or 1); veloM *= (a.Velocidad or 1); danoM *= (a.Dano or 1)
				escalaM *= (a.Escala or 1); cashM *= (a.CashMult or 1); regenT += (a.Regen or 0)
				if a.ExplotaAlMorir then explota = true; radioExpl = math.max(radioExpl, a.RadioExplota or 14); danoExpl = math.max(danoExpl, a.DanoExplota or 45) end
				if a.RoboVida then roboVida = true end
				if a.Frenetico then frenetico = true end
				prefijos[#prefijos + 1] = a.Nombre
				if (a.CashMult or 1) > mejorCash then mejorCash = (a.CashMult or 1); color = a.Color end
			end
		end
		def.Vida = math.floor(base.Vida * vidaM)
		def.Velocidad = base.Velocidad * veloM
		def.Dano = base.Dano * danoM
		def.TamCuerpo = base.TamCuerpo * escalaM
		def.TamCabeza = base.TamCabeza * escalaM
		def.Cash = math.floor((base.Cash or 0) * cashM)
		-- afijoDef sintetico: el resto del codigo (nameplate/glow/regen) lo usa igual
		afijoDef = { Nombre = table.concat(prefijos, " "), Color = color, Regen = (regenT > 0) and regenT or nil, Explota = explota and { radio = radioExpl, dano = danoExpl } or nil, RoboVida = roboVida, Frenetico = frenetico }
	end
	-- Escalado de vida global: +% por cada jefe derrotado en la run (se resetea cada partida).
	local hpMult = workspace:GetAttribute("EnemyHPMult") or 1
	if hpMult ~= 1 then def.Vida = math.max(1, math.floor(def.Vida * hpMult)) end
	-- Escalado de vida por OLEADA tardia: a partir de la 15 los enemigos aguantan progresivamente mas.
	local oleadaAhora = workspace:GetAttribute("Oleada") or 1
	if oleadaAhora > 15 then def.Vida = math.floor(def.Vida * (1 + (oleadaAhora - 15) * 0.06)) end
	-- Escalado del MUNDO actual (modo campana): el mundo elegido sube vida/dano/velocidad de los enemigos.
	def.Vida = math.floor(def.Vida * (workspace:GetAttribute("WorldVidaMult") or 1))
	local wdm = workspace:GetAttribute("WorldDanoMult") or 1
	def.Dano = def.Dano * wdm
	-- Los ataques ESPECIALES tambien escalan con la dificultad (audit): antes solo el dano de CONTACTO (def.Dano)
	-- subia con WorldDanoMult, asi que en Oblivion la explosion del Bomber / el disparo del Spitter pegaban MENOS
	-- que un simple Chaser. Ahora la explosion (def.DanoExplosion) y el disparo (def.DanoDisparo) escalan igual.
	if def.DanoExplosion then def.DanoExplosion = def.DanoExplosion * wdm end
	if def.DanoDisparo then def.DanoDisparo = def.DanoDisparo * wdm end
	def.Velocidad = def.Velocidad * (workspace:GetAttribute("WorldVeloMult") or 1)

	local enemigo = Instance.new("Model")
	enemigo.Name = "BrainrotEnemy"
	enemigo:SetAttribute("Tipo", tipo)
	if afijos then enemigo:SetAttribute("Afijo", table.concat(afijos, "+")) end
	enemigo:SetAttribute("Cash", def.Cash or 0)

	local raiz = Instance.new("Part")
	raiz.Name = "HumanoidRootPart"
	raiz.Size = def.TamCuerpo
	raiz.Color = def.ColorCuerpo
	raiz.Material = Enum.Material.SmoothPlastic
	raiz.Position = posicion
	raiz.CollisionGroup = "Enemigos"
	raiz.Parent = enemigo

	local cabeza = Instance.new("Part")
	cabeza.Name = "Head"
	cabeza.Shape = Enum.PartType.Ball
	cabeza.Size = def.TamCabeza
	cabeza.Color = def.ColorCabeza
	cabeza.Position = posicion + Vector3.new(0, def.TamCuerpo.Y / 2 + def.TamCabeza.Y / 2, 0)
	cabeza.CollisionGroup = "Enemigos"
	cabeza.Parent = enemigo

	local soldadura = Instance.new("WeldConstraint")
	soldadura.Part0 = raiz
	soldadura.Part1 = cabeza
	soldadura.Parent = raiz

	local humano = Instance.new("Humanoid")
	humano.MaxHealth = def.Vida
	humano.Health = def.Vida
	humano.WalkSpeed = def.Velocidad
	humano.Parent = enemigo

	-- VISUAL con mesh (Sju). La raiz y la cabeza SIGUEN existiendo (son la fisica/hitbox y el Humanoid necesita
	-- Head), solo se vuelven invisibles. El mesh se escala UNIFORME a la altura que ocupaba el cuerpo+cabeza, asi
	-- que el afijo Gigante (que ya multiplico TamCuerpo/TamCabeza) escala tambien el modelo sin tocar nada mas.
	local plantilla = MESHES and MESHES:FindFirstChild(tipo)
	if plantilla then
		local alturaObjetivo = def.TamCuerpo.Y + def.TamCabeza.Y
		local escala = alturaObjetivo / math.max(plantilla.Size.Y, 0.1)
		local visual = plantilla:Clone()
		visual.Name = "Visual"
		visual.Size = plantilla.Size * escala
		visual.CanCollide = false
		visual.CanQuery = false
		visual.CanTouch = false
		visual.Massless = true
		-- 50 meshes EN MOVIMIENTO proyectando sombra obligan a rehacer el shadow map cada frame. Antes no se
		-- notaba porque raiz/cabeza eran las que se veian; ahora estan en Transparency=1 y el que proyecta es
		-- este. El resto del proyecto ya apaga CastShadow en todo lo que crea (balas, auras, telegraphs).
		visual.CastShadow = false
		visual.CollisionGroup = "Enemigos"
		-- apoyado en el suelo: el borde inferior del mesh coincide con el del cuerpo original
		visual.Position = posicion + Vector3.new(0, -def.TamCuerpo.Y / 2 + visual.Size.Y / 2, 0)
		visual.Parent = enemigo
		-- Z1 (anim de caminar): en vez de soldar RIGIDO, un Motor6D + un tween en bucle = animacion procedural (bob
		-- arriba-abajo + leve balanceo). Son parts, no un rig R15, asi que no hay esqueleto que animar; esto le da
		-- VIDA a la horda barato (1 Motor6D + 1 tween por bicho, NO 6 partes + Animator). El mesh es Massless + sin
		-- colision, asi que animar su Motor6D no toca la fisica.
		local offsetY = -def.TamCuerpo.Y / 2 + visual.Size.Y / 2
		local motor = Instance.new("Motor6D")
		motor.Part0 = raiz
		motor.Part1 = visual
		local baseC0 = CFrame.new(0, offsetY, 0)
		motor.C0 = baseC0
		motor.Parent = raiz
		-- periodo aleatorio por bicho: sin variacion TODA la horda rebota en sincronia (robotico). Tween reversible
		-- (sube + se inclina -> baja) en bucle infinito.
		local periodo = 0.24 + math.random() * 0.16
		local subida = baseC0 * CFrame.new(0, 0.18, 0) * CFrame.Angles(math.rad(6), 0, math.rad(4))
		game:GetService("TweenService"):Create(motor, TweenInfo.new(periodo, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { C0 = subida }):Play()
		raiz.Transparency = 1
		cabeza.Transparency = 1
		if afijoDef and afijoDef.Color then
			-- Tintar un MeshPart CON TEXTURA no se ve: la textura manda (es la MISMA pega que descubrimos con el
			-- flash blanco). Asi que el "las elites siguen tintadas" que puse antes era FALSO para todos los
			-- tipos con mesh, o sea para casi toda la horda. Para que la elite se distinga de verdad hay que
			-- QUITARLE la textura: queda de color solido del afijo, que ademas se lee mucho mejor en la horda.
			visual.TextureID = ""
			visual.Color = afijoDef.Color
		end
	end

	enemigo.PrimaryPart = raiz
	enemigo.Parent = carpetaEnemigos()

	-- Nameplate (Fase 8): NOMBRE + barra de vida + HP en texto, sobre la cabeza. Ocultamos el
	-- nombre y la barra POR DEFECTO de Roblox y pintamos los nuestros. Server -> lo ven todos.
	humano.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local nombreEnemigo = def.Nombre or tipo
	if afijoDef and afijoDef.Nombre then
		nombreEnemigo = afijoDef.Nombre .. " " .. nombreEnemigo
	end
	-- JERARQUIA de nameplate (Sju): con 50 bichos, 50 nameplates COMPLETOS tapaban justo los modelos. Y ahora
	-- que cada tipo tiene MODELO propio, poner "Chaser" encima de un goblin sobra: ya se ve lo que es. Asi que:
	--   · NORMAL -> barrita fina, sin texto, y a menos distancia -> queda un "colchon" suave de fondo
	--   · ELITE  -> nombre de la MUTACION en grande y en SU color + barra gruesa + HP en texto
	-- El resultado es que lo que destaca en pantalla es exactamente lo que te va a matar.
	local esElite = afijoDef ~= nil
	local plate = Instance.new("BillboardGui")
	plate.Name = "Nameplate"
	plate.Size = esElite and UDim2.fromOffset(150, 42) or UDim2.fromOffset(92, 24)
	plate.StudsOffset = Vector3.new(0, def.TamCabeza.Y / 2 + (esElite and 1.5 or 1.15), 0)
	plate.AlwaysOnTop = true
	plate.MaxDistance = esElite and 170 or 95 -- un normal lejano ni se dibuja (menos saturacion)
	plate.Adornee = cabeza
	plate.Parent = cabeza

	-- El NOMBRE se pone SIEMPRE (sin el, el bicho se ve "vacio" - correccion de Bastian). Lo que cambia entre
	-- normal y elite no es que este o no, sino su PESO VISUAL: el normal va chiquitito y apagado (acompana pero
	-- no compite), y la elite va en GothamBlack, grande y en el color de su mutacion.
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, 0, 0, esElite and 21 or 11)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = esElite and Enum.Font.GothamBlack or Enum.Font.GothamMedium
	nameLbl.TextScaled = true
	nameLbl.TextColor3 = esElite and (afijoDef.Color or Color3.fromRGB(255, 215, 120)) or Color3.fromRGB(205, 210, 222)
	nameLbl.TextTransparency = esElite and 0 or 0.2
	nameLbl.TextStrokeTransparency = esElite and 0 or 0.55 -- contorno solido solo en elites
	nameLbl.Text = nombreEnemigo -- en elite incluye los prefijos de mutacion ("Giant Armored Tank")
	nameLbl.Parent = plate

	local yBarra = esElite and 24 or 13
	local altoBarra = esElite and 14 or 8

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0, altoBarra)
	barBg.Position = UDim2.new(0, 0, 0, yBarra)
	barBg.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	barBg.BackgroundTransparency = esElite and 0 or 0.25 -- los normales, mas discretos
	barBg.BorderSizePixel = 0
	barBg.Parent = plate
	local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(0, 3); c1.Parent = barBg
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(0, 0, 0); stroke.Thickness = esElite and 1.5 or 1; stroke.Transparency = esElite and 0.15 or 0.5; stroke.Parent = barBg
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0, 3); c2.Parent = fill
	local hpLbl -- SOLO en elites: en la horda normal los numeros son ruido puro
	if esElite then
		hpLbl = Instance.new("TextLabel")
		hpLbl.Size = UDim2.fromScale(1, 1)
		hpLbl.BackgroundTransparency = 1
		hpLbl.Font = Enum.Font.GothamBold
		hpLbl.TextScaled = true
		hpLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		hpLbl.TextStrokeTransparency = 0.3
		hpLbl.ZIndex = 2
		hpLbl.Parent = barBg
	end
	local function pintarVidaEnemigo(vida)
		local frac = (humano.MaxHealth > 0) and math.clamp(vida / humano.MaxHealth, 0, 1) or 0
		fill.Size = UDim2.fromScale(frac, 1)
		fill.BackgroundColor3 = Color3.fromRGB(230, 70, 70):Lerp(Color3.fromRGB(80, 220, 90), frac)
		if hpLbl then hpLbl.Text = math.ceil(vida) .. " / " .. math.floor(humano.MaxHealth) end
	end
	pintarVidaEnemigo(humano.Health)
	humano.HealthChanged:Connect(pintarVidaEnemigo)

	-- Limpieza al morir.
	humano.Died:Connect(function()
		activos[enemigo] = nil -- fuera del registro central YA (conteo de vivos exacto + no lo procesa muerto)
		juice:FireAllClients({ kind = "enemyDeath", pos = raiz.Position })
		Drops.maybeSpawn(raiz.Position) -- a veces deja un objeto / power-up
		if afijoDef and afijoDef.Explota then -- afijo Volatile: avisa y ESTALLA al morir
			local pos = raiz.Position
			local aviso = Instance.new("Part")
			aviso.Name = "Telegraph"; aviso.Shape = Enum.PartType.Cylinder
			aviso.Size = Vector3.new(0.4, afijoDef.Explota.radio * 2, afijoDef.Explota.radio * 2)
			aviso.CFrame = CFrame.new(pos.X, 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
			aviso.Anchored = true; aviso.CanCollide = false; aviso.CanQuery = false
			aviso.Material = Enum.Material.Neon; aviso.Color = Color3.fromRGB(255, 120, 30); aviso.Transparency = 0.6
			aviso.Parent = workspace
			game:GetService("Debris"):AddItem(aviso, 0.6)
			task.delay(0.5, function() explotarEnemigo(pos, { RadioExplosion = afijoDef.Explota.radio, DanoExplosion = afijoDef.Explota.dano }) end)
		end
		-- El cadaver desaparece YA (con hordas no se acumulan hitboxes): sin colision ni target.
		for _, p in ipairs(enemigo:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false; p.CanQuery = false end
		end
		task.wait(0.35)
		enemigo:Destroy()
	end)

	-- Élite: brillo del color del afijo + regeneración (si lo da).
	if afijoDef then
		local hl = Instance.new("Highlight")
		hl.FillColor = afijoDef.Color
		hl.FillTransparency = 0.55
		hl.OutlineColor = afijoDef.Color
		hl.OutlineTransparency = 0
		hl.Parent = enemigo
		if afijoDef.Regen then
			task.spawn(function()
				while enemigo.Parent and humano.Health > 0 do
					task.wait(0.5)
					if humano.Health > 0 then
						humano.Health = math.min(humano.MaxHealth, humano.Health + afijoDef.Regen * 0.5)
					end
				end
			end)
		end
	end

	-- IA: registrada en el bucle CENTRAL (Perf A2, definido arriba). El estado por-enemigo vive en 'activos';
	-- el Charger escribe cargando/windup ahi. Antes esto era 1 coroutine POR enemigo (cientos con hordas -> lag).
	activos[enemigo] = { raiz = raiz, humano = humano, def = def, afijoDef = afijoDef, puedeGolpear = true, cargando = false, windup = false }

	-- Splitter: al MORIR se divide en varios hijos pequenos (Swarmers).
	if def.DivideEn then
		-- Las crias heredan los afijos del padre MENOS "Explosivo". Un Brood Volatile escupia 3 MiniBroods
		-- volatiles, y cada uno 2 Swarmers volatiles: al reventar toda la familia junta (Nova/AoE) caian
		-- 1+3+6 = 10 explosiones de 45 encima del jugador A LA VEZ = instakill (reportado en playtest).
		-- El padre SIGUE estallando una vez (su Died de arriba); solo se corta la CADENA de las crias.
		local afijosHijo = nil
		if afijos then
			afijosHijo = {}
			for _, k in ipairs(afijos) do if k ~= "Explosivo" then afijosHijo[#afijosHijo + 1] = k end end
			if #afijosHijo == 0 then afijosHijo = nil end
		end
		humano.Died:Connect(function()
			for i = 1, def.DivideEn do
				local ang = (i / def.DivideEn) * math.pi * 2
				Enemy.spawn(def.TipoHijo or "Swarmer", raiz.Position + Vector3.new(math.cos(ang) * 4, 2, math.sin(ang) * 4), afijosHijo)
			end
		end)
	end
	-- Healer: AURA verde visible (radio de cura) + cura a los enemigos cercanos.
	if def.Cura then
		local aura = Instance.new("Part")
		aura.Name = "HealAura"; aura.Shape = Enum.PartType.Cylinder
		aura.Size = Vector3.new(0.4, (def.RadioCura or 24) * 2, (def.RadioCura or 24) * 2)
		aura.Anchored = false; aura.CanCollide = false; aura.CanQuery = false; aura.CastShadow = false
		aura.Material = Enum.Material.Neon; aura.Color = Color3.fromRGB(80, 255, 180); aura.Transparency = 0.86
		aura.CFrame = CFrame.new(raiz.Position) * CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
		aura.Parent = enemigo
		local w = Instance.new("WeldConstraint"); w.Part0 = raiz; w.Part1 = aura; w.Parent = aura
		task.spawn(function()
			while enemigo.Parent and humano.Health > 0 do
				task.wait(def.CadenciaCura or 1.5)
				if humano.Health > 0 then
					local curo = false
					local carpeta = workspace:FindFirstChild("Enemies")
					for _, m in ipairs(carpeta and carpeta:GetChildren() or {}) do
						if m.Name == "BrainrotEnemy" and m ~= enemigo then
							local r = m:FindFirstChild("HumanoidRootPart")
							local h = m:FindFirstChildOfClass("Humanoid")
							if r and h and h.Health > 0 and h.Health < h.MaxHealth and (r.Position - raiz.Position).Magnitude <= (def.RadioCura or 24) then
								h.Health = math.min(h.MaxHealth, h.Health + (def.Cura or 10)); curo = true
							end
						end
					end
					if curo and aura.Parent then
						aura.Transparency = 0.6
						game:GetService("TweenService"):Create(aura, TweenInfo.new(0.45), { Transparency = 0.86 }):Play()
					end
				end
			end
		end)
	end
	-- Charger: AVISA (glow rojo + se para un instante) y luego EMBISTE.
	if def.Carga then
		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(255, 60, 40); hl.FillTransparency = 0.4
		hl.OutlineColor = Color3.fromRGB(255, 130, 90); hl.Enabled = false; hl.Parent = enemigo
		task.spawn(function()
			while enemigo.Parent and humano.Health > 0 do
				task.wait(def.CargaCooldown or 3)
				local e = activos[enemigo]
				if e and humano.Health > 0 then
					hl.Enabled = true; e.windup = true; task.wait(0.45) -- AVISO
					e.windup = false; e.cargando = true; task.wait(def.CargaDuracion or 0.8)
					e.cargando = false; hl.Enabled = false
				end
			end
		end)
	end

	-- Summoner: INVOCA enemigos cada cierto tiempo (mantiene distancia, como el Healer).
	if def.Invoca then
		task.spawn(function()
			local minions = {} -- auditoria B2: cap de minions VIVOS para no crecer sin limite (run fantasma / dejarlo solo)
			local CAP = def.InvocaCap or 8
			while enemigo.Parent and humano.Health > 0 do
				task.wait(def.InvocaCada or 5)
				if humano.Health <= 0 or not enemigo.Parent then break end
				local vivos = 0
				for m in pairs(minions) do
					if m.Parent then vivos += 1 else minions[m] = nil end
				end
				if vivos < CAP then
					for i = 1, (def.InvocaCantidad or 2) do
						local ang = (i / (def.InvocaCantidad or 2)) * math.pi * 2
						local minion = Enemy.spawn(def.InvocaTipo or "Swarmer", raiz.Position + Vector3.new(math.cos(ang) * 6, 2, math.sin(ang) * 6))
						if minion then minions[minion] = true end
					end
				end
			end
		end)
	end

	return enemigo, humano
end

return Enemy
