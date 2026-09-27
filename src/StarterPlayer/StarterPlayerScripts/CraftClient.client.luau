-- CraftClient (LocalScript) - Scr - panel FORGE: materiales + reliquias (forjar/subir/equipar).
-- Boton FORGE en el lobby -> pide datos a CraftSync -> pinta. Cada accion avisa al remote Craft
-- (el servidor valida, gasta materiales y revalida). Solo UI.
--
-- === POR QUE ES MAESTRO-DETALLE (y ya no una lista de filas gordas) ===
-- Antes cada fila tenia que contener nombre + descripcion + receta + 2 botones. En movil eso significaba
-- texto de 12px con TextScaled y botones de 24px de alto: por debajo del minimo tactil (44) y con la receta
-- cortada. Ahora la lista de la izquierda solo IDENTIFICA (nombre, rareza, estado) y todo el detalle -- que
-- materiales pide, cuantos tienes, que boton hay -- vive en el panel de la derecha, con sitio de sobra.
-- El mismo esqueleto sirve para las 4 pestanas, asi que la Forja entera se lee igual.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local craft = remotes:WaitForChild("Craft")
local craftSync = remotes:WaitForChild("CraftSync")
local CraftData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("CraftData"))
local PowerData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("PowerData")) -- Evo gating: mapea la receta (power-ids) a nombres
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))

local ACENTO = UITheme.acentos.forge -- el mismo tono que el icono del martillo en la fila del Hub
local OK = UITheme.color.ok
local MAL = UITheme.color.peligro
local ORO = UITheme.color.acento

local MAT = {} -- id -> {nombre,color}
for _, m in ipairs(CraftData.Materiales) do MAT[m.id] = m end

-- Pictograma por material. Se DIBUJAN con Frames (UITheme), nunca emojis: cada movil los pinta con su set y
-- traen su propia paleta, que pelea con la del juego.
local ICONO_MAT = { woods = "rombo", frost = "gema", ember = "rayo", rare = "estrella", dust = "monedas" }

local datos, quiereAbrir = nil, false
local pestana = "relics" -- pestana activa: "relics" | "classes" | "consumibles" | "evos"
local seleccion = {}     -- pestana -> id seleccionado (se conserva entre repintados)
local pintar             -- forward-declared (los botones de pestana lo llaman)

-- (fmtCoste ya no existe: las recetas se pintan linea a linea en el detalle, con "tienes / necesitas" en
-- verde o rojo. Un "8 Verdant Essence  +  2 Ancient Core" en una sola linea obligaba a mirar arriba y restar.)
local function puedePagar(coste, materiales)
	if not coste then return false end
	for mat, n in pairs(coste) do if ((materiales and materiales[mat]) or 0) < n then return false end end
	return true
end
-- Evo gating: la RECETA (2 power-ids) -> nombres legibles ("Incendiary + Giant Bolt")
local function recetaTexto(ids)
	local info = PowerData.infoDe(ids or {})
	local nombres = {}
	for _, c in ipairs(info or {}) do nombres[#nombres + 1] = c.nombre or "?" end
	return table.concat(nombres, " + ")
end
local function gemsActuales()
	local ls = player:FindFirstChild("leaderstats")
	local g = ls and ls:FindFirstChild("Gems")
	return (g and g.Value) or 0
end
local function tengo(matId)
	return (datos and datos.materiales and datos.materiales[matId]) or 0
end

-- Borra el CONTENIDO visible de un contenedor pero respeta UICorner/UIGradient/UIStroke/UIListLayout, que no
-- son GuiObject. Con ClearAllChildren se cargaria el estilo de la placa y habria que repintarlo cada vez.
local function limpiar(f)
	for _, c in ipairs(f:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end

-- ===== Boton FORGE (lobby) =====
local btnGui = Instance.new("ScreenGui")
btnGui.Name = "ForgeButton"; btnGui.ResetOnSpawn = false; btnGui.Parent = playerGui
-- OJO: este boton lo ADOPTA HubClient buscandolo por su .Text EXACTO ("FORGE") entre todos los TextButton del
-- PlayerGui. De ahi dos decisiones:
--   · plano=true -> sin degradado, el texto va en el PROPIO boton. Si el texto viviera en un TextLabel hijo
--     (lo normal cuando hay degradado, porque un UIGradient tine tambien el texto), ese hijo SOBREVIVIRIA a la
--     adopcion y se leeria "FORGE" encima del dibujo del martillo que le mete el Hub.
--   · sin icono ni barra de acento: el Hub le pone los suyos (HubIcono/HubLabel/HubAcento) y se solaparian.
-- Mientras el Hub no lo adopte se ve como una placa de piedra normal, que ya encaja con el resto.
local abrirBtn = UITheme.boton(btnGui, "FORGE", {
	nombre = "ForgeAbrir",
	ancho = 130, alto = UITheme.TACTIL_MIN,
	pos = UDim2.new(0, 14, 0, 172),
	plano = true, tam = 15,
})
local function refrescarBoton() abrirBtn.Visible = not (player:GetAttribute("InMatch") == true) end
player:GetAttributeChangedSignal("InMatch"):Connect(refrescarBoton)
refrescarBoton()

-- ===== Panel =====
local ANCHO_PANEL, ALTO_PANEL = 880, 560 -- 22-jul: mas grande (Bastian: "que sea mas grande, menos apretujada")
local MARGEN = 18
local Y_CONTENIDO = 176
local ALTO_CONTENIDO = ALTO_PANEL - Y_CONTENIDO - 16
local ANCHO_LISTA = 330
local X_DETALLE = MARGEN + ANCHO_LISTA + 16
local ANCHO_DETALLE = ANCHO_PANEL - X_DETALLE - MARGEN

local gui = Instance.new("ScreenGui")
gui.Name = "ForgePanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 63; gui.Enabled = false; gui.Parent = playerGui

-- UITheme.panel ya trae lo que antes estaba a mano aqui: el overlay con Active = true (sin eso el toque
-- ATRAVIESA el fondo y le llega al boton PLAY de debajo -- mismo caso que QuestsClient), el UIScale con el
-- guardia de ViewportSize, y el MenuAbierto con contador (el Hub esconde su columna y el PLAY con ese
-- atributo; antes este panel no lo tocaba y se quedaban flotando encima).
local _overlay, panel, _barra, panelApi, lblTitulo = UITheme.panel(gui, ANCHO_PANEL, ALTO_PANEL, "FORGE", {
	acento = ACENTO,
	clave = "forge",
	velo = 0.5,
})

-- ----- tira de materiales (el "monedero" de la Forja) -----
-- Va arriba del todo y siempre visible: todo lo que se hace en este panel se paga con esto, asi que tenerlo
-- fuera de la vista obligaba a memorizar cuantos Frost Shards tenias mientras leias la receta.
local matRow = Instance.new("Frame")
matRow.Name = "Materiales"
matRow.BackgroundTransparency = 1
matRow.Position = UDim2.new(0, MARGEN, 0, 60)
matRow.Size = UDim2.new(1, -MARGEN * 2, 0, 30)
matRow.Parent = panel
local matLayout = Instance.new("UIListLayout", matRow)
matLayout.FillDirection = Enum.FillDirection.Horizontal
matLayout.Padding = UDim.new(0, 8) -- 10->8: caben los 5 materiales sin desbordar
matLayout.SortOrder = Enum.SortOrder.LayoutOrder
-- Alineadas a la IZQUIERDA, no centradas: centrarlas dejaba dos huecos simetricos a los lados, que es medio
-- kilo del aspecto "plantilla generada".
matLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
matLayout.VerticalAlignment = Enum.VerticalAlignment.Center

-- ----- pestanas -----
local tabRow = Instance.new("Frame")
tabRow.Name = "Pestanas"
tabRow.BackgroundTransparency = 1
tabRow.Position = UDim2.new(0, MARGEN, 0, 98)
tabRow.Size = UDim2.new(1, -MARGEN * 2, 0, UITheme.TACTIL_MIN)
tabRow.Parent = panel
local tl = Instance.new("UIListLayout", tabRow)
tl.FillDirection = Enum.FillDirection.Horizontal
tl.Padding = UDim.new(0, 8)
tl.SortOrder = Enum.SortOrder.LayoutOrder
tl.HorizontalAlignment = Enum.HorizontalAlignment.Left

-- Sin pictograma en las pestanas a proposito: "EVOLUTIONS" a 13px ya come casi los 118 px de la pastilla, y
-- con icono el texto se partiria. El color/identidad lo llevan la barra de acento y el borde de rareza.
local PESTANAS = {
	{ id = "relics", n = "RELICS" },
	{ id = "classes", n = "CLASSES" },
	{ id = "consumibles", n = "POTIONS" },
	{ id = "evos", n = "EVOLUTIONS" },
}
local tabBtns, tabLbls, tabAcentos = {}, {}, {}
for i, t in ipairs(PESTANAS) do
	-- 44 px de alto: minimo tactil en movil (las de antes median 28 y se fallaban con el pulgar).
	local b, lbl = UITheme.boton(tabRow, t.n, {
		nombre = "Tab_" .. t.id,
		ancho = 118, alto = UITheme.TACTIL_MIN, tam = 13,
		layoutOrder = i,
		variante = "apagado",
		-- IMPRESCINDIBLE aqui: sin esto UITheme.boton conecta su propio resalte, y como ese memoriza el color
		-- del momento de creacion (el de pestana APAGADA), al soltar el dedo devolvia el fondo a apagado y
		-- borraba el resalte de la pestana que acababas de activar. El nuestro va justo debajo.
		sinPulsacion = true,
	})
	local acento = UITheme.acentoBarra(b, ACENTO, {
		ancho = 30, alto = 3, pos = UDim2.new(0, 12, 1, -7), anchor = Vector2.new(0, 0), nombre = "TabAcento",
	})
	tabBtns[t.id], tabLbls[t.id], tabAcentos[t.id] = b, lbl, acento
	-- El resalte de UITheme.boton MEMORIZA el color de fondo al crearse, y aqui el fondo cambia al cambiar de
	-- pestana: usando el de serie, al soltar el dedo la pestana activa volveria al color de "apagada". Por eso
	-- el feedback tactil de las pestanas se hace SOLO con la barra de acento, que no depende del estado.
	UITheme.pulsacion(b, function(on)
		local base = (t.id == pestana) and 30 or 14 -- el reposo depende de si ESTA pestana es la activa
		acento.Size = UDim2.fromOffset(on and (base + 14) or base, 3)
	end)
	b.MouseButton1Click:Connect(function() pestana = t.id; if pintar then pintar() end end)
end

UITheme.separador(panel, 152, { izq = MARGEN, margen = MARGEN * 2 })

-- Linea de contexto: una frase corta por pestana. Antes cabia porque las filas eran gordas; ahora es la unica
-- explicacion "de sistema" que hay, asi que se queda pegada bajo el separador.
local hint = UITheme.etiqueta(panel, "", {
	nombre = "Hint",
	fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoTenue,
	pos = UDim2.new(0, MARGEN + 2, 0, 158), tamano = UDim2.new(1, -MARGEN * 2, 0, 14),
})

-- ----- columna izquierda: la lista -----
local lista = UITheme.scroll(panel, {
	nombre = "Lista",
	pos = UDim2.new(0, MARGEN, 0, Y_CONTENIDO),
	tamano = UDim2.fromOffset(ANCHO_LISTA, ALTO_CONTENIDO),
	padding = 7,
})

-- ----- columna derecha: el detalle -----
local detalle = Instance.new("Frame")
detalle.Name = "Detalle"
detalle.Position = UDim2.new(0, X_DETALLE, 0, Y_CONTENIDO)
detalle.Size = UDim2.fromOffset(ANCHO_DETALLE, ALTO_CONTENIDO)
detalle.Parent = panel
UITheme.placa(detalle, {
	fondo = Color3.fromRGB(31, 30, 39), -- un punto MAS HONDO que el panel: hunde el detalle en vez de flotarlo
	alto = Color3.fromRGB(44, 42, 54),
	bajo = Color3.fromRGB(24, 23, 31),
	radio = UITheme.radio.placa,
	bordeTransp = 0.35,
})

-- ===================================================================================================
-- PIEZAS DEL DETALLE
-- ===================================================================================================

-- Una linea de coste: icono + nombre del material + "tienes / necesitas". Verde si llega, rojo si no; asi se
-- ve de un vistazo QUE material te falta, que es la pregunta real del jugador.
local function filaCoste(padre, matId, necesita, y)
	local m = MAT[matId]
	local color = (m and m.color) or UITheme.color.textoSuave
	local hay = tengo(matId)

	local fila = Instance.new("Frame")
	fila.Name = "Coste_" .. matId
	fila.BackgroundTransparency = 1
	fila.Position = UDim2.new(0, 16, 0, y)
	fila.Size = UDim2.new(1, -32, 0, 22)
	fila.Parent = padre

	UITheme.icono(fila, ICONO_MAT[matId] or "gema", color, {
		lado = 16, pos = UDim2.new(0, 0, 0.5, 0), anchor = Vector2.new(0, 0.5),
	})
	UITheme.etiqueta(fila, (m and m.nombre) or matId, {
		fuente = UITheme.fuente.etiqueta, tam = 12, color = UITheme.color.textoSuave,
		pos = UDim2.new(0, 24, 0, 0), tamano = UDim2.new(1, -110, 1, 0),
		alignY = Enum.TextYAlignment.Center,
	})
	UITheme.etiqueta(fila, hay .. " / " .. necesita, {
		fuente = UITheme.fuente.dato, tam = 13, color = (hay >= necesita) and OK or MAL,
		pos = UDim2.new(1, -84, 0, 0), tamano = UDim2.new(0, 84, 1, 0),
		align = Enum.TextXAlignment.Right, alignY = Enum.TextYAlignment.Center,
	})
	return fila
end

-- Bloque de coste completo. Recorre CraftData.Materiales en vez de la receta: pairs() sobre la receta sale en
-- orden ARBITRARIO y las lineas bailaban de sitio entre repintados.
local function bloqueCoste(padre, coste, y, titulo)
	if not coste or not next(coste) then return y end
	UITheme.etiqueta(padre, titulo or "REQUIRED MATERIALS", {
		fuente = UITheme.fuente.etiqueta, tam = 10, color = UITheme.color.textoTenue,
		pos = UDim2.new(0, 16, 0, y), tamano = UDim2.new(1, -32, 0, 12),
	})
	y += 16
	for _, m in ipairs(CraftData.Materiales) do
		local n = coste[m.id]
		if n then
			filaCoste(padre, m.id, n, y)
			y += 24
		end
	end
	return y
end

-- Boton de accion del detalle. 'activo' decide color Y si se conecta: un boton apagado NO lleva handler, asi
-- que aunque el Active se comportara raro en algun dispositivo no se puede disparar una compra imposible.
local function accion(padre, texto, opts)
	opts = opts or {}
	local ancho = opts.ancho or 176
	local btn = UITheme.boton(padre, texto, {
		nombre = "Accion_" .. texto,
		ancho = ancho, alto = UITheme.TACTIL_MIN, tam = 14,
		anchor = Vector2.new(1, 1),
		pos = UDim2.new(1, -(opts.x or 16), 1, -14),
		variante = opts.activo and (opts.variante or "ok") or "apagado",
		acento = opts.activo and (opts.acento or OK) or nil,
		textoColor = opts.activo and UITheme.color.texto or UITheme.color.textoTenue,
	})
	btn.Active = opts.activo and true or false
	if opts.activo and opts.alPulsar then btn.MouseButton1Click:Connect(function() SoundManager.play("pickup"); opts.alPulsar() end) end -- 22-jul: sfx al craftear/subir/equipar/desequipar (Bastian)
	return btn
end

-- Cabecera del detalle: tick de rareza + nombre + linea de estado. El titulo va a la IZQUIERDA con el tick
-- delante (igual que la barra del panel), no centrado: centrarlo todo es el tic de UI generada.
local function cabeceraDetalle(nombre, sub, color)
	local tick = UITheme.pieza(detalle, 4, 22, 0, 0, color, 2)
	tick.AnchorPoint = Vector2.new(0, 0)
	tick.Position = UDim2.new(0, 16, 0, 16)

	UITheme.etiqueta(detalle, nombre, {
		nombre = "TituloDetalle",
		fuente = UITheme.fuente.titulo, tam = 19, color = UITheme.color.texto,
		pos = UDim2.new(0, 30, 0, 14), tamano = UDim2.new(1, -46, 0, 24),
	})
	UITheme.etiqueta(detalle, sub or "", {
		nombre = "SubDetalle",
		fuente = UITheme.fuente.dato, tam = 11, color = color,
		pos = UDim2.new(0, 30, 0, 38), tamano = UDim2.new(1, -46, 0, 14),
	})
	UITheme.separador(detalle, 60, { izq = 16, margen = 32 })
end

local function descDetalle(texto, y, alto)
	return UITheme.etiqueta(detalle, texto or "", {
		nombre = "DescDetalle",
		fuente = UITheme.fuente.etiqueta, tam = 13, color = UITheme.color.textoSuave,
		pos = UDim2.new(0, 16, 0, y or 72), tamano = UDim2.new(1, -32, 0, alto or 40),
		wrap = true, alignY = Enum.TextYAlignment.Top,
	})
end

local function detalleVacio(texto)
	UITheme.etiqueta(detalle, texto, {
		fuente = UITheme.fuente.dato, tam = 13, color = UITheme.color.textoTenue,
		pos = UDim2.new(0, 24, 0.5, -30), tamano = UDim2.new(1, -48, 0, 60),
		wrap = true, align = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Center,
	})
end

-- ===================================================================================================
-- FILA DE LA LISTA
-- ===================================================================================================
-- El borde de RAREZA es el codigo de color de todo el juego, asi que la lista se puede leer por color sin
-- leer el texto. La fila mide 58 px (por encima del minimo tactil de 44) porque en movil se recorre con el
-- pulgar en vertical y las filas cortas se fallan.
local function filaLista(id, nombre, sub, color, estado, orden, puede)
	local activa = (seleccion[pestana] == id)

	local b = Instance.new("TextButton")
	b.Name = "Fila_" .. tostring(id)
	-- .Text VACIO a proposito: HubClient adopta botones del lobby buscando por .Text exacto entre TODOS los
	-- TextButton del PlayerGui. Un texto suelto aqui podria robarle el boton de la columna.
	b.Text = ""
	b.AutoButtonColor = false
	b.Size = UDim2.new(1, -6, 0, 58)
	b.LayoutOrder = orden
	b.ClipsDescendants = true
	b.Parent = lista

	-- Fondo segun ESTADO DE CRAFTEO (Bastian: "verde si puedes, gris si no"): se lee de un vistazo que puedes
	-- forjar/subir AHORA (verde) y que no te llega el material (gris apagado). La RAREZA sigue en el stroke +
	-- la barra izquierda cuando el estado es neutro (equipada/max/otra pestana).
	local fondo, alto
	if activa then fondo, alto = Color3.fromRGB(50, 48, 61), Color3.fromRGB(64, 61, 77)
	elseif puede == true then fondo, alto = Color3.fromRGB(28, 46, 32), Color3.fromRGB(40, 62, 44)   -- PUEDES: verde
	elseif puede == false then fondo, alto = Color3.fromRGB(24, 23, 28), Color3.fromRGB(30, 29, 35)  -- NO PUEDES: gris apagado
	else fondo, alto = UITheme.color.fondoPlaca, UITheme.color.placaAlta end
	UITheme.placa(b, { fondo = fondo, alto = alto, bajo = UITheme.color.placaBaja, radio = UITheme.radio.tarjeta, sinBorde = true })
	-- stroke = RAREZA (fino). Si PUEDES craftear, verde y algo mas marcado para que "invite".
	local st = Instance.new("UIStroke")
	st.Color = (puede == true) and OK or color
	st.Thickness = (activa or puede == true) and 2 or 1.5
	st.Transparency = (activa or puede == true) and 0.1 or (puede == false and 0.7 or 0.55)
	st.Parent = b
	-- Barra vertical izquierda: verde (puedes) / gris (no) / rareza (neutro). No cruza la esquina redondeada.
	local barColor = (puede == true and OK) or (puede == false and UITheme.color.apagado) or color
	local barra = UITheme.pieza(b, (activa or puede == true) and 4 or 2, 30, 0, 0.5, barColor, 1)
	barra.AnchorPoint = Vector2.new(0, 0.5)
	barra.Position = UDim2.new(0, 0, 0.5, 0)

	UITheme.etiqueta(b, nombre, {
		fuente = UITheme.fuente.dato, tam = 15, color = activa and UITheme.color.texto or UITheme.color.textoSuave,
		pos = UDim2.new(0, 14, 0, 9), tamano = UDim2.new(1, -80, 0, 20),
	})
	UITheme.etiqueta(b, sub or "", {
		fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoTenue,
		pos = UDim2.new(0, 14, 0, 31), tamano = UDim2.new(1, -80, 0, 16),
	})
	if estado and estado ~= "" then
		UITheme.etiqueta(b, estado, {
			fuente = UITheme.fuente.dato, tam = 10, color = color,
			pos = UDim2.new(1, -70, 0, 10), tamano = UDim2.new(0, 58, 0, 16),
			align = Enum.TextXAlignment.Right,
		})
	end

	UITheme.pulsacion(b)
	b.MouseButton1Click:Connect(function()
		seleccion[pestana] = id
		pintar()
	end)
	return b
end

-- ===================================================================================================
-- DETALLES POR PESTANA
-- ===================================================================================================

local function detalleReliquia(r)
	local color = UITheme.colorRareza(r.rareza)
	local nEq = #(datos.equipadas or {})
	local slots = datos.slots or 3

	local estado
	if r.level == 0 then estado = "Not forged"
	elseif r.equipada then estado = "Equipped"
	else estado = "In stash" end
	cabeceraDetalle(r.nombre, r.rareza .. "  -  " .. (r.level > 0 and ("Level " .. r.level .. "/" .. r.maxNivel) or "Level 0") .. "  -  " .. estado, color)
	descDetalle(r.desc, 72, 40)

	if r.level == 0 then
		local ok = puedePagar(r.receta, datos.materiales)
		bloqueCoste(detalle, r.receta, 118, "FORGE COST")
		-- El texto NO puede ser "FORGE" a secas: HubClient adopta el boton del lobby buscando ese .Text exacto
		-- por todo el PlayerGui, y este boton se recrea cada repintado. Le robaria el sitio en la columna.
		accion(detalle, "FORGE RELIC", { activo = ok, alPulsar = function() craft:FireServer("forge", r.id) end })
	elseif r.level < r.maxNivel then
		local ok = puedePagar(r.costeSubir, datos.materiales)
		bloqueCoste(detalle, r.costeSubir, 118, "NEXT LEVEL COST")
		accion(detalle, "LEVEL UP", { activo = ok, acento = ORO, alPulsar = function() craft:FireServer("levelup", r.id) end })
	else
		UITheme.etiqueta(detalle, "MAX LEVEL", {
			fuente = UITheme.fuente.titulo, tam = 15, color = ORO,
			pos = UDim2.new(0, 16, 0, 122), tamano = UDim2.new(1, -32, 0, 20),
		})
		accion(detalle, "MAXED", { activo = false })
	end

	if r.level > 0 then
		if r.equipada then
			accion(detalle, "UNEQUIP", {
				ancho = 150, x = 200, activo = true, variante = "normal", acento = UITheme.color.textoTenue,
				alPulsar = function() craft:FireServer("unequip", r.id) end,
			})
		else
			local hueco = nEq < slots
			accion(detalle, hueco and "EQUIP" or "NO SLOTS", {
				ancho = 150, x = 200, activo = hueco, variante = "normal", acento = ACENTO,
				alPulsar = function() craft:FireServer("equip", r.id) end,
			})
		end
	end
end

local function detalleClase(c)
	local color = c.color or UITheme.color.texto
	cabeceraDetalle(c.nombre, "Level " .. c.nivel .. " / " .. c.max, color)
	descDetalle(c.pasivaDesc or "", 72, 40)

	if c.nivel < c.max then
		UITheme.etiqueta(detalle, "SHARDS", {
			fuente = UITheme.fuente.etiqueta, tam = 10, color = UITheme.color.textoTenue,
			pos = UDim2.new(0, 16, 0, 116), tamano = UDim2.new(1, -32, 0, 12),
		})
		UITheme.etiqueta(detalle, c.shards .. " / " .. tostring(c.costoSubir or "?"), {
			fuente = UITheme.fuente.dato, tam = 15, color = (c.costoSubir and c.shards >= c.costoSubir) and OK or UITheme.color.texto,
			pos = UDim2.new(0, 16, 0, 130), tamano = UDim2.new(1, -32, 0, 20),
		})
		-- Barra de progreso de shards: un numero "3 / 5" se entiende, pero la barra dice de un vistazo si estas
		-- a un shard o a diez del siguiente nivel.
		local pista = Instance.new("Frame")
		pista.BackgroundColor3 = Color3.fromRGB(24, 23, 31)
		pista.BorderSizePixel = 0
		pista.Position = UDim2.new(0, 16, 0, 154)
		pista.Size = UDim2.new(1, -32, 0, 6)
		pista.Parent = detalle
		Instance.new("UICorner", pista).CornerRadius = UDim.new(1, 0)
		local frac = math.clamp(c.shards / math.max(1, c.costoSubir or 1), 0, 1)
		local relleno = Instance.new("Frame")
		relleno.BackgroundColor3 = color
		relleno.BorderSizePixel = 0
		relleno.Size = UDim2.new(frac, 0, 1, 0)
		relleno.Parent = pista
		Instance.new("UICorner", relleno).CornerRadius = UDim.new(1, 0)

		local ok = puedePagar(c.costoShard, datos.materiales)
		bloqueCoste(detalle, c.costoShard, 174, "COST PER SHARD")
		accion(detalle, "CRAFT SHARD", { activo = ok, alPulsar = function() craft:FireServer("shard", c.id) end })
	else
		UITheme.etiqueta(detalle, "MAX LEVEL", {
			fuente = UITheme.fuente.titulo, tam = 15, color = ORO,
			pos = UDim2.new(0, 16, 0, 122), tamano = UDim2.new(1, -32, 0, 20),
		})
		accion(detalle, "MAXED", { activo = false })
	end
end

local function detalleConsumible(c)
	local color = UITheme.rareza.raro
	cabeceraDetalle(c.nombre, "You own " .. c.count .. (c.usar and "   -   Taken to next run" or ""), c.usar and ORO or color)
	descDetalle(c.desc, 72, 36)

	local ok = puedePagar(c.receta, datos.materiales)
	bloqueCoste(detalle, c.receta, 116, "CRAFT COST")
	accion(detalle, "CRAFT", { ancho = 150, activo = ok, alPulsar = function() craft:FireServer("consumible", c.id) end })
	-- USE es un toggle del servidor: se deja SIEMPRE pulsable (aunque tengas 0) porque el servidor es quien
	-- valida, y desmarcar una pocion que ya llevabas tiene que poder hacerse pase lo que pase.
	accion(detalle, c.usar and "USING" or "USE", {
		ancho = 150, x = 174, activo = true,
		variante = "normal", acento = c.usar and ORO or UITheme.color.textoTenue,
		alPulsar = function() craft:FireServer("usar", c.id) end,
	})
end

local function detalleEvo(e)
	local color = e.color or UITheme.rareza.legendario
	local estado
	if e.desbloqueada then estado = "Unlocked"
	elseif e.regalo then estado = "Free reward"
	elseif not e.tieneClase then estado = "Class not owned"
	else estado = "Locked" end
	cabeceraDetalle(e.nombre, e.clase .. "  -  " .. estado, color)

	UITheme.etiqueta(detalle, "IN-RUN RECIPE", {
		fuente = UITheme.fuente.etiqueta, tam = 10, color = UITheme.color.textoTenue,
		pos = UDim2.new(0, 16, 0, 70), tamano = UDim2.new(1, -32, 0, 12),
	})
	UITheme.etiqueta(detalle, recetaTexto(e.receta), {
		fuente = UITheme.fuente.dato, tam = 13, color = ORO,
		pos = UDim2.new(0, 16, 0, 84), tamano = UDim2.new(1, -32, 0, 18),
	})
	descDetalle(e.desc or "", 106, 34)

	if e.desbloqueada then
		UITheme.etiqueta(detalle, "UNLOCKED", {
			fuente = UITheme.fuente.titulo, tam = 16, color = OK,
			pos = UDim2.new(0, 16, 0, 150), tamano = UDim2.new(1, -32, 0, 22),
		})
		return
	end
	if e.regalo then
		UITheme.etiqueta(detalle, "Beat World 1 to unlock it for free.", {
			fuente = UITheme.fuente.dato, tam = 13, color = UITheme.color.textoSuave,
			pos = UDim2.new(0, 16, 0, 150), tamano = UDim2.new(1, -32, 0, 36), wrap = true,
		})
		return
	end
	if not e.tieneClase then
		UITheme.etiqueta(detalle, "Own " .. e.clase .. " first (pull it in CLASSES).", {
			fuente = UITheme.fuente.dato, tam = 13, color = Color3.fromRGB(190, 160, 160),
			pos = UDim2.new(0, 16, 0, 150), tamano = UDim2.new(1, -32, 0, 36), wrap = true,
		})
		return
	end

	local okC = puedePagar(e.recetaMat, datos.materiales)
	-- El bloque empieza en 112 y no en 146 por una cuenta que se me fue: TODAS las evoluciones piden los 4
	-- materiales, asi que bloqueCoste pinta titulo + 4 filas = 16 + 4*24 = 112 px de alto. Arrancando en 146
	-- la ultima fila llegaba a 256, y ahi abajo ya estan la linea de GEMS (y=234, porque el alto util son 308)
	-- y los botones (y=250): se pintaba encima de las dos. Con 112 termina en 222 y todo respira.
	bloqueCoste(detalle, e.recetaMat, 112, "UNLOCK WITH MATERIALS")

	local gems = gemsActuales()
	local coste = e.costeGems or math.huge
	local okG = gems >= coste
	-- Dos caminos al mismo desbloqueo: gemas (atajo de pago) o materiales (juego). Se pintan a la par para que
	-- se vea que hay alternativa gratis, no solo el boton de la tienda.
	UITheme.etiqueta(detalle, "GEMS  " .. gems .. " / " .. tostring(e.costeGems or "?"), {
		fuente = UITheme.fuente.dato, tam = 11, color = okG and OK or MAL,
		pos = UDim2.new(0, 16, 1, -74), tamano = UDim2.new(1, -32, 0, 14),
	})
	accion(detalle, "CRAFT", { ancho = 150, activo = okC, alPulsar = function() craft:FireServer("evo", e.id, "craft") end })
	accion(detalle, "UNLOCK WITH GEMS", {
		ancho = 176, x = 174, activo = okG,
		variante = "normal", acento = UITheme.acentos.classes,
		alPulsar = function() craft:FireServer("evo", e.id, "gems") end,
	})
end

-- ===================================================================================================
-- PINTADO
-- ===================================================================================================
pintar = function()
	if not datos then return end

	-- tira de materiales
	limpiar(matRow)
	for i, m in ipairs(CraftData.Materiales) do
		local pill = Instance.new("Frame")
		pill.Name = "Mat_" .. m.id
		pill.Size = UDim2.fromOffset(158, 30) -- 168->158: con 5 materiales (se anadio Dust) 5x168 desbordaba el panel
		pill.LayoutOrder = i
		pill.Parent = matRow
		UITheme.placa(pill, { radio = UITheme.radio.pildora, bordeTransp = 0.45 })
		UITheme.icono(pill, ICONO_MAT[m.id] or "gema", m.color, {
			lado = 16, pos = UDim2.new(0, 10, 0.5, 0), anchor = Vector2.new(0, 0.5),
		})
		UITheme.etiqueta(pill, m.nombre, {
			fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoTenue,
			pos = UDim2.new(0, 30, 0, 0), tamano = UDim2.new(1, -76, 1, 0),
			alignY = Enum.TextYAlignment.Center,
		})
		UITheme.etiqueta(pill, tostring(tengo(m.id)), {
			fuente = UITheme.fuente.dato, tam = 14, color = m.color,
			pos = UDim2.new(1, -46, 0, 0), tamano = UDim2.new(0, 36, 1, 0),
			align = Enum.TextXAlignment.Right, alignY = Enum.TextYAlignment.Center,
		})
	end

	-- pestanas
	for _, t in ipairs(PESTANAS) do
		local activa = (t.id == pestana)
		UITheme.placa(tabBtns[t.id], {
			fondo = activa and Color3.fromRGB(48, 44, 52) or Color3.fromRGB(32, 31, 38),
			alto = activa and Color3.fromRGB(64, 58, 66) or Color3.fromRGB(42, 41, 50),
			bajo = activa and Color3.fromRGB(28, 26, 32) or Color3.fromRGB(24, 23, 30),
			radio = UITheme.radio.boton, bordeTransp = 0.3,
		})
		tabLbls[t.id].TextColor3 = activa and UITheme.color.texto or UITheme.color.textoTenue
		tabAcentos[t.id].BackgroundTransparency = activa and 0 or 0.75
		tabAcentos[t.id].Size = UDim2.fromOffset(activa and 30 or 14, 3)
	end

	local nEq = #(datos.equipadas or {})
	local titulos = { relics = "RELICS", classes = "CLASSES", consumibles = "POTIONS", evos = "EVOLUTIONS" }
	lblTitulo.Text = "FORGE  -  " .. (titulos[pestana] or "")

	-- fuente de datos + como se dibuja cada fila, por pestana
	local items, pintarDetalle
	if pestana == "classes" then
		items = datos.clases or {}
		hint.Text = "Craft shards with materials to level your classes (complements the gacha)."
		pintarDetalle = detalleClase
	elseif pestana == "consumibles" then
		items = datos.consumibles or {}
		hint.Text = "Craft potions; toggle USE to bring them to your next run (consumed on start)."
		pintarDetalle = detalleConsumible
	elseif pestana == "evos" then
		items = datos.evos or {}
		hint.Text = "In a run the golden card only appears from team level " .. tostring(Config.MinEvoLevel) .. "."
		pintarDetalle = detalleEvo
	else
		items = datos.reliquias or {}
		hint.Text = "Relics give permanent bonuses every run.  Equipped: " .. nEq .. " / " .. (datos.slots or 3)
		pintarDetalle = detalleReliquia
	end

	-- La seleccion se conserva entre repintados (cada accion provoca un sync del servidor y un repintado
	-- completo: sin esto la Forja te devolveria al primer elemento cada vez que forjas algo).
	local sigueValido = false
	for _, it in ipairs(items) do if it.id == seleccion[pestana] then sigueValido = true end end
	if not sigueValido then seleccion[pestana] = items[1] and items[1].id or nil end

	limpiar(lista)
	limpiar(detalle)

	for i, it in ipairs(items) do
		if pestana == "classes" then
			filaLista(it.id, it.nombre, "Level " .. it.nivel .. " / " .. it.max, it.color or UITheme.color.texto,
				it.nivel >= it.max and "MAX" or nil, i)
		elseif pestana == "consumibles" then
			filaLista(it.id, it.nombre, "You own " .. it.count, it.usar and ORO or UITheme.rareza.raro,
				it.usar and "IN RUN" or nil, i, puedePagar(it.receta, datos.materiales))
		elseif pestana == "evos" then
			local estado = it.desbloqueada and "OWNED" or (it.regalo and "FREE" or (not it.tieneClase and "LOCKED" or nil))
			filaLista(it.id, it.nombre, it.clase, it.color or UITheme.rareza.legendario, estado, i)
		else
			local sub = (it.level > 0) and ("Level " .. it.level .. " / " .. it.maxNivel) or "Not forged"
			local puede -- verde si puedes forjar (nivel 0) o subir (nivel>0<max) AHORA; gris si no llega el material
			if it.level == 0 then puede = puedePagar(it.receta, datos.materiales)
			elseif it.level < it.maxNivel then puede = puedePagar(it.costeSubir, datos.materiales) end
			filaLista(it.id, it.nombre, sub, UITheme.colorRareza(it.rareza), it.equipada and "EQUIPPED" or nil, i, puede)
		end
	end

	local sel
	for _, it in ipairs(items) do if it.id == seleccion[pestana] then sel = it end end
	if sel then
		pintarDetalle(sel)
	elseif pestana == "classes" then
		detalleVacio("You don't own any class yet.\nPull one in CLASSES / GACHA.")
	else
		detalleVacio("Nothing here yet.")
	end
end

-- ===================================================================================================
-- REMOTES  ·  el contrato con el servidor (NO se toca)
-- ===================================================================================================
craftSync.OnClientEvent:Connect(function(d)
	datos = d
	if quiereAbrir then quiereAbrir = false; panelApi.abrir() end
	if panelApi.estaAbierto() then pintar() end
end)
-- Se abre SOLO cuando llegan los datos (quiereAbrir): abrir antes ensenaria un panel vacio medio segundo.
abrirBtn.MouseButton1Click:Connect(function() quiereAbrir = true; craft:FireServer() end)

-- Si arranca la partida con la Forja abierta, se cierra. Por api.cerrar(), que ademas apaga el MenuAbierto:
-- dejarlo puesto tenia al Hub escondiendo su columna y el PLAY durante toda la run.
player:GetAttributeChangedSignal("InMatch"):Connect(function()
	if player:GetAttribute("InMatch") == true and panelApi.estaAbierto() then
		quiereAbrir = false
		panelApi.cerrar()
	end
end)
