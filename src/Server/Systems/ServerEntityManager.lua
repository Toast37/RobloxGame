--[[
	============================================================================
	ServerEntityManager.lua - 服务器权威数据包管理器
	============================================================================

	职责：
	- 创建服务器权威数据包（唯一真实数据源）
	- 执行 updateAll() 更新循环（修改器、自动恢复）
	- 监听数据包事件，数据变化时同步给客户端
	- 管理所有玩家的数据包

	使用方式：
	local ServerEntityManager = require(script.ServerEntityManager)

	-- 创建数据包
	local health = ServerEntityManager:CreateAttribute(player, "Health", {
		MaxValue = 100,
		RegenRate = 2
	})

	-- 获取数据包
	local health = ServerEntityManager:GetAttribute(player, "Health")

	注意：
	- 此模块只能在服务器端运行
	- 客户端请勿使用此模块

	============================================================================
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- 引入 LocalAttribute 类（服务器只使用完整功能的 LocalAttribute）
local LocalAttribute = require(script.Parent:WaitForChild("LocalAttribute"))

-- ============================================================================
-- ServerEntityManager 模块
-- ============================================================================

local ServerEntityManager = {
	_playerInstances = {},  -- { [player] = { [attributeName] = Attribute } }
	_npcInstances = {},     -- { [npc] = { [attributeName] = Attribute } }
	_updateConnection = nil,
	_syncRemote = nil,  -- RemoteEvent for syncing to clients
}

-- ============================================================================
-- 核心方法
-- ============================================================================

--[[
	为指定实体创建服务器权威数据包
	@param owner: 拥有者（Player 或 Character）
	@param attributeName: 数据包名称（如 "Stamina", "Health"）
	@param config: 配置表（传递给 Attribute.new）
	@return: Attribute 实例
]]
function ServerEntityManager:CreateAttribute(owner, attributeName, config)
	-- 服务器端验证
	if not RunService:IsServer() then
		error("[ServerEntityManager] This module can only be used on the server!")
	end

	-- 判断是玩家数据包还是 NPC 数据包
	local isPlayer = owner:IsA("Player")
	local instanceContainer = isPlayer and self._playerInstances or self._npcInstances
	local entityType = isPlayer and "Player" or "NPC"

	-- 初始化实体的数据包容器
	if not instanceContainer[owner] then
		instanceContainer[owner] = {}
	end

	-- 检查是否已存在
	if instanceContainer[owner][attributeName] then
		warn(string.format("[ServerEntityManager] Attribute already exists: %s.%s (%s)",
			tostring(owner), attributeName, entityType))
		return instanceContainer[owner][attributeName]
	end

	-- 创建数据包实例（使用 LocalAttribute）
	local attribute = LocalAttribute.new(owner, attributeName, config)
	instanceContainer[owner][attributeName] = attribute

	-- 监听数据包的 "Changed" 事件，同步给客户端
	attribute:OnEvent("Changed", function(data)
		self:SyncToClient(owner, attributeName, data)
	end)

	print(string.format("[ServerEntityManager] Created attribute: %s.%s (Server Authority, %s)",
		tostring(owner), attributeName, entityType))

	return attribute
end

--[[
	获取指定实体的数据包
	@param owner: 拥有者
	@param attributeName: 数据包名称
	@return: Attribute 实例，如果不存在返回 nil
]]
function ServerEntityManager:GetAttribute(owner, attributeName)
	local isPlayer = owner:IsA("Player")
	local instanceContainer = isPlayer and self._playerInstances or self._npcInstances

	if instanceContainer[owner] then
		return instanceContainer[owner][attributeName]
	end
	return nil
end

--[[
	获取指定实体的所有数据包
	@param owner: 拥有者
	@return: 数据包表 { [attributeName] = Attribute }
]]
function ServerEntityManager:GetAllAttributes(owner)
	local isPlayer = owner:IsA("Player")
	local instanceContainer = isPlayer and self._playerInstances or self._npcInstances

	return instanceContainer[owner] or {}
end

--[[
	清理指定实体的所有数据包
	@param owner: 拥有者
]]
function ServerEntityManager:CleanupEntity(owner)
	local isPlayer = owner:IsA("Player")
	local instanceContainer = isPlayer and self._playerInstances or self._npcInstances
	local entityType = isPlayer and "Player" or "NPC"

	if instanceContainer[owner] then
		for _, attr in pairs(instanceContainer[owner]) do
			attr:Destroy()
		end
		instanceContainer[owner] = nil
		print(string.format("[ServerEntityManager] Cleaned up entity: %s (%s)", tostring(owner), entityType))
	end
end

--[[
	清理指定实体的单个数据包
	@param owner: 拥有者
	@param attributeName: 数据包名称
]]
function ServerEntityManager:CleanupAttribute(owner, attributeName)
	local isPlayer = owner:IsA("Player")
	local instanceContainer = isPlayer and self._playerInstances or self._npcInstances

	if instanceContainer[owner] and instanceContainer[owner][attributeName] then
		instanceContainer[owner][attributeName]:Destroy()
		instanceContainer[owner][attributeName] = nil
	end
end

-- ============================================================================
-- 网络同步
-- ============================================================================

--[[
	同步数据到所有客户端（全局广播）
	@param owner: 拥有者（Player 或 NPC）
	@param attributeName: 数据包名称
	@param data: 数据包的 Changed 事件数据
]]
function ServerEntityManager:SyncToClient(owner, attributeName, data)
	-- 获取 RemoteEvent
	if not self._syncRemote then
		local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if remoteEvents then
			self._syncRemote = remoteEvents:FindFirstChild("SyncAttribute")
		end

		if not self._syncRemote then
			warn("[ServerEntityManager] SyncAttribute RemoteEvent not found!")
			return
		end
	end

	-- 构建同步数据
	local syncData = {
		owner = owner,  -- 添加 owner 信息，让客户端知道是哪个实体的数据包
		attributeName = attributeName,
		currentValue = data.currentValue,
		maxValue = data.maxValue,
		percentage = data.percentage,
		change = data.change,
	}

	-- 全局广播给所有客户端
	local success, err = pcall(function()
		self._syncRemote:FireAllClients(syncData)
	end)

	if not success then
		warn("[ServerEntityManager] Failed to broadcast to all clients:", err)
	end
end

-- ============================================================================
-- 服务器权威更新循环
-- ============================================================================

-- 累积时间优化（降低更新频率）
local UPDATE_INTERVAL = 0.05  -- 每 0.05 秒更新一次（20Hz，肉眼不可见）
local accumulatedTime = 0

--[[
	统一的更新循环（更新所有数据包）
	只在服务器执行
	优化：通过累积时间减少更新频率，降低性能开销
]]
local function updateAll(deltaTime)
	-- 累积时间
	accumulatedTime = accumulatedTime + deltaTime

	-- 只在累积时间超过更新间隔时才执行更新
	if accumulatedTime < UPDATE_INTERVAL then
		return
	end

	-- 使用累积的时间作为 deltaTime
	local updateDelta = accumulatedTime
	accumulatedTime = 0  -- 重置累积时间

	-- 更新所有玩家数据包
	for player, attributes in pairs(ServerEntityManager._playerInstances) do
		for attributeName, attribute in pairs(attributes) do
			attribute:Update(updateDelta)
		end
	end

	-- 更新所有 NPC 数据包
	for npc, attributes in pairs(ServerEntityManager._npcInstances) do
		for attributeName, attribute in pairs(attributes) do
			attribute:Update(updateDelta)
		end
	end
end

-- ============================================================================
-- 初始化
-- ============================================================================

local function init()
	-- 只在服务器端初始化
	if not RunService:IsServer() then
		error("[ServerEntityManager] This module can only be required on the server!")
	end

	-- 启动统一的更新循环（服务器权威）
	if ServerEntityManager._updateConnection then
		ServerEntityManager._updateConnection:Disconnect()
	end

	ServerEntityManager._updateConnection = RunService.Heartbeat:Connect(updateAll)

	print("[ServerEntityManager] Initialized (Server Authority)")
	print("[ServerEntityManager] Update loop started on server")
	print(string.format("[ServerEntityManager] Update interval: %.2fs (%.0fHz)", UPDATE_INTERVAL, 1/UPDATE_INTERVAL))
end

-- 自动初始化
init()

return ServerEntityManager
