-- SettingsClient (LocalScript) · FASE 8 + Sju - panel de AJUSTES con PESTAÑAS (engranaje).
-- Los ajustes viven como atributos del jugador (Setting*) que leen los demas scripts cliente
-- (MusicClient, SoundManager, DamageNumbersClient, HudClient, CameraShake).
--
-- Sju: ahora PERSISTEN. Antes solo existian en la sesion y se reseteaban cada vez que entrabas. El cliente ya
-- NO escribe los atributos: manda el cambio al servidor (SettingsSync), el servidor lo valida, lo guarda en el
-- perfil y pone el atributo -> la UI se repinta al ver el cambio. Server-authoritative, como todo lo demas.
--
-- Pestaña CODES: preparada para los codigos promocionales (aun sin backend). Cuando se implemente, solo hay que
-- cablear el boton REDEEM a su remote; la UI ya esta.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local settingsSync = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SettingsSync")
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme")) -- solo para marcarMenu (contador de MenuAbierto)

-- Valores de arranque para que el panel no salga vacio antes de que conteste el servidor (el servidor manda).
local DEFAULTS = { DamageNumbers = true, ScreenFlash = true, CameraShake = true, MusicVol = 70, SfxVol = 80 }
for k, v in pairs(DEFAULTS) do
	if player:GetAttribute("Setting" .. k) == nil then player:SetAttribute("Setting" .. k, v) end
end

local gui = Instance.new("ScreenGui")
gui.Name = "Settings"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 70
gui.Parent = playerGui

-- Boton de engranaje (arriba izquierda). Estaba en y=48 con IgnoreGuiInset: en moviles donde la barra de
-- Roblox mide 50 px quedaba 2 px por debajo, o sea practicamente pegado a ella. El carril limpio empieza en 52.
-- El contador de monedas va a su derecha (x 68) y el boton PARTY justo debajo (y 100).
local gear = Instance.new("TextButton")
gear.Name = "GearBtn"
gear.Size = UDim2.fromOffset(44, 44) -- audit: >= 44 tactil
gear.Position = UDim2.fromOffset(16, 52)
gear.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
gear.BackgroundTransparency = 0.15
gear.Text = "\u{2699}" -- engranaje
gear.Font = Enum.Font.GothamBold
gear.TextSize = 26
gear.TextColor3 = Color3.fromRGB(225, 225, 240)
gear.Parent = gui
local gcc = Instance.new("UICorner"); gcc.CornerRadius = UDim.new(0, 10); gcc.Parent = gear
local gst = Instance.new("UIStroke"); gst.Color = Color3.fromRGB(80, 85, 100); gst.Transparency = 0.4; gst.Parent = gear

-- Fondo oscuro (click fuera = cerrar) + panel central.
local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dim.BackgroundTransparency = 0.5
dim.Text = ""
dim.AutoButtonColor = false
dim.Visible = false
dim.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Active = true -- absorbe clics (no cierra al tocar dentro)
panel.Size = UDim2.fromOffset(380, 430)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
panel.Parent = dim
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 14); pc.Parent = panel
local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(90, 100, 120); ps.Transparency = 0.3; ps.Parent = panel

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -60, 0, 30)
titulo.Position = UDim2.fromOffset(20, 14)
titulo.BackgroundTransparency = 1
titulo.Font = Enum.Font.GothamBlack
titulo.TextScaled = true
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
titulo.Text = "OPTIONS"
titulo.Parent = panel

local cerrar = Instance.new("TextButton")
cerrar.Size = UDim2.fromOffset(44, 44) -- audit: >= 44 tactil
cerrar.AnchorPoint = Vector2.new(1, 0)
cerrar.Position = UDim2.new(1, -14, 0, 14)
cerrar.BackgroundColor3 = Color3.fromRGB(60, 40, 45)
cerrar.Text = "X"
cerrar.Font = Enum.Font.GothamBold
cerrar.TextScaled = true
cerrar.TextColor3 = Color3.fromRGB(255, 200, 200)
cerrar.Parent = panel
local ccc = Instance.new("UICorner"); ccc.CornerRadius = UDim.new(0, 8); ccc.Parent = cerrar

-- ===== PESTAÑAS =====
local barra = Instance.new("Frame")
barra.Size = UDim2.new(1, -40, 0, 44) -- audit: tabs >= 44 tactil
barra.Position = UDim2.fromOffset(20, 52)
barra.BackgroundTransparency = 1
barra.Parent = panel
local bl = Instance.new("UIListLayout")
bl.FillDirection = Enum.FillDirection.Horizontal
bl.Padding = UDim.new(0, 8)
bl.Parent = barra

local paginas = {}   -- [nombre] = Frame
local botonesTab = {} -- [nombre] = TextButton
local tabActual

local function mostrarTab(nombre)
	tabActual = nombre
	for n, pagina in pairs(paginas) do pagina.Visible = (n == nombre) end
	for n, btn in pairs(botonesTab) do
		local on = (n == nombre)
		btn.BackgroundColor3 = on and Color3.fromRGB(60, 90, 150) or Color3.fromRGB(38, 38, 48)
		btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 185, 200)
	end
end

local function nuevaTab(nombre, etiqueta)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(110, 44) -- audit: >= 44 tactil
	btn.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 15
	btn.Text = etiqueta
	btn.TextColor3 = Color3.fromRGB(180, 185, 200)
	btn.Parent = barra
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = btn

	local pagina = Instance.new("Frame")
	pagina.Size = UDim2.new(1, -40, 1, -110)
	pagina.Position = UDim2.fromOffset(20, 96)
	pagina.BackgroundTransparency = 1
	pagina.Visible = false
	pagina.Parent = panel
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 10)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = pagina

	botonesTab[nombre] = btn
	paginas[nombre] = pagina
	btn.MouseButton1Click:Connect(function() mostrarTab(nombre) end)
	return pagina
end

local pagAjustes = nuevaTab("settings", "SETTINGS")
local pagCodes = nuevaTab("codes", "CODES")

-- ===== FILAS (dentro de la pagina de ajustes) =====
local orden = 0
local function nuevaFila(padre, texto)
	orden += 1
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	row.BackgroundTransparency = 0.3
	row.LayoutOrder = orden
	row.Parent = padre
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -120, 1, 0)
	lbl.Position = UDim2.fromOffset(12, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(235, 235, 245)
	lbl.TextSize = 17
	lbl.Text = texto
	lbl.Parent = row
	return row
end

-- El cliente NO escribe el atributo: pide el cambio al servidor y repinta cuando el servidor lo confirma.
local function pedirCambio(setting, valor)
	settingsSync:FireServer(setting, valor)
end

local function filaToggle(setting, texto)
	local row = nuevaFila(pagAjustes, texto)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(76, 40) -- audit: mas alto tactil
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -10, 0.5, 0)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 15
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Parent = row
	local bcc = Instance.new("UICorner"); bcc.CornerRadius = UDim.new(0, 8); bcc.Parent = btn
	local function pintar()
		local on = player:GetAttribute("Setting" .. setting) == true
		btn.Text = on and "ON" or "OFF"
		btn.BackgroundColor3 = on and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(80, 80, 92)
	end
	btn.MouseButton1Click:Connect(function()
		pedirCambio(setting, not (player:GetAttribute("Setting" .. setting) == true))
	end)
	player:GetAttributeChangedSignal("Setting" .. setting):Connect(pintar) -- el servidor manda: repintamos al confirmar
	pintar()
end

local function filaStepper(setting, texto)
	local row = nuevaFila(pagAjustes, texto)
	local function mkBtn(txt, dx)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(38, 40) -- audit: mas alto/ancho tactil (cabe en la fila de 44)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, dx, 0.5, 0)
		b.BackgroundColor3 = Color3.fromRGB(55, 60, 75)
		b.Text = txt
		b.Font = Enum.Font.GothamBold
		b.TextSize = 20
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Parent = row
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = b
		return b
	end
	local plus = mkBtn("+", -10)
	local val = Instance.new("TextLabel")
	val.Size = UDim2.fromOffset(46, 30)
	val.AnchorPoint = Vector2.new(1, 0.5)
	val.Position = UDim2.new(1, -44, 0.5, 0)
	val.BackgroundTransparency = 1
	val.Font = Enum.Font.GothamBold
	val.TextSize = 18
	val.TextColor3 = Color3.fromRGB(255, 230, 150)
	val.Parent = row
	local minus = mkBtn("-", -94)
	local function pintar() val.Text = tostring(player:GetAttribute("Setting" .. setting)) end
	local function mover(dx)
		pedirCambio(setting, math.clamp((player:GetAttribute("Setting" .. setting) or 0) + dx, 0, 100))
	end
	plus.MouseButton1Click:Connect(function() mover(10) end)
	minus.MouseButton1Click:Connect(function() mover(-10) end)
	player:GetAttributeChangedSignal("Setting" .. setting):Connect(pintar)
	pintar()
end

filaStepper("MusicVol", "Music Volume")
filaStepper("SfxVol", "SFX Volume")
filaToggle("DamageNumbers", "Damage Numbers")
filaToggle("ScreenFlash", "Screen Flash")
filaToggle("CameraShake", "Camera Shake")

-- ===== PESTAÑA CODES (preparada, sin backend todavia) =====
local codeInfo = Instance.new("TextLabel")
codeInfo.Size = UDim2.new(1, 0, 0, 54)
codeInfo.BackgroundTransparency = 1
codeInfo.Font = Enum.Font.Gotham
codeInfo.TextWrapped = true
codeInfo.TextSize = 15
codeInfo.TextColor3 = Color3.fromRGB(210, 214, 226)
codeInfo.Text = "Redeem codes for free Gems and rewards. Follow the game's community to get new codes!"
codeInfo.LayoutOrder = 1
codeInfo.Parent = pagCodes

local caja = Instance.new("TextBox")
caja.Size = UDim2.new(1, 0, 0, 44)
caja.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
caja.BackgroundTransparency = 0.2
caja.Font = Enum.Font.GothamBold
caja.TextSize = 17
caja.TextColor3 = Color3.fromRGB(255, 255, 255)
caja.PlaceholderText = "Enter code..."
caja.Text = ""
caja.ClearTextOnFocus = false
caja.TextEditable = false -- se activara cuando exista el backend de codigos
caja.LayoutOrder = 2
caja.Parent = pagCodes
local cajac = Instance.new("UICorner"); cajac.CornerRadius = UDim.new(0, 8); cajac.Parent = caja

local redeem = Instance.new("TextButton")
redeem.Size = UDim2.new(1, 0, 0, 44)
redeem.BackgroundColor3 = Color3.fromRGB(70, 75, 90)
redeem.Font = Enum.Font.GothamBlack
redeem.TextSize = 17
redeem.TextColor3 = Color3.fromRGB(200, 205, 220)
redeem.Text = "COMING SOON"
redeem.AutoButtonColor = false
redeem.Active = false
redeem.LayoutOrder = 3
redeem.Parent = pagCodes
local rc2 = Instance.new("UICorner"); rc2.CornerRadius = UDim.new(0, 8); rc2.Parent = redeem

mostrarTab("settings")

local function abrir(v)
	dim.Visible = v
	-- 'MenuAbierto' (antes "MenuOpen"): habia DOS nombres sueltos y ningun menu bloqueaba las dos cosas a la vez
	-- -> con la tienda/ajustes abiertos el PLAY seguia visible, y con el gacha abierto seguias moviendote en movil.
	-- marcarMenu con CONTADOR (audit 22-jul): cerrar Ajustes ya no apaga el flag si hay otro panel del Hub abierto.
	UITheme.marcarMenu("settings", v)
	if v then settingsSync:FireServer() end -- pide al servidor sus ajustes guardados (por si aun no llegaron)
end
gear.MouseButton1Click:Connect(function() abrir(true) end)
cerrar.MouseButton1Click:Connect(function() abrir(false) end)
-- C (fix): quitado el cerrar-al-tocar-el-velo; se cierra SOLO con la X.
