-- Combat (ModuleScript del SERVIDOR) - DANO unificado a un enemigo.
-- UNA sola fuente de la logica de golpe (crit + flash + numero flotante + lifesteal + elementos),
-- usada por WeaponServer (balas/tajo/explosion) y AbilityServer (nova). Cambiar el balance = AQUI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffects = require(script.Parent:WaitForChild("StatusEffects"))
local damageNumber = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageNumber")

local Combat = {}
Combat.danoAcum = {} -- Sco: dano acumulado por jugador esta run (medidor de dano co-op; GameManager lo sincroniza a atributo)
-- [Humanoid del enemigo] = jugador que le dio el ULTIMO golpe. Sirve para ATRIBUIR el kill (la XP que ese kill
-- aporta al pozo se multiplica por el xpMult de QUIEN mata: asi Scholar solo cuenta para quien lo eligio, como
-- cualquier otro talento). Claves DEBILES: los enemigos muertos se recolectan solos, no acumulan memoria.
Combat.ultimoAtacante = setmetatable({}, { __mode = "k" })
local curadoSeg = {} -- Fix A: curacion por lifesteal ESTE segundo, por jugador (cap 10% vida max/s -> anti-inmortalidad por cleave)

-- Flash blanco breve al golpear (feedback de impacto). Lo hace el servidor -> lo ven todos.
function Combat.flash(modelo)
	if not modelo then return end
	-- THROTTLE. Sin esto flash() se ejecutaba ENTERO en cada impacto aunque el modelo ya estuviera en flash, y
	-- con cadencia alta (multishot, perforacion, varios jugadores) el bicho pasaba la mayor parte del tiempo
	-- BLANCO Y SIN TEXTURA: el jefe se convertia en un bulto blanco durante toda la pelea, justo el modelo que
	-- acabamos de currarnos. Y ademas pagaba por golpe una reescritura de Size y TextureID del MeshPart, que
	-- obliga a re-escalar la malla y a re-bindear la textura, replicado a todos los clientes.
	if modelo:GetAttribute("__flash") then return end
	modelo:SetAttribute("__flash", true)
	for _, p in ipairs(modelo:GetChildren()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("__col") == nil then p:SetAttribute("__col", p.Color) end
			p.Color = Color3.fromRGB(255, 255, 255)
			-- Sju: en un MeshPart CON TEXTURA, tintar de blanco NO se ve (la textura manda; probado en Studio:
			-- ni Color blanco ni Neon cambian nada). Hay que quitarle la textura ese instante para que el flash
			-- de impacto se lea igual que en los enemigos hechos de partes. La textura ya esta cacheada, asi que
			-- restaurarla no vuelve a descargar nada.
			if p:IsA("MeshPart") and p.TextureID ~= "" and p:GetAttribute("__tex") == nil then
				p:SetAttribute("__tex", p.TextureID)
				p.TextureID = ""
			end
		end
	end
	-- POP de impacto: un respingo de tamano se nota MAS que alargar el color, y sin blanquear la horda entera.
	-- Solo sobre "Visual" (el mesh): la raiz es el HITBOX, escalarla cambiaria el area de golpeo. Sin tween a
	-- proposito -> dos impactos seguidos no dejan dos tweens peleandose por la misma propiedad.
	local visual = modelo:FindFirstChild("Visual")
	if visual and visual:IsA("BasePart") then
		if visual:GetAttribute("__tam") == nil then visual:SetAttribute("__tam", visual.Size) end
		visual.Size = visual:GetAttribute("__tam") * 1.12
	end
	task.delay(0.13, function() -- 0.06 se quedaba corto; 0.5 dejaria a los bichos blancos permanentemente
		for _, p in ipairs(modelo:GetChildren()) do
			if p:IsA("BasePart") and p:GetAttribute("__col") ~= nil then
				p.Color = p:GetAttribute("__col")
				local tex = p:GetAttribute("__tex")
				if tex then p.TextureID = tex; p:SetAttribute("__tex", nil) end
			end
		end
		if visual and visual.Parent and visual:GetAttribute("__tam") then
			visual.Size = visual:GetAttribute("__tam")
		end
		if modelo.Parent then modelo:SetAttribute("__flash", nil) end -- libera el throttle
	end)
end

-- Aplica un golpe a 'modelo' (enemigo): crit, dano, flash, numero, lifesteal (cap 10), elementos.
-- jugador/mods/arma pueden ser nil (p.ej. la explosion: dano plano sin crit/lifesteal/elemento).
-- 'pos' = donde aparece el numero flotante. Devuelve true si fue critico.
function Combat.aplicarGolpe(jugador, modelo, dano, mods, arma, pos, opts)
	if not modelo then return false end
	local hum = modelo:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0) then return false end
	local critico = false
	if not (opts and opts.sinCrit) and mods and mods.critChance > 0 and math.random() < mods.critChance then critico = true end -- opts.sinCrit: el AoE de explosion NO critea (a toda la horda seria brutal)
	if critico then dano = dano * mods.critMult end
	if mods and mods.ejecutarBonus and mods.ejecutarBonus > 1 and hum.MaxHealth > 0 and (hum.Health / hum.MaxHealth) < (mods.ejecutarUmbral or 0.25) then
		dano = dano * mods.ejecutarBonus -- Execute: remata a enemigos con poca vida
	end
	hum:TakeDamage(dano)
	if jugador then
		Combat.danoAcum[jugador] = (Combat.danoAcum[jugador] or 0) + dano -- Sco: medidor de dano co-op
		Combat.ultimoAtacante[hum] = jugador -- para atribuir el KILL a quien remata (XP de Scholar)
	end
	Combat.flash(modelo)
	if not pos then
		local r = modelo:FindFirstChild("HumanoidRootPart") or modelo.PrimaryPart
		pos = r and r.Position
	end
	-- CO-OP: el numero se lo mandamos SOLO a quien pega, no a todo el server. Con FireAllClients, en una party
	-- de 4 con auto-disparo sobre una horda, cada cliente recibia TODOS los golpes de TODOS -> miles de eventos
	-- por minuto de trafico y una sopa de numeros ilegible encima de los enemigos. Si no hay atacante conocido
	-- (dano sin duenio) no se pinta nada: seria ruido para todo el mundo.
	if jugador then
		damageNumber:FireClient(jugador, { pos = pos, amount = math.floor(dano + 0.5), crit = critico })
	end
	-- Robo de vida (carta Vampirism): cura una fraccion del dano hecho (cap 10 por golpe).
	if mods and mods.roboVida and mods.roboVida > 0 and jugador and not (opts and opts.sinLifesteal) then
		local pj = jugador.Character
		local ph = pj and pj:FindFirstChildOfClass("Humanoid")
		if ph and ph.Health > 0 then
			local capFrac = math.min(0.04 + math.max(0, mods.roboVida - 0.04) * 0.5, 0.15) -- cap POR GOLPE crece con el lifesteal: Vampirism(0.04)=4%, Bloodreaver escala 7%->15% (antes 4% plano ahogaba el escalado de la clase)
			local cura = math.min(ph.MaxHealth * capFrac, dano * mods.roboVida)
			local seg = math.floor(os.clock())
			local c = curadoSeg[jugador]
			if not c or c.t ~= seg then c = { t = seg, curado = 0 }; curadoSeg[jugador] = c end
			cura = math.max(0, math.min(cura, ph.MaxHealth * 0.18 - c.curado)) -- + cap 18% vida max POR SEGUNDO (era 10%; subido para que el escalado del Bloodreaver se note; sigue anti-inmortal)
			c.curado += cura
			ph.Health = math.min(ph.MaxHealth, ph.Health + cura)
		end
	end
	-- Elementos: el del arma + el extra de la build (Incendiary/Toxic).
	if arma and arma.Elemento then StatusEffects.aplicar(modelo, arma.Elemento) end
	if mods and mods.elementosExtra then for elem in pairs(mods.elementosExtra) do StatusEffects.aplicar(modelo, elem) end end -- TODOS los elementos de la build (se acumulan)
	return critico
end

function Combat.resetDano() table.clear(Combat.danoAcum); table.clear(curadoSeg); table.clear(Combat.ultimoAtacante) end -- Sco: al empezar cada run

return Combat
