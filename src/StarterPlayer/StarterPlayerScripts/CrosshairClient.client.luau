-- CrosshairClient (LocalScript) · FASE 8 - mira propia + camara 3a persona.
-- Pinta una cruz que sigue al raton (oculta el cursor por defecto), roja al apuntar a un
-- enemigo. Bloquea la camara a 3a persona (sin primera persona). Solo en partida.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local esMovil = UserInputService.TouchEnabled and not UserInputService.MouseEnabled and not UserInputService.KeyboardEnabled

-- Camara: 3a persona clasica, SIN primera persona (min zoom) y con tope de alejar.
player.CameraMode = Enum.CameraMode.Classic
player.CameraMinZoomDistance = 8
player.CameraMaxZoomDistance = 22

local gui = Instance.new("ScreenGui")
gui.Name = "Crosshair"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = playerGui

local cross = Instance.new("Frame")
cross.Name = "Reticle"
cross.AnchorPoint = Vector2.new(0.5, 0.5)
cross.Size = UDim2.fromOffset(34, 34)
cross.BackgroundTransparency = 1
cross.Parent = gui

local COL = Color3.fromRGB(245, 245, 245)
local COL_ENEMY = Color3.fromRGB(255, 70, 70)

local function tick(nombre)
	local f = Instance.new("Frame")
	f.Name = nombre
	f.BorderSizePixel = 0
	f.BackgroundColor3 = COL
	local st = Instance.new("UIStroke") -- borde negro para que se vea sobre cualquier fondo
	st.Thickness = 1; st.Color = Color3.fromRGB(0, 0, 0); st.Transparency = 0.3; st.Parent = f
	f.Parent = cross
	return f
end

local GAP, LEN, THICK = 5, 8, 2
local top = tick("Top");    top.Size = UDim2.fromOffset(THICK, LEN); top.AnchorPoint = Vector2.new(0.5, 1);   top.Position = UDim2.new(0.5, 0, 0.5, -GAP)
local bot = tick("Bottom"); bot.Size = UDim2.fromOffset(THICK, LEN); bot.AnchorPoint = Vector2.new(0.5, 0);   bot.Position = UDim2.new(0.5, 0, 0.5, GAP)
local lef = tick("Left");   lef.Size = UDim2.fromOffset(LEN, THICK); lef.AnchorPoint = Vector2.new(1, 0.5);   lef.Position = UDim2.new(0.5, -GAP, 0.5, 0)
local rig = tick("Right");  rig.Size = UDim2.fromOffset(LEN, THICK); rig.AnchorPoint = Vector2.new(0, 0.5);   rig.Position = UDim2.new(0.5, GAP, 0.5, 0)
local dot = tick("Dot");    dot.Size = UDim2.fromOffset(3, 3);       dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.new(0.5, 0, 0.5, 0)
local lineas = { top, bot, lef, rig, dot }

local function setColor(c)
	for _, f in ipairs(lineas) do f.BackgroundColor3 = c end
end

-- ¿el raton apunta a un enemigo?
local function sobreEnemigo()
	local t = mouse.Target
	if not t then return false end
	local modelo = t:FindFirstAncestorOfClass("Model")
	return modelo ~= nil and modelo.Name == "BrainrotEnemy"
end

local estadoEnemigo = nil
RunService.RenderStepped:Connect(function()
	if not gui.Enabled then return end
	local loc = UserInputService:GetMouseLocation()
	cross.Position = UDim2.fromOffset(loc.X, loc.Y)
	local sobre = sobreEnemigo()
	if sobre ~= estadoEnemigo then
		estadoEnemigo = sobre
		setColor(sobre and COL_ENEMY or COL)
	end
end)

-- S1 survivors: auto-aim (no se apunta a mano). La mira queda desactivada (en hiatus); cursor visible para UI.
local function gate()
	gui.Enabled = false
	UserInputService.MouseIconEnabled = true
end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()
