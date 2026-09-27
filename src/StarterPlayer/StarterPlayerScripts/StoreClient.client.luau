-- StoreClient (LocalScript) · Sju - TIENDA: packs de valor (dev products) + gamepasses de conveniencia.
-- Es LA pantalla que hace caja en Robux, asi que aqui la jerarquia visual importa mas que en ningun otro menu:
-- se entra viendo el pack recomendado, y lo que YA tienes se sigue viendo (comprado/owned), nunca se esconde:
-- ver la coleccion a medias es justo lo que empuja a completarla.
--
-- LO QUE NO CAMBIA (y no se toca): MarketplaceService:PromptProductPurchase / PromptGamePassPurchase, los IDs
-- de StoreData/MonetizationData, los atributos Pack_<id> y Pass_<id> que pone el server, y el atributo InMatch.
-- El grant SIEMPRE lo hace el server (ProcessReceipt); este script solo pinta y lanza el prompt.
--
-- BUGS ARREGLADOS EN ESTA PASADA:
--   · el panel colgaba del ScreenGui SIN velo detras: un toque fuera del panel se iba al mundo 3D (y en movil
--     al PLAY). Ahora va dentro de un overlay a pantalla completa con Active=true (UITheme.panel).
--   · no escribia player.MenuAbierto, asi que la columna de iconos del Hub y el PLAY se quedaban flotando
--     encima de la tienda. Ahora lo gestiona UITheme.panel (con contador por clave).
--   · si comprabas con la tienda ABIERTA, la tarjeta seguia diciendo "BUY" hasta cerrar y reabrir. Ahora se
--     repinta al cambiar Pack_/Pass_.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer
local StoreData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("StoreData"))

-- CUMPLIMIENTO "paid random items" (norma de Roblox, reforzada en marzo 2026).
-- PolicyServer consulta PolicyService en el SERVIDOR y deja el resultado en este atributo, con default TRUE
-- (restringido) hasta que Roblox conteste: si la consulta falla, se peca de prudente.
-- Aqui se usa SOLO para no OFRECER cosas aleatorias (la norma no es unicamente no venderlas). El bloqueo que
-- de verdad cuenta es el del servidor -- un gate solo-cliente no vale nada, porque un LocalScript puede
-- sobrescribir el atributo en su propia maquina.
local function restringido()
	return player:GetAttribute("PaidRandomRestricted") ~= false
end
local MonetizationData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MonetizationData"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))

local ORO = UITheme.acentos.store -- el tono de la entrada STORE del Hub: la tienda mantiene SU color

-- ===================================================================================================
-- GUIs  ·  DOS ScreenGui a proposito
-- ===================================================================================================
-- El boton de abrir vive en su PROPIO ScreenGui porque UITheme.panel apaga el .Enabled del ScreenGui que le
-- pases al cerrar: si el boton estuviera dentro, se apagaria con el panel y no habria forma de reabrirlo.
-- Ademas HubClient se LLEVA este boton a su columna (lo busca por .Text == "STORE" entre todos los TextButton
-- del PlayerGui), asi que tiene que poder existir fuera del panel.
local gui = Instance.new("ScreenGui")
gui.Name = "StoreMenu"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local guiPanel = Instance.new("ScreenGui")
guiPanel.Name = "StorePanel"; guiPanel.ResetOnSpawn = false; guiPanel.IgnoreGuiInset = true
guiPanel.DisplayOrder = 64 -- por encima del Hub (5) y del Lobby (45), en la misma banda que Forge/Quests
guiPanel.Enabled = false
guiPanel.Parent = player.PlayerGui

-- ===== Boton STORE (lateral derecha; el Hub lo adopta y lo convierte en icono) =====
-- OJO: este boton NO lleva hijos. HubClient, al adoptarlo, vacia el .Text y le mete SU icono y SU etiqueta,
-- pero no borra lo que ya hubiera: cualquier TextLabel/Frame que le pusieramos aqui saldria pintado ENCIMA del
-- dibujo del Hub. El UICorner/UIStroke/UIGradient si son seguros (el Hub los reutiliza en vez de duplicarlos).
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(118, UITheme.TACTIL_MIN) -- 44 de alto: minimo tactil en movil
toggle.Position = UDim2.new(1, -128, 0, 224)            -- mitad derecha: el pulgar izquierdo es del joystick
toggle.Text = "STORE" -- INTOCABLE: es la clave con la que el Hub encuentra este boton
toggle.Font = UITheme.fuente.dato
toggle.TextSize = 16
toggle.TextColor3 = ORO
toggle.Parent = gui
-- Placa plana (sin degradado) porque el texto va en el PROPIO boton: un UIGradient en un TextButton tiñe
-- tambien su texto, y aqui no podemos sacar el texto a un label hijo (ver nota de arriba).
UITheme.placa(toggle, { fondo = Color3.fromRGB(44, 40, 36), radio = UITheme.radio.boton, sinGradiente = true, bordeTransp = 0.3 })
-- El feedback de pulsacion se deja en AutoButtonColor y NO en UITheme.pulsacion: al adoptar el boton, HubClient
-- conecta SU propio resalte (y pone AutoButtonColor=false). Con pulsacion() quedarian los dos escuchando y cada
-- uno tweenearia el BackgroundColor3 a su color base -> el icono de la tienda parpadearia en marron al pasar el
-- dedo. AutoButtonColor se apaga solo en el traspaso; una conexion, no.
toggle.AutoButtonColor = true

-- ===================================================================================================
-- PANEL
-- ===================================================================================================
local ANCHO, ALTO = 560, 560
local overlay, panel, barra, api = UITheme.panel(guiPanel, ANCHO, ALTO, "STORE", {
	acento = ORO,
	clave = "store", -- clave del contador de MenuAbierto
	velo = 0.5,      -- algo mas oscuro que el resto: queremos la atencion DENTRO de la tienda
})
panel.Active = true -- absorbe el toque sobre la placa, para que el InputBegan del overlay (de abajo) solo
                    -- salte cuando tocas FUERA del panel

-- C (fix): quitado el cerrar-al-tocar-fuera; los paneles se cierran SOLO con la X (peticion de Bastian).

-- ===== Saldo (Gems / Cash) en la cabecera =====
-- Ponerlo aqui no es decoracion: el jugador que abre la tienda quiere saber cuanto le falta, y ver "180 Gems"
-- justo al lado de un pack de 1200 es el mejor argumento de venta que hay. Solo LEE leaderstats.
local chips = Instance.new("Frame")
chips.Name = "Saldo"
chips.AnchorPoint = Vector2.new(1, 0)
chips.Position = UDim2.new(1, -66, 0, 12) -- -66: deja libre el boton de cerrar (44 + margen)
chips.Size = UDim2.fromOffset(260, 28)
chips.BackgroundTransparency = 1
chips.Parent = barra
local chipsLay = Instance.new("UIListLayout")
chipsLay.FillDirection = Enum.FillDirection.Horizontal
chipsLay.HorizontalAlignment = Enum.HorizontalAlignment.Right
chipsLay.VerticalAlignment = Enum.VerticalAlignment.Center
chipsLay.Padding = UDim.new(0, 8)
chipsLay.Parent = chips

local function miles(n) -- 12500 -> 12,500 (los numeros largos sin separador se leen mal de un vistazo)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function chip(nombre, dibujo, color, orden)
	local c = Instance.new("Frame")
	c.Name = nombre
	c.Size = UDim2.fromOffset(104, 26)
	c.LayoutOrder = orden
	c.Parent = chips
	UITheme.placa(c, { fondo = Color3.fromRGB(30, 29, 38), radio = UITheme.radio.pildora, bordeTransp = 0.5 })
	UITheme.icono(c, dibujo, color, { lado = 16, pos = UDim2.new(0, 9, 0.5, 0), anchor = Vector2.new(0, 0.5) })
	return UITheme.etiqueta(c, "0", {
		fuente = UITheme.fuente.dato, tam = 13, color = UITheme.color.texto,
		pos = UDim2.new(0, 30, 0, 0), tamano = UDim2.new(1, -38, 1, 0), alignY = Enum.TextYAlignment.Center,
	})
end
local lblGems = chip("ChipGems", "gema", Color3.fromRGB(160, 120, 245), 1)
local lblCash = chip("ChipCash", "monedas", ORO, 2)

task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 20)
	if not ls then return end
	for _, par in ipairs({ { "Gems", lblGems }, { "Cash", lblCash } }) do
		local v = ls:WaitForChild(par[1], 10)
		if v then
			par[2].Text = miles(v.Value)
			v.Changed:Connect(function(nuevo) par[2].Text = miles(nuevo) end)
		end
	end
end)

-- ===== Lista =====
local scroll = UITheme.scroll(panel, {
	tamano = UDim2.new(1, -28, 1, -76),
	pos = UDim2.new(0, 14, 0, 64),
	padding = 12,
	relleno = 14,
})
local ordenLayout = 0 -- LayoutOrder incremental: en la lista se mezclan cabeceras, la rejilla y las filas de
                      -- pases; sin esto el UIListLayout las ordenaria por TIPO de instancia, no por aparicion

-- ===================================================================================================
-- DATOS -> TEXTO
-- ===================================================================================================
local NOMBRE = { woods = "Verdant", frost = "Frost", ember = "Ember", rare = "Ancient", gems = "Gems", cash = "Cash" }

-- Orden FIJO de las recompensas dentro de un pack. El codigo viejo iteraba con pairs(), asi que el mismo pack
-- listaba sus premios en un orden distinto en cada repintado: parece un bug aunque no lo sea, y ademas
-- enterraba las Gems (lo que de verdad se vende) en cualquier sitio. Aqui van primero las monedas premium.
local ORDEN = { "gems", "cash", "rare", "woods", "frost", "ember" }
-- Cada material con su tono (el mismo lenguaje de color que los mundos: Verdant verde, Frost azul, Ember fuego).
local MAT_COLOR = {
	gems  = Color3.fromRGB(160, 120, 245),
	cash  = ORO,
	rare  = UITheme.rareza.legendario,
	woods = Color3.fromRGB(120, 200, 130),
	frost = Color3.fromRGB(110, 190, 235),
	ember = Color3.fromRGB(245, 130, 70),
}

-- Devuelve { {clave, cantidad}, ... } en el orden de ORDEN; lo que no este en ORDEN se añade al final (asi un
-- material nuevo en StoreData sale igualmente, sin tocar este fichero).
local function entradasDe(da)
	local lista, vistos = {}, {}
	for _, k in ipairs(ORDEN) do
		if da[k] then lista[#lista + 1] = { k, da[k] }; vistos[k] = true end
	end
	for k, v in pairs(da) do
		if not vistos[k] then lista[#lista + 1] = { k, v } end
	end
	return lista
end

-- ===================================================================================================
-- PIEZAS DE LA TIENDA
-- ===================================================================================================

-- Cabecera de seccion: tick de acento + rotulo a la izquierda, contador a la derecha. Sin caja ni fondo, que
-- una barra de titulo por seccion competiria con las tarjetas. El contador de pases ("2 / 5 OWNED") es un
-- empujon honesto: enseña lo que te falta sin mentir ni esconder lo comprado.
local function seccion(texto, color, contador)
	local h = Instance.new("Frame")
	h.Size = UDim2.new(1, 0, 0, 26)
	h.BackgroundTransparency = 1
	ordenLayout += 1; h.LayoutOrder = ordenLayout
	h.Parent = scroll

	local tick = Instance.new("Frame")
	tick.Size = UDim2.fromOffset(4, 15)
	tick.Position = UDim2.new(0, 2, 0, 6)
	tick.BackgroundColor3 = color
	tick.BorderSizePixel = 0
	tick.Parent = h
	Instance.new("UICorner", tick).CornerRadius = UDim.new(1, 0)

	UITheme.etiqueta(h, texto, {
		fuente = UITheme.fuente.titulo, tam = 14, color = UITheme.color.texto,
		pos = UDim2.new(0, 14, 0, 4), tamano = UDim2.new(0.6, 0, 0, 18),
	})
	if contador then
		UITheme.etiqueta(h, contador, {
			fuente = UITheme.fuente.etiqueta, tam = 12, color = UITheme.color.textoTenue,
			pos = UDim2.new(0.5, 0, 0, 5), tamano = UDim2.new(0.5, -4, 0, 16),
			align = Enum.TextXAlignment.Right,
		})
	end
	return h
end

-- Placa de estado "ya es tuyo" (PURCHASED / OWNED). Es un Frame y NO un boton a proposito: si fuera un boton
-- daria feedback de pulsacion y el jugador pensaria que puede volver a comprarlo.
local function placaEstado(padre, texto, tamano, pos)
	local p = Instance.new("Frame")
	p.Name = "Estado"
	p.Size = tamano
	p.Position = pos
	p.AnchorPoint = Vector2.new(0, 0)
	p.Parent = padre
	UITheme.placa(p, {
		fondo = Color3.fromRGB(30, 44, 33), alto = Color3.fromRGB(42, 62, 46), bajo = Color3.fromRGB(22, 33, 25),
		radio = UITheme.radio.boton, borde = Color3.fromRGB(16, 26, 19), bordeTransp = 0.25,
	})
	UITheme.icono(p, "check", UITheme.color.ok, { lado = 16, pos = UDim2.new(0, 12, 0.5, 0), anchor = Vector2.new(0, 0.5) })
	UITheme.etiqueta(p, texto, {
		fuente = UITheme.fuente.dato, tam = 13, color = UITheme.color.ok,
		pos = UDim2.new(0, 32, 0, 0), tamano = UDim2.new(1, -40, 1, 0), alignY = Enum.TextYAlignment.Center,
	})
	return p
end

-- ===== TARJETA DE PACK =====
-- 'recomendado' = el pack que queremos que compre: borde dorado + cinta BEST VALUE. Solo UNO puede llevarlo;
-- si hubiera varios "destacados" no destacaria ninguno.
-- 250 y no 256: con 256 la cuenta salia 256*2 + 10 de hueco = 522, que es EXACTAMENTE el ancho util del
-- scroll. A cero de holgura, cualquier pixel de mas (grosor de la barra de scroll, un padding que cambie)
-- recorta el borde derecho de la segunda columna, porque el scroll lleva ClipsDescendants. Con 250 sobran 12.
local CELDA = Vector2.new(250, 196)

local function tarjetaPack(rejilla, p, comprado, recomendado)
	local col = p.color or UITheme.rareza.raro
	local bordeCol = recomendado and UITheme.rareza.legendario or col

	local card = Instance.new("Frame")
	card.Name = "Pack_" .. tostring(p.id)
	ordenLayout += 1; card.LayoutOrder = ordenLayout
	card.Parent = rejilla
	UITheme.placa(card, {
		fondo = comprado and Color3.fromRGB(30, 34, 31) or UITheme.color.fondoPlaca,
		alto = comprado and Color3.fromRGB(40, 46, 42) or Color3.fromRGB(52, 50, 63),
		bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.tarjeta,
		borde = bordeCol,
		grosor = recomendado and 2 or 1,
		bordeTransp = comprado and 0.7 or (recomendado and 0.05 or 0.45),
	})

	-- Cinta corta pegada al borde de arriba: da el codigo de color del pack sin pintar un fondo saturado.
	local cinta = Instance.new("Frame")
	cinta.Size = UDim2.new(0.34, 0, 0, 3)
	cinta.Position = UDim2.new(0, 12, 0, 0)
	cinta.BackgroundColor3 = bordeCol
	cinta.BackgroundTransparency = comprado and 0.6 or 0
	cinta.BorderSizePixel = 0
	cinta.Parent = card
	Instance.new("UICorner", cinta).CornerRadius = UDim.new(1, 0)

	UITheme.icono(card, "gema", comprado and UITheme.color.apagado or col, {
		lado = 28, pos = UDim2.new(0, 12, 0, 14), anchor = Vector2.new(0, 0),
	})
	UITheme.etiqueta(card, p.nombre, {
		fuente = UITheme.fuente.titulo, tam = 15,
		color = comprado and UITheme.color.textoTenue or UITheme.color.texto,
		pos = UDim2.new(0, 48, 0, 14), tamano = UDim2.new(1, -60, 0, 19),
	})
	if p.oneTime then
		-- Escasez real (el server SI lo respeta: MetaStore no vuelve a entregar un oneTime). No anunciamos
		-- 'limite' de StoreData porque hoy NADIE lo hace cumplir, y prometer un limite falso es mentir.
		UITheme.etiqueta(card, "ONE-TIME OFFER", {
			fuente = UITheme.fuente.etiqueta, tam = 10, color = UITheme.color.textoTenue,
			pos = UDim2.new(0, 48, 0, 33), tamano = UDim2.new(1, -60, 0, 13),
		})
	end

	-- Cinta de destacado: sobresale por arriba (fuera de la caja) para romper la rejilla; si estuviera dentro
	-- y alineada seria una tarjeta mas.
	-- El destacado SIEMPRE lleva cinta, aunque el pack no traiga 'banner' en StoreData: si el dorado se mueve a
	-- otro pack (porque el de entrada ya esta comprado) no puede quedarse un borde de oro sin explicacion.
	local textoBanner = recomendado and (p.banner or "BEST VALUE") or p.banner
	if textoBanner then
		local esOro = recomendado
		local ban = Instance.new("Frame")
		ban.Name = "Banner"
		ban.AnchorPoint = Vector2.new(1, 0)
		ban.Position = UDim2.new(1, -10, 0, -9)
		ban.Size = UDim2.fromOffset(esOro and 92 or 78, 20)
		ban.ZIndex = 4
		ban.Parent = card
		UITheme.placa(ban, {
			fondo = esOro and UITheme.rareza.legendario or UITheme.tono(col, -0.35),
			alto = esOro and UITheme.tono(UITheme.rareza.legendario, 0.35) or UITheme.tono(col, -0.1),
			bajo = esOro and UITheme.tono(UITheme.rareza.legendario, -0.2) or UITheme.tono(col, -0.5),
			radio = UITheme.radio.pildora, grosor = 1, bordeTransp = 0.2,
		})
		local t = UITheme.etiqueta(ban, textoBanner, {
			fuente = UITheme.fuente.dato, tam = 10,
			color = esOro and Color3.fromRGB(38, 27, 8) or UITheme.color.texto,
			tamano = UDim2.new(1, 0, 1, 0), align = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Center,
		})
		t.ZIndex = 5 -- el texto va en un label hijo: el UIGradient de la placa tiñe el .Text del padre
		ban.BackgroundTransparency = comprado and 0.5 or 0
	end

	UITheme.separador(card, 54, { izq = 12, margen = 24 })

	-- Contenido del pack en DOS columnas: los packs gordos traen 6 lineas y en una sola columna la tarjeta
	-- crecia el doble de alto que las demas y descuadraba la rejilla.
	local lista = entradasDe(p.da)
	local porCol = math.ceil(#lista / 2)
	for i, e in ipairs(lista) do
		local clave, cant = e[1], e[2]
		local columna = (i <= porCol) and 0 or 1
		local fila = (i <= porCol) and (i - 1) or (i - porCol - 1)
		local x = 14 + columna * 118
		local y = 62 + fila * 17
		local tinte = comprado and UITheme.color.apagado or (MAT_COLOR[clave] or UITheme.color.textoSuave)
		-- Rombo de 9 px en vez de un pictograma completo: a este tamaño un dibujo de 5 piezas se convierte en
		-- una mancha, y el color ya identifica el material.
		UITheme.pieza(card, 9, 9, 0, 0, tinte, 2, 45).Position = UDim2.new(0, x + 4, 0, y + 8)
		UITheme.etiqueta(card, miles(cant) .. " " .. (NOMBRE[clave] or clave), {
			fuente = UITheme.fuente.etiqueta, tam = 12,
			color = comprado and UITheme.color.textoTenue or UITheme.color.textoSuave,
			pos = UDim2.new(0, x + 14, 0, y), tamano = UDim2.new(0, 104, 0, 16),
		})
	end

	if comprado then
		placaEstado(card, "PURCHASED", UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 0, 140))
		return
	end

	-- Precio tachado + ahorro: el ancla de precio es lo que sube el ticket. Va JUSTO encima del boton, que es
	-- donde se mira antes de decidir. RichText porque <s> es la unica forma de tachar en Roblox.
	if p.valor and p.valor > p.robux then
		local ahorro = math.floor((1 - p.robux / p.valor) * 100 + 0.5)
		UITheme.etiqueta(card, string.format('<s>R$ %d</s>   <font color="#E2B246">SAVE %d%%</font>', p.valor, ahorro), {
			fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoTenue, rich = true,
			pos = UDim2.new(0, 14, 0, 122), tamano = UDim2.new(1, -28, 0, 14),
		})
	end

	local btn = UITheme.boton(card, "R$ " .. p.robux, {
		tamano = UDim2.new(1, -24, 0, 44), -- 44 de alto: minimo tactil
		pos = UDim2.new(0, 12, 0, 140),
		tam = 16,
		nombre = "Comprar",
		color = recomendado and Color3.fromRGB(58, 47, 24) or Color3.fromRGB(34, 44, 36),
		altoColor = recomendado and Color3.fromRGB(84, 68, 32) or Color3.fromRGB(48, 62, 50),
		bajoColor = recomendado and Color3.fromRGB(40, 32, 16) or Color3.fromRGB(25, 33, 27),
		textoColor = recomendado and UITheme.rareza.legendario or UITheme.color.ok,
		acento = recomendado and UITheme.rareza.legendario or UITheme.color.ok,
		ancho = CELDA.X - 24, -- lo usa la barra de acento para calcular su ancho (el Size real es 'tamano')
	})
	btn.MouseButton1Click:Connect(function()
		if p.productId and p.productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, p.productId)
		else
			warn("[Store] '" .. p.nombre .. "' no tiene productId (ponlo en StoreData)")
		end
	end)
end

-- ===== FILA DE GAMEPASS =====
-- Fila ancha, no tarjeta: darle a los pases OTRO ritmo que a los packs deja claro de un vistazo que son otra
-- cosa (compra unica, permanente) sin necesidad de explicarlo.
local PASE_ICONO = { extradrop = "martillo", vip = "estrella", cash2x = "monedas", gems2x = "gema", extraslot = "escudo" }

local function filaPase(g, owned)
	local col = owned and UITheme.color.ok or UITheme.acentos.classes

	local fila = Instance.new("Frame")
	fila.Name = "Pass_" .. tostring(g.id)
	fila.Size = UDim2.new(1, 0, 0, 78)
	ordenLayout += 1; fila.LayoutOrder = ordenLayout
	fila.Parent = scroll
	UITheme.placa(fila, {
		fondo = owned and Color3.fromRGB(31, 38, 33) or UITheme.color.fondoPlaca,
		alto = owned and Color3.fromRGB(42, 52, 45) or Color3.fromRGB(50, 48, 60),
		bajo = Color3.fromRGB(25, 24, 32),
		radio = UITheme.radio.placa,
		borde = owned and Color3.fromRGB(30, 60, 38) or UITheme.color.borde,
		bordeTransp = 0.3,
	})

	-- Caja del icono con su propio fondo: separa el pictograma del degradado de la fila y da un punto de
	-- entrada a la lectura por la izquierda.
	local caja = Instance.new("Frame")
	caja.Size = UDim2.fromOffset(46, 46)
	caja.Position = UDim2.new(0, 14, 0.5, 0)
	caja.AnchorPoint = Vector2.new(0, 0.5)
	caja.Parent = fila
	UITheme.placa(caja, { fondo = Color3.fromRGB(28, 27, 35), radio = UITheme.radio.tarjeta, bordeTransp = 0.55 })
	UITheme.icono(caja, PASE_ICONO[g.id] or "rayo", owned and UITheme.color.ok or col, {
		lado = 28, pos = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5),
	})

	UITheme.etiqueta(fila, g.nombre, {
		fuente = UITheme.fuente.dato, tam = 15, color = UITheme.color.texto,
		pos = UDim2.new(0, 72, 0, 17), tamano = UDim2.new(1, -220, 0, 19),
	})
	-- CUMPLIMIENTO paid random items: el VIP se anuncia como "Daily Gems + free spin + VIP tag", y esa
	-- tirada gratis es un OBJETO ALEATORIO. A un jugador restringido no se le puede ni PROMETER (la norma no
	-- es solo no venderlo, es no ofrecerlo), y ademas el servidor ya no se la da -- asi que si dejaramos el
	-- texto le estariamos cobrando 499 Robux por algo que no va a recibir, que acaba en queja o reembolso.
	-- El resto del pase (Gems diarias, tag) si lo recibe, por eso NO se le oculta el producto entero.
	local desc = g.desc
	if restringido() and g.id == "vip" then desc = "Daily Gems + VIP tag" end
	UITheme.etiqueta(fila, desc, {
		fuente = UITheme.fuente.etiqueta, tam = 12,
		color = owned and UITheme.color.textoTenue or UITheme.color.textoSuave,
		pos = UDim2.new(0, 72, 0, 39), tamano = UDim2.new(1, -220, 0, 16),
	})

	if owned then
		placaEstado(fila, "OWNED", UDim2.new(0, 132, 0, 44), UDim2.new(1, -146, 0.5, -22))
		return
	end

	local btn = UITheme.boton(fila, "R$ " .. g.robux, {
		ancho = 132, alto = 44,
		pos = UDim2.new(1, -146, 0.5, -22),
		tam = 16,
		nombre = "Comprar",
		color = Color3.fromRGB(36, 33, 48), altoColor = Color3.fromRGB(52, 47, 68), bajoColor = Color3.fromRGB(26, 24, 34),
		textoColor = UITheme.color.texto,
		acento = col,
	})
	btn.MouseButton1Click:Connect(function()
		local id = MonetizationData.Gamepasses[g.id]
		if id and id ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			warn("[Store] '" .. g.nombre .. "' no tiene gamepassId (ponlo en MonetizationData.Gamepasses)")
		end
	end)
end

-- ===================================================================================================
-- CONSTRUIR
-- ===================================================================================================
-- Elige QUE pack lleva el destacado dorado. Preferimos el que StoreData marca como "BEST VALUE"; si ese ya
-- esta comprado (es oneTime) el dorado se mueve al de mejor relacion valor/precio que quede, para que la
-- tienda nunca se quede sin ancla despues de la primera compra.
local function elegirRecomendado(comprados)
	local mejorBanner, mejorRatio, ratioTope = nil, nil, -1
	for _, p in ipairs(StoreData.Packs) do
		if not comprados[p.id] then
			if not mejorBanner and p.banner == "BEST VALUE" then mejorBanner = p end
			local r = (p.valor and p.robux and p.robux > 0) and (p.valor / p.robux) or 0
			if r > ratioTope then ratioTope, mejorRatio = r, p end
		end
	end
	return mejorBanner or mejorRatio
end

local function construir()
	-- Limpia y repinta: asi refleja el estado de compra ACTUAL (packs oneTime -> PURCHASED, pases -> OWNED).
	for _, c in ipairs(scroll:GetChildren()) do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then c:Destroy() end
	end
	ordenLayout = 0

	local comprados = {}
	for _, p in ipairs(StoreData.Packs) do
		comprados[p.id] = (p.oneTime and player:GetAttribute("Pack_" .. p.id)) and true or false
	end
	local recomendado = elegirRecomendado(comprados)

	seccion("VALUE PACKS", ORO)

	-- La rejilla va dentro de un contenedor con AutomaticSize: asi la lista vertical de fuera no necesita saber
	-- cuantas filas de packs hay (si mañana se añade un quinto pack, crece solo).
	local rejilla = Instance.new("Frame")
	rejilla.Name = "Packs"
	rejilla.Size = UDim2.new(1, 0, 0, 0)
	rejilla.AutomaticSize = Enum.AutomaticSize.Y
	rejilla.BackgroundTransparency = 1
	ordenLayout += 1; rejilla.LayoutOrder = ordenLayout
	rejilla.Parent = scroll
	local gridLay = Instance.new("UIGridLayout")
	gridLay.CellSize = UDim2.fromOffset(CELDA.X, CELDA.Y)
	gridLay.CellPadding = UDim2.fromOffset(10, 14)
	gridLay.FillDirectionMaxCells = 2 -- 2 columnas SIEMPRE: si el UIScale encoge el panel no quiero que la
	                                  -- rejilla decida sola reflotar a 1 columna a mitad de sesion
	gridLay.SortOrder = Enum.SortOrder.LayoutOrder
	gridLay.Parent = rejilla

	for _, p in ipairs(StoreData.Packs) do
		tarjetaPack(rejilla, p, comprados[p.id], recomendado == p)
	end

	local tengo = 0
	for _, g in ipairs(StoreData.Gamepasses) do
		if player:GetAttribute("Pass_" .. g.id) == true then tengo += 1 end
	end
	seccion("GAMEPASSES", UITheme.acentos.classes, tengo .. " / " .. #StoreData.Gamepasses .. " OWNED")

	for _, g in ipairs(StoreData.Gamepasses) do
		filaPase(g, player:GetAttribute("Pass_" .. g.id) == true)
	end

	-- Cierre honesto: quien duda de si un pack "se pierde" al morir compra menos. Ademas recuerda que el precio
	-- lo cobra Roblox, no nosotros.
	local pie = UITheme.etiqueta(scroll, "Purchases are permanent and granted instantly. Prices are charged by Roblox.", {
		fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoTenue,
		tamano = UDim2.new(1, -8, 0, 30), align = Enum.TextXAlignment.Center, wrap = true,
	})
	ordenLayout += 1; pie.LayoutOrder = ordenLayout
end

-- ===================================================================================================
-- ABRIR / CERRAR / VISIBILIDAD
-- ===================================================================================================
toggle.MouseButton1Click:Connect(function()
	if not api.estaAbierto() then construir() end -- repintar al abrir: los atributos pueden haber cambiado
	api.alternar()
end)

-- Segunda puerta a la tienda: el "+" que va pegado al saldo de Gems en el HUD. Hasta ahora la UNICA forma de
-- llegar aqui era cazar un icono de 60px en la columna lateral llamado "Store", y en un F2P de movil el boton
-- que mas convierte es justo el que esta al lado del numero que se te queda corto.
-- Se comunica por ATRIBUTO y no por remote: es cliente-a-cliente (HudClient -> aqui) y no tiene por que pasar
-- por el servidor. Es el mismo patron que ya usa el PLAY del lobby con "AbrirMundos".
player:GetAttributeChangedSignal("AbrirStore"):Connect(function()
	if player:GetAttribute("InMatch") == true then return end -- en partida no se abre nada
	if not api.estaAbierto() then construir() end
	api.abrir()
end)

-- Repintado en caliente: si la compra se confirma con la tienda ABIERTA (el server pone Pack_/Pass_), la
-- tarjeta pasa sola a PURCHASED/OWNED. Antes se quedaba en "BUY" y parecia que el pago no habia entrado.
for _, p in ipairs(StoreData.Packs) do
	player:GetAttributeChangedSignal("Pack_" .. p.id):Connect(function()
		if api.estaAbierto() then construir() end
	end)
end
for _, g in ipairs(StoreData.Gamepasses) do
	player:GetAttributeChangedSignal("Pass_" .. g.id):Connect(function()
		if api.estaAbierto() then construir() end
	end)
end

-- Solo en el lobby (oculta en partida)
local function refrescarVis()
	local enPartida = player:GetAttribute("InMatch") == true
	toggle.Visible = not enPartida
	if enPartida and api.estaAbierto() then api.cerrar() end -- cerrar por la api, no bajando .Visible a mano:
	                                                          -- si no, MenuAbierto se quedaria pegado en true
end
player:GetAttributeChangedSignal("InMatch"):Connect(refrescarVis)
refrescarVis()

construir() -- pintado inicial (se repinta al abrir y en cada cambio de Pack_/Pass_)
