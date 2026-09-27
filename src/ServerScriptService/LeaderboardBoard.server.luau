-- LeaderboardBoard (Script del SERVIDOR) · Sga v2 - MURO DE LA FAMA: 5 tableros en SEMICIRCULO en el lobby.
-- Bastian: la tabla unica era "3 barras de piedra y un bloque negro con fuente triste". Ahora hay varios boards
-- (mejor oleada del Endless / score / gemas / horas / partidas) en arco, el central (DEEPEST WAVE) mas grande,
-- con render bonito (degradado, medallas top-3, podio con los avatares de los 3 mejores) y refresco periodico.
-- Los datos salen de Leaderboard.topDe(cual) (OrderedDataStore por stat, ver Leaderboard.registrarStats).
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leaderboard = require(ServerScriptService:WaitForChild("Leaderboard"))
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local lobby = Config.LobbyPos

-- ===== CONFIG de los 5 boards (orden = izquierda -> derecha del arco; el central va grande) =====
local PISO = 50 -- cara superior del suelo del lobby (Config.LobbyPos.Y son 52)
local RADIO = 88 -- radio del arco (detras del spawn, mirando hacia el)
local ANG_INI, ANG_FIN = 135, 225 -- B (fix): semicirculo mas cerrado -> Most Runs / Most Hours salen del hueco entre pilares (antes un pilar los tapaba)

local BOARDS = {
	{ key = "horas", titulo = "MOST HOURS", color = Color3.fromRGB(120, 200, 255), fmt = function(v) return string.format("%dh", math.floor(v / 60)) end },
	{ key = "score", titulo = "TOP SCORE",  color = Color3.fromRGB(255, 210, 90),  fmt = function(v) return tostring(v) end },
	{ key = "wave",  titulo = "DEEPEST WAVE", color = Color3.fromRGB(196, 96, 255), fmt = function(v) return "Wave " .. v end, grande = true }, -- CENTRO
	{ key = "gems",  titulo = "MOST GEMS",  color = Color3.fromRGB(176, 132, 250),  fmt = function(v) return tostring(v) end },
	{ key = "runs",  titulo = "MOST RUNS",  color = Color3.fromRGB(120, 220, 150),  fmt = function(v) return tostring(v) end },
}

-- ===== limpieza de lo viejo =====
for _, n in ipairs({ "LeaderboardBoard", "LeaderboardMarco", "Leaderboards" }) do
	local o = workspace:FindFirstChild(n); if o then o:Destroy() end
end
local raiz = Instance.new("Folder"); raiz.Name = "Leaderboards"; raiz.Parent = workspace

-- ===== caches (nombre + avatar) =====
local nombres, avatares = {}, {}
local function nombreDe(userId)
	if nombres[userId] then return nombres[userId] end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	nombres[userId] = (ok and n) or ("User" .. userId)
	return nombres[userId]
end
local function avatarDe(userId)
	if avatares[userId] then return avatares[userId] end
	local ok, img = pcall(function()
		return (Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150))
	end)
	avatares[userId] = (ok and img) or ""
	return avatares[userId]
end

local MEDALLA = { Color3.fromRGB(255, 210, 90), Color3.fromRGB(206, 210, 222), Color3.fromRGB(214, 150, 86) } -- oro/plata/bronce

-- ===== construccion de un board (Part + pedestal + SurfaceGui con bg/titulo/lista) =====
local function construirBoard(cfg, cframe, grande)
	local ancho = grande and 24 or 18
	local alto = grande and 27 or 21

	-- pedestal de piedra (para que no flote)
	local base = Instance.new("Part")
	base.Name = "Base"; base.Anchored = true; base.CanCollide = false; base.CanQuery = false; base.CastShadow = false
	base.Size = Vector3.new(ancho + 3, 3, 4)
	base.CFrame = cframe * CFrame.new(0, -(alto / 2) - 1.5, 0)
	base.Color = Color3.fromRGB(46, 44, 58); base.Material = Enum.Material.Slate
	base.Parent = raiz

	-- marco (parte un poco mayor detras, tintada con el color del board -> "filo" de acento)
	local marco = Instance.new("Part")
	marco.Name = "Marco"; marco.Anchored = true; marco.CanCollide = false; marco.CanQuery = false; marco.CastShadow = false
	marco.Size = Vector3.new(ancho + 1.4, alto + 1.4, 0.5)
	marco.CFrame = cframe * CFrame.new(0, 0, 0.2)
	marco.Color = cfg.color:Lerp(Color3.fromRGB(0, 0, 0), 0.55); marco.Material = Enum.Material.SmoothPlastic
	marco.Parent = raiz

	-- tablero
	local board = Instance.new("Part")
	board.Name = "Board_" .. cfg.key; board.Anchored = true; board.CanCollide = false; board.CanQuery = false; board.CastShadow = false
	board.Size = Vector3.new(ancho, alto, 0.6)
	board.CFrame = cframe
	board.Color = Color3.fromRGB(20, 18, 28); board.Material = Enum.Material.SmoothPlastic
	board.Parent = raiz

	local sg = Instance.new("SurfaceGui")
	sg.Name = "GUI"; sg.Face = Enum.NormalId.Front -- -Z (con CFrame.lookAt, mira hacia el centro/spawn)
	sg.CanvasSize = Vector2.new(grande and 500 or 400, grande and 560 or 470)
	sg.Parent = board

	-- fondo con degradado + barra de acento
	local bg = Instance.new("Frame"); bg.Size = UDim2.new(1, 0, 1, 0); bg.BackgroundColor3 = Color3.fromRGB(24, 22, 34); bg.BorderSizePixel = 0; bg.Parent = sg
	local grad = Instance.new("UIGradient"); grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(34, 31, 48), Color3.fromRGB(17, 15, 25)); grad.Parent = bg
	local acento = Instance.new("Frame"); acento.Size = UDim2.new(1, 0, 0, grande and 12 or 10); acento.BackgroundColor3 = cfg.color; acento.BorderSizePixel = 0; acento.Parent = bg

	local titulo = Instance.new("TextLabel")
	titulo.Size = UDim2.new(1, -24, 0, grande and 60 or 50); titulo.Position = UDim2.new(0, 12, 0, grande and 16 or 14)
	titulo.BackgroundTransparency = 1; titulo.Font = Enum.Font.GothamBlack; titulo.TextScaled = true
	titulo.TextXAlignment = Enum.TextXAlignment.Left; titulo.TextColor3 = cfg.color; titulo.Text = cfg.titulo
	titulo.TextStrokeTransparency = 0.6; titulo.Parent = bg

	-- podio de avatares (solo el central): 3 huecos que se rellenan en pintar()
	local podio = nil
	if grande then
		podio = Instance.new("Frame"); podio.Name = "Podio"; podio.BackgroundTransparency = 1
		podio.Position = UDim2.new(0, 12, 0, 82); podio.Size = UDim2.new(1, -24, 0, 130); podio.Parent = bg
	end

	local lista = Instance.new("Frame"); lista.Name = "Lista"; lista.BackgroundTransparency = 1
	lista.Position = UDim2.new(0, 12, 0, grande and 220 or 74); lista.Size = UDim2.new(1, -24, 1, grande and -232 or -86); lista.Parent = bg
	local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, grande and 5 or 4); layout.Parent = lista

	return { board = board, cfg = cfg, lista = lista, podio = podio, grande = grande }
end

-- ===== pintar un board con su top =====
local function pintar(entry)
	local top = Leaderboard.topDe(entry.cfg.key, 10)
	for _, c in ipairs(entry.lista:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
	if entry.podio then for _, c in ipairs(entry.podio:GetChildren()) do c:Destroy() end end

	if #top == 0 then
		local vacio = Instance.new("TextLabel")
		vacio.Size = UDim2.new(1, 0, 0, 40); vacio.BackgroundTransparency = 1; vacio.Font = Enum.Font.GothamMedium
		vacio.TextColor3 = Color3.fromRGB(150, 150, 165); vacio.TextScaled = true; vacio.Text = "No entries yet - be the first!"
		vacio.Parent = entry.lista
		return
	end

	-- PODIO (central): avatares de los 3 primeros
	if entry.podio then
		local ordenPodio = { 2, 1, 3 } -- plata-oro-bronce, oro al centro
		local anchoHueco = 1 / 3
		for pos, rank in ipairs(ordenPodio) do
			local e = top[rank]
			if e then
				local col = Instance.new("Frame"); col.BackgroundTransparency = 1
				col.Size = UDim2.new(anchoHueco, -8, 1, 0); col.Position = UDim2.new(anchoHueco * (pos - 1), 4, 0, 0); col.Parent = entry.podio
				local av = Instance.new("ImageLabel")
				local d = (rank == 1) and 84 or 66
				av.Size = UDim2.fromOffset(d, d); av.AnchorPoint = Vector2.new(0.5, 0); av.Position = UDim2.new(0.5, 0, 0, (rank == 1) and 0 or 14)
				av.BackgroundColor3 = Color3.fromRGB(30, 28, 42); av.Image = avatarDe(e.userId); av.Parent = col
				Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)
				local ring = Instance.new("UIStroke", av); ring.Color = MEDALLA[rank]; ring.Thickness = 3
				local nm = Instance.new("TextLabel")
				nm.Size = UDim2.new(1, 0, 0, 20); nm.Position = UDim2.new(0, 0, 0, (rank == 1) and 88 or 84); nm.BackgroundTransparency = 1
				nm.Font = Enum.Font.GothamBold; nm.TextScaled = true; nm.TextColor3 = MEDALLA[rank]; nm.Text = "#" .. rank .. " " .. nombreDe(e.userId)
				nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Parent = col
				local vl = Instance.new("TextLabel")
				vl.Size = UDim2.new(1, 0, 0, 18); vl.Position = UDim2.new(0, 0, 0, (rank == 1) and 108 or 104); vl.BackgroundTransparency = 1
				vl.Font = Enum.Font.GothamMedium; vl.TextScaled = true; vl.TextColor3 = Color3.fromRGB(220, 222, 232); vl.Text = entry.cfg.fmt(e.valor); vl.Parent = col
			end
		end
	end

	-- LISTA (los que no van en podio: si hay podio empieza en el 4, si no en el 1)
	local desde = entry.podio and 4 or 1
	for i = desde, #top do
		local e = top[i]
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, entry.grande and 34 or 30)
		row.BackgroundColor3 = (i <= 3) and MEDALLA[i]:Lerp(Color3.fromRGB(24, 22, 34), 0.72) or Color3.fromRGB(30, 28, 42)
		row.BackgroundTransparency = (i % 2 == 0) and 0.15 or 0.35; row.BorderSizePixel = 0; row.Parent = entry.lista
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
		local rk = Instance.new("TextLabel")
		rk.Size = UDim2.new(0, 44, 1, 0); rk.BackgroundTransparency = 1; rk.Font = Enum.Font.GothamBlack; rk.TextScaled = true
		rk.TextColor3 = (i <= 3) and MEDALLA[i] or Color3.fromRGB(150, 152, 168); rk.Text = "#" .. i; rk.Parent = row
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -170, 1, 0); nm.Position = UDim2.new(0, 50, 0, 0); nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold; nm.TextScaled = true; nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextColor3 = Color3.fromRGB(232, 232, 244); nm.Text = nombreDe(e.userId); nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Parent = row
		local vl = Instance.new("TextLabel")
		vl.Size = UDim2.new(0, 116, 1, 0); vl.AnchorPoint = Vector2.new(1, 0); vl.Position = UDim2.new(1, -10, 0, 0); vl.BackgroundTransparency = 1
		vl.Font = Enum.Font.GothamBold; vl.TextScaled = true; vl.TextXAlignment = Enum.TextXAlignment.Right
		vl.TextColor3 = entry.cfg.color; vl.Text = entry.cfg.fmt(e.valor); vl.Parent = row
	end
end

-- ===== montar el arco =====
local centro = Vector3.new(lobby.X, PISO + (27 / 2) + 2, lobby.Z) -- centro del arco a la altura media de los boards
local entries = {}
for i, cfg in ipairs(BOARDS) do
	local t = (#BOARDS == 1) and 0.5 or ((i - 1) / (#BOARDS - 1))
	local ang = math.rad(ANG_INI + t * (ANG_FIN - ANG_INI))
	local grande = cfg.grande == true
	local altoB = grande and 27 or 21
	local y = PISO + (altoB / 2) + 2
	local pos = Vector3.new(lobby.X + math.cos(ang) * RADIO, y, lobby.Z + math.sin(ang) * RADIO)
	local cf = CFrame.lookAt(pos, Vector3.new(centro.X, y, centro.Z)) -- la cara Front (-Z, con el GUI) mira al centro/spawn
	entries[#entries + 1] = construirBoard(cfg, cf, grande)
end

-- ===== refresco =====
task.spawn(function()
	while true do
		for _, entry in ipairs(entries) do
			pintar(entry)
			task.wait(0.15) -- escalona las lecturas de DataStore (no todas a la vez)
		end
		task.wait(45)
	end
end)
