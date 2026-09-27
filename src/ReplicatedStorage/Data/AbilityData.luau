-- AbilityData (ModuleScript) · S2 - habilidades ACTIVAS (Dash + Nova). Universales (v1, iguales
-- para todas las clases). Compartido cliente/servidor: el cliente lee cooldown/tecla para el HUD,
-- el servidor valida cooldown + aplica el efecto.
local AbilityData = {}

AbilityData.Dash = {
	id = "dash", nombre = "Dash",
	cooldown = 6, distancia = 16, duracion = 0.18, iframes = 0.35,
	tecla = Enum.KeyCode.Space, color = Color3.fromRGB(120, 230, 255),
}
AbilityData.Nova = {
	id = "nova", nombre = "Nova",
	cooldown = 15, radio = 22, danoBase = 60,
	tecla = Enum.KeyCode.Q, color = Color3.fromRGB(130, 170, 255),
}
AbilityData.Lista = { AbilityData.Dash, AbilityData.Nova }

function AbilityData.porId(id)
	for _, a in ipairs(AbilityData.Lista) do if a.id == id then return a end end
end

return AbilityData
