-- StatusEffects (ModuleScript del SERVIDOR) - efectos de estado sobre enemigos.
-- Fuego/Veneno = daño por tiempo (DoT). Hielo = ralentiza. Datos en Config.Elementos.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))

local StatusEffects = {}

local COLORES = {
	Fuego = Color3.fromRGB(255, 110, 30),
	Veneno = Color3.fromRGB(120, 220, 60),
	Hielo = Color3.fromRGB(120, 220, 255),
}

-- Marca visual del efecto (un brillo del color del elemento) sobre el enemigo.
local function resaltar(modelo, elemento, duracion)
	-- REUTILIZAR el Highlight en vez de crear uno por golpe. aplicar() se llama en CADA impacto (una vez por el
	-- elemento del arma y otra por CADA elemento de la build), asi que con una horda se acumulaban cientos de
	-- Highlights vivos a la vez. Roblox solo renderiza ~31 simultaneos y DESCARTA el resto EN SILENCIO, y entre
	-- los descartados caian el Highlight de identidad de ELITE y el aviso rojo del Charger: es decir, el spam de
	-- efectos apagaba justo las dos senales que avisan del peligro.
	local hl = modelo:FindFirstChild("EfectoHL")
	if not hl then
		hl = Instance.new("Highlight")
		hl.Name = "EfectoHL"
		hl.OutlineTransparency = 1
		hl.Parent = modelo
	end
	hl.FillColor = COLORES[elemento] or Color3.new(1, 1, 1)
	hl.FillTransparency = 0.5
	-- se RENUEVA la cuenta atras (como el DoT) en vez de encolar un Debris por impacto
	local fin = os.clock() + duracion
	modelo:SetAttribute("EfectoHLFin", math.max(modelo:GetAttribute("EfectoHLFin") or 0, fin))
	task.delay(duracion + 0.1, function()
		if hl.Parent and os.clock() >= (modelo:GetAttribute("EfectoHLFin") or 0) then hl:Destroy() end
	end)
end

-- DoT escalado: % de la vida MAX del enemigo por tick (escala solo con la dificultad) + minimo plano (enemigos de poca vida).
local PCT_TICK = { Fuego = 0.012, Veneno = 0.010 } -- 1.2%/tick Fuego, 1%/tick Veneno (tick cada 0.5s)

-- Daño por tiempo con refresco: no apila bucles, solo extiende la duración.
local function aplicarDoT(modelo, hum, attr, dps, duracion, pctTick)
	local fin = os.clock() + duracion
	local activo = modelo:GetAttribute(attr)
	modelo:SetAttribute(attr, math.max(activo or 0, fin))
	if activo and activo > os.clock() then return end -- ya hay un bucle corriendo
	task.spawn(function()
		while modelo.Parent and hum.Health > 0 and os.clock() < (modelo:GetAttribute(attr) or 0) do
			hum:TakeDamage(math.max(dps * 0.5, hum.MaxHealth * (pctTick or 0))) -- % de vida MAX (escala) o el minimo plano
			task.wait(0.5)
		end
		modelo:SetAttribute(attr, nil)
	end)
end

-- Aplica un elemento a un enemigo (modelo con Humanoid).
function StatusEffects.aplicar(modelo, elemento)
	local def = Config.Elementos[elemento]
	if not def then return end
	local hum = modelo:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	resaltar(modelo, elemento, def.Duracion)

	if elemento == "Hielo" then
		-- El ralentizado NO puede vivir solo en WalkSpeed: los bucles de IA de Enemy (cada 0.2s) y Boss lo
		-- REESCRIBEN desde def.Velocidad, asi que el slow se borraba casi al instante y Frostbite / el congelar
		-- del Storm Bow no hacian practicamente NADA. Lo publicamos como MULTIPLICADOR en el modelo y son esos
		-- bucles los que lo aplican (ellos son los duenos de WalkSpeed).
		modelo:SetAttribute("SlowMult", def.Ralentizar)
		if modelo:GetAttribute("VelBase") == nil then
			modelo:SetAttribute("VelBase", hum.WalkSpeed)
		end
		local base = modelo:GetAttribute("VelBase")
		hum.WalkSpeed = base * def.Ralentizar -- efecto inmediato (no esperar al siguiente tick del bucle)
		local fin = os.clock() + def.Duracion
		local activo = modelo:GetAttribute("HieloFin")
		modelo:SetAttribute("HieloFin", math.max(activo or 0, fin))
		if activo and activo > os.clock() then return end
		task.spawn(function()
			while modelo.Parent and hum.Health > 0 and os.clock() < (modelo:GetAttribute("HieloFin") or 0) do
				task.wait(0.2)
			end
			modelo:SetAttribute("SlowMult", nil) -- se acabo el frio: los bucles de IA vuelven a velocidad plena
			if modelo.Parent and hum and hum.Health > 0 then
				hum.WalkSpeed = modelo:GetAttribute("VelBase") or base
			end
			modelo:SetAttribute("HieloFin", nil)
		end)
	else
		local attr = (elemento == "Fuego") and "FuegoFin" or "VenenoFin"
		aplicarDoT(modelo, hum, attr, def.DanoPorSegundo, def.Duracion, PCT_TICK[elemento])
	end
end

return StatusEffects
