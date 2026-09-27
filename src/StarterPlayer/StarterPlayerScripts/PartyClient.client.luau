-- PartyClient (LocalScript) - Sco Fase B - UI de PARTY en el lobby.
-- Boton PARTY -> panel con tus miembros + INVITAR a jugadores del mismo lobby (flujo principal) + invitar amigos
-- de Roblox (extra) + aceptar/rechazar + salir. El PLAY del lider teletransporta a la party junta.
-- El servidor (PartyServer) manda el estado por PartySync. Rediseño 22-jul: invitar-del-lobby prominente +
-- empty-state claro + look del tema (fuera el neon azul "slop" que marco la auditoria).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local plr = Players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local partyAction = remotes:WaitForChild("PartyAction")
local partySync = remotes:WaitForChild("PartySync")

local estado = nil

local MORADO = Color3.fromRGB(140, 120, 235) -- acento de PARTY
local PLACA = Color3.fromRGB(38, 37, 49)
local PLACA2 = Color3.fromRGB(46, 44, 62)
local BORDE = Color3.fromRGB(18, 16, 26)

local gui = Instance.new("ScreenGui")
gui.Name = "PartyUI"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 40
gui.Parent = playerGui

-- ===== BOTON PARTY (carril izquierdo, bajo el engranaje y el contador de monedas) =====
local btn = Instance.new("TextButton")
btn.Position = UDim2.new(0, 16, 0, 100); btn.Size = UDim2.new(0, 132, 0, 42)
btn.BackgroundColor3 = PLACA; btn.AutoButtonColor = false; btn.Text = "PARTY"; btn.Parent = gui -- G: .Text="PARTY" es el gancho para que HubClient lo adopte a la columna derecha (luego lo vacia y le pone su icono/etiqueta)
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
local bg = Instance.new("UIGradient"); bg.Color = ColorSequence.new(Color3.fromRGB(60, 56, 78), Color3.fromRGB(30, 28, 40)); bg.Rotation = 90; bg.Parent = btn
local bs = Instance.new("UIStroke"); bs.Color = BORDE; bs.Thickness = 2; bs.Transparency = 0.25; bs.Parent = btn

-- G: el ASPECTO del boton (icono de grupo + etiqueta "Party" + acento) lo pone HubClient al ADOPTARLO en la
-- columna derecha (lo busca por .Text == "PARTY", lo reparenta, lo reestiliza y le dibuja su icono). Aqui solo
-- dejamos el boton + el badge del nº de miembros (HubClient no toca los hijos que no son suyos).

-- una insignia con el nº de miembros sobre el boton (se ve de un vistazo sin abrir el panel)
local badge = Instance.new("TextLabel")
badge.AnchorPoint = Vector2.new(1, 0); badge.Position = UDim2.new(1, 3, 0, -3); badge.Size = UDim2.fromOffset(18, 18); badge.ZIndex = 6 -- G: esquina sup-der de la celda 60x68 de la columna
badge.BackgroundColor3 = MORADO; badge.Font = Enum.Font.GothamBlack; badge.TextSize = 12; badge.TextColor3 = Color3.new(1, 1, 1)
badge.Text = "1"; badge.Visible = false; badge.Parent = btn
Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)

-- ===== PANEL =====
local panel = Instance.new("Frame")
panel.Position = UDim2.new(0, 16, 0, 146); panel.Size = UDim2.new(0, 300, 0, 432)
panel.BackgroundColor3 = Color3.fromRGB(28, 26, 38); panel.Visible = false; panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local pgrad = Instance.new("UIGradient"); pgrad.Rotation = 90; pgrad.Color = ColorSequence.new(Color3.fromRGB(36, 33, 50), Color3.fromRGB(22, 20, 30)); pgrad.Parent = panel
local st = Instance.new("UIStroke", panel); st.Color = Color3.fromRGB(70, 64, 92); st.Thickness = 1.5; st.Transparency = 0.25
local pAcc = Instance.new("Frame"); pAcc.Size = UDim2.new(1, 0, 0, 8); pAcc.BackgroundColor3 = MORADO; pAcc.BorderSizePixel = 0; pAcc.Parent = panel
Instance.new("UICorner", pAcc).CornerRadius = UDim.new(0, 14)

-- C (fix): X de cerrar en la esquina (antes el panel solo se cerraba re-tocando el boton PARTY)
local cerrarX = Instance.new("TextButton")
cerrarX.AnchorPoint = Vector2.new(1, 0); cerrarX.Position = UDim2.new(1, -10, 0, 12); cerrarX.Size = UDim2.fromOffset(32, 32)
cerrarX.BackgroundColor3 = Color3.fromRGB(58, 42, 54); cerrarX.Text = "X"; cerrarX.Font = Enum.Font.GothamBlack; cerrarX.TextSize = 16
cerrarX.TextColor3 = Color3.fromRGB(235, 205, 215); cerrarX.ZIndex = 5; cerrarX.Parent = panel
Instance.new("UICorner", cerrarX).CornerRadius = UDim.new(0, 8)
cerrarX.MouseButton1Click:Connect(function() panel.Visible = false end)

local titulo = Instance.new("TextLabel")
titulo.BackgroundTransparency = 1; titulo.Position = UDim2.new(0, 16, 0, 16); titulo.Size = UDim2.new(1, -32, 0, 26)
titulo.Font = Enum.Font.GothamBlack; titulo.TextSize = 20; titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.TextColor3 = Color3.new(1, 1, 1); titulo.Text = "PARTY  1/4"; titulo.Parent = panel

-- --- tus miembros ---
local hdrMiembros = Instance.new("TextLabel")
hdrMiembros.BackgroundTransparency = 1; hdrMiembros.Position = UDim2.new(0, 16, 0, 46); hdrMiembros.Size = UDim2.new(1, -32, 0, 14)
hdrMiembros.Font = Enum.Font.GothamBold; hdrMiembros.TextSize = 11; hdrMiembros.TextXAlignment = Enum.TextXAlignment.Left
hdrMiembros.TextColor3 = Color3.fromRGB(150, 146, 168); hdrMiembros.Text = "YOUR PARTY"; hdrMiembros.Parent = panel
local miembrosCont = Instance.new("Frame")
miembrosCont.BackgroundTransparency = 1; miembrosCont.Position = UDim2.new(0, 16, 0, 64); miembrosCont.Size = UDim2.new(1, -32, 0, 128)
miembrosCont.Parent = panel
local mLayout = Instance.new("UIListLayout"); mLayout.Padding = UDim.new(0, 5); mLayout.Parent = miembrosCont

-- --- INVITAR DEL LOBBY (flujo principal, prominente) ---
local hdrInvite = Instance.new("TextLabel")
hdrInvite.BackgroundTransparency = 1; hdrInvite.Position = UDim2.new(0, 16, 0, 198); hdrInvite.Size = UDim2.new(1, -32, 0, 14)
hdrInvite.Font = Enum.Font.GothamBold; hdrInvite.TextSize = 11; hdrInvite.TextXAlignment = Enum.TextXAlignment.Left
hdrInvite.TextColor3 = MORADO; hdrInvite.Text = "INVITE FROM LOBBY"; hdrInvite.Parent = panel
local invCont = Instance.new("ScrollingFrame")
invCont.Position = UDim2.new(0, 16, 0, 216); invCont.Size = UDim2.new(1, -32, 0, 120); invCont.BackgroundColor3 = Color3.fromRGB(22, 20, 30)
invCont.BackgroundTransparency = 0.4; invCont.BorderSizePixel = 0; invCont.ScrollBarThickness = 4
invCont.ScrollBarImageColor3 = MORADO; invCont.CanvasSize = UDim2.new(0, 0, 0, 0); invCont.Parent = panel
Instance.new("UICorner", invCont).CornerRadius = UDim.new(0, 8)
local iPad = Instance.new("UIPadding"); iPad.PaddingTop = UDim.new(0, 5); iPad.PaddingLeft = UDim.new(0, 5); iPad.PaddingRight = UDim.new(0, 5); iPad.Parent = invCont
local iLayout = Instance.new("UIListLayout"); iLayout.Padding = UDim.new(0, 5); iLayout.Parent = invCont
-- empty-state (cuando no hay nadie mas en el lobby): sobre el area de la lista
local vacio = Instance.new("TextLabel")
vacio.BackgroundTransparency = 1; vacio.Position = UDim2.new(0, 8, 0, 8); vacio.Size = UDim2.new(1, -16, 1, -16)
vacio.Font = Enum.Font.GothamMedium; vacio.TextSize = 13; vacio.TextWrapped = true; vacio.TextColor3 = Color3.fromRGB(150, 146, 168)
vacio.Text = "Nobody else in the lobby yet.\nInvite a friend below to play together!"; vacio.Visible = false; vacio.Parent = invCont

-- --- invitar amigo de Roblox (extra) ---
local btnFriends = Instance.new("TextButton")
btnFriends.Position = UDim2.new(0, 16, 0, 344); btnFriends.Size = UDim2.new(1, -32, 0, 34)
btnFriends.BackgroundColor3 = PLACA2; btnFriends.AutoButtonColor = false; btnFriends.Font = Enum.Font.GothamBold; btnFriends.TextSize = 14
btnFriends.TextColor3 = Color3.fromRGB(180, 235, 200); btnFriends.Text = "+ Invite a Roblox friend"; btnFriends.Parent = panel
Instance.new("UICorner", btnFriends).CornerRadius = UDim.new(0, 8)
local fSt = Instance.new("UIStroke", btnFriends); fSt.Color = Color3.fromRGB(80, 180, 120); fSt.Thickness = 1.2; fSt.Transparency = 0.4

-- --- salir ---
local btnLeave = Instance.new("TextButton")
btnLeave.AnchorPoint = Vector2.new(0.5, 1); btnLeave.Position = UDim2.new(0.5, 0, 1, -12); btnLeave.Size = UDim2.new(1, -32, 0, 34)
btnLeave.BackgroundColor3 = Color3.fromRGB(58, 34, 40); btnLeave.AutoButtonColor = false; btnLeave.Font = Enum.Font.GothamBold; btnLeave.TextSize = 14
btnLeave.TextColor3 = Color3.fromRGB(255, 190, 190); btnLeave.Text = "Leave Party"; btnLeave.Parent = panel
Instance.new("UICorner", btnLeave).CornerRadius = UDim.new(0, 8)
local lSt = Instance.new("UIStroke", btnLeave); lSt.Color = Color3.fromRGB(150, 70, 74); lSt.Thickness = 1.2; lSt.Transparency = 0.4

-- ===== POPUP de invitacion recibida =====
local pop = Instance.new("Frame")
pop.AnchorPoint = Vector2.new(0.5, 0); pop.Position = UDim2.new(0.5, 0, 0, 16); pop.Size = UDim2.new(0, 330, 0, 92)
pop.BackgroundColor3 = Color3.fromRGB(30, 27, 42); pop.Visible = false; pop.Parent = gui
Instance.new("UICorner", pop).CornerRadius = UDim.new(0, 12)
local popAcc = Instance.new("Frame"); popAcc.Size = UDim2.new(1, 0, 0, 6); popAcc.BackgroundColor3 = MORADO; popAcc.BorderSizePixel = 0; popAcc.Parent = pop
Instance.new("UICorner", popAcc).CornerRadius = UDim.new(0, 12)
local ps = Instance.new("UIStroke", pop); ps.Color = Color3.fromRGB(70, 64, 92); ps.Thickness = 1.5; ps.Transparency = 0.2
local popTxt = Instance.new("TextLabel")
popTxt.BackgroundTransparency = 1; popTxt.Position = UDim2.new(0, 14, 0, 12); popTxt.Size = UDim2.new(1, -28, 0, 34)
popTxt.Font = Enum.Font.GothamBold; popTxt.TextSize = 14; popTxt.TextColor3 = Color3.new(1, 1, 1); popTxt.TextWrapped = true
popTxt.Text = ""; popTxt.Parent = pop
local popYes = Instance.new("TextButton")
popYes.Position = UDim2.new(0, 14, 1, -38); popYes.Size = UDim2.new(0.5, -18, 0, 30)
popYes.BackgroundColor3 = Color3.fromRGB(58, 150, 96); popYes.Font = Enum.Font.GothamBlack; popYes.TextSize = 14
popYes.TextColor3 = Color3.new(1, 1, 1); popYes.Text = "ACCEPT"; popYes.Parent = pop
Instance.new("UICorner", popYes).CornerRadius = UDim.new(0, 8)
local popNo = Instance.new("TextButton")
popNo.AnchorPoint = Vector2.new(1, 0); popNo.Position = UDim2.new(1, -14, 1, -38); popNo.Size = UDim2.new(0.5, -18, 0, 30)
popNo.BackgroundColor3 = Color3.fromRGB(54, 52, 68); popNo.Font = Enum.Font.GothamBold; popNo.TextSize = 14
popNo.TextColor3 = Color3.fromRGB(220, 220, 232); popNo.Text = "Decline"; popNo.Parent = pop
Instance.new("UICorner", popNo).CornerRadius = UDim.new(0, 8)

-- ===== acciones =====
btn.MouseButton1Click:Connect(function() panel.Visible = not panel.Visible end)
btnFriends.MouseButton1Click:Connect(function() pcall(function() SocialService:PromptGameInvite(plr) end) end)
btnLeave.MouseButton1Click:Connect(function()
	local n = estado and #estado.miembros or 1
	if n > 1 then
		partyAction:FireServer("leave") -- estas en una party -> salir
	else
		pcall(function() SocialService:PromptGameInvite(plr) end) -- solo tu -> "create party" = invita a alguien para empezar
	end
end)
popYes.MouseButton1Click:Connect(function() partyAction:FireServer("accept"); pop.Visible = false end)
popNo.MouseButton1Click:Connect(function() partyAction:FireServer("decline"); pop.Visible = false end)

local function limpiar(cont)
	for _, c in ipairs(cont:GetChildren()) do if c:IsA("GuiButton") or c:IsA("Frame") then c:Destroy() end end
end

local function refrescar()
	if not estado then return end
	local n = #estado.miembros
	titulo.Text = "PARTY  " .. n .. "/" .. (estado.maxParty or 4)
	badge.Text = tostring(n); badge.Visible = n > 1 -- se ve el tamaño sin abrir el panel

	-- tus miembros
	limpiar(miembrosCont)
	for _, m in ipairs(estado.miembros) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 28); row.BackgroundColor3 = PLACA2; row.BorderSizePixel = 0; row.Parent = miembrosCont
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
		local nm = Instance.new("TextLabel")
		nm.BackgroundTransparency = 1; nm.Position = UDim2.new(0, 10, 0, 0); nm.Size = UDim2.new(1, -44, 1, 0)
		nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextColor3 = m.esLider and Color3.fromRGB(255, 215, 110) or Color3.new(1, 1, 1)
		nm.Text = m.name .. (m.esLider and "  (leader)" or ""); nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Parent = row
		if estado.esLider and m.userId ~= plr.UserId then
			local k = Instance.new("TextButton")
			k.AnchorPoint = Vector2.new(1, 0.5); k.Position = UDim2.new(1, -6, 0.5, 0); k.Size = UDim2.new(0, 22, 0, 20)
			k.BackgroundColor3 = Color3.fromRGB(120, 56, 60); k.Font = Enum.Font.GothamBlack; k.TextSize = 12
			k.TextColor3 = Color3.fromRGB(255, 200, 200); k.Text = "X"; k.Parent = row
			Instance.new("UICorner", k).CornerRadius = UDim.new(0, 5)
			local uid = m.userId
			k.MouseButton1Click:Connect(function() partyAction:FireServer("kick", uid) end)
		end
	end
	-- T (Bastian): UN solo boton que cambia de nombre segun el estado. Solo dice "Leave Party" cuando de verdad
	-- estas en una party (2+ miembros). Si estas solo, dice "Create Party" e invita a alguien para empezar.
	if n > 1 then
		btnLeave.Text = "Leave Party"
		btnLeave.BackgroundColor3 = Color3.fromRGB(58, 34, 40); btnLeave.TextColor3 = Color3.fromRGB(255, 190, 190)
		lSt.Color = Color3.fromRGB(150, 70, 74)
	else
		btnLeave.Text = "+ Create Party"
		btnLeave.BackgroundColor3 = Color3.fromRGB(40, 44, 60); btnLeave.TextColor3 = Color3.fromRGB(195, 205, 255)
		lSt.Color = Color3.fromRGB(95, 110, 175)
	end
	btnLeave.Visible = true

	-- invitar del lobby
	local enParty = {}
	for _, m in ipairs(estado.miembros) do enParty[m.userId] = true end
	local puedeInvitar = estado.esLider and n < (estado.maxParty or 4)
	hdrInvite.Visible = puedeInvitar; invCont.Visible = puedeInvitar
	limpiar(invCont)
	if puedeInvitar then
		local cuantos = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= plr and not enParty[p.UserId] then
				cuantos += 1
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(1, 0, 0, 30); b.BackgroundColor3 = PLACA2; b.AutoButtonColor = true; b.Text = ""; b.Parent = invCont
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
				local acc = Instance.new("Frame"); acc.Size = UDim2.new(0, 3, 1, -8); acc.Position = UDim2.new(0, 4, 0.5, 0)
				acc.AnchorPoint = Vector2.new(0, 0.5); acc.BackgroundColor3 = MORADO; acc.BorderSizePixel = 0; acc.Parent = b
				Instance.new("UICorner", acc).CornerRadius = UDim.new(1, 0)
				local nm = Instance.new("TextLabel")
				nm.BackgroundTransparency = 1; nm.Position = UDim2.new(0, 14, 0, 0); nm.Size = UDim2.new(1, -80, 1, 0)
				nm.Font = Enum.Font.GothamBold; nm.TextSize = 13; nm.TextXAlignment = Enum.TextXAlignment.Left
				nm.TextColor3 = Color3.new(1, 1, 1); nm.Text = p.DisplayName; nm.TextTruncate = Enum.TextTruncate.AtEnd; nm.Parent = b
				local chip = Instance.new("TextLabel")
				chip.AnchorPoint = Vector2.new(1, 0.5); chip.Position = UDim2.new(1, -8, 0.5, 0); chip.Size = UDim2.new(0, 58, 0, 20)
				chip.BackgroundColor3 = MORADO; chip.Font = Enum.Font.GothamBlack; chip.TextSize = 11; chip.TextColor3 = Color3.new(1, 1, 1)
				chip.Text = "+ INVITE"; chip.Parent = b
				Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 5)
				local uid = p.UserId
				b.MouseButton1Click:Connect(function() partyAction:FireServer("invite", uid) end)
			end
		end
		vacio.Visible = (cuantos == 0)
	end
	invCont.CanvasSize = UDim2.new(0, 0, 0, iLayout.AbsoluteContentSize.Y + 10)

	-- invitacion recibida
	if estado.invitacion then
		popTxt.Text = estado.invitacion.fromName .. " invited you to their party!"; pop.Visible = true
	else
		pop.Visible = false
	end
end

partySync.OnClientEvent:Connect(function(data) estado = data; refrescar() end)
Players.PlayerAdded:Connect(function() task.wait(0.1); refrescar() end)
Players.PlayerRemoving:Connect(function() task.wait(0.1); refrescar() end)

-- La PARTY se monta en el LOBBY: en plena partida el boton/panel se ocultan (gate InMatch).
local function gate()
	local enPartida = plr:GetAttribute("InMatch") == true
	gui.Enabled = not enPartida
	if enPartida then panel.Visible = false; pop.Visible = false end
end
plr:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()

-- FIX #3: refresco periodico -> la lista "INVITE FROM LOBBY" se auto-actualiza aunque se pierda un evento
-- (alguien entra/sale del lobby). Solo en el lobby (gui.Enabled) y con estado ya recibido.
task.spawn(function()
	while true do
		task.wait(1.5)
		if gui.Enabled and estado then refrescar() end
	end
end)
