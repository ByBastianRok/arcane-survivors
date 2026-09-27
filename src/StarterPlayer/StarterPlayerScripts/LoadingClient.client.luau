-- LoadingClient (LocalScript) - Sco Fase B: SOLO en el PLACE DE JUEGO y SOLO si llegas por TELEPORT a un match:
-- tapa la pantalla mientras arranca la run (evita ver el lobby-copia esos ~2s). Se quita al empezar el match.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
if game.PlaceId ~= Config.GamePlaceId then return end -- solo en el place de JUEGO (en el lobby no hace nada)

-- Solo tapar si LLEGAMOS por teleport con datos de match. Si alguien entra DIRECTO (sin teleport), NO tapar:
-- asi nunca se ve una pantalla negra permanente sin run que arrancar (era el bug del "no hay lobby").
local td = TeleportService:GetLocalPlayerTeleportData()
if type(td) ~= "table" or td.world == nil then return end

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui")
local matchState = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MatchState")

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingCover"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 999
gui.Parent = playerGui
local bg = Instance.new("Frame")
bg.Size = UDim2.new(1, 0, 1, 0); bg.BackgroundColor3 = Color3.fromRGB(10, 10, 16); bg.BorderSizePixel = 0; bg.Parent = gui
local txt = Instance.new("TextLabel")
txt.AnchorPoint = Vector2.new(0.5, 0.5); txt.Position = UDim2.new(0.5, 0, 0.5, 0); txt.Size = UDim2.new(0, 500, 0, 60)
txt.BackgroundTransparency = 1; txt.Font = Enum.Font.GothamBlack; txt.TextSize = 30
txt.TextColor3 = Color3.fromRGB(235, 235, 250); txt.Text = "ENTERING MATCH..."; txt.Parent = bg

local hecho = false
local function ocultar()
	if hecho then return end
	hecho = true
	TweenService:Create(bg, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(txt, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	task.delay(0.5, function() gui:Destroy() end)
end

matchState.OnClientEvent:Connect(function(data)
	if data and data.state == "match" then ocultar() end -- la run arranco -> quita la pantalla
end)
pcall(function() matchState:FireServer() end) -- pide el estado actual por si el match ya empezo antes de conectar
-- Failsafe: el arranque real puede tardar ~40s en el PEOR caso (perfil hasta 25s + roster 12s + personajes 6s
-- + espera de perfiles de correrPartida). Con 18s la portada se quitaba ANTES de que empezara la run y el
-- jugador veia el "lobby copia" del place de juego creyendo que se habia colgado. El evento 'match' la quita
-- antes en las runs normales.
task.delay(20, function() if not hecho then txt.Text = "STILL LOADING PLAYERS..." end end)
task.delay(45, ocultar)
