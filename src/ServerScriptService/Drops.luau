-- Drops (ModuleScript del SERVIDOR) · FASE 5B - objetos y power-ups que sueltan los enemigos.
-- Al morir un enemigo, Enemy llama Drops.maybeSpawn(pos): a veces deja un objeto flotante.
-- Si un jugador se acerca, se aplica su efecto (curar, municion, Coins, bomba en area, o un
-- power-up TEMPORAL). Reparte por DATOS desde DropData; la logica de cada efecto vive aqui.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local DropData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("DropData"))
local RunState = require(ServerScriptService:WaitForChild("RunState"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local buffUpdate = remotes:WaitForChild("BuffUpdate")
local ammoRefill = ServerScriptService:WaitForChild("AmmoRefill") -- BindableEvent (lo escucha WeaponServer)

local Drops = {}

-- ===== EFECTOS (servidor) por id de objeto =====
local efectos = {}

function efectos.heart(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.25) -- +25% de la vida maxima
	end
end

function efectos.ammo(player)
	ammoRefill:Fire(player) -- WeaponServer rellena el cargador del arma equipada al instante
end

function efectos.rapid(player)
	local dur = DropData.porId("rapid").dur
	RunState.aplicarBuff(player, "buffCadenciaMult", 0.25, dur)
	buffUpdate:FireClient(player, { name = "RAPID FIRE", duration = dur })
end

-- ===== Elegir un tipo de objeto por peso =====
-- Fix K: la SUERTE ya NO sesga hacia buffs (antes hacia el INVINCIBLE/DAMAGE x2 casi permanentes).
-- La suerte solo sube la CHANCE de soltar ALGO (en maybeSpawn), no la probabilidad de que sea un buff.
local function pesoDrop(d) return d.peso end

local function elegirTipo(suerte)
	local total = 0
	for _, d in ipairs(DropData.Tipos) do total += pesoDrop(d, suerte) end
	local r = math.random() * total
	for _, d in ipairs(DropData.Tipos) do
		r -= pesoDrop(d, suerte)
		if r <= 0 then return d end
	end
	return DropData.Tipos[1]
end

-- ===== Objetos activos en el suelo (un solo bucle los anima, IMANTA y detecta la recogida) =====
local activos = {} -- activos[part] = { def=..., y0=..., t0=... }
-- IMAN (22-jul, Bastian): los drops vuelan hacia ti, mas rapido cuanto mas cerca (estilo survivors).
local MAGNET_RADIO = 34    -- desde aqui el objeto empieza a volar hacia el jugador
local MAGNET_VEL_MIN = 16  -- studs/s en el borde del radio
local MAGNET_VEL_MAX = 70  -- studs/s pegado (acelera cuanto mas cerca)
local RECOGER_RADIO = 3.5  -- a esta distancia se recoge

local function recoger(part, def, player)
	activos[part] = nil
	local fx = efectos[def.id]
	if fx then fx(player) end
	-- destello al recoger
	TweenService:Create(part, TweenInfo.new(0.2), { Size = part.Size * 2.2, Transparency = 1 }):Play()
	Debris:AddItem(part, 0.25)
end

-- Bucle compartido: flota/gira los objetos y comprueba si un jugador los recoge (por cercania).
RunService.Heartbeat:Connect(function(dt)
	if not next(activos) then return end
	local t = os.clock()
	for part, info in pairs(activos) do
		if not part.Parent then
			activos[part] = nil
		else
			-- jugador VIVO mas cercano (drops pocos * jugadores <=4 = barato)
			local mejorPl, mejorPos, mejorD = nil, nil, math.huge
			for _, pl in ipairs(Players:GetPlayers()) do
				local ch = pl.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local d2 = (hrp.Position - part.Position).Magnitude
					if d2 < mejorD then mejorPl, mejorPos, mejorD = pl, hrp.Position, d2 end
				end
			end
			local pos = part.Position
			local y = info.y0 + math.sin((t - info.t0) * 3) * 0.4 -- flotar arriba/abajo
			if mejorPl and mejorD <= RECOGER_RADIO then
				recoger(part, info.def, mejorPl)
			elseif mejorPl and mejorD <= MAGNET_RADIO then
				-- IMAN: vuela hacia ti, acelerando cuanto mas cerca
				local frac = 1 - (mejorD / MAGNET_RADIO) -- 0 en el borde, ~1 pegado
				local vel = MAGNET_VEL_MIN + frac * (MAGNET_VEL_MAX - MAGNET_VEL_MIN)
				local dir = mejorPos - pos
				local dxz = Vector3.new(dir.X, 0, dir.Z)
				dxz = (dxz.Magnitude > 0.05) and dxz.Unit or Vector3.zero
				local np = pos + dxz * (vel * dt)
				part.CFrame = CFrame.new(np.X, y, np.Z) * CFrame.Angles(0, (t - info.t0) * 6, 0) -- gira mas rapido al volar
			else
				-- en reposo: flota y gira en su sitio
				part.CFrame = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, (t - info.t0) * 2, 0)
			end
		end
	end
end)

-- Crea el objeto flotante (si la suerte lo permite). pos = donde murio el enemigo.
function Drops.maybeSpawn(pos)
	local suerte = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = RunState.get(pl).suerte or 0
		if s > suerte then suerte = s end
	end
	local oleada = workspace:GetAttribute("Oleada") or 1
	local penal = (oleada > 11) and math.max(0.35, 1 - (oleada - 11) * 0.06) or 1 -- tras ronda 11 baja el dropeo
	if math.random() > math.min(0.22, DropData.ChanceBase + suerte * 0.005) * penal then return end -- Fix K: tope 22% (era 40%) + suerte escala menos (0.005 vs 0.008)

	local def = elegirTipo(suerte)
	local y0 = pos.Y + 2.5

	local part = Instance.new("Part")
	part.Name = "Drop"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = def.color
	if def.forma == "Ball" then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.6, 1.6, 1.6)
	elseif def.forma == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.5, 1.8, 1.8)
	else
		part.Size = Vector3.new(1.5, 1.5, 1.5)
	end
	part.CFrame = CFrame.new(pos.X, y0, pos.Z)
	part.Parent = workspace

	-- (SIN PointLight: la auditoria lo marco como carga de movil -- 8-15 luces dinamicas en pleno combate.
	--  El material Neon ya brilla solo, igual que en ArenaBuilder.)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 26)
	bb.StudsOffset = Vector3.new(0, 1.6, 0)
	bb.AlwaysOnTop = true
	bb.Parent = part
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.GothamBold
	txt.TextScaled = true
	txt.TextColor3 = def.color
	txt.TextStrokeTransparency = 0.4
	txt.Text = def.nombre
	txt.Parent = bb

	activos[part] = { def = def, y0 = y0, t0 = os.clock() }

	task.delay(DropData.VidaEnSuelo, function()
		if part.Parent and activos[part] then
			activos[part] = nil
			TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			Debris:AddItem(part, 0.35)
		end
	end)
end

return Drops
