-- RunShopClient (LocalScript) · FASE 6 - SHOP de RUN upgrades (temporales, con Coins).
-- Coins se ganan matando y se reinician cada partida. La compra la valida el SERVIDOR (RunShop).
-- El boton SHOP solo se ve EN PARTIDA.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local runShopSync = remotes:WaitForChild("RunShopSync")
local buyRunUpgrade = remotes:WaitForChild("BuyRunUpgrade")
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))

local gui = Instance.new("ScreenGui")
gui.Name = "RunShop"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 40; gui.Parent = playerGui

-- Este boton SOLO se ve en partida (mas abajo, gateado con InMatch).
--
-- Ha hecho DOS viajes, y el primero fue un error mio:
--   1. Estaba abajo a la IZQUIERDA (x 16..146), que es donde Roblox pinta el joystick de movimiento en movil:
--      al ir a moverte hacia esa esquina abrias la tienda en pleno combate.
--   2. Lo mande abajo a la DERECHA... que es donde estan los BOTONES DE HABILIDAD (AbilityHUD ocupa
--      x 1540..1712, y 631..711 en 1736x793). O sea que lo saque de una zona ocupada para meterlo en otra.
--      Se veia clarisimo en una captura de partida: STATS y SHOP encimados sobre el boton de Dash.
-- Ahora va al carril DERECHO a MEDIA ALTURA, que en partida esta libre de verdad: ahi vive la columna de
-- iconos del lobby, y esa se oculta con InMatch. Ademas asi el sitio de "los menus" es el mismo en el lobby
-- y en la partida, que es una cosa menos que aprender.
local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.new(0, 120, 0, 44); openBtn.AnchorPoint = Vector2.new(1, 0.5); openBtn.Position = UDim2.new(1, -12, 0.5, 24)
openBtn.BackgroundColor3 = Color3.fromRGB(44, 40, 34); openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 16 -- era azul (60,120,200) fuera de paleta + TextScaled (audit 22-jul); tono calido de tienda + marco abajo
openBtn.TextColor3 = Color3.fromRGB(255, 255, 255); openBtn.Text = "SHOP"; openBtn.Parent = gui
local obc = Instance.new("UICorner"); obc.CornerRadius = UDim.new(0, 10); obc.Parent = openBtn
local obs = Instance.new("UIStroke", openBtn); obs.Color = Color3.fromRGB(212, 150, 70); obs.Thickness = 1.5; obs.Transparency = 0.35 -- marco de acento (tienda) = se ve tocable

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0); overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4; overlay.Visible = false; overlay.Active = true; overlay.Parent = gui -- Active: absorbe clics del fondo (audit 22-jul)

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 540, 0, 480); panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(24, 24, 30); panel.Parent = overlay
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 16); pc.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 38); title.Position = UDim2.new(0, 20, 0, 12); title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack; title.TextScaled = true; title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255); title.Text = "SHOP  (this run)"; title.Parent = panel

local curLabel = Instance.new("TextLabel")
curLabel.Size = UDim2.new(1, -40, 0, 26); curLabel.Position = UDim2.new(0, 20, 0, 52); curLabel.BackgroundTransparency = 1
curLabel.Font = Enum.Font.GothamBold; curLabel.TextScaled = true; curLabel.TextXAlignment = Enum.TextXAlignment.Right
curLabel.TextColor3 = Color3.fromRGB(255, 215, 90); curLabel.Text = "Coins: 0"; curLabel.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -40, 1, -150); scroll.Position = UDim2.new(0, 20, 0, 92); scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 6; scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = panel
local sl = Instance.new("UIListLayout"); sl.Padding = UDim.new(0, 8); sl.Parent = scroll

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 200, 0, 40); closeBtn.AnchorPoint = Vector2.new(0.5, 1); closeBtn.Position = UDim2.new(0.5, 0, 1, -14)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 70, 70); closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextScaled = true
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); closeBtn.Text = "CLOSE"; closeBtn.Parent = panel
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = closeBtn

local ultimo = {}

local function leerCoins()
	local c = player:FindFirstChild("Coins")
	return c and c.Value or 0
end
local function actualizarCoins()
	curLabel.Text = "Coins: " .. leerCoins()
end

local function render()
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local coins = leerCoins()
	for _, up in ipairs(ultimo) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 60); row.BackgroundColor3 = Color3.fromRGB(36, 36, 44); row.Parent = scroll
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(0.6, -10, 0, 26); nm.Position = UDim2.new(0, 12, 0, 6); nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold; nm.TextScaled = true; nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextColor3 = Color3.fromRGB(255, 255, 255); nm.Text = string.format("%s  (Lv %d/%d)", up.nombre, up.level, up.maxLevel); nm.Parent = row
		local ds = Instance.new("TextLabel")
		ds.Size = UDim2.new(0.6, -10, 0, 22); ds.Position = UDim2.new(0, 12, 0, 32); ds.BackgroundTransparency = 1
		ds.Font = Enum.Font.Gotham; ds.TextScaled = true; ds.TextXAlignment = Enum.TextXAlignment.Left
		ds.TextColor3 = Color3.fromRGB(200, 200, 205); ds.Text = up.desc; ds.Parent = row
		local buy = Instance.new("TextButton")
		buy.Size = UDim2.new(0, 150, 0, 42); buy.AnchorPoint = Vector2.new(1, 0.5); buy.Position = UDim2.new(1, -12, 0.5, 0)
		buy.Font = Enum.Font.GothamBold; buy.TextScaled = true; buy.TextColor3 = Color3.fromRGB(255, 255, 255)
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = buy
		buy.Parent = row
		if up.cost == nil then
			buy.Text = "MAX"; buy.BackgroundColor3 = Color3.fromRGB(80, 80, 90); buy.AutoButtonColor = false
		else
			local puede = coins >= up.cost
			buy.Text = "BUY  " .. up.cost
			buy.BackgroundColor3 = puede and Color3.fromRGB(210, 170, 50) or Color3.fromRGB(90, 90, 100)
			buy.AutoButtonColor = puede
			if puede then buy.MouseButton1Click:Connect(function() SoundManager.play("pickup"); buyRunUpgrade:FireServer(up.id) end) end -- 22-jul: sfx al mejorar in-run (Bastian)
		end
	end
end

runShopSync.OnClientEvent:Connect(function(info)
	if info.upgrades then ultimo = info.upgrades end
	actualizarCoins()
	if overlay.Visible then render() end
end)

local function abrir()
	overlay.Visible = true
	player:SetAttribute("MenuAbierto", true)
	actualizarCoins()
	render()
	runShopSync:FireServer()
end
local function cerrar()
	overlay.Visible = false
	player:SetAttribute("MenuAbierto", false)
end
openBtn.MouseButton1Click:Connect(function()
	if overlay.Visible then cerrar() else abrir() end
end)
closeBtn.MouseButton1Click:Connect(cerrar)

task.spawn(function()
	local coins = player:WaitForChild("Coins")
	coins.Changed:Connect(function() actualizarCoins(); if overlay.Visible then render() end end)
	actualizarCoins()
end)

-- El boton SHOP (run upgrades) solo se ve EN PARTIDA.
--
-- Y el PANEL se CIERRA solo al acabar la run: mismo motivo que en StatsClient. Antes, morir con la tienda
-- abierta te dejaba en el lobby con el panel viejo encima, su overlay comiendose los clics, y MenuAbierto
-- pegado en true -> sin columna de iconos y sin boton PLAY.
local function gateBoton()
	local enPartida = player:GetAttribute("InMatch") == true
	openBtn.Visible = enPartida
	if not enPartida and overlay.Visible then cerrar() end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gateBoton)
gateBoton()

runShopSync:FireServer()
