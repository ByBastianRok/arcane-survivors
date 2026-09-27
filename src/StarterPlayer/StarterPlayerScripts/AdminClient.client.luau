-- AdminClient (LocalScript) · DEV - menu de testeo. SOLO se construye para Bastian o en Studio.
-- El servidor (GameManager) revalida esAdmin en CADA accion, asi que es seguro aunque alguien lo copie.
-- Rediseño: panel grande, por secciones de color, botones en 2 columnas, cerrar con X. Nombres de la version final.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local ADMIN_ID = 0 -- configura tu UserId de Roblox (0 = menu admin solo en Studio)
if not (RunService:IsStudio() or player.UserId == ADMIN_ID) then return end

local admin = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin")

local ROJO = Color3.fromRGB(220, 70, 70)

local gui = Instance.new("ScreenGui")
gui.Name = "AdminMenu"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 90
gui.Parent = player:WaitForChild("PlayerGui")

-- ===== Boton flotante ADMIN (debajo de la barra nativa de Roblox) =====
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(104, 36); toggle.Position = UDim2.fromOffset(8, 56)
toggle.BackgroundColor3 = ROJO; toggle.Text = "⚙ ADMIN"; toggle.Font = Enum.Font.GothamBlack
toggle.TextSize = 15; toggle.TextColor3 = Color3.new(1, 1, 1); toggle.AutoButtonColor = true; toggle.Parent = gui
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)
local ts = Instance.new("UIStroke", toggle); ts.Color = Color3.fromRGB(90, 20, 20); ts.Thickness = 2; ts.Transparency = 0.2

-- ===== Panel =====
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(392, 620); panel.Position = UDim2.fromOffset(8, 100)
panel.BackgroundColor3 = Color3.fromRGB(24, 22, 28); panel.Visible = false; panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local pStroke = Instance.new("UIStroke", panel); pStroke.Color = Color3.fromRGB(90, 40, 44); pStroke.Thickness = 1.5; pStroke.Transparency = 0.2
local acc = Instance.new("Frame"); acc.Size = UDim2.new(1, 0, 0, 8); acc.BackgroundColor3 = ROJO; acc.BorderSizePixel = 0; acc.Parent = panel
Instance.new("UICorner", acc).CornerRadius = UDim.new(0, 14)

local titulo = Instance.new("TextLabel")
titulo.BackgroundTransparency = 1; titulo.Position = UDim2.new(0, 16, 0, 16); titulo.Size = UDim2.new(1, -60, 0, 26)
titulo.Font = Enum.Font.GothamBlack; titulo.TextSize = 19; titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.TextColor3 = Color3.new(1, 1, 1); titulo.Text = "ADMIN  ·  DEV"; titulo.Parent = panel
local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 16, 0, 40); sub.Size = UDim2.new(1, -60, 0, 14)
sub.Font = Enum.Font.Gotham; sub.TextSize = 11; sub.TextXAlignment = Enum.TextXAlignment.Left
sub.TextColor3 = Color3.fromRGB(150, 140, 145); sub.Text = "solo tu cuenta · se quita al lanzar"; sub.Parent = panel

local cerrar = Instance.new("TextButton")
cerrar.AnchorPoint = Vector2.new(1, 0); cerrar.Position = UDim2.new(1, -12, 0, 14); cerrar.Size = UDim2.fromOffset(34, 34)
cerrar.BackgroundColor3 = Color3.fromRGB(70, 40, 44); cerrar.Text = "X"; cerrar.Font = Enum.Font.GothamBlack
cerrar.TextSize = 16; cerrar.TextColor3 = Color3.fromRGB(240, 200, 205); cerrar.Parent = panel
Instance.new("UICorner", cerrar).CornerRadius = UDim.new(0, 8)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 12, 0, 64); scroll.Size = UDim2.new(1, -24, 1, -76)
scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = ROJO; scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = panel
local sLay = Instance.new("UIListLayout"); sLay.Padding = UDim.new(0, 10); sLay.SortOrder = Enum.SortOrder.LayoutOrder; sLay.Parent = scroll

toggle.MouseButton1Click:Connect(function() panel.Visible = not panel.Visible end)
cerrar.MouseButton1Click:Connect(function() panel.Visible = false end)

-- item = { texto, accion, v2, v3, v4 }
local SECCIONES = {
	{ titulo = "RESOURCES", color = Color3.fromRGB(120, 220, 130), items = {
		{ "+500 XP (level up)", "xp", 500 }, { "+100k Cash", "cash", 100000 },
		{ "+5k Gems", "gems", 5000 }, { "+50k Gems", "gems", 50000 },
		{ "+100 ALL materials", "mat", 100 }, { "+25 Luck", "luck", 25 },
	} },
	{ titulo = "START RUN  (world · act · difficulty)", color = Color3.fromRGB(110, 180, 255), items = {
		{ "Woods · A1 (Trial)", "world", 1, 1 }, { "Woods · A4 · Boss", "world", 1, 4 },
		{ "Woods · A1 · Torment", "world", 1, 1, "hard" }, { "Woods · A1 · Oblivion", "world", 1, 1, "nightmare" },
		{ "Frostfell · A1", "world", 2, 1 }, { "Frostfell · A4 · Boss", "world", 2, 4 },
		{ "Emberforge · A1", "world", 3, 1 }, { "Emberforge · A4 · Boss", "world", 3, 4 },
	} },
	{ titulo = "COMBAT", color = ROJO, items = {
		{ "Spawn Forest Warden", "boss", 1 }, { "Spawn Glacial Sentinel", "boss", 2 },
		{ "Spawn Magma Colossus", "boss", 3 }, { "GOD MODE (toggle)", "god" },
		{ "KILL ALL enemies", "killall" }, { "RESET perks", "resetperks" },
	} },
	{ titulo = "CLASS + EVO RECIPE  (in-run)", color = Color3.fromRGB(180, 120, 240), items = {
		{ "Mage → Inferno Orb", "evo", "Mage" }, { "Archer → Storm Bow", "evo", "Archer" },
		{ "Knight → Doom Greatsword", "evo", "Knight" }, { "Bloodreaver → Blood Harvest", "evo", "Bloodreaver" },
		{ "Trickster → Bladestorm", "evo", "Trickster" }, { "UNLOCK ALL evos (Forge)", "unlockevos" },
	} },
	{ titulo = "FUN / TROLL", color = Color3.fromRGB(255, 210, 70), items = {
		{ "🦣 GIANT  x5", "size", 5 }, { "🗿 COLOSSAL  x10", "size", 10 },
		{ "🐜 TINY  x0.4", "size", 0.4 }, { "🧍 NORMAL size", "size", 1 },
		{ "💨 SUPER SPEED", "speed", 70 }, { "❤️ HEAL to full", "heal" },
	} },
}

local orden = 0
for _, sec in ipairs(SECCIONES) do
	orden += 1
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 22); h.BackgroundTransparency = 1; h.Text = "▎ " .. sec.titulo
	h.Font = Enum.Font.GothamBlack; h.TextSize = 12; h.TextXAlignment = Enum.TextXAlignment.Left
	h.TextColor3 = sec.color; h.LayoutOrder = orden; h.Parent = scroll

	orden += 1
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1; grid.Size = UDim2.new(1, 0, 0, 0); grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = orden; grid.Parent = scroll
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -4, 0, 36); gl.CellPadding = UDim2.new(0, 8, 0, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.Parent = grid

	for i, it in ipairs(sec.items) do
		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = Color3.fromRGB(44, 42, 52); btn.Text = it[1]
		btn.Font = Enum.Font.GothamBold; btn.TextSize = 12; btn.TextColor3 = Color3.fromRGB(238, 236, 244)
		btn.TextWrapped = true; btn.AutoButtonColor = true; btn.LayoutOrder = i; btn.Parent = grid
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
		local bs = Instance.new("UIStroke", btn); bs.Color = sec.color; bs.Thickness = 1; bs.Transparency = 0.72
		btn.MouseButton1Click:Connect(function() admin:FireServer(it[2], it[3], it[4], it[5]) end)
	end
end
