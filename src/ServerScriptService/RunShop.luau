-- RunShop (ModuleScript del SERVIDOR) · FASE 6 - tienda de RUN upgrades (temporal, con Coins).
-- Coins = moneda POR-PARTIDA (se gana matando, se reinicia cada run). Las run upgrades se
-- aplican a la build de ESTA partida (RunState) y se borran al empezar otra.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RunUpgradeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("RunUpgradeData"))
local RunState = require(ServerScriptService:WaitForChild("RunState"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local runShopSync = remotes:WaitForChild("RunShopSync")
local buyRunUpgrade = remotes:WaitForChild("BuyRunUpgrade")

local RunShop = {}
local compras = {} -- compras[player] = { id = nivel } (se reinicia cada partida)

local function getCoins(player)
	return player:FindFirstChild("Coins")
end

function RunShop.sync(player)
	runShopSync:FireClient(player, { upgrades = RunUpgradeData.infoDe(compras[player] or {}) })
end

-- Reinicia las run upgrades y los Coins (al empezar una partida).
function RunShop.reset(player)
	compras[player] = {}
	local coins = getCoins(player)
	if coins then coins.Value = 0 end
	RunShop.sync(player)
end

-- Da Coins (por matar) a todos los jugadores vivos.
function RunShop.darCoins(cantidad)
	for _, pl in ipairs(Players:GetPlayers()) do
		local coins = getCoins(pl)
		if coins then coins.Value += cantidad end
	end
end

buyRunUpgrade.OnServerEvent:Connect(function(player, id)
	local up = RunUpgradeData.porId(id)
	if not up then return end
	compras[player] = compras[player] or {}
	local lvl = compras[player][id] or 0
	if lvl >= up.maxLevel then return end
	local cost = RunUpgradeData.costDe(up, lvl)
	local coins = getCoins(player)
	if not coins or coins.Value < cost then return end
	coins.Value -= cost
	compras[player][id] = lvl + 1
	up.aplicar(RunState.get(player))    -- aplica un escalon a la build de la partida
	RunState.aplicarAlPersonaje(player) -- por si toco vida/velocidad
	RunState.sync(player)               -- refresca el panel RUN STATS
	RunShop.sync(player)                -- refresca niveles/coste del SHOP
end)

runShopSync.OnServerEvent:Connect(function(player) RunShop.sync(player) end)

Players.PlayerRemoving:Connect(function(player) compras[player] = nil end)

return RunShop
