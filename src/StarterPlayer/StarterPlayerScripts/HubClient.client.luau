-- HubClient (LocalScript) · Sju - COLUMNA DE ICONOS del lobby (referencia de Bastian, 21 jul).
--
-- === POR QUE COLUMNA A LA DERECHA Y NO FILA ARRIBA (Bastian, 21-jul: "redistribuimos los botones?") ===
-- Estaban los 6 en fila en la esquina SUPERIOR DERECHA, que en un movil sujetado con las dos manos es la zona
-- que PEOR alcanza el pulgar -- y ahi vivian los dos botones que dan dinero (STORE y CLASSES/GACHA), en las
-- posiciones 5 y 6, o sea las mas lejanas de todas. Ahora van en columna por el lateral derecho, a media
-- altura: el pulgar derecho llega solo, no choca con el joystick (abajo-izquierda) ni con el PLAY
-- (abajo-centro), y al ser vertical caben celdas mas grandes (60x68 en vez de 54x66) sin comerse la escena.
--
-- Antes cada feature creaba SU PROPIO boton flotante con posiciones a mano, y el lobby acabo con 7 botones
-- repartidos por 4 zonas de la pantalla (QUESTS y FORGE arriba-izq, PLAYER INFO / CLASSES / PERKS abajo-izq,
-- STORE a la derecha...). Crecimiento organico: cada feature nueva metia su boton donde cabia.
-- Ahora van todos en UNA columna de iconos por el lateral derecho, como en las referencias que paso Bastian.
--
-- COMO esta hecho, y por que asi:
-- En vez de reescribir los 8 scripts de menu (y arriesgarme a romper logica que YA funciona), este script
-- REPARENTA los botones que esos scripts ya crean y los convierte en iconos de la fila. Sus handlers de click
-- siguen intactos: solo cambia DONDE viven y su aspecto. Anadir un menu nuevo = anadir su texto a la lista.
--
-- === POR QUE YA NO HAY EMOJIS (Bastian, 21-jul: "pq siempre tiene q tener emojis?") ===
-- Porque un emoji es un caracter de texto: gratis de poner, y por eso los puse. Pero (a) cada movil los pinta
-- con SU set -> el mismo boton se ve distinto en cada telefono, (b) vienen con su propia paleta chillona que
-- no es la del juego, y (c) se leen como placeholder. Ahora cada icono es un PICTOGRAMA dibujado aqui con
-- Frames (rectangulos, circulos y rotaciones): pesa nada, es nuestro, no depende del sistema y va todo en la
-- paleta del boton. Cada uno tiene SILUETA distinta, que es lo que se reconoce de un vistazo en movil.
--
-- Lo que NO entra aqui, a proposito:
--   · PLAY   -> es la accion principal: tiene que estar suelto, grande y centrado abajo.
--   · STATS  -> su boton solo se muestra DENTRO de la partida (es el panel de build en run) y esta columna se
--               oculta justo ahi; si lo metieramos quedaria inalcanzable.
--   · Ajustes (engranaje) -> hay que poder tocarlo TAMBIEN en partida.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- La lista de jugadores de Roblox vive en la esquina superior derecha (se comia la fila cuando estaba ahi, y
-- aun con la columna a media altura sigue estorbando arriba). Ademas duplicaba informacion: mostraba Cash/Gems
-- por leaderstats, que el HUD ya pinta arriba a la izquierda.
-- Se apaga (las referencias de Bastian tampoco la tienen). Para ver companeros ya estan AlliesClient en la run
-- y el panel de PARTY en el lobby, asi que no se pierde nada.
task.spawn(function()
	for _ = 1, 10 do -- el CoreGui a veces no esta listo al arrancar: se reintenta
		local ok = pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
		if ok then break end
		task.wait(0.5)
	end
end)

-- ===== Utilidades de dibujo =====
local CAJA = 30 -- lado del lienzo de cada icono, en px

-- Mezcla hacia blanco (f>0) o hacia negro (f<0). Todos los iconos se pintan a partir del color de su entrada,
-- asi cada boton tiene su tono y aun asi todos comparten el mismo lenguaje visual.
local function tono(c, f)
	if f >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), f)
	end
	return c:Lerp(Color3.fromRGB(18, 17, 24), -f)
end

-- Rectangulo posicionado por CENTRO en escala 0..1 de la caja. Con radio = redondeado; radio negativo = pildora.
local function pieza(padre, ancho, alto, cx, cy, color, radio, giro)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(cx, cy)
	f.Size = UDim2.fromOffset(ancho, alto)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = giro or 0
	f.Parent = padre
	if radio then
		local c = Instance.new("UICorner")
		c.CornerRadius = radio < 0 and UDim.new(1, 0) or UDim.new(0, radio)
		c.Parent = f
	end
	return f
end

-- Los 6 pictogramas. Cada uno con una silueta que no se parece a las otras: pergamino / orbe / martillo /
-- rombo / monedas / busto. Nada de "6 circulitos con un simbolo dentro".
local DIBUJOS = {}

function DIBUJOS.pergamino(caja, col) -- QUESTS: hoja con renglones
	pieza(caja, 19, 23, 0.5, 0.5, tono(col, 0.55), 3)
	pieza(caja, 19, 5, 0.5, 0.19, tono(col, 0.1), 3)          -- cabecera mas oscura
	for i, y in ipairs({ 0.45, 0.6, 0.75 }) do
		pieza(caja, i == 3 and 7 or 11, 2, i == 3 and 0.38 or 0.5, y, tono(col, -0.45), 1) -- ultimo renglon corto
	end
end

function DIBUJOS.orbe(caja, col) -- CLASSES/GACHA: orbe magico con brillo
	local o = pieza(caja, 23, 23, 0.5, 0.52, col, -1)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(tono(col, 0.45), tono(col, -0.4))
	g.Rotation = 70
	g.Parent = o
	local brillo = pieza(caja, 7, 7, 0.38, 0.36, Color3.new(1, 1, 1), -1)
	brillo.BackgroundTransparency = 0.45
	pieza(caja, 13, 3, 0.5, 0.9, tono(col, -0.55), -1) -- peana: lo asienta y lo separa del rombo de PERKS
end

function DIBUJOS.martillo(caja, col) -- FORGE: martillo inclinado
	pieza(caja, 4, 21, 0.56, 0.58, Color3.fromRGB(126, 92, 58), 2, -38)
	pieza(caja, 15, 9, 0.36, 0.32, tono(col, 0.25), 2, -38)
	pieza(caja, 5, 9, 0.29, 0.35, tono(col, -0.3), 1, -38) -- boca del martillo, mas oscura
end

function DIBUJOS.rombo(caja, col) -- PERKS: gema en rombo
	local r = pieza(caja, 16, 16, 0.5, 0.5, col, 2, 45)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(tono(col, 0.5), tono(col, -0.35))
	g.Rotation = 45
	g.Parent = r
	pieza(caja, 6, 6, 0.42, 0.4, tono(col, 0.75), 1, 45)
end

function DIBUJOS.monedas(caja, col) -- STORE: pila de monedas
	for i, d in ipairs({ { 22, 0.76 }, { 19, 0.53 }, { 16, 0.31 } }) do
		local m = pieza(caja, d[1], 8, 0.5, d[2], tono(col, i * 0.12), -1)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(tono(col, 0.55), tono(col, -0.2))
		g.Rotation = 90
		g.Parent = m
	end
end

function DIBUJOS.busto(caja, col) -- PLAYER INFO: cabeza y hombros
	pieza(caja, 11, 11, 0.5, 0.3, tono(col, 0.35), -1)
	pieza(caja, 21, 15, 0.5, 0.87, tono(col, 0.05), -1) -- la caja recorta: solo se ven los hombros
end

function DIBUJOS.grupo(caja, col) -- PARTY: dos bustos solapados (grupo)
	pieza(caja, 9, 9, 0.33, 0.33, tono(col, -0.1), -1)   -- figura de atras (izquierda, apagada)
	pieza(caja, 16, 12, 0.33, 0.92, tono(col, -0.32), -1)
	pieza(caja, 11, 11, 0.64, 0.35, tono(col, 0.4), -1)  -- figura de delante (derecha, viva)
	pieza(caja, 19, 14, 0.64, 0.92, tono(col, 0.08), -1)
end

-- El 'texto' tiene que coincidir EXACTO con el del boton que crea cada script. Se busca solo entre TextButton
-- porque los paneles tienen titulos parecidos (CraftClient tiene el boton "FORGE" y un titulo "FORGE - Relics").
local ENTRADAS = {
	{ texto = "PARTY",           etiqueta = "Party",   dibujo = "grupo",     color = Color3.fromRGB(140, 120, 235) }, -- G: PartyClient crea el boton con .Text="PARTY"; aqui se adopta a la columna
	{ texto = "QUESTS",          etiqueta = "Quests",  dibujo = "pergamino", color = Color3.fromRGB(206, 166, 74) },
	{ texto = "CLASSES / GACHA", etiqueta = "Classes", dibujo = "orbe",      color = Color3.fromRGB(148, 104, 214) },
	{ texto = "FORGE",           etiqueta = "Forge",   dibujo = "martillo",  color = Color3.fromRGB(196, 106, 76) },
	{ texto = "PERKS",           etiqueta = "Perks",   dibujo = "rombo",     color = Color3.fromRGB(88, 190, 178) },
	{ texto = "STORE",           etiqueta = "Store",   dibujo = "monedas",   color = Color3.fromRGB(226, 178, 70) },
	{ texto = "PLAYER INFO",     etiqueta = "Profile", dibujo = "busto",     color = Color3.fromRGB(96, 148, 220) },
}

local gui = Instance.new("ScreenGui")
gui.Name = "Hub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
-- Esto ponia 40 con el comentario "por debajo de los paneles que abre", y era MENTIRA: Gacha y Profile son 8,
-- asi que la barra se dibujaba ENCIMA de los menus que ella misma abria (se ve en cualquier captura con el
-- panel de PERKS abierto). Y con Perks y Store, que tambien son 40, quedaba EMPATE: con empate el orden de
-- dibujo en Roblox no esta definido, o sea el mismo sintoma pero aleatorio. 5 esta por debajo de los seis.
gui.DisplayOrder = 5
gui.Parent = playerGui

-- Columna pegada al lateral DERECHO, a media altura: la zona que mejor alcanza el pulgar derecho.
local columna = Instance.new("Frame")
columna.Name = "Columna"
columna.AnchorPoint = Vector2.new(1, 0.5)
columna.Position = UDim2.new(1, -12, 0.5, 8)
columna.Size = UDim2.fromOffset(60, 10) -- el alto lo calcula el UIListLayout (AutomaticSize)
columna.AutomaticSize = Enum.AutomaticSize.Y
columna.BackgroundTransparency = 1
columna.Parent = gui

-- Seis celdas de 68 + 5 huecos de 6 son 438 px de alto. En un movil apaisado corto eso se sale, y no hay ni un
-- solo UIScale en toda la UI del juego. Este encoge la columna (y solo la columna) si el viewport es bajo.
local escala = Instance.new("UIScale")
escala.Parent = columna
local camara = workspace.CurrentCamera
local function ajustarEscala()
	if not camara then return end
	local alto = camara.ViewportSize.Y
	-- Al arrancar, la camara reporta ViewportSize (1,1) hasta el primer fotograma. Sin este guardia la cuenta
	-- salia 1/620 y la columna se quedaba clavada en el minimo (0.78) para el resto de la sesion, en pantallas
	-- donde no hacia ninguna falta.
	if alto < 100 then return end
	escala.Scale = math.clamp(alto / 620, 0.78, 1) * 1.15 -- A: mismo +15% que UITheme.UI_ESCALA (la columna del Hub tiene su UIScale aparte)
end
if camara then camara:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala) end
-- Y por si la senal ya habia pasado antes de conectarnos: se reintenta un par de segundos.
task.spawn(function()
	for _ = 1, 20 do
		if camara and camara.ViewportSize.Y >= 100 then ajustarEscala() break end
		task.wait(0.1)
	end
end)
ajustarEscala()

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = columna

-- ===== Adoptar los botones que ya crean los demas scripts =====
local function buscarBoton(texto)
	for _, d in ipairs(playerGui:GetDescendants()) do
		if d:IsA("TextButton") and d.Text == texto and not d:IsDescendantOf(gui) then return d end
	end
	return nil
end

local function adoptar(entrada, orden)
	local btn = buscarBoton(entrada.texto)
	if not btn then return false end

	btn.Parent = columna
	btn.LayoutOrder = orden
	btn.Size = UDim2.fromOffset(60, 68)
	btn.AnchorPoint = Vector2.new(0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(38, 37, 47)
	btn.BackgroundTransparency = 0
	btn.AutoButtonColor = false -- el hover se hace a mano (mas abajo): AutoButtonColor pelea con el degradado
	-- El texto del boton se vacia (ahora el icono es un dibujo). TextScaled fuera: varios venian con el a true,
	-- que IGNORA el TextSize, y si algun script vuelve a escribir en .Text saldria un texto gigante encima del
	-- dibujo. Por eso ademas se vigila la propiedad.
	btn.Text = ""
	btn.TextScaled = false
	btn.TextTransparency = 1
	btn:GetPropertyChangedSignal("Text"):Connect(function()
		if btn.Text ~= "" then btn.Text = "" end
	end)

	local c = btn:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10); c.Parent = btn

	-- Degradado vertical = biselado: da volumen de placa. Un color plano con borde de neon es EL aspecto de
	-- plantilla; la placa de piedra pega ademas con el tema de fantasia.
	local grad = btn:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(58, 56, 70), Color3.fromRGB(28, 27, 35))
	grad.Rotation = 90
	grad.Parent = btn

	-- Borde OSCURO, no de color: separa la placa del fondo sin el look "neon" de UI generada.
	local st = btn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	st.Color = Color3.fromRGB(12, 11, 16); st.Thickness = 2; st.Transparency = 0.25; st.Parent = btn

	-- El icono
	local caja = btn:FindFirstChild("HubIcono") or Instance.new("Frame")
	caja.Name = "HubIcono"
	caja:ClearAllChildren()
	caja.Size = UDim2.fromOffset(CAJA, CAJA)
	caja.Position = UDim2.new(0.5, 0, 0, 7)
	caja.AnchorPoint = Vector2.new(0.5, 0)
	caja.BackgroundTransparency = 1
	caja.ClipsDescendants = true -- el busto cuenta con esto: los hombros se cortan por abajo
	caja.Parent = btn
	DIBUJOS[entrada.dibujo](caja, entrada.color)

	-- Etiqueta pequena bajo el icono. Los pictogramas se leen mejor que los emoji, pero en movil dudar de un
	-- icono cuesta un toque de mas, y "Forge" contra "Store" no se adivina a la primera.
	local lbl = btn:FindFirstChild("HubLabel") or Instance.new("TextLabel")
	lbl.Name = "HubLabel"
	lbl.Size = UDim2.new(1, 0, 0, 13)
	lbl.Position = UDim2.new(0, 0, 0, 40)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 11
	lbl.TextColor3 = Color3.fromRGB(198, 202, 214)
	lbl.Text = entrada.etiqueta
	lbl.Parent = btn

	-- Barra de acento abajo: es el UNICO sitio donde aparece el color a saco. Asi la fila se ve ordenada
	-- (6 placas iguales) pero cada boton sigue teniendo identidad.
	local acento = btn:FindFirstChild("HubAcento") or Instance.new("Frame")
	acento.Name = "HubAcento"
	acento.Size = UDim2.new(0, 26, 0, 3)
	acento.Position = UDim2.new(0.5, 0, 1, -9)
	acento.AnchorPoint = Vector2.new(0.5, 0)
	acento.BackgroundColor3 = entrada.color
	acento.BorderSizePixel = 0
	acento.Parent = btn
	local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(1, 0); ac.Parent = acento

	-- Hover/pulsacion: la placa se aclara y el acento se ensancha. Feedback tactil sin mover el layout.
	local infoRapida = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	local function resaltar(on)
		TweenService:Create(btn, infoRapida, {
			BackgroundColor3 = on and Color3.fromRGB(56, 55, 70) or Color3.fromRGB(38, 37, 47),
		}):Play()
		TweenService:Create(acento, infoRapida, { Size = UDim2.new(0, on and 36 or 26, 0, 3) }):Play()
		TweenService:Create(lbl, infoRapida, {
			TextColor3 = on and Color3.fromRGB(240, 243, 252) or Color3.fromRGB(198, 202, 214),
		}):Play()
	end
	btn.MouseEnter:Connect(function() resaltar(true) end)
	btn.MouseLeave:Connect(function() resaltar(false) end)
	-- En movil no hay MouseEnter/Leave fiables: el destello al tocar se hace con los eventos de input.
	btn.MouseButton1Down:Connect(function() resaltar(true) end)
	btn.MouseButton1Up:Connect(function() task.delay(0.15, function() resaltar(false) end) end)

	return true
end

-- Los scripts de menu son LocalScripts que corren EN PARALELO a este, asi que sus botones puede que aun no
-- existan. Se reintenta un rato en vez de asumir un orden de carga.
task.spawn(function()
	local pendientes = {}
	for i, e in ipairs(ENTRADAS) do pendientes[#pendientes + 1] = { e = e, orden = i } end
	local t0 = os.clock()
	while #pendientes > 0 and os.clock() - t0 < 15 do
		for i = #pendientes, 1, -1 do
			if adoptar(pendientes[i].e, pendientes[i].orden) then table.remove(pendientes, i) end
		end
		if #pendientes > 0 then task.wait(0.3) end
	end
	if #pendientes > 0 then
		local faltan = {}
		for _, p in ipairs(pendientes) do faltan[#faltan + 1] = p.e.texto end
		warn("[Hub] no encontre estos botones (se quedan donde estaban):", table.concat(faltan, ", "))
	end
end)

-- Durante la partida la columna no pinta nada: se oculta (igual que hacian los botones sueltos con InMatch).
-- Y tambien con un menu abierto: aunque el DisplayOrder ya la deja por debajo de los paneles, seguia flotando
-- sobre las esquinas de los que no ocupan la pantalla entera.
-- OJO: MenuAbierto no lo escriben todos los menus (Store, Quests, Forge y WorldSelect no lo tocan), asi que
-- esto es el cinturon y el DisplayOrder de arriba son los tirantes. Hacen falta los dos.
local function gate()
	columna.Visible = player:GetAttribute("InMatch") ~= true
		and player:GetAttribute("MenuAbierto") ~= true
end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
player:GetAttributeChangedSignal("MenuAbierto"):Connect(gate)
gate()
