-- ProfileClient (LocalScript) · S2 - panel PLAYER INFO (META): clase + stats de los perks + records.
-- Boton en el lobby; pide ProfileSync al servidor y pinta. Marca MenuAbierto (esconde PLAY).
--
-- === QUE CAMBIO AQUI (Sju/arte) Y POR QUE ===
-- Antes esto eran DOS columnas de "etiqueta ....... valor" (18 filas de texto del mismo tamaño). Una lista asi
-- se lee como un log de depuracion: no hay jerarquia, todos los datos pesan igual y en movil, con el panel
-- escalado, las filas de 16px se juntan. Ahora:
--   · CABECERA con el avatar real del jugador (headshot), su nombre y su clase. Es SU ficha: que se vea el.
--   · Los datos van en TARJETAS agrupadas por TEMA (combate / aguante / records / clasificacion). Agrupar da
--     el contexto que la lista corrida no daba: "Crit Damage" al lado de "Damage" se compara solo.
--   · CIFRA GRANDE arriba, etiqueta pequeña debajo. Lo que el jugador viene a mirar es el numero, no la
--     palabra; al reves (etiqueta grande, dato pequeño) obliga a leer dos veces cada tarjeta.
--   · Los bonus a 0 se pintan en gris apagado: el ojo salta directo a lo que SI tienes mejorado.
--
-- NO se ha tocado nada de datos: mismo remote ProfileSync (mismo FireServer al abrir, mismo OnClientEvent),
-- mismas claves del payload del servidor (stats/records/clase) y mismo gate por el atributo InMatch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local profileSync = remotes:WaitForChild("ProfileSync")

-- UITheme vive en /src pero puede NO estar espejado en el place (se añadio despues que estos menus). Un
-- WaitForChild pelado se quedaria colgado PARA SIEMPRE y en silencio: no habria panel, no habria boton, y
-- HubClient solo diria que le falta una entrada. Con el aviso previo el fallo se lee en la consola en 10s.
local modulos = ReplicatedStorage:WaitForChild("Modules")
if not modulos:WaitForChild("UITheme", 10) then
	warn("[ProfileClient] falta ReplicatedStorage/Modules/UITheme -> el panel PLAYER INFO no se creara")
end
local UITheme = require(modulos:WaitForChild("UITheme"))

local ACENTO = UITheme.acentos.profile -- el mismo azul que usa el icono PLAYER INFO del Hub: continuidad
local COMBATE = Color3.fromRGB(198, 112, 86)
local AGUANTE = UITheme.acentos.perks
local RECORDS = UITheme.acentos.quests

-- ===================================================================================================
-- GUIS
-- ===================================================================================================
-- DOS ScreenGui a proposito: UITheme.panel apaga el .Enabled del ScreenGui que le pases al cerrar, asi que
-- si el boton de abrir viviera ahi dentro se apagaria CON el panel y no habria forma de reabrirlo.
local gui = Instance.new("ScreenGui")
gui.Name = "ProfileUI"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 40; gui.Parent = playerGui

local guiPanel = Instance.new("ScreenGui")
guiPanel.Name = "ProfileUIPanel"; guiPanel.ResetOnSpawn = false; guiPanel.IgnoreGuiInset = true
guiPanel.DisplayOrder = 65; guiPanel.Parent = playerGui

-- ===================================================================================================
-- BOTON DE ABRIR
-- ===================================================================================================
-- OJO: .Text tiene que seguir siendo EXACTAMENTE "PLAYER INFO". HubClient recorre todos los TextButton del
-- PlayerGui y adopta este por ese texto para meterlo en la columna de iconos del lobby; si lo cambio, el
-- boton desaparece de la columna.
-- La posicion de abajo es solo el FALLBACK (si HubClient no llegara a adoptarlo): va abajo a la DERECHA
-- porque el cuadrante inferior izquierdo es del joystick.
local abrirBtn = Instance.new("TextButton")
abrirBtn.Name = "Open"
abrirBtn.Size = UDim2.fromOffset(160, 46) -- alto >= 44: minimo tactil en movil
abrirBtn.Position = UDim2.new(1, -20, 1, -150); abrirBtn.AnchorPoint = Vector2.new(1, 1)
abrirBtn.Text = "PLAYER INFO"
abrirBtn.Font = UITheme.fuente.dato
abrirBtn.TextSize = 15
abrirBtn.TextColor3 = UITheme.color.texto
abrirBtn.Parent = gui
-- sinGradiente: aqui el texto visible es el del PROPIO boton (no puedo meterlo en un TextLabel hijo, porque
-- al adoptarlo HubClient vacia .Text pero el hijo se quedaria escrito encima del pictograma). Y un UIGradient
-- en un TextButton tiñe TAMBIEN su texto, asi que se queda plano.
UITheme.placa(abrirBtn, { radio = UITheme.radio.boton, sinGradiente = true, bordeTransp = 0.3 })
-- La barra se llama HubAcento a proposito. HubClient reutiliza sus hijos POR NOMBRE al adoptar el boton
-- (HubIcono / HubLabel / HubAcento) y, si no encuentra uno con ese nombre, CREA otro encima: quedarian dos
-- barras desalineadas en el icono de la columna. ShopClient documenta la misma trampa.
UITheme.acentoBarra(abrirBtn, ACENTO, {
	nombre = "HubAcento",
	ancho = 30, alto = 3, pos = UDim2.new(0, 12, 1, -8), anchor = Vector2.new(0, 0),
})
-- Y AQUI NO se llama a UITheme.pulsacion: HubClient engancha su propio resalte a este mismo boton al
-- adoptarlo, y los dos tweens irian contra el mismo BackgroundColor3 con colores base distintos -> el icono
-- parpadea al soltar el dedo.

-- ===================================================================================================
-- PANEL
-- ===================================================================================================
local ANCHO, ALTO = 700, 496
local _overlay, panel, _barra, api = UITheme.panel(guiPanel, ANCHO, ALTO, "PLAYER INFO", {
	acento = ACENTO,
	clave = "Profile", -- clave del contador de MenuAbierto (asi cerrar ESTE no apaga el flag de otro panel)
})

-- ---------- Cabecera: avatar + nombre + clase ----------
local AV = 78
local avatarCaja = Instance.new("Frame")
avatarCaja.Name = "Avatar"
avatarCaja.Size = UDim2.fromOffset(AV, AV)
avatarCaja.Position = UDim2.fromOffset(22, 62)
avatarCaja.ClipsDescendants = true -- recorta el headshot a la esquina redondeada de la placa
avatarCaja.Parent = panel
UITheme.placa(avatarCaja, {
	fondo = Color3.fromRGB(30, 29, 38), alto = Color3.fromRGB(42, 41, 52), bajo = Color3.fromRGB(24, 23, 30),
	radio = UITheme.radio.placa, grosor = 2, bordeTransp = 0.2,
})
local avatarBorde = avatarCaja:FindFirstChildOfClass("UIStroke")

-- Busto dibujado DEBAJO de la imagen: si la miniatura tarda (o falla el servicio de thumbnails, que pasa en
-- Studio sin sesion), el hueco no se queda negro.
-- Los pictogramas estan medidos EN PIXELES para un lienzo de 30x30 y la caja recorta (ClipsDescendants).
-- Aqui se montaba una caja de 30 y se le metia un UIScale de 1.5 DENTRO: el dibujo crecia pero la caja seguia
-- midiendo 30 y le cortaba los hombros por los lados. Ahora UITheme.icono acepta cualquier 'lado' y hace el
-- escalado el mismo, en un envoltorio del tamano pedido, asi que basta con pedir 45.
UITheme.icono(avatarCaja, "busto", Color3.fromRGB(84, 92, 112), {
	lado = 45, pos = UDim2.fromScale(0.5, 0.56), anchor = Vector2.new(0.5, 0.5),
})

local avatarImg = Instance.new("ImageLabel")
avatarImg.Name = "Headshot"
avatarImg.Size = UDim2.fromScale(1, 1)
avatarImg.BackgroundTransparency = 1
avatarImg.Image = ""
avatarImg.ZIndex = 2
avatarImg.Parent = avatarCaja
local ai = Instance.new("UICorner"); ai.CornerRadius = UDim.new(0, UITheme.radio.placa); ai.Parent = avatarImg

-- GetUserThumbnailAsync BLOQUEA (llamada web): va en su propio hilo o retrasaria todo el montaje del panel.
-- Y en pcall porque el servicio falla de vez en cuando y un error aqui mataria el resto del script.
task.spawn(function()
	for intento = 1, 3 do
		local ok, contenido = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and contenido and contenido ~= "" then
			avatarImg.Image = contenido
			return
		end
		task.wait(1.5 * intento)
	end
end)

local nombreLbl = UITheme.etiqueta(panel, player.DisplayName, {
	nombre = "Nombre",
	fuente = UITheme.fuente.titulo, tam = 22, color = UITheme.color.texto,
	-- -180 de ancho: el boton de cerrar (44px) vive en la esquina derecha de la barra y el cuadro del nombre
	-- no debe llegar hasta el, o los nombres largos se meterian debajo.
	pos = UDim2.fromOffset(112, 62), tamano = UDim2.new(1, -180, 0, 26),
})
nombreLbl.TextTruncate = Enum.TextTruncate.AtEnd -- hay nombres larguisimos; que no se coma el boton de cerrar

-- El @usuario SOLO si difiere del nombre visible: repetir "Bastian / @Bastian" es ruido.
if player.Name ~= player.DisplayName then
	UITheme.etiqueta(panel, "@" .. player.Name, {
		nombre = "Usuario", tam = 12, color = UITheme.color.textoTenue,
		pos = UDim2.fromOffset(113, 88), tamano = UDim2.new(0, 300, 0, 16),
	})
end

-- Pildora de clase: se AUTODIMENSIONA al texto (los nombres de clase van a cambiar y una anchura fija dejaria
-- aire muerto a la derecha o cortaria el nivel).
local clasePill = Instance.new("Frame")
clasePill.Name = "ClasePill"
clasePill.Size = UDim2.fromOffset(0, 26)
clasePill.AutomaticSize = Enum.AutomaticSize.X
clasePill.Position = UDim2.fromOffset(112, 108)
clasePill.Parent = panel
UITheme.placa(clasePill, {
	fondo = Color3.fromRGB(30, 29, 38), alto = Color3.fromRGB(40, 39, 50), bajo = Color3.fromRGB(25, 24, 32),
	radio = 13, bordeTransp = 0.45,
})
local pillPad = Instance.new("UIPadding")
pillPad.PaddingLeft = UDim.new(0, 10); pillPad.PaddingRight = UDim.new(0, 12); pillPad.Parent = clasePill
local pillLay = Instance.new("UIListLayout")
pillLay.FillDirection = Enum.FillDirection.Horizontal
pillLay.VerticalAlignment = Enum.VerticalAlignment.Center
pillLay.Padding = UDim.new(0, 8)
pillLay.Parent = clasePill

local puntoClase = Instance.new("Frame")
puntoClase.Name = "Punto"
puntoClase.Size = UDim2.fromOffset(9, 9)
puntoClase.BackgroundColor3 = UITheme.color.apagado
puntoClase.BorderSizePixel = 0
puntoClase.LayoutOrder = 1
puntoClase.Parent = clasePill
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = puntoClase

local claseLbl = UITheme.etiqueta(clasePill, "No class", {
	nombre = "ClaseTexto", fuente = UITheme.fuente.dato, tam = 14, color = UITheme.color.textoSuave,
	tamano = UDim2.fromOffset(0, 20), layoutOrder = 2,
})
claseLbl.AutomaticSize = Enum.AutomaticSize.X

-- La pasiva de la clase, en gris y a una sola linea: es contexto, no un dato que se compare.
local buffLbl = UITheme.etiqueta(panel, "", {
	nombre = "Buff", tam = 12, color = UITheme.color.textoTenue,
	pos = UDim2.fromOffset(113, 138), tamano = UDim2.new(1, -140, 0, 16),
})
buffLbl.TextTruncate = Enum.TextTruncate.AtEnd

UITheme.separador(panel, 160, { izq = 22, margen = 60 })

-- ---------- Zona de tarjetas ----------
local scroll = UITheme.scroll(panel, {
	nombre = "Datos",
	pos = UDim2.fromOffset(22, 172),
	tamano = UDim2.new(1, -44, 1, -190),
	padding = 14,
})

local ALTO_TARJETA, HUECO = 62, 11

-- Cabecera de grupo: pictograma + titulo a la IZQUIERDA y una linea fina que arranca DONDE ACABA el texto y
-- muere antes del borde derecho. Un titulo centrado con la linea a los dos lados es justo el patron de
-- plantilla que hay que evitar; ademas asi se leen los grupos de un vistazo al bajar por la lista.
-- OJO: 'filas' ya NO decide el alto, solo queda como pista de intencion. El alto lo pone AutomaticSize.
-- Por que: la seccion tenia alto FIJO calculado con ese numero, y COMBAT (6 tarjetas, 3 columnas x 2 filas)
-- se desbordaba porque en pantalla solo entraban 2 por fila -> 3 filas -> la tercera se dibujaba ENCIMA de la
-- cabecera de RESILIENCE. Con AutomaticSize la seccion crece hasta lo que de verdad ocupa la malla, asi que
-- da igual cuantas columnas entren al final.
local function seccion(titulo, dibujo, acento, columnas, filas, orden)
	local sec = Instance.new("Frame")
	sec.Name = titulo
	sec.Size = UDim2.new(1, 0, 0, 34)
	sec.AutomaticSize = Enum.AutomaticSize.Y
	sec.BackgroundTransparency = 1
	sec.LayoutOrder = orden
	sec.Parent = scroll

	-- Ya se puede pedir el lado directamente: UITheme.icono escala el dibujo el mismo en un envoltorio. Antes
	-- habia que pedir 30 y encogerlo a mano con un UIScale, porque un lado menor recortaba el dibujo.
	UITheme.icono(sec, dibujo, acento, { lado = 21, pos = UDim2.fromOffset(0, 2), anchor = Vector2.new(0, 0) })
	UITheme.etiqueta(sec, titulo, {
		nombre = "Titulo", fuente = UITheme.fuente.titulo, tam = 13, color = UITheme.color.textoSuave,
		pos = UDim2.fromOffset(26, 3), tamano = UDim2.new(0, 320, 0, 16),
	})
	-- Se MIDE el texto en vez de dejar un hueco fijo: con hueco fijo, "AGUANTE" y "CLASIFICACION" dejarian
	-- separaciones distintas hasta la linea y cantaria a descuadre.
	local ancho = TextService:GetTextSize(titulo, 13, UITheme.fuente.titulo, Vector2.new(400, 20)).X
	local linea = Instance.new("Frame")
	linea.Name = "Regla"
	linea.Position = UDim2.fromOffset(26 + ancho + 12, 11)
	linea.Size = UDim2.new(1, -(26 + ancho + 12 + 14), 0, 1)
	linea.BackgroundColor3 = UITheme.color.placaAlta
	linea.BackgroundTransparency = 0.4
	linea.BorderSizePixel = 0
	linea.Parent = sec

	local malla = Instance.new("Frame")
	malla.Name = "Malla"
	malla.Position = UDim2.fromOffset(0, 34)
	malla.Size = UDim2.new(1, 0, 0, 0)
	malla.AutomaticSize = Enum.AutomaticSize.Y -- crece con las filas que salgan de verdad
	malla.BackgroundTransparency = 1
	malla.Parent = sec
	local grid = Instance.new("UIGridLayout")
	-- Celda en ESCALA (no en px): el panel lleva UIScale y el scroll cambia de ancho con el; con px fijos las
	-- tarjetas se saldrian o dejarian una columna coja.
	--
	-- El "- 3" es la HOLGURA, y no es un capricho: la cuenta sin el da 3 celdas + 2 huecos = EXACTAMENTE el
	-- 100% del ancho. A cero de margen, cualquier pixel de mas (el redondeo del UIScale, o la barra de scroll,
	-- que se solapa con el area de los hijos) hace que la tercera celda no quepa y el UIGridLayout la baja de
	-- fila. Eso es lo que dejaba COMBAT a 2 columnas en vez de 3 y desbordaba la seccion.
	grid.CellSize = UDim2.new(1 / columnas, -(HUECO * (columnas - 1) / columnas) - 3, 0, ALTO_TARJETA)
	grid.CellPadding = UDim2.fromOffset(HUECO, HUECO)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = malla
	return malla
end

-- Tarjeta de dato: CIFRA arriba (GothamBlack 21) y etiqueta pequeña debajo, con un raíl fino del color del
-- grupo pegado al canto izquierdo. El color solo aparece en ese raíl: fondos de color = look de plantilla.
local function tarjetaDato(padre, etiqueta, acento, orden)
	local t = Instance.new("Frame")
	t.Name = etiqueta
	t.LayoutOrder = orden
	t.Parent = padre -- el UIGridLayout le pone el Size
	UITheme.placa(t, {
		fondo = Color3.fromRGB(32, 31, 40), alto = Color3.fromRGB(45, 44, 55), bajo = Color3.fromRGB(26, 25, 33),
		radio = UITheme.radio.tarjeta, bordeTransp = 0.45,
	})

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.Size = UDim2.fromOffset(3, 22)
	rail.Position = UDim2.fromOffset(0, 11)
	rail.BackgroundColor3 = acento
	rail.BorderSizePixel = 0
	rail.Parent = t
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = rail

	local valor = UITheme.etiqueta(t, "—", {
		nombre = "Valor", fuente = UITheme.fuente.titulo, tam = 21, color = UITheme.color.texto,
		pos = UDim2.fromOffset(14, 8), tamano = UDim2.new(1, -22, 0, 26),
	})
	UITheme.etiqueta(t, etiqueta, {
		nombre = "Etiqueta", tam = 11, color = UITheme.color.textoTenue,
		pos = UDim2.fromOffset(14, 38), tamano = UDim2.new(1, -22, 0, 14),
	})
	return valor
end

-- Los grupos: ataque / aguante / lo que has hecho / donde estas. Mismos 17 datos que la lista de antes, pero
-- ahora comparables entre si.
local mCombate = seccion("COMBAT", "espada", COMBATE, 3, 2, 1)
local mAguante = seccion("RESILIENCE", "escudo", AGUANTE, 3, 1, 2)
local mRecords = seccion("RECORDS", "calavera", RECORDS, 3, 2, 3)
local mRango = seccion("STANDING", "estrella", ACENTO, 2, 1, 4) -- 2 columnas: rompe la retícula de 3 del resto

local sv = {}
sv.damage = tarjetaDato(mCombate, "DAMAGE", COMBATE, 1)
sv.fireRate = tarjetaDato(mCombate, "FIRE RATE", COMBATE, 2)
sv.crit = tarjetaDato(mCombate, "CRIT CHANCE", COMBATE, 3)
sv.critDmg = tarjetaDato(mCombate, "CRIT DAMAGE", COMBATE, 4)
sv.lifesteal = tarjetaDato(mCombate, "LIFESTEAL", COMBATE, 5)
sv.luck = tarjetaDato(mCombate, "LUCK", COMBATE, 6)
sv.hp = tarjetaDato(mAguante, "MAX HP", AGUANTE, 1)
sv.armor = tarjetaDato(mAguante, "ARMOR", AGUANTE, 2)
sv.speed = tarjetaDato(mAguante, "MOVE SPEED", AGUANTE, 3)

local rv = {}
rv.bestWave = tarjetaDato(mRecords, "BEST WAVE", RECORDS, 1)
rv.bestScore = tarjetaDato(mRecords, "BEST SCORE", RECORDS, 2)
rv.totalKills = tarjetaDato(mRecords, "TOTAL KILLS", RECORDS, 3)
rv.runsPlayed = tarjetaDato(mRecords, "RUNS PLAYED", RECORDS, 4)
rv.playTime = tarjetaDato(mRecords, "PLAY TIME", RECORDS, 5)
rv.clases = tarjetaDato(mRecords, "CLASSES OWNED", RECORDS, 6)
rv.rankG = tarjetaDato(mRango, "GLOBAL RANK", ACENTO, 1)
rv.rankW = tarjetaDato(mRango, "WEEKLY RANK", ACENTO, 2)

-- ===================================================================================================
-- DATOS  ·  formato y pintado (la fuente sigue siendo EXACTAMENTE el payload de ProfileSync)
-- ===================================================================================================
local function fmtPct(x) return (x >= 0 and "+" or "") .. string.format("%d%%", math.floor(x + 0.5)) end
local function fmtTime(s)
	s = math.floor(s)
	local h = math.floor(s / 3600); local m = math.floor((s % 3600) / 60)
	if h > 0 then return h .. "h " .. m .. "m" else return m .. "m " .. (s % 60) .. "s" end
end
-- Separador de millares: "18420" a tamaño 21 se lee como un numero cualquiera; "18,420" se lee de un golpe.
local function fmtNum(n)
	local s = tostring(math.floor(n))
	local salida = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (salida:gsub("^,", ""))
end

-- Un bonus a 0 sigue estando (para que se vea que la stat existe) pero en gris: asi el ojo va directo a lo
-- que el jugador SI ha mejorado, que es lo unico que le interesa mirar aqui.
local function poner(lbl, texto, apagado)
	lbl.Text = texto
	lbl.TextColor3 = apagado and UITheme.color.apagado or UITheme.color.texto
end

local function poblar(p)
	local s, r, cl = p.stats, p.records, p.clase
	if cl then
		claseLbl.Text = cl.nombre .. "   ·   Lv " .. cl.nivel
		claseLbl.TextColor3 = UITheme.color.texto
		puntoClase.BackgroundColor3 = cl.color or ACENTO
		buffLbl.Text = cl.buff or ""
		-- El borde del avatar lleva la RAREZA de la clase equipada (mismo codigo de color que las tarjetas de
		-- objeto del gacha/forja): sin leer nada, ya sabes con que estas jugando.
		if avatarBorde then
			avatarBorde.Color = UITheme.colorRareza(cl.rareza)
			avatarBorde.Transparency = 0.15
		end
	end
	poner(sv.damage, fmtPct(s.damage), s.damage == 0)
	poner(sv.hp, fmtPct(s.hp), s.hp == 0)
	poner(sv.fireRate, fmtPct(s.fireRate), s.fireRate == 0)
	poner(sv.crit, fmtPct(s.crit), s.crit == 0)
	poner(sv.critDmg, fmtPct(s.critDmg), s.critDmg == 0)
	poner(sv.speed, fmtPct(s.speed), s.speed == 0)
	poner(sv.armor, fmtPct(s.armor), s.armor == 0)
	poner(sv.lifesteal, fmtPct(s.lifesteal), s.lifesteal == 0)
	poner(sv.luck, "+" .. math.floor(s.luck + 0.5), s.luck == 0)
	poner(rv.bestWave, tostring(r.bestWave), r.bestWave == 0)
	poner(rv.bestScore, fmtNum(r.bestScore), r.bestScore == 0)
	poner(rv.totalKills, fmtNum(r.totalKills), r.totalKills == 0)
	poner(rv.runsPlayed, fmtNum(r.runsPlayed), r.runsPlayed == 0)
	poner(rv.playTime, fmtTime(r.playTime), r.playTime == 0)
	poner(rv.clases, r.clasesOwned .. "/" .. r.clasesTotal, false)
	poner(rv.rankG, r.rankGlobal and ("#" .. r.rankGlobal) or "200+", r.rankGlobal == nil)
	poner(rv.rankW, r.rankWeekly and ("#" .. r.rankWeekly) or "200+", r.rankWeekly == nil)
end
profileSync.OnClientEvent:Connect(poblar)

-- api.abrir/api.cerrar llevan solos el atributo MenuAbierto (con CONTADOR por clave), que es lo que usa el Hub
-- para esconder la columna de iconos y el PLAY mientras hay un panel delante.
abrirBtn.MouseButton1Click:Connect(function() api.abrir(); profileSync:FireServer() end)

local function gate()
	abrirBtn.Visible = (player:GetAttribute("InMatch") ~= true)
	if player:GetAttribute("InMatch") == true and api.estaAbierto() then api.cerrar() end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()
