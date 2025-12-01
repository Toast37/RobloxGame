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
}

-- 攻击动画字典（按武器类型分类）
local ATTACK_ANIMATIONS = {
	None = {
		LightAttack = {
			"rbxassetid://86626408791230",   -- LightAttack1
			"rbxassetid://132519929912742",  -- LightAttack2
			-- 可继续添加更多连招动画
		},
		HeavyAttack = {
			-- 重攻击动画预留
		},
	},
	-- 可添加更多武器类型
	-- Sword = { LightAttack = {...}, HeavyAttack = {...} },
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
-- @param weaponType: 武器类型（可选，默认为"None"）
-- @return: AnimationManager实例
function AnimationManager.new(target, weaponType)
	local self = setmetatable({}, AnimationManager)

	-- 获取Character
	local character = getCharacter(target)
	if not character then
		warn("AnimationManager.new - Invalid target (not a Player or Character)")
		return nil
	end

	self.character = character
	self.animationTracks = {}
	self.attackTracks = {}  -- 攻击动画轨道（按类型分组）
	self.currentWeaponType = weaponType or "None"

	-- 加载基础动画
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

	-- 加载当前武器类型的攻击动画
	self:LoadAttackAnimations(self.currentWeaponType)

	-- 预加载动画资源
	local animationArray = {}
	for _, track in pairs(self.animationTracks) do
		table.insert(animationArray, track)
	end
	for _, trackList in pairs(self.attackTracks) do
		for _, track in ipairs(trackList) do
			table.insert(animationArray, track)
		end
	end

	if #animationArray > 0 then
		ContentProvider:PreloadAsync(animationArray)
	end

	return self
end

-- 加载指定武器类型的攻击动画
-- @param weaponType: 武器类型（如"None", "Sword"等）
function AnimationManager:LoadAttackAnimations(weaponType)
	self.currentWeaponType = weaponType
	self.attackTracks = {}

	local weaponAnims = ATTACK_ANIMATIONS[weaponType]
	if not weaponAnims then
		warn("AnimationManager:LoadAttackAnimations - Unknown weapon type: " .. tostring(weaponType))
		return
	end

	-- 加载该武器类型的所有攻击动画
	for attackType, animIds in pairs(weaponAnims) do
		self.attackTracks[attackType] = {}
		for i, animId in ipairs(animIds) do
			local success, track = pcall(function()
				return loadAnimationTrack(self.character, animId)
			end)

			if success and track then
				table.insert(self.attackTracks[attackType], track)
			else
				warn("Failed to load attack animation: " .. attackType .. "[" .. i .. "]")
			end
		end
	end
end

-- 获取攻击动画轨道
-- @param attackType: 攻击类型（如"LightAttack", "HeavyAttack"）
-- @param index: 连招索引（从1开始）
-- @return: 动画轨道对象，如果不存在返回nil
function AnimationManager:GetAttackTrack(attackType, index)
	local trackList = self.attackTracks[attackType]
	if not trackList then
		return nil
	end
	return trackList[index]
end

-- 获取攻击动画数量
-- @param attackType: 攻击类型
-- @return: 该类型的攻击动画数量
function AnimationManager:GetAttackCount(attackType)
	local trackList = self.attackTracks[attackType]
	if not trackList then
		return 0
	end
	return #trackList
end

-- 播放攻击动画（实例方法）
-- @param attackType: 攻击类型（如"LightAttack", "HeavyAttack"）
-- @param index: 连招索引（从1开始）
-- @param fadeTime: 淡入淡出时间，默认为0
-- @param priority: 动画优先级（可选）
-- @param looped: 是否循环播放（可选）
-- @return: 动画轨道对象，如果失败返回nil
function AnimationManager:PlayAttackAnimation(attackType, index, fadeTime, priority, looped)
	fadeTime = fadeTime or 0

	local track = self:GetAttackTrack(attackType, index)
	if not track then
		warn("AnimationManager:PlayAttackAnimation - Attack animation not found: " .. tostring(attackType) .. "[" .. tostring(index) .. "]")
		return nil
	end

	-- 设置可选属性
	if priority ~= nil then
		track.Priority = priority
	end
	if looped ~= nil then
		track.Looped = looped
	end

	track:Play(fadeTime)
	return track
end

-- 播放动画函数（实例方法）
-- @param animationName: 动画名称（从已加载的轨道中获取）
-- @param fadeTime: 淡入淡出时间，默认为0（无淡入淡出）
-- @param priority: 动画优先级（可选，如 Enum.AnimationPriority.Action）
-- @param looped: 是否循环播放（可选）
-- @return: 动画轨道对象，如果失败返回nil
function AnimationManager:PlayAnimation(animationName, fadeTime, priority, looped)
	fadeTime = fadeTime or 0

	-- 从已加载的轨道中获取
	local track = self.animationTracks[animationName]
	if not track then
		warn("AnimationManager:PlayAnimation - Animation not found: " .. tostring(animationName))
		return nil
	end

	-- 设置可选属性
	if priority ~= nil then
		track.Priority = priority
	end
	if looped ~= nil then
		track.Looped = looped
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

	-- 清理攻击动画轨道
	for _, trackList in pairs(self.attackTracks) do
		for _, track in ipairs(trackList) do
			if track.IsPlaying then
				track:Stop()
			end
		end
	end
	self.attackTracks = {}
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