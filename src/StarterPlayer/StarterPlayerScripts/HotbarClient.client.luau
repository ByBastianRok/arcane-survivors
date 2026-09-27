-- HotbarClient (LocalScript) · FASE 8 - hotbar/inventario PROPIO de armas (no el de Roblox).
-- Oculta la mochila por defecto y pinta una barra inferior con un slot por arma: numero +
-- nombre, la EQUIPADA resaltada y con su municion + barra de cargador/recarga. Se equipa con
-- clic o con las teclas numericas. Solo visible en partida.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Quitar la hotbar/mochila POR DEFECTO de Roblox (puede no estar lista al instante: reintenta).
task.spawn(function()
	for _ = 1, 15 do
		local ok = pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
		if ok then break end
		task.wait(0.3)
	end
end)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local ammoUpdate = remotes:WaitForChild("AmmoUpdate")

local gui = Instance.new("ScreenGui")
gui.Name = "Hotbar"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Contenedor (abajo centro). El layout horizontal centra los slots y ajusta el ancho.
local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.Size = UDim2.new(0, 100, 0, 64)
bar.BackgroundTransparency = 1
bar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	bar.Size = UDim2.new(0, layout.AbsoluteContentSize.X, 0, 64)
end)

local SLOT_W, SLOT_H = 78, 64
local slots = {}        -- slots[tool] = TextButton
local ammoInfo = {}     -- ultimo AmmoUpdate recibido
local reloadTween

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

-- Tools del Backpack + la equipada (en el Character), orden estable por nombre.
local function toolsOrdenadas()
	local lista = {}
	local bp = player:FindFirstChild("Backpack")
	if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then lista[#lista + 1] = t end end end
	local char = player.Character
	if char then for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then lista[#lista + 1] = t end end end
	table.sort(lista, function(a, b) return a.Name < b.Name end)
	return lista
end

local function equipada()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Tool")
end

local function equipar(tool)
	local hum = getHumanoid()
	if not hum or not tool then return end
	if tool.Parent ~= player.Character then
		hum:EquipTool(tool) -- solo equipar; NO desequipar al reclicar (no puedes quedarte sin arma)
	end
end

-- Pinta la municion/recarga SOLO en el slot equipado.
local function pintarAmmo()
	local eq = equipada()
	for tool, slot in pairs(slots) do
		local ammoLbl = slot:FindFirstChild("Ammo")
		local barBg = slot:FindFirstChild("BarBg")
		local fill = barBg and barBg:FindFirstChild("Fill")
		if tool == eq and ammoInfo.weapon then
			barBg.Visible = true
			if ammoInfo.reloading then
				ammoLbl.Text = "RELOAD"
				ammoLbl.TextColor3 = Color3.fromRGB(255, 200, 80)
				if reloadTween then reloadTween:Cancel() end
				fill.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
				fill.Size = UDim2.fromScale(0, 1)
				reloadTween = TweenService:Create(fill, TweenInfo.new(ammoInfo.reloadTime or 1, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
				reloadTween:Play()
			else
				if reloadTween then reloadTween:Cancel(); reloadTween = nil end
				ammoLbl.Text = ammoInfo.current .. " / " .. ammoInfo.max
				ammoLbl.TextColor3 = (ammoInfo.current == 0) and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 230, 150)
				local frac = (ammoInfo.max > 0) and math.clamp(ammoInfo.current / ammoInfo.max, 0, 1) or 0
				fill.Size = UDim2.fromScale(frac, 1)
				fill.BackgroundColor3 = (ammoInfo.current <= ammoInfo.max * 0.25) and Color3.fromRGB(255, 140, 80) or Color3.fromRGB(120, 200, 255)
			end
		else
			ammoLbl.Text = ""
			if barBg then barBg.Visible = false end
		end
	end
end

-- (Re)construye todos los slots (al coger/soltar/equipar un arma).
local function rebuild()
	for _, f in pairs(slots) do f:Destroy() end
	slots = {}
	local eq = equipada()
	for i, tool in ipairs(toolsOrdenadas()) do
		local slot = Instance.new("TextButton")
		slot.Name = "Slot_" .. tool.Name
		slot.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
		slot.AutoButtonColor = false
		slot.Text = ""
		slot.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
		slot.BackgroundTransparency = 0.2
		slot.LayoutOrder = i
		slot.Parent = bar
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = slot
		local st = Instance.new("UIStroke"); st.Thickness = 2; st.Parent = slot

		local num = Instance.new("TextLabel")
		num.Size = UDim2.fromOffset(14, 14)
		num.Position = UDim2.fromOffset(5, 3)
		num.BackgroundTransparency = 1
		num.Font = Enum.Font.GothamBlack
		num.TextScaled = true
		num.TextXAlignment = Enum.TextXAlignment.Left
		num.TextColor3 = Color3.fromRGB(170, 180, 200)
		num.Text = tostring(i)
		num.Parent = slot

		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -8, 0, 15)
		nm.Position = UDim2.new(0, 4, 0, 18)
		nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBold
		nm.TextScaled = true
		nm.TextColor3 = Color3.fromRGB(255, 255, 255)
		nm.Text = string.upper(tool.Name)
		nm.Parent = slot

		local ammoLbl = Instance.new("TextLabel")
		ammoLbl.Name = "Ammo"
		ammoLbl.Size = UDim2.new(1, -8, 0, 13)
		ammoLbl.Position = UDim2.new(0, 4, 0, 34)
		ammoLbl.BackgroundTransparency = 1
		ammoLbl.Font = Enum.Font.GothamBold
		ammoLbl.TextScaled = true
		ammoLbl.TextColor3 = Color3.fromRGB(255, 230, 150)
		ammoLbl.Text = ""
		ammoLbl.Parent = slot

		local barBg = Instance.new("Frame")
		barBg.Name = "BarBg"
		barBg.Size = UDim2.new(1, -10, 0, 6)
		barBg.Position = UDim2.new(0, 5, 1, -9)
		barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
		barBg.BorderSizePixel = 0
		barBg.Visible = false
		barBg.Parent = slot
		local bgc = Instance.new("UICorner"); bgc.CornerRadius = UDim.new(0, 3); bgc.Parent = barBg
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
		fill.BorderSizePixel = 0
		fill.Parent = barBg
		local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 3); fc.Parent = fill

		if tool == eq then
			st.Color = Color3.fromRGB(120, 200, 255); st.Transparency = 0
			slot.BackgroundColor3 = Color3.fromRGB(30, 38, 52); slot.BackgroundTransparency = 0.05
		else
			st.Color = Color3.fromRGB(70, 80, 100); st.Transparency = 0.4
		end

		slot.MouseButton1Click:Connect(function() equipar(tool) end)
		slots[tool] = slot
	end
	pintarAmmo()
end

ammoUpdate.OnClientEvent:Connect(function(info)
	ammoInfo = info or {}
	pintarAmmo()
end)

-- Reconstruir cuando cambian las armas (coger / equipar / guardar).
local function hookBackpack()
	local bp = player:WaitForChild("Backpack")
	bp.ChildAdded:Connect(rebuild)
	bp.ChildRemoved:Connect(rebuild)
end
-- Auto-equipar la primera arma al spawnear si no hay ninguna equipada (UX, sobre todo en movil).
local function autoEquip()
	task.spawn(function()
		for _ = 1, 25 do
			if equipada() then return end
			local primera = toolsOrdenadas()[1]
			if primera then equipar(primera); return end
			task.wait(0.2)
		end
	end)
end

player.CharacterAdded:Connect(function(char)
	char.ChildAdded:Connect(function(c) if c:IsA("Tool") then rebuild() end end)
	char.ChildRemoved:Connect(function(c) if c:IsA("Tool") then rebuild() end end)
	task.wait(0.2)
	rebuild()
	autoEquip()
end)
task.spawn(hookBackpack)
rebuild()
autoEquip()

-- Teclas 1..9 para equipar el slot correspondiente.
UserInputService.InputBegan:Connect(function(inp, gpe)
	if gpe then return end
	local kc = inp.KeyCode.Value
	if kc >= Enum.KeyCode.One.Value and kc <= Enum.KeyCode.Nine.Value then
		local tool = toolsOrdenadas()[kc - Enum.KeyCode.One.Value + 1]
		if tool then equipar(tool) end
	end
end)

-- Solo visible en partida (en el lobby no hay armas/combate).
local function gate()
	gui.Enabled = player:GetAttribute("InMatch") == true
end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()
