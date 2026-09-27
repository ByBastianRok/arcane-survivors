--!nolint LocalShadow
-- UITheme (ModuleScript) - EL lenguaje visual del juego, en un solo sitio.
--
-- === POR QUE EXISTE ===
-- Cada menu se escribio por separado y cada uno invento su propia paleta: la Forja usa rgb(22,22,32) con un
-- stroke rgb(80,80,110), el Hub usa rgb(38,37,47) con stroke rgb(12,11,16), el gacha otra cosa... Resultado:
-- ocho panteles que no parecen del mismo juego. Este modulo EXTRAE lo que ya se hizo bien en
-- HubClient.client.luau (la placa de piedra: fondo oscuro + degradado vertical de bisel + stroke oscuro +
-- barra de acento fina) y lo da hecho, para que un menu nuevo no tenga que decidir NADA de estilo.
--
-- === REGLAS QUE ESTE MODULO HACE CUMPLIR SOLO ===
--   · Texto de cara al jugador en INGLES (lo pone quien llama; aqui no hay copy salvo el vacio).
--   · CERO emojis: todo pictograma se DIBUJA con Frames (ver seccion DIBUJOS).
--   · Un UIGradient en un TextButton tine TAMBIEN su texto -> boton() mete el texto visible en un TextLabel
--     hijo, pero DEJA .Text puesto con TextTransparency=1, porque HubClient adopta los botones del lobby
--     buscandolos por su .Text EXACTO. Si lo vaciaramos, el boton desapareceria de la columna del lobby.
--   · Movil: area tactil minima 44 px (boton() lo fuerza salvo opts.compacto).
--   · Nada por encima de y=52 (barra de Roblox) -> UITheme.SEGURO_ARRIBA.
--   · El cuadrante inferior IZQUIERDO es del joystick: no pongas ahi nada tocable.
--   · Panel a pantalla completa -> su fondo lleva Active=true, si no los clics lo atraviesan.
--   · Al abrir/cerrar panel hay que tocar el atributo MenuAbierto del jugador -> UITheme.marcarMenu()
--     (con CONTADOR: dos paneles abiertos y cerrar uno ya no apaga el flag del otro).
--
-- === ANTI-SLOP ===
-- Lo que canta a UI generada: todo simetrico, color plano con filo de neon, el MISMO radio de esquina en todo,
-- emojis, y elementos a distancias exactamente iguales. Por eso aqui:
--   · el radio de esquina CAMBIA segun el papel (panel 14 / placa 10 / boton 9 / tarjeta 7),
--   · el titulo del panel va a la IZQUIERDA con un tick de acento delante, no centrado,
--   · el separador bajo el titulo no llega a los bordes,
--   · el color saturado solo sale en barras finas, pictogramas y bordes de rareza. Nunca de fondo grande.
--
-- Se puede require() desde el servidor sin petar (solo marcarMenu() necesita LocalPlayer y se protege).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UITheme = {}

-- ===================================================================================================
-- PALETA
-- ===================================================================================================
UITheme.color = {
	fondo       = Color3.fromRGB(20, 19, 27),   -- lo mas hondo: fondo de panel / velo
	fondoPlaca  = Color3.fromRGB(38, 37, 47),   -- la placa de piedra (el color base del Hub)
	placaAlta   = Color3.fromRGB(58, 56, 70),   -- arriba del degradado (luz)
	placaBaja   = Color3.fromRGB(28, 27, 35),   -- abajo del degradado (sombra)
	borde       = Color3.fromRGB(12, 11, 16),   -- stroke OSCURO, nunca saturado
	texto       = Color3.fromRGB(240, 243, 252),
	textoTenue  = Color3.fromRGB(152, 157, 172),
	textoSuave  = Color3.fromRGB(198, 202, 214), -- etiquetas bajo iconos (el idle del Hub)
	acento      = Color3.fromRGB(214, 170, 72),  -- oro apagado: el acento global de fantasia
	peligro     = Color3.fromRGB(198, 74, 68),
	ok          = Color3.fromRGB(92, 186, 108),
	apagado     = Color3.fromRGB(74, 72, 88),    -- bloqueado / no disponible
	-- IDENTIDAD DE MONEDA (fuente unica): cada moneda un color y SIEMPRE el mismo, en todas las pantallas.
	-- Antes cada panel inventaba el suyo (Gems salia morado en Store, azul en Perks, verde en el saldo...).
	gemas       = Color3.fromRGB(170, 130, 250),  -- MORADO de Gems (premium/Robux) = el tono del Gacha (el mas extendido)
	cash        = Color3.fromRGB(120, 230, 150),  -- VERDE de Cash (moneda blanda) = el saldo del lobby
	coins       = Color3.fromRGB(255, 205, 80),   -- ORO de Coins (moneda temporal de la run)
}

-- Los 6 tonos de las entradas del Hub, por si un panel quiere seguir el color de SU feature.
UITheme.acentos = {
	quests  = Color3.fromRGB(206, 166, 74),
	classes = Color3.fromRGB(148, 104, 214),
	forge   = Color3.fromRGB(196, 106, 76),
	perks   = Color3.fromRGB(88, 190, 178),
	store   = Color3.fromRGB(226, 178, 70),
	profile = Color3.fromRGB(96, 148, 220),
}

UITheme.rareza = {
	comun      = Color3.fromRGB(150, 155, 165),
	raro       = Color3.fromRGB(80, 150, 220),
	epico      = Color3.fromRGB(160, 100, 220),
	legendario = Color3.fromRGB(230, 175, 60),
}
-- Alias en ingles/CamelCase: los datos guardan "Common"/"Rare"/"Epic"/"Legendary".
UITheme.rarezaAlias = {
	Common = "comun", Rare = "raro", Epic = "epico", Legendary = "legendario",
	common = "comun", rare = "raro", epic = "epico", legendary = "legendario",
}

UITheme.fuente = {
	titulo    = Enum.Font.GothamBlack,
	dato      = Enum.Font.GothamBold,
	etiqueta  = Enum.Font.GothamMedium,
}

UITheme.radio = { panel = 14, placa = 10, boton = 9, tarjeta = 7, pildora = 999 }
UITheme.SEGURO_ARRIBA = 52 -- px reservados arriba: ahi vive la barra de Roblox
UITheme.TACTIL_MIN = 44    -- px: area tactil minima en movil

-- rareza("Epic") / rareza("epico") / rareza(Color3) -> Color3. Nunca devuelve nil.
function UITheme.colorRareza(r)
	if typeof(r) == "Color3" then return r end
	if type(r) == "string" then
		local clave = UITheme.rarezaAlias[r] or string.lower(r)
		if UITheme.rareza[clave] then return UITheme.rareza[clave] end
	end
	return UITheme.rareza.comun
end

-- Mezcla hacia blanco (f>0) o hacia el negro de la paleta (f<0). Todos los pictogramas se pintan a partir del
-- color de su entrada, asi cada uno tiene su tono y todos comparten el mismo lenguaje.
function UITheme.tono(c, f)
	if f >= 0 then return c:Lerp(Color3.new(1, 1, 1), f) end
	return c:Lerp(Color3.fromRGB(18, 17, 24), -f)
end
local tono = UITheme.tono

-- ===================================================================================================
-- PIEZAS BASE
-- ===================================================================================================

-- Rectangulo posicionado por su CENTRO, en escala 0..1 de la caja. radio>0 = redondeado, radio<0 = pildora.
-- Es la primitiva con la que estan hechos TODOS los pictogramas (copiada tal cual de HubClient).
function UITheme.pieza(padre, ancho, alto, cx, cy, color, radio, giro)
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
local pieza = UITheme.pieza

-- ===================================================================================================
-- PLACA  ·  el ladrillo del que sale todo lo demas
-- ===================================================================================================
-- Convierte cualquier GuiObject en la placa de piedra: fondo + degradado vertical (bisel) + stroke oscuro +
-- esquina. Es IDEMPOTENTE (reusa el UICorner/UIGradient/UIStroke que ya hubiera), asi que se puede llamar
-- sobre un boton que ya existe -- que es justo lo que hace HubClient al adoptar los botones del lobby.
--
-- opts (todo opcional):
--   fondo=Color3 · alto=Color3 · bajo=Color3 · borde=Color3 · grosor=number · bordeTransp=number
--   radio=number · rotacion=number(grados del gradiente, 90=vertical) · sinGradiente=bool · sinBorde=bool
function UITheme.placa(gui, opts)
	opts = opts or {}
	gui.BackgroundColor3 = opts.fondo or UITheme.color.fondoPlaca
	gui.BackgroundTransparency = opts.transparencia or 0
	gui.BorderSizePixel = 0
	if gui:IsA("TextButton") or gui:IsA("ImageButton") then
		gui.AutoButtonColor = false -- pelea con el degradado: el resalte se hace a mano
	end

	local c = gui:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, opts.radio or UITheme.radio.placa)
	c.Parent = gui

	if opts.sinGradiente then
		-- idempotencia: si antes hubo degradado y ahora se pide plano, hay que quitarlo (si no, seguiria
		-- tiñendo el texto del boton)
		local viejo = gui:FindFirstChildOfClass("UIGradient")
		if viejo then viejo:Destroy() end
	else
		local g = gui:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
		g.Color = ColorSequence.new(opts.alto or UITheme.color.placaAlta, opts.bajo or UITheme.color.placaBaja)
		g.Rotation = opts.rotacion or 90
		g.Parent = gui
	end

	if not opts.sinBorde then
		local s = gui:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		s.Color = opts.borde or UITheme.color.borde
		s.Thickness = opts.grosor or 2
		s.Transparency = opts.bordeTransp or 0.25
		s.Parent = gui
	end
	return gui
end

-- Barra fina de acento (el UNICO sitio donde el color sale a saco). Devuelve el Frame.
-- opts: ancho=26 · alto=3 · pos=UDim2 · anchor=Vector2 · nombre=string
function UITheme.acentoBarra(padre, color, opts)
	opts = opts or {}
	local b = padre:FindFirstChild(opts.nombre or "Acento") or Instance.new("Frame")
	b.Name = opts.nombre or "Acento"
	b.Size = UDim2.fromOffset(opts.ancho or 26, opts.alto or 3)
	b.Position = opts.pos or UDim2.new(0.5, 0, 1, -9)
	b.AnchorPoint = opts.anchor or Vector2.new(0.5, 0)
	b.BackgroundColor3 = color or UITheme.color.acento
	b.BorderSizePixel = 0
	b.Parent = padre
	local c = b:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0); c.Parent = b
	return b
end

-- Linea separadora. NO llega a los bordes a proposito (simetria perfecta = look de plantilla).
function UITheme.separador(padre, y, opts)
	opts = opts or {}
	local l = Instance.new("Frame")
	l.Size = UDim2.new(1, -(opts.margen or 44), 0, 1)
	l.Position = UDim2.new(0, opts.izq or 20, 0, y)
	l.BackgroundColor3 = opts.color or UITheme.color.placaAlta
	l.BackgroundTransparency = opts.transparencia or 0.35
	l.BorderSizePixel = 0
	l.Parent = padre
	return l
end

-- TextLabel con las fuentes del juego ya puestas.
-- opts: fuente(Enum.Font) · tam=14 · color=Color3 · pos=UDim2 · tamano=UDim2 · anchor · align(Left/Center/Right)
--       alignY · wrap=bool · layoutOrder · nombre
function UITheme.etiqueta(padre, texto, opts)
	opts = opts or {}
	local l = Instance.new("TextLabel")
	l.Name = opts.nombre or "Etiqueta"
	l.BackgroundTransparency = 1
	l.Size = opts.tamano or UDim2.new(1, 0, 0, opts.altoLinea or 18)
	l.Position = opts.pos or UDim2.new(0, 0, 0, 0)
	if opts.anchor then l.AnchorPoint = opts.anchor end
	l.Font = opts.fuente or UITheme.fuente.etiqueta
	l.TextSize = opts.tam or 14
	l.TextColor3 = opts.color or UITheme.color.textoSuave
	l.TextXAlignment = opts.align or Enum.TextXAlignment.Left
	if opts.alignY then l.TextYAlignment = opts.alignY end
	l.TextWrapped = opts.wrap == true
	l.RichText = opts.rich == true
	l.LayoutOrder = opts.layoutOrder or 0
	l.Text = texto or ""
	l.Parent = padre
	return l
end

-- ===================================================================================================
-- PICTOGRAMAS  ·  dibujados con Frames. CERO emojis (cada movil los pinta con su set y traen su paleta).
-- ===================================================================================================
local DIBUJOS = {}

function DIBUJOS.pergamino(caja, col) -- QUESTS: hoja con renglones
	pieza(caja, 19, 23, 0.5, 0.5, tono(col, 0.55), 3)
	pieza(caja, 19, 5, 0.5, 0.19, tono(col, 0.1), 3)
	for i, y in ipairs({ 0.45, 0.6, 0.75 }) do
		pieza(caja, i == 3 and 7 or 11, 2, i == 3 and 0.38 or 0.5, y, tono(col, -0.45), 1)
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
	pieza(caja, 13, 3, 0.5, 0.9, tono(col, -0.55), -1) -- peana
end

function DIBUJOS.martillo(caja, col) -- FORGE: martillo inclinado
	pieza(caja, 4, 21, 0.56, 0.58, Color3.fromRGB(126, 92, 58), 2, -38)
	pieza(caja, 15, 9, 0.36, 0.32, tono(col, 0.25), 2, -38)
	pieza(caja, 5, 9, 0.29, 0.35, tono(col, -0.3), 1, -38)
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

function DIBUJOS.busto(caja, col) -- PLAYER INFO: cabeza y hombros (la caja recorta por abajo)
	pieza(caja, 11, 11, 0.5, 0.3, tono(col, 0.35), -1)
	pieza(caja, 21, 15, 0.5, 0.87, tono(col, 0.05), -1)
end

-- ---- nuevos ----

function DIBUJOS.candado(caja, col) -- bloqueado: arco + cuerpo + bocallave
	pieza(caja, 14, 14, 0.5, 0.33, tono(col, -0.15), 7)         -- arco (aro)
	pieza(caja, 8, 9, 0.5, 0.36, Color3.fromRGB(30, 29, 38), 4) -- hueco del arco
	local cuerpo = pieza(caja, 20, 15, 0.5, 0.66, tono(col, 0.3), 3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(tono(col, 0.5), tono(col, -0.2))
	g.Rotation = 90
	g.Parent = cuerpo
	pieza(caja, 3, 6, 0.5, 0.69, tono(col, -0.55), 1) -- bocallave
end

function DIBUJOS.calavera(caja, col) -- muerte / peligro / jefe
	pieza(caja, 21, 19, 0.5, 0.42, tono(col, 0.45), 8)
	pieza(caja, 5, 6, 0.39, 0.42, tono(col, -0.7), 2)  -- cuenca izq
	pieza(caja, 5, 6, 0.61, 0.42, tono(col, -0.7), 2)  -- cuenca der
	pieza(caja, 3, 4, 0.5, 0.57, tono(col, -0.55), 1)  -- nariz
	pieza(caja, 13, 7, 0.5, 0.75, tono(col, 0.3), 2)   -- mandibula
	pieza(caja, 1, 5, 0.5, 0.76, tono(col, -0.5), 0)   -- hueco entre dientes (asimetrico a proposito)
	pieza(caja, 1, 5, 0.42, 0.76, tono(col, -0.5), 0)
end

function DIBUJOS.reloj(caja, col) -- tiempo / cooldown / evento temporal
	pieza(caja, 23, 23, 0.5, 0.52, tono(col, -0.1), -1)
	pieza(caja, 17, 17, 0.5, 0.52, tono(col, 0.5), -1)
	pieza(caja, 2, 8, 0.5, 0.42, tono(col, -0.75), 1)        -- aguja larga (arriba)
	pieza(caja, 7, 2, 0.585, 0.52, tono(col, -0.75), 1)      -- aguja corta (derecha)
	pieza(caja, 7, 3, 0.5, 0.12, tono(col, -0.25), 1)        -- corona
end

function DIBUJOS.gema(caja, col) -- moneda premium / materiales: corona plana + pabellon en punta
	local corona = pieza(caja, 20, 6, 0.5, 0.3, tono(col, 0.55), 2)
	local g1 = Instance.new("UIGradient")
	g1.Color = ColorSequence.new(tono(col, 0.75), tono(col, 0.15))
	g1.Parent = corona
	local cuerpo = pieza(caja, 15, 15, 0.5, 0.62, col, 2, 45)
	local g2 = Instance.new("UIGradient")
	g2.Color = ColorSequence.new(tono(col, 0.35), tono(col, -0.45))
	g2.Rotation = 45
	g2.Parent = cuerpo
	pieza(caja, 4, 4, 0.4, 0.45, tono(col, 0.85), 1, 45) -- destello, descentrado
end

function DIBUJOS.espada(caja, col) -- arma / ataque
	pieza(caja, 7, 4, 0.5, 0.16, tono(col, 0.2), 1, 45)      -- punta
	local hoja = pieza(caja, 7, 18, 0.5, 0.45, tono(col, 0.55), 1)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(tono(col, 0.85), tono(col, 0.15))
	g.Rotation = 20
	g.Parent = hoja
	pieza(caja, 3, 18, 0.56, 0.45, tono(col, 0.05), 0)      -- filo en sombra (rompe la simetria)
	pieza(caja, 21, 4, 0.5, 0.7, tono(col, -0.25), 2)       -- guarda
	pieza(caja, 4, 7, 0.5, 0.83, Color3.fromRGB(126, 92, 58), 1) -- empunadura
	pieza(caja, 6, 3, 0.5, 0.95, tono(col, -0.35), -1)      -- pomo
end

function DIBUJOS.escudo(caja, col) -- defensa / armadura
	pieza(caja, 21, 14, 0.5, 0.36, tono(col, 0.4), 3)
	pieza(caja, 15, 15, 0.5, 0.62, tono(col, 0.4), 3, 45)   -- la punta de abajo
	local banda = pieza(caja, 21, 4, 0.5, 0.36, tono(col, -0.3), 1)
	banda.ZIndex = 3
	local emblema = pieza(caja, 6, 6, 0.5, 0.52, tono(col, 0.85), 1, 45)
	emblema.ZIndex = 3
end

function DIBUJOS.rayo(caja, col) -- daño / velocidad / energia
	pieza(caja, 6, 14, 0.56, 0.3, tono(col, 0.55), 1, 22)
	pieza(caja, 6, 14, 0.44, 0.7, tono(col, 0.15), 1, 22)
	pieza(caja, 13, 4, 0.5, 0.5, tono(col, 0.75), 1, -18)
end

function DIBUJOS.corazon(caja, col) -- vida
	pieza(caja, 11, 11, 0.37, 0.38, tono(col, 0.35), -1)
	pieza(caja, 11, 11, 0.63, 0.38, tono(col, 0.35), -1)
	pieza(caja, 15, 15, 0.5, 0.55, tono(col, 0.15), 2, 45)
	local br = pieza(caja, 4, 4, 0.36, 0.34, Color3.new(1, 1, 1), -1)
	br.BackgroundTransparency = 0.5
end

function DIBUJOS.estrella(caja, col) -- rango / favorito / rareza
	for _, giro in ipairs({ 0, 60, 120 }) do
		pieza(caja, 5, 24, 0.5, 0.5, tono(col, 0.45), 2, giro)
	end
	pieza(caja, 8, 8, 0.5, 0.5, tono(col, 0.8), -1)
end

function DIBUJOS.check(caja, col) -- hecho / equipado
	pieza(caja, 4, 10, 0.36, 0.62, tono(col, 0.35), 2, -45)
	pieza(caja, 4, 19, 0.58, 0.47, tono(col, 0.55), 2, 40)
end

function DIBUJOS.cruz(caja, col) -- cerrar / no disponible
	pieza(caja, 4, 20, 0.5, 0.5, tono(col, 0.45), 2, 45)
	pieza(caja, 4, 20, 0.5, 0.5, tono(col, 0.45), 2, -45)
end

-- --- SILUETAS DE CLASE (una por personaje; el gacha pintaba el MISMO orbe para las 5, solo cambiando
-- el color. Ahora cada clase tiene su arma dibujada. Se mapean en UITheme.iconoClase (mas abajo). ---

function DIBUJOS.varita(caja, col) -- MAGE: baculo con orbe magico (halo + brillo)
	pieza(caja, 5, 20, 0.42, 0.62, Color3.fromRGB(116, 84, 52), 2, -28) -- vara
	pieza(caja, 6, 5, 0.42, 0.62, tono(col, -0.3), 2, -28)              -- anillo del mango
	local halo = pieza(caja, 19, 19, 0.66, 0.3, col, -1); halo.BackgroundTransparency = 0.58 -- halo magico
	local o = pieza(caja, 15, 15, 0.66, 0.3, col, -1)                   -- orbe
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(tono(col, 0.75), tono(col, -0.4)); g.Rotation = 65; g.Parent = o
	local ost = Instance.new("UIStroke"); ost.Color = tono(col, 0.55); ost.Thickness = 1.5; ost.Transparency = 0.25; ost.Parent = o
	local br = pieza(caja, 5, 5, 0.61, 0.24, Color3.new(1, 1, 1), -1); br.BackgroundTransparency = 0.2 -- brillo
	pieza(caja, 3, 3, 0.87, 0.13, tono(col, 0.85), -1) -- chispa
	pieza(caja, 2, 2, 0.52, 0.11, tono(col, 0.85), -1) -- chispa
end

function DIBUJOS.arco(caja, col) -- ARCHER: arco a la izquierda (con brillo) + flecha DIAGONAL
	local a1 = pieza(caja, 5, 15, 0.3, 0.27, tono(col, 0.55), 3, 40)  -- brazo sup
	local a2 = pieza(caja, 5, 15, 0.3, 0.73, tono(col, 0.55), 3, -40) -- brazo inf
	local a3 = pieza(caja, 5, 9, 0.21, 0.5, tono(col, 0.72), 3)       -- lomo
	for _, a in ipairs({ a1, a2, a3 }) do local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(tono(col, 0.9), tono(col, 0.08)); g.Parent = a end
	pieza(caja, 2, 25, 0.42, 0.5, tono(col, 0.9), 1)       -- cuerda
	pieza(caja, 27, 3, 0.55, 0.5, tono(col, 0.7), 1, -33)  -- astil de la flecha (diagonal)
	local pt = pieza(caja, 9, 9, 0.8, 0.25, tono(col, 0.95), 1, 45)   -- punta (rombo)
	local pg = Instance.new("UIGradient"); pg.Color = ColorSequence.new(Color3.new(1, 1, 1), tono(col, 0.4)); pg.Rotation = 45; pg.Parent = pt
	pieza(caja, 6, 2, 0.31, 0.72, tono(col, 0.5), 1, 55)   -- pluma
	pieza(caja, 6, 2, 0.37, 0.78, tono(col, 0.5), 1, 55)   -- pluma
end

function DIBUJOS.mandoble(caja, col) -- KNIGHT: mandoble ancho (filo brillante + joya en la guarda)
	pieza(caja, 12, 5, 0.5, 0.1, tono(col, 0.35), 1, 45)   -- punta
	local hoja = pieza(caja, 12, 17, 0.5, 0.4, tono(col, 0.6), 2)
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(tono(col, 0.98), tono(col, 0.12)); g.Rotation = 20; g.Parent = hoja
	local filo = pieza(caja, 2, 15, 0.44, 0.4, Color3.new(1, 1, 1), 0); filo.BackgroundTransparency = 0.35 -- brillo del filo
	pieza(caja, 3, 15, 0.57, 0.4, tono(col, -0.08), 0)     -- sombra del otro filo
	pieza(caja, 27, 5, 0.5, 0.65, tono(col, -0.3), 2)      -- guarda ancha
	pieza(caja, 5, 5, 0.5, 0.65, tono(col, 0.75), -1)      -- joya en la guarda
	pieza(caja, 4, 9, 0.5, 0.81, Color3.fromRGB(126, 92, 58), 1) -- empunadura
	pieza(caja, 9, 4, 0.5, 0.96, tono(col, -0.3), -1)      -- pomo
end

function DIBUJOS.guadana(caja, col) -- BLOODREAVER: guadaña (hoja curva con gradiente + filo brillante)
	pieza(caja, 5, 26, 0.53, 0.55, Color3.fromRGB(108, 78, 48), 2, 14) -- astil
	pieza(caja, 4, 6, 0.53, 0.3, tono(col, -0.2), 1, 14)               -- abrazadera
	local b1 = pieza(caja, 17, 6, 0.42, 0.14, tono(col, 0.6), 3, -16)  -- hoja: tramo principal
	local b2 = pieza(caja, 9, 5, 0.18, 0.22, tono(col, 0.4), 3, -50)   -- hoja: punta que baja
	for _, b in ipairs({ b1, b2 }) do local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(tono(col, 0.95), tono(col, 0.1)); g.Parent = b end
	local filo = pieza(caja, 15, 2, 0.42, 0.1, Color3.new(1, 1, 1), 1, -16); filo.BackgroundTransparency = 0.4 -- filo brillante
end

function DIBUJOS.chakram(caja, col) -- TRICKSTER: aro de filo (doble anillo + dientes)
	local aro = pieza(caja, 26, 26, 0.5, 0.5, col, -1); aro.BackgroundTransparency = 1
	local s = Instance.new("UIStroke"); s.Thickness = 5; s.Color = tono(col, 0.6); s.Parent = aro
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(tono(col, 0.98), tono(col, -0.15)); g.Rotation = 45; g.Parent = s
	local aro2 = pieza(caja, 14, 14, 0.5, 0.5, col, -1); aro2.BackgroundTransparency = 1 -- anillo interior fino
	local s2 = Instance.new("UIStroke"); s2.Thickness = 1.5; s2.Color = tono(col, 0.35); s2.Transparency = 0.25; s2.Parent = aro2
	for _, p in ipairs({ { 0.5, 0.04 }, { 0.5, 0.96 }, { 0.04, 0.5 }, { 0.96, 0.5 } }) do
		pieza(caja, 7, 7, p[1], p[2], tono(col, 0.88), 1, 45) -- dientes
	end
	pieza(caja, 5, 5, 0.5, 0.5, tono(col, -0.15), -1) -- eje central
end

-- clase -> pictograma. El Hub (menu CLASSES/GACHA) sigue usando "orbe" a proposito: representa el
-- menu entero, no una clase concreta.
UITheme.iconoClase = {
	Mage = "varita", Archer = "arco", Knight = "mandoble",
	Bloodreaver = "guadana", Trickster = "chakram",
}

-- Nombres validos para UITheme.pictograma (por si un panel quiere iterarlos).
UITheme.pictogramas = {
	"pergamino", "orbe", "martillo", "rombo", "monedas", "busto",
	"candado", "calavera", "reloj", "gema", "espada", "escudo",
	"rayo", "corazon", "estrella", "check", "cruz",
	"varita", "arco", "mandoble", "guadana", "chakram",
}

-- Dibuja el pictograma 'cual' dentro de 'caja' (un Frame; se recomienda 30x30, que es el lienzo con el que
-- estan medidos todos). LIMPIA la caja antes, asi que se puede llamar de nuevo para cambiar de icono.
-- Devuelve la caja. Si el nombre no existe, avisa por warn y dibuja el rombo (nunca deja un hueco).
function UITheme.pictograma(caja, cual, color)
	local f = DIBUJOS[cual]
	if not f then
		warn("[UITheme] pictograma desconocido:", tostring(cual))
		f = DIBUJOS.rombo
	end
	caja:ClearAllChildren()
	caja.BackgroundTransparency = 1
	caja.BorderSizePixel = 0
	caja.ClipsDescendants = true -- el busto y el escudo cuentan con esto: se cortan por abajo
	f(caja, color or UITheme.color.acento)
	return caja
end

-- Atajo: crea la caja del pictograma Y lo dibuja. opts: lado=30 · pos · anchor · nombre · zindex
--
-- OJO CON EL LADO. Todos los dibujos de DIBUJOS estan medidos en PIXELES para un lienzo de 30x30, y
-- pictograma() pone ClipsDescendants = true (lo necesitan el busto y el escudo, que se cortan por abajo a
-- proposito). Consecuencia: si pides lado = 16, el dibujo NO se encoge, se RECORTA -- la estrella pierde las
-- puntas, el rombo pierde las esquinas y la gema se corta por arriba y por los lados. Quedaba un borron.
-- La caja se crea SIEMPRE de 30 y se escala con un UIScale en un envoltorio del tamano pedido. Asi cualquier
-- lado funciona y los dibujos siguen escritos contra una sola referencia.
local LADO_DIBUJO = 30

function UITheme.icono(padre, cual, color, opts)
	opts = opts or {}
	local lado = opts.lado or LADO_DIBUJO

	local marco = Instance.new("Frame")
	marco.Name = opts.nombre or "Icono"
	marco.Size = UDim2.fromOffset(lado, lado)
	marco.Position = opts.pos or UDim2.new(0.5, 0, 0, 7)
	marco.AnchorPoint = opts.anchor or Vector2.new(0.5, 0)
	marco.BackgroundTransparency = 1
	marco.ZIndex = opts.zindex or 1
	marco.Parent = padre

	if lado == LADO_DIBUJO then
		-- Caso normal: sin envoltorio ni UIScale de por medio.
		return UITheme.pictograma(marco, cual, color)
	end

	local caja = Instance.new("Frame")
	caja.Name = "Dibujo"
	caja.Size = UDim2.fromOffset(LADO_DIBUJO, LADO_DIBUJO)
	caja.AnchorPoint = Vector2.new(0.5, 0.5)
	caja.Position = UDim2.fromScale(0.5, 0.5)
	caja.BackgroundTransparency = 1
	caja.ZIndex = marco.ZIndex
	caja.Parent = marco
	local esc = Instance.new("UIScale")
	esc.Scale = lado / LADO_DIBUJO
	esc.Parent = caja
	return UITheme.pictograma(caja, cual, color)
end

-- ===================================================================================================
-- ESCALA  ·  el guardia del ViewportSize
-- ===================================================================================================
-- Mete un UIScale en 'frame' que lo encoge si el viewport es bajo (movil apaisado corto).
-- OJO, la trampa: la camara reporta ViewportSize (1,1) HASTA EL PRIMER FOTOGRAMA. Sin guardia la cuenta sale
-- 1/620 y la escala se queda clavada en el minimo PARA TODA LA SESION, en pantallas donde no hacia falta.
-- Por eso: (a) si el alto es < 100 se ignora, (b) se escucha el cambio de ViewportSize, y (c) se reintenta
-- 2 segundos por si la señal ya habia pasado antes de conectarnos.
-- opts: alto=620 (alto de referencia) · min=0.78 · max=1
-- Devuelve el UIScale (y la funcion de reajuste, por si quieres forzarlo).
UITheme.UI_ESCALA = 1.15 -- A (fix): factor GLOBAL de tamano de UI (1.15 = +15%). Sube/baja aqui. Multiplica el UIScale de cada panel (y la columna del Hub usa el mismo factor).
function UITheme.escalar(frame, opts)
	opts = opts or {}
	local altoRef = opts.alto or 620
	local minimo = opts.min or 0.78
	local maximo = opts.max or 1

	local escala = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	escala.Parent = frame

	local function ajustar()
		local camara = workspace.CurrentCamera
		if not camara then return end
		local alto = camara.ViewportSize.Y
		if alto < 100 then return end -- guardia: (1,1) antes del primer fotograma
		escala.Scale = math.clamp(alto / altoRef, minimo, maximo) * (UITheme.UI_ESCALA or 1)
	end

	local camara = workspace.CurrentCamera
	if camara then camara:GetPropertyChangedSignal("ViewportSize"):Connect(ajustar) end
	-- La camara se puede recrear (respawn): reengancharse.
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local c = workspace.CurrentCamera
		if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(ajustar) end
		ajustar()
	end)
	task.spawn(function()
		for _ = 1, 20 do -- reintento: 20 x 0.1s = 2 segundos
			local c = workspace.CurrentCamera
			if c and c.ViewportSize.Y >= 100 then ajustar() break end
			task.wait(0.1)
		end
	end)
	ajustar()
	return escala, ajustar
end

-- ===================================================================================================
-- MenuAbierto  ·  con CONTADOR
-- ===================================================================================================
-- El Hub esconde su columna de iconos y el PLAY con player:GetAttribute("MenuAbierto"). Varios menus no lo
-- tocan hoy y por eso se quedan flotando encima de los paneles. Aqui va con CLAVE + contador: si hay dos
-- paneles abiertos y cierras uno, el flag sigue en true (con un simple SetAttribute(false) se apagaria).
local abiertos = {}
function UITheme.marcarMenu(clave, abierto)
	if not RunService:IsClient() then return end
	local player = Players.LocalPlayer
	if not player then return end
	if abierto then abiertos[clave] = true else abiertos[clave] = nil end
	local hay = false
	for _ in pairs(abiertos) do hay = true break end
	player:SetAttribute("MenuAbierto", hay)
end

-- ===================================================================================================
-- PANEL
-- ===================================================================================================
-- Crea el overlay a pantalla completa + la placa del panel + la barra de titulo (titulo a la IZQUIERDA con
-- tick de acento, boton de cerrar de 44px a la derecha, separador que no llega a los bordes).
--
-- padre: el ScreenGui (o cualquier GuiObject). Si es un ScreenGui, api.abrir/cerrar tambien tocan .Enabled,
--        asi que ese ScreenGui tiene que ser EXCLUSIVO del panel: NO metas ahi el boton que lo abre (se
--        apagaria con el panel). El boton de abrir va en su propio ScreenGui, como ya hacen los menus.
-- OJO movil: el panel va centrado; en pantallas bajas el borde de arriba podria subir de y=52 (barra de
--        Roblox). Por eso lleva UIScale (opts.escala): dejalo puesto salvo que sepas lo que haces.
-- opts: acento=Color3 · clave=string(para MenuAbierto; por defecto el titulo) · velo=0.45 (opacidad del
--       fondo negro) · sinCerrar=bool · alCerrar=function · escala=bool(por defecto true) · radio
--
-- DEVUELVE, en este orden: overlay, panel, barra, api
--   overlay : Frame a pantalla completa con Active=true (ABSORBE los clics; sin esto el toque atraviesa el
--             panel y llega al boton PLAY de debajo). Cerrado empieza con Visible=false.
--   panel   : la placa central (aqui va tu contenido).
--   barra   : Frame de la cabecera (alto 52). barra.Titulo = TextLabel, barra.Cerrar = TextButton (o nil).
--   api     : { abrir(), cerrar(), alternar(), estaAbierto() -> bool }  ← usa ESTO y el MenuAbierto se
--             gestiona solo.
function UITheme.panel(padre, ancho, alto, titulo, opts)
	opts = opts or {}
	local acento = opts.acento or UITheme.color.acento
	local clave = opts.clave or titulo or ("panel_" .. tostring(math.random(1e6)))

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = opts.velo or 0.45
	overlay.BorderSizePixel = 0
	overlay.Active = true -- OBLIGATORIO: absorbe los clics del fondo
	overlay.Visible = false
	overlay.Parent = padre

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(ancho, alto)
	panel.Parent = overlay
	UITheme.placa(panel, {
		fondo = UITheme.color.fondoPlaca,
		alto = Color3.fromRGB(48, 46, 58),
		bajo = Color3.fromRGB(24, 23, 31),
		radio = opts.radio or UITheme.radio.panel,
		grosor = 2,
		bordeTransp = 0.15,
	})
	if opts.escala ~= false then UITheme.escalar(panel, { alto = alto + 90, min = 0.62 }) end

	-- Cabecera
	local barra = Instance.new("Frame")
	barra.Name = "Barra"
	barra.Size = UDim2.new(1, 0, 0, 52)
	barra.BackgroundTransparency = 1
	barra.Parent = panel

	-- Tick de acento a la izquierda del titulo: rompe la simetria y da color sin pintar fondos.
	local tick = Instance.new("Frame")
	tick.Name = "Tick"
	tick.Size = UDim2.fromOffset(4, 20)
	tick.Position = UDim2.new(0, 18, 0, 17)
	tick.BackgroundColor3 = acento
	tick.BorderSizePixel = 0
	tick.Parent = barra
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1, 0); tc.Parent = tick

	local lblTitulo = UITheme.etiqueta(barra, titulo or "", {
		nombre = "Titulo",
		fuente = UITheme.fuente.titulo,
		tam = 22,
		color = UITheme.color.texto,
		pos = UDim2.new(0, 32, 0, 14),
		tamano = UDim2.new(1, -90, 0, 26),
		align = Enum.TextXAlignment.Left,
	})
	barra:SetAttribute("EsBarra", true)
	UITheme.separador(barra, 50, { izq = 18, margen = 36 })

	local cerrarBtn = nil
	if not opts.sinCerrar then
		cerrarBtn = Instance.new("TextButton")
		cerrarBtn.Name = "Cerrar"
		cerrarBtn.Size = UDim2.fromOffset(UITheme.TACTIL_MIN, UITheme.TACTIL_MIN) -- 44: minimo tactil movil
		cerrarBtn.AnchorPoint = Vector2.new(1, 0)
		cerrarBtn.Position = UDim2.new(1, -10, 0, 5)
		cerrarBtn.Text = "" -- vacio a proposito: que no colisione con la busqueda por .Text de HubClient
		cerrarBtn.AutoButtonColor = false
		cerrarBtn.Parent = barra
		UITheme.placa(cerrarBtn, {
			fondo = Color3.fromRGB(46, 34, 38),
			alto = Color3.fromRGB(66, 44, 48),
			bajo = Color3.fromRGB(32, 24, 28),
			radio = UITheme.radio.boton,
			bordeTransp = 0.35,
		})
		UITheme.icono(cerrarBtn, "cruz", Color3.fromRGB(226, 150, 146), {
			lado = 16, pos = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5),
		})
	end

	local api = {}
	local visible = false
	function api.estaAbierto() return visible end
	function api.abrir()
		visible = true
		overlay.Visible = true
		if padre:IsA("ScreenGui") then padre.Enabled = true end
		UITheme.marcarMenu(clave, true)
	end
	function api.cerrar()
		visible = false
		overlay.Visible = false
		if padre:IsA("ScreenGui") then padre.Enabled = false end
		UITheme.marcarMenu(clave, false)
		if opts.alCerrar then task.spawn(opts.alCerrar) end
	end
	function api.alternar()
		if visible then api.cerrar() else api.abrir() end
	end
	if cerrarBtn then
		UITheme.pulsacion(cerrarBtn)
		cerrarBtn.MouseButton1Click:Connect(api.cerrar)
	end
	if padre:IsA("ScreenGui") then padre.Enabled = false end

	-- El titulo y el boton de cerrar son HIJOS con nombre: barra.Titulo / barra.Cerrar. Ademas se devuelven
	-- al final por comodidad (no se pueden meter campos sueltos en una Instance).
	return overlay, panel, barra, api, lblTitulo, cerrarBtn
end

-- ===================================================================================================
-- FEEDBACK DE PULSACION  ·  movil incluido
-- ===================================================================================================
-- En movil MouseEnter/MouseLeave NO son fiables: el destello al tocar se hace con MouseButton1Down/Up.
-- 'aplicar(on)' se llama con true al entrar/pulsar y false al salir/soltar (con 0.15s de retardo al soltar,
-- para que el destello se vea aunque el toque sea instantaneo).
function UITheme.pulsacion(btn, aplicar)
	local infoRapida = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	local base = btn.BackgroundColor3
	local claro = base:Lerp(Color3.new(1, 1, 1), 0.12)
	local fn = aplicar or function(on)
		TweenService:Create(btn, infoRapida, { BackgroundColor3 = on and claro or base }):Play()
	end
	btn.MouseEnter:Connect(function() fn(true) end)
	btn.MouseLeave:Connect(function() fn(false) end)
	btn.MouseButton1Down:Connect(function() fn(true) end)
	btn.MouseButton1Up:Connect(function() task.delay(0.15, function() fn(false) end) end)
	return fn
end

-- ===================================================================================================
-- BOTON
-- ===================================================================================================
-- TextButton con el lenguaje de placa + feedback de pulsacion (raton Y tactil).
--
-- IMPORTANTISIMO: el texto VISIBLE va en un TextLabel hijo (un UIGradient en un TextButton tiñe tambien su
-- texto), PERO btn.Text SE DEJA PUESTO con TextTransparency=1. Motivo: HubClient adopta los botones del
-- lobby buscandolos entre todos los TextButton del PlayerGui por su .Text EXACTO
-- ("QUESTS", "CLASSES / GACHA", "FORGE", "PERKS", "STORE", "PLAYER INFO"). Si vaciaramos .Text, esos botones
-- DESAPARECERIAN de la columna del lobby. Con opts.plano=true no hay degradado y el texto se pinta en el
-- propio boton (sin label hijo).
--
-- opts:
--   ancho=140 · alto=44 (nunca baja de 44 salvo compacto=true) · pos=UDim2 · anchor=Vector2 · layoutOrder
--   acento=Color3 (barra fina inferior; nil = sin barra) · color=Color3 (fondo de la placa)
--   tam=15 (TextSize) · fuente · textoColor · icono="espada" · iconoColor · radio
--   plano=bool (sin degradado: el texto va en el propio boton) · compacto=bool (permite alto < 44)
--   variante="normal"|"peligro"|"ok"|"apagado"  (tiñe el fondo levemente; el color sigue sin ser plano)
--   nombre=string
--
-- Devuelve: btn, lbl  (lbl = el TextLabel hijo, o nil si opts.plano)
function UITheme.boton(padre, texto, opts)
	opts = opts or {}
	local variantes = {
		normal  = { Color3.fromRGB(72, 68, 88), Color3.fromRGB(94, 89, 112), Color3.fromRGB(56, 53, 70) },   -- 22-jul (2a pasada, Bastian "siguen muy oscuros"): MUCHO mas claro que fondoPlaca (38,37,47) -> el boton salta del panel
		peligro = { Color3.fromRGB(72, 44, 46), Color3.fromRGB(96, 56, 58), Color3.fromRGB(52, 32, 34) },
		ok      = { Color3.fromRGB(42, 64, 46), Color3.fromRGB(58, 84, 62), Color3.fromRGB(32, 50, 36) },
		apagado = { Color3.fromRGB(50, 48, 60), Color3.fromRGB(62, 60, 74), Color3.fromRGB(40, 38, 49) },
	}
	local v = variantes[opts.variante or "normal"] or variantes.normal

	local alto = opts.alto or UITheme.TACTIL_MIN
	if not opts.compacto then alto = math.max(alto, UITheme.TACTIL_MIN) end -- movil: 44 px minimo

	local btn = Instance.new("TextButton")
	btn.Name = opts.nombre or "Boton"
	btn.Size = UDim2.fromOffset(opts.ancho or 140, alto)
	if opts.tamano then btn.Size = opts.tamano end
	btn.Position = opts.pos or UDim2.new(0, 0, 0, 0)
	if opts.anchor then btn.AnchorPoint = opts.anchor end
	btn.LayoutOrder = opts.layoutOrder or 0
	btn.AutoButtonColor = false
	btn.Font = opts.fuente or UITheme.fuente.dato
	btn.TextSize = opts.tam or 15
	btn.TextScaled = false -- TextScaled IGNORA el TextSize y descuadra las placas
	btn.TextColor3 = opts.textoColor or UITheme.color.texto
	btn.Text = texto or "" -- se deja SIEMPRE: HubClient busca por .Text exacto
	btn.Parent = padre

	UITheme.placa(btn, {
		fondo = opts.color or v[1],
		alto = opts.altoColor or v[2],
		bajo = opts.bajoColor or v[3],
		radio = opts.radio or UITheme.radio.boton,
		borde = opts.borde or Color3.fromRGB(112, 108, 132), -- 22-jul (2a pasada): borde CLARO (no el oscuro) -> el boton se delimita del panel
		bordeTransp = 0.28,
		sinGradiente = opts.plano == true,
	})

	local lbl = nil
	local margenIzq = opts.icono and 34 or 0
	if not opts.plano then
		btn.TextTransparency = 1 -- invisible pero PRESENTE (el gradiente lo tiñe; el .Text sigue buscable)
		lbl = UITheme.etiqueta(btn, texto or "", {
			nombre = "Label",
			fuente = opts.fuente or UITheme.fuente.dato,
			tam = opts.tam or 15,
			color = opts.textoColor or UITheme.color.texto,
			pos = UDim2.new(0, margenIzq, 0, 0),
			tamano = UDim2.new(1, -margenIzq, 1, opts.acento and -6 or 0),
			align = opts.align or (opts.icono and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center),
			alignY = Enum.TextYAlignment.Center,
			wrap = opts.wrap == true,
		})
		lbl.ZIndex = 2
	elseif opts.icono then
		btn.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, margenIzq); pad.Parent = btn
	end

	if opts.icono then
		UITheme.icono(btn, opts.icono, opts.iconoColor or opts.acento or UITheme.color.acento, {
			lado = 22, pos = UDim2.new(0, 8, 0.5, 0), anchor = Vector2.new(0, 0.5), zindex = 2,
		})
	end

	local acento = nil
	if opts.acento then
		acento = UITheme.acentoBarra(btn, opts.acento, {
			ancho = math.floor((opts.ancho or 140) * 0.2), alto = 3,
			pos = UDim2.new(0, 12, 1, -8), anchor = Vector2.new(0, 0), -- a la IZQUIERDA, no centrada
		})
	end

	-- Resalte: la placa se aclara, la barra de acento se ensancha y la etiqueta sube de brillo.
	--
	-- opts.sinPulsacion existe por un motivo concreto: este resalte MEMORIZA el color de fondo del momento en
	-- que se crea el boton. Si el boton cambia de fondo despues (pestanas activa/apagada, un boton que pasa a
	-- "no te lo puedes permitir"), al soltar el dedo el tween lo devuelve al color VIEJO y borra el estado.
	-- Quien tenga botones asi pide sinPulsacion y conecta su propio UITheme.pulsacion. Si no se ofrece esta
	-- puerta, el que lo intente acaba con DOS handlers conectados peleandose, que es peor que no tener ninguno.
	if not opts.sinPulsacion then
		local baseColor = btn.BackgroundColor3
		local claro = baseColor:Lerp(Color3.new(1, 1, 1), 0.13)
		local infoRapida = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
		UITheme.pulsacion(btn, function(on)
			TweenService:Create(btn, infoRapida, { BackgroundColor3 = on and claro or baseColor }):Play()
			if acento then
				local w = math.floor((opts.ancho or 140) * (on and 0.34 or 0.2))
				TweenService:Create(acento, infoRapida, { Size = UDim2.fromOffset(w, 3) }):Play()
			end
		end)
	end

	return btn, lbl
end

-- ===================================================================================================
-- TARJETA DE OBJETO
-- ===================================================================================================
-- Placa con BORDE DE RAREZA (el otro sitio, junto a las barras finas y los pictogramas, donde el color sale).
--
-- opts:
--   rareza="Epic"|"epico"|Color3 (por defecto comun) · ancho=150 · alto=96 · pos · anchor · layoutOrder
--   titulo=string · sub=string · icono="gema" · iconoColor · bloqueada=bool (baja la placa y pinta candado)
--   nombre=string · radio · sinIcono=bool
--
-- Devuelve: card, refs
--   refs = { titulo=TextLabel|nil, sub=TextLabel|nil, icono=Frame|nil, stroke=UIStroke, cinta=Frame }
function UITheme.tarjeta(padre, opts)
	opts = opts or {}
	local col = UITheme.colorRareza(opts.rareza)

	local card = Instance.new("Frame")
	card.Name = opts.nombre or "Tarjeta"
	card.Size = opts.tamano or UDim2.fromOffset(opts.ancho or 150, opts.alto or 96)
	card.Position = opts.pos or UDim2.new(0, 0, 0, 0)
	if opts.anchor then card.AnchorPoint = opts.anchor end
	card.LayoutOrder = opts.layoutOrder or 0
	card.Parent = padre

	UITheme.placa(card, {
		fondo = opts.bloqueada and Color3.fromRGB(30, 29, 37) or UITheme.color.fondoPlaca,
		alto = opts.bloqueada and Color3.fromRGB(40, 39, 48) or Color3.fromRGB(52, 50, 63),
		bajo = Color3.fromRGB(26, 25, 33),
		radio = opts.radio or UITheme.radio.tarjeta,
		sinBorde = true,
	})
	-- El stroke SI lleva color aqui: es el codigo de rareza. Fino y algo transparente, no un neon.
	local stroke = Instance.new("UIStroke")
	stroke.Color = col
	stroke.Thickness = 2
	stroke.Transparency = opts.bloqueada and 0.6 or 0.25
	stroke.Parent = card

	-- Cinta de rareza pegada al borde SUPERIOR, sin llegar a las esquinas (asimetria intencionada).
	local cinta = Instance.new("Frame")
	cinta.Name = "Cinta"
	cinta.Size = UDim2.new(0.42, 0, 0, 3)
	cinta.Position = UDim2.new(0, 10, 0, 0)
	cinta.BackgroundColor3 = col
	cinta.BackgroundTransparency = opts.bloqueada and 0.55 or 0
	cinta.BorderSizePixel = 0
	cinta.Parent = card
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(1, 0); cc.Parent = cinta

	local refs = { stroke = stroke, cinta = cinta }

	if not opts.sinIcono then
		refs.icono = UITheme.icono(card, opts.bloqueada and "candado" or (opts.icono or "gema"),
			opts.bloqueada and UITheme.color.apagado or (opts.iconoColor or col),
			{ lado = 30, pos = UDim2.new(0.5, 0, 0, 14), anchor = Vector2.new(0.5, 0) })
	end

	if opts.titulo then
		refs.titulo = UITheme.etiqueta(card, opts.titulo, {
			nombre = "Titulo",
			fuente = UITheme.fuente.dato,
			tam = 14,
			color = opts.bloqueada and UITheme.color.textoTenue or UITheme.color.texto,
			pos = UDim2.new(0, 8, 0, opts.sinIcono and 12 or 50),
			tamano = UDim2.new(1, -16, 0, 18),
			align = Enum.TextXAlignment.Center,
		})
	end
	if opts.sub then
		refs.sub = UITheme.etiqueta(card, opts.sub, {
			nombre = "Sub",
			fuente = UITheme.fuente.etiqueta,
			tam = 12,
			color = opts.bloqueada and UITheme.color.apagado or col,
			pos = UDim2.new(0, 8, 0, opts.sinIcono and 32 or 70),
			tamano = UDim2.new(1, -16, 0, 16),
			align = Enum.TextXAlignment.Center,
		})
	end

	return card, refs
end

-- ===================================================================================================
-- SCROLL  ·  lista vertical lista para movil
-- ===================================================================================================
-- ScrollingFrame con barra fina, CanvasSize automatico y UIListLayout ya puesto.
-- opts: pos · tamano · padding=8 · relleno=10 · grid=bool · celda=Vector2 (si grid) · nombre
-- Devuelve: scroll, layout
function UITheme.scroll(padre, opts)
	opts = opts or {}
	local s = Instance.new("ScrollingFrame")
	s.Name = opts.nombre or "Scroll"
	s.Size = opts.tamano or UDim2.new(1, -32, 1, -80)
	s.Position = opts.pos or UDim2.new(0, 16, 0, 64)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.ScrollBarImageColor3 = UITheme.color.placaAlta
	s.ScrollBarImageTransparency = 0.3
	s.CanvasSize = UDim2.new(0, 0, 0, 0)
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ClipsDescendants = true
	s.Parent = padre

	local layout
	if opts.grid then
		layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromOffset((opts.celda and opts.celda.X) or 150, (opts.celda and opts.celda.Y) or 96)
		layout.CellPadding = UDim2.fromOffset(opts.padding or 8, opts.padding or 8)
	else
		layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, opts.padding or 8)
	end
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = s

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, opts.relleno or 10)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = s

	return s, layout
end

return UITheme
