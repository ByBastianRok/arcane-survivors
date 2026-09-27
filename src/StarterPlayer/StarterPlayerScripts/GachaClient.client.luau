-- GachaClient (LocalScript) · Sju - CLASS GACHA con el lenguaje visual de UITheme.
--
-- === POR QUE ESTA REESCRITO ===
-- Junto con la STORE es la pantalla que hace caja, y era la unica que seguia inventandose su paleta
-- (morados rgb(150,90,230), verdes planos, una ruleta de 760 px que en movil no cabia) y que escondia la
-- informacion importante detras de una pestana "RATES" que casi nadie abre.
--
-- Ahora el cuerpo son TRES COLUMNAS, que es como se lee un gacha de un vistazo:
--   1) THIS PULL   -> QUE te da la tirada: la ruleta + el resultado revelado + los tres botones.
--   2) YOUR CLASSES-> el POOL entero. Lo que YA tienes se ENSENA con su nivel y sus shards; lo bloqueado
--                     tambien se ve (con candado). Ver lo que te falta es justo lo que empuja a tirar.
--   3) DROP RATES  -> los PORCENTAJES REALES, escritos, siempre visibles y sin letra pequena. Ni pestana
--                     ni "ver detalles": esconder las odds es lo que quema a la gente (y a Roblox).
--
-- TRES NIVELES DE BOTON, con jerarquia de tamano y peso:
--   · ROLL (grande, centrado, con acento)  · PULL x3 (al lado, marcado BEST VALUE)  · GET GEMS (discreto).
--
-- === LO QUE NO SE TOCA (contrato con el servidor) ===
--   · Remotes: GachaSpin :FireServer() / :FireServer(3) + .OnClientEvent, GachaSync :FireServer() +
--     .OnClientEvent, SelectClass :FireServer(id). Mismos argumentos, mismos payloads.
--   · Atributos que LEE: PaidRandomRestricted, Pass_x3, Pass_autospin, InMatch (+ sus ChangedSignal).
--   · Atributos que ESCRIBE: MenuAbierto (via UITheme.panel, con contador) y AbrirStore (el mismo patron
--     cliente-a-cliente que usa el "+" del HUD para llamar a StoreClient).
--   · MarketplaceService:PromptGamePassPurchase con MonetizationData.Gamepasses.x3 / .autospin.
--   · leaderstats.Gems (solo lectura).
--
-- === CUMPLIMIENTO "paid random items" (LO MAS GRAVE QUE PODEMOS ROMPER) ===
-- PolicyServer pone el atributo PaidRandomRestricted (default TRUE hasta comprobar la policy de Roblox).
-- Si esta restringido: NO se puede ofrecer gacha ni venta de gemas a ese jugador -> aqui se OCULTA el boton
-- de comprar gemas y se BLOQUEAN roll / x3 / auto, ademas de cortar en el propio handler antes de tocar el
-- remote. El servidor (MetaStore) tambien lo corta por su cuenta; esto es la mitad de cliente, no la unica.
-- La comprobacion es "~= false" A PROPOSITO: nil (todavia no comprobado) cuenta como RESTRINGIDO.
--
-- Trampas conocidas que este fichero respeta:
--   · abrirBtn.Text tiene que ser EXACTAMENTE "CLASSES / GACHA" (HubClient adopta el boton buscandolo por
--     ese texto entre los TextButton del PlayerGui). Sus hijos se llaman HubIcono/HubLabel/HubAcento porque
--     el Hub los REUSA por nombre; con otro nombre crearia los suyos encima y saldrian dos iconos.
--   · un UIGradient en un TextButton tine TAMBIEN su texto -> el texto visible va en un TextLabel hijo.
--   · UITheme.boton conecta un resalte que MEMORIZA el color de fondo al crearse. Los botones que cambian
--     de color segun estado (roll/x3/auto/gems) se crean con sinPulsacion y usan pulsacionViva(), que lee
--     el color base ACTUAL en cada toque.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================================================================================================
-- BOTON DE ABRIR  ·  lo PRIMERO del script, antes de cualquier WaitForChild
-- ===================================================================================================
-- HubClient se rinde a los 15 s buscando este boton. Si lo creasemos despues de esperar a Remotes/UITheme,
-- un arranque lento lo dejaria fuera de la columna del lobby: el peor caso aceptable es un boton que aun no
-- responde, nunca un boton que no aparece.
local gui = Instance.new("ScreenGui")
gui.Name = "GachaMenu"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 40
gui.Parent = playerGui

local abrirBtn = Instance.new("TextButton")
abrirBtn.Name = "Open"
-- 60x68 = la MISMA celda de la columna del Hub, asi se ve igual lo adopte el Hub o no. A la DERECHA y a
-- media altura: el cuadrante inferior izquierdo es del joystick.
abrirBtn.Size = UDim2.fromOffset(60, 68)
abrirBtn.AnchorPoint = Vector2.new(1, 0.5)
abrirBtn.Position = UDim2.new(1, -12, 0.5, -80)
abrirBtn.BackgroundColor3 = Color3.fromRGB(38, 37, 47)
abrirBtn.AutoButtonColor = false
abrirBtn.Font = Enum.Font.GothamBold
abrirBtn.TextSize = 13
abrirBtn.TextTransparency = 1 -- invisible pero PRESENTE: el Hub busca por .Text exacto
abrirBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
abrirBtn.Text = "CLASSES / GACHA" -- NO TOCAR: es la clave con la que HubClient encuentra este boton
abrirBtn.Parent = gui

local ClassData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("ClassData"))
local MonetizationData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("MonetizationData"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gachaSpin = remotes:WaitForChild("GachaSpin")
local gachaSync = remotes:WaitForChild("GachaSync")
local selectClass = remotes:WaitForChild("SelectClass")

local ACENTO = UITheme.acentos.classes -- el morado de la entrada CLASSES del Hub: el gacha mantiene SU color
local GEMA_COL = Color3.fromRGB(160, 120, 245) -- el mismo tono de Gems que usa la tienda (chip + pictogramas)

-- Placa + los tres hijos con el nombre EXACTO que reusa HubClient (si no, dibuja los suyos encima).
UITheme.placa(abrirBtn, { radio = 10 })
UITheme.icono(abrirBtn, "orbe", ACENTO, { nombre = "HubIcono", lado = 30, pos = UDim2.new(0.5, 0, 0, 7) })
UITheme.etiqueta(abrirBtn, "Classes", {
	nombre = "HubLabel", tam = 11, color = UITheme.color.textoSuave,
	pos = UDim2.new(0, 0, 0, 40), tamano = UDim2.new(1, 0, 0, 13), align = Enum.TextXAlignment.Center,
})
UITheme.acentoBarra(abrirBtn, ACENTO, { nombre = "HubAcento" })
-- Aqui NO se llama a UITheme.pulsacion: al adoptar el boton, el Hub engancha SU resalte, y dos tweens sobre
-- el mismo BackgroundColor3 se pelean (parpadeo al soltar el dedo).

-- ===================================================================================================
-- DATOS -> % (la misma matematica de siempre; solo cambia como se pinta)
-- ===================================================================================================
local SPIN_COST = 100 -- Gems por tirada. Solo para MOSTRAR: quien cobra es el servidor (MetaStore).
local TIRADAS_MULTI = 3 -- lo que se le pide al remote en la multi-tirada (el server acepta hasta 10 con x3)
local clases = ClassData.infoLista()

local ordenRareza = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
local porRareza = {}
for _, c in ipairs(clases) do
	porRareza[c.rareza] = porRareza[c.rareza] or {}
	table.insert(porRareza[c.rareza], c)
end
local rarezasPresentes = {}
for _, r in ipairs(ordenRareza) do if porRareza[r] then table.insert(rarezasPresentes, r) end end
local totalRarPeso = 0
for _, r in ipairs(rarezasPresentes) do totalRarPeso += (ClassData.PesoRareza[r] or 1) end
local function chanceRareza(r) return (ClassData.PesoRareza[r] or 1) / totalRarPeso * 100 end -- % de esa RAREZA
local probClase = ClassData.probabilidades() -- % TOTAL por clase (rareza x peso dentro)
-- El borde/cinta de cada tarjeta va con el color de RAREZA de UITheme (codigo compartido con Forge y Store);
-- el color propio de la clase (c.color) se reserva para su pictograma y su nombre, que es su identidad.
local function colRareza(r) return UITheme.colorRareza(r) end

-- ===================================================================================================
-- PANEL
-- ===================================================================================================
-- ScreenGui APARTE: UITheme.panel apaga el .Enabled de su padre al cerrar, y el boton de abrir no puede
-- morir con el panel. 66 = el hueco del gacha en la convencion (Perks 61 / Quests 62 / Forge 63 / Store 64 /
-- Profile 65 / Gacha 66 / WorldSelect 67); no empata con ninguno.
local guiPanel = Instance.new("ScreenGui")
guiPanel.Name = "GachaPanel"; guiPanel.ResetOnSpawn = false; guiPanel.IgnoreGuiInset = true
guiPanel.DisplayOrder = 66; guiPanel.Enabled = false
guiPanel.Parent = playerGui

local ANCHO, ALTO = 980, 590 -- 22-jul: mas grande (Bastian: "que ocupe mas, no tan apretujado")
-- sinCerrar = true: la X la pinto yo porque tiene que pasar por el aviso de AUTOSPIN antes de cerrar, y la X
-- que trae UITheme.panel llama a api.cerrar() directamente (no hay forma de meterse en medio).
local overlay, panel, barra, api = UITheme.panel(guiPanel, ANCHO, ALTO, "CLASS GACHA", {
	acento = ACENTO,
	clave = "gacha", -- clave del contador de MenuAbierto
	velo = 0.5,
	sinCerrar = true,
})
panel.Active = true -- absorbe el toque sobre la placa: el InputBegan del overlay solo salta FUERA del panel

-- ===================================================================================================
-- HELPERS DE ESTADO EN BOTONES
-- ===================================================================================================
-- El resalte de UITheme.boton memoriza el color de fondo del MOMENTO EN QUE SE CREA. Roll/x3/auto/gems
-- cambian de color segun el estado (gratis, sin gemas, rolling, bloqueado por policy), asi que se crean con
-- sinPulsacion y usan esto, que relee el color base actual en cada toque.
local colorBase = {}
local function pintar(btn, color)
	colorBase[btn] = color
	btn.BackgroundColor3 = color
end
local function pulsacionViva(btn)
	local infoRapida = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	UITheme.pulsacion(btn, function(on)
		local base = colorBase[btn] or btn.BackgroundColor3
		TweenService:Create(btn, infoRapida, {
			BackgroundColor3 = on and base:Lerp(Color3.new(1, 1, 1), 0.13) or base,
		}):Play()
	end)
end

-- Cabecera de columna: tick de acento + rotulo a la izquierda, dato a la derecha. Sin caja: una barra de
-- titulo por columna competiria con las tarjetas.
local function cabecera(padre, texto, color, dato)
	local h = Instance.new("Frame")
	h.Name = "Cabecera"
	h.Size = UDim2.new(1, 0, 0, 20)
	h.BackgroundTransparency = 1
	h.Parent = padre

	local tick = Instance.new("Frame")
	tick.Size = UDim2.fromOffset(4, 14)
	tick.Position = UDim2.new(0, 0, 0, 3)
	tick.BackgroundColor3 = color
	tick.BorderSizePixel = 0
	tick.Parent = h
	Instance.new("UICorner", tick).CornerRadius = UDim.new(1, 0)

	UITheme.etiqueta(h, texto, {
		fuente = UITheme.fuente.titulo, tam = 13, color = UITheme.color.texto,
		pos = UDim2.new(0, 12, 0, 1), tamano = UDim2.new(0.62, 0, 0, 18),
	})
	local lblDato = nil
	if dato then
		lblDato = UITheme.etiqueta(h, dato, {
			nombre = "Dato", fuente = UITheme.fuente.etiqueta, tam = 12, color = UITheme.color.textoTenue,
			pos = UDim2.new(0.62, 0, 0, 2), tamano = UDim2.new(0.38, 0, 0, 16),
			align = Enum.TextXAlignment.Right,
		})
	end
	return h, lblDato
end

-- ===================================================================================================
-- CABECERA: saldo de Gems
-- ===================================================================================================
-- Va al lado del titulo por el mismo motivo que en la tienda: quien abre el gacha quiere saber cuantas
-- tiradas le quedan, y "180 Gems" junto a un ROLL de 100 es el mejor argumento que hay. Solo LEE leaderstats.
local chipGems = Instance.new("Frame")
chipGems.Name = "ChipGems"
chipGems.AnchorPoint = Vector2.new(1, 0)
chipGems.Position = UDim2.new(1, -66, 0, 13) -- -66 deja libre la X (44 + margen)
chipGems.Size = UDim2.fromOffset(116, 26)
chipGems.Parent = barra
UITheme.placa(chipGems, { fondo = Color3.fromRGB(30, 29, 38), radio = UITheme.radio.pildora, bordeTransp = 0.5 })
UITheme.icono(chipGems, "gema", GEMA_COL, { lado = 16, pos = UDim2.new(0, 9, 0.5, 0), anchor = Vector2.new(0, 0.5) })
local lblGems = UITheme.etiqueta(chipGems, "0", {
	fuente = UITheme.fuente.dato, tam = 13, color = UITheme.color.texto,
	pos = UDim2.new(0, 30, 0, 0), tamano = UDim2.new(1, -38, 1, 0), alignY = Enum.TextYAlignment.Center,
})

local function miles(n) -- 12500 -> 12,500 (un numero largo sin separador no se lee de un vistazo)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- ===================================================================================================
-- CUERPO: TRES COLUMNAS
-- ===================================================================================================
-- Anchos DISTINTOS a proposito (300 / 252 / 180): tres columnas iguales es el look de plantilla, y ademas
-- no tienen la misma importancia -- donde se decide es en la primera.
local CUERPO_Y, CUERPO_H = 58, 520 -- alto 430->520 (panel mas grande)
local COL1_X, COL1_W = 16, 380 -- anchos subidos ~1.27x: menos apretujado, misma proporcion 300/252/180
local COL2_X, COL2_W = 406, 330
local COL3_X, COL3_W = 746, 222

local function columna(x, w)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(w, CUERPO_H)
	f.Position = UDim2.fromOffset(x, CUERPO_Y)
	f.BackgroundTransparency = 1
	f.Parent = panel
	return f
end
local col1 = columna(COL1_X, COL1_W)
local col2 = columna(COL2_X, COL2_W)
local col3 = columna(COL3_X, COL3_W)
col1.Name = "Tirada"; col2.Name = "Coleccion"; col3.Name = "Rates"

-- Separadores verticales finos entre columnas. NO llegan arriba ni abajo (simetria perfecta = plantilla).
for _, x in ipairs({ COL2_X - 5, COL3_X - 5 }) do
	local l = Instance.new("Frame")
	l.Size = UDim2.fromOffset(1, CUERPO_H - 40)
	l.Position = UDim2.fromOffset(x, CUERPO_Y + 26)
	l.BackgroundColor3 = UITheme.color.placaAlta
	l.BackgroundTransparency = 0.55
	l.BorderSizePixel = 0
	l.Parent = panel
end

-- ===================================================================================================
-- COLUMNA 1  ·  THIS PULL
-- ===================================================================================================
cabecera(col1, "THIS PULL", ACENTO, "1 pull = 1 class")

-- ---- RULETA ----
-- Es el juice del gacha: la carta pasa, hace tic en el marcador y frena sobre lo que ya decidio el SERVIDOR
-- (aqui no se sortea nada, solo se anima el id que llega por el remote).
-- NTILES no es un numero al azar: pararRoll frena 4 PERIODOS por delante, asi que la tira tiene que medir al
-- menos 5*PERIODO + REEL_W o el frenazo acabaria en una zona SIN cartas (una ventana vacia).
-- Va CALCULADO y no clavado a mano: con las 5 clases de hoy hacen falta 28 y un 30 fijo colaba, pero a la
-- sexta clase harian falta 33 y la ruleta volveria a parar en el vacio -- justo el bug que esto evita, y que
-- no daria ningun error, solo una ventana en blanco al tirar.
local REEL_W, REEL_H, TILE = COL1_W, 108, 100
local PERIODO = #clases * TILE
local NTILES = math.max(30, 5 * #clases + math.ceil(REEL_W / TILE))

local reelWin = Instance.new("Frame")
reelWin.Name = "Ruleta"
reelWin.Size = UDim2.fromOffset(REEL_W, REEL_H)
reelWin.Position = UDim2.fromOffset(0, 24)
reelWin.ClipsDescendants = true
reelWin.Parent = col1
UITheme.placa(reelWin, {
	fondo = Color3.fromRGB(24, 23, 31), alto = Color3.fromRGB(32, 30, 40), bajo = Color3.fromRGB(19, 18, 25),
	radio = UITheme.radio.placa, bordeTransp = 0.2,
})

local strip = Instance.new("Frame")
strip.Name = "Tira"
strip.Size = UDim2.fromOffset(NTILES * TILE, REEL_H)
strip.Position = UDim2.fromOffset(0, 0)
strip.BackgroundTransparency = 1
strip.Parent = reelWin
for i = 0, NTILES - 1 do
	local c = clases[(i % #clases) + 1]
	local tile = Instance.new("Frame")
	tile.Size = UDim2.fromOffset(TILE - 12, REEL_H - 20)
	tile.Position = UDim2.fromOffset(i * TILE + 6, 10)
	tile.Parent = strip
	UITheme.placa(tile, {
		fondo = Color3.fromRGB(34, 33, 43), alto = Color3.fromRGB(46, 44, 56), bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.tarjeta, borde = colRareza(c.rareza), grosor = 1, bordeTransp = 0.45,
	})
	UITheme.icono(tile, UITheme.iconoClase[c.id] or "orbe", c.color, { lado = 26, pos = UDim2.new(0.5, 0, 0, 10), anchor = Vector2.new(0.5, 0) })
	UITheme.etiqueta(tile, c.nombre, {
		fuente = UITheme.fuente.dato, tam = 11, color = c.color,
		pos = UDim2.new(0, 3, 0, 42), tamano = UDim2.new(1, -6, 0, 14), align = Enum.TextXAlignment.Center,
	}).TextTruncate = Enum.TextTruncate.AtEnd
	UITheme.etiqueta(tile, string.upper(c.rareza), {
		fuente = UITheme.fuente.etiqueta, tam = 9, color = colRareza(c.rareza),
		pos = UDim2.new(0, 3, 0, 57), tamano = UDim2.new(1, -6, 0, 12), align = Enum.TextXAlignment.Center,
	})
end

-- Marcador central: el UNICO adorno que parpadea, y solo cuando pasa una carta.
local marker = Instance.new("Frame")
marker.Name = "Marcador"
marker.Size = UDim2.fromOffset(TILE - 8, REEL_H - 12)
marker.Position = UDim2.new(0.5, 0, 0.5, 0)
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.BackgroundTransparency = 1
marker.Parent = reelWin
Instance.new("UICorner", marker).CornerRadius = UDim.new(0, UITheme.radio.tarjeta)
local mStroke = Instance.new("UIStroke")
mStroke.Thickness = 2
mStroke.Color = UITheme.color.acento
mStroke.Parent = marker

-- ---- REVELADO ----
local flash = Instance.new("Frame") -- destello celebratorio DETRAS del texto del resultado
flash.Name = "Flash"
flash.Size = UDim2.fromOffset(COL1_W, 90)
flash.Position = UDim2.fromOffset(0, 134)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 0
flash.Parent = col1
Instance.new("UICorner", flash).CornerRadius = UDim.new(0, UITheme.radio.placa)

local revealNombre = UITheme.etiqueta(col1, "Press ROLL to pull a class", {
	nombre = "Resultado", fuente = UITheme.fuente.titulo, tam = 22, color = UITheme.color.texto,
	pos = UDim2.new(0, 0, 0, 136), tamano = UDim2.new(1, 0, 0, 30), align = Enum.TextXAlignment.Center,
})
local revealScale = Instance.new("UIScale") -- el POP del nombre al aterrizar
revealScale.Parent = revealNombre

local revealEstado = UITheme.etiqueta(col1, "New class, or shards to level one up", {
	nombre = "Estado", fuente = UITheme.fuente.dato, tam = 13, color = UITheme.color.textoTenue,
	pos = UDim2.new(0, 0, 0, 166), tamano = UDim2.new(1, 0, 0, 18), align = Enum.TextXAlignment.Center,
})
local revealBuff = UITheme.etiqueta(col1, "", {
	nombre = "Buff", fuente = UITheme.fuente.etiqueta, tam = 12, color = UITheme.color.textoSuave,
	pos = UDim2.new(0, 14, 0, 188), tamano = UDim2.new(1, -28, 0, 30), align = Enum.TextXAlignment.Center,
	alignY = Enum.TextYAlignment.Top, wrap = true,
})
-- Pity: solo aparece si de verdad hay clases bloqueadas. Es una promesa que el servidor SI cumple, asi que
-- se puede escribir sin mentir.
local pityLbl = UITheme.etiqueta(col1, "", {
	nombre = "Pity", fuente = UITheme.fuente.dato, tam = 12, color = UITheme.color.acento,
	pos = UDim2.new(0, 0, 0, 220), tamano = UDim2.new(1, 0, 0, 15), align = Enum.TextXAlignment.Center,
})
UITheme.separador(col1, 238, { izq = 30, margen = 60 })

-- ---- LOS TRES BOTONES ----
-- Nivel 1: ROLL. Grande, ancho completo, con barra de acento. Es lo que queremos que se toque.
local rollBtn, rollLbl = UITheme.boton(col1, "ROLL", {
	tamano = UDim2.new(1, 0, 0, 58), pos = UDim2.new(0, 0, 0, 244),
	ancho = COL1_W, tam = 20, nombre = "Roll",
	color = Color3.fromRGB(48, 38, 70), altoColor = Color3.fromRGB(70, 55, 100), bajoColor = Color3.fromRGB(33, 26, 48),
	textoColor = UITheme.color.texto,
	acento = ACENTO,
	sinPulsacion = true, -- cambia de color por estado: el resalte se conecta abajo con pulsacionViva
})
rollLbl.Position = UDim2.new(0, 0, 0, 8)
rollLbl.Size = UDim2.new(1, 0, 0, 24)
local rollSub = UITheme.etiqueta(rollBtn, "", {
	nombre = "Coste", fuente = UITheme.fuente.etiqueta, tam = 12, color = UITheme.color.textoSuave,
	pos = UDim2.new(0, 0, 0, 32), tamano = UDim2.new(1, 0, 0, 15), align = Enum.TextXAlignment.Center,
})
rollSub.ZIndex = 2
pintar(rollBtn, Color3.fromRGB(48, 38, 70))
pulsacionViva(rollBtn)

-- Nivel 2: la multi-tirada. Mas chica que ROLL pero con la cinta de BEST VALUE: es el mejor precio por
-- tirada (y ademas es lo que empuja el gamepass x3).
local x3Btn, x3Lbl = UITheme.boton(col1, "PULL x3", {
	tamano = UDim2.new(0, 194, 0, 48), pos = UDim2.new(0, 0, 0, 308),
	ancho = 194, tam = 16, nombre = "Multi",
	color = Color3.fromRGB(44, 38, 30), altoColor = Color3.fromRGB(64, 54, 40), bajoColor = Color3.fromRGB(30, 26, 21),
	textoColor = UITheme.color.texto,
	acento = UITheme.rareza.legendario,
	sinPulsacion = true,
})
x3Lbl.Position = UDim2.new(0, 0, 0, 5)
x3Lbl.Size = UDim2.new(1, 0, 0, 22)
local x3Sub = UITheme.etiqueta(x3Btn, "", {
	nombre = "Coste", fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoSuave,
	pos = UDim2.new(0, 0, 0, 26), tamano = UDim2.new(1, 0, 0, 14), align = Enum.TextXAlignment.Center,
})
x3Sub.ZIndex = 2
pintar(x3Btn, Color3.fromRGB(44, 38, 30))
pulsacionViva(x3Btn)

-- Cinta que SOBRESALE por arriba del boton: dentro y alineada seria un boton mas.
local cintaValor = Instance.new("Frame")
cintaValor.Name = "Banner"
cintaValor.AnchorPoint = Vector2.new(1, 0)
-- -6 y no -9: con -9 la cinta arrancaba 3 px por encima del borde inferior del boton ROLL, que acaba justo
-- ahi arriba, y se pisaban en la esquina.
cintaValor.Position = UDim2.new(1, -8, 0, -6)
cintaValor.Size = UDim2.fromOffset(86, 18)
cintaValor.ZIndex = 4
cintaValor.Parent = x3Btn
UITheme.placa(cintaValor, {
	fondo = UITheme.rareza.legendario,
	alto = UITheme.tono(UITheme.rareza.legendario, 0.35),
	bajo = UITheme.tono(UITheme.rareza.legendario, -0.2),
	radio = UITheme.radio.pildora, grosor = 1, bordeTransp = 0.2,
})
UITheme.etiqueta(cintaValor, "BEST VALUE", {
	fuente = UITheme.fuente.dato, tam = 10, color = Color3.fromRGB(38, 27, 8),
	tamano = UDim2.new(1, 0, 1, 0), align = Enum.TextXAlignment.Center, alignY = Enum.TextYAlignment.Center,
}).ZIndex = 5 -- el texto va en label hijo: el UIGradient de la placa tine el .Text del padre

-- AUTO: gamepass de conveniencia. Va pegado al x3 y es el mas pequeno de la fila; no compite con ROLL.
local autoBtn, autoLbl = UITheme.boton(col1, "AUTO", {
	tamano = UDim2.new(0, 98, 0, 48), pos = UDim2.new(0, 202, 0, 308),
	ancho = 98, tam = 14, nombre = "Auto",
	color = Color3.fromRGB(34, 33, 42), altoColor = Color3.fromRGB(46, 45, 56), bajoColor = Color3.fromRGB(26, 25, 32),
	textoColor = UITheme.color.textoSuave,
	sinPulsacion = true,
})
autoLbl.Position = UDim2.new(0, 0, 0, 6)
autoLbl.Size = UDim2.new(1, 0, 0, 20)
local autoSub = UITheme.etiqueta(autoBtn, "OFF", {
	nombre = "Estado", fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoTenue,
	pos = UDim2.new(0, 0, 0, 26), tamano = UDim2.new(1, 0, 0, 14), align = Enum.TextXAlignment.Center,
})
autoSub.ZIndex = 2
pintar(autoBtn, Color3.fromRGB(34, 33, 42))
pulsacionViva(autoBtn)

-- Nivel 3: comprar gemas. DISCRETO a proposito (sin acento, texto tenue) pero con sus 44 px de alto, que es
-- el minimo tactil de movil. No vende aqui: abre la TIENDA, que es donde estan los packs de verdad.
local gemsBtn, gemsLbl = UITheme.boton(col1, "GET GEMS", {
	tamano = UDim2.new(1, 0, 0, UITheme.TACTIL_MIN), pos = UDim2.new(0, 0, 0, 362),
	ancho = COL1_W, tam = 13, nombre = "Gemas",
	icono = "gema", iconoColor = GEMA_COL,
	color = Color3.fromRGB(31, 30, 39), altoColor = Color3.fromRGB(42, 41, 52), bajoColor = Color3.fromRGB(25, 24, 31),
	textoColor = UITheme.color.textoSuave,
	sinPulsacion = true,
})
pintar(gemsBtn, Color3.fromRGB(31, 30, 39))
pulsacionViva(gemsBtn)

-- Toast del diario (la tirada gratis de cada dia). Ocupa su propio renglon para no empujar nada al aparecer.
local toastLbl = UITheme.etiqueta(col1, "", {
	nombre = "Toast", fuente = UITheme.fuente.dato, tam = 12, color = UITheme.color.ok,
	pos = UDim2.new(0, 0, 0, 410), tamano = UDim2.new(1, 0, 0, 16), align = Enum.TextXAlignment.Center,
})
toastLbl.TextTransparency = 1

-- ===================================================================================================
-- COLUMNA 2  ·  YOUR CLASSES  (lo que YA tienes se ENSENA, con su nivel)
-- ===================================================================================================
local _, lblPoseidas = cabecera(col2, "YOUR CLASSES", UITheme.rareza.raro, "0 / " .. #clases)
local listaCol2 = UITheme.scroll(col2, {
	nombre = "Clases",
	tamano = UDim2.new(1, 0, 1, -26),
	pos = UDim2.new(0, 0, 0, 26),
	padding = 8,
	relleno = 8,
})

local tarjetas = {}
for i, c in ipairs(clases) do
	local col = colRareza(c.rareza)

	local fila = Instance.new("Frame")
	fila.Name = "Clase_" .. c.id
	fila.Size = UDim2.new(1, -6, 0, 76)
	fila.LayoutOrder = i
	fila.Parent = listaCol2
	UITheme.placa(fila, {
		fondo = UITheme.color.fondoPlaca, alto = Color3.fromRGB(50, 48, 60), bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.tarjeta, sinBorde = true,
	})
	-- El stroke SI lleva color: es el codigo de RAREZA. Fino y algo transparente, no un neon.
	local stroke = Instance.new("UIStroke")
	stroke.Color = col; stroke.Thickness = 2; stroke.Transparency = 0.25
	stroke.Parent = fila
	-- Cinta corta pegada al borde de arriba, sin llegar a las esquinas.
	local cinta = Instance.new("Frame")
	cinta.Size = UDim2.new(0.32, 0, 0, 3)
	cinta.Position = UDim2.new(0, 10, 0, 0)
	cinta.BackgroundColor3 = col
	cinta.BorderSizePixel = 0
	cinta.Parent = fila
	Instance.new("UICorner", cinta).CornerRadius = UDim.new(1, 0)

	local dibujo = UITheme.icono(fila, UITheme.iconoClase[c.id] or "orbe", c.color, {
		lado = 30, pos = UDim2.new(0, 10, 0, 12), anchor = Vector2.new(0, 0),
	})

	local nombre = UITheme.etiqueta(fila, c.nombre, {
		fuente = UITheme.fuente.dato, tam = 14, color = c.color,
		pos = UDim2.new(0, 48, 0, 9), tamano = UDim2.new(1, -140, 0, 18),
	})
	nombre.TextTruncate = Enum.TextTruncate.AtEnd
	local sub = UITheme.etiqueta(fila, string.upper(c.rareza), {
		fuente = UITheme.fuente.etiqueta, tam = 12, color = UITheme.color.textoTenue,
		pos = UDim2.new(0, 48, 0, 29), tamano = UDim2.new(1, -140, 0, 16),
	})
	sub.TextTruncate = Enum.TextTruncate.AtEnd

	-- Barra de shards: cuanto te falta para el siguiente nivel. Es EL bucle de los duplicados.
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -104, 0, 6)
	barBg.Position = UDim2.fromOffset(10, 58)
	barBg.BackgroundColor3 = Color3.fromRGB(22, 21, 28)
	barBg.BorderSizePixel = 0
	barBg.Parent = fila
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = col
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

	local equipBtn, equipLbl = UITheme.boton(fila, "EQUIP", {
		tamano = UDim2.new(0, 78, 0, UITheme.TACTIL_MIN), pos = UDim2.new(1, -88, 0, 16),
		ancho = 78, tam = 12, nombre = "Equipar",
		color = Color3.fromRGB(36, 34, 46), altoColor = Color3.fromRGB(50, 47, 62), bajoColor = Color3.fromRGB(27, 26, 34),
		textoColor = UITheme.color.texto,
		sinPulsacion = true, -- pasa a verde cuando esta equipada: el resalte tiene que releer el color
	})
	pintar(equipBtn, Color3.fromRGB(36, 34, 46))
	pulsacionViva(equipBtn)
	-- Nace OCULTO. Solo actualizarColeccion() decide quien lo ensena, y hasta que no llega el primer GachaSync
	-- no sabemos que clases tienes: sin esto, durante ese hueco TODAS las clases bloqueadas ofrecian su EQUIP.
	equipBtn.Visible = false

	tarjetas[c.id] = {
		fila = fila, stroke = stroke, cinta = cinta, dibujo = dibujo, nombre = nombre, sub = sub,
		barFill = barFill, equipBtn = equipBtn, equipLbl = equipLbl,
		color = c.color, rarezaCol = col, rareza = c.rareza, bloqueadaPintada = nil,
	}
end

-- ===================================================================================================
-- COLUMNA 3  ·  DROP RATES  (los % REALES, escritos y siempre visibles)
-- ===================================================================================================
cabecera(col3, "DROP RATES", UITheme.color.acento, "per pull")
local listaCol3 = UITheme.scroll(col3, {
	nombre = "Rates",
	tamano = UDim2.new(1, 0, 1, -26),
	pos = UDim2.new(0, 0, 0, 26),
	padding = 4,
	relleno = 8,
})
local ordenRates = 0
for _, r in ipairs(rarezasPresentes) do
	local col = colRareza(r)
	ordenRates += 1

	-- Fila de RAREZA: el % gordo, a la derecha, en el color de la rareza.
	local h = Instance.new("Frame")
	h.Size = UDim2.new(1, -6, 0, 26)
	h.LayoutOrder = ordenRates
	h.BackgroundTransparency = 1
	h.Parent = listaCol3

	local tick = Instance.new("Frame")
	tick.Size = UDim2.fromOffset(3, 14)
	tick.Position = UDim2.new(0, 0, 0, 7)
	tick.BackgroundColor3 = col
	tick.BorderSizePixel = 0
	tick.Parent = h
	Instance.new("UICorner", tick).CornerRadius = UDim.new(1, 0)

	UITheme.etiqueta(h, string.upper(r), {
		fuente = UITheme.fuente.dato, tam = 13, color = col,
		pos = UDim2.new(0, 10, 0, 4), tamano = UDim2.new(0.55, 0, 0, 18),
	})
	UITheme.etiqueta(h, string.format("%.1f%%", chanceRareza(r)), {
		fuente = UITheme.fuente.titulo, tam = 14, color = col,
		pos = UDim2.new(0.55, 0, 0, 4), tamano = UDim2.new(0.45, 0, 0, 18),
		align = Enum.TextXAlignment.Right,
	})

	-- Y debajo, CADA clase de esa rareza con su probabilidad total. Nada de "ver detalles".
	for _, c in ipairs(porRareza[r]) do
		ordenRates += 1
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, -6, 0, 18)
		f.LayoutOrder = ordenRates
		f.BackgroundTransparency = 1
		f.Parent = listaCol3
		UITheme.etiqueta(f, c.nombre, {
			fuente = UITheme.fuente.etiqueta, tam = 12, color = UITheme.color.textoSuave,
			pos = UDim2.new(0, 12, 0, 0), tamano = UDim2.new(0.6, -12, 1, 0),
		}).TextTruncate = Enum.TextTruncate.AtEnd
		UITheme.etiqueta(f, string.format("%.2f%%", (probClase[c.id] or 0) * 100), {
			fuente = UITheme.fuente.dato, tam = 12, color = UITheme.color.textoTenue,
			pos = UDim2.new(0.6, 0, 0, 0), tamano = UDim2.new(0.4, 0, 1, 0), align = Enum.TextXAlignment.Right,
		})
	end
end
-- Pie honesto: explica el duplicado y el pity SIN letra pequena (tam 11 es el minimo que usamos).
ordenRates += 1
local pieRates = UITheme.etiqueta(listaCol3, "Duplicates give shards. Shards level a class up. Odds are the same on every pull.", {
	fuente = UITheme.fuente.etiqueta, tam = 11, color = UITheme.color.textoTenue,
	tamano = UDim2.new(1, -6, 0, 46), wrap = true, alignY = Enum.TextYAlignment.Top,
})
pieRates.LayoutOrder = ordenRates

-- ===================================================================================================
-- ESTADO
-- ===================================================================================================
local tiradasGratis = 0
local ultimaCol = { nivel = {}, shards = {}, claseActual = nil }
local gemsStat
local stripX = 0
local rolling = false
local reelConn
local spinning = false
local autoOn = false -- autospin activo
-- n = numero de tiradas (1 por defecto). La x3 cuesta SPIN_COST*3; la tirada gratis solo cubre 1.
local function puedeSpin(n) n = n or 1; return (tiradasGratis > 0 and n == 1) or (gemsStat and gemsStat.Value >= SPIN_COST * n) end
-- CUMPLIMIENTO: restringido, o TODAVIA sin comprobar (nil) = restringido. El "~= false" es intencionado.
local function policyRestringido() return player:GetAttribute("PaidRandomRestricted") ~= false end

-- ===================================================================================================
-- REPINTADO DE LOS BOTONES  (estado + policy en un solo sitio)
-- ===================================================================================================
local function refrescarBotones()
	local restringido = policyRestringido()
	local hasX3 = player:GetAttribute("Pass_x3") == true
	local hasAuto = player:GetAttribute("Pass_autospin") == true

	-- CUMPLIMIENTO paid random items: al restringido se le OCULTA la compra de gemas y se le BLOQUEA el gacha.
	gemsBtn.Visible = not restringido
	cintaValor.Visible = not restringido -- un "BEST VALUE" sobre un boton bloqueado es publicidad de algo que no puede comprar
	if restringido then
		for _, b in ipairs({ rollBtn, x3Btn, autoBtn }) do
			b.Active = false
			b.AutoButtonColor = false
			pintar(b, UITheme.color.apagado)
		end
		rollLbl.Text = "UNAVAILABLE"; rollLbl.TextColor3 = UITheme.color.textoTenue
		rollSub.Text = "Paid random items are restricted on this account"
		x3Lbl.Text = "UNAVAILABLE"; x3Sub.Text = ""
		autoLbl.Text = "AUTO"; autoSub.Text = "-"
		return
	end

	for _, b in ipairs({ rollBtn, x3Btn, autoBtn }) do b.Active = true end

	-- ROLL
	if spinning then
		rollLbl.Text = "ROLLING..."; rollLbl.TextColor3 = UITheme.color.textoSuave
		rollSub.Text = ""
		pintar(rollBtn, Color3.fromRGB(40, 38, 52))
	elseif tiradasGratis > 0 then
		rollLbl.Text = "FREE ROLL"; rollLbl.TextColor3 = UITheme.color.texto
		rollSub.Text = tiradasGratis .. " free " .. (tiradasGratis == 1 and "pull" or "pulls") .. " left"
		pintar(rollBtn, Color3.fromRGB(32, 52, 38)) -- verde de placa: gratis merece otro color, no otro tamano
	elseif puedeSpin() then
		rollLbl.Text = "ROLL"; rollLbl.TextColor3 = UITheme.color.texto
		rollSub.Text = SPIN_COST .. " Gems"
		pintar(rollBtn, Color3.fromRGB(48, 38, 70))
	else
		rollLbl.Text = "ROLL"; rollLbl.TextColor3 = UITheme.color.textoTenue
		rollSub.Text = "Not enough Gems (" .. SPIN_COST .. ")"
		pintar(rollBtn, Color3.fromRGB(38, 36, 46))
	end

	-- GET GEMS sube de brillo SOLO cuando no te llega para tirar. El resto del tiempo se queda apagado: un
	-- tercer boton gritando al lado del ROLL le robaria el toque al boton que de verdad queremos.
	local sinSaldo = not puedeSpin()
	gemsLbl.Text = sinSaldo and "GET GEMS  -  you're short" or "GET GEMS"
	gemsLbl.TextColor3 = sinSaldo and UITheme.color.texto or UITheme.color.textoSuave
	pintar(gemsBtn, sinSaldo and Color3.fromRGB(38, 34, 52) or Color3.fromRGB(31, 30, 39))

	-- PULL x3 (o la invitacion al gamepass si no lo tiene)
	if not hasX3 then
		x3Lbl.Text = "UNLOCK x3"; x3Lbl.TextColor3 = UITheme.color.texto
		x3Sub.Text = "Gamepass - 3 pulls at once"
		pintar(x3Btn, Color3.fromRGB(44, 38, 30))
	else
		x3Lbl.Text = "PULL x" .. TIRADAS_MULTI; x3Lbl.TextColor3 = UITheme.color.texto
		x3Sub.Text = (SPIN_COST * TIRADAS_MULTI) .. " Gems - one tap"
		pintar(x3Btn, puedeSpin(TIRADAS_MULTI) and Color3.fromRGB(52, 44, 32) or Color3.fromRGB(38, 36, 44))
	end

	-- AUTO
	autoLbl.Text = "AUTO"
	if not hasAuto then
		autoLbl.TextColor3 = UITheme.color.textoSuave
		autoSub.Text = "Gamepass"
		pintar(autoBtn, Color3.fromRGB(34, 33, 42))
	elseif autoOn then
		autoLbl.TextColor3 = UITheme.color.texto
		autoSub.Text = "ON"
		pintar(autoBtn, Color3.fromRGB(32, 52, 38))
	else
		autoLbl.TextColor3 = UITheme.color.textoSuave
		autoSub.Text = "OFF"
		pintar(autoBtn, Color3.fromRGB(34, 33, 42))
	end
end

local function actualizarGems()
	if gemsStat then lblGems.Text = miles(gemsStat.Value) end
	refrescarBotones() -- el saldo decide si ROLL se ve "comprable" o no
end

task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 20)
	gemsStat = ls and ls:WaitForChild("Gems", 10)
	if gemsStat then
		gemsStat:GetPropertyChangedSignal("Value"):Connect(actualizarGems)
		actualizarGems()
	end
end)

-- ===================================================================================================
-- COLECCION  (payload de GachaSync, sin cambiar ni un campo)
-- ===================================================================================================
local function actualizarColeccion(sync)
	ultimaCol = sync
	if sync.tiradasGratis ~= nil then tiradasGratis = sync.tiradasGratis; refrescarBotones() end

	local poseidas = 0
	local hayBloq = false
	for _, c in ipairs(clases) do
		if ((sync.nivel or {})[c.id] or 0) >= 1 then poseidas += 1 else hayBloq = true end
	end
	lblPoseidas.Text = poseidas .. " / " .. #clases

	-- El pity solo se anuncia si queda algo que desbloquear (si no, es una promesa vacia).
	pityLbl.Text = (hayBloq and sync.pity)
		and ("Guaranteed new class in " .. math.max(0, sync.pity - (sync.spinsSinNueva or 0)) .. " pulls")
		or ""

	if sync.dailyNuevo then
		toastLbl.Text = "Daily free pull claimed  (+1)"
		toastLbl.TextTransparency = 0
		TweenService:Create(toastLbl, TweenInfo.new(2.8), { TextTransparency = 1 }):Play()
	end

	for id, t in pairs(tarjetas) do
		local nivel = (sync.nivel or {})[id] or 0
		local shards = (sync.shards or {})[id] or 0
		local owned = nivel >= 1
		local equipped = (sync.claseActual == id)

		-- El pictograma solo se redibuja cuando CAMBIA de estado: pictograma() borra y reconstruye la caja,
		-- y hacerlo en cada sync seria tirar y crear frames por gusto.
		if t.bloqueadaPintada ~= owned then
			t.bloqueadaPintada = owned
			UITheme.pictograma(t.dibujo, owned and (UITheme.iconoClase[id] or "orbe") or "candado", owned and t.color or UITheme.color.apagado)
		end

		t.fila.BackgroundTransparency = owned and 0 or 0.35
		t.stroke.Transparency = owned and 0.25 or 0.6
		t.cinta.BackgroundTransparency = owned and 0 or 0.55
		t.nombre.TextColor3 = owned and t.color or UITheme.color.textoTenue

		if owned then
			local costo = ClassData.ShardsParaSubir[nivel]
			if costo and nivel < ClassData.NivelMax then
				t.sub.Text = "Lv " .. nivel .. "   ·   " .. shards .. "/" .. costo .. " shards"
				t.barFill.Size = UDim2.fromScale(math.clamp(shards / costo, 0, 1), 1)
			else
				t.sub.Text = "Lv " .. nivel .. "   ·   MAX"
				t.barFill.Size = UDim2.fromScale(1, 1)
			end
			t.sub.TextColor3 = UITheme.color.textoSuave
			t.equipBtn.Visible = true
			t.equipLbl.Text = equipped and "EQUIPPED" or "EQUIP"
			t.equipLbl.TextColor3 = equipped and UITheme.color.ok or UITheme.color.texto
			pintar(t.equipBtn, equipped and Color3.fromRGB(30, 46, 34) or Color3.fromRGB(36, 34, 46))
		else
			t.sub.Text = string.upper(t.rareza) .. "   ·   LOCKED"
			t.sub.TextColor3 = UITheme.color.apagado
			t.barFill.Size = UDim2.fromScale(0, 1)
			t.equipBtn.Visible = false
		end
	end
end

for id, t in pairs(tarjetas) do
	t.equipBtn.MouseButton1Click:Connect(function()
		selectClass:FireServer(id)
		-- Pintado optimista: el servidor manda, pero esperar al sync deja el boton muerto medio segundo.
		ultimaCol.claseActual = id
		actualizarColeccion(ultimaCol)
	end)
end

-- ===================================================================================================
-- RULETA  ·  animacion (el resultado lo decide el SERVIDOR; aqui solo se frena encima)
-- ===================================================================================================
local lastTile
local function tileCentrado() return math.floor((-strip.Position.X.Offset + REEL_W / 2) / TILE) end
local function setStrip(x)
	while x <= -PERIODO do x += PERIODO end
	while x > 0 do x -= PERIODO end
	stripX = x
	strip.Position = UDim2.fromOffset(x, 0)
end
local function empezarRoll()
	rolling = true; lastTile = nil
	if reelConn then reelConn:Disconnect() end
	reelConn = RunService.RenderStepped:Connect(function(dt)
		if rolling then setStrip(stripX - 1500 * dt) end
		local tc = tileCentrado()
		if tc ~= lastTile then -- TIC al pasar cada carta
			lastTile = tc
			mStroke.Thickness = 5
			mStroke.Color = Color3.fromRGB(255, 255, 255)
		end
		mStroke.Thickness += (2 - mStroke.Thickness) * math.min(1, dt * 14) -- decae a fino
		mStroke.Color = mStroke.Color:Lerp(UITheme.color.acento, math.min(1, dt * 14))
	end)
end
local function pararRoll(resultId, onDone)
	rolling = false
	local p = 1
	for i, c in ipairs(clases) do if c.id == resultId then p = i end end
	local Xland = (REEL_W / 2) - ((p - 1) * TILE + TILE / 2)
	while Xland <= -PERIODO do Xland += PERIODO end
	while Xland > 0 do Xland -= PERIODO end
	local targetX = Xland - 4 * PERIODO -- 4 vueltas mas antes de frenar
	while targetX >= stripX do targetX -= PERIODO end
	local tw = TweenService:Create(strip, TweenInfo.new(1.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(targetX, 0) })
	tw.Completed:Connect(function()
		stripX = targetX
		if reelConn then reelConn:Disconnect(); reelConn = nil end
		mStroke.Thickness = 6
		mStroke.Color = UITheme.tono(UITheme.color.acento, 0.5) -- pulso fuerte de aterrizaje
		TweenService:Create(mStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Thickness = 2 }):Play()
		if onDone then onDone() end
	end)
	tw:Play()
end

-- ===================================================================================================
-- REVELADO
-- ===================================================================================================
local function mostrarReveal(res)
	if not res then
		-- El servidor devuelve nil tambien cuando el perfil aun no cargo o cuando la policy corta. Se lee como
		-- "no se pudo": nunca se promete que sea por gemas si no lo sabemos.
		revealNombre.Text = policyRestringido() and "Not available" or "Not enough Gems"
		revealNombre.TextColor3 = UITheme.color.peligro
		revealEstado.Text = policyRestringido() and "" or "Tap GET GEMS to top up"
		revealEstado.TextColor3 = UITheme.color.textoTenue
		revealBuff.Text = ""
		return
	end

	revealNombre.Text = res.nombre or res.claseId
	revealNombre.TextColor3 = res.color or UITheme.color.texto

	if res.isNew then
		revealEstado.Text = "NEW CLASS UNLOCKED"
		revealEstado.TextColor3 = UITheme.rareza.legendario
	elseif res.leveledUp then
		revealEstado.Text = "LEVEL UP  ->  Lv " .. res.nivel
		revealEstado.TextColor3 = UITheme.color.ok
	else
		local costo = ClassData.ShardsParaSubir[res.nivel]
		revealEstado.Text = "Duplicate  ·  +1 shard (" .. res.shards .. "/" .. (costo or "MAX") .. ")"
		revealEstado.TextColor3 = UITheme.color.textoTenue
	end

	for _, c in ipairs(clases) do
		if c.id == res.claseId then revealBuff.Text = c.pasivaDesc end
	end

	-- POP del nombre + FLASH (mas fuerte en NEW / LEVEL UP: la recompensa gorda tiene que SONAR distinta)
	revealScale.Scale = 1.4
	TweenService:Create(revealScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local fuerte = res.isNew or res.leveledUp
	flash.BackgroundColor3 = res.color or Color3.new(1, 1, 1)
	flash.BackgroundTransparency = fuerte and 0.55 or 0.82
	TweenService:Create(flash, TweenInfo.new(fuerte and 0.65 or 0.4, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

-- ===================================================================================================
-- MULTI-TIRADA  ·  3 ruletas a la vez (overlay por encima del panel)
-- ===================================================================================================
-- Va colgado del overlay y no del panel: con ZIndexBehavior Sibling, un hijo del overlay con ZIndex alto se
-- dibuja por encima del panel Y de todos sus descendientes. Active = true para que no se cuelen los toques.
local multiView = Instance.new("Frame")
multiView.Name = "Multi"
multiView.Size = UDim2.fromScale(1, 1)
multiView.BackgroundColor3 = Color3.new(0, 0, 0)
multiView.BackgroundTransparency = 0.45 -- 22-jul: menos oscuro (Bastian: "la pantalla se ve oscurecida al spinear"). Antes 0.25
multiView.BorderSizePixel = 0
multiView.Active = true
multiView.ZIndex = 6
multiView.Visible = false
multiView.Parent = overlay

local multiCaja = Instance.new("Frame")
multiCaja.AnchorPoint = Vector2.new(0.5, 0.5)
multiCaja.Position = UDim2.fromScale(0.5, 0.5)
multiCaja.Size = UDim2.fromOffset(560, 320)
multiCaja.BackgroundTransparency = 1
multiCaja.Parent = multiView
UITheme.escalar(multiCaja, { alto = 420, min = 0.6 })

UITheme.etiqueta(multiCaja, "MULTI PULL", {
	fuente = UITheme.fuente.titulo, tam = 22, color = UITheme.color.texto,
	pos = UDim2.new(0, 0, 0, 0), tamano = UDim2.new(1, 0, 0, 28), align = Enum.TextXAlignment.Center,
})

local multiFila = Instance.new("Frame")
multiFila.Size = UDim2.new(1, 0, 0, 190)
multiFila.Position = UDim2.fromOffset(0, 38)
multiFila.BackgroundTransparency = 1
multiFila.Parent = multiCaja
local multiLay = Instance.new("UIListLayout")
multiLay.FillDirection = Enum.FillDirection.Horizontal
multiLay.HorizontalAlignment = Enum.HorizontalAlignment.Center
multiLay.VerticalAlignment = Enum.VerticalAlignment.Center
multiLay.Padding = UDim.new(0, 16)
multiLay.SortOrder = Enum.SortOrder.LayoutOrder
multiLay.Parent = multiFila

local slots = {}
for i = 1, TIRADAS_MULTI do
	local slot = Instance.new("Frame")
	slot.Size = UDim2.fromOffset(158, 186)
	slot.LayoutOrder = i
	slot.Parent = multiFila
	UITheme.placa(slot, {
		fondo = UITheme.color.fondoPlaca, alto = Color3.fromRGB(52, 50, 63), bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.tarjeta, sinBorde = true,
	})
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.color.apagado; stroke.Thickness = 2; stroke.Transparency = 0.25
	stroke.Parent = slot
	local dibujo = UITheme.icono(slot, "orbe", UITheme.color.apagado, {
		lado = 30, pos = UDim2.new(0.5, 0, 0, 26), anchor = Vector2.new(0.5, 0),
	})
	local nom = UITheme.etiqueta(slot, "?", {
		fuente = UITheme.fuente.titulo, tam = 16, color = UITheme.color.texto,
		pos = UDim2.new(0, 6, 0, 74), tamano = UDim2.new(1, -12, 0, 22), align = Enum.TextXAlignment.Center,
	})
	nom.TextTruncate = Enum.TextTruncate.AtEnd
	local est = UITheme.etiqueta(slot, "", {
		fuente = UITheme.fuente.dato, tam = 12, color = UITheme.color.textoTenue,
		pos = UDim2.new(0, 6, 0, 100), tamano = UDim2.new(1, -12, 0, 18), align = Enum.TextXAlignment.Center,
	})
	local buff = UITheme.etiqueta(slot, "", {
		fuente = UITheme.fuente.etiqueta, tam = 10, color = UITheme.color.textoSuave,
		pos = UDim2.new(0, 8, 0, 122), tamano = UDim2.new(1, -16, 0, 54), align = Enum.TextXAlignment.Center,
		alignY = Enum.TextYAlignment.Top, wrap = true,
	})
	slots[i] = { slot = slot, stroke = stroke, dibujo = dibujo, nom = nom, est = est, buff = buff }
end

local multiCerrar, multiCerrarLbl = UITheme.boton(multiCaja, "CONTINUE", {
	tamano = UDim2.new(0, 200, 0, UITheme.TACTIL_MIN), pos = UDim2.new(0.5, -100, 1, -48),
	ancho = 200, tam = 15, nombre = "Continuar",
	color = Color3.fromRGB(48, 38, 70), altoColor = Color3.fromRGB(70, 55, 100), bajoColor = Color3.fromRGB(33, 26, 48),
	acento = ACENTO,
})
multiCerrar.Visible = false
multiCerrar.MouseButton1Click:Connect(function() multiView.Visible = false end)

local function pasivaDe(id)
	for _, c in ipairs(clases) do if c.id == id then return c.pasivaDesc end end
	return ""
end

local function animarMulti(results)
	multiView.Visible = true
	multiCerrar.Visible = false
	multiCerrarLbl.Text = "CONTINUE"
	for _, s in ipairs(slots) do s.est.Text = ""; s.buff.Text = "" end

	local terminados = 0
	for i = 1, TIRADAS_MULTI do
		local s = slots[i]
		local res = results[i]
		task.spawn(function()
			-- Cada slot para un poco despues que el anterior: tres revelados a la vez no se leen.
			local landT = 0.8 + i * 0.4
			local t0 = os.clock()
			while os.clock() - t0 < landT do
				local c = clases[math.random(1, #clases)]
				s.nom.Text = c.nombre
				s.nom.TextColor3 = c.color
				s.stroke.Color = colRareza(c.rareza)
				UITheme.pictograma(s.dibujo, UITheme.iconoClase[c.id] or "orbe", c.color) -- 22-jul: el ICONO tambien gira = tragaperras (antes solo el texto = parecia bug)
				task.wait(0.055)
			end
			if res then
				s.nom.Text = res.nombre or res.claseId or "?"
				s.nom.TextColor3 = res.color or UITheme.color.texto
				s.stroke.Color = colRareza(res.rareza)
				UITheme.pictograma(s.dibujo, UITheme.iconoClase[res.claseId] or "orbe", res.color or UITheme.color.apagado)
				if res.isNew then
					s.est.Text = "NEW!"; s.est.TextColor3 = UITheme.rareza.legendario
				elseif res.leveledUp then
					s.est.Text = "LEVEL UP  Lv " .. tostring(res.nivel); s.est.TextColor3 = UITheme.color.ok
				else
					s.est.Text = "+1 shard  (Lv " .. tostring(res.nivel) .. ")"; s.est.TextColor3 = UITheme.color.textoTenue
				end
				s.buff.Text = pasivaDe(res.claseId)
			else
				-- Menos resultados que slots (se quedo sin Gems a mitad): slot VACIO. Pintar una clase al azar
				-- de la animacion seria hacerle creer que le toco algo.
				s.nom.Text = "-"
				s.nom.TextColor3 = UITheme.color.apagado
				s.stroke.Color = UITheme.color.apagado
				UITheme.pictograma(s.dibujo, "candado", UITheme.color.apagado)
				s.est.Text = "No pull"
				s.est.TextColor3 = UITheme.color.apagado
				s.buff.Text = ""
			end
			-- POP de aterrizaje (tragaperras): el slot da un golpe de escala al parar
			local sc = s.slot:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", s.slot)
			sc.Scale = 1.16
			TweenService:Create(sc, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			terminados += 1
			if terminados >= TIRADAS_MULTI then multiCerrar.Visible = true end
		end)
	end
end

-- ===================================================================================================
-- TIRAR
-- ===================================================================================================
local function spin()
	if spinning then return end
	if policyRestringido() then return end -- CUMPLIMIENTO: ni se pide al servidor
	if not puedeSpin() then mostrarReveal(nil); return end
	spinning = true
	refrescarBotones()
	revealEstado.Text = ""; revealBuff.Text = ""
	revealNombre.Text = "..."; revealNombre.TextColor3 = UITheme.color.textoSuave
	empezarRoll()
	gachaSpin:FireServer()
end

local function spinMulti()
	if spinning then return end
	if policyRestringido() then return end -- CUMPLIMIENTO
	if not puedeSpin() then mostrarReveal(nil); return end
	spinning = true
	refrescarBotones()
	gachaSpin:FireServer(TIRADAS_MULTI) -- N resultados -> N ruletas a la vez (animarMulti)
end

rollBtn.MouseButton1Click:Connect(spin)

x3Btn.MouseButton1Click:Connect(function()
	if policyRestringido() then return end
	if player:GetAttribute("Pass_x3") ~= true then
		MarketplaceService:PromptGamePassPurchase(player, MonetizationData.Gamepasses.x3)
		return
	end
	if not puedeSpin(TIRADAS_MULTI) then return end -- 22-jul (audit): la x3 cuesta SPIN_COST*3 (300); no dispares con 100
	spinMulti()
end)

autoBtn.MouseButton1Click:Connect(function()
	if policyRestringido() then return end
	if player:GetAttribute("Pass_autospin") ~= true then
		MarketplaceService:PromptGamePassPurchase(player, MonetizationData.Gamepasses.autospin)
		return
	end
	autoOn = not autoOn
	refrescarBotones()
	if autoOn and not spinning and puedeSpin() then spin() end
end)

player:GetAttributeChangedSignal("Pass_x3"):Connect(refrescarBotones)
player:GetAttributeChangedSignal("Pass_autospin"):Connect(refrescarBotones)

gachaSpin.OnClientEvent:Connect(function(res)
	if not res then -- sin Gems/tiradas, perfil sin cargar, o policy: el servidor no dice cual y no lo inventamos
		rolling = false
		if reelConn then reelConn:Disconnect(); reelConn = nil end
		spinning = false
		autoOn = false -- si no, el autospin se queda girando en seco
		refrescarBotones()
		mostrarReveal(nil)
		return
	end
	if res.multi then -- multi-tirada: sin ruleta grande, se revelan los slots
		spinning = false
		refrescarBotones()
		if #res.multi > 0 then animarMulti(res.multi) else mostrarReveal(nil) end
		return
	end
	if res.tiradasGratis ~= nil then tiradasGratis = res.tiradasGratis end
	pararRoll(res.claseId, function()
		spinning = false
		refrescarBotones()
		mostrarReveal(res)
		if autoOn and puedeSpin() then
			task.delay(0.6, function() if autoOn and not spinning then spin() end end)
		elseif autoOn then
			autoOn = false
			refrescarBotones()
		end
	end)
end)

gachaSync.OnClientEvent:Connect(actualizarColeccion)

-- ===================================================================================================
-- ABRIR / CERRAR  (+ el aviso de AUTOSPIN)
-- ===================================================================================================
-- Cerrar con el autospin encendido sigue GASTANDO Gems de fondo. Se avisa antes de cerrar, con las tres
-- salidas claras. Sin este aviso la queja es siempre la misma: "me he quedado sin gemas y no se por que".
local avisoAuto = Instance.new("Frame")
avisoAuto.Name = "AvisoAuto"
avisoAuto.AnchorPoint = Vector2.new(0.5, 0.5)
avisoAuto.Position = UDim2.fromScale(0.5, 0.5)
avisoAuto.Size = UDim2.fromOffset(400, 208)
avisoAuto.ZIndex = 8 -- por encima del panel Y de la multi-tirada
avisoAuto.Visible = false
avisoAuto.Parent = overlay
UITheme.placa(avisoAuto, {
	fondo = UITheme.color.fondoPlaca, alto = Color3.fromRGB(52, 48, 58), bajo = Color3.fromRGB(28, 26, 32),
	radio = UITheme.radio.panel, borde = UITheme.color.acento, grosor = 2, bordeTransp = 0.4,
})
UITheme.icono(avisoAuto, "reloj", UITheme.color.acento, { lado = 26, pos = UDim2.new(0, 18, 0, 18), anchor = Vector2.new(0, 0) })
UITheme.etiqueta(avisoAuto, "AUTOSPIN IS STILL ON", {
	fuente = UITheme.fuente.titulo, tam = 16, color = UITheme.color.texto,
	pos = UDim2.new(0, 54, 0, 20), tamano = UDim2.new(1, -70, 0, 22),
})
UITheme.etiqueta(avisoAuto, "If you close without turning it off, it will keep pulling and spending your Gems.", {
	fuente = UITheme.fuente.etiqueta, tam = 13, color = UITheme.color.textoSuave,
	pos = UDim2.new(0, 22, 0, 52), tamano = UDim2.new(1, -44, 0, 44), wrap = true, alignY = Enum.TextYAlignment.Top,
})

local function cerrarGacha()
	avisoAuto.Visible = false
	multiView.Visible = false
	api.cerrar() -- por la api: es quien lleva el contador de MenuAbierto
end
local function pedirCerrar()
	if autoOn then avisoAuto.Visible = true else cerrarGacha() end
end

-- Tres salidas, con la SEGURA primero (izquierda) y la de riesgo en ambar. Anchos distintos: el boton que
-- recomendamos es el mas ancho.
local avisoOpciones = {
	{ texto = "STOP & CLOSE", x = 22, w = 142, variante = "ok", cb = function() autoOn = false; refrescarBotones(); cerrarGacha() end },
	{ texto = "KEEP & CLOSE", x = 172, w = 120, variante = "normal", cb = cerrarGacha },
	{ texto = "CANCEL", x = 300, w = 78, variante = "apagado", cb = function() avisoAuto.Visible = false end },
}
for _, o in ipairs(avisoOpciones) do
	local b = UITheme.boton(avisoAuto, o.texto, {
		tamano = UDim2.new(0, o.w, 0, UITheme.TACTIL_MIN), pos = UDim2.new(0, o.x, 1, -60),
		ancho = o.w, tam = 12, variante = o.variante, nombre = "Aviso_" .. o.texto,
	})
	b.ZIndex = 9
	b.MouseButton1Click:Connect(o.cb)
end

-- X de la cabecera (la pinto yo porque tiene que pasar por pedirCerrar; ver el sinCerrar del panel).
local cerrarBtn = Instance.new("TextButton")
cerrarBtn.Name = "Cerrar"
cerrarBtn.Size = UDim2.fromOffset(UITheme.TACTIL_MIN, UITheme.TACTIL_MIN) -- 44: minimo tactil
cerrarBtn.AnchorPoint = Vector2.new(1, 0)
cerrarBtn.Position = UDim2.new(1, -10, 0, 5)
cerrarBtn.Text = "" -- vacio a proposito: que no colisione con la busqueda por .Text de HubClient
cerrarBtn.AutoButtonColor = false
cerrarBtn.Parent = barra
UITheme.placa(cerrarBtn, {
	fondo = Color3.fromRGB(46, 34, 38), alto = Color3.fromRGB(66, 44, 48), bajo = Color3.fromRGB(32, 24, 28),
	radio = UITheme.radio.boton, bordeTransp = 0.35,
})
UITheme.icono(cerrarBtn, "cruz", Color3.fromRGB(226, 150, 146), {
	lado = 16, pos = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5),
})
UITheme.pulsacion(cerrarBtn)
cerrarBtn.MouseButton1Click:Connect(pedirCerrar)

-- C (fix): quitado el cerrar-al-tocar-fuera; se cierra SOLO con la X.

abrirBtn.MouseButton1Click:Connect(function()
	api.abrir()
	refrescarBotones()
	gachaSync:FireServer() -- pide coleccion + diario al abrir
end)

-- ===================================================================================================
-- GET GEMS  ·  el tercer boton
-- ===================================================================================================
-- No vende aqui: sube el atributo AbrirStore y deja que StoreClient abra SU pantalla (el mismo patron
-- cliente-a-cliente del "+" del HUD). Ademas hay que CERRAR el gacha: la tienda es DisplayOrder 64 y este
-- panel 66, asi que si nos quedamos abiertos la tienda se abriria DEBAJO y no se veria.
-- El autospin se apaga al salir por aqui: si vienes a comprar gemas es que no te llegan, y dejar tirando
-- sola una pantalla que ya no ves es justo lo que el aviso de arriba intenta evitar.
gemsBtn.MouseButton1Click:Connect(function()
	if policyRestringido() then return end -- CUMPLIMIENTO: ni siquiera se ofrece el camino a comprar
	if autoOn then autoOn = false; refrescarBotones() end
	cerrarGacha()
	player:SetAttribute("AbrirStore", (player:GetAttribute("AbrirStore") or 0) + 1)
end)

-- ===================================================================================================
-- POLICY + VISIBILIDAD
-- ===================================================================================================
-- CUMPLIMIENTO paid random items: si el atributo cambia con el panel abierto (PolicyServer responde tarde),
-- se repinta al vuelo. refrescarBotones() ya oculta GET GEMS y bloquea roll/x3/auto cuando toca.
player:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(function()
	refrescarBotones()
	if policyRestringido() then
		multiView.Visible = false -- que no se quede un revelado de gacha delante de un jugador restringido
		autoOn = false
	end
end)

-- Solo en el lobby (fuera en partida)
local function gate()
	local enPartida = player:GetAttribute("InMatch") == true
	abrirBtn.Visible = not enPartida
	if enPartida then
		autoOn = false -- cerrar a la fuerza con el auto encendido seria gastar Gems sin que se vea nada
		refrescarBotones()
		if api.estaAbierto() then cerrarGacha() end -- por la api: si no, MenuAbierto se queda pegado en true
	end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()

refrescarBotones()
gachaSync:FireServer() -- estado inicial de la coleccion (tambien reclama el diario si toca)
