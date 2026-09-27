-- SoundManager (ModuleScript, ReplicatedStorage.Modules) · FASE 11 - reproduce SFX (cliente).
-- SoundManager.play(nombre, pos?) -> 2D si no hay pos (UI/propio), 3D en el mundo si hay pos.
-- Respeta el ajuste de volumen SFX (SettingSfxVol). La musica la lleva MusicClient aparte.
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local SoundData = require(script.Parent:WaitForChild("SoundData"))

local SoundManager = {}

-- Sju (pase de sonido): anti-METRALLETA. Sin esto, cuando muere media horda de golpe se lanzan 20 copias del
-- MISMO sample a la vez: se superponen, SUMAN volumen y saturan (es lo que se percibe como "raya el oido").
-- 'minGap' = espera minima entre dos disparos del mismo sonido · 'maxVoces' = tope de copias simultaneas.
local ultimaVez = {}    -- [nombre] = os.clock() de la ultima reproduccion aceptada
local vocesActivas = {} -- [nombre] = cuantas copias suenan AHORA

local function sfxVol()
	local p = Players.LocalPlayer
	local v = p and p:GetAttribute("SettingSfxVol")
	return (v ~= nil) and (v / 100) or 0.8
end

function SoundManager.play(nombre, pos)
	local d = SoundData[nombre]
	if not d then return end
	local ahora = os.clock()
	if d.minGap and ultimaVez[nombre] and (ahora - ultimaVez[nombre]) < d.minGap then return end
	if d.maxVoces and (vocesActivas[nombre] or 0) >= d.maxVoces then return end
	ultimaVez[nombre] = ahora
	vocesActivas[nombre] = (vocesActivas[nombre] or 0) + 1
	local s = Instance.new("Sound")
	s.SoundId = d.id
	s.Volume = (d.volume or 0.5) * sfxVol()
	if d.pitch then s.PlaybackSpeed = 1 + (math.random() - 0.5) * 2 * d.pitch end
	local cont
	if pos then
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.Transparency = 1
		p.Size = Vector3.new(0.4, 0.4, 0.4); p.Position = pos; p.Parent = workspace
		s.RollOffMaxDistance = 130
		s.Parent = p
		cont = p
	else
		s.Parent = SoundService
		cont = s
	end
	s:Play()
	-- UN SOLO camino de limpieza: si el contador se soltara solo en Ended y el Debris destruyera por su cuenta
	-- (p.ej. un sonido que no llega a cargar), 'vocesActivas' se quedaria alto PARA SIEMPRE y ese sonido dejaria
	-- de oirse el resto de la partida.
	local liberado = false
	local function liberar()
		if liberado then return end
		liberado = true
		vocesActivas[nombre] = math.max(0, (vocesActivas[nombre] or 1) - 1)
		if cont and cont.Parent then cont:Destroy() end
	end
	s.Ended:Once(liberar)
	task.delay(6, liberar) -- backup por si el sonido no carga
	return s
end

return SoundManager
