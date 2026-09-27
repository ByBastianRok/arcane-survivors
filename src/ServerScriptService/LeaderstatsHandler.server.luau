-- LeaderstatsHandler  (Script del SERVIDOR)
-- Crea las "stats" de cada jugador. El dinero lo maneja SOLO el servidor.
-- Roblox muestra automaticamente cualquier carpeta llamada "leaderstats"
-- en el ranking de arriba a la derecha.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local DINERO_INICIAL = Config.DineroInicial -- con cuanto dinero empieza un jugador nuevo

-- Esta funcion se ejecuta cada vez que ENTRA un jugador al juego.
local function onPlayerAdded(player)
	-- 1) Carpeta "leaderstats" dentro del jugador.
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- 2) El valor "Cash" (dinero blando, PERSISTE). IntValue = numero entero.
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = DINERO_INICIAL
	cash.Parent = leaderstats

	-- 3) "Gems": moneda DURA (gancho de monetizacion, Fase 9). Empieza a 0.
	local gems = Instance.new("IntValue")
	gems.Name = "Gems"
	gems.Value = 0
	gems.Parent = leaderstats

	-- 4) "Coins": moneda POR-PARTIDA (Fase 6). Se gana matando y se REINICIA cada partida.
	--    Fuera de leaderstats (no ensucia el leaderboard); la lee el SHOP de run upgrades.
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = player
end

-- Conectamos la funcion al evento PlayerAdded.
Players.PlayerAdded:Connect(onPlayerAdded)
