-- ============================================================================
-- CombatManager.lua - 战斗动作管理器（客户端专用 Module）
-- 职责：处理所有战斗相关动作的逻辑（闪避、蹲下、奔跑、瞄准、攻击等）
-- ⚠️ 此模块仅在客户端使用，请勿在服务器引用
-- ============================================================================

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- 客户端验证
if not RunService:IsClient() then
	error("[CombatManager] This module can only be used on the client!")
end

-- 模块引用
local Player = Players.LocalPlayer
local PlayerManager = require(ReplicatedStorage:WaitForChild("PlayerManager"))
local CameraEffectManager = require(ReplicatedStorage:WaitForChild("CameraEffectManager"))
local AnimationManager = require(ReplicatedStorage:WaitForChild("AnimationManager"))
local UIManager = require(ReplicatedStorage:WaitForChild("UIManager"))

if not UIManager.IsReady then
	repeat task.wait() until UIManager.IsReady
end

-- ============================================================================
-- 配置参数
-- ============================================================================

-- 闪避配置
local DODGE_COOLDOWN = 0.4
local DODGE_DISTANCE = 15
local DODGE_DURATION = 0.3

-- 蹲下配置
local CROUCH_HIP_HEIGHT_OFFSET = -1.5

-- 瞄准配置
local AIM_FOV_OFFSET = -20
local AIM_TRANSITION_SPEED = 0.15

-- 准心配置
local CROSSHAIR_UI_NAME = "Crosshair"
local CROSSHAIR_SMOOTHNESS = 0.05
local CAMERA_SMOOTHNESS = 0.1

-- 奔跑配置
local RUNNING_FOV_OFFSET = 10

-- ============================================================================
-- 战斗管理器
-- ============================================================================

local CombatManager = {
	-- === 状态标志 ===
	IsDodging = false,
	IsCrouching = false,
	IsAiming = false,
	IsRunning = false,
	IsAttacking = false,

	-- === 原始值 ===
	OriginalWalkSpeed = PlayerManager.DefaultWalkSpeed,
	OriginalJumpHeight = PlayerManager.DefaultJumpHeight,
	OriginalHipHeight = PlayerManager.DefaultHipHeight,

	-- === 内部状态 ===
	_dodgeCooldownEndTime = 0,
	_aimProgress = 0,
	_runningProgress = 0,
	_smoothCrosshairAngleX = 0,
	_smoothCrosshairAngleY = 0,
	_smoothCrosshairX = 0.5,
	_smoothCrosshairY = 0.5,

	-- === 连接管理 ===
	_crouchConnection = nil,
	_updateConnection = nil,
	_animManager = nil,

	-- === 角色引用 ===
	_character = nil,
	_humanoid = nil,
}

-- ============================================================================
-- 工具函数
-- ============================================================================

-- 将角度归一化到 -180 到 180 范围
local function normalizeAngle(angle)
	angle = angle % 360
	if angle > 180 then
		angle = angle - 360
	elseif angle < -180 then
		angle = angle + 360
	end
	return angle
end

-- 计算两个角度之间的最短差值
local function shortestDeltaDeg(fromDeg, toDeg)
	return normalizeAngle(toDeg - fromDeg)
end

-- ============================================================================
-- 瞄准系统
-- ============================================================================

function CombatManager:StartAiming()
	if self.IsAiming then return end

	self.IsAiming = true
	PlayerManager.IsAiming = true
	PlayerManager.IsRunning = false
	self.IsRunning = false

	if self._animManager then
		local aimAnimation = self._animManager:PlayAnimation("Aiming", 0.1)
		if aimAnimation then
			aimAnimation.Priority = Enum.AnimationPriority.Action
		end
	end

	UIManager:SettingAlpha("Vignette", 0, true, 0.2)
	UIManager:ShowUI(CROSSHAIR_UI_NAME)
end

function CombatManager:StopAiming()
	if not self.IsAiming then return end

	self.IsAiming = false
	PlayerManager.IsAiming = false

	if self._animManager then
		self._animManager:StopAnimation("Aiming", 0.2)
	end

	UIManager:SettingAlpha("Vignette", 1, true, 0.4)
	UIManager:HideUI(CROSSHAIR_UI_NAME)
end

-- 更新瞄准效果（内部更新循环调用）
function CombatManager:_updateAimingEffects()
	local targetAimProgress = self.IsAiming and 1 or 0
	self._aimProgress = self._aimProgress + (targetAimProgress - self._aimProgress) * AIM_TRANSITION_SPEED

	local targetAimFOV = AIM_FOV_OFFSET * self._aimProgress
	CameraEffectManager:SetFOVModifier("Aiming", targetAimFOV)
end

-- ============================================================================
-- 奔跑系统
-- ============================================================================

function CombatManager:StartRunning()
	if self.IsRunning or not self._humanoid or self._humanoid.Health <= 0 then return end
	if PlayerManager.IsExhausted or PlayerManager.IsAiming then return end

	self.IsRunning = true
	PlayerManager.IsRunning = true
	PlayerManager.StaminaComp:AddEffect("Running", -10, nil)
end

function CombatManager:StopRunning()
	if not self.IsRunning then return end

	self.IsRunning = false
	PlayerManager.IsRunning = false
	PlayerManager.StaminaComp:RemoveEffectByName("Running")
end

-- 更新奔跑效果（内部更新循环调用）
function CombatManager:_updateRunningEffects()
	local targetRunningProgress = PlayerManager.IsRunning and 1 or 0
	self._runningProgress = self._runningProgress + (targetRunningProgress - self._runningProgress) * AIM_TRANSITION_SPEED

	local targetRunningFOV = RUNNING_FOV_OFFSET * self._runningProgress
	CameraEffectManager:SetFOVModifier("Running", targetRunningFOV)
end

-- ============================================================================
-- 蹲下系统
-- ============================================================================

function CombatManager:StartCrouching()
	if self.IsCrouching or not self._character or not self._humanoid or self._humanoid.Health <= 0 then
		return
	end

	self.IsCrouching = true
	PlayerManager.IsCrouching = true

	if self._animManager then
		local crouchAnimation = self._animManager:PlayAnimation("Down", 0.2)
		if crouchAnimation then
			crouchAnimation.Priority = Enum.AnimationPriority.Idle
			crouchAnimation.Looped = true
		end
	end

	if self._crouchConnection then
		self._crouchConnection:Disconnect()
	end

	self._crouchConnection = RunService.Heartbeat:Connect(function()
		if self.IsCrouching and self._humanoid and self._humanoid.Health > 0 then
			self._humanoid.JumpHeight = 0
			self._humanoid.JumpPower = 0
			self._humanoid.HipHeight = self.OriginalHipHeight + CROUCH_HIP_HEIGHT_OFFSET
		end
	end)
end

function CombatManager:StopCrouching()
	if not self.IsCrouching then return end

	self.IsCrouching = false
	PlayerManager.IsCrouching = false

	if self._crouchConnection then
		self._crouchConnection:Disconnect()
		self._crouchConnection = nil
	end

	if self._humanoid then
		self._humanoid.JumpHeight = self.OriginalJumpHeight
		self._humanoid.JumpPower = 50
		self._humanoid.HipHeight = self.OriginalHipHeight
	end

	if self._animManager then
		self._animManager:StopAnimation("Down", 0.2)
	end
end

-- ============================================================================
-- 闪避系统
-- ============================================================================

function CombatManager:PerformDodge()
	if self.IsDodging or tick() < self._dodgeCooldownEndTime then
		return false
	end

	if not self._character or not self._humanoid then return false end

	local rootPart = self._character:FindFirstChild("HumanoidRootPart")
	if not rootPart or self._humanoid.Health <= 0 then return false end

	if PlayerManager.IsExhausted or not PlayerManager.StaminaComp:Consume(20, "Dodge") then
		return false
	end

	self.IsDodging = true
	PlayerManager.IsDodging = true
	self._dodgeCooldownEndTime = tick() + DODGE_COOLDOWN

	local tempWalkSpeed = self._humanoid.WalkSpeed
	self._humanoid.WalkSpeed = 0

	if self._animManager then
		local dodgeAnimation = self._animManager:PlayAnimation("Dodge", 0.2)
		if dodgeAnimation then
			dodgeAnimation.Priority = Enum.AnimationPriority.Action
		end
	end

	local moveDirection = self._humanoid.MoveDirection
	if moveDirection.Magnitude < 0.1 then
		moveDirection = -rootPart.CFrame.LookVector
	end
	local dodgeVector = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit * DODGE_DISTANCE

	local tweenInfo = TweenInfo.new(DODGE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local targetCFrame = rootPart.CFrame + dodgeVector
	local dodgeTween = TweenService:Create(rootPart, tweenInfo, {CFrame = targetCFrame})
	dodgeTween:Play()

	task.wait(DODGE_DURATION)

	if self._animManager then
		self._animManager:StopAnimation("Dodge", 0.2)
	end

	self._humanoid.WalkSpeed = tempWalkSpeed
	self.IsDodging = false
	PlayerManager.IsDodging = false

	return true
end

-- ============================================================================
-- 准心系统
-- ============================================================================

function CombatManager:_updateCrosshairPosition()
	if not self._character then return end

	local rootPart = self._character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local rawCameraAngleX = PlayerManager.RawCameraAngleX or 0
	local rawCameraAngleY = PlayerManager.RawCameraAngleY or 0

	self._smoothCrosshairAngleX = self._smoothCrosshairAngleX +
		shortestDeltaDeg(self._smoothCrosshairAngleX, rawCameraAngleX) * CROSSHAIR_SMOOTHNESS
	self._smoothCrosshairAngleY = self._smoothCrosshairAngleY +
		(rawCameraAngleY - self._smoothCrosshairAngleY) * CROSSHAIR_SMOOTHNESS

	self._smoothCrosshairAngleX = normalizeAngle(self._smoothCrosshairAngleX)
	self._smoothCrosshairAngleY = normalizeAngle(self._smoothCrosshairAngleY)

	local crosshairRotation = CFrame.Angles(0, math.rad(self._smoothCrosshairAngleX), 0)
		* CFrame.Angles(math.rad(self._smoothCrosshairAngleY), 0, 0)
	local rayOrigin = rootPart.Position + Vector3.new(0, 1.5, 0)
	local rayDirection = crosshairRotation.LookVector
	
	local rayEndPoint = rayOrigin + rayDirection * 100

	local camera = workspace.CurrentCamera
	local screenPoint = camera:WorldToViewportPoint(rayEndPoint)
	local viewportSize = camera.ViewportSize
	local targetCrosshairX = screenPoint.X / viewportSize.X
	local targetCrosshairY = 1.0 - (screenPoint.Y / viewportSize.Y)

	if not PlayerManager.IsTargetLocked then
		targetCrosshairX = targetCrosshairX - 0.035
		targetCrosshairY = targetCrosshairY - 0.1
	end

	self._smoothCrosshairX = self._smoothCrosshairX + (targetCrosshairX - self._smoothCrosshairX) * 0.3
	self._smoothCrosshairY = self._smoothCrosshairY + (targetCrosshairY - self._smoothCrosshairY) * 0.3

	local targetPosition = UDim2.new(self._smoothCrosshairX, 0, self._smoothCrosshairY, 0)
	if UIManager:HasUI(CROSSHAIR_UI_NAME) then
	UIManager:MoveUI(CROSSHAIR_UI_NAME, targetPosition, false)
	end
end
-- ============================================================================
-- 攻击系统
-- ============================================================================
function CombatManager:Attack()
	if not self.IsAttacking and not self.IsAiming then
		
		self.IsAttacking=true
		
		if self._animManager then
			local AttackAnimation = self._animManager:PlayAnimation("None_LightAttack_2",0.1)
			AttackAnimation.Priority = Enum.AnimationPriority.Action
			AttackAnimation.Looped=false
		end
		self.IsAttacking = false
	end
end

-- ============================================================================
-- 初始化和清理
-- ============================================================================

function CombatManager:Init(character)
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid")

	-- 初始化动画管理器
	self._animManager = AnimationManager.new(Player)

	self.OriginalWalkSpeed = self._humanoid.WalkSpeed
	self.OriginalJumpHeight = self._humanoid.JumpHeight
	self.OriginalHipHeight = self._humanoid.HipHeight

	-- 初始化准心角度
	self._smoothCrosshairAngleX = normalizeAngle(PlayerManager.RawCameraAngleX or 0)
	self._smoothCrosshairAngleY = normalizeAngle(PlayerManager.RawCameraAngleY or 0)

	-- 统一的更新循环
	if self._updateConnection then
		self._updateConnection:Disconnect()
	end
	self._updateConnection = RunService.RenderStepped:Connect(function()
		self:_updateAimingEffects()
		self:_updateRunningEffects()
		self:_updateCrosshairPosition()
	end)

	print("[CombatManager] 初始化完成")
end

function CombatManager:Cleanup()
	-- 断开连接
	if self._crouchConnection then
		self._crouchConnection:Disconnect()
		self._crouchConnection = nil
	end

	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end

	-- 清理动画管理器
	if self._animManager then
		self._animManager:Cleanup()
		self._animManager = nil
	end

	-- 重置状态
	self.IsCrouching = false
	self.IsDodging = false
	self.IsAiming = false
	self.IsRunning = false
	PlayerManager.IsCrouching = false
	PlayerManager.IsDodging = false
	PlayerManager.IsAiming = false
	PlayerManager.IsRunning = false

	print("[CombatManager] 清理完成")
end

return CombatManager
