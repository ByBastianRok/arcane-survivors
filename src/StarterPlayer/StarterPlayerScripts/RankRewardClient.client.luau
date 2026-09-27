-- RankRewardClient (LocalScript) - Sga - popup al ENTRAR si ganaste premio del ranking semanal.
-- El server (MetaStore.init) manda RankReward {rank, gems} cuando quedaste en el top la semana pasada.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rankReward = remotes:WaitForChild("RankReward")

rankReward.OnClientEvent:Connect(function(data)
	local gui = Instance.new("ScreenGui"); gui.Name = "RankRewardPopup"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 80; gui.Parent = playerGui
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0); card.Position = UDim2.new(0.5, 0, 0, -120); card.Size = UDim2.new(0, 360, 0, 96)
	card.BackgroundColor3 = Color3.fromRGB(28, 24, 40); card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local st = Instance.new("UIStroke", card); st.Color = Color3.fromRGB(245, 200, 90); st.Thickness = 2
	local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Position = UDim2.new(0, 0, 0, 12); t.Size = UDim2.new(1, 0, 0, 30)
	t.Font = Enum.Font.GothamBlack; t.TextColor3 = Color3.fromRGB(245, 210, 90); t.TextScaled = true; t.TextStrokeTransparency = 0.4
	t.Text = "WEEKLY RANK #" .. tostring(data.rank); t.Parent = card
	local s = Instance.new("TextLabel"); s.BackgroundTransparency = 1; s.Position = UDim2.new(0, 0, 0, 46); s.Size = UDim2.new(1, 0, 0, 36)
	s.Font = Enum.Font.GothamBold; s.TextColor3 = Color3.new(1, 1, 1); s.TextScaled = true; s.TextStrokeTransparency = 0.5
	local partes = {} -- desglose: Gems (podio) + Cash + materiales
	if (data.gems or 0) > 0 then partes[#partes + 1] = "+" .. data.gems .. " Gems" end
	if (data.cash or 0) > 0 then partes[#partes + 1] = "+" .. data.cash .. " Cash" end
	if (data.mats or 0) > 0 then partes[#partes + 1] = "+" .. data.mats .. " Rare" end
	s.Text = (#partes > 0) and table.concat(partes, "   ") or ("+" .. tostring(data.gems or 0) .. " Gems"); s.Parent = card
	TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 40) }):Play()
	task.delay(4.5, function()
		local tw = TweenService:Create(card, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0, -120) })
		tw:Play(); tw.Completed:Wait(); gui:Destroy()
	end)
end)
