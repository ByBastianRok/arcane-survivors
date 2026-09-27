-- ReviveClient (LocalScript) · Smn - al MORIR en una run, ofrece revivir PAGANDO (consumible).
-- El server manda ReviveOffer; esto muestra "YOU DIED / REVIVE (R$X) / GIVE UP" + cuenta atras.
-- REVIVE -> PromptProductPurchase del producto de revive; el grant lo hace el server (ProcessReceipt).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local reviveOffer = remotes:WaitForChild("ReviveOffer")
local reviveDecision = remotes:WaitForChild("ReviveDecision")
local MonetizationData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MonetizationData"))
local REVIVE_ID = MonetizationData.ReviveProduct
local REVIVE_PRECIO = MonetizationData.RevivePrecio or 99

local gui = Instance.new("ScreenGui")
gui.Name = "ReviveOfferGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 75
gui.Parent = player:WaitForChild("PlayerGui")

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0); dim.BackgroundTransparency = 0.35
dim.Visible = false; dim.Active = true; dim.Parent = gui -- Active (audit): el velo absorbe el toque, no atraviesa a STATS/SHOP de detras

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(420, 312); panel.Position = UDim2.new(0.5, -210, 0.5, -156)
panel.BackgroundColor3 = Color3.fromRGB(28, 26, 36); panel.Parent = dim
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, 0, 0, 56); titulo.Position = UDim2.fromOffset(0, 20); titulo.BackgroundTransparency = 1
titulo.Text = "YOU DIED"; titulo.Font = Enum.Font.GothamBlack; titulo.TextSize = 40; titulo.TextColor3 = Color3.fromRGB(255, 75, 75); titulo.Parent = panel

local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(1, -40, 0, 30); sub.Position = UDim2.fromOffset(20, 80); sub.BackgroundTransparency = 1
sub.Text = "Revive and continue your run?"; sub.Font = Enum.Font.Gotham; sub.TextSize = 17; sub.TextColor3 = Color3.fromRGB(225, 225, 235); sub.Parent = panel

local cuenta = Instance.new("TextLabel")
cuenta.Size = UDim2.new(1, 0, 0, 26); cuenta.Position = UDim2.fromOffset(0, 116); cuenta.BackgroundTransparency = 1
cuenta.Font = Enum.Font.GothamBold; cuenta.TextSize = 18; cuenta.TextColor3 = Color3.fromRGB(255, 210, 90); cuenta.Parent = panel

local revivir = Instance.new("TextButton")
revivir.Size = UDim2.fromOffset(360, 60); revivir.Position = UDim2.new(0.5, -180, 0, 158)
revivir.BackgroundColor3 = Color3.fromRGB(70, 175, 75); revivir.Font = Enum.Font.GothamBold; revivir.TextSize = 22; revivir.TextColor3 = Color3.new(1, 1, 1)
revivir.Text = "REVIVE  (R$ " .. REVIVE_PRECIO .. ")"; revivir.Parent = panel
Instance.new("UICorner", revivir).CornerRadius = UDim.new(0, 10)

local rendirse = Instance.new("TextButton")
rendirse.Size = UDim2.fromOffset(360, 42); rendirse.Position = UDim2.new(0.5, -180, 0, 228)
rendirse.BackgroundColor3 = Color3.fromRGB(70, 70, 85); rendirse.Font = Enum.Font.GothamBold; rendirse.TextSize = 16; rendirse.TextColor3 = Color3.fromRGB(220, 220, 230)
rendirse.Text = "GIVE UP"; rendirse.Parent = panel
Instance.new("UICorner", rendirse).CornerRadius = UDim.new(0, 8)

local abierto = false
local comprando = false
local sesion = 0 -- invalida cuentas atras viejas

local function cerrar()
	abierto = false
	comprando = false
	sesion += 1
	dim.Visible = false
end

revivir.MouseButton1Click:Connect(function()
	if not abierto or comprando then return end
	if not REVIVE_ID or REVIVE_ID == 0 then warn("[Revive] falta MonetizationData.ReviveProduct"); return end
	comprando = true
	cuenta.Text = "Waiting for purchase..."
	reviveDecision:FireServer("buy")
	MarketplaceService:PromptProductPurchase(player, REVIVE_ID)
end)

rendirse.MouseButton1Click:Connect(function()
	if not abierto then return end
	reviveDecision:FireServer("giveup")
	cerrar()
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(_uid, productId, comprado)
	if productId ~= REVIVE_ID then return end
	if comprado then
		cuenta.Text = "Reviving..." -- el server revive y cierra via ReviveOffer {close}
	else
		comprando = false
		reviveDecision:FireServer("cancel") -- cancelo el popup; el server cierra por timeout
	end
end)

reviveOffer.OnClientEvent:Connect(function(data)
	if data.close then cerrar(); return end
	abierto = true
	comprando = false
	sesion += 1
	local miSesion = sesion
	dim.Visible = true
	revivir.Text = "REVIVE  (R$ " .. REVIVE_PRECIO .. ")"
	local restante = data.segundos or 10
	task.spawn(function()
		while abierto and miSesion == sesion and restante > 0 do
			if not comprando then cuenta.Text = "Run ends in " .. restante .. "s" end
			task.wait(1)
			restante -= 1
		end
		if abierto and miSesion == sesion and restante <= 0 and not comprando then
			reviveDecision:FireServer("giveup")
			cerrar()
		end
	end)
end)
