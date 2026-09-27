-- MonetizationServer (Script SERVIDOR) · S2 - Robux: ProcessReceipt (Gems) + propiedad de gamepasses.
-- Gamepasses -> atributo Pass_<nombre> en el jugador (lo lee el cliente para mostrar x3/autospin).
-- Developer products -> da Gems al comprar (idempotente via MetaStore.darGems).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MonetizationData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MonetizationData"))
local MetaStore = require(ServerScriptService:WaitForChild("MetaStore"))
local StoreData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("StoreData"))
local ReviveComprado = ServerScriptService:WaitForChild("ReviveComprado") -- Smn: avisa al GameManager que se pago un revive

-- ===== Gamepasses: comprobar propiedad y exponerla como atributo (Pass_<nombre>) =====
local function comprobarPases(player)
	for nombre, id in pairs(MonetizationData.Gamepasses) do
		if id == 0 then player:SetAttribute("Pass_" .. nombre, false) -- gamepass aun sin crear (ID 0)
		else
			task.spawn(function()
				local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id) end)
				player:SetAttribute("Pass_" .. nombre, ok and owns or false)
			end)
		end
	end
end
Players.PlayerAdded:Connect(comprobarPases)
for _, p in ipairs(Players:GetPlayers()) do comprobarPases(p) end

-- ===== VIP: etiqueta cosmetica sobre la cabeza (estatus). El visual bonito va en la fase de arte. =====
local function ponerTagVip(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end
	local viejo = head:FindFirstChild("VipTag")
	if not player:GetAttribute("Pass_vip") then if viejo then viejo:Destroy() end return end
	if viejo then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "VipTag"; bb.Size = UDim2.fromOffset(70, 22); bb.StudsOffset = Vector3.new(0, 2.7, 0); bb.AlwaysOnTop = true
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.Text = "VIP"
	lbl.Font = Enum.Font.GothamBlack; lbl.TextScaled = true; lbl.TextColor3 = Color3.fromRGB(255, 215, 70); lbl.TextStrokeTransparency = 0.3
	lbl.Parent = bb
	bb.Parent = head
end

local function engancharVip(player)
	player.CharacterAdded:Connect(function() task.wait(0.4); ponerTagVip(player) end)
	player:GetAttributeChangedSignal("Pass_vip"):Connect(function() ponerTagVip(player) end)
	if player.Character then task.spawn(function() task.wait(0.4); ponerTagVip(player) end) end
end
Players.PlayerAdded:Connect(engancharVip)
for _, p in ipairs(Players:GetPlayers()) do engancharVip(p) end

-- al comprar un pase en la sesion, refrescar el atributo al momento
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, comprado)
	if not comprado then return end
	for nombre, id in pairs(MonetizationData.Gamepasses) do
		if id == gamePassId then player:SetAttribute("Pass_" .. nombre, true) end
	end
end)

-- ===== Developer Products: dar Gems al comprar (ProcessReceipt) =====
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end -- reintenta cuando vuelva
	-- 0) Revive consumible (Extra Life: pagar al morir)?
	if receipt.ProductId == MonetizationData.ReviveProduct then
		-- IDEMPOTENTE (audit): dedup por PurchaseId para que un reintento del recibo NO doble-revuelva.
		local estado = MetaStore.marcarReciboEfecto(player, receipt.PurchaseId)
		if estado == "reintentar" then return Enum.ProductPurchaseDecision.NotProcessedYet end -- perfil no cargado
		if estado == "nuevo" then ReviveComprado:Fire(player) end -- solo la 1a vez: el GameManager revive / da credito
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- 1) Pack de la TIENDA (bundle de Gems/materiales/Cash)?
	local pack = StoreData.packPorProducto(receipt.ProductId)
	if pack then
		if MetaStore.darPack(player, pack, receipt.PurchaseId) then return Enum.ProductPurchaseDecision.PurchaseGranted end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- 2) Pack de Gems suelto?
	local gems = MonetizationData.GemsProducts[receipt.ProductId]
	if gems then
		if MetaStore.darGems(player, gems, receipt.PurchaseId) then return Enum.ProductPurchaseDecision.PurchaseGranted end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet -- producto desconocido
end
