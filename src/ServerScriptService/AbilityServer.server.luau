-- AbilityServer (Script SERVIDOR) · S2 - habilidades activas SERVER-AUTHORITATIVE.
-- El cliente pide UseAbility(id); el servidor valida el cooldown y aplica el efecto:
--   dash -> i-frames (invulnerable breve)   ·   nova -> dano en area (escala con la build)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local useAbility = remotes:WaitForChild("UseAbility")
local damageNumber = remotes:WaitForChild("DamageNumber")
local AbilityData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("AbilityData"))
local RunState = require(script.Parent:WaitForChild("RunState"))
local Combat = require(script.Parent:WaitForChild("Combat")) -- daño unificado

local cooldowns = {}

local function listo(player, id, cd)
	cooldowns[player] = cooldowns[player] or {}
	local last = cooldowns[player][id]
	if last and (os.clock() - last) < cd then return false end
	cooldowns[player][id] = os.clock()
	return true
end

local function flash(modelo)
	for _, p in ipairs(modelo:GetChildren()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("__col") == nil then p:SetAttribute("__col", p.Color) end
			p.Color = Color3.fromRGB(255, 255, 255)
		end
	end
	task.delay(0.06, function()
		for _, p in ipairs(modelo:GetChildren()) do
			if p:IsA("BasePart") and p:GetAttribute("__col") ~= nil then p.Color = p:GetAttribute("__col") end
		end
	end)
end

local function nova(player, hrp)
	local d = AbilityData.Nova
	local mods = RunState.get(player)
	local dano = d.danoBase * (mods.danoMult or 1) * (mods.buffDanoMult or 1)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder; ring.Material = Enum.Material.Neon; ring.Color = d.color
	ring.Transparency = 0.2; ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CastShadow = false
	ring.Size = Vector3.new(1, 4, 4)
	ring.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.4), { Size = Vector3.new(1, d.radio * 2, d.radio * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.5)
	local carpeta = workspace:FindFirstChild("Enemies") -- todos los enemigos viven aqui (ver Enemy.luau)
	for _, m in ipairs(carpeta and carpeta:GetChildren() or {}) do
		if m.Name == "BrainrotEnemy" then
			local r = m:FindFirstChild("HumanoidRootPart")
			local h = m:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 and (r.Position - hrp.Position).Magnitude <= d.radio then
				-- Pasar el JUGADOR (antes iba nil). Con nil, tras el cambio de damageNumber a FireClient la Nova
				-- se quedo SIN numeros de dano; ademas no sumaba al medidor de dano co-op ni marcaba
				-- ultimoAtacante, asi que sus kills se atribuian a otro y el Scholar del que la lanza no contaba.
				Combat.aplicarGolpe(player, m, dano, nil, nil, r.Position)
			end
		end
	end
end

useAbility.OnServerEvent:Connect(function(player, id)
	local pj = player.Character
	local hrp = pj and pj:FindFirstChild("HumanoidRootPart")
	local hum = pj and pj:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum and hum.Health > 0) then return end
	local cdMult = RunState.get(player).cdMult or 1 -- Adrenaline: reduce el cooldown de habilidades
	if id == "dash" then
		if not listo(player, "dash", AbilityData.Dash.cooldown * cdMult) then return end
		RunState.aplicarBuff(player, "invulnerable", true, AbilityData.Dash.iframes)
	elseif id == "nova" then
		if not listo(player, "nova", AbilityData.Nova.cooldown * cdMult) then return end
		nova(player, hrp)
	end
end)

Players.PlayerRemoving:Connect(function(player) cooldowns[player] = nil end)
