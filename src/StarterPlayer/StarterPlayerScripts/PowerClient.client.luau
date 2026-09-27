-- PowerClient (LocalScript) · FASE 5A - pantalla "elige 1 de 3" del roguelite.
-- El servidor manda 3 cartas; el jugador hace clic en una; avisamos al servidor.
-- Solo PINTA y reporta la eleccion; el EFECTO lo aplica el servidor (RunState).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local tono = UITheme.tono

-- Sju (juice de cartas): sonido SEGUN rareza + entrada animada + destello en las gordas. Elegir mejora es EL
-- momento de dopamina del juego; antes las cartas se plantaban de golpe y en silencio.
local RANGO = { COMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4, MYTHIC = 5, EVOLUTION = 6 }
local SONIDO = { [1] = "cardCommon", [2] = "cardRare", [3] = "cardEpic", [4] = "cardLegend", [5] = "cardLegend", [6] = "cardLegend" }
local function rangoDe(c)
	if c.evo then return RANGO.EVOLUTION end
	return RANGO[string.upper(c.rareza or "")] or 1
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local offerPowers = remotes:WaitForChild("OfferPowers")
local pickPower = remotes:WaitForChild("PickPower")

local gui = Instance.new("ScreenGui")
gui.Name = "PowerSelect"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50 -- por encima del HUD
gui.Enabled = false
gui.Parent = playerGui

-- Fondo oscuro semitransparente.
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.Active = true -- absorbe el toque (audit): sin esto, tocar el hueco entre cartas atraviesa y mueve al personaje
overlay.Parent = gui

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(0, 760, 0, 60)
titulo.AnchorPoint = Vector2.new(0.5, 0)
titulo.Position = UDim2.new(0.5, 0, 0.12, 0)
titulo.BackgroundTransparency = 1
titulo.Font = Enum.Font.GothamBlack
titulo.TextScaled = true
titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
titulo.TextStrokeTransparency = 0.3
titulo.Text = "LEVEL UP — Choose a Power"
titulo.Parent = overlay

-- Fila contenedora de las 3 cartas (centrada).
local fila = Instance.new("Frame")
fila.Size = UDim2.new(0, 810, 0, 360)
fila.AnchorPoint = Vector2.new(0.5, 0.5)
fila.Position = UDim2.new(0.5, 0, 0.52, 0)
fila.BackgroundTransparency = 1
fila.Parent = overlay
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 24)
layout.Parent = fila

local abierto = false

-- I (co-op): aviso "GAME PAUSED - waiting for teammates" cuando el mundo esta CONGELADO (alguien subio de nivel)
-- pero YO ya elegi mi carta (o no tengo oferta). Sin esto la pantalla se quedaba quieta y sin explicacion
-- mientras el compañero elegia. XP compartida -> todos suben a la vez, pero uno puede tardar mas en elegir.
local esperaGui = Instance.new("ScreenGui")
esperaGui.Name = "PowerWaiting"; esperaGui.ResetOnSpawn = false; esperaGui.IgnoreGuiInset = true
esperaGui.DisplayOrder = 49; esperaGui.Enabled = false; esperaGui.Parent = playerGui
do
	local ov = Instance.new("Frame")
	ov.Size = UDim2.new(1, 0, 1, 0); ov.BackgroundColor3 = Color3.fromRGB(0, 0, 0); ov.BackgroundTransparency = 0.45
	ov.Active = true; ov.Parent = esperaGui
	local t1 = Instance.new("TextLabel")
	t1.AnchorPoint = Vector2.new(0.5, 0.5); t1.Position = UDim2.new(0.5, 0, 0.44, 0); t1.Size = UDim2.new(0, 560, 0, 58)
	t1.BackgroundTransparency = 1; t1.Font = Enum.Font.GothamBlack; t1.TextScaled = true
	t1.TextColor3 = Color3.fromRGB(255, 255, 255); t1.TextStrokeTransparency = 0.3; t1.Text = "GAME PAUSED"; t1.Parent = ov
	local t2 = Instance.new("TextLabel")
	t2.AnchorPoint = Vector2.new(0.5, 0.5); t2.Position = UDim2.new(0.5, 0, 0.53, 0); t2.Size = UDim2.new(0, 560, 0, 30)
	t2.BackgroundTransparency = 1; t2.Font = Enum.Font.GothamBold; t2.TextSize = 20
	t2.TextColor3 = Color3.fromRGB(205, 205, 215); t2.Text = "Waiting for teammates to choose..."; t2.Parent = ov
end
local esperaToken = 0
local function actualizarEspera()
	esperaToken += 1
	local mio = esperaToken
	-- debounce 0.35s: si soy el ULTIMO en elegir, Congelado pasa a false casi al instante -> el aviso no parpadea
	task.delay(0.35, function()
		if esperaToken ~= mio then return end
		esperaGui.Enabled = (workspace:GetAttribute("Congelado") == true) and not abierto
	end)
end
workspace:GetAttributeChangedSignal("Congelado"):Connect(actualizarEspera)

local function limpiarCartas()
	for _, hijo in ipairs(fila:GetChildren()) do
		if hijo:IsA("TextButton") then hijo:Destroy() end
	end
end

local function cerrar()
	abierto = false
	gui.Enabled = false
	player:SetAttribute("ChoosingPower", false) -- vuelve a permitir disparar
	limpiarCartas()
	actualizarEspera() -- I (co-op): si el mundo sigue congelado esperando a un compañero, muestra el aviso
end

local function elegir(id, card)
	if not abierto then return end
	abierto = false -- evita doble-pick mientras corre la animacion
	pickPower:FireServer(id) -- avisa YA; el servidor confirma y aplica
	SoundManager.play("cardPick") -- sonido de confirmacion (feedback de Bastian: al elegir no sonaba nada)

	-- FX de confirmacion: la elegida PULSA + destella, las otras se apagan. Antes la eleccion se cerraba
	-- de golpe y sin feedback; ahora se NOTA que el poder se ha absorbido.
	for _, hijo in ipairs(fila:GetChildren()) do
		if hijo:IsA("TextButton") then
			local sc = hijo:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			sc.Parent = hijo
			if hijo == card then
				TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
				local fl = Instance.new("Frame")
				fl.Size = UDim2.new(1, 0, 1, 0); fl.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				fl.BackgroundTransparency = 0.15; fl.BorderSizePixel = 0; fl.ZIndex = 30; fl.Parent = hijo
				Instance.new("UICorner", fl).CornerRadius = UDim.new(0, 14)
				TweenService:Create(fl, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			else
				TweenService:Create(sc, TweenInfo.new(0.18), { Scale = 0.82 }):Play()
				TweenService:Create(hijo, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
			end
		end
	end
	task.delay(0.22, cerrar) -- cierra tras el fx
end

-- Icono por TIPO de poder (por palabra clave; si no, por categoria). Da variedad visual a las cartas.
local function iconoDe(info)
	local t = string.lower((info.nombre or "") .. " " .. (info.desc or ""))
	if t:find("crit") or t:find("fire rate") or t:find("attack speed") or t:find("haste") or t:find("rapid") or t:find("speed") or t:find("swift") or t:find("move") then return "rayo"
	elseif t:find("health") or t:find("vital") or t:find("regen") or t:find("heal") or t:find("lifesteal") or t:find("vampir") or t:find("leech") or t:find("blood") then return "corazon"
	elseif t:find("dodge") or t:find("evasion") or t:find("armor") or t:find("skin") or t:find("shield") or t:find("guard") or t:find("tough") or t:find("stone") then return "escudo"
	elseif t:find("luck") or t:find("greed") or t:find("fortune") or t:find("cash") or t:find("gold") or t:find("scholar") or t:find("xp") then return "estrella"
	elseif t:find("damage") or t:find("brutal") or t:find("power") or t:find("berserk") or t:find("execute") or t:find("pierc") or t:find("range") or t:find("longshot") then return "espada"
	end
	local cat = string.lower(info.categoria or "")
	if cat == "defensive" then return "escudo" elseif cat == "utility" then return "estrella" end
	return "espada"
end

local function crearCarta(info, indice)
	local esEvo = info.evo == true
	local col = esEvo and Color3.fromRGB(255, 200, 80) or (info.color or Color3.fromRGB(200, 200, 200))
	local card = Instance.new("TextButton")
	card.Name = info.id
	card.Size = UDim2.new(0, 240, 0, 342)
	card.BackgroundColor3 = tono(col, -0.55)
	card.AutoButtonColor = false
	card.BorderSizePixel = 0
	card.Text = ""
	card.Parent = fila
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	-- fondo TINTADO por rareza (degradado) = cada carta "siente" su rareza, no un negro plano
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(tono(col, -0.32), Color3.fromRGB(15, 14, 19)); grad.Rotation = 90; grad.Parent = card
	-- glow exterior de rareza (detras)
	local glow = Instance.new("Frame")
	glow.Size = UDim2.new(1, 20, 1, 20); glow.Position = UDim2.new(0, -10, 0, -10); glow.ZIndex = 0
	glow.BackgroundColor3 = col; glow.BackgroundTransparency = 0.8; glow.BorderSizePixel = 0; glow.Parent = card
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 22)
	-- borde que brilla (gradiente en el stroke)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = esEvo and 4 or 3; stroke.Color = col; stroke.Parent = card
	local sg = Instance.new("UIGradient"); sg.Color = ColorSequence.new(tono(col, 0.65), tono(col, -0.25)); sg.Rotation = 90; sg.Parent = stroke
	if esEvo then
		TweenService:Create(stroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.4 }):Play()
	end
	-- RIBBON de rareza (pastilla arriba)
	local rib = Instance.new("Frame")
	rib.Size = UDim2.new(0, 132, 0, 24); rib.Position = UDim2.new(0.5, 0, 0, 14); rib.AnchorPoint = Vector2.new(0.5, 0)
	rib.BackgroundColor3 = col; rib.BorderSizePixel = 0; rib.Parent = card
	Instance.new("UICorner", rib).CornerRadius = UDim.new(1, 0)
	local ribT = Instance.new("TextLabel")
	ribT.Size = UDim2.new(1, 0, 1, 0); ribT.BackgroundTransparency = 1; ribT.Font = Enum.Font.GothamBlack; ribT.TextSize = 13
	ribT.TextColor3 = tono(col, -0.8); ribT.Text = esEvo and "EVOLUTION" or string.upper(info.rareza or ""); ribT.Parent = rib
	-- BADGE del icono (circulo con halo + anillo)
	local badge = Instance.new("Frame")
	badge.Size = UDim2.new(0, 78, 0, 78); badge.Position = UDim2.new(0.5, 0, 0, 48); badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.BackgroundColor3 = tono(col, -0.4); badge.BorderSizePixel = 0; badge.Parent = card
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	local bglow = Instance.new("Frame"); bglow.Size = UDim2.new(0, 60, 0, 60); bglow.Position = UDim2.new(0.5, 0, 0.5, 0); bglow.AnchorPoint = Vector2.new(0.5, 0.5)
	bglow.BackgroundColor3 = col; bglow.BackgroundTransparency = 0.55; bglow.BorderSizePixel = 0; bglow.Parent = badge
	Instance.new("UICorner", bglow).CornerRadius = UDim.new(1, 0)
	local bst = Instance.new("UIStroke"); bst.Color = col; bst.Thickness = 3; bst.Transparency = 0.05; bst.Parent = badge
	UITheme.icono(badge, iconoDe(info), Color3.new(1, 1, 1), { lado = 46, pos = UDim2.new(0.5, 0, 0.5, 0), anchor = Vector2.new(0.5, 0.5) })
	-- NOMBRE
	local nombre = Instance.new("TextLabel")
	nombre.Size = UDim2.new(1, -16, 0, 26); nombre.Position = UDim2.new(0, 8, 0, 140); nombre.BackgroundTransparency = 1
	nombre.Font = Enum.Font.GothamBlack; nombre.TextSize = 21; nombre.TextColor3 = Color3.new(1, 1, 1)
	nombre.TextTruncate = Enum.TextTruncate.AtEnd; nombre.Text = info.nombre; nombre.Parent = card
	-- divisor de acento
	local div = Instance.new("Frame"); div.Size = UDim2.new(0, 48, 0, 2); div.Position = UDim2.new(0.5, 0, 0, 172); div.AnchorPoint = Vector2.new(0.5, 0)
	div.BackgroundColor3 = col; div.BorderSizePixel = 0; div.Parent = card
	Instance.new("UICorner", div).CornerRadius = UDim.new(1, 0)
	-- EFECTO
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -28, 0, 92); desc.Position = UDim2.new(0, 14, 0, 184); desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.GothamBold; desc.TextWrapped = true; desc.TextSize = 16; desc.TextColor3 = tono(col, 0.62)
	desc.TextYAlignment = Enum.TextYAlignment.Top; desc.Text = info.desc; desc.Parent = card
	-- PILL de categoria (abajo)
	local cat = string.upper(info.categoria or "")
	local cpw = 46 + #cat * 8
	local cpill = Instance.new("Frame"); cpill.Size = UDim2.new(0, cpw, 0, 24); cpill.Position = UDim2.new(0.5, 0, 1, -34); cpill.AnchorPoint = Vector2.new(0.5, 0)
	cpill.BackgroundColor3 = tono(col, -0.5); cpill.BorderSizePixel = 0; cpill.Parent = card
	Instance.new("UICorner", cpill).CornerRadius = UDim.new(1, 0)
	local cpst = Instance.new("UIStroke"); cpst.Color = col; cpst.Thickness = 1; cpst.Transparency = 0.45; cpst.Parent = cpill
	local cpt = Instance.new("TextLabel"); cpt.Size = UDim2.new(1, 0, 1, 0); cpt.BackgroundTransparency = 1
	cpt.Font = Enum.Font.GothamBold; cpt.TextSize = 11; cpt.TextColor3 = tono(col, 0.5); cpt.Text = cat; cpt.Parent = cpill
	-- acentos en 2 esquinas (detalle)
	local function acento(ax, ay, ox, oy)
		local h = Instance.new("Frame"); h.Size = UDim2.fromOffset(14, 2); h.AnchorPoint = Vector2.new(ax, ay); h.Position = UDim2.new(ax, ox, ay, oy); h.BackgroundColor3 = col; h.BackgroundTransparency = 0.4; h.BorderSizePixel = 0; h.Parent = card
		local v = Instance.new("Frame"); v.Size = UDim2.fromOffset(2, 14); v.AnchorPoint = Vector2.new(ax, ay); v.Position = UDim2.new(ax, ox, ay, oy); v.BackgroundColor3 = col; v.BackgroundTransparency = 0.4; v.BorderSizePixel = 0; v.Parent = card
	end
	acento(0, 0, 10, 10); acento(1, 1, -10, -10)

	-- ENTRADA animada: la carta "aparece" con un pop escalonado en vez de plantarse de golpe. Se anima un
	-- UIScale (no la Position) porque el UIListLayout ya controla donde va cada carta.
	local rango = rangoDe(info)
	local retardo = 0.07 * ((indice or 1) - 1)
	local escala = Instance.new("UIScale")
	escala.Scale = 0.62
	escala.Parent = card
	task.delay(retardo, function()
		if escala.Parent then
			TweenService:Create(escala, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
	-- DESTELLO en las cartas gordas (Legendary / Mythic / Evolution): que se note que ha caido algo bueno.
	if rango >= RANGO.LEGENDARY then
		local flash = Instance.new("Frame")
		flash.Size = UDim2.new(1, 0, 1, 0)
		flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		flash.BackgroundTransparency = 0.2
		flash.BorderSizePixel = 0
		flash.ZIndex = 20
		flash.Parent = card
		local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 14); fc.Parent = flash
		task.delay(retardo, function()
			if flash.Parent then
				TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
				task.delay(0.7, function() if flash.Parent then flash:Destroy() end end)
			end
		end)
	end

	card.MouseButton1Click:Connect(function() elegir(info.id, card) end)
end

offerPowers.OnClientEvent:Connect(function(info)
	if info.close then
		cerrar()
		return
	end
	if info.cards then
		limpiarCartas()
		local mejor = 0
		for i, c in ipairs(info.cards) do
			crearCarta(c, i)
			local r = rangoDe(c)
			if r > mejor then mejor = r end
		end
		SoundManager.play(SONIDO[mejor] or "cardCommon") -- suena la MEJOR rareza de la oferta: si cae una dorada, se nota
		abierto = true
		player:SetAttribute("ChoosingPower", true) -- bloquea el disparo mientras eliges
		gui.Enabled = true
		esperaGui.Enabled = false -- I: si estaba el aviso de espera, quitalo (ahora ME toca elegir a mi)
	end
end)
