-- MobileControlsClient (LocalScript) · FASE 8 - controles TÁCTILES (twin-stick).
-- Movimiento = joystick IZQUIERDO por defecto de Roblox. Apuntado = joystick DERECHO propio:
-- arrastras para apuntar y, mientras mantienes, disparas a la cadencia del arma. + boton recarga.
-- Solo se activa en dispositivos tactiles "puros" (movil/tablet). En PC no hace nada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local esMovil = UserInputService.TouchEnabled and not UserInputService.MouseEnabled and not UserInputService.KeyboardEnabled
if not esMovil then return end

local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireWeapon = remotes:WaitForChild("FireWeapon")
local reloadEvent = remotes:WaitForChild("Reload")
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("WeaponData"))
local CameraShake = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CameraShake"))
local SoundManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundManager"))

local gui = Instance.new("ScreenGui")
gui.Name = "MobileControls"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Enabled = false
gui.Parent = playerGui

-- Joystick de apuntado (derecha): base + knob, ocultos hasta tocar.
local RADIO = 60
local base = Instance.new("Frame")
base.Name = "AimBase"
base.Size = UDim2.fromOffset(RADIO * 2, RADIO * 2)
base.AnchorPoint = Vector2.new(0.5, 0.5)
base.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
base.BackgroundTransparency = 0.5
base.Visible = false
base.Parent = gui
local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = base
local bs = Instance.new("UIStroke"); bs.Thickness = 2; bs.Color = Color3.fromRGB(120, 200, 255); bs.Transparency = 0.3; bs.Parent = base
local knob = Instance.new("Frame")
knob.Name = "Knob"
knob.Size = UDim2.fromOffset(48, 48)
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.fromScale(0.5, 0.5)
knob.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
knob.BackgroundTransparency = 0.15
knob.Parent = base
local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(1, 0); kc.Parent = knob

-- Boton de recarga (abajo derecha).
local reloadBtn = Instance.new("TextButton")
reloadBtn.Name = "ReloadBtn"
reloadBtn.Size = UDim2.fromOffset(96, 44)
reloadBtn.AnchorPoint = Vector2.new(1, 1)
reloadBtn.Position = UDim2.new(1, -22, 1, -170)
reloadBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
reloadBtn.BackgroundTransparency = 0.2
reloadBtn.Text = "RELOAD"
reloadBtn.Font = Enum.Font.GothamBold
reloadBtn.TextScaled = true
reloadBtn.TextColor3 = Color3.fromRGB(255, 220, 120)
reloadBtn.Parent = gui
local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 12); rc.Parent = reloadBtn
local rp = Instance.new("UIPadding"); rp.PaddingTop = UDim.new(0, 10); rp.PaddingBottom = UDim.new(0, 10); rp.Parent = reloadBtn
reloadBtn.MouseButton1Click:Connect(function() reloadEvent:FireServer(); SoundManager.play("reload") end)

-- ===== Logica del joystick de apuntado =====
local aimTouch = nil       -- InputObject del dedo que apunta
local aimDir = Vector2.zero -- direccion normalizada (x derecha, y abajo)
local firing = false
local ultimoEnvio = 0

local function armaEquipada()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	return tool and WeaponData[tool.Name] or nil
end

-- Convierte la direccion 2D de pantalla a un punto del mundo (relativo a la camara) y dispara.
local function dispararHacia(dir2d)
	if true then return end -- S1 survivors: disparo AUTOMATICO (servidor); el joystick de apuntar queda en hiatus
	-- OJO: todo lo que hay debajo del `if true then return end` de arriba es CODIGO MUERTO desde el pivot a
	-- auto-disparo. Cuando unifique MenuOpen -> MenuAbierto di a entender que esto arreglaba el disparo en movil
	-- con menus abiertos; era falso, aqui no se ejecuta nada. El unico lector REAL de MenuAbierto es LobbyClient
	-- (ocultar el PLAY). Se deja el nombre correcto por si algun dia se recupera el apuntado manual.
	if player:GetAttribute("ChoosingPower") or player:GetAttribute("MenuAbierto") then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local camCF = workspace.CurrentCamera.CFrame
	local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	if forward.Magnitude < 0.01 then return end
	forward = forward.Unit
	local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
	-- en pantalla, arriba (y negativo) = alejar de la camara = forward
	local worldDir = right * dir2d.X + forward * (-dir2d.Y)
	if worldDir.Magnitude < 0.01 then return end
	worldDir = worldDir.Unit
	ultimoEnvio = os.clock()
	fireWeapon:FireServer(hrp.Position + worldDir * 80)
	CameraShake.shake(0.08, 0.12)
	SoundManager.play("shoot")
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if not gui.Enabled then return end
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	if gpe then return end -- toque sobre un boton (recarga, hotbar, SHOP...) -> ignorar
	local screen = workspace.CurrentCamera.ViewportSize
	if input.Position.X < screen.X * 0.5 then return end -- mitad izquierda = mover
	if aimTouch then return end
	aimTouch = input
	base.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
	base.Visible = true
	knob.Position = UDim2.fromScale(0.5, 0.5)
	aimDir = Vector2.zero
	firing = true
end)

UserInputService.InputChanged:Connect(function(input)
	if input ~= aimTouch then return end
	local centro = base.AbsolutePosition + base.AbsoluteSize / 2
	local delta = Vector2.new(input.Position.X - centro.X, input.Position.Y - centro.Y)
	local dist = math.min(delta.Magnitude, RADIO)
	local dir = (delta.Magnitude > 0) and delta.Unit or Vector2.zero
	knob.Position = UDim2.fromOffset(RADIO + dir.X * dist, RADIO + dir.Y * dist)
	aimDir = dir * (dist / RADIO)
end)

UserInputService.InputEnded:Connect(function(input)
	if input ~= aimTouch then return end
	aimTouch = nil
	firing = false
	aimDir = Vector2.zero
	base.Visible = false
end)

-- Mientras mantienes el joystick apuntando, dispara a la cadencia del arma (el servidor la valida).
RunService.Heartbeat:Connect(function()
	if not (gui.Enabled and firing and aimDir.Magnitude > 0.35) then return end
	local arma = armaEquipada()
	if not arma then return end
	if os.clock() - ultimoEnvio >= (arma.Cadencia or 0.2) then
		dispararHacia(aimDir)
	end
end)

-- Solo en partida.
local function gate()
	gui.Enabled = player:GetAttribute("InMatch") == true
	if not gui.Enabled then base.Visible = false; aimTouch = nil; firing = false end
end
player:GetAttributeChangedSignal("InMatch"):Connect(gate)
gate()
