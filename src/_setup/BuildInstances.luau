-- BuildInstances  ·  Reconstruye las piezas que NO son código (instancias).
-- Esto NO es un script del juego: es una "receta" para rearmar la estructura desde cero
-- si algún día se pierde el place. Pégalo en la barra de comandos de Roblox Studio
-- (View → Command Bar) y ejecútalo UNA vez en modo Edit.
--
-- Los SCRIPTS (en /src) se copian aparte. Esto solo crea los "contenedores".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- 0) Carpetas de módulos y datos (los ModuleScripts se pegan luego desde /src)
for _, nombre in ipairs({ "Modules", "Data" }) do
	if not ReplicatedStorage:FindFirstChild(nombre) then
		local f = Instance.new("Folder")
		f.Name = nombre
		f.Parent = ReplicatedStorage
	end
end

-- 1) Carpeta Remotes + todos los RemoteEvents
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
for _, nombre in ipairs({
	"FireWeapon", "HudUpdate", "GameOver", "Retry", "Reload", "AmmoUpdate", "BossHealth",
	"OfferPowers", "PickPower", "BuffUpdate",                       -- Fase 5 (roguelite + power-ups)
	"ShopSync", "BuyUpgrade", "BuyWeapon", "StatsSync",            -- Fase 6 (PERKS + panel stats)
	"BuyRunUpgrade", "RunShopSync",                               -- Fase 6 (SHOP de run upgrades, Coins)
	"StartMatch", "MatchState", "MatchEnd", "MatchError", "WorldsSync", -- bucle LOBBY <-> PARTIDA (+ menu de mundos, Smo Fase B) · MatchError = aviso de teleport co-op fallido
	"QuestsSync",                                                -- Fase D (misiones diarias + racha de login)
	"CraftSync", "Craft",                                       -- Scr (crafteo: materiales + reliquias)
	"DamageNumber",                                              -- Fase 8 (numeros de dano flotantes)
	"Juice",                                                    -- Fase 11 (camera shake / efectos)
	"SelectClass",                                              -- S2 (selector de clase temporal -> gacha)
	"GachaSpin", "GachaSync",                                   -- S2 Parte B (gacha: tirada + sync de coleccion)
	"ProfileSync",                                              -- S2 (Player Info: stats meta + records)
	"UseAbility",                                               -- S2 (habilidades activas: Dash + Nova)
	"Admin",                                                    -- DEV (admin menu de testeo, gated)
	"ReviveOffer", "ReviveDecision",                            -- Smn (revivir pagando al morir: oferta + decision)
	"RankReward",                                              -- Sga (premio de ranking semanal al entrar)
	"PartyAction", "PartySync",                                -- Sco Fase B (party: invitar/aceptar/salir/kick + sync del estado)
	"SettingsSync",                                            -- Sju (ajustes que PERSISTEN en el perfil: volumen, toggles...)
}) do
	if not remotes:FindFirstChild(nombre) then
		local ev = Instance.new("RemoteEvent")
		ev.Name = nombre
		ev.Parent = remotes
	end
end

-- 1b) BindableEvent servidor->servidor (Fase 5B): el drop de munición avisa al WeaponServer.
if not ServerScriptService:FindFirstChild("AmmoRefill") then
	local b = Instance.new("BindableEvent")
	b.Name = "AmmoRefill"
	b.Parent = ServerScriptService
end

-- 1c) BindableEvent servidor->servidor (Smn): la compra del revive avisa al GameManager (server-only, seguro).
if not ServerScriptService:FindFirstChild("ReviveComprado") then
	local b = Instance.new("BindableEvent")
	b.Name = "ReviveComprado"
	b.Parent = ServerScriptService
end

-- 2) Armas: Tool con Handle + Muzzle, en ServerStorage.WeaponTemplates (Fase 6). El servidor
--    da SOLO las armas compradas (MetaStore). El nombre coincide con la clave en WeaponData.
local templates = ServerStorage:FindFirstChild("WeaponTemplates")
if not templates then
	templates = Instance.new("Folder")
	templates.Name = "WeaponTemplates"
	templates.Parent = ServerStorage
end

local function crearArma(nombre, size, color, material)
	local vieja = templates:FindFirstChild(nombre)
	if vieja then vieja:Destroy() end
	local tool = Instance.new("Tool")
	tool.Name = nombre
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Parent = templates
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Color = color
	handle.Material = material
	handle.Parent = tool
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -size.Z / 2) -- delante del cañón
	muzzle.Parent = handle
end

crearArma("Pistol", Vector3.new(0.6, 1.2, 2.4), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
crearArma("Shotgun", Vector3.new(0.55, 1.0, 4.0), Color3.fromRGB(90, 55, 30), Enum.Material.Wood)
crearArma("SMG", Vector3.new(0.5, 1.0, 2.2), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
crearArma("Sniper", Vector3.new(0.4, 0.9, 5.2), Color3.fromRGB(30, 35, 30), Enum.Material.Metal)
crearArma("Rocket Launcher", Vector3.new(0.8, 1.2, 5.5), Color3.fromRGB(60, 80, 50), Enum.Material.Metal)
-- Clases (S2): armas de fantasia (mismo sistema Tool+Handle+Muzzle).
crearArma("Arcane Wand", Vector3.new(0.4, 0.4, 2.6), Color3.fromRGB(120, 70, 200), Enum.Material.Neon)
crearArma("Hunter Bow", Vector3.new(0.3, 2.6, 0.5), Color3.fromRGB(110, 80, 50), Enum.Material.Wood)
crearArma("War Blade", Vector3.new(0.3, 4.0, 0.9), Color3.fromRGB(200, 215, 235), Enum.Material.Metal)
crearArma("Reaver Scythe", Vector3.new(0.3, 4.2, 1.2), Color3.fromRGB(150, 20, 30), Enum.Material.Metal) -- Bloodreaver (Legendary)
crearArma("Chakram", Vector3.new(1.4, 0.25, 1.4), Color3.fromRGB(80, 240, 220), Enum.Material.Neon) -- Trickster (Legendary)

-- 3) LOBBY: plataforma + SpawnLocation, lejos de la arena. Los jugadores aparecen aqui y PLAY
--    los teleporta a la arena (Config.ArenaPos / Config.LobbyPos). Se desactivan otros spawns.
local floor = Workspace:FindFirstChild("LobbyFloor")
if floor then floor:Destroy() end
floor = Instance.new("Part")
floor.Name = "LobbyFloor"
floor.Anchored = true
floor.Size = Vector3.new(70, 2, 70)
floor.Position = Vector3.new(300, 49, 0)
floor.Material = Enum.Material.WoodPlanks
floor.Color = Color3.fromRGB(95, 70, 50)
floor.Parent = Workspace

local sp = Workspace:FindFirstChild("LobbySpawn")
if sp then sp:Destroy() end
sp = Instance.new("SpawnLocation")
sp.Name = "LobbySpawn"
sp.Anchored = true
sp.Size = Vector3.new(10, 1, 10)
sp.Position = Vector3.new(300, 50.5, 0)
sp.Neutral = true
sp.Color = Color3.fromRGB(80, 160, 255)
sp.Material = Enum.Material.Neon
sp.Parent = Workspace

for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("SpawnLocation") and d ~= sp then d.Enabled = false end
end

-- 4) ILUMINACION bonita + cartel de titulo de la lobby (Fase 8).
local Lighting = game:GetService("Lighting")
Lighting.Brightness = 2
Lighting.ClockTime = 14.5
Lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 130)
-- OJO: Lighting.Technology = Future hay que ponerlo A MANO en Studio (el sandbox no deja por script).
for _, n in ipairs({ "Atmosphere", "GameBloom", "GameColor" }) do
	local e = Lighting:FindFirstChild(n); if e then e:Destroy() end
end
local atmo = Instance.new("Atmosphere"); atmo.Name = "Atmosphere"
atmo.Density = 0.3; atmo.Offset = 0.2; atmo.Haze = 1.4; atmo.Glare = 0.1
atmo.Color = Color3.fromRGB(199, 207, 225); atmo.Decay = Color3.fromRGB(106, 112, 125); atmo.Parent = Lighting
local bloom = Instance.new("BloomEffect"); bloom.Name = "GameBloom"
bloom.Intensity = 0.5; bloom.Size = 24; bloom.Threshold = 1.2; bloom.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect"); cc.Name = "GameColor"
cc.Saturation = 0.1; cc.Contrast = 0.05; cc.Parent = Lighting

local viejoTitulo = Workspace:FindFirstChild("LobbyTitle")
if viejoTitulo then viejoTitulo:Destroy() end
local sign = Instance.new("Part")
sign.Name = "LobbyTitle"; sign.Anchored = true; sign.CanCollide = false; sign.CanQuery = false
sign.Transparency = 1; sign.Size = Vector3.new(1, 1, 1)
sign.Position = Vector3.new(300, 64, 0) -- LobbyPos (300,52,0) + 12 en Y
sign.Parent = Workspace
local tbb = Instance.new("BillboardGui"); tbb.Size = UDim2.fromOffset(720, 150); tbb.MaxDistance = 150; tbb.Parent = sign
local t1 = Instance.new("TextLabel")
t1.Size = UDim2.new(1, 0, 0.68, 0); t1.BackgroundTransparency = 1
t1.Font = Enum.Font.GothamBlack; t1.TextScaled = true
t1.TextColor3 = Color3.fromRGB(255, 90, 200); t1.TextStrokeTransparency = 0.15
t1.Text = "ARCANE SURVIVORS"; t1.Parent = tbb
local t2 = Instance.new("TextLabel")
t2.Size = UDim2.new(1, 0, 0.3, 0); t2.Position = UDim2.new(0, 0, 0.7, 0); t2.BackgroundTransparency = 1
t2.Font = Enum.Font.GothamBold; t2.TextScaled = true
t2.TextColor3 = Color3.fromRGB(235, 235, 255); t2.TextStrokeTransparency = 0.4
t2.Text = "Survive the waves - Buy PERKS - PLAY"; t2.Parent = tbb

print("OK: carpetas, Remotes, AmmoRefill, 5 armas (ServerStorage), LOBBY, iluminacion y cartel reconstruidos. Pega los scripts de /src.")
