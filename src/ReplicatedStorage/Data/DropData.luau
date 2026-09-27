-- DropData (ModuleScript) · FASE 5B - tipos de objetos que sueltan los enemigos.
-- SOLO datos visuales/meta (la logica vive en Drops, servidor). Anadir un drop = anadir fila.
--   categoria: "instant" (efecto inmediato) | "buff" (power-up temporal con 'dur' segundos)
--   forma: "Ball" | "Block" | "Cylinder"   ·   peso: probabilidad relativa de que toque ese
--   nombre: TEXTO que VE el jugador (en ingles)
local DropData = {}

DropData.ChanceBase = 0.07 -- probabilidad base de que un enemigo suelte ALGO. Con solo heart+rapid, ~6% sueltan
-- VIDA (el heart absorbe casi toda la probabilidad). Drops escala esto a la baja en rondas altas.
DropData.VidaEnSuelo = 18  -- segundos que el objeto espera en el suelo antes de desaparecer

-- Solo VIDA + RAPID FIRE (22-jul, Bastian): FUERA nuke(Bomb) / x2(DAMAGE x2) / invencible(INVINCIBLE) / dinero(Coins).
-- Eran power-ups arcade que rompian el ritmo del survivors. Ahora el drop es limpio y se IMANTA hacia ti (ver Drops).
DropData.Tipos = {
	{ id = "heart",  nombre = "Health",     color = Color3.fromRGB(255, 70, 90),  forma = "Ball",  peso = 48, categoria = "instant" }, -- ~6% de enemigos: cura 25% de vida max
	{ id = "rapid",  nombre = "RAPID FIRE", color = Color3.fromRGB(120, 200, 255), forma = "Block", peso = 6,  categoria = "buff", dur = 8 }, -- unico buff que queda (el mas inofensivo); peso 1->6 al ser 1 de 2
}

local porId = {}
for _, d in ipairs(DropData.Tipos) do porId[d.id] = d end
function DropData.porId(id) return porId[id] end

return DropData
