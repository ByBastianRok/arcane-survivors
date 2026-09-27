-- WeaponSkins (Script del SERVIDOR) · Sju - viste las PLANTILLAS de armas al arrancar.
--
-- Las armas se creaban en BuildInstances como Tool con un Handle que era literalmente una CAJA de color:
--   Arcane Wand  = caja morada Neon de 0.4 x 0.4 x 2.6
--   Hunter Bow   = caja de madera de 0.3 x 2.6 x 0.5
--   War Blade    = caja blanca de 0.3 x 4 x 0.9
-- O sea, el jugador iba con un palo pegado a la mano, y se ve en cualquier captura del juego.
--
-- POR QUE ESTO CORRE EN RUNTIME y no se arregla a mano en Studio:
-- BuildInstances NO se ejecuta en el juego (es una receta para pegar en la barra de comandos). Un arreglo a
-- mano viviria solo en el archivo del place, NO entraria en git, y habria que repetirlo en el OTRO place del
-- co-op. Aqui es codigo: va versionado y se aplica solo en los dos.
--
-- Los MeshParts si son datos del place (ServerStorage.WeaponMeshes, igual que WorldProps). Generados con IA,
-- asi que no hay lio de licencias como con la Toolbox.
-- El QUE mesh y QUE agarre le toca a cada arma vive en WeaponVisuals, porque GameManager necesita lo mismo
-- para las evoluciones.

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local WeaponVisuals = require(ServerScriptService:WaitForChild("WeaponVisuals"))

local plantillas = ServerStorage:FindFirstChild("WeaponTemplates")
if not plantillas then
	warn("[WeaponSkins] no hay WeaponTemplates; nada que vestir")
	return
end

-- Armas de ANTES del pivot a fantasia (22-jun). El juego era un shooter de olas y estas eran sus armas; en un
-- survivors-like de fantasia un lanzacohetes no pinta nada. Se borran las plantillas para que no salgan por
-- error en ningun listado ni se le den a nadie.
-- OJO: solo se borra la PLANTILLA. Sus entradas en WeaponData se dejan (borrarlas es un cambio de datos que
-- podria romper el perfil de alguien que las tuviera compradas), y el juego nunca las ofrece.
local LEGACY = { "Pistol", "Shotgun", "SMG", "Sniper", "Rocket Launcher" }
local borradas = {}
for _, nombre in ipairs(LEGACY) do
	local t = plantillas:FindFirstChild(nombre)
	if t then t:Destroy(); borradas[#borradas + 1] = nombre end
end

local puestas, sinMesh = {}, {}
for _, tool in ipairs(plantillas:GetChildren()) do
	if tool:IsA("Tool") then
		-- El Handle de la plantilla sigue siendo la caja original, asi que hay que SUSTITUIRLO por un MeshPart
		-- (aqui si se puede: la plantilla no esta equipada por nadie). Una vez puesto, las evoluciones ya solo
		-- tienen que hacer ApplyMesh encima, sin tocar la instancia.
		local mesh = ServerStorage.WeaponMeshes:FindFirstChild(tool.Name)
		if mesh then
			local viejo = tool:FindFirstChild("Handle")
			local nuevo = mesh:Clone()
			nuevo.Name = "Handle" -- OBLIGATORIO: un Tool con RequiresHandle busca un hijo con ese nombre exacto
			nuevo.Anchored = false
			nuevo.CanCollide = false
			nuevo.CanQuery = false
			nuevo.CanTouch = false
			nuevo.CastShadow = false
			nuevo.Massless = true -- si pesa, un arma de 4 studs frena y tambalea al personaje

			-- El MUZZLE es de donde salen los proyectiles. Va en la PUNTA del mesh, no en su centro: si se
			-- queda en el centro, las balas nacen dentro del personaje.
			local muzzle = Instance.new("Attachment")
			muzzle.Name = "Muzzle"
			muzzle.Position = Vector3.new(0, nuevo.Size.Y / 2, 0)
			muzzle.Parent = nuevo

			-- Se copia lo demas que colgara del Handle viejo (luces, sonidos, attachments de efectos) para no
			-- perder nada que otro sistema pueda estar buscando por nombre.
			if viejo then
				for _, hijo in ipairs(viejo:GetChildren()) do
					if hijo.Name ~= "Muzzle" then hijo:Clone().Parent = nuevo end
				end
				viejo:Destroy()
			end
			nuevo.Parent = tool
			WeaponVisuals.aplicar(tool, tool.Name) -- deja el agarre puesto
			puestas[#puestas + 1] = tool.Name
		else
			sinMesh[#sinMesh + 1] = tool.Name
		end
	end
end

print(("[WeaponSkins] vestidas: %s%s%s"):format(
	#puestas > 0 and table.concat(puestas, ", ") or "(ninguna)",
	#sinMesh > 0 and ("  |  sin mesh: " .. table.concat(sinMesh, ", ")) or "",
	#borradas > 0 and ("  |  legacy borradas: " .. table.concat(borradas, ", ")) or ""))
