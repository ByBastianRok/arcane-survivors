-- WeaponServer  (Script del SERVIDOR)  ·  FASE 2 - pieza 2
-- El servidor MANDA: recibe "he disparado hacia ahí" del cliente, crea la bala
-- física de verdad, la lanza, y SOLO el servidor decide el daño. Así nadie
-- puede hacer trampas tocando su cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireWeapon = remotes:WaitForChild("FireWeapon")
local reloadEvent = remotes:WaitForChild("Reload")
local ammoUpdate = remotes:WaitForChild("AmmoUpdate")
local damageNumber = remotes:WaitForChild("DamageNumber")
local juice = remotes:WaitForChild("Juice")

-- ====== MOTOR DE ARMAS (data-driven) ======
-- Un solo motor sirve para TODAS las armas: lee los stats del arma equipada desde
-- WeaponData. Añadir un arma = añadir una tabla en WeaponData (y su Tool en StarterPack).
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponData"))
local StatusEffects = require(script.Parent:WaitForChild("StatusEffects"))
local RunState = require(script.Parent:WaitForChild("RunState"))
local Combat = require(script.Parent:WaitForChild("Combat")) -- daño unificado (crit/flash/numero/lifesteal/elementos)

-- Recordamos el último disparo de cada jugador para limitar la cadencia.
local ultimoDisparo = {}
local municion = {}   -- municion[jugador][nombreArma] = balas en el cargador
local recargando = {} -- recargando[jugador] = true mientras recarga

-- ====== CACHE DE ENEMIGOS (rendimiento) ======
-- En vez de que CADA bala y el auto-fuego escaneen TODO el workspace cada frame (O(balas x objetos)),
-- refrescamos 1 lista de enemigos vivos UNA vez por frame y todos la leen. Mucho menos lag con hordas.
local enemigosModelos = {}
RunService.Heartbeat:Connect(function()
	table.clear(enemigosModelos)
	-- todos los enemigos viven en workspace.Enemies (ver Enemy.luau): recorrer 50 en vez de todo el workspace,
	-- que con la arena por mundo tiene ~1500 partes mas.
	local carpeta = workspace:FindFirstChild("Enemies")
	local todos = carpeta and carpeta:GetChildren() or {}
	for _, m in ipairs(todos) do
		if m.Name == "BrainrotEnemy" then
			-- CACHE {modelo, root, humano} resuelto UNA vez/frame (audit): los consumidores (auto-fuego, tajo,
			-- explosion, aim y el bucle de balas) ya NO hacen FindFirstChild/FindFirstChildOfClass por enemigo/frame.
			local r = m:FindFirstChild("HumanoidRootPart")
			local h = m:FindFirstChildOfClass("Humanoid")
			if r and h then enemigosModelos[#enemigosModelos + 1] = { m = m, r = r, h = h } end
		end
	end
end)

-- Devuelve (e inicializa al cargador lleno si hace falta) la munición de un arma.
local function getMunicion(jugador, nombreArma, arma)
	municion[jugador] = municion[jugador] or {}
	if municion[jugador][nombreArma] == nil then
		municion[jugador][nombreArma] = arma.Cargador
	end
	return municion[jugador][nombreArma]
end

-- Avisa al cliente (HUD) de la munición actual de su arma.
local function avisarMunicion(jugador, arma, nombreArma)
	ammoUpdate:FireClient(jugador, {
		current = getMunicion(jugador, nombreArma, arma),
		max = arma.Cargador,
		reloading = recargando[jugador] == true,
		weapon = nombreArma,
		reloadTime = arma.TiempoRecarga * RunState.get(jugador).recargaMult, -- para animar la barra de recarga
	})
end

-- Recarga el arma tras su tiempo de recarga (no se puede disparar mientras).
local function recargar(jugador, arma, nombreArma)
	if recargando[jugador] then return end
	if getMunicion(jugador, nombreArma, arma) >= arma.Cargador then return end
	recargando[jugador] = true
	avisarMunicion(jugador, arma, nombreArma)
	task.delay(arma.TiempoRecarga * RunState.get(jugador).recargaMult, function()
		recargando[jugador] = false
		municion[jugador] = municion[jugador] or {}
		municion[jugador][nombreArma] = arma.Cargador
		avisarMunicion(jugador, arma, nombreArma)
	end)
end

-- ¿El personaje al que pertenece este Humanoid es de un jugador?
local function esJugador(modelo)
	return modelo and Players:GetPlayerFromCharacter(modelo) ~= nil
end

-- Flash blanco breve al golpear a un enemigo (feedback de impacto). Lo hace el SERVIDOR -> lo ven todos.
local function flashEnemy(modelo)
	if not modelo then return end
	for _, p in ipairs(modelo:GetChildren()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("__col") == nil then p:SetAttribute("__col", p.Color) end
			p.Color = Color3.fromRGB(255, 255, 255)
		end
	end
	task.delay(0.06, function()
		for _, p in ipairs(modelo:GetChildren()) do
			if p:IsA("BasePart") and p:GetAttribute("__col") ~= nil then
				p.Color = p:GetAttribute("__col")
			end
		end
	end)
end

-- Explosión en área: daña a TODOS los enemigos dentro del radio (para el lanzacohetes).
local function explotar(pos, arma, jugador, mods, excluir)
	-- Visual: esfera neon que se expande y desvanece (no usamos Explosion de Roblox para
	-- no romper articulaciones del jugador si explota cerca; el daño lo damos a mano).
	juice:FireAllClients({ kind = "explosion", pos = pos })
	local s = Instance.new("Part")
	s.Shape = Enum.PartType.Ball
	s.Material = Enum.Material.Neon
	s.Color = Color3.fromRGB(255, 150, 60)
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.Size = Vector3.new(2, 2, 2)
	s.Position = pos
	s.Parent = workspace
	game:GetService("TweenService"):Create(s, TweenInfo.new(0.3),
		{ Size = Vector3.new(arma.RadioExplosion * 2, arma.RadioExplosion * 2, arma.RadioExplosion * 2), Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(s, 0.4)
	for _, e in ipairs(enemigosModelos) do
		local r, h = e.r, e.h
		if h.Health > 0 and h ~= excluir and (r.Position - pos).Magnitude <= arma.RadioExplosion then
			Combat.aplicarGolpe(jugador, e.m, arma.DanoExplosion, mods, arma, r.Position, { sinCrit = true, sinLifesteal = true }) -- AoE: aplica build (danoMult/Execute/elemento) + cuenta en el medidor co-op, pero SIN crit/lifesteal a toda la horda
		end
	end
end

-- Tajo de MELEE (Knight): da dano a TODOS los enemigos en un arco frontal de corto alcance.
-- Sin proyectil; golpe instantaneo + un visual de onda de corte (lo crea el SERVIDOR -> lo ven todos).
local function tajoMelee(jugador, origen, direccion, arma, mods)
	local alcance = arma.AlcanceMelee or 14
	local cosLimite = math.cos(math.rad((arma.AnguloMelee or 120) / 2))
	-- visual: un TAJO que BARRE el arco frontal (de un lado al otro) dejando una estela de corte.
	-- Una hoja neon se mueve por el borde del cono y un Trail vertical dibuja la media luna del corte.
	local mitad = math.rad((arma.AnguloMelee or 120) / 2)
	local centro = origen + Vector3.new(0, 1.2, 0)
	local baseCF = CFrame.lookAt(centro, centro + direccion)
	local radio = alcance -- la estela del tajo llega al BORDE real del dano (antes 0.6 = se quedaba corta)
	local function puntaEn(ang) return centro + (baseCF * CFrame.Angles(0, ang, 0)).LookVector * radio end
	local hoja = Instance.new("Part")
	hoja.Size = Vector3.new(0.4, 3, 0.4)
	hoja.Anchored = true; hoja.CanCollide = false; hoja.CanQuery = false; hoja.CastShadow = false
	hoja.Material = Enum.Material.Neon
	hoja.Color = arma.ColorTajo or Color3.fromRGB(220, 235, 255)
	hoja.Transparency = 0.1
	hoja.CFrame = CFrame.new(puntaEn(mitad))
	hoja.Parent = workspace
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 1.6, 0); a0.Parent = hoja
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -1.6, 0); a1.Parent = hoja
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Lifetime = 0.2; trail.FaceCamera = true; trail.LightEmission = 1
	trail.Color = ColorSequence.new(arma.ColorTajo or Color3.fromRGB(220, 235, 255))
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = hoja
	Debris:AddItem(hoja, 0.4)
	task.spawn(function()
		local dur, t0 = 0.11, os.clock()
		while true do
			local k = (os.clock() - t0) / dur
			if k >= 1 then break end
			hoja.CFrame = CFrame.new(puntaEn(mitad - k * 2 * mitad)) -- barre de un lado al otro
			task.wait()
		end
		hoja.Transparency = 1
	end)
	-- dano: todo enemigo dentro del alcance Y dentro del arco frontal
	for _, e in ipairs(enemigosModelos) do
		local r, h = e.r, e.h
		if h.Health > 0 then
			local hacia = r.Position - origen
			local dist = hacia.Magnitude
			if dist <= alcance and (dist < 0.1 or hacia.Unit:Dot(direccion) >= cosLimite) then
				Combat.aplicarGolpe(jugador, e.m, arma.Dano, mods, arma, r.Position)
			end
		end
	end
end

-- Distancia minima del punto p al segmento [a,b] (para impacto por BARRIDO, sin tunneling).
local function distSegmento(a, b, p)
	a = Vector3.new(a.X, 0, a.Z); b = Vector3.new(b.X, 0, b.Z); p = Vector3.new(p.X, 0, p.Z) -- XZ (top-down: ignora altura)
	local ab = b - a
	local denom = ab:Dot(ab)
	local t = denom > 0 and math.clamp((p - a):Dot(ab) / denom, 0, 1) or 0
	return ((a + ab * t) - p).Magnitude
end

-- ====== BALAS (bucle UNICO + pooling) ======
-- En vez de un Heartbeat POR bala (O(balas) conexiones) + Instance.new por bala (churn de GC),
-- mantenemos UNA lista de balas vivas barrida por UN solo bucle, y REUTILIZAMOS las Parts (pool).
local balasActivas = {} -- { {bala, arma, jugador, mods, yaImpactados, prevPos, radioBala, muerteEn}, ... }
local poolBalas = {}    -- balas apagadas, listas para reutilizar

-- Saca una bala del pool (o crea una nueva con toda su estructura: Part + velocidad + estela).
local function obtenerBala()
	local bala = table.remove(poolBalas)
	if bala then return bala end
	bala = Instance.new("Part")
	bala.Name = "Bala"
	bala.Shape = Enum.PartType.Ball
	bala.Material = Enum.Material.Neon
	bala.CanCollide = false
	bala.CanQuery = false
	bala.CastShadow = false
	local attVel = Instance.new("Attachment"); attVel.Parent = bala
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attVel
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.Parent = bala
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.2, 0); a0.Parent = bala
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.2, 0); a1.Parent = bala
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.15 -- estela CORTA (antes 0.5 = ~75 studs de cola que se veia 'continuar' tras el impacto)
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = bala
	return bala
end

-- Devuelve una bala al pool (la apaga; se reutiliza en el proximo disparo).
local function devolverBala(bala)
	-- ===== BALAS INVISIBLES: la causa, y por que esta linea es la que lo arregla =====
	-- Sintoma que reportaba Bastian jugando: "los proyectiles invisibles sigue pasando con algunos personajes",
	-- y a mas rato jugado, mas balas invisibles.
	--
	-- El servidor creaba la bala con Transparency 0 y NO LA TOCABA NUNCA MAS. Quien la ocultaba era el CLIENTE
	-- (BulletClient la pone a 1 al impactar, para que la estela acabe EN el enemigo). Eso es un cambio LOCAL:
	-- no vuelve al servidor. Y como la copia del servidor seguia valiendo 0 SIEMPRE, nunca replicaba una
	-- correccion que devolviera la bala a visible.
	-- El unico camino que tenia el cliente para volver a mostrarla era su handler de workspace.ChildAdded...
	-- que depende de ver el par quitar/anadir del pool. Cuando la bala muere y se vuelve a disparar dentro de
	-- la misma ventana de replicacion, el cliente NO ve ningun cambio de padre -> nunca la vuelve a mostrar ->
	-- esa Part se queda invisible PARA SIEMPRE, y sigue dando vueltas por el pool infectando disparos futuros.
	-- Por eso empeoraba con el tiempo y por eso pegaba mas a unas armas que a otras (las de cadencia alta y
	-- vida de bala corta reciclan mucho mas rapido).
	--
	-- Ahora la visibilidad la manda el SERVIDOR: se apaga aqui y se enciende en lanzarBala. Al ser un cambio
	-- REAL (1 -> 0) siempre replica y pisa cualquier valor local que el cliente hubiera dejado puesto.
	bala.Transparency = 1
	bala.Parent = nil
	bala.AssemblyAngularVelocity = Vector3.zero -- el chakram gira; si no se para, el siguiente que use esta Part nace girando
	local lv = bala:FindFirstChildOfClass("LinearVelocity")
	if lv then lv.VectorVelocity = Vector3.zero end
	local trail = bala:FindFirstChildOfClass("Trail")
	if trail then trail.Enabled = false end
	if #poolBalas < 250 then
		poolBalas[#poolBalas + 1] = bala
	else
		bala:Destroy()
	end
end

-- Mata una bala (idempotente): la quita del juego AL INSTANTE + desconecta su Touched.
local function matarBala(b)
	if b.muerto then return end
	b.muerto = true
	if b.touchedConn then b.touchedConn:Disconnect(); b.touchedConn = nil end
	devolverBala(b.bala)
end

-- Lanza una bala (reutilizada del pool) desde 'origen' hacia 'direccion' con los stats de 'arma'.
local function lanzarBala(origen, direccion, arma, jugador, mods)
	if arma.Bumerang or (arma.Perforante and not arma.Explosivo) then -- bumerang Y flechas perforantes: vuelan PLANO a la altura del enemigo (no se hunden al suelo -> atraviesan la fila ENTERA, no solo 2)
		local flat = Vector3.new(direccion.X, 0, direccion.Z)
		if flat.Magnitude > 0.05 then direccion = flat.Unit end
		local mejorY, mejorD
		for _, e in ipairs(enemigosModelos) do
			local r = e.r
			local d = (r.Position - origen).Magnitude; if not mejorD or d < mejorD then mejorD = d; mejorY = r.Position.Y end
		end
		origen = Vector3.new(origen.X, mejorY or (origen.Y - 3), origen.Z) -- fallback: 3 bajo el origen si no hay enemigos
	end
	local bala = obtenerBala()
	local t = arma.TamanoBala

	-- ===== FORMA DEL PROYECTIL =====
	-- Antes TODAS las armas disparaban la misma esfera de Neon y solo cambiaba el tamano y el color: el arco
	-- tiraba bolas y el chakram tambien. Ahora cada arma tiene su silueta, que es lo que se lee de un vistazo
	-- desde la camara cenital (mucho antes que el color).
	-- El giro del chakram va por FISICA (AssemblyAngularVelocity), no con un bucle que reescriba el CFrame
	-- cada frame: con 30 balas a la vez eso seria trabajo por fotograma para nada.
	local forma = arma.FormaBala or "orbe"
	if forma == "flecha" then
		bala.Shape = Enum.PartType.Block
		bala.Size = Vector3.new(t * 0.42, t * 0.42, t * 3.2) -- alargada en Z: es su eje de vuelo
	elseif forma == "disco" then
		bala.Shape = Enum.PartType.Cylinder
		-- Un Cylinder de Roblox tiene su eje en X, asi que "plano" es X fino y las otras dos anchas.
		bala.Size = Vector3.new(t * 0.22, t, t)
	else
		bala.Shape = Enum.PartType.Ball
		bala.Size = Vector3.new(t, t, t)
	end
	bala.Color = arma.ColorBala
	-- La otra mitad del arreglo de las balas invisibles (ver el comentario largo en devolverBala): el SERVIDOR
	-- es quien manda sobre la visibilidad. Como viene del pool en 1, esto es un cambio de verdad y replica,
	-- pisando el Transparency local que el cliente del tirador le hubiera dejado puesto al ocultarla.
	bala.Transparency = 0
	bala.Position = origen
	local lv = bala:FindFirstChildOfClass("LinearVelocity")
	lv.VectorVelocity = direccion * arma.VelocidadBala -- RECTA, sin gravedad
	local trail = bala:FindFirstChildOfClass("Trail")
	trail.Color = ColorSequence.new(arma.ColorTracer)
	bala:SetAttribute("MuereAlTocar", (arma.Explosivo == true) or (not arma.Perforante)) -- ANTES de parentear: el Part reusado del pool traia el MuereAlTocar VIEJO -> el cliente ocultaba la flecha perforante al 1er impacto. Asi lo ve correcto en cuanto aparece
	trail.Enabled = true

	-- ORIENTACION. Se pone UNA vez al nacer y no hace falta tocarla mas: las balas vuelan en linea recta y sin
	-- gravedad, asi que la direccion no cambia (el bumerang gira sobre si mismo, que da igual para esto).
	if forma == "flecha" then
		-- La punta mira a donde va. Sin esto, una caja alargada vuela de lado y parece un ladrillo.
		bala.CFrame = CFrame.lookAt(origen, origen + direccion)
	elseif forma == "disco" then
		-- El eje del Cylinder es X, asi que se tumba para que la cara plana quede HORIZONTAL: desde la camara
		-- cenital se ve el anillo entero, que es lo que hace que se lea como chakram y no como una moneda.
		bala.CFrame = CFrame.new(origen) * CFrame.Angles(0, 0, math.rad(90))
	else
		bala.CFrame = CFrame.new(origen)
	end

	bala.Parent = workspace
	pcall(function() bala:SetNetworkOwner(nil) end) -- SERVER-owned TODAS: posicion EXACTA para el barrido de golpe (client-owned fallaba impactos, sobre todo el Mago)
	-- El GIRO del chakram, por fisica. Va DESPUES de parentear y de SetNetworkOwner, porque la velocidad
	-- angular se pierde si se pone antes de que la pieza entre en la simulacion.
	if forma == "disco" then
		bala.AssemblyAngularVelocity = Vector3.new(0, 18, 0) -- sobre el eje vertical: gira como un disco tirado
	end
	local b = {
		bala = bala, arma = arma, jugador = jugador, mods = mods,
		yaImpactados = {}, prevPos = origen, origen = origen,
		radioBala = (arma.Bumerang and ((arma.TamanoBala or 1) * 0.5 + 1.6)) or ((arma.Perforante and not arma.Explosivo) and ((arma.TamanoBala or 1) * 0.5 + 2.2)) or ((arma.TamanoBala or 1) * 0.5), -- chakram +1.6; perforantes (flechas/sniper) barren MUY ANCHO (+2.2) para atravesar TODO en linea; el resto fino
		muerteEn = os.clock() + arma.VidaBala,
	}
	if arma.Bumerang then b.regresarEn = os.clock() + arma.VidaBala * 0.5 end -- bumerang: a media vida se da la vuelta
	balasActivas[#balasActivas + 1] = b
	-- Touched: impacto INSTANTANEO al tocar (la bala desaparece al chocar = se siente limpio).
	-- El barrido del bucle es solo el RESPALDO anti-tunneling para balas muy rapidas.
	b.touchedConn = bala.Touched:Connect(function(otro)
		if b.muerto or otro.Name == "Bala" then return end
		if arma.Explosivo then return end -- explosivas: las gestiona el BARRIDO por CENTRO (capado); el Touched las hacia explotar por roce del cuerpo gordo / al spawnear
		local modelo = otro:FindFirstAncestorOfClass("Model")
		local hum = modelo and modelo:FindFirstChildOfClass("Humanoid")
		if esJugador(modelo) then return end
		if hum then
			-- Es un enemigo. OJO: un CADAVER (Health 0) sigue ~0.35s con CanTouch activo (Enemy.luau solo apaga
			-- CanCollide/CanQuery al morir). Antes caia al bloque "mundo" de abajo y MATABA la flecha -> la
			-- perforante se paraba en el primer enemigo QUE MATABA. Ahora tocar un enemigo (vivo o cadaver)
			-- nunca cuenta como pared: la flecha lo ignora y sigue.
			if hum.Health > 0 and not b.yaImpactados[hum] then
				b.yaImpactados[hum] = true
				Combat.aplicarGolpe(jugador, modelo, arma.Dano, mods, arma, bala.Position)
				if not arma.Perforante then matarBala(b) end
			end
			return
		end
		-- mundo REAL (suelo/pared): la bala se para; el cohete explota.
		if arma.Explosivo then explotar(bala.Position, arma) end
		if not arma.Bumerang then matarBala(b) end -- el bumerang ATRAVIESA el mundo (vuela y vuelve)
	end)
end

-- UN solo bucle para TODAS las balas: RESPALDO anti-tunneling (barrido) + expiracion + limpieza.
RunService.Heartbeat:Connect(function()
	local i = 1
	while i <= #balasActivas do
		local b = balasActivas[i]
		if not b.muerto then
			local curPos = b.bala.Position
			if os.clock() >= b.muerteEn then
				if b.arma.Explosivo then explotar(curPos, b.arma, b.jugador, b.mods) end -- el cohete revienta al expirar (AoE con build)
				matarBala(b)
			else
				if b.arma.Bumerang and not b.regresado and os.clock() >= b.regresarEn then
						b.regresado = true
						b.yaImpactados = {} -- al VOLVER vuelve a pegar (pega 2 veces)
						local lv2 = b.bala:FindFirstChildOfClass("LinearVelocity")
						if lv2 then
							local car = b.jugador and b.jugador.Character
							local root = car and car:FindFirstChild("HumanoidRootPart")
							local dir = (root and (root.Position - curPos)) or -lv2.VectorVelocity
							dir = Vector3.new(dir.X, 0, dir.Z) -- horizontal: vuelve a NIVEL enemigo (pega tambien al volver), no sube a la mano
							if dir.Magnitude < 0.05 then dir = Vector3.new(-lv2.VectorVelocity.X, 0, -lv2.VectorVelocity.Z) end
							if dir.Magnitude < 0.05 then dir = Vector3.new(0, 0, 1) end
							lv2.VectorVelocity = dir.Unit * b.arma.VelocidadBala
						end
					end
					for _, e in ipairs(enemigosModelos) do -- cache {m,r,h} ya resuelto (audit): sin FindFirstChild por frame
					local m, r, h = e.m, e.r, e.h
					if h.Health > 0 and not b.yaImpactados[h] then
						local radioEnemigo = math.max(r.Size.X, r.Size.Z) * 0.5
						if (curPos - r.Position).Magnitude <= b.radioBala + radioEnemigo or ((curPos - b.prevPos).Magnitude > b.radioBala + radioEnemigo and distSegmento(b.prevPos, curPos, r.Position) <= b.radioBala + radioEnemigo) then
							if b.arma.Explosivo then
							if (b.arma.Dano or 0) > 0 then Combat.aplicarGolpe(b.jugador, m, b.arma.Dano, b.mods, b.arma, r.Position) end -- impacto DIRECTO al central (Inferno Orb 80): single-target, con crit/lifesteal/elemento
							explotar(curPos, b.arma, b.jugador, b.mods, h) -- splash al RESTO (excluye el central para no doblar)
							matarBala(b); break
						end -- explota DONDE esta la orbe (server-owned = coincide con el visual)
							b.yaImpactados[h] = true
							Combat.aplicarGolpe(b.jugador, m, b.arma.Dano, b.mods, b.arma, r.Position)
							if not b.arma.Perforante then b.bala.Position = r.Position; matarBala(b); break end -- snap al enemigo: la estela acaba EN el impacto (no sigue de largo)
						end
					end
				end
				if not b.muerto then b.prevPos = curPos end
			end
		end
		if b.muerto then
			balasActivas[i] = balasActivas[#balasActivas] -- swap-remove (O(1))
			balasActivas[#balasActivas] = nil
		else
			i += 1
		end
	end
end)

-- Aplica dispersión (spread) a una dirección: la desvía un ángulo aleatorio dentro de
-- un cono de 'grados'. Para escopetas (varios perdigones abiertos) o armas imprecisas.
local function dispersar(direccion, grados)
	if not grados or grados <= 0 then return direccion end
	local r = math.rad(grados)
	local desvio = CFrame.Angles((math.random() - 0.5) * r, (math.random() - 0.5) * r, 0)
	return (CFrame.lookAt(Vector3.zero, direccion) * desvio).LookVector
end

-- Aplica los modificadores de la partida (RunState) a los stats del arma para ESTE disparo.
-- Devuelve una COPIA del arma con dano/cadencia/balas/perforar ajustados (no toca WeaponData).
-- OJO: esto es una LISTA BLANCA, no una copia. Todo campo de WeaponData que no este escrito aqui abajo
-- DESAPARECE, y sin dar ningun error: el resto del codigo recibe la tabla de esta funcion, no el arma
-- original. Me acaba de morder con FormaBala (las flechas seguian saliendo esfericas).
-- Si anades un campo a WeaponData y no se nota en el juego, mira aqui ANTES que en ningun otro sitio.
local function efectivo(arma, mods)
	return {
		Dano = arma.Dano * mods.danoMult * (mods.buffDanoMult or 1),
		DanoExplosion = (arma.DanoExplosion or 0) * mods.danoMult * (mods.buffDanoMult or 1),
		Cadencia = arma.Cadencia * mods.cadenciaMult * (mods.buffCadenciaMult or 1),
		Balas = (arma.Balas or 1) + mods.balasExtra,
		Spread = (arma.Spread or 0) + (mods.spreadExtra or 0),
		Perforante = arma.Perforante or mods.perforante,
		Bumerang = arma.Bumerang,
		Explosivo = arma.Explosivo,
		RadioExplosion = arma.RadioExplosion,
		Elemento = arma.Elemento,
		VelocidadBala = arma.VelocidadBala,
		FormaBala = arma.FormaBala, -- orbe / flecha / disco: la silueta del proyectil
		TamanoBala = (arma.TamanoBala or 0) * (mods.tamanoMult or 1),
		ColorBala = arma.ColorBala,
		ColorTracer = arma.ColorTracer,
		VidaBala = arma.VidaBala,
		TipoDisparo = arma.TipoDisparo,
		AlcanceMelee = arma.AlcanceMelee and arma.AlcanceMelee * math.min((mods.tamanoMult or 1) * (mods.rangoMult or 1), 1.75) or nil, -- (U) Giant Bolt + Longshot agrandan el tajo PERO con tope 1.75x: sin cap el melee acababa pegando a TODO el mapa a final de run (Bastian). Cap tanto el alcance como el visual (usan el mismo AlcanceMelee efectivo).
		AnguloMelee = arma.AnguloMelee,
		ColorTajo = arma.ColorTajo,
		Sonido = arma.Sonido,
	}
end

-- Cuando un cliente dice "he disparado hacia este punto":
fireWeapon.OnServerEvent:Connect(function(jugador, puntoObjetivo)
	-- --- Validaciones de servidor (no fiarse del cliente) ---
	if typeof(puntoObjetivo) ~= "Vector3" then return end

	local pj = jugador.Character
	local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
	local hum = pj and pj:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum and hum.Health > 0) then return end

	-- El arma = la Tool equipada cuyo nombre exista en WeaponData (el SERVIDOR decide cuál).
	local tool = pj:FindFirstChildOfClass("Tool")
	local arma = tool and WeaponData[tool.Name]
	if not arma then return end
	local nombreArma = tool.Name

	-- Modificadores de la partida (cartas de poder): arma EFECTIVA para este disparo.
	local mods = RunState.get(jugador)
	local armaEf = efectivo(arma, mods)

	-- MELEE: tajo instantaneo hacia el punto (sin municion ni proyectil).
	if armaEf.TipoDisparo == "Melee" then
		local ahora = os.clock()
		if ultimoDisparo[jugador] and (ahora - ultimoDisparo[jugador]) < armaEf.Cadencia then return end
		ultimoDisparo[jugador] = ahora
		local dir = puntoObjetivo - hrp.Position
		dir = (dir.Magnitude < 0.1) and hrp.CFrame.LookVector or dir.Unit
		tajoMelee(jugador, hrp.Position, dir, armaEf, mods)
		return
	end

	-- No se dispara mientras recargas.
	if recargando[jugador] then return end

	-- Cadencia propia de cada arma.
	local ahora = os.clock()
	if ultimoDisparo[jugador] and (ahora - ultimoDisparo[jugador]) < armaEf.Cadencia then
		return
	end

	-- Munición: si el cargador está vacío, recarga automática y no dispara.
	if getMunicion(jugador, nombreArma, arma) <= 0 then
		recargar(jugador, arma, nombreArma)
		return
	end

	ultimoDisparo[jugador] = ahora
	municion[jugador][nombreArma] -= 1
	avisarMunicion(jugador, arma, nombreArma)

	-- Origen = el cañón (Muzzle) si existe, si no el centro del jugador.
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	local origen = muzzle and muzzle.WorldPosition or hrp.Position

	-- Dirección base desde el cañón hacia el punto al que apunta el jugador.
	local delta = puntoObjetivo - origen
	if delta.Magnitude < 0.1 then return end
	local direccionBase = delta.Unit

	-- Dispara N proyectiles. 1 = recto (con la dispersion del arma si la tiene). Varios = ABANICO UNIFORME.
	-- H (fix): antes cada bala usaba dispersion ALEATORIA -> en armas de 1 objetivo (Spread=0) TODAS las balas
	-- extra salian en la misma linea (acumuladas). Ahora se reparten en un abanico regular.
	local n = armaEf.Balas
	local cono = (armaEf.Spread and armaEf.Spread > 0) and armaEf.Spread or ((n - 1) * 9) -- sin spread propio: ~9 grados por hueco
	cono = math.min(cono, 70)
	for i = 1, n do
		local dir
		if n <= 1 then
			dir = dispersar(direccionBase, armaEf.Spread)
		else
			local ang = -cono / 2 + (cono / (n - 1)) * (i - 1) -- reparto UNIFORME del abanico
			dir = (CFrame.Angles(0, math.rad(ang), 0) * direccionBase)
		end
		lanzarBala(origen + dir * 2, dir, armaEf, jugador, mods)
	end
end)

-- El jugador pulsa R para recargar manualmente.
reloadEvent.OnServerEvent:Connect(function(jugador)
	local pj = jugador.Character
	local tool = pj and pj:FindFirstChildOfClass("Tool")
	local arma = tool and WeaponData[tool.Name]
	if arma then
		recargar(jugador, arma, tool.Name)
	end
end)

-- Drop de municion (Fase 5B): rellena el cargador del arma equipada AL INSTANTE.
local ammoRefill = game:GetService("ServerScriptService"):WaitForChild("AmmoRefill")
ammoRefill.Event:Connect(function(jugador)
	local pj = jugador.Character
	local tool = pj and pj:FindFirstChildOfClass("Tool")
	local arma = tool and WeaponData[tool.Name]
	if arma then
		recargando[jugador] = false
		municion[jugador] = municion[jugador] or {}
		municion[jugador][tool.Name] = arma.Cargador
		avisarMunicion(jugador, arma, tool.Name)
	end
end)

-- Al reaparecer, el cargador vuelve lleno; al equipar un arma, avisamos al HUD.
local function alEntrarPersonaje(jugador, char)
	municion[jugador] = nil
	recargando[jugador] = false
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and WeaponData[child.Name] then
			avisarMunicion(jugador, WeaponData[child.Name], child.Name)
		end
	end)
end

local function configurarMunicion(jugador)
	jugador.CharacterAdded:Connect(function(char) alEntrarPersonaje(jugador, char) end)
	if jugador.Character then
		alEntrarPersonaje(jugador, jugador.Character)
	end
end
Players.PlayerAdded:Connect(configurarMunicion)
for _, jugador in ipairs(Players:GetPlayers()) do
	configurarMunicion(jugador)
end

-- Limpieza: si el jugador se va, olvidamos sus datos.
Players.PlayerRemoving:Connect(function(jugador)
	ultimoDisparo[jugador] = nil
	municion[jugador] = nil
	recargando[jugador] = nil
end)

-- ====== AUTO-ATTACK (S1, survivors) ======
-- El arma dispara SOLA al enemigo mas cercano por cooldown. Sin municion. El jugador solo se mueve.
local function enemigoMasCercano(pos, rango)
	local mejor, distMin = nil, rango or math.huge
	for _, e in ipairs(enemigosModelos) do
		local r, h = e.r, e.h
		if h.Health > 0 then
			local d = (r.Position - pos).Magnitude
			if d < distMin then distMin = d; mejor = r end
		end
	end
	return mejor
end

local RANGO_AUTO = 90 -- a que distancia el arma engancha enemigos
RunService.Heartbeat:Connect(function()
	for _, jugador in ipairs(Players:GetPlayers()) do
		if jugador:GetAttribute("Eligiendo") then continue end -- pausa el auto-fuego mientras elige mejora (S1.2)
		-- Solo dispara si hay un enemigo cerca (en el lobby no hay enemigos -> no dispara).
		local pj = jugador.Character
		local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
		local hum = pj and pj:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum and hum.Health > 0) then continue end
		local tool = pj:FindFirstChildOfClass("Tool")
		local arma = tool and WeaponData[tool.Name]
		if not arma then continue end
		local mods = RunState.get(jugador)
		local ahora = os.clock()
		-- CADENCIA efectiva con escalares (audit): comprobar el cooldown ANTES de construir efectivo() (~25 campos).
		-- En cooldown la mayoria de frames -> nos ahorramos esa alocacion casi siempre (4 jugadores x 60fps).
		local cadenciaEf = arma.Cadencia * mods.cadenciaMult * (mods.buffCadenciaMult or 1)
		if ultimoDisparo[jugador] and (ahora - ultimoDisparo[jugador]) < cadenciaEf then continue end
		local armaEf = efectivo(arma, mods)
		if armaEf.TipoDisparo == "Melee" then
			-- MELEE: solo ataca si hay un enemigo dentro del alcance del tajo
			local objetivo = enemigoMasCercano(hrp.Position, (armaEf.AlcanceMelee or 14) + 3)
			if not objetivo then continue end
			ultimoDisparo[jugador] = ahora
			local dir = objetivo.Position - hrp.Position
			dir = (dir.Magnitude < 0.1) and hrp.CFrame.LookVector or dir.Unit
			tajoMelee(jugador, hrp.Position, dir, armaEf, mods)
			juice:FireClient(jugador, { kind = "melee" }) -- sonido de tajo + shake leve
			-- Twin/Triple Cast en melee: tajos EXTRA encadenados (re-apuntando al enemigo mas cercano)
			for k = 1, (armaEf.Balas or 1) - 1 do
				task.delay(k * 0.14, function()
					local pj2 = jugador.Character
					local hrp2 = pj2 and pj2:FindFirstChild("HumanoidRootPart")
					local hum2 = pj2 and pj2:FindFirstChildOfClass("Humanoid")
					if not (hrp2 and hum2 and hum2.Health > 0) then return end
					local obj2 = enemigoMasCercano(hrp2.Position, (armaEf.AlcanceMelee or 14) + 3)
					local dir2 = obj2 and (obj2.Position - hrp2.Position) or hrp2.CFrame.LookVector
					dir2 = (dir2.Magnitude < 0.1) and hrp2.CFrame.LookVector or dir2.Unit
					tajoMelee(jugador, hrp2.Position, dir2, armaEf, mods)
					juice:FireClient(jugador, { kind = "melee" })
				end)
			end
		else
			-- PROYECTIL: dispara a distancia al enemigo mas cercano
			local objetivo = enemigoMasCercano(hrp.Position, RANGO_AUTO * (mods.rangoMult or 1)) -- Longshot: +alcance
			if not objetivo then continue end
			ultimoDisparo[jugador] = ahora
			local handle = tool:FindFirstChild("Handle")
			local muzzle = handle and handle:FindFirstChild("Muzzle")
			local origenXZ = muzzle and muzzle.WorldPosition or hrp.Position
			local origen = Vector3.new(origenXZ.X, hrp.Position.Y, origenXZ.Z) -- altura del JUGADOR (horizontal, no toca el suelo)
			local dir = objetivo.Position - origen
			-- dir apunta al ENEMIGO incluyendo ALTURA (asi NO pasa por encima de los bajitos como el Swarmer; el impacto se sigue midiendo por XZ)
			if dir.Magnitude < 0.1 then continue end
			dir = dir.Unit
			for _ = 1, armaEf.Balas do
				local d = dispersar(dir, armaEf.Spread)
				lanzarBala(origen + d * 2, d, armaEf, jugador, mods)
			end
			juice:FireClient(jugador, { kind = "shoot", snd = armaEf.Sonido }) -- sonido propio del arma + retroceso
		end
	end
end)
