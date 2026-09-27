-- JuiceClient (LocalScript) · FASE 11 - traduce eventos "Juice" del servidor en feedback:
-- camera shake (escalado por distancia) + SFX. Tipos: explosion, bossSlam, hurt, enemyDeath, pickup.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CameraShake = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CameraShake"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))
local juice = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Juice")
local player = Players.LocalPlayer

-- intensidad / duracion del shake por tipo
local SHAKE = {
	explosion = { 0.75, 0.42 },
	bossSlam = { 1.3, 0.6 },
	hurt = { 0.5, 0.3 },
	shoot = { 0.08, 0.12 }, -- retroceso del auto-disparo
	melee = { 0.12, 0.14 }, -- golpe de espada
}
local SONIDOS = { explosion = true, enemyDeath = true, pickup = true, shoot = true, melee = true } -- kinds que tambien suenan

local function distFactor(pos)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and pos) then return 1 end
	return math.clamp(1 - (hrp.Position - pos).Magnitude / 80, 0, 1) -- a >80 studs, nada
end

juice.OnClientEvent:Connect(function(info)
	if not info or not info.kind then return end
	local sh = SHAKE[info.kind]
	if sh then
		local f = info.pos and distFactor(info.pos) or 1
		if f > 0 then CameraShake.shake(sh[1] * f, sh[2]) end
	end
	if SONIDOS[info.kind] then SoundManager.play(info.snd or info.kind, info.pos) end -- snd = sonido propio del arma
end)
