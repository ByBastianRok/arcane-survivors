-- CameraClient (LocalScript) · S1 survivors - camara CENITAL/alejada que sigue al jugador.
-- En partida: camara Scriptable fija en angulo alto encima/detras del jugador (para ver la horda).
-- En el lobby: la camara normal. El movimiento sigue siendo relativo a la camara (mover = pantalla).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local OFFSET = Vector3.new(0, 48, 34) -- arriba + algo atras (angulo alto, alejada para ver la horda)
local activo = false

local function seguir()
	local cam = workspace.CurrentCamera
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not cam then return end
	-- muerto: NO congelar la camara en el sitio de la muerte; volver a la normal
	if not hrp or (hum and hum.Health <= 0) then
		if cam.CameraType ~= Enum.CameraType.Custom then cam.CameraType = Enum.CameraType.Custom end
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	local objetivo = hrp.Position
	cam.CFrame = CFrame.lookAt(objetivo + OFFSET, objetivo + Vector3.new(0, 2, 0))
end

RunService:BindToRenderStep("SurvivorsCam", Enum.RenderPriority.Camera.Value + 1, function()
	if activo then seguir() end
end)

local function gate()
	activo = player:GetAttribute("InMatch") == true
	if not activo then
		local cam = workspace.CurrentCamera
		if cam then cam.CameraType = Enum.CameraType.Custom end -- vuelve a la camara normal en el lobby
	end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()
