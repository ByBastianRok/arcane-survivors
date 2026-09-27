-- AbilityClient (LocalScript) · S2 - input + HUD de las habilidades activas (Dash + Nova).
-- Tecla (PC: Espacio/Q) o boton (movil/tap) -> pide UseAbility al servidor (valida cooldown + efecto).
-- El cliente PREDICE el cooldown (HUD) y hace el MOVIMIENTO del dash; el server da los i-frames + nova.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local AbilityData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("AbilityData"))
local RunService = game:GetService("RunService")
local useAbility = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UseAbility")
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))

local esMovil = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local gui = Instance.new("ScreenGui")
gui.Name = "AbilityHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 6; gui.Parent = playerGui

local cont = Instance.new("Frame")
cont.Size = UDim2.fromOffset(172, 80); cont.Position = UDim2.new(1, -24, 1, -24); cont.AnchorPoint = Vector2.new(1, 1)
cont.BackgroundTransparency = 1; cont.Parent = gui
local lay = Instance.new("UIListLayout")
lay.FillDirection = Enum.FillDirection.Horizontal; lay.Padding = UDim.new(0, 12); lay.HorizontalAlignment = Enum.HorizontalAlignment.Right; lay.Parent = cont

local cooldownLocal = {}
local botones = {}

local function hacerBoton(ab, hint)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(80, 80); b.BackgroundColor3 = ab.color; b.AutoButtonColor = true; b.Text = ""; b.Parent = cont
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(1, 0, 0, 22); nm.Position = UDim2.fromOffset(0, 16); nm.BackgroundTransparency = 1
	nm.Text = ab.nombre; nm.Font = Enum.Font.GothamBold; nm.TextSize = 16; nm.TextColor3 = Color3.fromRGB(255, 255, 255); nm.Parent = b
	local key = Instance.new("TextLabel")
	key.Size = UDim2.new(1, 0, 0, 16); key.Position = UDim2.fromOffset(0, 44); key.BackgroundTransparency = 1
	key.Text = hint; key.Font = Enum.Font.Gotham; key.TextSize = 12; key.TextColor3 = Color3.fromRGB(235, 235, 245); key.Parent = b
	local ov = Instance.new("Frame") -- cubre y "drena" durante el cooldown
	ov.Size = UDim2.fromScale(1, 0); ov.AnchorPoint = Vector2.new(0, 0); ov.BackgroundColor3 = Color3.fromRGB(0, 0, 0); ov.BackgroundTransparency = 0.45
	ov.BorderSizePixel = 0; ov.Parent = b
	Instance.new("UICorner", ov).CornerRadius = UDim.new(0, 14)
	botones[ab.id] = { btn = b, ov = ov }
end

local function usar(id)
	if player:GetAttribute("InMatch") ~= true then return end
	local ab = AbilityData.porId(id); if not ab then return end
	local cdMult = player:GetAttribute("AbilityCdMult") or 1 -- Adrenaline: -20% cooldown (antes el gate usaba el cooldown BASE y anulaba el talento entero)
	local last = cooldownLocal[id]
	if last and (os.clock() - last) < ab.cooldown * cdMult then return end -- en cooldown
	cooldownLocal[id] = os.clock()
	useAbility:FireServer(id)
	SoundManager.play(id) -- sfx (dash / nova)
	local ov = botones[id].ov -- HUD: cubre y baja a 0 en 'cooldown' segundos
	ov.Size = UDim2.fromScale(1, 1)
	TweenService:Create(ov, TweenInfo.new(ab.cooldown * cdMult, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) }):Play()
	if id == "dash" then -- movimiento SUAVE (boost de WalkSpeed; no tropieza). El server da los i-frames.
		local ch = player.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hrp and hum then
			local dir = hum.MoveDirection
			if dir.Magnitude < 0.1 then dir = hrp.CFrame.LookVector end
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude >= 0.1 then
				dir = dir.Unit
				local oldWS = hum.WalkSpeed
				hum.WalkSpeed = ab.distancia / ab.duracion
				local t0 = os.clock()
				local conn
				conn = RunService.Heartbeat:Connect(function()
					if (not hum.Parent) or os.clock() - t0 >= ab.duracion then
						if conn then conn:Disconnect(); conn = nil end
						if hum.Parent then hum.WalkSpeed = oldWS end
						return
					end
					hum:Move(dir, false)
				end)
			end
		end
	end
end

hacerBoton(AbilityData.Dash, esMovil and "TAP" or "[Space]")
hacerBoton(AbilityData.Nova, esMovil and "TAP" or "[Q]")
botones.dash.btn.Activated:Connect(function() usar("dash") end)
botones.nova.btn.Activated:Connect(function() usar("nova") end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == AbilityData.Dash.tecla then usar("dash")
	elseif input.KeyCode == AbilityData.Nova.tecla then usar("nova") end
end)

-- sin salto (survivors cenital; asi el Espacio es el Dash)
local function configChar(ch)
	local hum = ch:WaitForChild("Humanoid")
	hum.UseJumpPower = true; hum.JumpPower = 0
end
if player.Character then configChar(player.Character) end
player.CharacterAdded:Connect(configChar)

local function gate() cont.Visible = (player:GetAttribute("InMatch") == true) end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()
