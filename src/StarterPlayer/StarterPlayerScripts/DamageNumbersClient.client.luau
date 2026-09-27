-- DamageNumbersClient (LocalScript) · FASE 8 - numeros de dano flotantes sobre los enemigos.
-- El servidor (WeaponServer) avisa de cada golpe; aqui se pinta un numero que sube y se desvanece.
-- Critico = mas grande, dorado y con "!". Es local (cada cliente pinta los suyos).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local player = game:GetService("Players").LocalPlayer

local damageNumber = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageNumber")

damageNumber.OnClientEvent:Connect(function(info)
	if player:GetAttribute("SettingDamageNumbers") == false then return end -- ajuste
	if not info or not info.pos or not info.amount then return end
	local crit = info.crit == true

	local part = Instance.new("Part")
	part.Anchored = true; part.CanCollide = false; part.CanQuery = false
	part.Transparency = 1; part.Size = Vector3.new(0.2, 0.2, 0.2)
	-- pequeno desvio aleatorio para que no se solapen al pegar varios
	part.Position = info.pos + Vector3.new((math.random() - 0.5) * 2, 1, (math.random() - 0.5) * 2)
	part.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, crit and 100 or 64, 0, crit and 44 or 30)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
	lbl.Font = crit and Enum.Font.GothamBlack or Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = crit and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = crit and (tostring(info.amount) .. "!") or tostring(info.amount)
	lbl.Parent = bb

	-- subir + desvanecer
	TweenService:Create(bb, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 3.2, 0) }):Play()
	TweenService:Create(lbl, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(part, 0.75)
end)
