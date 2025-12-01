--[[
	============================================================================
	ClientEntityManager.lua - 客户端镜像数据包管理器
	============================================================================

	职责：
	- 创建客户端镜像数据包（从服务器接收数据）
	- 接收服务器的 SyncAttribute 同步消息
	- 更新镜像数据包的值（触发事件，供组件监听）
	- 不执行 updateAll()（修改器计算由服务器负责）

	使用方式：
	local ClientEntityManager = require(ReplicatedStorage.ClientEntityManager)

	-- 创建镜像数据包
	local health = ClientEntityManager:CreateAttribute(player, "Health", {
		MaxValue = 100,
		RegenRate = 2
	})

	-- 获取数据包
	local health = ClientEntityManager:GetAttribute(player, "Health")

	注意：
	- 此模块只能在客户端运行
	- 服务器请勿使用此模块
	- 镜像数据包的值由服务器同步更新

	============================================================================
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- 引入数据包类
local LocalAttribute = require(ReplicatedStorage:WaitForChild("LocalAttribute"))
local MirrorAttribute = require(ReplicatedStorage:WaitForChild("MirrorAttribute"))

-- ============================================================================
-- ClientEntityManager 模块
-- ============================================================================

local ClientEntityManager = {
	_localPlayerAttributes = {},  -- { [attributeName] = LocalAttribute } - 本地玩家的数据包（完整功能）
	_mirrorAttributes = {},  -- { [owner] = { [attributeName] = MirrorAttribute } } - 其他实体的镜像数据包
	_syncRemote = nil,  -- RemoteEvent for receiving sync from server
	_updateConnection = nil,  -- Client-side prediction update loop
}

-- ============================================================================
-- 核心方法
-- ============================================================================

--[[
	为指定实体创建客户端数据包
	@param owner: 拥有者（Player 或 Character）
	@param attributeName: 数据包名称（如 "Stamina", "Health"）
	@param config: 配置表（传递给 LocalAttribute 或 MirrorAttribute）
	@return: LocalAttribute 或 MirrorAttribute 实例
]]
function ClientEntityManager:CreateAttribute(owner, attributeName, config)
	-- 客户端验证
	if not RunService:IsClient() then
		error("[ClientEntityManager] This module can only be used on the client!")
	end

	-- 获取本地玩家
	local localPlayer = Players.LocalPlayer

	-- 判断是本地玩家还是其他实体
	local isLocalPlayer = (owner == localPlayer)

	if isLocalPlayer then
		-- 本地玩家：创建 LocalAttribute（完整功能，用于客户端预测）
		if self._localPlayerAttributes[attributeName] then
			warn("[ClientEntityManager] Local player attribute already exists:", attributeName)
			return self._localPlayerAttributes[attributeName]
		end

		local attribute = LocalAttribute.new(owner, attributeName, config)
		self._localPlayerAttributes[attributeName] = attribute

		print(string.format("[ClientEntityManager] Created LocalAttribute: %s (Client Prediction)",
			attributeName))

		return attribute
	else
		-- 其他实体：创建 MirrorAttribute（阉割版，只接收服务器广播）
		if not self._mirrorAttributes[owner] then
			self._mirrorAttributes[owner] = {}
		end

		if self._mirrorAttributes[owner][attributeName] then
			warn(string.format("[ClientEntityManager] Mirror attribute already exists: %s.%s",
				tostring(owner), attributeName))
			return self._mirrorAttributes[owner][attributeName]
		end

		local attribute = MirrorAttribute.new(owner, attributeName, config)
		self._mirrorAttributes[owner][attributeName] = attribute

		print(string.format("[ClientEntityManager] Created MirrorAttribute: %s.%s (Broadcast Only)",
			tostring(owner), attributeName))

		return attribute
	end
end

--[[
	获取指定实体的数据包
	@param owner: 拥有者
	@param attributeName: 数据包名称
	@return: LocalAttribute 或 MirrorAttribute 实例，如果不存在返回 nil
]]
function ClientEntityManager:GetAttribute(owner, attributeName)
	local localPlayer = Players.LocalPlayer

	-- 判断是本地玩家还是其他实体
	if owner == localPlayer then
		return self._localPlayerAttributes[attributeName]
	else
		if self._mirrorAttributes[owner] then
			return self._mirrorAttributes[owner][attributeName]
		end
	end

	return nil
end

--[[
	获取指定实体的所有数据包
	@param owner: 拥有者
	@return: 数据包表 { [attributeName] = Attribute }
]]
function ClientEntityManager:GetAllAttributes(owner)
	local localPlayer = Players.LocalPlayer

	-- 判断是本地玩家还是其他实体
	if owner == localPlayer then
		return self._localPlayerAttributes
	else
		return self._mirrorAttributes[owner] or {}
	end
end

--[[
	清理指定实体的所有数据包
	@param owner: 拥有者
]]
function ClientEntityManager:CleanupEntity(owner)
	local localPlayer = Players.LocalPlayer

	-- 判断是本地玩家还是其他实体
	if owner == localPlayer then
		-- 清理本地玩家数据包
		for _, attr in pairs(self._localPlayerAttributes) do
			attr:Destroy()
		end
		self._localPlayerAttributes = {}
		print("[ClientEntityManager] Cleaned up local player attributes")
	else
		-- 清理镜像数据包
		if self._mirrorAttributes[owner] then
			for _, attr in pairs(self._mirrorAttributes[owner]) do
				attr:Destroy()
			end
			self._mirrorAttributes[owner] = nil
			print(string.format("[ClientEntityManager] Cleaned up mirror attributes for: %s", tostring(owner)))
		end
	end
end

--[[
	清理指定实体的单个数据包
	@param owner: 拥有者
	@param attributeName: 数据包名称
]]
function ClientEntityManager:CleanupAttribute(owner, attributeName)
	local localPlayer = Players.LocalPlayer

	-- 判断是本地玩家还是其他实体
	if owner == localPlayer then
		if self._localPlayerAttributes[attributeName] then
			self._localPlayerAttributes[attributeName]:Destroy()
			self._localPlayerAttributes[attributeName] = nil
		end
	else
		if self._mirrorAttributes[owner] and self._mirrorAttributes[owner][attributeName] then
			self._mirrorAttributes[owner][attributeName]:Destroy()
			self._mirrorAttributes[owner][attributeName] = nil
		end
	end
end

-- ============================================================================
-- 网络同步接收
-- ============================================================================

--[[
	接收服务器同步（内部方法）
	@param data: 服务器发送的同步数据
		- owner: 数据包的拥有者
		- attributeName: 数据包名称
		- currentValue: 当前值
		- maxValue: 最大值
		- percentage: 百分比
		- change: 变化量
]]
local function onServerSync(data)
	local localPlayer = Players.LocalPlayer

	-- 判断是本地玩家还是其他实体
	local isLocalPlayer = (data.owner == localPlayer)

	local attribute
	if isLocalPlayer then
		-- 获取本地玩家的 LocalAttribute
		attribute = ClientEntityManager._localPlayerAttributes[data.attributeName]
	else
		-- 获取其他实体的 MirrorAttribute
		if ClientEntityManager._mirrorAttributes[data.owner] then
			attribute = ClientEntityManager._mirrorAttributes[data.owner][data.attributeName]
		end
	end

	if not attribute then
		-- 如果数据包不存在，自动创建（服务器先创建，客户端接收广播后自动同步）
		local config = {
			MaxValue = data.maxValue,
			CurrentValue = data.currentValue
		}
		attribute = ClientEntityManager:CreateAttribute(data.owner, data.attributeName, config)
		return
	end

	if isLocalPlayer then
		-- 本地玩家：检查客户端预测值与服务器权威值的差异
		local predictionError = math.abs(attribute.CurrentValue - data.currentValue)

		-- 如果差异大于阈值，校正客户端值
		local ERROR_THRESHOLD = 0.5  -- 误差阈值
		if predictionError > ERROR_THRESHOLD then
			-- 预测错误，需要校正
			print(string.format("[ClientEntityManager] Correcting %s: %.2f → %.2f (error: %.2f)",
				data.attributeName,
				attribute.CurrentValue,
				data.currentValue,
				predictionError
				))

			-- 使用 SetValue 平滑校正（会触发 Changed 事件）
			attribute:SetValue(data.currentValue)
		end
		-- 如果预测准确（误差小），不需要校正，避免不必要的同步
	else
		-- 其他实体：直接更新 MirrorAttribute 的值
		attribute:SetValue(data.currentValue)
	end
end

-- ============================================================================
-- 客户端预测更新循环
-- ============================================================================

-- 累积时间优化（降低更新频率）
local UPDATE_INTERVAL = 0.05  -- 每 0.05 秒更新一次（20Hz，肉眼不可见）
local accumulatedTime = 0

--[[
	客户端预测更新循环（与服务器并行计算）
	- 执行修改器更新
	- 执行自动恢复
	- 等待服务器同步校正
	- 只更新本地玩家的数据包
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

	-- 只更新本地玩家的数据包
	for attributeName, attribute in pairs(ClientEntityManager._localPlayerAttributes) do
		-- 客户端预测：执行修改器和自动恢复
		attribute:Update(updateDelta)
	end
end

-- ============================================================================
-- 初始化
-- ============================================================================

local function init()
	-- 只在客户端初始化
	if not RunService:IsClient() then
		error("[ClientEntityManager] This module can only be required on the client!")
	end

	-- 获取 RemoteEvent
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	if not remoteEvents then
		error("[ClientEntityManager] RemoteEvents folder not found in ReplicatedStorage!")
	end

	ClientEntityManager._syncRemote = remoteEvents:WaitForChild("SyncAttribute", 10)
	if not ClientEntityManager._syncRemote then
		error("[ClientEntityManager] SyncAttribute RemoteEvent not found!")
	end

	-- 监听服务器的同步消息
	ClientEntityManager._syncRemote.OnClientEvent:Connect(onServerSync)

	-- 启动客户端预测更新循环
	if ClientEntityManager._updateConnection then
		ClientEntityManager._updateConnection:Disconnect()
	end

	ClientEntityManager._updateConnection = RunService.Heartbeat:Connect(updateAll)

	print("[ClientEntityManager] Initialized (Client Prediction)")
	print("[ClientEntityManager] - Listening for server sync messages")
	print("[ClientEntityManager] - Client prediction enabled")
	print(string.format("[ClientEntityManager] Update interval: %.2fs (%.0fHz)", UPDATE_INTERVAL, 1/UPDATE_INTERVAL))
end

-- 自动初始化
init()

return ClientEntityManager
