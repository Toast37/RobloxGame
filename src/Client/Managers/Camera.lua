-- ============================================================================
-- 摄像机控制系统
-- 职责：控制第三人称摄像机、角色身体和头部旋转
-- ============================================================================

-- 服务
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

-- 模块
local PlayerManager = require(game.ReplicatedStorage:WaitForChild("Client"):WaitForChild("Managers"):WaitForChild("PlayerManager"))
local CameraEffectManager = require(game.ReplicatedStorage:WaitForChild("Client"):WaitForChild("Managers"):WaitForChild("CameraEffectManager"))

-- UI设置
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
UserInputService.MouseIconEnabled = false

-- ============================================================================
-- 配置参数
-- ============================================================================

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 摄像机配置
local INITIAL_CAMERA_OFFSET = Vector3.new(2.5, 2.5, 5)
local cameraOffset = INITIAL_CAMERA_OFFSET
local mouseSensitivity = 0.15
local Y_CLAMP_MIN = -80
local Y_CLAMP_MAX = 80

-- 平滑度配置
local headSmoothness = 0.3 
local bodySmoothness = 0.1  
local cameraSmoothness = 0.5
local cameraTargetSmoothness = 0.08

-- 头部与身体分离
local MAX_HEAD_BODY_ANGLE = 60
local MOVE_ALIGN_SMOOTHNESS = 0.15

-- 视角归位配置
local RECENTER_TIMEOUT = 10
local RECENTER_SPEED = 0.08
local DEFAULT_CAMERA_ANGLE_Y = 10

-- FOV配置
local defaultFOV = 70

-- ============================================================================
-- 状态变量
-- ============================================================================

-- 角度状态
local cameraAngleX = 0
local cameraAngleY = 0
local headAngleX = 0
local bodyAngleX = 0
local smoothCameraAngleX = 0
local smoothCameraAngleY = 0

-- 视角归位状态
local lastMouseMoveTime = 0
local isRecentering = false
local recenterTargetX = 0
local recenterTargetY = DEFAULT_CAMERA_ANGLE_Y

-- 肩膀切换状态
local cameraOffsetValue = Instance.new("Vector3Value")
cameraOffsetValue.Value = cameraOffset
local shoulderTween: Tween? = nil
local isChangingShoulder = false
local currentShoulderSide = 1

-- 连接
local cameraConnection = nil

cameraOffsetValue:GetPropertyChangedSignal("Value"):Connect(function()
	cameraOffset = cameraOffsetValue.Value
end)

-- ============================================================================
-- 工具函数
-- ============================================================================

-- 简单归一化到 -180 到 180（仅在必要时使用）
local function normalizeAngle(angle)
	while angle > 180 do angle = angle - 360 end
	while angle < -180 do angle = angle + 360 end
	return angle
end

-- 计算从 current 到 target 的最短角度差（带符号）
local function shortestAngleDelta(current, target)
	local delta = normalizeAngle(target - current)
	return delta
end

-- 使用最短路径进行角度插值
local function stepAngleDeg(current, target, alpha)
	local delta = shortestAngleDelta(current, target)
	return current + delta * alpha
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- ============================================================================
-- 头部与身体旋转系统
-- ============================================================================

local function updateHeadAndBodyAngles(targetAngleX, isMoving)
	-- 检测快速旋转：如果目标角度与头部/身体差距过大，加速跟随
	local headDelta = math.abs(shortestAngleDelta(headAngleX, targetAngleX))
	local bodyDelta = math.abs(shortestAngleDelta(bodyAngleX, targetAngleX))

	-- 如果差距超过 90°，视为快速旋转，提高跟随速度
	local headAlpha = headDelta > 90 and 0.95 or headSmoothness
	local bodyAlpha = bodyDelta > 90 and 0.85 or (bodySmoothness + (isMoving and MOVE_ALIGN_SMOOTHNESS or 0))

	headAngleX = stepAngleDeg(headAngleX, targetAngleX, headAlpha)
	bodyAngleX = stepAngleDeg(bodyAngleX, targetAngleX, bodyAlpha)
end

local function applyBodyRotation(rootPart)
	local currentCF = rootPart.CFrame
	local targetRotation = CFrame.Angles(0, math.rad(bodyAngleX), 0)
	rootPart.CFrame = CFrame.new(currentCF.Position) * targetRotation
end

local function applyHeadRotation(neck, originalNeckC0, pitchAngle)
	if not neck or not originalNeckC0 then return end

	local yaw = math.clamp(headAngleX - bodyAngleX, -MAX_HEAD_BODY_ANGLE, MAX_HEAD_BODY_ANGLE)
	local headRotation = CFrame.Angles(math.rad(-pitchAngle), 0, math.rad(-yaw))
	neck.C0 = originalNeckC0 * headRotation
end

-- ============================================================================
-- 摄像机系统
-- ============================================================================

local function updateCameraSmoothAngles()
	local deltaX = cameraAngleX - smoothCameraAngleX
	smoothCameraAngleX = smoothCameraAngleX + deltaX * cameraSmoothness
	smoothCameraAngleY = smoothCameraAngleY + (cameraAngleY - smoothCameraAngleY) * cameraSmoothness
end

local function applyCameraTransform(rootPart, currentOffset)
	local cameraRotation = CFrame.Angles(0, math.rad(smoothCameraAngleX), 0)
		* CFrame.Angles(math.rad(smoothCameraAngleY), 0, 0)

	-- 获取摄像机抖动偏移
	local shakeOffset = CameraEffectManager.CameraShakeOffset or CFrame.new()

	-- 获取头部晃动偏移
	local headBobOffset = CameraEffectManager.HeadBobOffset or Vector3.new(0, 0, 0)

	-- 应用摄像机变换：位置 + 旋转 + 偏移 + 抖动
	local baseCFrame = CFrame.new(rootPart.Position)
		* cameraRotation
		* CFrame.new(currentOffset)
		* shakeOffset

	-- 在摄像机的本地空间中应用头部晃动
	local finalCFrame = baseCFrame * CFrame.new(headBobOffset)

	camera.CFrame = finalCFrame
end

-- ============================================================================
-- 视角归位系统
-- ============================================================================

local function handleMouseInputAndRecenter(mouseDelta)
	if PlayerManager.IsTargetLocked then return end

	-- 防止 Roblox 引擎偶发的异常大增量（窗口失焦/重新获得焦点时）
	local MAX_MOUSE_DELTA = 50
	if mouseDelta.Magnitude > MAX_MOUSE_DELTA then
		mouseDelta = mouseDelta.Unit * MAX_MOUSE_DELTA
	end

	local hasMouseInput = mouseDelta.Magnitude > 0.01

	if hasMouseInput then
		-- 瞄准时降低鼠标灵敏度为一半
		local currentSensitivity = mouseSensitivity
		if PlayerManager.IsAiming then
			currentSensitivity = currentSensitivity * 0.5
		end

		cameraAngleX = cameraAngleX - mouseDelta.X * currentSensitivity
		cameraAngleY = cameraAngleY - mouseDelta.Y * currentSensitivity
		cameraAngleY = math.clamp(cameraAngleY, Y_CLAMP_MIN, Y_CLAMP_MAX)

		lastMouseMoveTime = tick()
		isRecentering = false
	else
		local idleTime = tick() - lastMouseMoveTime
		if idleTime >= RECENTER_TIMEOUT and not isRecentering then
			isRecentering = true
			recenterTargetX = bodyAngleX
			recenterTargetY = DEFAULT_CAMERA_ANGLE_Y
		end
	end


end

local function updateRecenterProgress()
	if not isRecentering then return end

	cameraAngleX = stepAngleDeg(cameraAngleX, recenterTargetX, RECENTER_SPEED)
	cameraAngleY = lerp(cameraAngleY, recenterTargetY, RECENTER_SPEED)

	-- 计算接近阈值（不做归一化）
	local deltaX = math.abs(cameraAngleX - recenterTargetX)
	local deltaY = math.abs(cameraAngleY - recenterTargetY)
	if deltaX < 0.5 and deltaY < 0.5 then
		isRecentering = false
	end
end

-- ============================================================================
-- 目标锁定系统
-- ============================================================================

local function updateTargetLockCamera(rootPart)
	if not PlayerManager.IsTargetLocked or not PlayerManager.LockedTarget then return end

	local target = PlayerManager.LockedTarget
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	local playerPos = rootPart.Position
	local targetPos = targetRoot.Position
	local direction = (targetPos - playerPos).Unit

	local lookAtCFrame = CFrame.lookAt(playerPos, targetPos)
	local _, y, _ = lookAtCFrame:ToEulerAnglesYXZ()
	local targetAngleX = math.deg(y)

	local horizontalDistance = math.sqrt(direction.X^2 + direction.Z^2)
	local targetAngleY = math.deg(math.atan2(direction.Y, horizontalDistance))

	-- 使用最短路径插值，避免"转错方向"（比如目标在左边5°却转右边355°）
	cameraAngleX = stepAngleDeg(cameraAngleX, targetAngleX, cameraTargetSmoothness)
	cameraAngleY = stepAngleDeg(cameraAngleY, targetAngleY, cameraTargetSmoothness)
	cameraAngleY = math.clamp(cameraAngleY, Y_CLAMP_MIN, Y_CLAMP_MAX)
end

-- ============================================================================
-- 核心摄像机设置
-- ============================================================================

local function setupThirdPersonCamera(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")
	local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
	local Neck = torso and torso:FindFirstChild("Neck")
	if torso and not Neck then
		Neck = torso:WaitForChild("Neck")
	end

	local originalNeckC0 = Neck and Neck.C0
	if Neck then Neck.Transform = CFrame.new() end

	-- 初始化角度（归一化一次，避免初始值超出范围）
	local _, startY, _ = rootPart.CFrame:ToOrientation()
	cameraAngleX = normalizeAngle(-math.deg(startY))
	headAngleX = cameraAngleX
	bodyAngleX = cameraAngleX
	smoothCameraAngleX = cameraAngleX
	smoothCameraAngleY = DEFAULT_CAMERA_ANGLE_Y
	cameraAngleY = DEFAULT_CAMERA_ANGLE_Y

	-- 初始化归位系统
	lastMouseMoveTime = tick()
	isRecentering = false
	recenterTargetX = cameraAngleX
	recenterTargetY = DEFAULT_CAMERA_ANGLE_Y

	if cameraConnection then
		cameraConnection:Disconnect()
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	humanoid.AutoRotate = false
	camera.FieldOfView = defaultFOV

	-- 核心循环
	cameraConnection = RunService.RenderStepped:Connect(function(dt)
		camera.CameraType = Enum.CameraType.Scriptable

		if not rootPart or not rootPart.Parent then
			cameraConnection:Disconnect()
			return
		end

		local mouseDelta = UserInputService:GetMouseDelta()
		handleMouseInputAndRecenter(mouseDelta)
		updateRecenterProgress()
		updateTargetLockCamera(rootPart)

		local isMoving = humanoid.MoveDirection.Magnitude > 0.05
		updateHeadAndBodyAngles(cameraAngleX, isMoving)
		applyBodyRotation(rootPart)
		updateCameraSmoothAngles()
		applyHeadRotation(Neck, originalNeckC0, smoothCameraAngleY)

		applyCameraTransform(rootPart, cameraOffset)

		-- 导出原始摄像机角度供准心系统使用
		-- 准心和摄像机追踪同一个目标，但准心使用更慢的平滑速度，从而延后于摄像机
		PlayerManager.RawCameraAngleX = cameraAngleX
		PlayerManager.RawCameraAngleY = cameraAngleY
	end)
end

-- ============================================================================
-- 肩膀切换
-- ============================================================================

local function ChangeShoulder(ActionName, InputState, Inputobj)
	if InputState ~= Enum.UserInputState.Begin then return end
	if isChangingShoulder then return end

	isChangingShoulder = true
	currentShoulderSide = -currentShoulderSide

	local target = Vector3.new(
		INITIAL_CAMERA_OFFSET.X * currentShoulderSide,
		INITIAL_CAMERA_OFFSET.Y,
		INITIAL_CAMERA_OFFSET.Z
	)

	if shoulderTween then shoulderTween:Cancel() end
	shoulderTween = TweenService:Create(
		cameraOffsetValue,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = target }
	)

	shoulderTween.Completed:Connect(function()
		isChangingShoulder = false
	end)

	shoulderTween:Play()
end

-- ============================================================================
-- 初始化
-- ============================================================================

localPlayer.CharacterAdded:Connect(setupThirdPersonCamera)
ContextActionService:BindAction("ChangeCameraShoulder", ChangeShoulder, false, Enum.KeyCode.H)

if localPlayer.Character then
	setupThirdPersonCamera(localPlayer.Character)
end