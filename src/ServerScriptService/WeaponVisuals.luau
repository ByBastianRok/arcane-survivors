-- WeaponVisuals (ModuleScript del SERVIDOR) · Sju - la CARA de las armas.
--
-- Un solo sitio que sepa que mesh y que agarre le toca a cada arma. Lo usan:
--   · WeaponSkins  -> al arrancar, para vestir las plantillas de ServerStorage.WeaponTemplates
--   · GameManager  -> al EVOLUCIONAR el arma en mitad de una run, y al revivir con el build evolucionado
--
-- POR QUE EXISTE ESTE MODULO (y no dos trozos de codigo parecidos):
-- Las armas se creaban en BuildInstances como CAJAS de color, y evolucionar consistia en `h.Color = evo.color`.
-- Eso funcionaba con una caja. Desde que las armas son MeshParts CON TEXTURA, el tinte no se ve -- una textura
-- tapa el .Color por completo -- asi que la evolucion, que es el "momento clip" del juego, se habia quedado
-- SIN NINGUN cambio visual. Y no daba ningun error: simplemente no pasaba nada.

local ServerStorage = game:GetService("ServerStorage")

local WeaponVisuals = {}

local meshes = ServerStorage:FindFirstChild("WeaponMeshes")

-- El GRIP dice donde cae la MANO respecto al Handle, NO cuanto se mueve el arma.
-- Los meshes salen con su largo en el eje Y y el origen EN EL CENTRO, asi que sin tocarlo el personaje agarra
-- el arma por la mitad de la hoja. Con Y POSITIVO la mano se va hacia la PUNTA y el arma cuelga hacia abajo
-- (asi se veia sujetando la guadana POR LA HOJA). Tiene que ser NEGATIVO.
-- El giro en X es la inclinacion hacia delante; pasado de 45 grados el arma se tumba y se pierde detras del
-- personaje. Arcos y anillos son los dos casos raros y van comentados.
-- ===== EL GIRO SOBRE EL EJE LARGO (por que las hojas salian PLANAS) =====
-- Bastian, jugando: "la espada deberia estar con las partes afiladas mirandome a mi y al frente y esta como
-- plano". Y es exactamente lo que pasaba, por como estan hechos los meshes:
--   War Blade mide 1.17 x 4.0 x 0.36  ->  Y es el LARGO, X es el ANCHO DE LA HOJA y Z el grosor.
-- O sea que el filo son los extremos en X. Y el eje X del Handle cae sobre el eje LATERAL de la mano, asi que
-- el ancho de la hoja quedaba de lado y lo que veias era la CARA PLANA.
-- El giro de 90 en Y (aplicado ANTES de la inclinacion, para que sea sobre el eje largo del arma y no sobre
-- el del mundo) pone el filo mirando adelante-atras, que es como se sujeta una espada.
-- Solo lo llevan las armas con HOJA: la varita y el orbe son simetricos y les da igual, y el arco y el
-- chakram tienen su propio criterio (ver abajo).
local FILO = CFrame.Angles(0, math.rad(90), 0)

WeaponVisuals.GRIPS = {
	-- Base
	["Arcane Wand"]     = CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(-25), 0, 0),
	-- El arco NO se agarra por un extremo sino por el CENTRO, y girado en Y para que se vea de perfil (visto de
	-- frente un arco es una linea). Bastian: se veia AL REVES (apuntando hacia el jugador) -> giro -90 en vez de +90.
	["Hunter Bow"]      = CFrame.new(0, 0, 0)    * CFrame.Angles(0, math.rad(-90), 0),
	["War Blade"]       = CFrame.new(0, -1.5, 0) * FILO * CFrame.Angles(math.rad(-20), 0, 0),
	-- La guadana "flotaba": su hoja sobresale 2.23 en Z, asi que el origen del mesh (centro de la caja) queda lejos
	-- del MANGO. El offset final CFrame.new(0,0,-1.1) (espacio del mesh, tras las rotaciones) mueve la mano al asta.
	-- Verificado en Play: la sujeta por el palo, hoja arriba (aspecto de segador). El signo importa (+1.1 la alejaba).
	["Reaver Scythe"]   = CFrame.new(0, -1.6, 0) * FILO * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, -1.1),
	-- El chakram es un anillo plano: se lleva tumbado en la palma.
	["Chakram"]         = CFrame.new(0, 0, 0)    * CFrame.Angles(math.rad(90), 0, 0),
	-- Evoluciones (mismo criterio, ajustado a que son mas largas)
	["Inferno Orb"]     = CFrame.new(0, -1.1, 0) * CFrame.Angles(math.rad(-25), 0, 0),
	["Storm Bow"]       = CFrame.new(0, 0, 0)    * CFrame.Angles(0, math.rad(-90), 0),
	["Doom Greatsword"] = CFrame.new(0, -1.9, 0) * FILO * CFrame.Angles(math.rad(-20), 0, 0),
	["Blood Harvest"]   = CFrame.new(0, -1.8, 0) * FILO * CFrame.Angles(math.rad(-20), 0, 0),
	["Bladestorm"]      = CFrame.new(0, 0, 0)    * CFrame.Angles(math.rad(90), 0, 0),
}

function WeaponVisuals.tieneMesh(nombreArma)
	return meshes ~= nil and meshes:FindFirstChild(nombreArma) ~= nil
end

-- Le pone a un Tool YA EXISTENTE la cara del arma 'nombreArma'.
--
-- Usa ApplyMesh, que cambia mesh Y textura EN SITIO sin sustituir la pieza. Eso NO es un detalle: cuando esto
-- se llama desde una evolucion, el arma esta EQUIPADA y soldada a la mano; si se sustituyera la instancia del
-- Handle, el agarre se rompe y el arma se cae al suelo.
-- Devuelve true si consiguio ponerle el mesh, false si no habia (para que quien llame use su respaldo).
function WeaponVisuals.aplicar(tool, nombreArma)
	if not tool then return false end
	local h = tool:FindFirstChild("Handle")
	if not h then return false end

	local mesh = meshes and meshes:FindFirstChild(nombreArma)
	if not (mesh and mesh:IsA("MeshPart") and h:IsA("MeshPart")) then
		-- Sin mesh (o el Handle sigue siendo una caja): solo se ajusta el agarre si lo tenemos.
		if WeaponVisuals.GRIPS[nombreArma] then tool.Grip = WeaponVisuals.GRIPS[nombreArma] end
		return false
	end

	local ok = pcall(function() h:ApplyMesh(mesh) end)
	if not ok then return false end
	-- El tamano va DESPUES del ApplyMesh: aplicar un mesh nuevo trae consigo su tamano original y hay que
	-- volver a poner el que le dimos al escalarlo (uniforme, para no deformarlo).
	h.Size = mesh.Size
	h.Color = mesh.Color
	if WeaponVisuals.GRIPS[nombreArma] then tool.Grip = WeaponVisuals.GRIPS[nombreArma] end
	return true
end

return WeaponVisuals
