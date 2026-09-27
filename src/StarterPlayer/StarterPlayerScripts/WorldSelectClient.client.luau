-- =====================================================================================================
-- WorldSelectClient (LocalScript) - Fase B - SELECTOR de mundos/actos/dificultad.
-- Se abre desde el boton PLAY del lobby (atributo "AbrirMundos"). Pide datos a WorldsSync,
-- pinta mundos + actos + dificultad con su bloqueo/superado, y al darle PLAY arranca la run
-- con startMatch(world, act, dif). El SERVIDOR revalida todo (esto es SOLO UI).
--
-- ESTA es la pantalla que se ve antes de CADA partida, o sea la que mas veces ve el jugador en toda su
-- vida con el juego. Por eso se pinta con el lenguaje de UITheme (placa de piedra) y con el patron de
-- "dungeon select": LISTA de mundos a la izquierda + DETALLE del elegido a la derecha, en vez de tres
-- filas de botones sueltos. Elegir mundo deja de ser un formulario y pasa a ser mirar un mapa.
--
-- OJO (dependencia): requiere ReplicatedStorage/Modules/UITheme. Si ese ModuleScript no esta espejado en
-- Studio, el WaitForChild se queda colgado PARA SIEMPRE y esta pantalla no abre -> el juego no arranca.
-- Espejar UITheme ANTES de probar esto.
--
-- Lo que NO se toca (logica ya buena, viene de arriba):
--   · remotes WorldsSync / StartMatch / PartySync / MatchError y sus handlers,
--   · el gateo co-op (en party, SOLO el lider puede empezar),
--   · el atributo "AbrirMundos" que dispara la peticion de datos,
--   · el guard de MatchError (sin datos NO se abre: si no queda un panel vacio tapando la pantalla).
-- El boton PLAY del LOBBY (LobbyClient) no arranca nada, solo pone "AbrirMundos"; el que llama a
-- startMatch es el de ESTE panel.
-- =====================================================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local worldsSync = remotes:WaitForChild("WorldsSync")
local startMatch = remotes:WaitForChild("StartMatch")
local partySync = remotes:WaitForChild("PartySync") -- co-op: saber si somos el LIDER de la party
local matchError = remotes:WaitForChild("MatchError") -- co-op: teleport fallido -> reabrir selector
local esLiderLocal, enParty = true, false -- por defecto party de 1 (=lider); PartySync lo actualiza
local partyN, partyMax = 1, 4 -- solo para PINTAR el contador de party de la barra inferior

local COL = UITheme.color
local ORO = COL.acento

local datos, selWorld, selDif, selAct = nil, nil, "normal", 1

-- Nombres de cara al jugador que el payload de WorldsSync NO trae (manda claves internas legacy).
-- Son ESPEJOS de CraftData.Materiales y BossData: si alli cambia el nombre, cambiarlo aqui. Se prefiere
-- esto a un require() extra para no sumar otro WaitForChild que pueda colgar la pantalla de PLAY.
local MATERIAL_POR_MUNDO = {
	[1] = { nombre = "Verdant Essence", color = Color3.fromRGB(110, 200, 110) },
	[2] = { nombre = "Frost Shard", color = Color3.fromRGB(130, 205, 240) },
	[3] = { nombre = "Ember Core", color = Color3.fromRGB(240, 140, 70) },
}
local JEFE_POR_MUNDO = { [1] = "Forest Warden", [2] = "Glacial Sentinel", [3] = "Magma Colossus" }

-- =====================================================================================================
-- ARMAZON
-- =====================================================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "WorldSelect"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 67
gui.Enabled = false; gui.Parent = playerGui

local ANCHO, ALTO = 764, 532
-- UITheme.panel da el overlay con Active=true (absorbe los clics: sin eso el toque atraviesa el panel y
-- llega al PLAY del lobby de debajo) y ademas lleva el MenuAbierto CON CONTADOR, que es lo que hace que
-- la columna de iconos del Hub se esconda mientras este selector esta abierto.
-- (el overlay no hace falta guardarlo: quien lo enciende y lo apaga es api.abrir/api.cerrar)
local _, panel, barra, api = UITheme.panel(gui, ANCHO, ALTO, "SELECT A WORLD", {
	acento = ORO,
	clave = "worldselect",
	velo = 0.55, -- mas oscuro de lo normal: aqui interesa que el lobby de detras deje de competir
})
local tickTitulo = barra:FindFirstChild("Tick") -- se retiñe con el color del mundo elegido

-- Reparto vertical (cuadra JUSTO): 64 de cabecera + 392 de contenido + 76 de barra inferior = 532.
-- Si se toca alguna de las 'y' del detalle, revisar que la fila de ACTS (la ultima, acaba en 390) no se
-- meta debajo del boton de PLAY: 'detalle' no clipa, asi que un desborde no se ve hasta que se solapan.
local Y_CONT = 64 -- debajo de la cabecera de 52 + aire
local ALTO_CONT = 392
local X_DET = 278
local ANCHO_DET = ANCHO - X_DET - 20 -- 466

-- Boton generico con el lenguaje de placa. No se usa UITheme.boton para los botones cuyo COLOR cambia de
-- estado (el PLAY): UITheme.boton captura su color base al crearse y el destello de pulsacion lo
-- restauraria al color VIEJO. Aqui el destello se conecta con el color que toca en cada momento.
local function placaBoton(padre, opts)
	local b = Instance.new("TextButton")
	b.Name = opts.nombre or "Boton"
	b.Text = "" -- el rotulo va en TextLabels hijos: un UIGradient tiñe TAMBIEN el texto del propio boton
	b.AutoButtonColor = false
	b.Size = opts.tamano or UDim2.fromOffset(opts.ancho or 120, opts.alto or 44)
	b.Position = opts.pos or UDim2.new(0, 0, 0, 0)
	if opts.anchor then b.AnchorPoint = opts.anchor end
	b.LayoutOrder = opts.layoutOrder or 0
	b.Parent = padre
	UITheme.placa(b, {
		fondo = opts.fondo,
		alto = opts.altoColor,
		bajo = opts.bajoColor,
		radio = opts.radio or UITheme.radio.placa,
		bordeTransp = opts.bordeTransp or 0.25,
	})
	return b
end

-- Destruye SOLO los hijos visuales: los UIListLayout/UIPadding del contenedor se quedan (si se van, la
-- fila deja de colocar nada y todo se apila en la esquina).
local function vaciar(cont)
	for _, c in ipairs(cont:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

local function filaHorizontal(padre, y, alto, padding)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Position = UDim2.new(0, 0, 0, y)
	f.Size = UDim2.new(1, 0, 0, alto)
	f.Parent = padre
	local ll = Instance.new("UIListLayout", f)
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, padding)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.VerticalAlignment = Enum.VerticalAlignment.Center
	return f
end

-- =====================================================================================================
-- COLUMNA IZQUIERDA  ·  lista de mundos
-- =====================================================================================================
local listaMundos = UITheme.scroll(panel, {
	nombre = "Mundos",
	pos = UDim2.new(0, 14, 0, Y_CONT),
	tamano = UDim2.new(0, 252, 0, ALTO_CONT),
	padding = 9,
})

-- Una tarjeta de mundo: franja de color a la izquierda, nombre, subtitulo y (si toca) candado dibujado.
-- La seleccionada se DESPLAZA 10 px a la derecha; por eso el boton vive dentro de un "hueco" transparente
-- que es quien ocupa el sitio en el UIListLayout (el layout escribe Position, asi que el boton no puede
-- moverse el mismo sin que el layout se lo pise en el siguiente reflow).
local function tarjetaMundo(orden, o)
	local hueco = Instance.new("Frame")
	hueco.Name = "Hueco" .. orden
	hueco.BackgroundTransparency = 1
	hueco.Size = UDim2.new(1, -6, 0, o.alto)
	hueco.LayoutOrder = orden
	hueco.Parent = listaMundos

	local base = o.desbloqueado and o.color:Lerp(COL.fondoPlaca, 0.80) or Color3.fromRGB(32, 31, 39)
	local btn = placaBoton(hueco, {
		nombre = "Mundo",
		tamano = UDim2.new(1, -10, 1, 0),
		pos = UDim2.new(0, o.seleccionado and 10 or 0, 0, 0),
		fondo = base,
		altoColor = UITheme.tono(base, 0.16),
		bajoColor = UITheme.tono(base, -0.24),
		bordeTransp = o.desbloqueado and 0.2 or 0.5,
	})
	-- El borde dorado del seleccionado REUSA el UIStroke que ya puso la placa (crear otro daria dos
	-- strokes superpuestos y un filo sucio).
	if o.seleccionado then
		local s = btn:FindFirstChildOfClass("UIStroke")
		if s then s.Color = ORO; s.Thickness = 2; s.Transparency = 0 end
	end

	-- Franja del mundo: metida 9 px, no pegada al canto, porque la esquina redondeada de la placa se la
	-- comeria por arriba y por abajo.
	local franja = Instance.new("Frame")
	franja.Size = UDim2.new(0, 4, 1, -20)
	franja.Position = UDim2.new(0, 9, 0.5, 0)
	franja.AnchorPoint = Vector2.new(0, 0.5)
	franja.BackgroundColor3 = o.desbloqueado and o.color or COL.apagado
	franja.BorderSizePixel = 0
	franja.Parent = btn
	Instance.new("UICorner", franja).CornerRadius = UDim.new(1, 0)

	UITheme.etiqueta(btn, o.nombre, {
		nombre = "Nombre",
		fuente = UITheme.fuente.dato,
		tam = 16,
		color = o.desbloqueado and COL.texto or COL.textoTenue,
		pos = UDim2.new(0, 23, 0, 13),
		tamano = UDim2.new(1, -60, 0, 20),
	})
	UITheme.etiqueta(btn, o.sub, {
		nombre = "Sub",
		tam = 12,
		color = o.desbloqueado and COL.textoTenue or COL.apagado,
		pos = UDim2.new(0, 23, 0, 34),
		tamano = UDim2.new(1, -60, 0, 16),
	})

	if not o.desbloqueado then
		UITheme.icono(btn, "candado", COL.apagado, {
			lado = 26, pos = UDim2.new(1, -14, 0.5, 0), anchor = Vector2.new(1, 0.5),
		})
	elseif o.actos then
		-- Progreso de un vistazo: un punto por acto, relleno = superado en la dificultad elegida.
		-- Asi la lista de la izquierda no es solo un menu, tambien dice por donde vas.
		for i = 1, o.actos do
			local p = Instance.new("Frame")
			p.Size = UDim2.fromOffset(7, 7)
			p.AnchorPoint = Vector2.new(1, 1)
			p.Position = UDim2.new(1, -14 - (o.actos - i) * 11, 1, -13)
			p.BackgroundColor3 = (i <= (o.superados or 0)) and o.color or Color3.fromRGB(56, 54, 66)
			p.BorderSizePixel = 0
			p.Parent = btn
			Instance.new("UICorner", p).CornerRadius = UDim.new(1, 0)
		end
	end

	UITheme.pulsacion(btn)
	btn.Active = o.desbloqueado and true or false -- Active NO admite nil, y el payload puede no traer el flag
	btn.MouseButton1Click:Connect(o.alPulsar)
	return btn
end

-- =====================================================================================================
-- COLUMNA DERECHA  ·  detalle del mundo elegido
-- =====================================================================================================
local detalle = Instance.new("Frame")
detalle.Name = "Detalle"
detalle.BackgroundTransparency = 1
detalle.Position = UDim2.new(0, X_DET, 0, Y_CONT)
detalle.Size = UDim2.new(0, ANCHO_DET, 0, ALTO_CONT)
detalle.Parent = panel

local lblNombre = UITheme.etiqueta(detalle, "", {
	nombre = "NombreMundo", fuente = UITheme.fuente.titulo, tam = 25, color = COL.texto,
	pos = UDim2.new(0, 0, 0, 0), tamano = UDim2.new(1, 0, 0, 30),
})
local subrayado = UITheme.acentoBarra(detalle, ORO, {
	nombre = "Subrayado", ancho = 46, alto = 3, pos = UDim2.new(0, 1, 0, 33), anchor = Vector2.new(0, 0),
})
local lblTwist = UITheme.etiqueta(detalle, "", {
	nombre = "Twist", tam = 13, color = COL.textoTenue,
	pos = UDim2.new(0, 0, 0, 43), tamano = UDim2.new(1, 0, 0, 16),
})
-- El separador NO llega al borde derecho a proposito (la simetria perfecta es lo que hace que una UI
-- parezca sacada de una plantilla).
UITheme.separador(detalle, 68, { izq = 0, margen = 130 })

local lblPoderEt = UITheme.etiqueta(detalle, "RECOMMENDED POWER", {
	nombre = "PoderEt", tam = 11, color = COL.textoTenue,
	pos = UDim2.new(0, 0, 0, 78), tamano = UDim2.new(0, 220, 0, 14),
})
-- "Power" en PILDORAS, no en un numero: el servidor no manda ninguna cifra de poder recomendado y
-- inventarse un "Power 340" seria mentirle al jugador. Cinco muescas = amenaza del mundo + dificultad.
local pipsPoder = {}
local cajaPips = Instance.new("Frame")
cajaPips.Name = "Pips"; cajaPips.BackgroundTransparency = 1
cajaPips.Position = UDim2.new(0, 0, 0, 96); cajaPips.Size = UDim2.new(0, 220, 0, 12)
cajaPips.Parent = detalle
for i = 1, 5 do
	local p = Instance.new("Frame")
	p.Size = UDim2.fromOffset(22, 6)
	p.Position = UDim2.new(0, (i - 1) * 27, 0, 3)
	p.BackgroundColor3 = Color3.fromRGB(56, 54, 66)
	p.BorderSizePixel = 0
	p.Parent = cajaPips
	Instance.new("UICorner", p).CornerRadius = UDim.new(1, 0)
	pipsPoder[i] = p
end

local lblProgEt = UITheme.etiqueta(detalle, "PROGRESS", {
	nombre = "ProgEt", tam = 11, color = COL.textoTenue, align = Enum.TextXAlignment.Right,
	pos = UDim2.new(1, -180, 0, 78), tamano = UDim2.new(0, 180, 0, 14),
})
local lblProgVal = UITheme.etiqueta(detalle, "", {
	nombre = "ProgVal", fuente = UITheme.fuente.dato, tam = 16, color = COL.texto,
	align = Enum.TextXAlignment.Right,
	pos = UDim2.new(1, -180, 0, 93), tamano = UDim2.new(0, 180, 0, 18),
})

local lblDropEt = UITheme.etiqueta(detalle, "POSSIBLE DROP", {
	nombre = "DropEt", tam = 11, color = COL.textoTenue,
	pos = UDim2.new(0, 0, 0, 120), tamano = UDim2.new(0, 220, 0, 14),
})
local filaDrop = filaHorizontal(detalle, 138, 88, 14)

UITheme.separador(detalle, 238, { izq = 0, margen = 190 })

local lblDifEt = UITheme.etiqueta(detalle, "DIFFICULTY", {
	nombre = "DifEt", tam = 11, color = COL.textoTenue,
	pos = UDim2.new(0, 0, 0, 246), tamano = UDim2.new(0, 220, 0, 14),
})
-- La marca de la dificultad elegida (el rombo) sobresale 17 px POR ENCIMA de la fila. Por eso esta fila
-- baja 26 px desde su etiqueta en vez de los 20 de las demas: si no, el rombo de la primera pestaña se
-- comia la ultima letra de "DIFFICULTY".
local filaDif = filaHorizontal(detalle, 272, 46, 12)

local lblActEt = UITheme.etiqueta(detalle, "ACTS", {
	nombre = "ActEt", tam = 11, color = COL.textoTenue,
	pos = UDim2.new(0, 0, 0, 326), tamano = UDim2.new(0, 220, 0, 14),
})
local filaActos = filaHorizontal(detalle, 344, 46, 12)

-- Endless no tiene actos ni dificultades: en vez de dejar media pantalla de huecos vacios, se apagan esas
-- secciones y se pone un solo rotulo.
local lblEndless = UITheme.etiqueta(detalle, "", {
	nombre = "Endless", fuente = UITheme.fuente.dato, tam = 16, color = Color3.fromRGB(210, 170, 245),
	pos = UDim2.new(0, 0, 0, 140), tamano = UDim2.new(1, 0, 0, 60), wrap = true,
	align = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top,
})
lblEndless.Visible = false

-- =====================================================================================================
-- BARRA INFERIOR  ·  party + accion
-- =====================================================================================================
UITheme.separador(panel, ALTO - 76, { izq = 20, margen = 40 })

local cajaParty = Instance.new("Frame")
cajaParty.Name = "Party"; cajaParty.BackgroundTransparency = 1
cajaParty.Position = UDim2.new(0, 20, 1, -60); cajaParty.Size = UDim2.new(0, 260, 0, 46)
cajaParty.Parent = panel
UITheme.etiqueta(cajaParty, "PARTY", {
	tam = 11, color = COL.textoTenue, pos = UDim2.new(0, 0, 0, 2), tamano = UDim2.new(0, 60, 0, 14),
})
local lblPartyN = UITheme.etiqueta(cajaParty, "1/4", {
	nombre = "PartyN", fuente = UITheme.fuente.dato, tam = 15, color = COL.texto,
	pos = UDim2.new(0, 0, 0, 18), tamano = UDim2.new(0, 44, 0, 18),
})
local cajaSlots = Instance.new("Frame")
cajaSlots.Name = "Slots"; cajaSlots.BackgroundTransparency = 1
cajaSlots.Position = UDim2.new(0, 44, 0, 16); cajaSlots.Size = UDim2.new(0, 130, 0, 22)
cajaSlots.Parent = cajaParty
local lblPartyPista = UITheme.etiqueta(cajaParty, "", {
	nombre = "PartyPista", tam = 11, color = COL.textoTenue,
	pos = UDim2.new(0, 0, 0, 34), tamano = UDim2.new(1, -10, 0, 14),
})

-- El tamaño de party NO se toca desde aqui: los miembros entran por invitacion (PartyClient/PartyServer),
-- no hay remote para "subir/bajar" el numero. Un + y un - que no llaman a nada seria un boton muerto, asi
-- que el contador es un MARCADOR: hueco relleno = jugador dentro, hueco vacio = sitio libre.
local function pintarParty()
	vaciar(cajaSlots)
	local maximo = math.clamp(partyMax or 4, 1, 4) -- 4 = MAX_PARTY de PartyServer; mas huecos no caben aqui
	for i = 1, maximo do
		local s = Instance.new("Frame")
		s.Size = UDim2.fromOffset(18, 18)
		s.Position = UDim2.new(0, (i - 1) * 24, 0, 2)
		s.BackgroundColor3 = i <= partyN and Color3.fromRGB(64, 62, 78) or Color3.fromRGB(38, 37, 46)
		s.BorderSizePixel = 0
		s.Parent = cajaSlots
		Instance.new("UICorner", s).CornerRadius = UDim.new(1, 0)
		local st = Instance.new("UIStroke", s)
		st.Color = i <= partyN and ORO or COL.borde
		st.Thickness = 1.5
		st.Transparency = i <= partyN and 0.15 or 0.4
		if i <= partyN then
			local n = Instance.new("Frame") -- punto interior: "ocupado" sin escribir nada
			n.Size = UDim2.fromOffset(7, 7)
			n.AnchorPoint = Vector2.new(0.5, 0.5)
			n.Position = UDim2.fromScale(0.5, 0.5)
			n.BackgroundColor3 = ORO
			n.BorderSizePixel = 0
			n.Parent = s
			Instance.new("UICorner", n).CornerRadius = UDim.new(1, 0)
		end
	end
	lblPartyN.Text = partyN .. "/" .. maximo
	lblPartyPista.Text = (enParty and not esLiderLocal) and "The leader starts the run" or "Invite from the PARTY panel"
end

local btnPlay = placaBoton(panel, {
	nombre = "Play",
	tamano = UDim2.fromOffset(252, 54),
	pos = UDim2.new(1, -20, 1, -14),
	anchor = Vector2.new(1, 1),
	radio = 11,
	bordeTransp = 0.2,
})
local lblPlay = UITheme.etiqueta(btnPlay, "PLAY", {
	nombre = "Label", fuente = UITheme.fuente.titulo, tam = 21, color = COL.texto,
	pos = UDim2.new(0, 0, 0, 0), tamano = UDim2.new(1, 0, 1, -5),
	align = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Center,
})
lblPlay.ZIndex = 2
local acentoPlay = UITheme.acentoBarra(btnPlay, COL.ok, {
	ancho = 54, alto = 3, pos = UDim2.new(0, 14, 1, -8), anchor = Vector2.new(0, 0),
})
btnPlay.Text = "PLAY" -- se DEJA puesto (HubClient busca botones por .Text exacto; "PLAY" no es de los suyos)

local playActivo = false
-- El destello de pulsacion se calcula con el color ACTUAL, no con el que tenia el boton al crearse: este
-- boton cambia de verde a gris segun si se puede empezar, y con el color capturado se quedaba pintado del
-- estado anterior al soltar el dedo.
UITheme.pulsacion(btnPlay, function(on)
	local base = playActivo and Color3.fromRGB(34, 58, 40) or Color3.fromRGB(34, 33, 40)
	-- apagado no destella: un boton que responde al dedo pero no hace nada se lee como que el juego se colgo
	local destino = (on and playActivo) and base:Lerp(Color3.new(1, 1, 1), 0.14) or base
	TweenService:Create(btnPlay, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { BackgroundColor3 = destino }):Play()
end)

local function estadoPlay(activo, texto)
	playActivo = activo and true or false
	UITheme.placa(btnPlay, {
		fondo = playActivo and Color3.fromRGB(34, 58, 40) or Color3.fromRGB(34, 33, 40),
		alto = playActivo and Color3.fromRGB(54, 88, 60) or Color3.fromRGB(44, 43, 52),
		bajo = playActivo and Color3.fromRGB(22, 38, 26) or Color3.fromRGB(24, 23, 30),
		radio = 11,
		bordeTransp = 0.2,
	})
	lblPlay.Text = texto
	lblPlay.TextColor3 = playActivo and Color3.fromRGB(228, 246, 230) or COL.textoTenue
	acentoPlay.BackgroundColor3 = playActivo and COL.ok or COL.apagado
	btnPlay.Text = texto -- misma cadena que el rotulo: nunca se vacia (ver nota de HubClient arriba)
	btnPlay.Active = playActivo
end

-- =====================================================================================================
-- PINTADO
-- =====================================================================================================
local function difDatos(id)
	if not datos or not datos.dificultades then return nil, 1 end
	for i, d in ipairs(datos.dificultades) do
		if d.id == id then return d, i end
	end
	return datos.dificultades[1], 1
end

-- Pestaña de dificultad. El color de la dificultad (verde/ambar/rojo, viene de WorldData) solo aparece en
-- el borde, la barrita y el rombo de seleccion: de fondo grande cantaria a boton de plantilla.
local function tabDificultad(d, indice, desbloq, sel)
	local base
	if not desbloq then
		base = Color3.fromRGB(31, 30, 37)
	elseif sel then
		base = d.color:Lerp(COL.fondoPlaca, 0.74)
	else
		base = COL.fondoPlaca
	end
	local b = placaBoton(filaDif, {
		nombre = "Dif" .. d.id,
		tamano = UDim2.fromOffset(144, 46),
		layoutOrder = indice,
		fondo = base,
		altoColor = UITheme.tono(base, 0.16),
		bajoColor = UITheme.tono(base, -0.22),
		radio = UITheme.radio.boton,
		bordeTransp = desbloq and 0.28 or 0.5,
	})
	if sel then
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then s.Color = d.color; s.Thickness = 2; s.Transparency = 0.1 end
	end

	UITheme.etiqueta(b, d.nombre, {
		nombre = "Label",
		fuente = UITheme.fuente.dato,
		tam = 15,
		color = desbloq and (sel and COL.texto or COL.textoSuave) or COL.apagado,
		pos = UDim2.new(0, desbloq and 14 or 36, 0, 0),
		tamano = UDim2.new(1, -20, 1, sel and -5 or 0),
		alignY = Enum.TextYAlignment.Center,
	})
	if not desbloq then
		UITheme.icono(b, "candado", COL.apagado, {
			lado = 20, pos = UDim2.new(0, 10, 0.5, 0), anchor = Vector2.new(0, 0.5),
		})
	end
	if sel then
		UITheme.acentoBarra(b, d.color, {
			ancho = 40, alto = 3, pos = UDim2.new(0, 14, 1, -7), anchor = Vector2.new(0, 0),
		})
		-- Marca ENCIMA de la pestaña elegida. Es un rombo (cuadrado girado 45), no un triangulo: Roblox no
		-- tiene poligono sin ImageLabel, y para simular la punta habria que recortar contra el borde del
		-- padre, que aqui no clipa. Un rombo se lee igual de bien y no necesita trucos.
		local marca = Instance.new("Frame")
		marca.BackgroundTransparency = 1
		marca.Size = UDim2.fromOffset(14, 14)
		marca.AnchorPoint = Vector2.new(0.5, 1)
		marca.Position = UDim2.new(0.5, 0, 0, -3)
		marca.Parent = b
		UITheme.pieza(marca, 9, 9, 0.5, 0.5, d.color, 2, 45)
	end
	UITheme.pulsacion(b)
	b.Active = desbloq and true or false
	return b
end

-- Boton de acto. El acto 4 (jefe del mundo) se marca DISTINTO: calavera + rotulo del jefe, para que no
-- parezca "un acto mas" cuando en realidad es el que cierra el mundo.
local function botonActo(act, esBoss, desbloq, superado, sel, nombreJefe)
	local base
	if not desbloq then
		base = Color3.fromRGB(31, 30, 37)
	elseif esBoss then
		base = Color3.fromRGB(48, 34, 36) -- tinte rojizo apagado, no rojo saturado
	else
		base = COL.fondoPlaca
	end
	local b = placaBoton(filaActos, {
		nombre = "Acto" .. act,
		tamano = UDim2.fromOffset(106, 46),
		layoutOrder = act,
		fondo = base,
		altoColor = UITheme.tono(base, 0.16),
		bajoColor = UITheme.tono(base, -0.22),
		radio = UITheme.radio.boton,
		bordeTransp = desbloq and 0.28 or 0.5,
	})
	if sel then
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then s.Color = ORO; s.Thickness = 2; s.Transparency = 0 end
	end

	local icono, colorIcono
	if not desbloq then
		icono, colorIcono = "candado", COL.apagado
	elseif superado then
		icono, colorIcono = "check", COL.ok
	elseif esBoss then
		icono, colorIcono = "calavera", COL.peligro
	end
	if icono then
		UITheme.icono(b, icono, colorIcono, {
			lado = 20, pos = UDim2.new(0, 9, 0, esBoss and 8 or 13), anchor = Vector2.new(0, 0),
		})
	end

	local izq = icono and 32 or 12
	UITheme.etiqueta(b, "ACT " .. act, {
		nombre = "Label",
		fuente = UITheme.fuente.dato,
		tam = 14,
		color = desbloq and (sel and COL.texto or COL.textoSuave) or COL.apagado,
		pos = UDim2.new(0, izq, 0, esBoss and 6 or 0),
		tamano = UDim2.new(1, -izq - 6, esBoss and 0 or 1, esBoss and 20 or 0),
		alignY = Enum.TextYAlignment.Center,
	})
	if esBoss then
		-- El nombre del jefe se corta si no cabe: es un guiño, no informacion critica.
		UITheme.etiqueta(b, desbloq and (nombreJefe or "BOSS") or "BOSS", {
			nombre = "Jefe",
			tam = 10,
			color = desbloq and COL.peligro or COL.apagado,
			pos = UDim2.new(0, izq, 0, 26),
			tamano = UDim2.new(1, -izq - 6, 0, 14),
		})
	end
	if sel then
		UITheme.acentoBarra(b, ORO, {
			ancho = 30, alto = 3, pos = UDim2.new(0, 12, 1, -7), anchor = Vector2.new(0, 0),
		})
	end
	UITheme.pulsacion(b)
	b.Active = desbloq and true or false
	return b
end

-- Fila de "posible drop": tarjetas con BORDE DE RAREZA. Solo se ponen recompensas que el server paga de
-- verdad, y AHORA reflejan la DIFICULTAD (audit 22-jul: antes solo el material cambiaba, rompiendo el
-- mensaje "harder = more rewards" en la pantalla mas vista). Los numeros salen de las mismas formulas del
-- server (GameManager): Cash escala con recompensaMult, y los Gems del 1er clear tambien (repetir no da Gems).
local function pintarDrop(w, d)
	vaciar(filaDrop)
	local mat = MATERIAL_POR_MUNDO[w.id]
	local difW = w.dif and w.dif[selDif]
	local yaCompleto = difW and difW.completo -- ya superaste este mundo en esta dificultad -> sin bonus de 1er clear
	local recomp = (d and d.recompensaMult) or 1
	-- GEMS: SOLO en el 1er clear del mundo (por dificultad = hito unico), escalados con la dificultad. Repetir NO da Gems.
	local gemsFC = math.floor((w.primeraGems or 0) * recomp)
	UITheme.tarjeta(filaDrop, {
		nombre = "DropGems", layoutOrder = 1, ancho = 144, alto = 88,
		rareza = "epico", icono = "gema",
		titulo = string.format("%d Gems", gemsFC),
		sub = yaCompleto and "Claimed" or "First clear",
	})
	-- CASH: se paga en CADA clear de acto y escala con la dificultad (recompensaMult). Mostramos base x dif; el
	-- pago real es algo MAYOR (suma bonus por acto y por score), asi que esto nunca infla la promesa.
	UITheme.tarjeta(filaDrop, {
		nombre = "DropCash", layoutOrder = 2, ancho = 144, alto = 88,
		rareza = "comun", icono = "monedas",
		titulo = string.format("%d Cash", math.floor((w.repiteCash or 0) * recomp)),
		sub = "Per clear",
	})
	UITheme.tarjeta(filaDrop, {
		nombre = "DropMat", layoutOrder = 3, ancho = 144, alto = 88,
		rareza = mat and mat.color or UITheme.rareza.raro, icono = "rombo",
		titulo = mat and mat.nombre or "Materials",
		sub = string.format("x%.1f amount", (d and d.matMult) or 1),
	})
end

local function pintar()
	if not datos then return end

	-- ---- lista de mundos ----
	vaciar(listaMundos)
	for i, w in ipairs(datos.worlds) do
		local difW = w.dif and w.dif[selDif]
		local superados = 0
		if difW and difW.actos then
			for act, info in ipairs(difW.actos) do if info.superado then superados = act end end
		end
		tarjetaMundo(i, {
			alto = 76,
			nombre = w.nombre,
			sub = w.desbloqueado and (w.twist or "") or "LOCKED",
			color = w.color,
			desbloqueado = w.desbloqueado,
			seleccionado = selWorld ~= nil and selWorld.id == w.id,
			actos = w.numActos,
			superados = superados,
			alPulsar = function()
				if not w.desbloqueado then return end
				selWorld = w; selAct = 1; pintar()
			end,
		})
	end
	-- Entrada ENDLESS (modo infinito + leaderboard); se desbloquea al superar todos los mundos.
	-- Va mas baja que las demas tarjetas a proposito: no es un mundo de la campaña.
	if datos.endless then
		local e = datos.endless
		tarjetaMundo(90, {
			alto = 64,
			nombre = e.desbloqueado and e.nombre or "Endless Rift",
			sub = e.desbloqueado and "Survive forever" or "Beat all worlds",
			color = e.color,
			desbloqueado = e.desbloqueado,
			seleccionado = selWorld ~= nil and selWorld.id == "endless",
			alPulsar = function()
				if not e.desbloqueado then return end
				selWorld = { id = "endless", nombre = e.nombre, color = e.color, desbloqueado = true, endless = true }
				pintar()
			end,
		})
	end

	local w = selWorld
	local colorMundo = (w and w.color) or ORO
	lblNombre.Text = w and w.nombre or ""
	subrayado.BackgroundColor3 = colorMundo
	if tickTitulo then tickTitulo.BackgroundColor3 = colorMundo end

	-- ---- ENDLESS: no hay actos ni dificultades, se apaga media columna ----
	if w and w.endless then
		lblTwist.Text = "Infinite waves - no acts, no end"
		lblPoderEt.Visible = true
		cajaPips.Visible = true
		for _, p in ipairs(pipsPoder) do
			p.BackgroundColor3 = colorMundo -- Endless = amenaza maxima: las 5 muescas encendidas
		end
		lblProgEt.Visible = false
		lblProgVal.Visible = false
		lblDropEt.Visible = false
		filaDrop.Visible = false
		lblDifEt.Visible = false
		filaDif.Visible = false
		lblActEt.Visible = false
		filaActos.Visible = false
		lblEndless.Visible = true
		lblEndless.Text = "Infinite waves - climb the TOP SCORES board!"
		estadoPlay(w.desbloqueado and true or false, "PLAY")
		pintarParty()
		return
	end

	lblEndless.Visible = false
	lblProgEt.Visible = true
	lblProgVal.Visible = true
	lblDropEt.Visible = true
	filaDrop.Visible = true
	lblDifEt.Visible = true
	filaDif.Visible = true
	lblActEt.Visible = true
	filaActos.Visible = true

	local dSel, iSel = difDatos(selDif)

	-- ---- dificultades ----
	-- Bastian se penso que era un bug: "al pasarte un acto no te deja hacerlo con la siguiente dificultad".
	-- No lo era (hacia falta el mundo ENTERO), pero el problema de fondo si: la UI solo pintaba un candado
	-- SIN DECIR POR QUE, y un candado sin motivo se lee como fallo. Ahora se dice el requisito, y ademas el
	-- requisito se ha suavizado a UN acto (ver difDesbloqueada en WorldsServer).
	vaciar(filaDif)
	local ANTERIOR = { hard = "normal", nightmare = "hard" } -- que dificultad hay que tocar para abrir esta
	for i, d in ipairs(datos.dificultades) do
		local difW = w and w.dif[d.id]
		local desbloq = difW and difW.desbloqueada
		local b = tabDificultad(d, i, desbloq, selDif == d.id)
		if not desbloq and w then
			local previaId = ANTERIOR[d.id]
			local previa
			for _, dd in ipairs(datos.dificultades) do if dd.id == previaId then previa = dd end end
			if previa then
				UITheme.etiqueta(b, "Clear 1 act on " .. previa.nombre, {
					nombre = "Requisito", fuente = UITheme.fuente.etiqueta, tam = 9,
					color = UITheme.color.textoTenue,
					pos = UDim2.new(0, 0, 1, -13), tamano = UDim2.new(1, 0, 0, 12),
					align = Enum.TextXAlignment.Center,
				})
			end
		end
		b.MouseButton1Click:Connect(function()
			if not desbloq then return end
			selDif = d.id; selAct = 1; pintar()
		end)
	end

	-- ---- actos ----
	vaciar(filaActos)
	if w then
		local difW = w.dif[selDif]
		for act = 1, w.numActos do
			local info = difW and difW.actos[act]
			local desbloq = info and info.desbloqueado
			local b = botonActo(act, act == w.numActos, desbloq, info and info.superado, selAct == act, JEFE_POR_MUNDO[w.id])
			b.MouseButton1Click:Connect(function()
				if not desbloq then return end
				selAct = act; pintar()
			end)
		end

		lblTwist.Text = string.format("%s  ·  %d waves per act  ·  %d acts", w.twist or "", w.oleadasActo or 0, w.numActos or 0)
		pintarDrop(w, dSel)

		-- Amenaza = que tan hondo esta el mundo + que tan dura la dificultad. Es lo unico que el payload
		-- permite decir con honestidad sobre "cuanta fuerza necesitas".
		local indiceMundo = 1
		for i, ww in ipairs(datos.worlds) do if ww.id == w.id then indiceMundo = i end end
		local amenaza = math.clamp(indiceMundo + (iSel - 1), 1, 5)
		for i, p in ipairs(pipsPoder) do
			p.BackgroundColor3 = i <= amenaza and ((dSel and dSel.color) or ORO) or Color3.fromRGB(56, 54, 66)
		end

		local difW2 = w.dif[selDif]
		local sup = 0
		if difW2 and difW2.actos then
			for act, info in ipairs(difW2.actos) do if info.superado then sup = act end end
		end
		if difW2 and difW2.completo then
			lblProgVal.Text = "CLEARED"
			lblProgVal.TextColor3 = COL.ok
		else
			lblProgVal.Text = string.format("%d / %d ACTS", sup, w.numActos or 0)
			lblProgVal.TextColor3 = COL.texto
		end
	else
		lblTwist.Text = ""
		vaciar(filaDrop)
		for _, p in ipairs(pipsPoder) do p.BackgroundColor3 = Color3.fromRGB(56, 54, 66) end
		lblProgVal.Text = ""
	end

	-- ---- boton de accion ----
	local difW = w and w.dif[selDif]
	local actInfo = difW and difW.actos[selAct]
	local valido = w and w.desbloqueado and difW and difW.desbloqueada and actInfo and actInfo.desbloqueado
	local puedeEmpezar = valido and (esLiderLocal or not enParty) -- co-op: en party, SOLO el lider empieza
	estadoPlay(puedeEmpezar and true or false,
		(enParty and not esLiderLocal) and "WAITING FOR LEADER..." or "PLAY")
	pintarParty()
end

local function elegirDefault()
	selDif = "normal"; selWorld = nil
	for _, w in ipairs(datos.worlds) do
		if w.desbloqueado then selWorld = w; break end
	end
	selWorld = selWorld or datos.worlds[1]
	-- default al SIGUIENTE acto jugable (no siempre al 1) -> no da sensacion de "se me reinicio el progreso"
	selAct = 1
	local difW = selWorld and selWorld.dif[selDif]
	if difW and difW.actos then
		local maxSup = 0
		for act, info in ipairs(difW.actos) do if info.superado then maxSup = act end end
		selAct = math.min(maxSup + 1, #difW.actos)
	end
end

worldsSync.OnClientEvent:Connect(function(d)
	datos = d
	elegirDefault()
	api.abrir() -- enciende el ScreenGui Y marca MenuAbierto (el Hub esconde su columna y su PLAY)
	pintar()
end)

-- El lobby pide abrir el selector (cambia el atributo) -> pedimos datos frescos al servidor.
player:GetAttributeChangedSignal("AbrirMundos"):Connect(function()
	worldsSync:FireServer()
end)

-- Co-op: solo el LIDER puede empezar (el server tambien lo revalida). Actualiza el estado del PLAY.
partySync.OnClientEvent:Connect(function(d)
	esLiderLocal = (d and d.esLider ~= false)
	enParty = (d and d.miembros and #d.miembros > 1) or false
	partyN = (d and d.miembros and #d.miembros) or 1
	partyMax = (d and d.maxParty) or 4
	if api.estaAbierto() then pintar() end
end)

-- Si el teleport co-op falla, reabrir el selector para reintentar. OJO: a quien NUNCA lo abrio (los que no son
-- lider) no le hemos pedido los datos todavia, y abrirlo sin `datos` le dejaba un panel VACIO a pantalla
-- completa, sin mundos y con el PLAY verde que al pulsarlo petaba (selWorld = nil). Solo se reabre si hay datos.
matchError.OnClientEvent:Connect(function()
	if not datos then return end -- sin datos no hay nada que pintar: mejor no tapar la pantalla con un panel vacio
	api.abrir()
	pintar()
end)

-- El aspa de la cabecera ya la cablea UITheme.panel a api.cerrar() (apaga el gui y suelta MenuAbierto).

btnPlay.MouseButton1Click:Connect(function()
	if not btnPlay.Active then return end
	if not selWorld then return end -- guarda: sin mundo seleccionado, indexar selWorld.id lanzaba error
	api.cerrar()
	startMatch:FireServer(selWorld.id, selAct, selDif)
end)

estadoPlay(false, "PLAY")
pintarParty()
