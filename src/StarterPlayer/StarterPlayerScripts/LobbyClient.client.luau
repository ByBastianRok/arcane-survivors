-- LobbyClient (LocalScript) · bucle LOBBY <-> PARTIDA (cliente). Boton PLAY + pantalla de
-- resultados. Marca el atributo InMatch (los demas menus muestran/ocultan su boton segun el).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- CO-OP: en el place de JUEGO la run SOLO la arranca el teleport. El PLAY no debe existir ahi (si no, un
-- miembro podia lanzar una 2a run en paralelo durante el arranque). La pantalla de RESULTADOS si se usa aqui.
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local esPlaceJuego = (game.PlaceId == Config.GamePlaceId)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local startMatch = remotes:WaitForChild("StartMatch")
local matchState = remotes:WaitForChild("MatchState")
local matchEnd = remotes:WaitForChild("MatchEnd")

local gui = Instance.new("ScreenGui")
gui.Name = "Lobby"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 45; gui.Parent = playerGui

-- Aqui habia un cartelon blanco a media pantalla ("Upgrade in the menus -> then PLAY", GothamBlack de 600px
-- centrado arriba). Bastian: "no pega nada, lo quitaria". Y tiene razon: tapaba el lobby, era lo primero que
-- leias, y ya no hace falta -- la fila de iconos de arriba a la derecha lleva su etiqueta debajo de cada uno
-- (Quests / Classes / Forge / Perks / Store / Profile) y el PLAY es lo mas grande de la pantalla. Si algun dia
-- hace falta onboarding, va como tutorial de primera partida, no como un letrero permanente.

local playBtn = Instance.new("TextButton")
playBtn.Size = UDim2.new(0, 300, 0, 84); playBtn.AnchorPoint = Vector2.new(0.5, 1); playBtn.Position = UDim2.new(0.5, 0, 1, -90)
playBtn.BackgroundColor3 = Color3.fromRGB(58, 168, 84)
playBtn.AutoButtonColor = false
-- OJO: el UIGradient de un TextButton tine TAMBIEN su texto. Con el degradado puesto directamente aqui, el
-- "PLAY" salia verde oscuro en vez de blanco. Por eso el boton va SIN texto y la palabra es un TextLabel hijo
-- (los hijos no heredan el gradiente del padre).
playBtn.Text = ""; playBtn.Parent = gui
local pbc = Instance.new("UICorner"); pbc.CornerRadius = UDim.new(0, 14); pbc.Parent = playBtn
-- Degradado (claro arriba, oscuro abajo) + borde OSCURO. El verde plano con filo verde neon es el aspecto de
-- boton de plantilla; asi parece una pieza con volumen y pega con las placas de la fila de iconos.
local pbg = Instance.new("UIGradient")
pbg.Color = ColorSequence.new(Color3.fromRGB(104, 216, 126), Color3.fromRGB(36, 126, 62))
pbg.Rotation = 90; pbg.Parent = playBtn
local pbs = Instance.new("UIStroke"); pbs.Color = Color3.fromRGB(14, 46, 24); pbs.Thickness = 3; pbs.Transparency = 0.1; pbs.Parent = playBtn
-- Filo de luz pegado al borde de arriba y sombra pegada al de abajo. Son dos Frames de 2 px y son LO que
-- convierte un rectangulo verde en una pieza con volumen: el ojo lee el brillo arriba como "esto sobresale".
-- Van dentro del boton y con ClipsDescendants para que las esquinas redondeadas los recorten.
playBtn.ClipsDescendants = true
local pbLuz = Instance.new("Frame")
pbLuz.Size = UDim2.new(1, -16, 0, 2); pbLuz.Position = UDim2.new(0.5, 0, 0, 3)
pbLuz.AnchorPoint = Vector2.new(0.5, 0); pbLuz.BackgroundColor3 = Color3.fromRGB(190, 255, 205)
pbLuz.BackgroundTransparency = 0.55; pbLuz.BorderSizePixel = 0; pbLuz.Parent = playBtn
Instance.new("UICorner", pbLuz).CornerRadius = UDim.new(1, 0)
local pbSombra = Instance.new("Frame")
pbSombra.Size = UDim2.new(1, -10, 0, 3); pbSombra.Position = UDim2.new(0.5, 0, 1, -4)
pbSombra.AnchorPoint = Vector2.new(0.5, 0); pbSombra.BackgroundColor3 = Color3.fromRGB(10, 42, 20)
pbSombra.BackgroundTransparency = 0.45; pbSombra.BorderSizePixel = 0; pbSombra.Parent = playBtn
Instance.new("UICorner", pbSombra).CornerRadius = UDim.new(1, 0)

local pbTxt = Instance.new("TextLabel")
pbTxt.Size = UDim2.new(1, 0, 1, 0); pbTxt.BackgroundTransparency = 1
pbTxt.Font = Enum.Font.GothamBlack; pbTxt.TextScaled = false; pbTxt.TextSize = 38
pbTxt.TextColor3 = Color3.fromRGB(255, 255, 255)
pbTxt.TextStrokeColor3 = Color3.fromRGB(16, 52, 28); pbTxt.TextStrokeTransparency = 0.55
pbTxt.Text = "PLAY"; pbTxt.Parent = playBtn

-- Feedback al pulsar: la pieza se HUNDE (se apaga el filo de arriba y crece la sombra). En movil no hay
-- hover, asi que si el boton no reacciona al dedo parece que no ha registrado el toque y la gente lo repite.
playBtn.MouseButton1Down:Connect(function()
	pbLuz.BackgroundTransparency = 0.9
	pbSombra.BackgroundTransparency = 0.15
end)
playBtn.MouseButton1Up:Connect(function()
	pbLuz.BackgroundTransparency = 0.55
	pbSombra.BackgroundTransparency = 0.45
end)
-- pulso sutil para llamar la atencion al boton PLAY (solo la caja: el texto ya no escala)
TweenService:Create(playBtn, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.new(0, 314, 0, 88) }):Play()

local resFrame = Instance.new("Frame")
resFrame.Size = UDim2.new(1, 0, 1, 0); resFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
resFrame.BackgroundTransparency = 0.4; resFrame.Visible = false; resFrame.Active = true; resFrame.Parent = gui -- Active: velo modal absorbe clics (audit)
-- PANEL de resultados (bonito, no texto suelto sobre el velo): placa con degradado + barra de acento + stats.
local resPanel = Instance.new("Frame")
resPanel.AnchorPoint = Vector2.new(0.5, 0.5); resPanel.Position = UDim2.new(0.5, 0, 0.5, 0); resPanel.Size = UDim2.new(0, 460, 0, 380)
resPanel.BackgroundColor3 = Color3.fromRGB(30, 27, 42); resPanel.Parent = resFrame
Instance.new("UICorner", resPanel).CornerRadius = UDim.new(0, 18)
local rpg = Instance.new("UIGradient"); rpg.Rotation = 90; rpg.Color = ColorSequence.new(Color3.fromRGB(40, 36, 56), Color3.fromRGB(22, 20, 32)); rpg.Parent = resPanel
local rps = Instance.new("UIStroke", resPanel); rps.Color = Color3.fromRGB(72, 66, 94); rps.Thickness = 2; rps.Transparency = 0.2
local resAcento = Instance.new("Frame"); resAcento.Size = UDim2.new(1, 0, 0, 12); resAcento.BackgroundColor3 = Color3.fromRGB(90, 255, 130); resAcento.BorderSizePixel = 0; resAcento.Parent = resPanel
Instance.new("UICorner", resAcento).CornerRadius = UDim.new(0, 18)
local resTitle = Instance.new("TextLabel")
resTitle.Size = UDim2.new(1, -40, 0, 58); resTitle.Position = UDim2.new(0, 20, 0, 34); resTitle.BackgroundTransparency = 1
resTitle.Font = Enum.Font.GothamBlack; resTitle.TextScaled = true; resTitle.TextColor3 = Color3.fromRGB(90, 255, 130); resTitle.Text = "RUN OVER"; resTitle.Parent = resPanel
local resBody = Instance.new("TextLabel")
resBody.Size = UDim2.new(1, -50, 0, 150); resBody.Position = UDim2.new(0, 25, 0, 108); resBody.BackgroundTransparency = 1
resBody.Font = Enum.Font.GothamBold; resBody.TextScaled = true; resBody.TextColor3 = Color3.fromRGB(235, 235, 245); resBody.Text = ""; resBody.Parent = resPanel
local backBtn = Instance.new("TextButton")
backBtn.Size = UDim2.new(0, 260, 0, 56); backBtn.AnchorPoint = Vector2.new(0.5, 1); backBtn.Position = UDim2.new(0.5, 0, 1, -22)
backBtn.BackgroundColor3 = Color3.fromRGB(44, 40, 60); backBtn.Font = Enum.Font.GothamBold; backBtn.TextSize = 20
backBtn.TextColor3 = Color3.fromRGB(238, 236, 244); backBtn.Text = "BACK TO LOBBY"; backBtn.Parent = resPanel
Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, 12)
local bbs = Instance.new("UIStroke", backBtn); bbs.Color = Color3.fromRGB(140, 120, 210); bbs.Thickness = 1.5; bbs.Transparency = 0.25

local function refrescar()
	local oculto = (player:GetAttribute("InMatch") == true) or (player:GetAttribute("MenuAbierto") == true) or esPlaceJuego
	playBtn.Visible = not oculto
end
local function setLobbyUI(inMatch)
	player:SetAttribute("InMatch", inMatch)
	refrescar()
end
-- ocultar PLAY tambien si hay un menu abierto (gacha, etc.)
player:GetAttributeChangedSignal("MenuAbierto"):Connect(refrescar)

matchState.OnClientEvent:Connect(function(info)
	setLobbyUI(info.state == "match")
end)

playBtn.MouseButton1Click:Connect(function()
	-- Fase B: abre el SELECTOR de mundos (lo escucha WorldSelectClient via este atributo);
	-- el menu es quien hace startMatch(world, act, dif).
	player:SetAttribute("AbrirMundos", (player:GetAttribute("AbrirMundos") or 0) + 1)
end)

matchEnd.OnClientEvent:Connect(function(info)
	local ganado = info.cleared == true
	local col = ganado and Color3.fromRGB(90, 255, 130) or Color3.fromRGB(255, 96, 96)
	resTitle.Text = ganado and "RUN WON!" or "RUN OVER"; resTitle.TextColor3 = col; resAcento.BackgroundColor3 = col
	local extra = ((info.gems or 0) > 0) and string.format("     +%d Gems", info.gems) or "" -- Gems solo si de verdad ganaste (1er clear)
	resBody.Text = string.format("Wave %d      Score %d\n\n+%d Cash%s", info.wave or 0, info.score or 0, info.cash or 0, extra)
	resFrame.Visible = true
end)

backBtn.MouseButton1Click:Connect(function()
	resFrame.Visible = false
end)

setLobbyUI(false) -- por defecto lobby hasta que llegue el estado real
matchState:FireServer()
