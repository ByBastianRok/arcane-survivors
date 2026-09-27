-- MusicClient (LocalScript) · L - musica de fondo por CAPAS con crossfade (fundido 2.2s):
--   · LOBBY   -> pool tranquilo (Celtic), elige una al volver al hub
--   · COMBATE -> pool epico, una pista aleatoria por PARTIDA (sin repetir la anterior)
--   · JEFE    -> pool intenso, entra al aparecer el jefe y al morir vuelve el combate (misma pista)
-- Estado = InMatch (lobby/partida) + BossHealth (jefe vivo). Respeta el ajuste SettingMusicVol.
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundData"))
local player = Players.LocalPlayer
local bossHealth = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BossHealth")

local function nuevo(nombre)
	local s = Instance.new("Sound")
	s.Name = nombre; s.Looped = true; s.Volume = 0; s.Parent = SoundService
	return s
end
local lobby, combat, boss = nuevo("MusicLobby"), nuevo("MusicCombat"), nuevo("MusicBoss")

local function musicVol()
	local v = player:GetAttribute("SettingMusicVol")
	return (v ~= nil) and (v / 100) or 0.7
end
local function fade(snd, target) TweenService:Create(snd, TweenInfo.new(2.2), { Volume = target }):Play() end
local function volDe(pool) return (pool.volume or 0.3) * musicVol() end

-- elige un id del pool DISTINTO al anterior (ref.v guarda el ultimo elegido, para no repetir seguido)
local function elegir(pool, ref)
	local ids = pool.ids or { pool.id }
	local id = ids[1]
	if #ids > 1 then repeat id = ids[math.random(#ids)] until id ~= ref.v end
	ref.v = id
	return id
end
local ultLobby, ultCombat, ultBoss = {}, {}, {}
local bossActivo = false

-- crossfade de volumenes segun el estado actual (tambien lo usa el cambio de SettingMusicVol, sin tocar pistas)
local function aplicar()
	local inMatch = player:GetAttribute("InMatch") == true
	if not inMatch then
		fade(combat, 0); fade(boss, 0); fade(lobby, volDe(SoundData.musicLobby))
	elseif bossActivo then
		fade(lobby, 0); fade(combat, 0); fade(boss, volDe(SoundData.musicBoss))
	else
		fade(lobby, 0); fade(boss, 0); fade(combat, volDe(SoundData.musicCombat))
	end
end

local function pista(snd, pool, ref)
	snd.SoundId = elegir(pool, ref)
	if not snd.IsPlaying then snd:Play() end
end

-- InMatch: al entrar a partida -> nueva pista epica; al volver al hub -> nueva ambientacion de lobby.
local function onInMatch()
	if player:GetAttribute("InMatch") == true then
		pista(combat, SoundData.musicCombat, ultCombat)
	else
		bossActivo = false
		pista(lobby, SoundData.musicLobby, ultLobby)
	end
	aplicar()
end

-- Jefe: BossHealth manda {current,max,...} mientras vive y {dead=true} al morir. Al APARECER, pista de jefe;
-- al morir, volvemos al combate (que sigue reproduciendose por debajo, solo sube su volumen).
bossHealth.OnClientEvent:Connect(function(info)
	local activo = (info and info.current and info.current > 0) and true or false
	if activo == bossActivo then return end
	bossActivo = activo
	if activo then pista(boss, SoundData.musicBoss, ultBoss) end
	aplicar()
end)

player:GetAttributeChangedSignal("InMatch"):Connect(onInMatch)
player:GetAttributeChangedSignal("SettingMusicVol"):Connect(aplicar)
task.defer(onInMatch)
