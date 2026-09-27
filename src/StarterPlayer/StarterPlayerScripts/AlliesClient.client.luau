-- AlliesClient (LocalScript) - Sco co-op: panel de estado de los ALIADOS (vida / caido / eligiendo carta).
-- Client-only: lee datos REPLICADOS (el Humanoid de cada aliado + su atributo Eligiendo). Solo aparece si
-- hay companeros en el server (en solo = oculto). Provisional de sitio (izquierda); estetica en Fase Sju.
local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "AlliesPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 30; gui.Enabled = false
gui.Parent = playerGui

local cont = Instance.new("Frame")
cont.AnchorPoint = Vector2.new(0, 0.5); cont.Position = UDim2.new(0, 12, 0.5, 20)
cont.Size = UDim2.new(0, 185, 0, 10); cont.BackgroundTransparency = 1; cont.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = cont

local filas = {} -- [player] = { frame, nm, barBg, fill, st }

-- === Medidor de dano (co-op): panel arriba-derecha con el % del dano de la run por jugador (atributo RunDamage) ===
local meterGui = Instance.new("ScreenGui")
meterGui.Name = "DamageMeter"; meterGui.ResetOnSpawn = false; meterGui.IgnoreGuiInset = true; meterGui.DisplayOrder = 30; meterGui.Enabled = false
meterGui.Parent = playerGui
local mCont = Instance.new("Frame")
mCont.AnchorPoint = Vector2.new(1, 0); mCont.Position = UDim2.new(1, -12, 0, 92); mCont.Size = UDim2.new(0, 195, 0, 46)
mCont.BackgroundColor3 = Color3.fromRGB(18, 18, 28); mCont.BackgroundTransparency = 0.2; mCont.Parent = meterGui
Instance.new("UICorner", mCont).CornerRadius = UDim.new(0, 8)
local mTitle = Instance.new("TextLabel")
mTitle.BackgroundTransparency = 1; mTitle.Position = UDim2.new(0, 10, 0, 5); mTitle.Size = UDim2.new(1, -16, 0, 15)
mTitle.Font = Enum.Font.GothamBlack; mTitle.TextSize = 12; mTitle.TextXAlignment = Enum.TextXAlignment.Left
mTitle.TextColor3 = Color3.fromRGB(255, 210, 120); mTitle.Text = "DAMAGE"; mTitle.Parent = mCont
local mList = Instance.new("Frame")
mList.BackgroundTransparency = 1; mList.Position = UDim2.new(0, 10, 0, 23); mList.Size = UDim2.new(1, -20, 1, -28); mList.Parent = mCont
local mLayout = Instance.new("UIListLayout"); mLayout.Padding = UDim.new(0, 3); mLayout.SortOrder = Enum.SortOrder.LayoutOrder; mLayout.Parent = mList
local mFilas = {} -- [player] = { frame, nm, pct, fill }

local function crearFilaMeter()
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 18); f.BackgroundColor3 = Color3.fromRGB(45, 45, 60); f.BorderSizePixel = 0
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(255, 170, 90); fill.BorderSizePixel = 0; fill.Parent = f
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
	local nm = Instance.new("TextLabel")
	nm.BackgroundTransparency = 1; nm.Position = UDim2.new(0, 6, 0, 0); nm.Size = UDim2.new(1, -44, 1, 0)
	nm.Font = Enum.Font.GothamBold; nm.TextSize = 11; nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.TextColor3 = Color3.new(1, 1, 1); nm.ZIndex = 2; nm.Parent = f
	local pct = Instance.new("TextLabel")
	pct.BackgroundTransparency = 1; pct.Position = UDim2.new(1, -40, 0, 0); pct.Size = UDim2.new(0, 38, 1, 0)
	pct.Font = Enum.Font.GothamBlack; pct.TextSize = 11; pct.TextXAlignment = Enum.TextXAlignment.Right
	pct.TextColor3 = Color3.new(1, 1, 1); pct.ZIndex = 2; pct.Parent = f
	return { frame = f, nm = nm, pct = pct, fill = fill }
end

local function crearFila()
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 42); f.BackgroundColor3 = Color3.fromRGB(22, 22, 32); f.BackgroundTransparency = 0.2
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
	local nm = Instance.new("TextLabel")
	nm.BackgroundTransparency = 1; nm.Position = UDim2.new(0, 8, 0, 4); nm.Size = UDim2.new(1, -12, 0, 15)
	nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.TextColor3 = Color3.fromRGB(235, 235, 250); nm.Parent = f
	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0, 8, 0, 24); barBg.Size = UDim2.new(1, -16, 0, 11)
	barBg.BackgroundColor3 = Color3.fromRGB(60, 22, 22); barBg.BorderSizePixel = 0; barBg.Parent = f
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(90, 220, 110); fill.BorderSizePixel = 0; fill.Parent = barBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)
	local st = Instance.new("TextLabel")
	st.BackgroundTransparency = 1; st.Position = UDim2.new(0, 8, 0, 23); st.Size = UDim2.new(1, -16, 0, 13)
	st.Font = Enum.Font.GothamBlack; st.TextSize = 11; st.Text = ""; st.Parent = f
	return { frame = f, nm = nm, barBg = barBg, fill = fill, st = st }
end

while true do
	task.wait(0.2)
	local inMatch = plr:GetAttribute("InMatch") == true -- FIX: los aliados solo se ven EN PARTIDA, no en el lobby (antes salian barras de vida en el lobby)
	local otros = {}
	for _, p in ipairs(Players:GetPlayers()) do if p ~= plr then otros[#otros + 1] = p end end
	gui.Enabled = inMatch and #otros > 0
	if inMatch and #otros > 0 then
		local vistos = {}
		for i, p in ipairs(otros) do
			vistos[p] = true
			local fila = filas[p]
			if not fila then fila = crearFila(); filas[p] = fila; fila.frame.Parent = cont end
			fila.frame.LayoutOrder = i
			fila.nm.Text = p.DisplayName
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local eligiendo = p:GetAttribute("Eligiendo") == true
			if hum and hum.Health > 0 then
				fila.barBg.Visible = not eligiendo
				fila.fill.Size = UDim2.new(math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1), 0, 1, 0)
				fila.st.Visible = eligiendo
				fila.st.Text = "CHOOSING..."; fila.st.TextColor3 = Color3.fromRGB(255, 225, 110)
			else
				fila.barBg.Visible = false
				fila.st.Visible = true; fila.st.Text = "DOWN"; fila.st.TextColor3 = Color3.fromRGB(255, 95, 95)
			end
		end
		for p, fila in pairs(filas) do
			if not vistos[p] then fila.frame:Destroy(); filas[p] = nil end
		end
		cont.Size = UDim2.new(0, 185, 0, #otros * 48)
	end
	-- medidor de dano: % de la run por jugador (todos, incluido tu)
	local total, datos = 0, {}
	for _, p in ipairs(Players:GetPlayers()) do local d = p:GetAttribute("RunDamage") or 0; datos[#datos + 1] = { p = p, d = d }; total += d end
	table.sort(datos, function(a, b) return a.d > b.d end)
	meterGui.Enabled = inMatch and (#datos > 1) and (total > 0)
	if meterGui.Enabled then
		local vm = {}
		for i, e in ipairs(datos) do
			vm[e.p] = true
			local fila = mFilas[e.p]
			if not fila then fila = crearFilaMeter(); mFilas[e.p] = fila; fila.frame.Parent = mList end
			fila.frame.LayoutOrder = i
			local pct = total > 0 and e.d / total or 0
			fila.nm.Text = e.p.DisplayName
			fila.pct.Text = string.format("%d%%", math.floor(pct * 100 + 0.5))
			fila.fill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
			fila.fill.BackgroundColor3 = (e.p == plr) and Color3.fromRGB(120, 210, 255) or Color3.fromRGB(255, 170, 90)
		end
		for p, fila in pairs(mFilas) do if not vm[p] then fila.frame:Destroy(); mFilas[p] = nil end end
		mCont.Size = UDim2.new(0, 195, 0, 26 + #datos * 21)
	end
end
