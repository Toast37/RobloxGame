-- 动画管理器模块
-- 负责加载和播放角色动画
-- 支持两种使用方式：
-- 1. 实例模式：用于玩家，初始化后重复使用（推荐）
-- 2. 静态模式：用于NPC，直接播放不需要初始化

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local AnimationManager = {}
AnimationManager.__index = AnimationManager

-- 动画ID配置字典
local ANIMATION_IDS = {
	Dodge = "rbxassetid://115583572020539",
	Down = "rbxassetid://74409949830270",
	Aiming = "rbxassetid://97130422316194",
	None_LightAttack_1 = "rbxassetid://86626408791230",
	None_LightAttack_2 = "rbxassetid://132519929912742",
}

-- 内部函数：从Player或Character获取Character
local function getCharacter(target)
	-- 检测是否是Player对象
	if target:IsA("Player") then
		return target.Character
	end
	-- 否则假定是Character
	return target
end

-- 内部函数：加载单个动画轨道
local function loadAnimationTrack(character, animId)
	local humanoid = character:WaitForChild("Humanoid")
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	anim.Parent = ReplicatedStorage

	local track = humanoid:LoadAnimation(anim)
	return track
end

-- ========================================
-- 实例模式方法（用于玩家）
-- ========================================

-- 创建新的动画管理器实例（初始化并加载所有动画）
-- @param target: Player或Character对象
-- @return: AnimationManager实例
function AnimationManager.new(target)
	local self = setmetatable({}, AnimationManager)

	-- 获取Character
	local character = getCharacter(target)
	if not character then
		warn("AnimationManager.new - Invalid target (not a Player or Character)")
		return nil
	end

	self.character = character
	self.animationTracks = {}

	-- 加载所有动画
	for name, animId in pairs(ANIMATION_IDS) do
		local success, track = pcall(function()
			return loadAnimationTrack(character, animId)
		end)

		if success and track then
			self.animationTracks[name] = track
		else
			warn("Failed to load animation: " .. name)
		end
	end

	-- 预加载动画资源
	local animationArray = {}
	for _, track in pairs(self.animationTracks) do
		table.insert(animationArray, track)
	end

	if #animationArray > 0 then
		ContentProvider:PreloadAsync(animationArray)
	end

	return self
end

-- 播放动画函数（实例方法）
-- @param animationName: 动画名称（从已加载的轨道中获取）
-- @param fadeTime: 淡入淡出时间，默认为0（无淡入淡出）
-- @return: 动画轨道对象，如果失败返回nil
function AnimationManager:PlayAnimation(animationName, fadeTime)
	fadeTime = fadeTime or 0

	-- 从已加载的轨道中获取
	local track = self.animationTracks[animationName]
	if not track then
		warn("AnimationManager:PlayAnimation - Animation not found: " .. tostring(animationName))
		return nil
	end

	track:Play(fadeTime)
	return track
end

-- 停止动画（实例方法）
-- @param animationName: 动画名称
-- @param fadeTime: 淡出时间，默认为0
function AnimationManager:StopAnimation(animationName, fadeTime)
	fadeTime = fadeTime or 0

	local track = self.animationTracks[animationName]
	if track and track.IsPlaying then
		track:Stop(fadeTime)
	end
end

-- 获取动画轨道（实例方法）
-- @param animationName: 动画名称
-- @return: 动画轨道对象
function AnimationManager:GetTrack(animationName)
	return self.animationTracks[animationName]
end

-- 清理所有动画轨道（实例方法）
function AnimationManager:Cleanup()
	for _, track in pairs(self.animationTracks) do
		if track.IsPlaying then
			track:Stop()
		end
	end
	self.animationTracks = {}
end

-- ========================================
-- 静态模式方法（用于NPC或一次性播放）
-- ========================================

-- 静态播放动画函数（不需要初始化，直接播放）
-- @param target: Player或Character对象
-- @param animationName: 动画名称（从ANIMATION_IDS字典中获取）
-- @param fadeTime: 淡入淡出时间，默认为0（无淡入淡出）
-- @return: 动画轨道对象，如果失败返回nil
function AnimationManager.Play(target, animationName, fadeTime)
	fadeTime = fadeTime or 0

	-- 获取Character
	local character = getCharacter(target)
	if not character then
		warn("AnimationManager.Play - Invalid target (not a Player or Character)")
		return nil
	end

	-- 从字典中获取动画ID
	local animId = ANIMATION_IDS[animationName]
	if not animId then
		warn("AnimationManager.Play - Animation not found: " .. tostring(animationName))
		return nil
	end

	-- 加载并播放动画
	local success, track = pcall(function()
		return loadAnimationTrack(character, animId)
	end)

	if success and track then
		track:Play(fadeTime)
		return track
	else
		warn("AnimationManager.Play - Failed to load/play animation: " .. animationName)
		return nil
	end
end

return AnimationManager