-- CameraShake (ModuleScript, ReplicatedStorage.Modules) · FASE 11 (juice) - sacude la camara.
-- Cualquier script CLIENTE puede pedir un shake: CameraShake.shake(intensidad, duracion).
-- Se aplica DESPUES de la camara (BindToRenderStep prioridad Camera+1) para que no lo pise.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CameraShake = {}
local activos = {}

function CameraShake.shake(intensidad, duracion)
	if not intensidad or not duracion or intensidad <= 0 or duracion <= 0 then return end
	-- Ajuste del jugador (accesibilidad: hay gente a la que el shake le marea, sobre todo en MOVIL).
	local p = Players.LocalPlayer
	if p and p:GetAttribute("SettingCameraShake") == false then return end
	table.insert(activos, { intensidad = intensidad, duracion = duracion, restante = duracion })
end

if RunService:IsClient() then
	RunService:BindToRenderStep("CameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if #activos == 0 then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local off = Vector3.zero
		local roll = 0
		for i = #activos, 1, -1 do
			local s = activos[i]
			s.restante -= dt
			if s.restante <= 0 then
				table.remove(activos, i)
			else
				local mag = s.intensidad * (s.restante / s.duracion)
				off += Vector3.new((math.random() - 0.5) * 2 * mag, (math.random() - 0.5) * 2 * mag, 0)
				roll += (math.random() - 0.5) * 2 * mag
			end
		end
		cam.CFrame = cam.CFrame * CFrame.new(off) * CFrame.Angles(0, 0, math.rad(roll))
	end)
end

return CameraShake
