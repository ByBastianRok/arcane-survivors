-- WeatherClient (LocalScript) · Sju - CLIMA del mundo en curso (nieve, pavesas, hojas...).
-- Va en CLIENTE y pegado a la CAMARA a proposito: asi las particulas te acompanan siempre, cuestan
-- practicamente nada (no se replican) y venden el mundo al instante. El servidor solo publica que mundo
-- estamos jugando en el atributo workspace.MundoArte; aqui se traduce a particulas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldArt = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WorldArt"))

local player = Players.LocalPlayer
local emisor -- ParticleEmitter activo (uno como mucho)
local soporte -- parte invisible pegada a la camara

local function apagar()
	if soporte then soporte:Destroy(); soporte = nil end
	emisor = nil
end

local function encender(worldId)
	apagar()
	local art = WorldArt.de(worldId)
	local c = art and art.clima
	if not c then return end

	local cam = workspace.CurrentCamera
	if not cam then return end

	-- Soporte invisible que SIGUE a la camara: las particulas caen siempre alrededor del jugador, se mire
	-- donde se mire, sin tener que llenar toda la arena de emisores.
	soporte = Instance.new("Part")
	soporte.Name = "ClimaSoporte"
	soporte.Size = Vector3.new(60, 1, 60)
	soporte.Transparency = 1
	soporte.Anchored = true
	soporte.CanCollide = false
	soporte.CanQuery = false
	soporte.CanTouch = false
	soporte.Parent = workspace

	emisor = Instance.new("ParticleEmitter")
	emisor.Rate = c.rate
	emisor.Lifetime = NumberRange.new(3.5, 6)
	emisor.Speed = NumberRange.new(math.abs(c.velocidad) * 0.5, math.abs(c.velocidad))
	emisor.SpreadAngle = Vector2.new(180, 180)
	emisor.Size = NumberSequence.new(c.tam)
	emisor.Transparency = NumberSequence.new(c.transparencia)
	emisor.Color = ColorSequence.new(c.color)
	emisor.Rotation = NumberRange.new(0, 360)
	emisor.RotSpeed = NumberRange.new(-c.giro, c.giro)
	emisor.LightEmission = 0.35
	emisor.Acceleration = Vector3.new(0, c.velocidad, 0) -- negativo = cae (nieve/hojas), positivo = sube (pavesas)
	emisor.Parent = soporte

	-- Seguimiento de camara. Heartbeat solo mientras hay clima; al apagarlo, la conexion muere con el soporte.
	local RunService = game:GetService("RunService")
	local conexion
	conexion = RunService.Heartbeat:Connect(function()
		if not (soporte and soporte.Parent) then conexion:Disconnect(); return end
		local camara = workspace.CurrentCamera
		if camara then
			-- por encima de la camara si cae, por debajo si sube
			local alto = (c.velocidad < 0) and 26 or -6
			soporte.CFrame = CFrame.new(camara.CFrame.Position + Vector3.new(0, alto, 0))
		end
	end)
end

local function refrescar()
	local id = workspace:GetAttribute("MundoArte")
	-- Ajuste del jugador: si baja graficos/efectos se puede colgar aqui en el futuro.
	if id == nil then apagar() else encender(id) end
end

workspace:GetAttributeChangedSignal("MundoArte"):Connect(refrescar)
task.defer(refrescar)
player.CharacterAdded:Connect(function() task.delay(0.5, refrescar) end) -- al respawnear, la camara cambia
