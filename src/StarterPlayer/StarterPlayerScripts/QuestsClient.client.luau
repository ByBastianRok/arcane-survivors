-- QuestsClient (LocalScript) - Fase D - panel de MISIONES DIARIAS + RACHA de login.
-- Boton QUESTS en el lobby -> abre el panel (pide datos a QuestsSync). Reclamar mision/racha
-- avisa al servidor (que da los Gems y revalida). Solo UI.
--
-- === PASE DE ARTE ===
-- Antes esto era el "rectangulo plano con relleno verde": la barra de progreso ERA el fondo entero de la
-- fila, asi que una mision a medias se veia como media placa verde y otra media azul. Colorines de fondo =
-- lo que mas canta a UI generada. Ahora la fila es una placa de piedra (UITheme) y el color solo sale en:
-- la barra FINA de progreso, el pictograma del tipo de mision, el "+N" de la recompensa y el borde de la
-- fila que YA se puede reclamar (que es la unica que interesa que salte a la vista).
--
-- Decisiones de ORDEN (lo que se gana no es estetico, es que el pulgar acierte a la primera):
--   1. lo RECLAMABLE arriba del todo,
--   2. lo que esta en curso en medio,
--   3. lo ya reclamado al fondo y en tono apagado (ocupa sitio pero ya no pide nada).
-- Con 3 misiones parece poco, pero el pool crece y el orden es lo que evita tener que leerlas todas.
--
-- === LO QUE NO SE TOCA (contrato con el servidor) ===
--   · questsSync:FireServer()                -> pedir datos
--   · questsSync:FireServer("quest", idx)    -> idx es el indice ORIGINAL de datos.misiones. Se reordena la
--                                               PINTURA con LayoutOrder, NUNCA la tabla: si se reordenara el
--                                               array, el indice enviado apuntaria a otra mision.
--   · questsSync:FireServer("racha")
--   · questsSync.OnClientEvent               -> datos + apertura diferida (quiereAbrir)
--   · abrirBtn.Text == "QUESTS" EXACTO       -> HubClient adopta este boton buscandolo por su .Text.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- OJO: UITheme vive en ReplicatedStorage/Modules. Si no esta espejado en Studio, este WaitForChild se queda
-- colgado y el boton QUESTS no llega a existir (HubClient avisaria con su warn de "no encontre estos botones").
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local questsSync = remotes:WaitForChild("QuestsSync")

local ACENTO = UITheme.acentos.quests -- el mismo oro que el icono del Hub: el panel y su entrada son lo mismo
local OK = UITheme.color.ok
local TENUE = UITheme.color.textoTenue
local APAGADO = UITheme.color.apagado

local datos = nil
local quiereAbrir = false

-- ===== Boton QUESTS (lobby) =====
-- Va en SU PROPIO ScreenGui, separado del panel: el panel se apaga entero con .Enabled y se llevaria el boton
-- por delante.
local btnGui = Instance.new("ScreenGui")
btnGui.Name = "QuestsButton"; btnGui.ResetOnSpawn = false; btnGui.Parent = playerGui
local abrirBtn = Instance.new("TextButton")
abrirBtn.Position = UDim2.new(0, 14, 0, 120); abrirBtn.Size = UDim2.new(0, 130, 0, 44)
abrirBtn.Font = UITheme.fuente.dato; abrirBtn.TextSize = 15
abrirBtn.TextScaled = false -- TextScaled IGNORA el TextSize; ademas HubClient lo apaga al adoptar
abrirBtn.TextColor3 = UITheme.color.texto
abrirBtn.Text = "QUESTS" -- LITERAL: HubClient lo busca por este texto exacto entre todos los TextButton
abrirBtn.Parent = btnGui
-- A proposito SIN pictograma, sin barra de acento y sin resalte propio: HubClient reviste este boton al
-- adoptarlo (le mete HubIcono + HubLabel + HubAcento + su tween de hover). Todo hijo que le pusieramos aqui
-- SOBREVIVE a la adopcion y se quedaria solapado encima del dibujo. Esto es solo el aspecto de reserva por si
-- la adopcion falla (el Hub reintenta 15s y se rinde).
UITheme.placa(abrirBtn, { radio = UITheme.radio.boton, sinGradiente = true, bordeTransp = 0.3 })

-- El gate de InMatch se conecta MAS ABAJO, despues de crear el panel: ahora que este menu si marca
-- MenuAbierto, esconder solo el boton no basta. Ver el comentario del final del fichero.
local function refrescarBoton()
	abrirBtn.Visible = not (player:GetAttribute("InMatch") == true)
end

-- ===== Panel =====
local gui = Instance.new("ScreenGui")
gui.Name = "QuestsPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 62; gui.Enabled = false; gui.Parent = playerGui

-- UITheme.panel da hecho: el overlay a pantalla completa con Active = true, la placa, la cabecera y el UIScale.
-- Active = true -> el fondo ABSORBE los clics. Sin esto, un Frame a pantalla completa se ve pero deja pasar el
-- toque: el boton PLAY recibia el click A TRAVES del fondo y podias arrancar una run sin querer desde dentro
-- del panel de misiones. Y 'clave' marca MenuAbierto (con contador), que es lo que esconde la columna del Hub
-- y el PLAY mientras esto esta abierto -- antes se quedaban flotando por encima.
-- (el overlay y la barra de titulo no hacen falta aqui: los guarda el propio UITheme.panel)
local _overlay, panel, _barra, api = UITheme.panel(gui, 620, 470, "QUESTS", {
	acento = ACENTO,
	clave = "quests",
	velo = 0.5,
})

-- Cabecera de seccion: tick de acento + rotulo pequeno a la izquierda y un dato a la derecha. El rotulo NO va
-- centrado y el tick sobresale por la izquierda: simetria perfecta = aspecto de plantilla.
local function cabecera(y, texto, nombre)
	UITheme.acentoBarra(panel, ACENTO, {
		nombre = nombre .. "Tick", ancho = 3, alto = 12,
		pos = UDim2.new(0, 20, 0, y + 3), anchor = Vector2.new(0, 0),
	})
	UITheme.etiqueta(panel, texto, {
		nombre = nombre, tam = 12, color = TENUE,
		pos = UDim2.new(0, 30, 0, y), tamano = UDim2.new(0, 300, 0, 16),
	})
end

cabecera(60, "LOGIN STREAK", "CabRacha")

local filaRacha = Instance.new("Frame")
filaRacha.Name = "Racha"; filaRacha.BackgroundTransparency = 1
filaRacha.Position = UDim2.new(0, 20, 0, 82); filaRacha.Size = UDim2.new(1, -40, 0, 54)
filaRacha.Parent = panel
local lr = Instance.new("UIListLayout", filaRacha)
lr.FillDirection = Enum.FillDirection.Horizontal
lr.SortOrder = Enum.SortOrder.LayoutOrder
lr.Padding = UDim.new(0, 5)

-- Resumen de racha a la IZQUIERDA y el boton de reclamar a la DERECHA (antes el boton iba centrado y solo).
-- El texto usa datos.racha.streak, que el servidor ya mandaba y no se pintaba en ningun sitio.
local lblRachaInfo = UITheme.etiqueta(panel, "", {
	nombre = "RachaInfo", tam = 13, color = TENUE,
	pos = UDim2.new(0, 20, 0, 144), tamano = UDim2.new(0, 330, 0, UITheme.TACTIL_MIN),
	alignY = Enum.TextYAlignment.Center,
})

local btnRacha = Instance.new("TextButton")
btnRacha.Name = "ClaimStreak"
btnRacha.AnchorPoint = Vector2.new(1, 0)
btnRacha.Position = UDim2.new(1, -20, 0, 144)
btnRacha.Size = UDim2.fromOffset(224, UITheme.TACTIL_MIN) -- 44 px: minimo tactil en movil
btnRacha.AutoButtonColor = false
btnRacha.Font = UITheme.fuente.dato
btnRacha.TextSize = 14
btnRacha.TextScaled = false
btnRacha.Text = ""          -- el texto visible va en el hijo: un UIGradient en un TextButton tiñe TAMBIEN su texto
btnRacha.TextTransparency = 1
btnRacha.Parent = panel
local lblRacha = UITheme.etiqueta(btnRacha, "", {
	nombre = "Label", fuente = UITheme.fuente.dato, tam = 14, color = UITheme.color.texto,
	tamano = UDim2.fromScale(1, 1), align = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Center,
})
lblRacha.ZIndex = 2

-- Este boton cambia de color segun estado, por eso NO se construye con UITheme.boton: aquel congela el color
-- base dentro del cierre del resalte, y al soltar el dedo el tween lo devolveria al color del estado ANTERIOR.
local RACHA_ACTIVO = { Color3.fromRGB(30, 46, 34), Color3.fromRGB(44, 66, 48), Color3.fromRGB(22, 34, 26) }
local RACHA_MUERTO = { Color3.fromRGB(32, 31, 38), Color3.fromRGB(42, 41, 50), Color3.fromRGB(24, 23, 30) }
local rachaViva = false
local function vestirRacha()
	local v = rachaViva and RACHA_ACTIVO or RACHA_MUERTO
	UITheme.placa(btnRacha, { fondo = v[1], alto = v[2], bajo = v[3], radio = UITheme.radio.boton, bordeTransp = 0.3 })
end
vestirRacha()
UITheme.pulsacion(btnRacha, function(on)
	if not rachaViva then return end -- un boton muerto que se ilumina al tocarlo promete algo que no va a pasar
	local base = RACHA_ACTIVO[1]
	TweenService:Create(btnRacha, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
		BackgroundColor3 = on and base:Lerp(Color3.new(1, 1, 1), 0.13) or base,
	}):Play()
end)

-- El separador va SOLO aqui (la cabecera del panel ya trae el suyo). Repetir la misma linea entre todos los
-- bloques es justo el patron que hace que una UI parezca una plantilla.
UITheme.separador(panel, 204, { izq = 20, margen = 44 })
cabecera(214, "DAILY MISSIONS", "CabMisiones")

-- Contador a la derecha de la cabecera: "1 / 3 CLAIMED" dice de un vistazo si queda algo por hacer hoy.
local lblProgreso = UITheme.etiqueta(panel, "", {
	nombre = "ContadorMisiones", tam = 12, color = TENUE,
	pos = UDim2.new(1, -220, 0, 214), tamano = UDim2.new(0, 200, 0, 16),
	align = Enum.TextXAlignment.Right,
})

-- Lista con scroll aunque hoy quepan las 3 del pool: el pool crece y una fila cortada por abajo es peor que
-- una barra de scroll.
local filaMis = UITheme.scroll(panel, {
	nombre = "Misiones", padding = 8, relleno = 6,
	pos = UDim2.new(0, 20, 0, 236), tamano = UDim2.new(1, -40, 1, -252),
})

local function limpiar(f)
	-- Solo GuiObject: hay que respetar el UIListLayout y el UIPadding que trae UITheme.scroll.
	for _, c in ipairs(f:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

-- El servidor manda la desc YA formateada y BORRA el campo 'tipo' (ver Quests.construirDatos), asi que el
-- pictograma se deduce por palabra clave. Si manana cambia el copy del pool esto cae al pergamino y no rompe nada.
local function iconoDe(desc)
	local d = string.lower(desc or "")
	if string.find(d, "kill", 1, true) then return "calavera" end
	if string.find(d, "wave", 1, true) then return "escudo" end
	if string.find(d, "act", 1, true) then return "estrella" end
	return "pergamino"
end

-- ===== Una casilla de la racha =====
-- Los 7 dias NO son 7 cajas identicas: el de hoy lleva borde de acento y su barrita, los ya cobrados cambian
-- el numero por un check, y el ultimo (el premio gordo del ciclo) lleva borde legendario. Siete celdas clonadas
-- serian ilegibles: hay que ver DONDE estas sin contar.
local function pintarDia(i, gems, cobrado, esHoy, esUltimo, total)
	local cell = Instance.new("Frame")
	cell.Name = "Dia" .. i
	cell.LayoutOrder = i
	cell.Size = UDim2.new(1 / total, -5, 1, 0)
	cell.Parent = filaRacha

	local borde, bordeTransp = nil, nil
	if esHoy then
		borde, bordeTransp = ACENTO, 0.05
	elseif esUltimo then
		borde, bordeTransp = UITheme.rareza.legendario, 0.5 -- el dia 7 se ve venir desde el dia 1
	end
	UITheme.placa(cell, {
		fondo = cobrado and Color3.fromRGB(30, 29, 37) or UITheme.color.fondoPlaca,
		alto = cobrado and Color3.fromRGB(38, 37, 46) or Color3.fromRGB(52, 50, 63),
		bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.tarjeta, -- radio distinto al de las filas (10) y al del panel (14): jerarquia
		borde = borde, bordeTransp = bordeTransp, grosor = 2,
	})

	UITheme.etiqueta(cell, "D" .. i, {
		nombre = "Dia", tam = 11, color = esHoy and UITheme.color.texto or (cobrado and APAGADO or TENUE),
		pos = UDim2.new(0, 0, 0, 7), tamano = UDim2.new(1, 0, 0, 12),
		align = Enum.TextXAlignment.Center,
	})

	if cobrado then
		-- El numero ya no importa: importa que esta hecho.
		UITheme.icono(cell, "check", UITheme.tono(OK, -0.25), {
			lado = 24, pos = UDim2.new(0.5, 0, 0, 24), anchor = Vector2.new(0.5, 0),
		})
	else
		local col = esUltimo and UITheme.rareza.legendario or (esHoy and ACENTO or TENUE)
		UITheme.etiqueta(cell, tostring(gems), {
			nombre = "Gems", fuente = UITheme.fuente.dato, tam = esUltimo and 17 or 15, color = col,
			pos = UDim2.new(0, 0, 0, 23), tamano = UDim2.new(1, 0, 0, 20),
			align = Enum.TextXAlignment.Center,
		})
	end

	if esHoy then
		UITheme.acentoBarra(cell, ACENTO, { nombre = "Hoy", ancho = 18, alto = 3, pos = UDim2.new(0.5, 0, 1, -7) })
	end
end

-- ===== Una fila de mision =====
-- Anatomia: pictograma | descripcion + barra fina + contador | recompensa | boton. La barra NO llega hasta la
-- recompensa (el contador "45/100" va justo detras): que todo termine en la misma vertical es lo que da el
-- aire de plantilla.
local function pintarMision(m, idx, orden)
	local listo = m.completa and not m.claimed

	local row = Instance.new("Frame")
	row.Name = "Mision" .. idx
	row.LayoutOrder = orden
	row.Size = UDim2.new(1, 0, 0, 66)
	row.Parent = filaMis
	UITheme.placa(row, {
		fondo = m.claimed and Color3.fromRGB(30, 29, 37) or UITheme.color.fondoPlaca,
		alto = m.claimed and Color3.fromRGB(38, 37, 46) or Color3.fromRGB(52, 50, 63),
		bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.placa,
		-- La UNICA fila con borde de color es la que se puede cobrar YA. Si todas llevaran filo, ninguna destacaria.
		borde = listo and ACENTO or nil,
		bordeTransp = listo and 0.15 or 0.3,
	})

	local colIcono = m.claimed and APAGADO or (listo and ACENTO or UITheme.color.textoSuave)
	UITheme.icono(row, m.claimed and "check" or iconoDe(m.desc), colIcono, {
		lado = 28, pos = UDim2.new(0, 10, 0.5, 0), anchor = Vector2.new(0, 0.5),
	})

	UITheme.etiqueta(row, m.desc or "", {
		nombre = "Desc", fuente = UITheme.fuente.dato, tam = 15,
		color = m.claimed and TENUE or UITheme.color.texto,
		pos = UDim2.new(0, 48, 0, 11), tamano = UDim2.new(1, -246, 0, 20),
	})

	-- Barra de progreso: 6 px de alto. Antes el relleno era el fondo ENTERO de la fila, o sea media placa
	-- pintada de verde; asi el color pesa lo justo para leerse de un vistazo sin gritar.
	local pista = Instance.new("Frame")
	pista.Name = "Pista"
	pista.Position = UDim2.new(0, 48, 0, 40)
	pista.Size = UDim2.new(1, -310, 0, 6)
	pista.BackgroundColor3 = Color3.fromRGB(24, 23, 31)
	pista.BorderSizePixel = 0
	pista.ClipsDescendants = true -- el relleno hereda asi la esquina redondeada de la pista
	pista.Parent = row
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = pista

	local ratio = math.clamp((m.prog or 0) / math.max(m.target or 1, 1), 0, 1)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(ratio, 0, 1, 0)
	fill.BackgroundColor3 = m.claimed and APAGADO or (m.completa and OK or ACENTO)
	fill.BackgroundTransparency = m.claimed and 0.4 or 0
	fill.BorderSizePixel = 0
	fill.Parent = pista
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill

	UITheme.etiqueta(row, (m.prog or 0) .. " / " .. (m.target or 0), {
		nombre = "Contador", tam = 12, color = m.claimed and APAGADO or TENUE,
		pos = UDim2.new(1, -202, 0, 34), tamano = UDim2.new(0, 56, 0, 16),
		anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right,
	})

	-- Recompensa: gema dibujada + "+N". Nada de emoji de diamante (cada movil pinta el suyo, con su paleta).
	-- lado 28 y no 26: los pictogramas estan medidos para un lienzo de 30 y la caja RECORTA (ClipsDescendants),
	-- asi que apurar el tamaño le come la punta al pabellon de la gema.
	UITheme.icono(row, "gema", m.claimed and APAGADO or UITheme.color.gemas, { -- morado canonico de Gems (audit 22-jul: antes azul rareza.raro)
		lado = 28, pos = UDim2.new(1, -164, 0.5, 0), anchor = Vector2.new(1, 0.5),
	})
	UITheme.etiqueta(row, "+" .. (m.gems or 0), {
		nombre = "Premio", fuente = UITheme.fuente.dato, tam = 14,
		color = m.claimed and APAGADO or ACENTO,
		pos = UDim2.new(1, -158, 0.5, 0), tamano = UDim2.new(0, 40, 0, 18),
		anchor = Vector2.new(0, 0.5), alignY = Enum.TextYAlignment.Center,
	})

	local texto, variante, colTexto
	if m.claimed then
		-- Apagado SI, ilegible NO: el gris de UITheme.color.apagado sobre la placa oscura casi no se lee en
		-- un movil al sol. Se baja el tono del texto tenue en vez de usar el apagado a pelo.
		texto, variante, colTexto = "CLAIMED", "apagado", UITheme.tono(TENUE, -0.35)
	elseif m.completa then
		texto, variante, colTexto = "CLAIM", "ok", UITheme.color.texto
	else
		texto, variante, colTexto = "In progress", "apagado", TENUE
	end
	local reclamable = (variante == "ok") -- solo el estado CLAIM es tocable de verdad
	local claim = UITheme.boton(row, texto, {
		nombre = "Claim", ancho = 104, alto = UITheme.TACTIL_MIN, tam = 13,
		variante = variante, textoColor = colTexto,
		pos = UDim2.new(1, -10, 0.5, 0), anchor = Vector2.new(1, 0.5),
		sinPulsacion = not reclamable, -- audit 22-jul: sin esto, "In progress"/claimed se ILUMINABAN al pasar el raton (prometian click que no hay)
	})
	if listo and reclamable then
		claim.Active = true
		-- idx es el indice en datos.misiones TAL CUAL lo mando el servidor. La reordenacion visual va por
		-- LayoutOrder justamente para no tocar este numero.
		claim.MouseButton1Click:Connect(function() questsSync:FireServer("quest", idx) end)
	else
		claim.Active = false -- sin handler: un boton no reclamable no dispara nada al servidor
	end
end

local function pintar()
	if not datos then return end

	-- ---- racha ----
	limpiar(filaRacha)
	local racha = datos.racha or {}
	local premios = racha.premios or {}
	local dia = racha.dia or 1
	-- Si el dia de hoy sigue reclamable, aun NO cuenta como cobrado; si ya se cobro, el dia actual entra en los hechos.
	local cobrados = racha.reclamableHoy and (dia - 1) or dia
	for i, gems in ipairs(premios) do
		pintarDia(i, gems, i <= cobrados, i == dia, i == #premios, #premios)
	end
	-- Separadores ASCII a proposito: este fichero viaja de /src a Studio por el MCP y un caracter raro dentro de
	-- una cadena es justo lo que puede llegar mojibake al otro lado. En los COMENTARIOS da igual, en el copy no.
	lblRachaInfo.Text = string.format("Day %d of %d  |  %d day streak", dia, math.max(#premios, 1), racha.streak or 1)

	rachaViva = racha.reclamableHoy == true
	btnRacha.Active = rachaViva -- se conserva tal cual: el handler de abajo lo comprueba antes de disparar
	vestirRacha()
	if rachaViva then
		lblRacha.Text = "CLAIM DAY " .. dia .. "  (+" .. (premios[dia] or 0) .. " Gems)"
		lblRacha.TextColor3 = UITheme.color.texto
	else
		lblRacha.Text = "Come back tomorrow"
		lblRacha.TextColor3 = TENUE
	end

	-- ---- misiones ----
	limpiar(filaMis)
	local misiones = datos.misiones or {}
	local cobradas = 0
	for i, m in ipairs(misiones) do
		if m.claimed then cobradas += 1 end
		-- Reclamable (1xx) -> en curso (2xx) -> cobrada (3xx). El +i mantiene estable el orden dentro de cada grupo.
		local grupo = m.claimed and 300 or (m.completa and 100 or 200)
		pintarMision(m, i, grupo + i)
	end
	lblProgreso.Text = #misiones > 0 and string.format("%d / %d CLAIMED", cobradas, #misiones) or ""

	if #misiones == 0 then
		-- Hueco vacio sin explicacion = parece roto.
		UITheme.etiqueta(filaMis, "No missions today. Come back tomorrow.", {
			nombre = "Vacio", tam = 14, color = TENUE,
			tamano = UDim2.new(1, 0, 0, 60), align = Enum.TextXAlignment.Center,
			alignY = Enum.TextYAlignment.Center,
		})
	end
end

questsSync.OnClientEvent:Connect(function(d)
	datos = d
	if quiereAbrir then quiereAbrir = false; api.abrir() end
	if api.estaAbierto() then pintar() end
end)

abrirBtn.MouseButton1Click:Connect(function()
	quiereAbrir = true
	questsSync:FireServer() -- pedir datos; al llegar se abre
end)
-- La X de la cabecera ya la cablea UITheme.panel a api.cerrar (y ese es el que apaga MenuAbierto).
btnRacha.MouseButton1Click:Connect(function()
	if btnRacha.Active then questsSync:FireServer("racha") end
end)

-- ===== Gate de partida =====
-- Va aqui abajo y no junto a refrescarBoton porque necesita `api`, que se crea con el panel.
--
-- OJO, esto es mas que esconder un boton: desde que este panel marca MenuAbierto (clave "quests"), si
-- arrancas una run con las misiones abiertas el flag se queda pegado en true TODA la partida -> el Hub
-- esconde su columna de iconos y el PLAY desaparece, y encima el overlay (que absorbe clics, Active = true)
-- se queda tapando el combate. CraftClient y ProfileClient ya cierran su panel por este motivo.
local function gatePartida()
	refrescarBoton()
	if player:GetAttribute("InMatch") == true and api.estaAbierto() then
		quiereAbrir = false -- si no, el siguiente sync del servidor lo volveria a abrir en plena run
		api.cerrar()
	end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gatePartida)
gatePartida()
