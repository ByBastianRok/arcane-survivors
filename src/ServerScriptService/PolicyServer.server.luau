-- PolicyServer (Script SERVIDOR) - CUMPLIMIENTO Roblox "paid random items" (el GACHA).
-- Para ciertos jugadores (menores / regiones reguladas tipo BE/NL) Roblox pone
-- ArePaidRandomItemsRestricted = true: NO se les puede vender/ofrecer items aleatorios de pago.
-- Guardamos ese estado en el atributo del jugador "PaidRandomRestricted"; el gacha (spin, MetaStore)
-- y el "Buy Gems" (GachaClient) lo respetan (bloquear/ocultar).
-- DEFAULT = restringido (true) HASTA comprobar -> nunca ofrecer random pagado antes de saberlo (anti-ban).
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local function comprobar(player)
	player:SetAttribute("PaidRandomRestricted", true) -- default SEGURO: restringido hasta saber de verdad
	task.spawn(function()
		local restricted = true
		for intento = 1, 3 do
			local ok, info = pcall(function() return PolicyService:GetPolicyInfoForPlayerAsync(player) end)
			if ok and type(info) == "table" then
				restricted = info.ArePaidRandomItemsRestricted and true or false
				break
			end
			warn("[Policy] GetPolicyInfoForPlayerAsync fallo (intento " .. intento .. "):", info)
			task.wait(1)
		end
		if player.Parent then player:SetAttribute("PaidRandomRestricted", restricted) end
	end)
end

Players.PlayerAdded:Connect(comprobar)
for _, p in ipairs(Players:GetPlayers()) do comprobar(p) end
