-- BulletClient (LocalScript) - el cliente del tirador SIMULA la bala (network owner) y va un pelin
-- por delante del servidor, asi que la estela se veia 'seguir' unos studs tras el impacto. Aqui
-- ocultamos la bala LOCALMENTE en cuanto TOCA el cuerpo del enemigo (su propio Touched, igual que
-- el servidor) -> la estela acaba EN el impacto. El DANO lo hace el servidor aparte. Al reusarse
-- la bala (pool) se vuelve a mostrar (Transparency 0 + estela ON + Touched reconectado).
local conns = {} -- Part -> conexion Touched
local prev = {} -- Part -> posicion anterior (chequeo por SEGMENTO, para enemigos pequenos que se tunelean)

-- distancia^2 del punto (px,pz) al segmento [(ax,az),(bx,bz)] en XZ, con SCALARES (sin alocar Vector3 -> sin
-- churn de GC; la auditoria marco este bucle como ~270k Vector3/s en movil). Devuelve al CUADRADO (sin sqrt).
local function distSeg2(ax, az, bx, bz, px, pz)
	local abx, abz = bx - ax, bz - az
	local d = abx * abx + abz * abz
	local t = (d > 0) and math.clamp(((px - ax) * abx + (pz - az) * abz) / d, 0, 1) or 0
	local dx, dz = (ax + abx * t) - px, (az + abz * t) - pz
	return dx * dx + dz * dz
end

local function ocultar(c)
	c.Transparency = 1
	local tr = c:FindFirstChildOfClass("Trail"); if tr then tr.Enabled = false end
end

local function alAnadir(c)
	if not (c:IsA("BasePart") and c.Name == "Bala") then return end
	c.Transparency = 0 -- fresh fire (puede venir del pool ya oculta): mostrar de nuevo
	prev[c] = c.Position -- reinicia el segmento (no usar la posicion vieja del pool)
	local tr = c:FindFirstChildOfClass("Trail"); if tr then tr.Enabled = true end
	if conns[c] then conns[c]:Disconnect() end
	conns[c] = c.Touched:Connect(function(otro)
		if c.Transparency >= 1 then return end
		if not c:GetAttribute("MuereAlTocar") then return end -- la perforante pura no se oculta (sigue de largo)
		local modelo = otro:FindFirstAncestorOfClass("Model")
		if modelo and modelo.Name == "BrainrotEnemy" then
			ocultar(c) -- la estela acaba EN el enemigo, no unos studs de largo
		end
	end)
end

workspace.ChildAdded:Connect(alAnadir)
workspace.ChildRemoved:Connect(function(c)
	if conns[c] then conns[c]:Disconnect(); conns[c] = nil end
	prev[c] = nil
end)
for _, c in ipairs(workspace:GetChildren()) do alAnadir(c) end

-- FALLBACK por distancia (por si el Touched no salta): oculta la bala si entra en el cuerpo del enemigo.
local enemigos = {}
task.spawn(function()
	while true do
		local nuevo = {}
		-- Antes esto era workspace:GetDescendants() 5 VECES POR SEGUNDO. Con el workspace vacio pasaba, pero la
		-- arena por mundo mete ~1500 partes -> ~8750 objetos/segundo en CADA cliente solo para localizar
		-- enemigos. Ahora todos viven en workspace.Enemies y se recorren ~50.
		local carpeta = workspace:FindFirstChild("Enemies")
		for _, m in ipairs(carpeta and carpeta:GetChildren() or {}) do
			if m:IsA("Model") and m.Name == "BrainrotEnemy" then
				local r = m:FindFirstChild("HumanoidRootPart")
				if r then
					local ok, ext = pcall(function() return m:GetExtentsSize() end)
					nuevo[#nuevo + 1] = { hrp = r, radio = ok and math.max(ext.X, ext.Z) * 0.5 or 2 }
				end
			end
		end
		enemigos = nuevo
		task.wait(0.2)
	end
end)
game:GetService("RunService").RenderStepped:Connect(function()
	if not next(conns) then return end
	-- snapshot de posiciones de enemigos UNA sola vez por frame (a escalar): el bucle interno bala x enemigo
	-- ya no lee .Position ni aloca Vector3 en cada iteracion.
	local ex, ez, er, en = {}, {}, {}, 0
	for _, e in ipairs(enemigos) do
		if e.hrp.Parent then
			en += 1
			local p = e.hrp.Position
			ex[en], ez[en], er[en] = p.X, p.Z, e.radio
		end
	end
	if en == 0 then return end
	for c in pairs(conns) do
		if c.Parent and c.Transparency < 1 and c:GetAttribute("MuereAlTocar") then
			local pos = c.Position
			local px, pz = pos.X, pos.Z
			local pp = prev[c] or pos
			local ppx, ppz, rb = pp.X, pp.Z, c.Size.X * 0.5
			for i = 1, en do
				local lim = rb + er[i] + 0.5
				if distSeg2(ppx, ppz, px, pz, ex[i], ez[i]) <= lim * lim then ocultar(c); break end
			end
			prev[c] = pos
		end
	end
end)
