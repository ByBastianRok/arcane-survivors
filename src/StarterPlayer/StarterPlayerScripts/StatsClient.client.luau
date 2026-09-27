-- StatsClient (LocalScript) · FASE 6 - panel "RUN STATS": el jugador ve su build de la partida.
-- El servidor (RunState) manda una foto de los modificadores; aqui se pinta legible. HP en vivo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local statsSync = remotes:WaitForChild("StatsSync")
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponData"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme")) -- solo para marcarMenu (contador de MenuAbierto)

local gui = Instance.new("ScreenGui")
gui.Name = "RunStats"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 41
gui.Parent = playerGui

-- Boton STATS. Solo se ve EN PARTIDA. Ha hecho el mismo viaje (y el mismo error) que el SHOP:
--   1. estaba abajo a la izquierda (x 296..416), dentro del radio del joystick de movimiento en movil,
--   2. lo mande abajo a la derecha, que es donde estan los BOTONES DE HABILIDAD -> se encimaron.
-- Ahora va al carril derecho a media altura, JUSTO ENCIMA del SHOP: ese carril en partida esta libre porque
-- es donde vive la columna de iconos del lobby, que se oculta con InMatch.
local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.new(0, 120, 0, 44)
openBtn.AnchorPoint = Vector2.new(1, 0.5)
openBtn.Position = UDim2.new(1, -12, 0.5, -28)
openBtn.BackgroundColor3 = Color3.fromRGB(56, 48, 80) -- placa oscura (era plano 120,90,200); el acento va en degradado+filo
openBtn.Font = Enum.Font.GothamBold
openBtn.TextSize = 16
openBtn.TextColor3 = Color3.fromRGB(238, 232, 250)
openBtn.Text = "STATS"
openBtn.Parent = gui
local obc = Instance.new("UICorner"); obc.CornerRadius = UDim.new(0, 10); obc.Parent = openBtn
local obg = Instance.new("UIGradient"); obg.Rotation = 90; obg.Color = ColorSequence.new(Color3.fromRGB(72, 62, 100), Color3.fromRGB(44, 38, 62)); obg.Parent = openBtn
local obs = Instance.new("UIStroke", openBtn); obs.Color = Color3.fromRGB(150, 118, 230); obs.Thickness = 1.5; obs.Transparency = 0.3 -- filo morado: se ve tocable

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4
overlay.Visible = false
overlay.Active = true -- absorbe los clics del fondo: sin esto atraviesan a los botones de detras (audit 22-jul)
overlay.Parent = gui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 420, 0, 480)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
panel.Parent = overlay
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 16); pc.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 40)
title.Position = UDim2.new(0, 20, 0, 14)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "RUN STATS"
title.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -40, 1, -118)
scroll.Position = UDim2.new(0, 20, 0, 62)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel
local sl = Instance.new("UIListLayout"); sl.Padding = UDim.new(0, 4); sl.Parent = scroll

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 200, 0, 40)
closeBtn.AnchorPoint = Vector2.new(0.5, 1)
closeBtn.Position = UDim2.new(0.5, 0, 1, -14)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextScaled = true
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "CLOSE"
closeBtn.Parent = panel
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = closeBtn

local datos = nil -- ultima foto de la build

local function fmtMult(x) return string.format("x%.2f", x) end

-- Arma equipada -> su ficha base (Dano/Cadencia) para mostrar valores REALES, no solo el multiplicador.
local function armaBase()
	local ch = player.Character
	local tool = ch and ch:FindFirstChildOfClass("Tool")
	return tool and WeaponData[tool.Name]
end
-- "base -> final" con el final en COLOR (verde si sube, rojo si baja). fmt formatea cada numero.
local ARROW = " <font color=\"rgb(130,140,160)\">→</font> "
local function baseFinal(base, final, fmt)
	fmt = fmt or function(v) return tostring(math.floor(v + 0.5)) end
	local mult = (base ~= 0) and (final / base) or 1
	local multTxt = string.format(" <font color=\"rgb(150,160,180)\">(x%.2f)</font>", mult)
	if math.abs(final - base) < 0.05 then return fmt(base) .. multTxt end -- sin build: valor + (x1.00) para que el multiplicador SIEMPRE se vea
	local col = (final > base) and "rgb(90,235,130)" or "rgb(255,120,120)"
	return string.format("%s%s<font color=\"%s\">%s</font>%s", fmt(base), ARROW, col, fmt(final), multTxt)
end

-- Construye la lista de { etiqueta, valor, resaltar? } a partir de la build + HP en vivo.
local function lineas()
	local L = {}
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		L[#L + 1] = { "Health", string.format("%d / %d", math.floor(hum.Health), math.floor(hum.MaxHealth)) }
	end
	if datos then
		local wd = armaBase()
		local dano = datos.danoMult * (datos.buffDanoMult or 1)
		if wd and (wd.Dano or 0) > 0 then
			L[#L + 1] = { "Damage", baseFinal(wd.Dano, wd.Dano * dano), (datos.buffDanoMult or 1) > 1 }
		else
			L[#L + 1] = { "Damage", fmtMult(dano), (datos.buffDanoMult or 1) > 1 }
		end
		local cad = datos.cadenciaMult * (datos.buffCadenciaMult or 1)
		if wd and (wd.Cadencia or 0) > 0 then
			L[#L + 1] = { "Fire rate", baseFinal(1 / wd.Cadencia, 1 / (wd.Cadencia * cad), function(v) return string.format("%.1f/s", v) end), (datos.buffCadenciaMult or 1) < 1 }
		else
			L[#L + 1] = { "Fire rate", fmtMult(1 / cad), (datos.buffCadenciaMult or 1) < 1 }
		end
		if datos.critChance > 0 then
			L[#L + 1] = { "Crit", string.format("%d%% (x%.1f)", math.floor(datos.critChance * 100 + 0.5), datos.critMult) }
		end
		if datos.rangoMult and datos.rangoMult > 1 then L[#L + 1] = { "Range", string.format("+%d%%", math.floor((datos.rangoMult - 1) * 100 + 0.5)) } end
		if datos.ejecutarBonus and datos.ejecutarBonus > 1 then L[#L + 1] = { "Execute", string.format("+%d%% under %d%% HP", math.floor((datos.ejecutarBonus - 1) * 100 + 0.5), math.floor((datos.ejecutarUmbral or 0.25) * 100 + 0.5)) } end
		if datos.cdMult and datos.cdMult < 1 then L[#L + 1] = { "Ability CD", string.format("-%d%%", math.floor((1 - datos.cdMult) * 100 + 0.5)) } end
		if datos.balasExtra > 0 then L[#L + 1] = { "Projectiles", "+" .. datos.balasExtra } end
		if datos.perforante then L[#L + 1] = { "Piercing", "Yes" } end
		if datos.elementosExtra and next(datos.elementosExtra) then
			local NOM = { Fuego = "Fire", Veneno = "Poison", Hielo = "Ice" }
			local es = {}
			for elem in pairs(datos.elementosExtra) do es[#es + 1] = NOM[elem] or elem end
			L[#L + 1] = { "Bullets", table.concat(es, " + ") }
		end
		if datos.roboVida > 0 then L[#L + 1] = { "Lifesteal", string.format("%d%%", math.floor(datos.roboVida * 100 + 0.5)) } end
		if datos.regen > 0 then L[#L + 1] = { "Regen", string.format("%d%% HP/s", math.floor(datos.regen * 100 + 0.5)) } end
		if datos.danoRecibidoMult < 1 then L[#L + 1] = { "Armor", string.format("-%d%% dmg", math.floor((1 - datos.danoRecibidoMult) * 100 + 0.5)) } end
			if datos.esquivar and datos.esquivar > 0 then L[#L + 1] = { "Dodge", string.format("%d%%", math.floor(datos.esquivar * 100 + 0.5)) } end
		L[#L + 1] = { "Move speed", baseFinal(16, 16 * datos.velocidadMult) }
		L[#L + 1] = { "Cash bonus", string.format("+%d%%", math.floor((datos.cashMult - 1) * 100 + 0.5)) }
			if datos.xpMult and datos.xpMult > 1 then L[#L + 1] = { "XP bonus", string.format("+%d%%", math.floor((datos.xpMult - 1) * 100 + 0.5)) } end
		L[#L + 1] = { "Luck", tostring(datos.suerte) }
		if datos.invulnerable then L[#L + 1] = { "INVINCIBLE", "active", true } end
	end
	return L
end

local function render()
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	for _, ln in ipairs(lineas()) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 34)
		row.BackgroundColor3 = ln[3] and Color3.fromRGB(60, 50, 30) or Color3.fromRGB(36, 36, 44)
		row.Parent = scroll
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row
		local lab = Instance.new("TextLabel")
		lab.Size = UDim2.new(0.6, -12, 1, 0); lab.Position = UDim2.new(0, 12, 0, 0)
		lab.BackgroundTransparency = 1; lab.Font = Enum.Font.Gotham; lab.TextScaled = true
		lab.TextXAlignment = Enum.TextXAlignment.Left; lab.TextColor3 = Color3.fromRGB(210, 210, 220)
		lab.Text = ln[1]; lab.Parent = row
		local val = Instance.new("TextLabel")
		val.Size = UDim2.new(0.4, -12, 1, 0); val.Position = UDim2.new(0.6, 0, 0, 0)
		val.BackgroundTransparency = 1; val.Font = Enum.Font.GothamBold; val.TextScaled = true; val.RichText = true
		val.TextXAlignment = Enum.TextXAlignment.Right; val.TextColor3 = ln[3] and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(255, 255, 255)
		val.Text = ln[2]; val.Parent = row
	end
end

statsSync.OnClientEvent:Connect(function(info)
	datos = info
	if overlay.Visible then render() end
end)

local abierto = false
local function abrir()
	abierto = true
	overlay.Visible = true
	UITheme.marcarMenu("stats", true) -- contador: no pisa el flag si hay otro panel abierto (audit 22-jul)
	render()
	statsSync:FireServer() -- pedir la build fresca
	task.spawn(function()
		while abierto do -- refrescar HP en vivo mientras el panel este abierto
			render()
			task.wait(0.4)
		end
	end)
end
local function cerrar()
	abierto = false
	overlay.Visible = false
	UITheme.marcarMenu("stats", false)
end
openBtn.MouseButton1Click:Connect(function()
	if overlay.Visible then cerrar() else abrir() end
end)
closeBtn.MouseButton1Click:Connect(cerrar)

-- El boton STATS solo se ve EN PARTIDA.
--
-- Y el PANEL se CIERRA solo cuando la run termina. Antes esto solo escondia el boton, y si morias (o
-- superabas el acto) con el panel abierto, volvias al lobby con: (a) un panel de RUN STATS viejo flotando,
-- (b) su overlay comiendose los clics, y (c) MenuAbierto pegado en true -> el Hub esconde su columna de
-- iconos y LobbyClient esconde el PLAY. O sea el lobby sin ningun boton, y sin forma de adivinar que lo
-- unico que lo desbloquea es el CLOSE de ese panel viejo.
local function gateBoton()
	local enPartida = player:GetAttribute("InMatch") == true
	openBtn.Visible = enPartida
	if not enPartida and overlay.Visible then cerrar() end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gateBoton)
gateBoton()

statsSync:FireServer() -- pedir build inicial al cargar
