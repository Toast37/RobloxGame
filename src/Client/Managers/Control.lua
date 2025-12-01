-- ============================================================================
-- 玩家控制系统（输入接收器）
-- 职责：仅处理用户输入，将输入转发到 CombatManager
-- ============================================================================

-- 服务
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 模块
local Player = Players.LocalPlayer
local CombatManager = require(ReplicatedStorage:WaitForChild("CombatManager"))

-- ============================================================================
-- 配置参数
-- ============================================================================

-- 按键配置
local DODGE_KEY = Enum.KeyCode.Q
local CROUCH_KEY = Enum.KeyCode.C
local RUN_KEY = Enum.KeyCode.LeftShift
local AIM_KEY = Enum.UserInputType.MouseButton2
local ATTACK_KEY = Enum.UserInputType.MouseButton1

-- ============================================================================
-- 输入处理函数
-- ============================================================================

-- 闪避输入
local function DodgeAction(actionName, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then return end
	CombatManager:PerformDodge()
end

-- 蹲下输入
local function CrouchAction(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		CombatManager:StartCrouching()
	elseif inputState == Enum.UserInputState.End then
		CombatManager:StopCrouching()
	end
end

-- 奔跑输入
local function RunAction(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		CombatManager:StartRunning()
	else
		CombatManager:StopRunning()
	end
end

-- 瞄准输入
local function AimAction(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		CombatManager:StartAiming()
	elseif inputState == Enum.UserInputState.End then
		CombatManager:StopAiming()
	end
end

-- 攻击输入
local function AttackAction(actionNamae,inputState,inputObject)
	if inputState == Enum.UserInputState.Begin then
		CombatManager:Attack()
	end
end

-- ============================================================================
-- 初始化和清理
-- ============================================================================

local function Init()
	local character = Player.Character or Player.CharacterAdded:Wait()

	-- 初始化 CombatManager
	CombatManager:Init(character)

	-- 解绑旧的输入（如果存在）
	pcall(function()
		ContextActionService:UnbindAction("SinkInput")
	end)

	-- 绑定所有输入
	ContextActionService:BindAction("DodgeAction", DodgeAction, false, DODGE_KEY)
	ContextActionService:BindAction("CrouchAction", CrouchAction, false, CROUCH_KEY)
	ContextActionService:BindAction("RunAction", RunAction, false, RUN_KEY)
	ContextActionService:BindAction("AimAction", AimAction, false, AIM_KEY)
	ContextActionService:BindAction("AttackAction", AttackAction, false, ATTACK_KEY)

	print("[Control] 输入系统初始化完成")
	print("[Control] - Q: 闪避")
	print("[Control] - C: 蹲下")
	print("[Control] - Shift: 奔跑")
	print("[Control] - 鼠标右键: 瞄准")
end

local function Cleanup()
	-- 解绑所有输入
	ContextActionService:UnbindAction("DodgeAction")
	ContextActionService:UnbindAction("CrouchAction")
	ContextActionService:UnbindAction("RunAction")
	ContextActionService:UnbindAction("AimAction")

	-- 清理 CombatManager
	CombatManager:Cleanup()

	print("[Control] 输入系统清理完成")
end

-- ============================================================================
-- 事件监听
-- ============================================================================

Player.CharacterAdded:Connect(Init)
Player.CharacterRemoving:Connect(Cleanup)

if Player.Character then
	Init()
end
