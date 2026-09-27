-- WeaponClient (LocalScript) - cliente GENÉRICO de armas.
-- Solo APUNTA y avisa; el servidor decide el daño. Funciona con CUALQUIER arma cuyo
-- nombre esté en WeaponData. Semi = un tiro por clic; Automático = mientras mantengas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponData"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireWeapon = remotes:WaitForChild("FireWeapon")
local reloadEvent = remotes:WaitForChild("Reload")
local CameraShake = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CameraShake"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- En movil dispara el joystick de apuntado (MobileControlsClient), no el raton.
local esMovil = UserInputService.TouchEnabled and not UserInputService.MouseEnabled and not UserInputService.KeyboardEnabled

local sosteniendo = false
local ultimoEnvio = 0

-- Datos del arma equipada (o nil si no hay ninguna).
local function armaEquipada()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	return tool and WeaponData[tool.Name] or nil
end

-- (HIATUS) El disparo MANUAL esta desactivado: en survivors el fuego es AUTOMATICO (lo hace el servidor).
-- Se quito la funcion 'disparar' muerta (if true then return) y su Heartbeat permanente (corria
-- cada frame sin hacer nada). Si se reactiva el apuntado manual, va aqui detras de un flag de Config.

-- Tecla R: recargar el arma equipada.
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.R and armaEquipada() then
		reloadEvent:FireServer()
		SoundManager.play("reload")
	end
end)
