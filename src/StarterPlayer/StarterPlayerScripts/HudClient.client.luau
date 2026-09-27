-- HudClient  (LocalScript)  ·  HUD de la partida (oleada / enemigos / score / vida / monedas /
-- munición / jefe / buffs / números de daño). Solo PINTA: el servidor manda los datos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CameraShake = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CameraShake"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local hudUpdate = remotes:WaitForChild("HudUpdate")
local ammoUpdate = remotes:WaitForChild("AmmoUpdate")
local bossHealth = remotes:WaitForChild("BossHealth")
local buffUpdate = remotes:WaitForChild("BuffUpdate")

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false -- no se borra al reaparecer el personaje
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Oleada actual (arriba centro)
local waveLabel = Instance.new("TextLabel")
waveLabel.Size = UDim2.new(0, 300, 0, 40)
waveLabel.Position = UDim2.new(0.5, -150, 0, 10)
waveLabel.BackgroundTransparency = 1
waveLabel.Font = Enum.Font.GothamBold
waveLabel.TextScaled = true
waveLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
waveLabel.TextStrokeTransparency = 0.4
waveLabel.Text = "Wave 1"
waveLabel.Parent = gui

-- ===================================================================================================
-- INTRO CINEMATICA al empezar la run (22-jul, pedido por Bastian, estilo su foto "GRASSLANDS"). El servidor
-- (GameManager) pone RunMundo/RunDif/RunActo y sube IntroTick; aqui se pinta: dificultad pequena arriba,
-- NOMBRE DEL MUNDO grande, linea de acento, cuenta atras, todo con fundido sobre la arena visible.
-- ===================================================================================================
local DIF_COLOR = {
	Trial = Color3.fromRGB(120, 200, 255), Torment = Color3.fromRGB(255, 165, 85), Oblivion = Color3.fromRGB(255, 85, 85),
}
local introGui = Instance.new("ScreenGui")
introGui.Name = "MatchIntro"; introGui.ResetOnSpawn = false; introGui.IgnoreGuiInset = true
introGui.DisplayOrder = 60; introGui.Enabled = false; introGui.Parent = playerGui
local introBg = Instance.new("Frame")
introBg.Size = UDim2.fromScale(1, 1); introBg.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
introBg.BackgroundTransparency = 1; introBg.BorderSizePixel = 0; introBg.Parent = introGui
local introDif = Instance.new("TextLabel")
introDif.Size = UDim2.new(1, 0, 0, 30); introDif.Position = UDim2.new(0, 0, 0.35, 0); introDif.BackgroundTransparency = 1
introDif.Font = Enum.Font.GothamBold; introDif.TextSize = 22; introDif.TextColor3 = Color3.fromRGB(120, 200, 255)
introDif.TextTransparency = 1; introDif.Text = ""; introDif.Parent = introBg
local introMundo = Instance.new("TextLabel")
introMundo.Size = UDim2.new(1, -60, 0, 90); introMundo.Position = UDim2.new(0, 30, 0.4, 0); introMundo.BackgroundTransparency = 1
introMundo.Font = Enum.Font.GothamBlack; introMundo.TextScaled = true; introMundo.TextColor3 = Color3.new(1, 1, 1)
introMundo.TextTransparency = 1; introMundo.TextStrokeTransparency = 1; introMundo.Text = ""; introMundo.Parent = introBg
local introLinea = Instance.new("Frame")
introLinea.Size = UDim2.fromOffset(0, 2); introLinea.Position = UDim2.new(0.5, 0, 0.4, 96); introLinea.AnchorPoint = Vector2.new(0.5, 0)
introLinea.BackgroundColor3 = Color3.fromRGB(120, 200, 255); introLinea.BorderSizePixel = 0; introLinea.BackgroundTransparency = 1; introLinea.Parent = introBg
local introCuenta = Instance.new("TextLabel")
introCuenta.Size = UDim2.new(1, 0, 0, 34); introCuenta.Position = UDim2.new(0, 0, 0.57, 0); introCuenta.BackgroundTransparency = 1
introCuenta.Font = Enum.Font.GothamMedium; introCuenta.TextSize = 24; introCuenta.TextColor3 = Color3.fromRGB(210, 210, 220)
introCuenta.TextTransparency = 1; introCuenta.Text = ""; introCuenta.Parent = introBg

local introActivo = false
local function reproducirIntro()
	if introActivo then return end
	introActivo = true
	-- RunMundo/RunDif pueden replicar 1 frame DESPUES de IntroTick (el orden entre atributos no esta garantizado):
	-- esperamos a que llegue el nombre antes de pintar (si no, saldria vacio y la intro no se veria).
	local mundo = ""
	for _ = 1, 12 do
		mundo = tostring(workspace:GetAttribute("RunMundo") or "")
		if mundo ~= "" then break end
		task.wait()
	end
	if mundo == "" then introActivo = false; return end
	local dif = tostring(workspace:GetAttribute("RunDif") or "")
	local acto = workspace:GetAttribute("RunActo") or 0
	local col = DIF_COLOR[dif] or Color3.fromRGB(200, 200, 210)
	introDif.Text = string.upper(dif) .. ((acto and acto > 0) and ("   ·   ACT " .. acto) or "")
	introDif.TextColor3 = col
	introMundo.Text = string.upper(mundo)
	introLinea.BackgroundColor3 = col
	introCuenta.Text = "Starting in 3"
	introGui.Enabled = true
	introBg.BackgroundTransparency = 1
	TweenService:Create(introBg, TweenInfo.new(0.4), { BackgroundTransparency = 0.3 }):Play()
	TweenService:Create(introDif, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	TweenService:Create(introMundo, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	TweenService:Create(introCuenta, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	introLinea.Size = UDim2.fromOffset(0, 2); introLinea.BackgroundTransparency = 0
	TweenService:Create(introLinea, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(360, 2) }):Play()
	task.spawn(function()
		for n = 3, 1, -1 do
			introCuenta.Text = "Starting in " .. n
			task.wait(0.9)
		end
		TweenService:Create(introBg, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		for _, o in ipairs({ introDif, introMundo, introCuenta }) do TweenService:Create(o, TweenInfo.new(0.4), { TextTransparency = 1 }):Play() end
		TweenService:Create(introLinea, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.5)
		introGui.Enabled = false
		introActivo = false
	end)
end
workspace:GetAttributeChangedSignal("IntroTick"):Connect(reproducirIntro)

-- Enemigos restantes (debajo)
local enemiesLabel = Instance.new("TextLabel")
enemiesLabel.Size = UDim2.new(0, 300, 0, 26)
enemiesLabel.Position = UDim2.new(0.5, -150, 0, 52)
enemiesLabel.BackgroundTransparency = 1
enemiesLabel.Font = Enum.Font.Gotham
enemiesLabel.TextScaled = true
enemiesLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
enemiesLabel.TextStrokeTransparency = 0.6
enemiesLabel.Text = "Enemies: 0"
enemiesLabel.Parent = gui

-- Puntuacion (debajo)
local scoreLabel = Instance.new("TextLabel")
scoreLabel.Size = UDim2.new(0, 300, 0, 22)
scoreLabel.Position = UDim2.new(0.5, -150, 0, 80)
scoreLabel.BackgroundTransparency = 1
scoreLabel.Font = Enum.Font.GothamBold
scoreLabel.TextScaled = true
scoreLabel.TextColor3 = Color3.fromRGB(120, 230, 150)
scoreLabel.TextStrokeTransparency = 0.6
scoreLabel.Text = "Score: 0"
scoreLabel.Parent = gui

-- Barra de XP (arriba del todo, ancho completo) + nivel (S1.2 survivors)
local xpBarBg = Instance.new("Frame")
xpBarBg.Name = "XpBar"
xpBarBg.Size = UDim2.new(1, 0, 0, 12)
xpBarBg.Position = UDim2.new(0, 0, 0, 0)
xpBarBg.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
xpBarBg.BorderSizePixel = 0
xpBarBg.Parent = gui
local xpFill = Instance.new("Frame")
xpFill.Size = UDim2.new(0, 0, 1, 0)
xpFill.BackgroundColor3 = Color3.fromRGB(120, 220, 255)
xpFill.BorderSizePixel = 0
xpFill.Parent = xpBarBg
local levelLbl = Instance.new("TextLabel")
levelLbl.Name = "Level"
levelLbl.Size = UDim2.new(0, 90, 0, 22)
levelLbl.Position = UDim2.new(0, 10, 0, 88) -- audit: era y=15 (chocaba con el boton de menu de Roblox, y<52). Bajado por debajo de la fila de monedas.
levelLbl.BackgroundTransparency = 1
levelLbl.Font = Enum.Font.GothamBlack
levelLbl.TextScaled = true
levelLbl.TextXAlignment = Enum.TextXAlignment.Left
levelLbl.TextColor3 = Color3.fromRGB(150, 230, 255)
levelLbl.TextStrokeTransparency = 0.4
levelLbl.Text = "LV 1"
levelLbl.Parent = gui

-- (El HUD de armas ahora es la Hotbar propia: HotbarClient pinta nombre + municion + recarga
--  en el slot equipado. Aqui ya no hay panel de arma.)

-- Flash rojo al recibir dano (cubre la pantalla; ZIndex 0 = detras del resto del HUD)
local dmgFlash = Instance.new("Frame")
dmgFlash.Size = UDim2.new(1, 0, 1, 0)
dmgFlash.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
dmgFlash.BackgroundTransparency = 1
dmgFlash.ZIndex = 0
dmgFlash.Parent = gui

-- Barra de vida (abajo centro)
local hpFrame = Instance.new("Frame")
hpFrame.Size = UDim2.new(0, 320, 0, 28)
hpFrame.AnchorPoint = Vector2.new(0.5, 1)
hpFrame.Position = UDim2.new(0.5, 0, 1, -84) -- encima de la hotbar
hpFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
hpFrame.Parent = gui
local hpc = Instance.new("UICorner"); hpc.CornerRadius = UDim.new(0, 8); hpc.Parent = hpFrame
local hpFill = Instance.new("Frame")
hpFill.Size = UDim2.new(1, 0, 1, 0)
hpFill.BackgroundColor3 = Color3.fromRGB(70, 200, 90)
hpFill.BorderSizePixel = 0
hpFill.Parent = hpFrame
local hfc = Instance.new("UICorner"); hfc.CornerRadius = UDim.new(0, 8); hfc.Parent = hpFill
local hpText = Instance.new("TextLabel")
hpText.Size = UDim2.new(1, 0, 1, 0); hpText.BackgroundTransparency = 1
hpText.Font = Enum.Font.GothamBold; hpText.TextScaled = true
hpText.TextColor3 = Color3.fromRGB(255, 255, 255); hpText.TextStrokeTransparency = 0.4
hpText.Text = "100 / 100"; hpText.ZIndex = 2; hpText.Parent = hpFrame

-- Monedas en pantalla (arriba izquierda; contextual lobby/partida)
-- Estaba en y=14 con IgnoreGuiInset=true, o sea DENTRO de la barra superior de Roblox: en todas las capturas
-- se lee "ms: 5835" porque el boton de Roblox se comia la mitad izquierda del texto. Y encima el boton PARTY
-- (DisplayOrder 40 contra el 0 de este HUD) se le plantaba encima. Justo el dato de monetizacion.
-- El carril limpio empieza en y~52. Aqui se coloca a la derecha del engranaje de ajustes (x 16..58).
-- ===== Saldo (pastillas por moneda) =====
-- Antes: UN TextLabel verde "Cash: N   Gems: M" para AMBAS monedas, sin iconos ni distincion (audit 22-jul,
-- Bastian: "cash y gems lo has descuidado"). Ahora una PASTILLA por moneda con su icono y su color canonico:
-- Cash verde, Gems MORADO (el mismo tono que el gacha), Coins oro en partida.
local COL_CASH = UITheme.color.cash   -- fuente unica (audit 22-jul): mismos tonos en todas las pantallas
local COL_GEMS = UITheme.color.gemas  -- morado de Gems = el del Gacha
local COL_COINS = UITheme.color.coins

local monedasRow = Instance.new("Frame")
monedasRow.Name = "Monedas"; monedasRow.BackgroundTransparency = 1
monedasRow.Position = UDim2.new(0, 68, 0, 54); monedasRow.Size = UDim2.new(0, 480, 0, 30)
monedasRow.Parent = gui
local mrl = Instance.new("UIListLayout", monedasRow)
mrl.FillDirection = Enum.FillDirection.Horizontal; mrl.Padding = UDim.new(0, 8)
mrl.VerticalAlignment = Enum.VerticalAlignment.Center; mrl.SortOrder = Enum.SortOrder.LayoutOrder

local function crearPastilla(nombre, icono, color, orden)
	local p = Instance.new("Frame"); p.Name = nombre; p.AutomaticSize = Enum.AutomaticSize.X
	p.Size = UDim2.fromOffset(0, 30); p.LayoutOrder = orden; p.Parent = monedasRow
	UITheme.placa(p, { fondo = Color3.fromRGB(30, 29, 37), radio = UITheme.radio.pildora, borde = color, grosor = 1, bordeTransp = 0.55 })
	local pad = Instance.new("UIPadding", p); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 12)
	local lay = Instance.new("UIListLayout", p); lay.FillDirection = Enum.FillDirection.Horizontal
	lay.Padding = UDim.new(0, 7); lay.VerticalAlignment = Enum.VerticalAlignment.Center; lay.SortOrder = Enum.SortOrder.LayoutOrder
	local ic = Instance.new("Frame"); ic.Size = UDim2.fromOffset(18, 18); ic.BackgroundTransparency = 1; ic.LayoutOrder = 1; ic.Parent = p
	UITheme.icono(ic, icono, color, { lado = 18, pos = UDim2.new(0.5, 0, 0.5, 0), anchor = Vector2.new(0.5, 0.5) })
	local v = Instance.new("TextLabel"); v.Name = "Valor"; v.AutomaticSize = Enum.AutomaticSize.X; v.Size = UDim2.fromOffset(0, 20)
	v.BackgroundTransparency = 1; v.Font = UITheme.fuente.dato; v.TextSize = 15; v.TextColor3 = color; v.Text = "0"; v.LayoutOrder = 2; v.Parent = p
	return p, v
end

local cashPill, cashVal = crearPastilla("Cash", "monedas", COL_CASH, 1)
local gemsPill, gemsVal = crearPastilla("Gems", "gema", COL_GEMS, 2)
local coinsPill, coinsVal = crearPastilla("Coins", "monedas", COL_COINS, 4)

-- El "+" de comprar Gems, PEGADO a la pastilla de Gems (el boton que mas convierte en F2P movil). Con feedback
-- tactil (audit: no daba ninguno). Sube un atributo y StoreClient lo escucha (los scripts no se conocen).
local masGems = Instance.new("TextButton")
masGems.Name = "MasGems"; masGems.Size = UDim2.fromOffset(30, 30); masGems.LayoutOrder = 3
masGems.BackgroundColor3 = Color3.fromRGB(46, 42, 60); masGems.AutoButtonColor = false
masGems.Font = Enum.Font.GothamBlack; masGems.TextSize = 20; masGems.TextColor3 = COL_GEMS; masGems.Text = "+"
masGems.Parent = monedasRow
Instance.new("UICorner", masGems).CornerRadius = UDim.new(0, 8)
local mgs = Instance.new("UIStroke"); mgs.Color = COL_GEMS; mgs.Thickness = 1.5; mgs.Transparency = 0.35; mgs.Parent = masGems
UITheme.pulsacion(masGems)
masGems.MouseButton1Click:Connect(function()
	player:SetAttribute("AbrirStore", (player:GetAttribute("AbrirStore") or 0) + 1)
end)

-- Barra de vida del jefe (arriba centro, oculta por defecto)
local bossFrame = Instance.new("Frame")
bossFrame.Size = UDim2.new(0, 600, 0, 44)
bossFrame.AnchorPoint = Vector2.new(0.5, 0)
bossFrame.Position = UDim2.new(0.5, 0, 0, 118) -- audit: era y=70 (solapaba "Enemies"/"Score" del carril central). Bajado por debajo del score.
bossFrame.BackgroundTransparency = 1
bossFrame.Visible = false
bossFrame.Parent = gui

local bossName = Instance.new("TextLabel")
bossName.Size = UDim2.new(1, 0, 0, 20)
bossName.BackgroundTransparency = 1
bossName.Font = Enum.Font.GothamBlack
bossName.TextScaled = true
bossName.TextColor3 = Color3.fromRGB(255, 90, 90)
bossName.TextStrokeTransparency = 0.3
bossName.Text = "BOSS"
bossName.Parent = bossFrame

local bossBarBg = Instance.new("Frame")
bossBarBg.Size = UDim2.new(1, 0, 0, 18)
bossBarBg.Position = UDim2.new(0, 0, 0, 24)
bossBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
bossBarBg.BorderSizePixel = 0
bossBarBg.Parent = bossFrame
local bbgc = Instance.new("UICorner"); bbgc.CornerRadius = UDim.new(0, 6); bbgc.Parent = bossBarBg

local bossBarFill = Instance.new("Frame")
bossBarFill.Size = UDim2.new(1, 0, 1, 0)
bossBarFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
bossBarFill.BorderSizePixel = 0
bossBarFill.Parent = bossBarBg
local bfc = Instance.new("UICorner"); bfc.CornerRadius = UDim.new(0, 6); bfc.Parent = bossBarFill

-- Segmentos de FASE (lineas divisorias) + color de barra por fase. Se reconstruyen al cambiar de jefe.
local bossSegs = Instance.new("Folder"); bossSegs.Name = "Segmentos"; bossSegs.Parent = bossBarBg
local FASE_COLORES = {
	Color3.fromRGB(225, 60, 60),   -- fase 1
	Color3.fromRGB(245, 150, 40),  -- fase 2 (se enfada)
	Color3.fromRGB(215, 55, 150),  -- fase 3 (enrage)
	Color3.fromRGB(150, 60, 230),  -- fase 4+
}
local bossUmbralesKey = ""
local function faseDe(umbrales, frac)
	local idx = 1
	for i, u in ipairs(umbrales) do if frac <= u then idx = i end end
	return idx
end
local function reconstruirSegmentos(umbrales)
	local key = table.concat(umbrales, ",")
	if key == bossUmbralesKey then return end -- mismo jefe: no reconstruir cada 0.15s
	bossUmbralesKey = key
	bossSegs:ClearAllChildren()
	for _, u in ipairs(umbrales) do
		if u < 0.999 and u > 0.001 then -- no en los extremos de la barra
			local ln = Instance.new("Frame")
			ln.AnchorPoint = Vector2.new(0.5, 0.5)
			ln.Position = UDim2.new(u, 0, 0.5, 0)
			ln.Size = UDim2.new(0, 2, 1, 0)
			ln.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
			ln.BackgroundTransparency = 0.1
			ln.BorderSizePixel = 0
			ln.ZIndex = 4
			ln.Parent = bossSegs
		end
	end
end

-- Power-ups temporales activos (arriba a la izquierda)
local buffFrame = Instance.new("Frame")
buffFrame.Size = UDim2.new(0, 230, 0, 130)
buffFrame.Position = UDim2.new(0, 16, 0, 120)
buffFrame.BackgroundTransparency = 1
buffFrame.Parent = gui
local buffLayout = Instance.new("UIListLayout")
buffLayout.Padding = UDim.new(0, 4)
buffLayout.Parent = buffFrame
local buffsActivos = {} -- buffsActivos[name] = label

-- Banner central para mensajes temporales
local banner = Instance.new("TextLabel")
banner.Size = UDim2.new(0, 600, 0, 60)
banner.Position = UDim2.new(0.5, -300, 0.22, 0)
banner.BackgroundTransparency = 1
banner.Font = Enum.Font.GothamBlack
banner.TextScaled = true
banner.TextColor3 = Color3.fromRGB(255, 255, 255)
banner.TextStrokeTransparency = 0.3
banner.Visible = false
banner.Text = ""
banner.Parent = gui

-- (La antigua pantalla de Game Over + boton RETRY se borro: era codigo muerto. El fin de run lo pinta
--  ahora el RESULTS del LobbyClient, y el server nunca disparaba "GameOver" ni escuchaba "Retry".)

-- ===== Lógica =====
local bannerToken = 0
local function mostrarBanner(texto)
	bannerToken += 1
	local mio = bannerToken
	banner.Text = texto
	banner.Visible = true
	task.delay(2.2, function()
		if bannerToken == mio then banner.Visible = false end
	end)
end

hudUpdate.OnClientEvent:Connect(function(info)
	if info.wave then waveLabel.Text = "Wave " .. info.wave end
	if info.enemiesLeft ~= nil then enemiesLabel.Text = "Enemies: " .. info.enemiesLeft end
	if info.score ~= nil then scoreLabel.Text = "Score: " .. info.score end
	if info.xp ~= nil and info.xpMax then xpFill.Size = UDim2.new(math.clamp(info.xp / info.xpMax, 0, 1), 0, 1, 0) end
	if info.level then levelLbl.Text = "LV " .. info.level end
	if info.message then mostrarBanner(info.message) end
end)

-- (AmmoUpdate lo gestiona ahora HotbarClient, que pinta la municion en el slot equipado.)

-- Oleada/enemigos/score/vida solo EN PARTIDA (en el lobby se ocultan).
local function gateHud()
	local inMatch = player:GetAttribute("InMatch") == true
	waveLabel.Visible = inMatch
	enemiesLabel.Visible = inMatch
	scoreLabel.Visible = inMatch
	xpBarBg.Visible = inMatch
	levelLbl.Visible = inMatch
	hpFrame.Visible = inMatch
end
player:GetAttributeChangedSignal("InMatch"):Connect(gateHud)
gateHud()

bossHealth.OnClientEvent:Connect(function(info)
	if info.dead then
		bossFrame.Visible = false
	else
		bossFrame.Visible = true
		bossName.Text = info.name or "BOSS"
		local frac = math.clamp(info.current / info.max, 0, 1)
		bossBarFill.Size = UDim2.new(frac, 0, 1, 0)
		if info.umbrales and #info.umbrales > 0 then
			reconstruirSegmentos(info.umbrales)
			bossBarFill.BackgroundColor3 = FASE_COLORES[math.min(faseDe(info.umbrales, frac), #FASE_COLORES)]
		end
	end
end)

-- Power-ups temporales: cada uno con su cuenta atras + contador de stack (xN) al refrescar.
buffUpdate.OnClientEvent:Connect(function(info)
	if not info or not info.name then return end
	local restante = info.duration or 5
	local lbl = buffsActivos[info.name]
	if not lbl then
		lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 26)
		lbl.BackgroundTransparency = 0.3
		lbl.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 230, 120)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Parent = buffFrame
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = lbl
		local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 8); pad.Parent = lbl
		buffsActivos[info.name] = lbl
		lbl:SetAttribute("stack", 1)
		lbl:SetAttribute("until", os.clock() + restante)
		task.spawn(function()
			while lbl.Parent do
				local queda = (lbl:GetAttribute("until") or 0) - os.clock()
				if queda <= 0 then
					buffsActivos[info.name] = nil
					lbl:Destroy()
					break
				end
				local st = lbl:GetAttribute("stack") or 1
				if st > 1 then
					lbl.Text = string.format("%s  (x%d)  %ds", info.name, st, math.ceil(queda))
				else
					lbl.Text = string.format("%s  %ds", info.name, math.ceil(queda))
				end
				task.wait(0.2)
			end
		end)
	else
		-- Coger el MISMO buff: refresca el tiempo y sube el contador de stack (xN). El efecto NO se
		-- apila de momento (solo el tiempo) -- decision de Bastian; cambiar aqui si se quiere apilar.
		lbl:SetAttribute("stack", (lbl:GetAttribute("stack") or 1) + 1)
		lbl:SetAttribute("until", os.clock() + restante)
	end
end)

-- ===== Barra de vida + flash de dano (Fase 8) =====
local function pintarVida(hum)
	local frac = (hum.MaxHealth > 0) and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
	hpFill.Size = UDim2.new(frac, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(70, 200, 90), frac)
	hpText.Text = math.floor(hum.Health + 0.5) .. " / " .. math.floor(hum.MaxHealth + 0.5)
end
local function flashDano()
	if player:GetAttribute("SettingScreenFlash") == false then return end -- ajuste
	dmgFlash.BackgroundTransparency = 0.55
	TweenService:Create(dmgFlash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end
local function hookVida(char)
	local hum = char:WaitForChild("Humanoid")
	pintarVida(hum)
	local ultima = hum.Health
	hum.HealthChanged:Connect(function(nueva)
		pintarVida(hum)
		if nueva < ultima - 0.01 then flashDano(); CameraShake.shake(0.35, 0.3); SoundManager.play("hurt") end
		ultima = nueva
	end)
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(function() pintarVida(hum) end)
end
player.CharacterAdded:Connect(hookVida)
if player.Character then task.spawn(hookVida, player.Character) end

-- ===== Monedas en pantalla (Cash/Gems en lobby, Coins en partida) =====
local function actualizarMonedas()
	local ls = player:FindFirstChild("leaderstats")
	local enMatch = player:GetAttribute("InMatch") == true
	cashPill.Visible = not enMatch
	gemsPill.Visible = not enMatch
	masGems.Visible = not enMatch -- en partida la moneda es Coins (no se compra) y la tienda esta cerrada
	coinsPill.Visible = enMatch
	if enMatch then
		local coins = player:FindFirstChild("Coins"); coinsVal.Text = tostring(coins and coins.Value or 0)
	else
		local cash = ls and ls:FindFirstChild("Cash"); cashVal.Text = tostring(cash and cash.Value or 0)
		local gems = ls and ls:FindFirstChild("Gems"); gemsVal.Text = tostring(gems and gems.Value or 0)
	end
end
player:GetAttributeChangedSignal("InMatch"):Connect(actualizarMonedas)
task.spawn(function()
	local ls = player:WaitForChild("leaderstats")
	ls:WaitForChild("Cash").Changed:Connect(actualizarMonedas)
	ls:WaitForChild("Gems").Changed:Connect(actualizarMonedas)
	local coins = player:WaitForChild("Coins")
	coins.Changed:Connect(actualizarMonedas)
	actualizarMonedas()
end)
player:GetAttributeChangedSignal("InMatch"):Connect(actualizarMonedas)
