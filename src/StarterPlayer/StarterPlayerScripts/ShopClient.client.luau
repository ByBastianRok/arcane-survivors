-- ShopClient (LocalScript) · FASE 6 - PERKS (permanentes): mejoras + ARMAS (2 pestanas), con Cash.
-- Boton PERKS solo en el LOBBY. La compra la valida el SERVIDOR (MetaStore). Cash/Gems via leaderstats.
--
-- === QUE CAMBIO AQUI (solo la CAPA VISUAL; remotes, handlers y atributos siguen igual) ===
-- Antes era una lista de filas planas con un boton verde "BUY  $250" y el nivel escrito como texto
-- ("Damage Up  (Lv 3/8)"). Problemas reales de eso:
--   · el nivel en texto hay que LEERLO; en movil, con el pulgar tapando media pantalla, nadie compara
--     "Lv 3/8" contra "Lv 6/8" de un vistazo. Ahora va en PIPS (puntitos llenos/vacios): se cuenta con
--     la vista periferica, como una barra de vida.
--   · las seis mejoras se veian IDENTICAS (mismo verde, mismo texto). Ahora cada una tiene su
--     pictograma DIBUJADO y su tono propio -> memoria muscular: "la roja es dano".
--   · lo que NO te puedes permitir seguia visible pero indistinguible. Ahora sale con el precio en
--     rojo, el boton apagado y CUANTO te falta. Ver lo que te falta es lo que empuja a jugar otra run;
--     esconderlo mata la unica motivacion de la pantalla.
-- Todo el estilo sale de UITheme (la placa de piedra del lobby), no de colores a mano.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================================================================================================
-- BOTON DE ABRIR  ·  se crea LO PRIMERO, antes de cualquier require/WaitForChild
-- ===================================================================================================
-- HubClient adopta este boton buscandolo entre todos los TextButton del PlayerGui por su .Text EXACTO
-- ("PERKS") y lo mete en la columna del lobby, y se rinde a los 15s. Si lo crearamos DESPUES de los
-- WaitForChild de Remotes/UITheme, un arranque lento (o un modulo que aun no esta espejado a Studio)
-- dejaria el boton fuera de la columna. Creandolo aqui, el peor caso es un boton que no responde,
-- no un boton que desaparece.
local gui = Instance.new("ScreenGui")
gui.Name = "Shop"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 40; gui.Parent = playerGui

local openBtn = Instance.new("TextButton")
-- 60x68 = la MISMA celda que usa la columna del Hub, asi el boton se ve igual lo adopte el Hub o no.
-- Colocado a la DERECHA a media altura: el cuadrante inferior izquierdo es del joystick (regla movil).
openBtn.Size = UDim2.new(0, 60, 0, 68); openBtn.AnchorPoint = Vector2.new(1, 0.5)
openBtn.Position = UDim2.new(1, -12, 0.5, 60)
openBtn.BackgroundColor3 = Color3.fromRGB(38, 37, 47); openBtn.AutoButtonColor = false
openBtn.Font = Enum.Font.GothamBold; openBtn.TextSize = 13; openBtn.TextTransparency = 1
openBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
openBtn.Text = "PERKS" -- NO TOCAR: es la clave con la que HubClient lo encuentra
openBtn.Parent = gui

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local shopSync = remotes:WaitForChild("ShopSync")
local buyUpgrade = remotes:WaitForChild("BuyUpgrade")
local buyWeapon = remotes:WaitForChild("BuyWeapon")
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponData"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))

local ORDEN_ARMAS = { "Pistol", "Shotgun", "SMG", "Sniper", "Rocket Launcher" }

local ACENTO = UITheme.acentos.perks -- el mismo teal que lleva PERKS en la columna del Hub

-- Pictograma + tono por mejora. El id manda (el 'nombre' es texto de cara al jugador y puede cambiar
-- sin avisar). "recarga" es un id HEREDADO: hoy da CRIT, por eso lleva chispa/estrella y no un reloj.
-- Los tonos son deliberadamente DISTINTOS entre si: seis tarjetas del mismo color = lista de plantilla.
local PINTA = {
	dano      = { icono = "espada",   color = Color3.fromRGB(206, 96, 82) },
	vida      = { icono = "corazon",  color = Color3.fromRGB(92, 186, 108) },
	velocidad = { icono = "rayo",     color = Color3.fromRGB(104, 172, 226) },
	recarga   = { icono = "estrella", color = Color3.fromRGB(224, 118, 150) },
	suerte    = { icono = "gema",     color = Color3.fromRGB(150, 108, 214) },
	cash      = { icono = "monedas",  color = Color3.fromRGB(226, 178, 70) },
}
local PINTA_POR_DEFECTO = { icono = "rombo", color = ACENTO } -- mejora nueva sin entrada: no deja hueco

-- El boton de abrir, con el lenguaje de placa. Los hijos se llaman HubIcono/HubLabel/HubAcento A PROPOSITO:
-- HubClient los REUSA por nombre al adoptar (FindFirstChild(...) or Instance.new(...)). Si les pusiera otro
-- nombre, el Hub crearia los suyos ENCIMA y quedarian dos iconos superpuestos.
UITheme.placa(openBtn, { radio = 10 })
UITheme.icono(openBtn, "rombo", ACENTO, { nombre = "HubIcono", lado = 30, pos = UDim2.new(0.5, 0, 0, 7) })
UITheme.etiqueta(openBtn, "Perks", {
	nombre = "HubLabel", tam = 11, color = UITheme.color.textoSuave,
	pos = UDim2.new(0, 0, 0, 40), tamano = UDim2.new(1, 0, 0, 13), align = Enum.TextXAlignment.Center,
})
UITheme.acentoBarra(openBtn, ACENTO, { nombre = "HubAcento" })
-- OJO: aqui NO se llama a UITheme.pulsacion. Cuando el Hub adopta el boton le engancha SU propio resalte,
-- y dos tweens sobre el mismo BackgroundColor3 se pelean (parpadeo al soltar el dedo).

-- ===================================================================================================
-- PANEL
-- ===================================================================================================
-- ScreenGui APARTE: UITheme.panel apaga el .Enabled de su padre al cerrar, asi que el boton de abrir NO
-- puede vivir aqui dentro (se apagaria con el panel y no habria forma de volver a abrirlo).
local guiPanel = Instance.new("ScreenGui")
guiPanel.Name = "ShopPanel"; guiPanel.ResetOnSpawn = false; guiPanel.IgnoreGuiInset = true
guiPanel.DisplayOrder = 61; guiPanel.Parent = playerGui

local ANCHO_PANEL, ALTO_PANEL = 580, 520
-- (el overlay y la barra no hacen falta aqui: el overlay ya lleva Active=true de fabrica -- si no, los
-- toques lo atravesarian y llegarian al PLAY de debajo -- y la barra ya trae titulo y boton de cerrar)
local _overlay, panel, _barra, panelApi = UITheme.panel(guiPanel, ANCHO_PANEL, ALTO_PANEL, "PERKS", {
	acento = ACENTO,
	clave = "perks", -- clave del contador de MenuAbierto (varios paneles a la vez no se pisan)
})

-- Subtitulo: la unica linea que explica POR QUE esto no es la tienda de la run (Coins vs Cash).
UITheme.etiqueta(panel, "Permanent - active in every run", {
	nombre = "Sub", tam = 12, color = UITheme.color.textoTenue,
	pos = UDim2.new(0, 22, 0, 58), tamano = UDim2.new(0.5, 0, 0, 16),
})

-- --- Contadores de moneda (arriba a la derecha) ---
-- Dos pildoras con el pictograma dibujado. Cash es la moneda de ESTA pantalla, por eso va primero y con
-- el numero en el tono de acento; Gems va detras y apagado (aqui no se gasta).
local function pildoraMoneda(x, dibujo, color)
	local caja = Instance.new("Frame")
	caja.Size = UDim2.fromOffset(118, 30)
	caja.AnchorPoint = Vector2.new(1, 0)
	caja.Position = UDim2.new(1, x, 0, 54)
	caja.Parent = panel
	UITheme.placa(caja, {
		fondo = Color3.fromRGB(30, 29, 38), alto = Color3.fromRGB(40, 39, 50),
		bajo = Color3.fromRGB(24, 23, 31), radio = UITheme.radio.boton, bordeTransp = 0.45,
	})
	UITheme.icono(caja, dibujo, color, { lado = 20, pos = UDim2.new(0, 7, 0.5, 0), anchor = Vector2.new(0, 0.5) })
	return UITheme.etiqueta(caja, "0", {
		fuente = UITheme.fuente.dato, tam = 14, color = color,
		pos = UDim2.new(0, 30, 0, 0), tamano = UDim2.new(1, -38, 1, 0),
		align = Enum.TextXAlignment.Right, alignY = Enum.TextYAlignment.Center,
	})
end
local lblCash = pildoraMoneda(-142, "monedas", Color3.fromRGB(226, 178, 70))
local lblGems = pildoraMoneda(-18, "gema", Color3.fromRGB(120, 178, 226))

-- --- Pestana (hoy solo UPGRADES; la de armas existe en codigo, ver setTab) ---
local tabUpg = Instance.new("TextButton")
tabUpg.Size = UDim2.new(0, 124, 0, 30)
tabUpg.Position = UDim2.new(0, 20, 0, 94)
tabUpg.AutoButtonColor = false
tabUpg.Font = UITheme.fuente.dato; tabUpg.TextSize = 13; tabUpg.TextTransparency = 1
tabUpg.TextColor3 = UITheme.color.texto
tabUpg.Text = "UPGRADES"
tabUpg.Parent = panel
UITheme.placa(tabUpg, { radio = UITheme.radio.boton, bordeTransp = 0.4 })
local lblTab = UITheme.etiqueta(tabUpg, "UPGRADES", {
	tam = 13, fuente = UITheme.fuente.dato, color = UITheme.color.texto,
	tamano = UDim2.new(1, 0, 1, -4), align = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Center,
})
lblTab.ZIndex = 2
local subrayadoTab = UITheme.acentoBarra(tabUpg, ACENTO, {
	ancho = 30, alto = 3, pos = UDim2.new(0, 12, 1, -7), anchor = Vector2.new(0, 0), -- a la IZQUIERDA: no centrar todo
})

-- Contador de mejoras al maximo, al lado de la pestana: un remate para el que ya lo tiene todo subido.
local lblProgreso = UITheme.etiqueta(panel, "", {
	nombre = "Progreso", tam = 12, color = UITheme.color.textoTenue,
	pos = UDim2.new(0, 156, 0, 94), tamano = UDim2.new(0.5, 0, 0, 30),
	alignY = Enum.TextYAlignment.Center,
})

local scroll = UITheme.scroll(panel, {
	pos = UDim2.new(0, 18, 0, 134),
	tamano = UDim2.new(1, -36, 0, ALTO_PANEL - 134 - 66),
	padding = 8,
})

local closeBtn = UITheme.boton(panel, "CLOSE", {
	ancho = 150, alto = 44, variante = "peligro", tam = 14,
	anchor = Vector2.new(1, 1), pos = UDim2.new(1, -18, 1, -14),
	nombre = "CerrarAbajo",
})
-- Va abajo a la DERECHA (no centrado): el pulgar derecho llega solo y no cae sobre el joystick.

local ultimoUpgrades = {}
local ownedWeapons = {}
local tab = "upgrades"

local function leerStat(nombre)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(nombre)
	return v and v.Value or 0
end

-- Separador de millares: los precios llegan a 4-5 cifras y "4300" se lee peor que "4,300" de un vistazo.
local function num(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function actualizarCurrency()
	lblCash.Text = num(leerStat("Cash"))
	lblGems.Text = num(leerStat("Gems"))
end
local function limpiarFilas()
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
end

-- ===================================================================================================
-- PIPS  ·  el nivel de un vistazo
-- ===================================================================================================
-- Un puntito por nivel: lleno = comprado. Dos detalles a proposito:
--   · el lleno es MAS GRANDE que el vacio, para que se distinga tambien sin color (daltonismo / brillo
--     de movil al sol), no solo por tono;
--   · hay un hueco extra cada 4 pips. Sin el, ocho puntos a distancia identica hay que CONTARLOS; con
--     el grupo, "5 de 8" se ve como "cuatro y uno". Ademas rompe el reparto perfectamente regular, que
--     es justo lo que hace que una lista parezca generada.
local function pintarPips(padre, nivel, maximo, color)
	local caja = Instance.new("Frame")
	caja.Name = "Pips"
	caja.BackgroundTransparency = 1
	caja.Size = UDim2.new(0, maximo * 13 + 8, 0, 10)
	caja.Position = UDim2.new(0, 60, 0, 40)
	caja.Parent = padre

	local vacio = UITheme.tono(color, -0.62) -- guarda un rastro del tono: el hueco sigue "siendo" la mejora
	for i = 1, maximo do
		local lleno = i <= nivel
		local x = (i - 1) * 13 + (i > 4 and 8 or 0)
		local p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0, 0.5)
		p.Position = UDim2.new(0, x, 0.5, 0)
		p.Size = lleno and UDim2.fromOffset(11, 8) or UDim2.fromOffset(9, 5)
		p.BackgroundColor3 = lleno and color or vacio
		p.BorderSizePixel = 0
		p.Parent = caja
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = p
		if lleno then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(UITheme.tono(color, 0.35), UITheme.tono(color, -0.2))
			g.Rotation = 90
			g.Parent = p
		end
	end
	return caja
end

-- Pildora estatica (MAX / OWNED): ocupa el sitio del boton pero NO es un TextButton, para que no se pueda
-- pulsar por error ni aparezca en la busqueda por .Text de HubClient.
local function pildoraEstado(padre, texto, color)
	local p = Instance.new("Frame")
	p.Size = UDim2.fromOffset(128, 44)
	p.AnchorPoint = Vector2.new(1, 0)
	p.Position = UDim2.new(1, -12, 0, 14)
	p.Parent = padre
	UITheme.placa(p, {
		fondo = Color3.fromRGB(32, 31, 40), alto = Color3.fromRGB(44, 42, 54),
		bajo = Color3.fromRGB(26, 25, 33), radio = UITheme.radio.boton, bordeTransp = 0.4,
	})
	UITheme.icono(p, "check", color, { lado = 20, pos = UDim2.new(0, 14, 0.5, 0), anchor = Vector2.new(0, 0.5) })
	UITheme.etiqueta(p, texto, {
		fuente = UITheme.fuente.dato, tam = 14, color = color,
		pos = UDim2.new(0, 40, 0, 0), tamano = UDim2.new(1, -52, 1, 0),
		align = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Center,
	})
	return p
end

-- ===================================================================================================
-- TARJETA
-- ===================================================================================================
-- La usa TODO lo que se lista aqui (mejoras y armas). opts:
--   titulo · desc · icono · color · nivel/maximo (si hay, dibuja pips) · maxima=bool
--   boton = { texto, activo, accion, falta } | nil   (nil => sin boton)
--   estado = { texto, color } | nil                  (pildora estatica: MAX / OWNED)
local function crearTarjeta(opts)
	local color = opts.color or ACENTO
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -4, 0, 88)
	card.Parent = scroll
	UITheme.placa(card, {
		-- La maxima se levanta un pelin (mas clara): premia visualmente al que la termino, sin cambiar de color.
		fondo = opts.maxima and Color3.fromRGB(43, 42, 52) or UITheme.color.fondoPlaca,
		alto = opts.maxima and Color3.fromRGB(60, 58, 72) or Color3.fromRGB(52, 50, 63),
		bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.tarjeta, -- 7: MENOR que el del panel (14). Mismo radio en todo = look de plantilla.
		bordeTransp = 0.35,
	})

	-- Tick vertical pegado al canto izquierdo: es el unico sitio de la tarjeta donde el tono sale entero.
	local tick = Instance.new("Frame")
	tick.Size = UDim2.fromOffset(3, 50)
	tick.AnchorPoint = Vector2.new(0, 0.5)
	tick.Position = UDim2.new(0, 0, 0.5, 0)
	tick.BackgroundColor3 = color
	tick.BackgroundTransparency = opts.apagada and 0.5 or 0
	tick.BorderSizePixel = 0
	tick.Parent = card
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(1, 0); tc.Parent = tick

	UITheme.icono(card, opts.icono or "rombo", color, {
		lado = 32, pos = UDim2.new(0, 16, 0.5, 0), anchor = Vector2.new(0, 0.5),
	})

	local hayPips = opts.maximo ~= nil
	UITheme.etiqueta(card, opts.titulo or "", {
		nombre = "Titulo", fuente = UITheme.fuente.dato, tam = 15, color = UITheme.color.texto,
		pos = UDim2.new(0, 60, 0, hayPips and 12 or 22), tamano = UDim2.new(1, -212, 0, 20),
	})
	if hayPips then
		pintarPips(card, opts.nivel or 0, opts.maximo, color)
	end
	UITheme.etiqueta(card, opts.desc or "", {
		nombre = "Desc", tam = 12, color = UITheme.color.textoTenue,
		pos = UDim2.new(0, 60, 0, hayPips and 58 or 44), tamano = UDim2.new(1, -212, 0, 16),
	})

	if opts.estado then
		pildoraEstado(card, opts.estado.texto, opts.estado.color)
	elseif opts.boton then
		local b = opts.boton
		local btn = UITheme.boton(card, b.texto, {
			ancho = 128, alto = 44, -- 44 = minimo tactil movil
			anchor = Vector2.new(1, 0), pos = UDim2.new(1, -12, 0, 14),
			variante = b.activo and "ok" or "apagado",
			acento = b.activo and color or nil,
			textoColor = b.activo and UITheme.color.texto or UITheme.color.peligro,
			icono = "monedas",
			iconoColor = b.activo and Color3.fromRGB(226, 178, 70) or UITheme.color.apagado,
			tam = 14,
			nombre = "Comprar",
		})
		if b.activo and b.accion then
			btn.MouseButton1Click:Connect(function() SoundManager.play("pickup"); b.accion() end) -- 22-jul: sfx al comprar perk (Bastian)
		else
			btn.Active = false -- sin handler: el toque no hace nada, pero la tarjeta SIGUE visible
		end
		if b.falta and b.falta > 0 then
			-- Cuanto te falta, debajo del precio. Es el dato que convierte "no puedo" en "me faltan 2 runs".
			-- Mismo ancho y misma x que el boton (128 / -12) para que su CAJA no invada la de la descripcion:
			-- se solapaban en la misma franja de altura y el texto largo se comia al corto.
			UITheme.etiqueta(card, "NEED " .. num(b.falta) .. " MORE", {
				nombre = "Falta", tam = 10, color = UITheme.color.peligro,
				anchor = Vector2.new(1, 0), pos = UDim2.new(1, -12, 0, 62),
				tamano = UDim2.new(0, 128, 0, 14), align = Enum.TextXAlignment.Right,
			})
		end
	end
	return card
end

-- Aviso a pantalla completa (sin datos aun). Va dentro de un Frame para que limpiarFilas() lo barra:
-- esa funcion solo destruye Frames, un TextLabel suelto se quedaria pegado bajo la primera tarjeta.
local function crearAviso(texto)
	local caja = Instance.new("Frame")
	caja.Size = UDim2.new(1, -4, 0, 60)
	caja.BackgroundTransparency = 1
	caja.Parent = scroll
	UITheme.etiqueta(caja, texto, {
		tam = 13, color = UITheme.color.textoTenue,
		tamano = UDim2.new(1, 0, 1, 0), align = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Center,
	})
end

-- MISMOS parametros y en el MISMO orden que antes, para que renderWeapons se quede intacta. El 4o (el color
-- del boton) ya no se usa: ahora el color lo decide el ESTADO (comprable / sin dinero / en propiedad), no
-- quien llama; se deja en la firma con guion bajo para no reordenar los argumentos de las llamadas.
local function crearFila(nombre, desc, btnTexto, _btnColor, btnActiva, accion)
	if accion == nil then
		-- Sin accion = estado terminal (OWNED / MAX): pildora, no boton.
		crearTarjeta({
			titulo = nombre, desc = desc, icono = "espada", color = ACENTO, maxima = true,
			estado = { texto = btnTexto, color = UITheme.color.ok },
		})
	else
		crearTarjeta({
			titulo = nombre, desc = desc, icono = "espada", color = ACENTO, apagada = not btnActiva,
			boton = { texto = btnTexto, activo = btnActiva, accion = accion },
		})
	end
end

local function renderUpgrades()
	limpiarFilas()
	local cash = leerStat("Cash")
	if #ultimoUpgrades == 0 then
		crearAviso("Loading perks...")
		lblProgreso.Text = ""
		return
	end
	local maxeadas = 0
	for _, up in ipairs(ultimoUpgrades) do
		local pinta = PINTA[up.id] or PINTA_POR_DEFECTO
		if up.cost == nil then
			maxeadas += 1
			crearTarjeta({
				titulo = up.nombre, desc = up.desc, icono = pinta.icono, color = pinta.color,
				nivel = up.level, maximo = up.maxLevel, maxima = true,
				estado = { texto = "MAX", color = UITheme.color.acento },
			})
		else
			local puede = cash >= up.cost
			crearTarjeta({
				titulo = up.nombre, desc = up.desc, icono = pinta.icono, color = pinta.color,
				nivel = up.level, maximo = up.maxLevel, apagada = not puede,
				boton = {
					texto = num(up.cost),
					activo = puede,
					falta = (not puede) and (up.cost - cash) or nil,
					-- La compra la valida el SERVIDOR: aqui solo se manda el id, sin tocar nada local.
					accion = function() buyUpgrade:FireServer(up.id) end,
				},
			})
		end
	end
	lblProgreso.Text = string.format("%d / %d maxed", maxeadas, #ultimoUpgrades)
end

local function elemEN(e)
	if e == "Fuego" then return "Fire" elseif e == "Hielo" then return "Ice" elseif e == "Veneno" then return "Poison" end
	return e
end

local function renderWeapons()
	limpiarFilas()
	local cash = leerStat("Cash")
	for _, nombre in ipairs(ORDEN_ARMAS) do
		local arma = WeaponData[nombre]
		if arma then
			local dmg = arma.Explosivo and (arma.DanoExplosion or 0) or arma.Dano
			local linea = string.format("DMG %d  -  %s", dmg, arma.Automatico and "Auto" or "Semi")
			if arma.Balas and arma.Balas > 1 then linea = linea .. "  -  x" .. arma.Balas end
			if arma.Perforante then linea = linea .. "  -  Pierce" end
			if arma.Explosivo then linea = linea .. "  -  AoE" end
			if arma.Elemento then linea = linea .. "  -  " .. elemEN(arma.Elemento) end
			if ownedWeapons[nombre] then
				crearFila(nombre, linea, "OWNED", Color3.fromRGB(70, 120, 80), false, nil)
			else
				local precio = arma.Precio or 0
				local puede = cash >= precio
				crearFila(nombre, linea, "BUY  $" .. precio,
					puede and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(90, 90, 100), puede,
					function() buyWeapon:FireServer(nombre) end)
			end
		end
	end
	lblProgreso.Text = ""
end

local function render()
	if tab == "weapons" then renderWeapons() else renderUpgrades() end
end
local function setTab(t)
	tab = t
	-- Hoy solo hay pestana de UPGRADES a la vista; la de armas sigue en codigo (setTab("weapons")).
	-- El activo se marca con el subrayado de acento, no pintando el fondo de un color plano.
	local activa = (t == "upgrades")
	subrayadoTab.BackgroundTransparency = activa and 0 or 0.75
	lblTab.TextColor3 = activa and UITheme.color.texto or UITheme.color.textoTenue
	render()
end
tabUpg.MouseButton1Click:Connect(function() setTab("upgrades") end)
UITheme.pulsacion(tabUpg)

shopSync.OnClientEvent:Connect(function(info)
	if info.upgrades then ultimoUpgrades = info.upgrades end
	if info.ownedWeapons then ownedWeapons = info.ownedWeapons end
	actualizarCurrency()
	if panelApi.estaAbierto() then render() end
end)

local function abrir()
	panelApi.abrir() -- pone MenuAbierto (con contador) y enciende el ScreenGui del panel
	actualizarCurrency()
	setTab(tab)
	shopSync:FireServer()
end
local function cerrar()
	panelApi.cerrar() -- quita MenuAbierto
end
openBtn.MouseButton1Click:Connect(function()
	if panelApi.estaAbierto() then cerrar() else abrir() end
end)
closeBtn.MouseButton1Click:Connect(cerrar)

task.spawn(function()
	local ls = player:WaitForChild("leaderstats")
	local cash = ls:WaitForChild("Cash")
	local gems = ls:WaitForChild("Gems")
	-- Al comprar, el servidor baja el Cash -> esto repinta: los precios que ya no llegan pasan a rojo solos.
	cash.Changed:Connect(function() actualizarCurrency(); if panelApi.estaAbierto() then render() end end)
	gems.Changed:Connect(actualizarCurrency)
	actualizarCurrency()
end)

-- El boton PERKS (permanentes) solo se ve en el LOBBY.
--
-- Y el PANEL tambien se CIERRA al empezar la run, no solo se esconde el boton. Este era el unico de los 6
-- paneles que no lo hacia, y no es un detalle: el overlay de UITheme lleva Active = true (absorbe TODOS los
-- toques). Si la run arrancaba con PERKS abierto -- y hay una ventana larga para que pase, porque al llegar
-- por teleport el servidor espera hasta 25s el perfil y 12s el roster con InMatch todavia en false -- el
-- jugador se quedaba sin poder moverse ni ver nada mientras los enemigos le pegaban, y con MenuAbierto
-- pegado en true toda la partida (o sea, de vuelta al lobby sin columna de iconos y sin PLAY).
local function gateBoton()
	local enPartida = player:GetAttribute("InMatch") == true
	openBtn.Visible = not enPartida
	if enPartida and panelApi and panelApi.estaAbierto() then panelApi.cerrar() end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gateBoton)
gateBoton()

shopSync:FireServer()
