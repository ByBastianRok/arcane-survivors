-- BossMarkerClient (LocalScript) · S1 - marca al JEFE en el borde de la pantalla cuando esta
-- FUERA de tu vista (con la camara cenital la horda se ve, pero el jefe puede quedar fuera).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "BossMarker"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 55
gui.Parent = playerGui

local marker = Instance.new("Frame")
marker.Name = "Marker"
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Size = UDim2.fromOffset(100, 30)
marker.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
marker.BackgroundTransparency = 0.1
marker.Visible = false
marker.Parent = gui
local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 8); mc.Parent = marker
local ms = Instance.new("UIStroke"); ms.Color = Color3.fromRGB(255, 180, 180); ms.Thickness = 2; ms.Parent = marker
local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromScale(1, 1)
lbl.BackgroundTransparency = 1
lbl.Font = Enum.Font.GothamBlack
lbl.TextScaled = true
lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
lbl.TextStrokeTransparency = 0.4
lbl.Text = "BOSS"
lbl.Parent = marker
local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6); pad.Parent = lbl

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local bossHealth = remotes:WaitForChild("BossHealth")
local bossRef = nil -- HumanoidRootPart del jefe actual (cacheado; nil = no hay jefe). Evita escanear cada frame.

local function buscarJefe()
	local carpeta = workspace:FindFirstChild("Enemies") -- todos los enemigos viven aqui (ver Enemy.luau)
	for _, m in ipairs(carpeta and carpeta:GetChildren() or {}) do
		if m.Name == "BrainrotEnemy" and m:GetAttribute("Boss") then
			local r = m:FindFirstChild("HumanoidRootPart")
			local h = m:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 then return r end
		end
	end
	return nil
end

-- El remote del jefe nos avisa de que hay uno vivo -> solo escaneamos UNA vez al aparecer (no cada frame).
bossHealth.OnClientEvent:Connect(function(info)
	if info and info.current and info.current > 0 then
		if not (bossRef and bossRef.Parent) then bossRef = buscarJefe() end
	else
		bossRef = nil
	end
end)

RunService.RenderStepped:Connect(function()
	local boss = bossRef
	if not (boss and boss.Parent) then
		if marker.Visible then marker.Visible = false end
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local sp, onScreen = cam:WorldToViewportPoint(boss.Position)
	local vp = cam.ViewportSize
	local margin = 50
	local dentro = onScreen and sp.X >= margin and sp.X <= vp.X - margin and sp.Y >= margin and sp.Y <= vp.Y - margin
	if dentro then
		if marker.Visible then marker.Visible = false end
		return
	end
	marker.Visible = true
	local center = vp / 2
	local dir = Vector2.new(sp.X, sp.Y) - center
	if sp.Z < 0 then dir = -dir end -- el jefe esta detras de la camara
	if dir.Magnitude < 1 then dir = Vector2.new(0, -1) end
	dir = dir.Unit
	local scale = math.min((center.X - margin) / math.max(math.abs(dir.X), 1e-4), (center.Y - margin) / math.max(math.abs(dir.Y), 1e-4))
	local pos = center + dir * scale
	marker.Position = UDim2.fromOffset(pos.X, pos.Y)
end)
