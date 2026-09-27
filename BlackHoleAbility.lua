--!nocheck
--[[
	=====================================================================
	  SINGULARIDADE - Habilidade de Buraco Negro (Roblox / Luau)
	  Tipo : LocalScript
	  Local: StarterPlayer > StarterPlayerScripts
	=====================================================================
	  Sequencia cinematografica:
	    1. Criacao      - esfera densa se forma na mao, luz diminui, pedras sao atraidas
	    2. Arremesso    - projetil que distorce o espaco, FOV kick
	    3. Contato      - para, silencio, camera lenta, vazio cresce na superficie
	    4. Colapso      - aneis, orbita, espaguetificacao, escuridao progressiva
	    5. Singularidade- congelamento, pulsos, 0.3s de silencio absoluto
	    6. Colapso final- implosao, JANELA COSMICA, 0.2s de vazio, EXPLOSAO REVERSA

	  Ativacao:
	    - Tecla Z / Gamepad ButtonY
	    - Botao mobile automatico (CONFIG.CreateMobileButton)
	    - De qualquer LocalScript/GUI:
	        _G.ActivateBlackHole()
	        game.Players.LocalPlayer:WaitForChild("BlackHoleActivate"):Fire()
	=====================================================================
]]

---------------------------------------------------------------------
-- SERVICOS
---------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
local CONFIG = {
	-- CONTROLE
	Keybind = Enum.KeyCode.Z,
	GamepadButton = Enum.KeyCode.ButtonY,
	CreateMobileButton = true,      -- cria botao touch automatico
	Cooldown = 3,                   -- segundos apos o fim da sequencia

	-- FASE 1 / 2
	ChargeTime = 1.1,               -- tempo de formacao da esfera na mao
	ProjectileSpeed = 150,
	ProjectileSize = 0.9,           -- diametro da esfera (mantenha PEQUENO)
	ProjectileMaxDistance = 320,

	-- BURACO NEGRO
	BlackHoleRadius = 4.5,          -- raio do nucleo apos o colapso
	GravityRadius = 45,             -- alcance da atracao
	GravityStrength = 55,           -- velocidade de sucao
	OrbitStrength = 30,             -- velocidade orbital
	HeavyMassThreshold = 500,       -- acima disso: so um leve arrasto
	MaxAffectedAssemblies = 35,     -- limite de objetos fisicos afetados
	AffectCaster = false,

	-- TIMELINE
	AbilityDuration = 8.5,          -- do impacto ate o fim da explosao
	ImpactDelay = 1.0,              -- tensao antes do colapso
	SingularityPulses = 3,

	-- EXPLOSAO REVERSA
	ExplosionRadius = 60,
	ExplosionForce = 130,
	GroundMarkDuration = 12,

	-- CAMERA
	CameraShake = 1,                -- multiplicador global de tremor (0 desliga)
	CameraLeanIn = 7,               -- quanto a camera se aproxima no colapso
	LaunchFOVBoost = 8,
	ExplosionFOVBoost = 24,

	-- VISUAL
	DarknessIntensity = 1,          -- 0 = sem escurecer, 1.5 = bem escuro
	DiskTilt = 14,
	DiskRoll = 9,
	MuteWorldSounds = true,
	AnimateArm = true,
	Quality = "High",               -- "Low" | "Medium" | "High"

	Colors = {
		Energy     = Color3.fromRGB(130, 70, 255),
		PhotonRing = Color3.fromRGB(255, 228, 200),
		DiskHot    = Color3.fromRGB(255, 222, 175),
		DiskMid    = Color3.fromRGB(255, 120, 80),
		DiskOuter  = Color3.fromRGB(120, 60, 255),
		Shockwave  = Color3.fromRGB(235, 225, 255),
		DarkTint   = Color3.fromRGB(185, 172, 255),
		CosmicTint = Color3.fromRGB(150, 195, 255),
	},
	Textures = {
		Spark = "rbxasset://textures/particles/sparkles_main.dds",
		Smoke = "rbxasset://textures/particles/smoke_main.dds",
	},
}

local QUALITY_PRESETS = {
	Low    = {Particles = 0.35, Streaks = 14, Debris = 6,  ExplosionChunks = 6,  ChargePebbles = 3, RingSegments = 16, DustTrails = false, DistortionPuffs = false},
	Medium = {Particles = 0.65, Streaks = 24, Debris = 10, ExplosionChunks = 10, ChargePebbles = 5, RingSegments = 24, DustTrails = false, DistortionPuffs = true},
	High   = {Particles = 1.0,  Streaks = 36, Debris = 16, ExplosionChunks = 16, ChargePebbles = 7, RingSegments = 32, DustTrails = true,  DistortionPuffs = true},
}
local Q = QUALITY_PRESETS[CONFIG.Quality] or QUALITY_PRESETS.High

---------------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------------
local rng = Random.new()
local function rand(a, b) return rng:NextNumber(a, b) end
local function lerp(a, b, t) return a + (b - a) * t end
local function randomUnit() return rng:NextUnitVector() end
local function getCamera() return Workspace.CurrentCamera end

local ValueFolder = Instance.new("Folder")
ValueFolder.Name = "BlackHoleValues"
ValueFolder.Parent = script

local function newValue(v)
	local n = Instance.new("NumberValue")
	n.Value = v or 0
	n.Parent = ValueFolder
	return n
end

local function tween(obj, time, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local EffectsFolder = Instance.new("Folder")
EffectsFolder.Name = "BlackHoleFX_Local"
EffectsFolder.Parent = Workspace

local function newPart(props)
	local p = Instance.new("Part")
	if props.Shape then p.Shape = props.Shape end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		if k ~= "Parent" and k ~= "Shape" then p[k] = v end
	end
	p.Parent = props.Parent or EffectsFolder
	return p
end

local function setMaterial(part, mat)
	if not pcall(function() part.Material = mat end) or part.Material == Enum.Material.Water then
		part.Material = Enum.Material.Slate
	end
end

local function getSurfaceColor(result)
	if not result or not result.Instance then return Color3.fromRGB(90, 90, 95) end
	if result.Instance == Workspace.Terrain then
		local ok, c = pcall(function() return Workspace.Terrain:GetMaterialColor(result.Material) end)
		return ok and c or Color3.fromRGB(95, 110, 80)
	elseif result.Instance:IsA("BasePart") then
		return result.Instance.Color
	end
	return Color3.fromRGB(90, 90, 95)
end

local function NS(...)
	local a, k = {...}, {}
	for i = 1, #a, 2 do table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1])) end
	return NumberSequence.new(k)
end

local function CS(...)
	local a, k = {...}, {}
	for i = 1, #a, 2 do table.insert(k, ColorSequenceKeypoint.new(a[i], a[i + 1])) end
	return ColorSequence.new(k)
end

-- CFrame cujo UpVector = normal
local function basisFromNormal(pos, normal)
	normal = normal.Unit
	local ref = math.abs(normal.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
	local right = ref:Cross(normal).Unit
	return CFrame.fromMatrix(pos, right, normal)
end

-- CFrame para Part Cylinder com a face achatada apontando para a normal
local function diskCFrame(pos, normal)
	return basisFromNormal(pos, normal) * CFrame.Angles(0, 0, math.pi / 2)
end

local function dirToCamera(pos)
	local cam = getCamera()
	local v = cam and (cam.CFrame.Position - pos) or Vector3.zAxis
	if v.Magnitude < 0.05 then return Vector3.zAxis end
	return v.Unit
end

local function makeRaycastParams(char)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = {char, EffectsFolder}
	p.IgnoreWater = true
	return p
end

---------------------------------------------------------------------
-- MAID (limpeza)
---------------------------------------------------------------------
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({_tasks = {}}, Maid) end
function Maid:Give(t) table.insert(self._tasks, t) return t end
function Maid:Clean()
	for i = #self._tasks, 1, -1 do
		local t = self._tasks[i]
		if typeof(t) == "Instance" then t:Destroy()
		elseif typeof(t) == "RBXScriptConnection" then t:Disconnect()
		elseif type(t) == "function" then pcall(t) end
		self._tasks[i] = nil
	end
end

---------------------------------------------------------------------
-- LOOP DE ATUALIZACAO (com TimeScale para camera lenta / congelamento)
---------------------------------------------------------------------
local TimeScale = 1
local Updaters = {}
local Emitters = setmetatable({}, {__mode = "k"})

local function AddUpdater(fn) -- fn(dt, elapsed) -> true para parar
	local u = {fn = fn, t = 0, alive = true}
	table.insert(Updaters, u)
	return function() u.alive = false end
end

RunService.Heartbeat:Connect(function(rawDt)
	local dt = rawDt * TimeScale
	for i = #Updaters, 1, -1 do
		local u = Updaters[i]
		if not u.alive then
			table.remove(Updaters, i)
		else
			u.t += dt
			local ok, done = pcall(u.fn, dt, u.t)
			if not ok then
				warn("[BlackHole] " .. tostring(done))
				u.alive = false
				table.remove(Updaters, i)
			elseif done then
				u.alive = false
				table.remove(Updaters, i)
			end
		end
	end
end)

local function makeEmitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = CONFIG.Textures.Spark
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in pairs(props) do e[k] = v end
	e.TimeScale = TimeScale
	e.Parent = parent
	Emitters[e] = true
	return e
end

local function setEffectsTimeScale(v)
	TimeScale = math.clamp(v, 0, 1)
	for e in pairs(Emitters) do
		if e.Parent then e.TimeScale = TimeScale end
	end
end

---------------------------------------------------------------------
-- ILUMINACAO / POS-PROCESSAMENTO
---------------------------------------------------------------------
local FX = {
	Darkness = newValue(0),
	Flash = newValue(0),
	Cosmic = newValue(0),
	Blur = newValue(0),
	TimeScale = newValue(1),
}

local CC = Instance.new("ColorCorrectionEffect")
CC.Name = "BlackHole_ColorCorrection"
CC.Parent = Lighting
local BlurFx = Instance.new("BlurEffect")
BlurFx.Name = "BlackHole_Blur"
BlurFx.Size = 0
BlurFx.Parent = Lighting

local baseExposure = Lighting.ExposureCompensation

local function applyLighting()
	local d = FX.Darkness.Value * CONFIG.DarknessIntensity
	local f = FX.Flash.Value
	local c = FX.Cosmic.Value
	CC.Brightness = -0.28 * d + 0.45 * f
	CC.Contrast = 0.35 * d + 0.25 * f + 0.35 * c
	CC.Saturation = -0.55 * d + 0.6 * c - 0.3 * f
	CC.TintColor = Color3.new(1, 1, 1)
		:Lerp(CONFIG.Colors.DarkTint, math.clamp(d * 0.7, 0, 1))
		:Lerp(CONFIG.Colors.CosmicTint, math.clamp(c, 0, 1))
	Lighting.ExposureCompensation = baseExposure - 1.0 * d + 0.5 * f
	BlurFx.Size = FX.Blur.Value
end

for name, v in pairs(FX) do
	if name ~= "TimeScale" then v.Changed:Connect(applyLighting) end
end
FX.TimeScale.Changed:Connect(setEffectsTimeScale)

---------------------------------------------------------------------
-- CAMERA (offset aditivo que nao briga com o script de camera padrao)
---------------------------------------------------------------------
local Cam = {
	FOV = newValue(0),
	Lean = newValue(0),
	Look = newValue(0),
	Smooth = newValue(1),   -- 1 = normal, perto de 0 = camera "pesada"/lenta
	Shake = 0,
	Focus = nil,
}
local lastBaseCF, lastBaseFOV, smoothedCF

RunService:BindToRenderStep("BlackHole_CameraRestore", Enum.RenderPriority.Camera.Value - 1, function()
	local cam = getCamera()
	if cam and lastBaseCF then
		cam.CFrame = lastBaseCF
		cam.FieldOfView = lastBaseFOV
	end
	lastBaseCF = nil
end)

RunService:BindToRenderStep("BlackHole_CameraApply", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = getCamera()
	if not cam then return end
	local idle = Cam.Shake <= 0 and math.abs(Cam.FOV.Value) < 1e-3 and Cam.Lean.Value < 1e-3
		and Cam.Look.Value < 1e-3 and Cam.Smooth.Value >= 0.999
	if idle then smoothedCF = nil return end

	local base, baseFOV = cam.CFrame, cam.FieldOfView
	lastBaseCF, lastBaseFOV = base, baseFOV
	local cf = base

	local focus = Cam.Focus
	if focus and (focus - cf.Position).Magnitude > 2 then
		local look = Cam.Look.Value
		if look > 0 then
			cf = cf:Lerp(CFrame.lookAt(cf.Position, focus), math.clamp(look, 0, 1))
		end
		local lean = Cam.Lean.Value
		if lean > 0 then
			local off = focus - cf.Position
			cf = cf + off.Unit * math.min(lean, off.Magnitude * 0.45)
		end
	end

	local s = Cam.Smooth.Value
	if smoothedCF and s < 0.999 then
		local alpha = 1 - (1 - math.clamp(s, 0.001, 1)) ^ (dt * 60)
		cf = smoothedCF:Lerp(cf, alpha)
	end
	smoothedCF = cf

	if Cam.Shake > 0 then
		local m = Cam.Shake * CONFIG.CameraShake
		local t = os.clock()
		cf = cf * CFrame.new(math.noise(t * 22, 0.31) * m * 0.6, math.noise(t * 22, 7.13) * m * 0.6, 0)
			* CFrame.Angles(math.noise(t * 18, 3.71) * m * 0.035, math.noise(t * 18, 9.27) * m * 0.035, math.noise(t * 14, 5.53) * m * 0.05)
		Cam.Shake *= math.exp(-3.4 * dt)
		if Cam.Shake < 0.01 then Cam.Shake = 0 end
	end

	cam.CFrame = cf
	cam.FieldOfView = math.clamp(baseFOV + Cam.FOV.Value, 10, 120)
end)

local function AddShake(amount)
	Cam.Shake = math.min(Cam.Shake + amount, 4)
end

local function CreateCameraEffect(kind, info)
	info = info or {}
	if info.Focus then Cam.Focus = info.Focus end
	local Sine, Quad, Quart = Enum.EasingStyle.Sine, Enum.EasingStyle.Quad, Enum.EasingStyle.Quart
	local InOut, In, Out = Enum.EasingDirection.InOut, Enum.EasingDirection.In, Enum.EasingDirection.Out

	if kind == "Charge" then
		-- CRIACAO: FOV normal
		tween(Cam.FOV, 0.3, {Value = 0})
	elseif kind == "Launch" then
		-- ARREMESSO: pequeno aumento de FOV
		tween(Cam.FOV, 0.12, {Value = CONFIG.LaunchFOVBoost}, Quad, Out)
		task.delay(0.25, function() tween(Cam.FOV, 0.7, {Value = CONFIG.LaunchFOVBoost * 0.3}, Sine, InOut) end)
		AddShake(0.15)
	elseif kind == "Impact" then
		-- IMPACTO: desaceleracao visual
		tween(Cam.FOV, 0.6, {Value = 0}, Sine, Out)
		tween(Cam.Smooth, 0.15, {Value = 0.12})
		tween(Cam.Look, CONFIG.ImpactDelay, {Value = 0.3}, Sine, InOut)
		AddShake(0.25)
	elseif kind == "Collapse" then
		-- COLAPSO: aproxima lentamente
		local d = info.Duration or 3
		tween(Cam.Lean, d, {Value = CONFIG.CameraLeanIn}, Sine, InOut)
		tween(Cam.Look, d * 0.6, {Value = 0.45}, Sine, InOut)
		tween(Cam.Smooth, 0.8, {Value = 0.25})
		tween(Cam.FOV, d, {Value = -4}, Sine, InOut)
	elseif kind == "Singularity" then
		-- SINGULARIDADE: quase imovel
		tween(Cam.Smooth, 0.15, {Value = 0.04})
	elseif kind == "FinalCollapse" then
		-- COLAPSO FINAL: pequeno shake + "sucao" do FOV
		AddShake(0.7)
		tween(Cam.FOV, 0.3, {Value = -9}, Quad, In)
		tween(Cam.Smooth, 0.2, {Value = 0.5})
	elseif kind == "Explosion" then
		-- EXPLOSAO REVERSA: shake grande + FOV expandido, camera empurrada para tras
		Cam.Smooth.Value = 1
		AddShake(3.2)
		tween(Cam.FOV, 0.09, {Value = CONFIG.ExplosionFOVBoost}, Quad, Out)
		task.delay(0.3, function() tween(Cam.FOV, 2.0, {Value = 0}, Sine, InOut) end)
		tween(Cam.Lean, 0.35, {Value = 0}, Quart, Out)
		tween(Cam.Look, 1.5, {Value = 0}, Sine, Out)
	elseif kind == "Reset" then
		tween(Cam.FOV, 0.8, {Value = 0}, Sine, InOut)
		tween(Cam.Lean, 0.8, {Value = 0}, Sine, InOut)
		tween(Cam.Look, 0.8, {Value = 0}, Sine, InOut)
		tween(Cam.Smooth, 0.5, {Value = 1})
		task.delay(0.9, function() Cam.Focus = nil end)
	end
end

---------------------------------------------------------------------
-- SILENCIO DO MUNDO
---------------------------------------------------------------------
local Silenced = {}
local function SetWorldSilence(on, fadeTime)
	if not CONFIG.MuteWorldSounds then return end
	if on then
		for _, container in ipairs({Workspace, SoundService}) do
			for _, s in ipairs(container:GetDescendants()) do
				if s:IsA("Sound") and s.IsPlaying and not Silenced[s] then
					Silenced[s] = s.Volume
					tween(s, fadeTime, {Volume = s.Volume * 0.1})
				end
			end
		end
	else
		for s, vol in pairs(Silenced) do
			if s.Parent then tween(s, fadeTime, {Volume = vol}) end
		end
		table.clear(Silenced)
	end
end

---------------------------------------------------------------------
-- POSE DO BRACO (sobrescreve a animacao no Stepped)
---------------------------------------------------------------------
local ArmPose = {Motor = nil, Angle = nil, R6 = false}

local function SetArmPose(char, angleDeg)
	if not CONFIG.AnimateArm then return end
	if angleDeg == nil or not char then ArmPose.Angle = nil return end
	local motor, r6 = nil, false
	local upper = char:FindFirstChild("RightUpperArm")
	if upper then
		motor = upper:FindFirstChild("RightShoulder")
	else
		local torso = char:FindFirstChild("Torso")
		motor = torso and torso:FindFirstChild("Right Shoulder")
		r6 = true
	end
	if motor and motor:IsA("Motor6D") then
		ArmPose.Motor, ArmPose.R6, ArmPose.Angle = motor, r6, angleDeg
	end
end

RunService.Stepped:Connect(function()
	local m = ArmPose.Motor
	if m and ArmPose.Angle and m.Parent then
		local a = math.rad(ArmPose.Angle)
		m.Transform = ArmPose.R6 and CFrame.Angles(0, 0, a) or CFrame.Angles(a, 0, 0)
	end
end)

---------------------------------------------------------------------
-- ANEIS SEGMENTADOS (sem malhas externas)
---------------------------------------------------------------------
local function CreateRing(segments, color, material, transparency)
	local ring = {Parts = {}, CFs = {}, N = segments}
	for i = 1, segments do
		ring.Parts[i] = newPart({Name = "RingSeg", Color = color, Material = material, Transparency = transparency, Size = Vector3.one * 0.1})
		ring.CFs[i] = CFrame.new()
	end
	function ring:Set(basis, radius, width, height, transp)
		local n = self.N
		local segLen = 2 * (radius + width * 0.5) * math.tan(math.pi / n) * 1.04 + 0.02
		local size = Vector3.new(math.max(segLen, 0.01), math.max(height, 0.01), math.max(width, 0.01))
		for i = 1, n do
			self.CFs[i] = basis * CFrame.Angles(0, (i / n) * math.pi * 2, 0) * CFrame.new(0, 0, -radius)
			local p = self.Parts[i]
			p.Size = size
			if transp then p.Transparency = transp end
		end
		Workspace:BulkMoveTo(self.Parts, self.CFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	function ring:Destroy()
		for _, p in ipairs(self.Parts) do p:Destroy() end
		table.clear(self.Parts)
	end
	return ring
end

-- o: Basis, R0, R1, W0, W1, H, T0, T1, Time, Color, Material, Easing, Direction
local function SpawnRing(o)
	local ring = CreateRing(o.Segments or Q.RingSegments, o.Color, o.Material or Enum.Material.Neon, o.T0 or 0)
	local style = o.Easing or Enum.EasingStyle.Quart
	local dir = o.Direction or Enum.EasingDirection.Out
	ring:Set(o.Basis, o.R0, o.W0, o.H, o.T0)
	AddUpdater(function(_, t)
		local a = math.clamp(t / o.Time, 0, 1)
		local e = TweenService:GetValue(a, style, dir)
		ring:Set(o.Basis, lerp(o.R0, o.R1, e), lerp(o.W0, o.W1, e), o.H, lerp(o.T0, o.T1, a))
		if a >= 1 then ring:Destroy() return true end
		return false
	end)
end

---------------------------------------------------------------------
-- BURACO NEGRO: DISCO DE ACRECAO
---------------------------------------------------------------------
local function CreateAccretionDisk(bh)
	bh.DiskLayers = {}
	local defs = {
		{Mul = 1.7, Thick = 0.10, Color = CONFIG.Colors.DiskHot,   T = 0.08, Spin = 1.0},
		{Mul = 2.5, Thick = 0.07, Color = CONFIG.Colors.DiskMid,   T = 0.45, Spin = 0.7},
		{Mul = 3.5, Thick = 0.04, Color = CONFIG.Colors.DiskOuter, T = 0.72, Spin = 0.45},
	}
	for _, def in ipairs(defs) do
		local p = newPart({Name = "AccretionLayer", Shape = Enum.PartType.Cylinder, Color = def.Color,
			Material = Enum.Material.Neon, Transparency = def.T, Parent = bh.Model})
		table.insert(bh.DiskLayers, {Part = p, Def = def})
	end

	-- Filamentos com rotacao Kepleriana (interno gira mais rapido que o externo)
	bh.Streaks, bh.StreakParts, bh.StreakCFs = {}, {}, {}
	for i = 1, Q.Streaks do
		local rf = 1.25 + rng:NextNumber() ^ 0.8 * 2.4
		local k = (rf - 1.25) / 2.4
		local color = CONFIG.Colors.DiskHot:Lerp(CONFIG.Colors.DiskMid, math.min(k * 2, 1)):Lerp(CONFIG.Colors.DiskOuter, math.max(k * 2 - 1, 0))
		local baseT = 0.05 + k * 0.5
		local p = newPart({Name = "DiskStreak", Color = color, Material = Enum.Material.Neon, Transparency = baseT, Parent = bh.Model})
		bh.Streaks[i] = {Part = p, RF = rf, Angle = rand(0, math.pi * 2), Omega = (1.25 / rf) ^ 1.5 * 3.2,
			Length = rand(0.25, 0.8), Width = rand(0.035, 0.075), Height = rand(-0.03, 0.03), BaseT = baseT}
		bh.StreakParts[i] = p
		bh.StreakCFs[i] = CFrame.new()
	end
	bh.LastFade = -1
end

---------------------------------------------------------------------
-- BURACO NEGRO: PARTICULAS ORBITAIS (espiral para dentro)
---------------------------------------------------------------------
local function CreateOrbitingParticles(bh)
	-- A esfera de campo gira; como as particulas sao LockedToPart, a trajetoria vira espiral.
	bh.Field = newPart({Name = "GravityField", Shape = Enum.PartType.Ball, Transparency = 1, Parent = bh.Model})
	bh.InflowSpark = makeEmitter(bh.Field, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LockedToPart = true,
		Lifetime = NumberRange.new(0.8),
		LightEmission = 1,
		Color = CS(0, Color3.new(1, 1, 1), 0.6, CONFIG.Colors.DiskHot, 1, CONFIG.Colors.Energy),
		Transparency = NS(0, 1, 0.15, 0.1, 0.85, 0, 1, 1),
	})
	bh.InflowDark = makeEmitter(bh.Field, {
		Texture = CONFIG.Textures.Smoke,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LockedToPart = true,
		Lifetime = NumberRange.new(1.0),
		LightEmission = 0,
		LightInfluence = 0.2,
		Color = CS(0, Color3.fromRGB(10, 5, 20), 1, Color3.fromRGB(40, 15, 80)),
		Transparency = NS(0, 1, 0.3, 0.55, 1, 1),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
	})
	bh.LastSizeR = -1
end

---------------------------------------------------------------------
-- BURACO NEGRO: OBJETO PRINCIPAL (mesmo objeto da mao ate a explosao)
---------------------------------------------------------------------
local function CreateBlackHole(radius, maid)
	local bh = {
		BaseRadius = radius, Radius = radius,
		ScaleValue = newValue(1), PulseValue = newValue(0), DiskFade = newValue(0),
		PosValue = Instance.new("Vector3Value"),
		FieldMul = 7, EmitMul = 1, SpinSpeed = 2.2, SpinMul = 1,
		Spin = 0, FieldSpin = 0, Frozen = false, Hidden = false, Destroyed = false,
	}
	bh.PosValue.Parent = ValueFolder
	maid:Give(bh.ScaleValue); maid:Give(bh.PulseValue); maid:Give(bh.DiskFade); maid:Give(bh.PosValue)

	local model = Instance.new("Model")
	model.Name = "BlackHole"
	model.Parent = EffectsFolder
	maid:Give(model)
	bh.Model = model

	-- Nucleo: neon preto = preto absoluto, ignora iluminacao
	bh.Core = newPart({Name = "Core", Shape = Enum.PartType.Ball, Color = Color3.new(0, 0, 0), Material = Enum.Material.Neon, Parent = model})
	-- Horizonte de eventos: energia escura cintilante
	bh.Horizon = newPart({Name = "Horizon", Shape = Enum.PartType.Ball, Color = CONFIG.Colors.Energy, Material = Enum.Material.ForceField, Parent = model})
	-- Lente gravitacional: vidro refrata o que esta atras
	bh.Lens = newPart({Name = "Lens", Shape = Enum.PartType.Ball, Color = Color3.fromRGB(190, 180, 255), Material = Enum.Material.Glass, Transparency = 0.88, Parent = model})
	-- Anel de fotons: disco atras do nucleo, sempre virado para a camera (so a borda aparece)
	bh.PhotonRing = newPart({Name = "PhotonRing", Shape = Enum.PartType.Cylinder, Color = CONFIG.Colors.PhotonRing, Material = Enum.Material.Neon, Parent = model})

	bh.Light = Instance.new("PointLight")
	bh.Light.Color = CONFIG.Colors.Energy
	bh.Light.Brightness = 1.8
	bh.Light.Shadows = false
	bh.Light.Parent = bh.Core

	-- Rastro escuro sutil + filete de energia
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.3, 0); a0.Parent = bh.Core
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.3, 0); a1.Parent = bh.Core
	bh.TrailDark = Instance.new("Trail")
	bh.TrailDark.Attachment0, bh.TrailDark.Attachment1 = a0, a1
	bh.TrailDark.Lifetime = 0.35
	bh.TrailDark.Color = CS(0, Color3.new(0, 0, 0), 1, Color3.fromRGB(40, 10, 80))
	bh.TrailDark.Transparency = NS(0, 0.35, 1, 1)
	bh.TrailDark.WidthScale = NS(0, 1, 1, 0)
	bh.TrailDark.LightEmission = 0
	bh.TrailDark.LightInfluence = 0
	bh.TrailDark.FaceCamera = true
	bh.TrailDark.Enabled = false
	bh.TrailDark.Parent = bh.Core
	bh.TrailGlow = bh.TrailDark:Clone()
	bh.TrailGlow.Lifetime = 0.18
	bh.TrailGlow.Color = ColorSequence.new(CONFIG.Colors.Energy)
	bh.TrailGlow.Transparency = NS(0, 0.6, 1, 1)
	bh.TrailGlow.WidthScale = NS(0, 0.4, 1, 0)
	bh.TrailGlow.LightEmission = 1
	bh.TrailGlow.Parent = bh.Core

	CreateAccretionDisk(bh)
	CreateOrbitingParticles(bh)

	function bh:Apply()
		local s = math.max(self.ScaleValue.Value, 0.002)
		local pulse = 1 + self.PulseValue.Value
		local r = self.BaseRadius * s
		self.Radius = r
		local core = r * 2 * pulse
		self.Core.Size = Vector3.one * core
		self.Horizon.Size = Vector3.one * (core * 1.07)
		self.Lens.Size = Vector3.one * (r * 3.8)
		self.PhotonRing.Size = Vector3.new(math.max(r * 0.02, 0.01), core * 1.16, core * 1.16)
		for _, L in ipairs(self.DiskLayers) do
			local d = L.Def.Mul * r * 2
			L.Part.Size = Vector3.new(math.max(L.Def.Thick * r * 0.35, 0.005), d, d)
		end
		local fr = r * self.FieldMul
		self.Field.Size = Vector3.one * (fr * 2)
		self.Light.Range = math.clamp(r * 7, 4, 60)
		local sp = fr / 0.8
		self.InflowSpark.Speed = NumberRange.new(sp * 0.9, sp * 1.02)
		self.InflowDark.Speed = NumberRange.new(fr * 0.85, fr * 0.98)
		self.InflowSpark.Rate = 80 * Q.Particles * self.EmitMul
		self.InflowDark.Rate = 18 * Q.Particles * self.EmitMul
		if math.abs(r - self.LastSizeR) > math.abs(self.LastSizeR) * 0.3 then
			self.LastSizeR = r
			local k = math.clamp(r, 0.35, 6)
			self.InflowSpark.Size = NS(0, 0.05 * k, 0.6, 0.09 * k, 1, 0)
			self.InflowDark.Size = NS(0, 0.6 * k, 1, 0)
		end
	end

	function bh:SetTrail(on)
		self.TrailDark.Enabled = on
		self.TrailGlow.Enabled = on
	end

	function bh:SetHidden(h)
		self.Hidden = h
		if not h then return end
		for _, d in ipairs(self.Model:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency = 1
			elseif d:IsA("ParticleEmitter") then d.Enabled = false d:Clear()
			elseif d:IsA("Trail") or d:IsA("Light") then d.Enabled = false end
		end
	end

	function bh:Update(dt)
		self:Apply()
		if self.Hidden then return end
		local pos = self.PosValue.Value
		local toCam = dirToCamera(pos)
		local facing = CFrame.lookAt(pos, pos + toCam)
		local rotTarget = (facing * CFrame.Angles(math.rad(CONFIG.DiskTilt), 0, math.rad(CONFIG.DiskRoll))).Rotation
		self.DiskRot = self.DiskRot and self.DiskRot:Lerp(rotTarget, math.clamp(dt * 3, 0, 1)) or rotTarget

		if not self.Frozen then
			local w = dt * self.SpinSpeed * self.SpinMul
			self.Spin += w
			self.FieldSpin += w * 0.6
		end

		local P = CFrame.new(pos)
		self.Core.CFrame = P
		self.Horizon.CFrame = P * CFrame.Angles(self.Spin * 0.2, self.Spin * 0.35, 0)
		self.Lens.CFrame = P
		self.PhotonRing.CFrame = facing * CFrame.Angles(0, math.pi / 2, 0)

		local diskCF = P * self.DiskRot
		local axisCF = diskCF * CFrame.Angles(0, 0, math.pi / 2)
		for _, L in ipairs(self.DiskLayers) do
			L.Part.CFrame = axisCF * CFrame.Angles(self.Spin * L.Def.Spin, 0, 0)
		end
		self.Field.CFrame = diskCF * CFrame.Angles(0, self.FieldSpin, 0)

		local R, F, N = self.DiskRot.RightVector, self.DiskRot.LookVector, self.DiskRot.UpVector
		local r = self.Radius
		for i, st in ipairs(self.Streaks) do
			if not self.Frozen then st.Angle += dt * self.SpinSpeed * self.SpinMul * st.Omega end
			local c, s = math.cos(st.Angle), math.sin(st.Angle)
			local p = pos + (R * c + F * s) * (st.RF * r) + N * (st.Height * r)
			local tangent = F * c - R * s
			self.StreakCFs[i] = CFrame.lookAt(p, p + tangent, N)
			st.Part.Size = Vector3.new(math.max(st.Width * r, 0.01), math.max(st.Width * r * 0.6, 0.01), math.max(st.Length * st.RF * r * 0.5, 0.02))
		end
		Workspace:BulkMoveTo(self.StreakParts, self.StreakCFs, Enum.BulkMoveMode.FireCFrameChanged)

		local fade = self.DiskFade.Value
		if fade ~= self.LastFade then
			self.LastFade = fade
			for _, L in ipairs(self.DiskLayers) do L.Part.Transparency = lerp(L.Def.T, 1, fade) end
			for _, st in ipairs(self.Streaks) do st.Part.Transparency = lerp(st.BaseT, 1, fade) end
		end
	end

	local stop = AddUpdater(function(dt)
		if bh.Destroyed then return true end
		bh:Update(dt)
		return false
	end)
	maid:Give(function() bh.Destroyed = true stop() end)
	return bh
end

---------------------------------------------------------------------
-- FASE 1: CAMPO GRAVITACIONAL DA MAO
---------------------------------------------------------------------
local function CreateGravityEffect(getPos, char, maid)
	local field = newPart({Name = "ChargeField", Shape = Enum.PartType.Ball, Transparency = 1, Size = Vector3.one * 9})
	maid:Give(field)
	local sp = 4.5 / 0.75
	local sparks = makeEmitter(field, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LockedToPart = true,
		Lifetime = NumberRange.new(0.75),
		Speed = NumberRange.new(sp * 0.95, sp),
		Rate = 55 * Q.Particles,
		LightEmission = 1,
		Size = NS(0, 0.06, 0.7, 0.14, 1, 0),
		Color = CS(0, Color3.new(1, 1, 1), 1, CONFIG.Colors.Energy),
		Transparency = NS(0, 1, 0.2, 0.1, 1, 0.3),
	})
	local wisps = makeEmitter(field, {
		Texture = CONFIG.Textures.Smoke,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		LockedToPart = true,
		Lifetime = NumberRange.new(1),
		Speed = NumberRange.new(4.0, 4.5),
		Rate = 10 * Q.Particles,
		LightEmission = 0,
		LightInfluence = 0.3,
		Size = NS(0, 0.9, 1, 0),
		Color = CS(0, Color3.fromRGB(20, 8, 40), 1, Color3.fromRGB(5, 0, 12)),
		Transparency = NS(0, 1, 0.3, 0.6, 1, 1),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	})

	-- Pedrinhas arrancadas do chao e atraidas para a mao
	local pebbles = {}
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local params = makeRaycastParams(char)
		for _ = 1, Q.ChargePebbles do
			local ang, dist = rand(0, math.pi * 2), rand(3, 9)
			local origin = hrp.Position + Vector3.new(math.cos(ang) * dist, 3, math.sin(ang) * dist)
			local hit = Workspace:Raycast(origin, Vector3.new(0, -14, 0), params)
			if hit then
				local s = rand(0.18, 0.5)
				local p = newPart({Name = "Pebble", Size = Vector3.new(s, s * rand(0.6, 1), s * rand(0.7, 1.2)),
					Color = getSurfaceColor(hit), CFrame = CFrame.new(hit.Position + Vector3.new(0, s * 0.3, 0))})
				setMaterial(p, hit.Material)
				maid:Give(p)
				table.insert(pebbles, {Part = p, Start = p.Position, Delay = rand(0, 0.35), Seed = rand(0, 100), Size = p.Size})
			end
		end
	end

	local stop = AddUpdater(function(_, t)
		local pos = getPos()
		field.CFrame = CFrame.new(pos) * CFrame.Angles(0, t * 5, t * 1.3)
		for _, pb in ipairs(pebbles) do
			local a = math.clamp((t - pb.Delay) / math.max(CONFIG.ChargeTime - pb.Delay, 0.1), 0, 1)
			local lifted = pb.Start + Vector3.new(0, 1.8 * math.sin(math.min(a * 2, 1) * math.pi * 0.5), 0)
			local p = lifted:Lerp(pos, a ^ 3)
			local wob = Vector3.new(math.noise(t * 5, pb.Seed), math.noise(pb.Seed, t * 5), math.noise(t * 5, pb.Seed + 3)) * 0.25 * (1 - a)
			pb.Part.CFrame = CFrame.new(p + wob) * CFrame.Angles(t * 3 + pb.Seed, t * 2.2, t * 1.4)
			if a > 0.75 then pb.Part.Size = pb.Size * math.max(1 - (a - 0.75) / 0.25, 0.02) end
		end
		return false
	end)

	return function()
		stop()
		sparks.Enabled = false
		wisps.Enabled = false
		for _, pb in ipairs(pebbles) do
			if pb.Part.Parent then pb.Part.Transparency = 1 end
		end
	end
end

---------------------------------------------------------------------
-- FISICA
---------------------------------------------------------------------
local function RefreshGravityTargets(center, overlap)
	local parts = Workspace:GetPartBoundsInRadius(center, CONFIG.GravityRadius, overlap)
	local list, seen, models = {}, {}, {}
	for _, p in ipairs(parts) do
		if not p.Anchored then
			local root = p.AssemblyRootPart
			if root and not root.Anchored and not seen[root] then
				seen[root] = true
				if #list < CONFIG.MaxAffectedAssemblies then table.insert(list, root) end
				local m = root.Parent
				if m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then models[m] = root end
			end
		end
	end
	return list, models
end

local function ApplyGravityEffect(center, dt, strength, targets, axis)
	if strength <= 0 or dt <= 0 then return end
	local R = CONFIG.BlackHoleRadius
	local g = Workspace.Gravity
	for _, root in ipairs(targets) do
		if root.Parent and not root.Anchored then
			local off = center - root.Position
			local dist = off.Magnitude
			if dist < CONFIG.GravityRadius and dist > 0.05 then
				local dir = off / dist
				local falloff = 1 - dist / CONFIG.GravityRadius
				local mass = root.AssemblyMass
				local vel = root.AssemblyLinearVelocity
				if mass > CONFIG.HeavyMassThreshold then
					-- objetos pesados: so um leve deslocamento
					root.AssemblyLinearVelocity = vel + dir * 6 * falloff * strength * dt
				else
					local mf = math.clamp(50 / math.max(mass, 1), 0.35, 1)
					local tangent = dir:Cross(axis)
					if tangent.Magnitude < 1e-3 then tangent = dir:Cross(Vector3.xAxis) end
					tangent = tangent.Unit
					local inward = CONFIG.GravityStrength * falloff ^ 0.6
					local orbit = CONFIG.OrbitStrength * falloff ^ 0.5
					if dist < R * 1.3 then inward *= 0.15 orbit *= 0.6 end
					local desired = (dir * inward + tangent * orbit) * strength
					local newVel = vel:Lerp(desired, math.clamp(dt * 2.2 * mf * strength, 0, 1))
					newVel += Vector3.yAxis * g * dt * math.clamp(falloff * 1.4, 0, 1) * mf
					root.AssemblyLinearVelocity = newVel
				end
			end
		end
	end
end

local function UpdateWisps(ctx, models)
	local count = 0
	for _ in pairs(ctx.Wisps) do count += 1 end
	for model, root in pairs(models) do
		if not ctx.Wisps[model] and count < 6 then
			count += 1
			local att = Instance.new("Attachment")
			att.Name = "BH_Wisp"
			att.Parent = root
			local e = makeEmitter(att, {
				Texture = CONFIG.Textures.Smoke,
				EmissionDirection = Enum.NormalId.Front,
				SpreadAngle = Vector2.new(18, 18),
				Speed = NumberRange.new(8, 15),
				Lifetime = NumberRange.new(0.5, 0.8),
				Rate = 22 * Q.Particles,
				Size = NS(0, 1.2, 1, 0),
				Color = CS(0, Color3.fromRGB(30, 12, 60), 1, Color3.fromRGB(0, 0, 0)),
				Transparency = NS(0, 0.5, 1, 1),
				LightEmission = 0.2,
				Rotation = NumberRange.new(0, 360),
			})
			ctx.Maid:Give(att)
			ctx.Wisps[model] = {Att = att, Emitter = e}
		end
	end
end

local function StartGravity(ctx)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {EffectsFolder}
	if not CONFIG.AffectCaster then table.insert(ex, ctx.Char) end
	overlap.FilterDescendantsInstances = ex
	overlap.MaxParts = 400
	ctx.OverlapParams = overlap
	ctx.Wisps = {}

	local targets, refresh = {}, 0
	local stop = AddUpdater(function(dt)
		if ctx.Ended then return true end
		if not ctx.GravityActive then
			for _, w in pairs(ctx.Wisps) do w.Emitter.Enabled = false end
			return false
		end
		refresh -= dt
		if refresh <= 0 then
			refresh = 0.3
			local models
			targets, models = RefreshGravityTargets(ctx.Center, overlap)
			UpdateWisps(ctx, models)
		end
		ApplyGravityEffect(ctx.Center, dt, ctx.GravityStrength.Value, targets, ctx.GroundNormal)
		for _, w in pairs(ctx.Wisps) do
			local parent = w.Att.Parent
			if parent and (parent.Position - ctx.Center).Magnitude > 0.1 then
				w.Att.WorldCFrame = CFrame.lookAt(parent.Position, ctx.Center)
			end
		end
		return false
	end)
	ctx.Maid:Give(stop)
end

---------------------------------------------------------------------
-- DESTROCOS ORBITAIS (pedacos do chao, locais e controlados)
---------------------------------------------------------------------
local function CreateDebrisField(ctx)
	local field = {Chunks = {}, Parts = {}, CFs = {}, Mode = "tremble", Respawns = Q.Debris}
	local R = CONFIG.BlackHoleRadius
	local N = ctx.GroundNormal
	local basis = basisFromNormal(ctx.Center, N)
	local U, V = basis.RightVector, basis.LookVector
	local groundH = (ctx.GroundPos - ctx.Center):Dot(N)
	local outer = CONFIG.GravityRadius * 0.55

	local function reset(c, initial)
		c.Angle = rand(0, math.pi * 2)
		c.Radius = initial and rand(R * 1.6, outer) or rand(outer * 0.75, outer)
		local s = rand(0.35, 1.3)
		c.Height = groundH - s * 0.6
		c.FloatTarget = groundH + rand(0.6, 2.4)
		c.Omega = rand(0.9, 1.5)
		c.Inward = rand(1.6, 3.2)
		c.Spin = randomUnit() * rand(1, 4)
		c.Rot = CFrame.Angles(rand(0, 6.28), rand(0, 6.28), rand(0, 6.28))
		c.Dead = false
		c.BaseSize = Vector3.new(s, s * rand(0.55, 0.95), s * rand(0.7, 1.2))
		c.Part.Size = c.BaseSize
		c.Part.Transparency = 0
		if c.Dust then c.Dust.Enabled = true end
	end

	local function kill(c)
		c.Dead = true
		c.Part.Transparency = 1
		if c.Dust then c.Dust.Enabled = false end
	end

	for i = 1, Q.Debris do
		local p = newPart({Name = "Debris", Color = ctx.GroundColor})
		setMaterial(p, ctx.GroundMaterial)
		ctx.Maid:Give(p)
		local c = {Part = p}
		if Q.DustTrails then
			c.Dust = makeEmitter(p, {
				Texture = CONFIG.Textures.Smoke,
				Color = ColorSequence.new(ctx.GroundColor),
				LightEmission = 0, LightInfluence = 1,
				Size = NS(0, 0.5, 1, 1.4),
				Transparency = NS(0, 0.6, 1, 1),
				Lifetime = NumberRange.new(0.5, 0.9),
				Rate = 7 * Q.Particles,
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(180, 180),
				Rotation = NumberRange.new(0, 360),
			})
		end
		reset(c, true)
		field.Chunks[i] = c
		field.Parts[i] = p
		field.CFs[i] = p.CFrame
	end

	function field:Update(dt)
		local center = ctx.Center
		for i, c in ipairs(self.Chunks) do
			local p = c.Part
			if c.Dead then
				self.CFs[i] = p.CFrame
				continue
			end
			local stretch = 0
			if self.Mode == "tremble" then
				c.Height += (c.FloatTarget - c.Height) * math.min(dt * 1.1, 1)
			elseif self.Mode == "orbit" then
				c.Radius -= dt * c.Inward * (1 + 5 * (R / math.max(c.Radius, 0.1)))
				c.Angle += dt * c.Omega * (outer / math.max(c.Radius, R)) ^ 1.15 * 0.6
				c.Height += (0 - c.Height) * math.min(dt * 0.9, 1)
				if c.Radius < R * 2.4 then stretch = 1 - (c.Radius - R) / (R * 1.4) end
				if c.Radius <= R then
					if self.Respawns > 0 then
						self.Respawns -= 1
						reset(c, false)
						stretch = 0
					else
						kill(c)
					end
				end
			elseif self.Mode == "consume" then
				local k = math.exp(-dt * 10)
				c.Radius *= k
				c.Height *= k
				c.Angle += dt * c.Omega * 6
				stretch = 1
				if c.Radius < 0.6 then kill(c) end
			end

			c.Rot = c.Rot * CFrame.Angles(c.Spin.X * dt, c.Spin.Y * dt, c.Spin.Z * dt)
			local pos = center + (U * math.cos(c.Angle) + V * math.sin(c.Angle)) * c.Radius + N * c.Height
			if self.Mode == "tremble" then pos += randomUnit() * 0.06 end

			if stretch > 0 and (center - pos).Magnitude > 0.05 then
				-- espaguetificacao: estica na direcao do nucleo
				stretch = math.clamp(stretch, 0, 1)
				local s = c.BaseSize
				p.Size = Vector3.new(s.X * (1 - 0.6 * stretch), s.Y * (1 - 0.6 * stretch), s.Z * (1 + 2.5 * stretch))
				self.CFs[i] = CFrame.lookAt(pos, center)
			else
				self.CFs[i] = CFrame.new(pos) * c.Rot
			end
		end
		Workspace:BulkMoveTo(self.Parts, self.CFs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	ctx.Maid:Give(AddUpdater(function(dt)
		if ctx.Ended then return true end
		field:Update(dt)
		return false
	end))
	return field
end

---------------------------------------------------------------------
-- FASE 2: PROJETIL
---------------------------------------------------------------------
local function SpawnDistortionPuff(pos, r)
	local p = newPart({Name = "Distortion", Shape = Enum.PartType.Ball, Material = Enum.Material.Glass,
		Color = Color3.fromRGB(200, 190, 255), Transparency = 0.7, Size = Vector3.one * r * 3, CFrame = CFrame.new(pos)})
	tween(p, 0.4, {Size = Vector3.one * r * 7, Transparency = 1})
	Debris:AddItem(p, 0.45)
end

local function shouldIgnoreHit(inst)
	return inst:IsA("BasePart") and inst.Transparency >= 0.95 and not inst.CanCollide
end

local function FlyProjectile(orb, origin, dir, params)
	local pos, traveled, puffT = origin, 0, 0
	local vel = dir * CONFIG.ProjectileSpeed
	while true do
		local dt = RunService.Heartbeat:Wait()
		local step = vel * dt
		local len = step.Magnitude
		local result = Workspace:Raycast(pos, dir * (len + orb.Radius), params)
		local tries = 0
		while result and tries < 4 and shouldIgnoreHit(result.Instance) do
			params:AddToFilter(result.Instance)
			result = Workspace:Raycast(pos, dir * (len + orb.Radius), params)
			tries += 1
		end
		if result then
			return {Position = result.Position, Normal = result.Normal, Instance = result.Instance, Material = result.Material, Raw = result}
		end
		pos += step
		traveled += len
		orb.PosValue.Value = pos
		if Q.DistortionPuffs then
			puffT += dt
			if puffT >= 0.035 then
				puffT = 0
				SpawnDistortionPuff(pos, orb.Radius)
			end
		end
		if traveled >= CONFIG.ProjectileMaxDistance then
			return {Position = pos, Normal = Vector3.yAxis}
		end
	end
end

local function GetAimPoint(params)
	local cam = getCamera()
	local ray
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local m = UserInputService:GetMouseLocation()
		ray = cam:ViewportPointToRay(m.X, m.Y)
	else
		local vs = cam.ViewportSize
		ray = cam:ViewportPointToRay(vs.X / 2, vs.Y / 2)
	end
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	return hit and hit.Position or (ray.Origin + ray.Direction * 1000)
end

local function getHandTip(char)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if hand then
		return (hand.CFrame * CFrame.new(0, -(hand.Size.Y * 0.5 + 0.75), 0)).Position
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp.CFrame * CFrame.new(1, 0.5, -2)).Position or Vector3.zero
end

local function ResolveGround(ctx, hit)
	local inst = hit.Instance
	local model = inst and inst:FindFirstAncestorOfClass("Model")
	local isChar = model and model:FindFirstChildOfClass("Humanoid") ~= nil
	local groundHit = hit.Raw
	if not inst or isChar then
		local p2 = RaycastParams.new()
		p2.FilterType = Enum.RaycastFilterType.Exclude
		local ex = {ctx.Char, EffectsFolder}
		if isChar then table.insert(ex, model) end
		p2.FilterDescendantsInstances = ex
		p2.IgnoreWater = true
		groundHit = Workspace:Raycast(ctx.Center, Vector3.new(0, -80, 0), p2)
	end
	if groundHit then
		ctx.HasGround = true
		ctx.GroundPos = groundHit.Position
		ctx.GroundNormal = groundHit.Normal
		ctx.GroundColor = getSurfaceColor(groundHit)
		ctx.GroundMaterial = groundHit.Material
	else
		ctx.HasGround = false
		ctx.GroundPos = ctx.Center - Vector3.new(0, CONFIG.BlackHoleRadius * 1.2, 0)
		ctx.GroundNormal = Vector3.yAxis
		ctx.GroundColor = Color3.fromRGB(80, 80, 90)
		ctx.GroundMaterial = Enum.Material.Slate
	end
end

---------------------------------------------------------------------
-- FASE 3: CONTATO
---------------------------------------------------------------------
local function CreateImpact(ctx)
	local bh = ctx.BH
	local T = CONFIG.ImpactDelay

	-- A esfera para completamente. Nada explode.
	bh:SetTrail(false)
	bh.FieldMul = 14
	bh.EmitMul = 0.6
	bh.SpinMul = 0.4

	-- Silencio + camera lenta
	SetWorldSilence(true, 0.25)
	FX.TimeScale.Value = 0.25
	tween(FX.TimeScale, T, {Value = 0.6}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	CreateCameraEffect("Impact", {Focus = ctx.Center})
	tween(FX.Darkness, T, {Value = 0.45}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- Pequeno circulo preto que cresce lentamente na superficie
	local cf = diskCFrame(ctx.HitPos + ctx.Normal * 0.04, ctx.Normal)
	local void = newPart({Name = "ImpactVoid", Shape = Enum.PartType.Cylinder, Color = Color3.new(0, 0, 0),
		Material = Enum.Material.Neon, Size = Vector3.new(0.05, 0.1, 0.1), CFrame = cf})
	local rim = newPart({Name = "ImpactRim", Shape = Enum.PartType.Cylinder, Color = CONFIG.Colors.Energy,
		Material = Enum.Material.Neon, Transparency = 0.3, Size = Vector3.new(0.03, 0.1, 0.1), CFrame = cf * CFrame.new(-0.01, 0, 0)})
	ctx.Maid:Give(void); ctx.Maid:Give(rim)
	ctx.ImpactVoid, ctx.ImpactRim = void, rim
	local d = CONFIG.BlackHoleRadius * 1.4
	tween(void, T * 1.1, {Size = Vector3.new(0.05, d, d)}, Enum.EasingStyle.Sine)
	tween(rim, T * 1.1, {Size = Vector3.new(0.03, d * 1.12, d * 1.12)}, Enum.EasingStyle.Sine)

	-- Objetos proximos tremem e flutuam
	ctx.Debris = CreateDebrisField(ctx)
	ctx.GravityStrength = newValue(0)
	ctx.Maid:Give(ctx.GravityStrength)
	ctx.GravityActive = true
	StartGravity(ctx)
	tween(ctx.GravityStrength, T, {Value = 0.25})

	task.wait(T)
	tween(FX.TimeScale, 0.35, {Value = 1})
end

---------------------------------------------------------------------
-- FASE 4: COLAPSO ESPACIAL
---------------------------------------------------------------------
local function CreateSpatialCollapse(ctx, duration)
	local bh = ctx.BH
	local R = CONFIG.BlackHoleRadius
	local center = ctx.Center

	-- O nucleo cresce e se ergue da superficie
	tween(bh.PosValue, 1.1, {Value = center}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	tween(bh.ScaleValue, 1.5, {Value = R / bh.BaseRadius}, Enum.EasingStyle.Quint)
	bh.FieldMul = 6.5
	bh.EmitMul = 1.4
	bh.SpinMul = 1

	-- 1. Anel preto se expande pela superficie
	SpawnRing({Basis = basisFromNormal(ctx.HitPos + ctx.Normal * 0.08, ctx.Normal), R0 = R * 0.7, R1 = CONFIG.GravityRadius * 0.75,
		W0 = R * 0.8, W1 = 0.2, H = 0.12, T0 = 0, T1 = 1, Time = 1.8, Color = Color3.new(0, 0, 0), Easing = Enum.EasingStyle.Quint})
	-- 2. Segundo anel ao redor
	task.delay(0.3, function()
		SpawnRing({Basis = basisFromNormal(center, dirToCamera(center)), R0 = R * 1.3, R1 = R * 5, W0 = R * 0.25, W1 = 0.05,
			H = 0.1, T0 = 0.2, T1 = 1, Time = 1.4, Color = CONFIG.Colors.Energy})
	end)

	-- 3. Distorcao simulada (forcefield cintilante + vidro refrativo + blur)
	local haze = newPart({Name = "DistortionField", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField,
		Color = CONFIG.Colors.Energy, Transparency = 0.4, Size = Vector3.one * R * 2, CFrame = CFrame.new(center)})
	local lensShell = newPart({Name = "LensShell", Shape = Enum.PartType.Ball, Material = Enum.Material.Glass,
		Color = Color3.fromRGB(205, 195, 255), Transparency = 0.9, Size = Vector3.one * R * 2, CFrame = CFrame.new(center)})
	ctx.Maid:Give(haze); ctx.Maid:Give(lensShell)
	ctx.Haze, ctx.LensShell = haze, lensShell
	tween(haze, 1.8, {Size = Vector3.one * CONFIG.GravityRadius * 1.2}, Enum.EasingStyle.Quint)
	tween(lensShell, 1.5, {Size = Vector3.one * R * 9}, Enum.EasingStyle.Quint)
	ctx.Maid:Give(AddUpdater(function(_, t)
		if ctx.Ended or not haze.Parent then return true end
		haze.CFrame = CFrame.new(center) * CFrame.Angles(t * 0.2, t * 0.5, 0)
		return false
	end))
	tween(FX.Blur, duration, {Value = 2.5})

	-- 8. Ceu e iluminacao progressivamente mais escuros
	tween(FX.Darkness, duration, {Value = 0.9}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- 4/5/6/7. Orbita, sucao, espirais, poeira do chao
	ctx.Debris.Mode = "orbit"
	tween(ctx.GravityStrength, duration * 0.6, {Value = 1})

	-- 10. Disco acelera
	ctx.Maid:Give(AddUpdater(function(_, t)
		bh.SpinMul = lerp(1, 2.2, math.clamp(t / duration, 0, 1))
		return t >= duration
	end))

	CreateCameraEffect("Collapse", {Duration = duration, Focus = center})

	-- Ondulacoes do espaco caindo para dentro
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		if os.clock() - t0 > 0.8 then
			SpawnRing({Basis = basisFromNormal(center, dirToCamera(center)), R0 = CONFIG.GravityRadius * 0.45, R1 = R * 1.05,
				W0 = 0.15, W1 = R * 0.3, H = 0.08, T0 = 0.95, T1 = 0.35, Time = 0.9,
				Color = Color3.fromRGB(70, 25, 150), Easing = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In})
		end
		task.wait(0.55)
	end
end

---------------------------------------------------------------------
-- FASE 5: SINGULARIDADE
---------------------------------------------------------------------
local function CreateSingularity(ctx)
	local bh = ctx.BH
	local R = CONFIG.BlackHoleRadius

	-- Tudo congela por uma fracao de segundo
	CreateCameraEffect("Singularity")
	bh.Frozen = true
	FX.TimeScale.Value = 0
	task.wait(0.18)
	FX.TimeScale.Value = 1
	bh.Frozen = false
	tween(ctx.GravityStrength, 0.3, {Value = 1.25})

	-- Pulsos do nucleo
	for i = 1, CONFIG.SingularityPulses do
		tween(bh.PulseValue, 0.07, {Value = 0.22})
		task.delay(0.07, function() tween(bh.PulseValue, 0.28, {Value = 0}, Enum.EasingStyle.Sine) end)
		SpawnRing({Basis = basisFromNormal(ctx.Center, dirToCamera(ctx.Center)), R0 = R * 1.1, R1 = R * (3.5 + i),
			W0 = 0.6, W1 = 0.05, H = 0.15, T0 = 0.1, T1 = 1, Time = 0.45, Color = CONFIG.Colors.PhotonRing})
		SpawnRing({Basis = basisFromNormal(ctx.GroundPos + ctx.GroundNormal * 0.15, ctx.GroundNormal), R0 = R, R1 = CONFIG.GravityRadius * 0.5,
			W0 = 1.2, W1 = 0.1, H = 0.1, T0 = 0.4, T1 = 1, Time = 0.6, Color = CONFIG.Colors.Energy, Material = Enum.Material.ForceField})
		AddShake(0.35 + i * 0.08)
		FX.Darkness.Value = math.min(1, FX.Darkness.Value + 0.08)
		tween(FX.Darkness, 0.3, {Value = 0.9})
		bh.SpinMul *= 1.55
		task.wait(0.45)
	end

	-- 0.3s: nenhuma explosao, nenhum efeito. So o buraco negro.
	bh.EmitMul = 0
	task.wait(0.3)
end

---------------------------------------------------------------------
-- EFEITO ESPECIAL: JANELA COSMICA (procedural)
---------------------------------------------------------------------
local function CreateCosmicWindow(ctx, duration)
	local center = ctx.Center
	local R = CONFIG.BlackHoleRadius * 1.35
	local model = Instance.new("Model")
	model.Name = "CosmicWindow"
	model.Parent = EffectsFolder
	ctx.Maid:Give(model)

	-- Discos concentricos: o maior fica mais longe, os menores mais perto => tunel de profundidade
	local layers = {
		{r = 1.10, d = 1.00, c = Color3.fromRGB(255, 235, 255)},
		{r = 1.00, d = 0.85, c = Color3.fromRGB(150, 70, 255)},
		{r = 0.86, d = 0.70, c = Color3.fromRGB(70, 20, 170)},
		{r = 0.70, d = 0.55, c = Color3.fromRGB(25, 8, 90)},
		{r = 0.54, d = 0.40, c = Color3.fromRGB(8, 3, 45)},
		{r = 0.36, d = 0.25, c = Color3.fromRGB(2, 1, 18)},
		{r = 0.18, d = 0.10, c = Color3.fromRGB(0, 0, 4)},
	}
	for _, L in ipairs(layers) do
		L.p = newPart({Name = "Depth", Shape = Enum.PartType.Cylinder, Color = L.c, Material = Enum.Material.Neon, Parent = model})
	end

	local holder = newPart({Name = "Stars", Shape = Enum.PartType.Ball, Transparency = 1, Size = Vector3.one * R * 1.4, Parent = model})
	local stars = makeEmitter(holder, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		LockedToPart = true,
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(R * 0.4, R * 1.2),
		Size = NS(0, 0.22, 1, 0.06),
		Color = CS(0, Color3.new(1, 1, 1), 1, Color3.fromRGB(170, 220, 255)),
		LightEmission = 1,
		ZOffset = R,
		Rate = 500 * Q.Particles,
	})
	local nebula = makeEmitter(holder, {
		Texture = CONFIG.Textures.Smoke,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		LockedToPart = true,
		Lifetime = NumberRange.new(0.3, 0.4),
		Speed = NumberRange.new(0.5, 2),
		Size = NS(0, R * 0.35, 1, R * 0.6),
		Color = CS(0, Color3.fromRGB(255, 80, 200), 1, Color3.fromRGB(80, 200, 255)),
		Transparency = NS(0, 0.5, 1, 1),
		LightEmission = 1,
		ZOffset = R * 0.8,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
	})
	local galaxy = newPart({Name = "GalaxyCore", Shape = Enum.PartType.Ball, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Parent = model})

	stars:Emit(math.floor(160 * Q.Particles))
	nebula:Emit(math.floor(14 * Q.Particles) + 2)

	FX.Cosmic.Value = 0
	tween(FX.Cosmic, duration * 0.3, {Value = 1})
	task.delay(duration * 0.5, function() tween(FX.Cosmic, 0.25, {Value = 0}) end)

	AddUpdater(function(_, t)
		if not model.Parent then return true end
		local toCam = dirToCamera(center)
		local front = center + toCam * R * 0.9
		local facing = CFrame.lookAt(front, front + toCam)
		local a = t / duration
		local s
		if a < 0.3 then s = TweenService:GetValue(a / 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		elseif a < 0.65 then s = 1
		else s = 1 - TweenService:GetValue(math.min((a - 0.65) / 0.35, 1), Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
		s = math.max(s, 0.001)
		for _, L in ipairs(layers) do
			local dsz = L.r * R * 2 * s
			L.p.Size = Vector3.new(0.04, dsz, dsz)
			L.p.CFrame = facing * CFrame.new(0, 0, L.d * R * 0.6) * CFrame.Angles(0, math.pi / 2, 0)
		end
		holder.Size = Vector3.one * R * 1.4 * s
		holder.CFrame = facing
		galaxy.Size = Vector3.one * R * 0.08 * s
		galaxy.CFrame = facing * CFrame.new(0, 0, -0.1)
		if a >= 1 then model:Destroy() return true end
		return false
	end)

	task.wait(duration)
end

---------------------------------------------------------------------
-- FASE 6: COLAPSO FINAL
---------------------------------------------------------------------
local function CreateFinalCollapse(ctx)
	local bh = ctx.BH
	ctx.Debris.Mode = "consume"
	tween(ctx.GravityStrength, 0.2, {Value = 2.2})
	bh.EmitMul = 2.5
	bh.FieldMul = 4
	bh.SpinMul *= 2
	tween(bh.DiskFade, 0.28, {Value = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(FX.Darkness, 0.35, {Value = 0}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(FX.Blur, 0.3, {Value = 0})
	CreateCameraEffect("FinalCollapse")
	tween(bh.ScaleValue, 0.32, {Value = bh.ScaleValue.Value * 0.1}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	for _, obj in ipairs({ctx.Haze, ctx.LensShell, ctx.ImpactVoid, ctx.ImpactRim}) do
		if obj and obj.Parent then tween(obj, 0.3, {Size = obj.Size * 0.01}, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
	end
	SpawnRing({Basis = basisFromNormal(ctx.Center, dirToCamera(ctx.Center)), R0 = CONFIG.GravityRadius * 0.4, R1 = 0.2,
		W0 = 0.3, W1 = 1.2, H = 0.1, T0 = 0.6, T1 = 0, Time = 0.3, Color = CONFIG.Colors.PhotonRing,
		Easing = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In})
	task.wait(0.32)

	-- O buraco negro desaparece... e por um instante, outra dimensao
	bh:SetHidden(true)
	ctx.GravityActive = false
	CreateCosmicWindow(ctx, 0.2)

	-- 0.2s de vazio absoluto
	task.wait(0.2)
end

---------------------------------------------------------------------
-- EXPLOSAO REVERSA
---------------------------------------------------------------------
local function SpawnFlyingChunk(ctx)
	local N = ctx.GroundNormal
	local s = rand(0.5, 1.9)
	local dirv = (N * rand(0.4, 1.2) + randomUnit() * 0.9).Unit
	if dirv:Dot(N) < 0.1 then dirv = (dirv + N).Unit end
	local p = newPart({Name = "FlyingChunk", Anchored = false, CanCollide = true, CanQuery = true,
		Size = Vector3.new(s, s * rand(0.5, 1), s * rand(0.6, 1.2)), Color = ctx.GroundColor,
		CFrame = CFrame.new(ctx.GroundPos + N * (s * 0.6) + randomUnit() * 1.5) * CFrame.Angles(rand(0, 6.28), rand(0, 6.28), rand(0, 6.28))})
	setMaterial(p, ctx.GroundMaterial)
	p.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.4, 0.3)
	p.AssemblyLinearVelocity = dirv * rand(40, 120)
	p.AssemblyAngularVelocity = randomUnit() * rand(5, 20)
	task.delay(3.5, function() if p.Parent then tween(p, 1, {Transparency = 1}) end end)
	Debris:AddItem(p, 4.6)
end

local function ApplyExplosionForce(ctx)
	local parts = Workspace:GetPartBoundsInRadius(ctx.Center, CONFIG.ExplosionRadius, ctx.OverlapParams)
	local seen, count = {}, 0
	for _, p in ipairs(parts) do
		local root = p.AssemblyRootPart
		if root and not root.Anchored and not seen[root] then
			seen[root] = true
			count += 1
			if count > CONFIG.MaxAffectedAssemblies * 2 then break end
			local off = root.Position - ctx.Center
			local dist = math.max(off.Magnitude, 0.5)
			local falloff = 1 - math.clamp(dist / CONFIG.ExplosionRadius, 0, 1)
			local mass = root.AssemblyMass
			local mf = mass > CONFIG.HeavyMassThreshold and 0.1 or math.clamp(60 / math.max(mass, 1), 0.3, 1)
			local dir = (off.Unit + ctx.GroundNormal * 0.6).Unit
			root.AssemblyLinearVelocity += dir * CONFIG.ExplosionForce * falloff * mf
			root.AssemblyAngularVelocity += randomUnit() * 10 * falloff * mf
		end
	end
end

local function CreateGroundMark(ctx)
	if not ctx.HasGround then return end
	local N = ctx.GroundNormal
	local base = basisFromNormal(ctx.GroundPos + N * 0.03, N)
	local axis = base * CFrame.Angles(0, 0, math.pi / 2)
	local R = CONFIG.ExplosionRadius * 0.16 + CONFIG.BlackHoleRadius
	local parts = {}
	local scorch = newPart({Name = "Scorch", Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(14, 11, 20),
		Material = Enum.Material.Slate, Size = Vector3.new(0.06, R * 2, R * 2), CFrame = axis})
	local glow = newPart({Name = "ScorchGlow", Shape = Enum.PartType.Cylinder, Color = CONFIG.Colors.Energy,
		Material = Enum.Material.Neon, Transparency = 0.1, Size = Vector3.new(0.04, R * 2.15, R * 2.15), CFrame = axis * CFrame.new(-0.012, 0, 0)})
	local void = newPart({Name = "ScorchVoid", Shape = Enum.PartType.Cylinder, Color = Color3.new(0, 0, 0),
		Material = Enum.Material.Neon, Size = Vector3.new(0.08, R * 0.9, R * 0.9), CFrame = axis * CFrame.new(0.012, 0, 0)})
	table.insert(parts, scorch); table.insert(parts, glow); table.insert(parts, void)
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2 + rand(-0.15, 0.15)
		local len = R * rand(0.6, 1.5)
		local crack = newPart({Name = "Crack", Color = Color3.fromRGB(10, 8, 14), Material = Enum.Material.Slate,
			Size = Vector3.new(rand(0.18, 0.4), 0.05, len),
			CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.04, -(R * 0.8 + len / 2))})
		table.insert(parts, crack)
	end
	task.delay(0.4, function() if glow.Parent then tween(glow, 3, {Transparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end end)
	task.delay(CONFIG.GroundMarkDuration, function()
		for _, p in ipairs(parts) do if p.Parent then tween(p, 2, {Transparency = 1}) end end
	end)
	for _, p in ipairs(parts) do Debris:AddItem(p, CONFIG.GroundMarkDuration + 2.5) end
end

local function CreateReverseExplosion(ctx)
	local R = CONFIG.BlackHoleRadius
	local ER = CONFIG.ExplosionRadius
	local center = ctx.Center
	local N = ctx.GroundNormal
	local toCam = dirToCamera(center)

	-- "O universo acabou de voltar ao lugar."
	CreateCameraEffect("Explosion")
	FX.Darkness.Value = 0
	FX.Flash.Value = 1
	tween(FX.Flash, 0.9, {Value = 0})
	FX.Blur.Value = 16
	tween(FX.Blur, 0.7, {Value = 0})

	local flash = newPart({Name = "Flash", Shape = Enum.PartType.Ball, Color = Color3.new(1, 1, 1),
		Material = Enum.Material.Neon, Size = Vector3.one * 0.4, CFrame = CFrame.new(center)})
	local light = Instance.new("PointLight")
	light.Color = CONFIG.Colors.Energy
	light.Brightness = 12
	light.Range = 60
	light.Parent = flash
	tween(flash, 0.07, {Size = Vector3.one * R * 2.2})
	task.delay(0.07, function() tween(flash, 0.35, {Size = Vector3.one * R * 4, Transparency = 1}) end)
	tween(light, 0.5, {Brightness = 0})
	Debris:AddItem(flash, 0.6)

	-- Ondas de choque
	local groundBasis = basisFromNormal(ctx.GroundPos + N * 0.25, N)
	SpawnRing({Basis = groundBasis, R0 = R, R1 = ER, W0 = R * 1.2, W1 = 0.3, H = 0.4, T0 = 0, T1 = 1, Time = 0.95, Color = CONFIG.Colors.Shockwave})
	SpawnRing({Basis = groundBasis, R0 = R * 0.6, R1 = ER * 0.7, W0 = R * 2, W1 = R * 0.6, H = R * 0.5, T0 = 0.2, T1 = 1, Time = 1.3,
		Color = CONFIG.Colors.Energy, Material = Enum.Material.ForceField, Easing = Enum.EasingStyle.Quint})
	SpawnRing({Basis = basisFromNormal(center, toCam), R0 = R * 0.8, R1 = ER * 0.55, W0 = R * 0.6, W1 = 0.1, H = 0.2, T0 = 0, T1 = 1, Time = 0.6,
		Color = CONFIG.Colors.PhotonRing})

	-- Esfera de distorcao gigante
	local glassS = newPart({Name = "DistortionSphere", Shape = Enum.PartType.Ball, Material = Enum.Material.Glass,
		Color = Color3.fromRGB(215, 205, 255), Transparency = 0.5, Size = Vector3.one * R * 2, CFrame = CFrame.new(center)})
	tween(glassS, 0.6, {Size = Vector3.one * ER * 1.5, Transparency = 1}, Enum.EasingStyle.Quart)
	Debris:AddItem(glassS, 0.7)
	local ffS = newPart({Name = "EnergySphere", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField,
		Color = CONFIG.Colors.Energy, Size = Vector3.one * R * 2, CFrame = CFrame.new(center)})
	tween(ffS, 0.9, {Size = Vector3.one * ER * 2, Transparency = 1}, Enum.EasingStyle.Quint)
	Debris:AddItem(ffS, 1)

	-- Particulas lancadas em todas as direcoes
	local burst = newPart({Name = "Burst", Shape = Enum.PartType.Ball, Transparency = 1, Size = Vector3.one * R, CFrame = CFrame.new(center)})
	Debris:AddItem(burst, 3)
	local sparks = makeEmitter(burst, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(70, 170), Drag = 3.5, Lifetime = NumberRange.new(0.6, 1.4),
		Size = NS(0, 0.45, 1, 0), LightEmission = 1,
		Color = CS(0, Color3.new(1, 1, 1), 0.4, CONFIG.Colors.DiskHot, 1, CONFIG.Colors.Energy),
		Transparency = NS(0, 0, 0.8, 0.2, 1, 1),
	})
	sparks:Emit(math.floor(220 * Q.Particles))
	local smoke = makeEmitter(burst, {
		Texture = CONFIG.Textures.Smoke,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Speed = NumberRange.new(25, 60), Drag = 2.5, Lifetime = NumberRange.new(0.9, 1.6),
		Size = NS(0, 3, 1, 10), LightEmission = 0.1, LightInfluence = 0.4,
		Color = CS(0, Color3.fromRGB(35, 15, 70), 1, Color3.fromRGB(10, 5, 20)),
		Transparency = NS(0, 0.35, 1, 1),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
	})
	smoke:Emit(math.floor(40 * Q.Particles))
	local dust = makeEmitter(burst, {
		Texture = CONFIG.Textures.Smoke,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Speed = NumberRange.new(30, 80), Drag = 3, Lifetime = NumberRange.new(0.8, 1.4),
		Size = NS(0, 2, 1, 6), LightEmission = 0, LightInfluence = 1,
		Color = ColorSequence.new(ctx.GroundColor),
		Transparency = NS(0, 0.4, 1, 1),
		Rotation = NumberRange.new(0, 360),
	})
	dust:Emit(math.floor(30 * Q.Particles))

	-- Objetos arremessados
	for _ = 1, Q.ExplosionChunks do SpawnFlyingChunk(ctx) end
	ApplyExplosionForce(ctx)

	-- Marca circular no chao
	CreateGroundMark(ctx)

	-- O som do mundo volta
	SetWorldSilence(false, 1.5)
end

---------------------------------------------------------------------
-- ORQUESTRACAO DA SEQUENCIA
---------------------------------------------------------------------
local function computeCollapseTime()
	local fixed = CONFIG.ImpactDelay + (0.18 + CONFIG.SingularityPulses * 0.45 + 0.3) + (0.32 + 0.2 + 0.2) + 1.8
	return math.max(1.5, CONFIG.AbilityDuration - fixed)
end

local function ResetEnvironment()
	tween(FX.Darkness, 0.6, {Value = 0})
	tween(FX.Blur, 0.4, {Value = 0})
	tween(FX.Flash, 0.3, {Value = 0})
	tween(FX.Cosmic, 0.3, {Value = 0})
	FX.TimeScale.Value = 1
	SetWorldSilence(false, 0.8)
	CreateCameraEffect("Reset")
	ArmPose.Angle = nil
end

local function RunSequence(maid, char, aimOverride)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	baseExposure = Lighting.ExposureCompensation
	local ctx = {Maid = maid, Char = char}

	-- ================= FASE 1: CRIACAO =================
	local orb = CreateBlackHole(CONFIG.ProjectileSize / 2, maid)
	ctx.BH = orb
	local function handTip() return getHandTip(char) end
	orb.PosValue.Value = handTip()
	orb.ScaleValue.Value = 0.02
	orb.DiskFade.Value = 1
	orb.FieldMul = 7
	tween(orb.DiskFade, CONFIG.ChargeTime * 0.8, {Value = 0})
	tween(orb.ScaleValue, CONFIG.ChargeTime * 0.85, {Value = 1}, Enum.EasingStyle.Back)
	tween(FX.Darkness, CONFIG.ChargeTime, {Value = 0.22}, Enum.EasingStyle.Sine)
	CreateCameraEffect("Charge")
	SetArmPose(char, 95)
	local stopGravity = CreateGravityEffect(handTip, char, maid)

	local following = true
	maid:Give(AddUpdater(function(_, t)
		if not following then return true end
		orb.PosValue.Value = handTip()
		orb.PulseValue.Value = math.sin(t * 9) * 0.05
		return false
	end))
	task.wait(CONFIG.ChargeTime)

	-- ================= FASE 2: ARREMESSO =================
	local params = makeRaycastParams(char)
	local aimPoint = aimOverride or GetAimPoint(params)
	if hrp then
		local flat = Vector3.new(aimPoint.X - hrp.Position.X, 0, aimPoint.Z - hrp.Position.Z)
		if flat.Magnitude > 0.1 then hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat) end
	end
	SetArmPose(char, 115)
	RunService.Heartbeat:Wait()
	following = false
	stopGravity()
	orb.PulseValue.Value = 0

	local origin = handTip()
	local dir = aimPoint - origin
	if dir.Magnitude < 2 then dir = hrp and hrp.CFrame.LookVector or Vector3.zAxis end
	dir = dir.Unit
	orb.FieldMul = 11
	orb:SetTrail(true)
	CreateCameraEffect("Launch")
	task.delay(0.35, function() SetArmPose(char, nil) end)

	local hit = FlyProjectile(orb, origin, dir, params)

	-- ================= FASE 3: CONTATO =================
	ctx.HitPos = hit.Position
	ctx.Normal = hit.Normal
	ctx.Center = hit.Position + hit.Normal * CONFIG.BlackHoleRadius * 1.2
	orb.PosValue.Value = hit.Position + hit.Normal * orb.Radius
	ResolveGround(ctx, hit)
	CreateImpact(ctx)

	-- ================= FASE 4: COLAPSO ESPACIAL =================
	CreateSpatialCollapse(ctx, computeCollapseTime())

	-- ================= FASE 5: SINGULARIDADE =================
	CreateSingularity(ctx)

	-- ================= FASE 6: COLAPSO FINAL + JANELA =================
	CreateFinalCollapse(ctx)

	-- ================= EXPLOSAO REVERSA =================
	CreateReverseExplosion(ctx)
	task.wait(1.8)

	ctx.Ended = true
	ResetEnvironment()
	task.wait(0.6)
end

---------------------------------------------------------------------
-- API PUBLICA
---------------------------------------------------------------------
local State = {Busy = false, LastEnd = -math.huge}

-- aimOverride (opcional): Vector3 alvo. Util para mobile/auto-aim.
function ActivateBlackHole(aimOverride)
	if State.Busy then return false end
	if os.clock() - State.LastEnd < CONFIG.Cooldown then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart")) then return false end

	State.Busy = true
	task.spawn(function()
		local maid = Maid.new()
		local ok, err = pcall(RunSequence, maid, char, aimOverride)
		if not ok then warn("[BlackHole] " .. tostring(err)) end
		maid:Clean()
		ResetEnvironment()
		State.Busy = false
		State.LastEnd = os.clock()
	end)
	return true
end

_G.ActivateBlackHole = ActivateBlackHole

-- Evento para GUIs mobile / outros LocalScripts
local activateEvent = player:FindFirstChild("BlackHoleActivate") or Instance.new("BindableEvent")
activateEvent.Name = "BlackHoleActivate"
activateEvent.Parent = player
activateEvent.Event:Connect(function(target) ActivateBlackHole(target) end)

---------------------------------------------------------------------
-- INPUT (teclado, gamepad e botao touch automatico)
---------------------------------------------------------------------
local ACTION_NAME = "BlackHoleAbility"
ContextActionService:BindAction(ACTION_NAME, function(_, state)
	if state == Enum.UserInputState.Begin then ActivateBlackHole() end
	return Enum.ContextActionResult.Sink
end, CONFIG.CreateMobileButton, CONFIG.Keybind, CONFIG.GamepadButton)

if CONFIG.CreateMobileButton then
	ContextActionService:SetTitle(ACTION_NAME, "🕳")
end

print("[BlackHole] Singularidade carregada. Pressione Z.")
