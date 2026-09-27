-- RiftPulseClient (LocalScript) · Sju - PALPITO de las grietas y esquirlas del Endless Rift (aura de nivel final).
-- Las partes con atributo "Palpita" (su valor = fase) laten cambiando su Transparency (= brillo del Neon). Va SOLO
-- en cliente: no replica, cuesta practicamente nada. Se enciende cuando workspace.MundoArte == "endless" y se
-- apaga al salir del Rift. ~22 Hz para que sea suave y barato en movil (Transparency no es una luz dinamica).
local RunService = game:GetService("RunService")

local conexion = nil
local partes = {}

local function apagar()
	if conexion then conexion:Disconnect(); conexion = nil end
	-- devolver el brillo pleno por si se reutilizan las partes
	for _, e in ipairs(partes) do if e.p and e.p.Parent then e.p.Transparency = 0 end end
	partes = {}
end

local function encender()
	apagar()
	local arena = workspace:FindFirstChild("Arena")
	if not arena then return end
	for _, p in ipairs(arena:GetChildren()) do
		local fase = p:GetAttribute("Palpita")
		if fase ~= nil and p:IsA("BasePart") then partes[#partes + 1] = { p = p, fase = fase } end
	end
	if #partes == 0 then return end
	local acum = 0
	conexion = RunService.Heartbeat:Connect(function(dt)
		acum += dt
		if acum < 0.045 then return end -- ~22 Hz
		acum = 0
		local t = os.clock()
		for _, e in ipairs(partes) do
			if e.p.Parent then
				-- late entre ~0.06 (brillo casi pleno) y ~0.56 (apagado a medias)
				e.p.Transparency = 0.06 + 0.5 * (0.5 + 0.5 * math.sin(t * 2.2 + e.fase))
			end
		end
	end)
end

local function refrescar()
	if workspace:GetAttribute("MundoArte") == "endless" then
		task.wait(0.6) -- dar tiempo a que la arena replique al cliente
		if workspace:GetAttribute("MundoArte") == "endless" then encender() end
	else
		apagar()
	end
end

workspace:GetAttributeChangedSignal("MundoArte"):Connect(refrescar)
task.defer(refrescar)
