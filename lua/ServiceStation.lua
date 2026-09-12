ServiceStation = ServiceStation or {}

local Service = ServiceStation
local BASE_KEY = "placeable.ServiceStation"
local ROOT_KEY_MODE = Service.CONFIG_MODE or "ServiceStationMode"
local ROOT_KEY_WIDTH = Service.CONFIG_WIDTH or "ServiceStationWidth"
local ROOT_KEY_LENGTH = Service.CONFIG_LENGTH or "ServiceStationLength"
local ENERGY_UPDATE_INTERVAL_MS = 1000
local FILL_EPSILON = 0.0001
local DEFAULT_WIDTH_METERS = 10
local DEFAULT_LENGTH_METERS = 20
local STRIPE_LENGTHS_METERS = { 0.5, 1, 2, 4, 6, 8, 10, 15, 20, 25, 30, 35, 40 }
local STRIPE_WIDTH_METERS = 0.25
local TRIGGER_MARGIN_METERS = 0.5
local TRIGGER_MIN_LENGTH_METERS = 2
local SCALE_EPSILON = 0.0001

local function getStripeLengthIndex(length)
    local bestIndex = 1
    local bestDistance = math.huge

    for index, stripeLength in ipairs(STRIPE_LENGTHS_METERS) do
        local distance = math.abs(length - stripeLength)
        if distance < bestDistance then
            bestIndex = index
            bestDistance = distance
        end
    end

    return bestIndex
end

local function setPhysicsNodeScale(node, scaleX, scaleY, scaleZ)
    local currentX, currentY, currentZ = getScale(node)
    if
        math.abs(currentX - scaleX) <= SCALE_EPSILON
        and math.abs(currentY - scaleY) <= SCALE_EPSILON
        and math.abs(currentZ - scaleZ) <= SCALE_EPSILON
    then
        return
    end

    local wasAddedToPhysics = getIsAddedToPhysics(node)
    if wasAddedToPhysics then
        removeFromPhysics(node)
    end

    setScale(node, scaleX, scaleY, scaleZ)

    if wasAddedToPhysics then
        addToPhysics(node)
    end
end

function Service.prerequisitesPresent(specializations)
    return true
end

function Service.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("ServiceStation")
    schema:register(
        XMLValueType.NODE_INDEX,
        basePath .. ".ServiceStation#triggerNode",
        "Automatic service trigger node"
    )
    schema:register(
        XMLValueType.NODE_INDEX,
        basePath .. ".ServiceStation#selectionNode",
        "Construction mode selection node"
    )
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".ServiceStation#stripeLeftNode", "Left warning stripe node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".ServiceStation#stripeRightNode", "Right warning stripe node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".ServiceStation#clearAreaStartNode", "Clear area start node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".ServiceStation#clearAreaWidthNode", "Clear area width node")
    schema:register(
        XMLValueType.NODE_INDEX,
        basePath .. ".ServiceStation#clearAreaHeightNode",
        "Clear area height node"
    )
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".ServiceStation#levelAreaStartNode", "Level area start node")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".ServiceStation#levelAreaWidthNode", "Level area width node")
    schema:register(
        XMLValueType.NODE_INDEX,
        basePath .. ".ServiceStation#levelAreaHeightNode",
        "Level area height node"
    )
    schema:register(
        XMLValueType.NODE_INDEX,
        basePath .. ".ServiceStation#testAreaStartNode",
        "Placement test area start node"
    )
    schema:register(
        XMLValueType.NODE_INDEX,
        basePath .. ".ServiceStation#testAreaEndNode",
        "Placement test area end node"
    )
    schema:register(
        XMLValueType.FLOAT,
        basePath .. ".ServiceStation#baseWashPrice",
        "Price for completely washing one dirty vehicle before the global price multiplier",
        10
    )
    schema:register(
        XMLValueType.FLOAT,
        basePath .. ".ServiceStation#baseDieselLitersPerSecond",
        "Base diesel fill speed before configuration multipliers",
        20
    )
    schema:register(
        XMLValueType.FLOAT,
        basePath .. ".ServiceStation#baseMethaneUnitsPerSecond",
        "Base methane fill speed before configuration multipliers",
        2
    )
    schema:register(
        XMLValueType.FLOAT,
        basePath .. ".ServiceStation#baseChargeUnitsPerSecond",
        "Base electric charge speed before configuration multipliers",
        0.015
    )
    schema:setXMLSpecializationType()
end

function Service.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationTriggerCallback",
        Service.ServiceStationTriggerCallback
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationGetConfigurationItem",
        Service.ServiceStationGetConfigurationItem
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationLoadSelectedServiceOptions",
        Service.ServiceStationLoadSelectedServiceOptions
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationApplyDimensions",
        Service.ServiceStationApplyDimensions
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationGetRootVehicle",
        Service.ServiceStationGetRootVehicle
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationGetVehicleChain",
        Service.ServiceStationGetVehicleChain
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationGetVehicleFarmId",
        Service.ServiceStationGetVehicleFarmId
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationGetCanServiceVehicle",
        Service.ServiceStationGetCanServiceVehicle
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationSetupAutoDriveRefuelTrigger",
        Service.ServiceStationSetupAutoDriveRefuelTrigger
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationDeleteAutoDriveRefuelTrigger",
        Service.ServiceStationDeleteAutoDriveRefuelTrigger
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationUpdateAutoDriveRefuelTrigger",
        Service.ServiceStationUpdateAutoDriveRefuelTrigger
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationRefreshActiveRoots",
        Service.ServiceStationRefreshActiveRoots
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationProcessInstantChain",
        Service.ServiceStationProcessInstantChain
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationFillEnergyChain",
        Service.ServiceStationFillEnergyChain
    )
    SpecializationUtil.registerFunction(placeableType, "ServiceStationWashVehicle", Service.ServiceStationWashVehicle)
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationRepairVehicle",
        Service.ServiceStationRepairVehicle
    )
    SpecializationUtil.registerFunction(
        placeableType,
        "ServiceStationRepaintVehicle",
        Service.ServiceStationRepaintVehicle
    )
    SpecializationUtil.registerFunction(placeableType, "ServiceStationFillConsumer", Service.ServiceStationFillConsumer)
end

function Service.registerOverwrittenFunctions(placeableType)
    SpecializationUtil.registerOverwrittenFunction(
        placeableType,
        "collectPickObjects",
        Service.ServiceStationCollectPickObjects
    )
end

function Service.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", Service)
    SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", Service)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", Service)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate", Service)
end

local function getTimeMillis()
    if g_currentMission ~= nil and g_currentMission.time ~= nil then
        return g_currentMission.time
    end

    if getTimeSec ~= nil then
        return getTimeSec() * 1000
    end

    return 0
end

local function getScaledPrice(price)
    return math.max(tonumber(price) or 0, 0) * Service.getPriceFactor()
end

local function getFillTypePricePerLiter(fillTypeIndex)
    local economyManager = g_currentMission ~= nil and g_currentMission.economyManager or nil
    if economyManager == nil or economyManager.getPricePerLiter == nil then
        return 0
    end

    return math.max(tonumber(economyManager:getPricePerLiter(fillTypeIndex)) or 0, 0)
end

local function chargeFarm(farmId, price, moneyType, showMoneyChange, updateExpenses)
    price = getScaledPrice(price)
    if price <= 0 or g_currentMission == nil then
        return 0
    end

    if updateExpenses and g_farmManager ~= nil then
        g_farmManager:updateFarmStats(farmId, "expenses", price)
    end

    g_currentMission:addMoney(-price, farmId, moneyType, showMoneyChange ~= false, true)
    return price
end

local function getRootKey(rootVehicle)
    if rootVehicle == nil then
        return nil
    end

    return rootVehicle.rootNode or rootVehicle.id
end

local function isVehicleObjectValid(vehicle)
    return vehicle ~= nil
        and vehicle.isDeleting ~= true
        and vehicle.isDeleted ~= true
        and vehicle.markedForDeletion ~= true
        and vehicle.rootNode ~= nil
        and vehicle.rootNode ~= 0
end

local function getVehicleMaxDirtAmount(vehicle)
    local washableSpec = vehicle ~= nil and vehicle.spec_washable or nil
    if washableSpec ~= nil and washableSpec.washableNodes ~= nil then
        local maxDirtAmount = 0
        for _, nodeData in ipairs(washableSpec.washableNodes) do
            maxDirtAmount = math.max(maxDirtAmount, tonumber(nodeData.dirtAmount) or 0)
        end
        return maxDirtAmount
    end

    if vehicle ~= nil and vehicle.getDirtAmount ~= nil then
        return math.max(tonumber(vehicle:getDirtAmount()) or 0, 0)
    end

    return 0
end

local function getVehicleChainHash(rootVehicle)
    if rootVehicle ~= nil and rootVehicle.getChildVehicleHash ~= nil then
        local chainHash = rootVehicle:getChildVehicleHash()
        if chainHash ~= nil then
            return tostring(chainHash)
        end
    end

    local vehicleKeys = {}
    if rootVehicle ~= nil and rootVehicle.getChildVehicles ~= nil then
        for _, vehicle in ipairs(rootVehicle:getChildVehicles() or {}) do
            vehicleKeys[#vehicleKeys + 1] = tostring(vehicle.id or vehicle.rootNode or vehicle)
        end
    end
    table.sort(vehicleKeys)
    return table.concat(vehicleKeys, ":")
end

local function removeTriggerNodeObject(self, otherId, removeListener)
    local spec = self.spec_ServiceStation
    local vehicle = spec.triggerNodeObjects[otherId]
    if vehicle == nil then
        return
    end

    spec.triggerNodeObjects[otherId] = nil
    local count = (spec.triggerVehicles[vehicle] or 1) - 1
    if count <= 0 then
        spec.triggerVehicles[vehicle] = nil
        spec.triggerSessionVehicles[vehicle] = nil
        if removeListener ~= false and vehicle.removeDeleteListener ~= nil then
            vehicle:removeDeleteListener(self, Service.ServiceStationOnVehicleDeleted)
        end
    else
        spec.triggerVehicles[vehicle] = count
    end
end

local function getServiceStationNode(self, attributeName)
    local nodePath = getXMLString(self.xmlFile.handle, string.format("%s#%s", BASE_KEY, attributeName))
    if nodePath == nil then
        return nil
    end

    return I3DUtil.indexToObject(self.components, nodePath, self.i3dMappings)
end

function Service:onLoad(savegame)
    self.spec_ServiceStation = {}
    local spec = self.spec_ServiceStation

    spec.triggerNode = getServiceStationNode(self, "triggerNode")
    spec.autoDriveTriggerNode = getServiceStationNode(self, "autoDriveTriggerNode")
    spec.selectionNode = getServiceStationNode(self, "selectionNode")
    spec.stripeLeftNode = getServiceStationNode(self, "stripeLeftNode")
    spec.stripeRightNode = getServiceStationNode(self, "stripeRightNode")
    spec.clearAreaStartNode = getServiceStationNode(self, "clearAreaStartNode")
    spec.clearAreaWidthNode = getServiceStationNode(self, "clearAreaWidthNode")
    spec.clearAreaHeightNode = getServiceStationNode(self, "clearAreaHeightNode")
    spec.levelAreaStartNode = getServiceStationNode(self, "levelAreaStartNode")
    spec.levelAreaWidthNode = getServiceStationNode(self, "levelAreaWidthNode")
    spec.levelAreaHeightNode = getServiceStationNode(self, "levelAreaHeightNode")
    spec.testAreaStartNode = getServiceStationNode(self, "testAreaStartNode")
    spec.testAreaEndNode = getServiceStationNode(self, "testAreaEndNode")

    spec.baseDieselLitersPerSecond =
        math.max(getXMLFloat(self.xmlFile.handle, BASE_KEY .. "#baseDieselLitersPerSecond") or 20, 0)
    spec.baseMethaneUnitsPerSecond =
        math.max(getXMLFloat(self.xmlFile.handle, BASE_KEY .. "#baseMethaneUnitsPerSecond") or 2, 0)
    spec.baseChargeUnitsPerSecond =
        math.max(getXMLFloat(self.xmlFile.handle, BASE_KEY .. "#baseChargeUnitsPerSecond") or 0.015, 0)
    spec.baseWashPrice = math.max(getXMLFloat(self.xmlFile.handle, BASE_KEY .. "#baseWashPrice") or 10, 0)
    spec.triggerNodeObjects = {}
    spec.triggerVehicles = {}
    spec.triggerSessionVehicles = {}
    spec.activeRoots = {}
    spec.activeRootHashes = {}
    spec.lastServiceTimes = setmetatable({}, { __mode = "k" })
    spec.fillCompletedRoots = {}
    spec.electricCompletedRoots = {}
    spec.energyAccumulatorMs = {}
    spec.autoDriveRefuelTrigger = nil
    spec.autoDriveLoadingStation = nil
    spec.autoDrivePreviousLoadingStation = nil

    self:ServiceStationLoadSelectedServiceOptions()
    self:ServiceStationApplyDimensions()
end

function Service:onFinalizePlacement()
    local spec = self.spec_ServiceStation
    if self.isServer and spec.triggerNode ~= nil then
        addTrigger(spec.triggerNode, "ServiceStationTriggerCallback", self)
        self:ServiceStationSetupAutoDriveRefuelTrigger()
    end
end

function Service:onDelete()
    local spec = self.spec_ServiceStation
    if self.isServer and spec ~= nil then
        self:ServiceStationDeleteAutoDriveRefuelTrigger()
    end

    if self.isServer and spec ~= nil and spec.triggerNode ~= nil then
        removeTrigger(spec.triggerNode)
    end

    if self.isServer and spec ~= nil and spec.triggerVehicles ~= nil then
        for vehicle in pairs(spec.triggerVehicles) do
            if vehicle.removeDeleteListener ~= nil then
                vehicle:removeDeleteListener(self, Service.ServiceStationOnVehicleDeleted)
            end
        end
    end
end

function Service:ServiceStationCollectPickObjects(superFunc, node)
    local spec = self.spec_ServiceStation
    if spec == nil or (node ~= spec.triggerNode and node ~= spec.autoDriveTriggerNode) then
        superFunc(self, node)
    end
end

function Service:ServiceStationGetConfigurationItem(configName)
    local configId = self.configurations ~= nil and self.configurations[configName] or nil
    if configId == nil and g_storeManager ~= nil then
        local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)
        if storeItem ~= nil and storeItem.defaultConfigurationIds ~= nil then
            configId = storeItem.defaultConfigurationIds[configName]
        end
    end

    return ConfigurationUtil.getConfigItemByConfigId(self.configFileName, configName, configId)
end

function Service:ServiceStationLoadSelectedServiceOptions()
    local spec = self.spec_ServiceStation
    local modeItem = self:ServiceStationGetConfigurationItem(ROOT_KEY_MODE)

    spec.wash = modeItem == nil or modeItem.wash == true
    spec.repair = modeItem == nil or modeItem.repair == true
    spec.repaint = modeItem == nil or modeItem.repaint == true
    spec.energyDiesel = modeItem == nil or modeItem.diesel == true
    spec.energyElectric = modeItem == nil or modeItem.electric == true
    spec.energyMethane = modeItem == nil or modeItem.methane == true
end

function Service:ServiceStationApplyDimensions()
    local spec = self.spec_ServiceStation
    local widthItem = self:ServiceStationGetConfigurationItem(ROOT_KEY_WIDTH)
    local lengthItem = self:ServiceStationGetConfigurationItem(ROOT_KEY_LENGTH)
    local width = math.clamp(tonumber(widthItem ~= nil and widthItem.meters) or DEFAULT_WIDTH_METERS, 2, 20)
    local length = math.clamp(tonumber(lengthItem ~= nil and lengthItem.meters) or DEFAULT_LENGTH_METERS, 0.5, 40)
    local stripeOffset = width * 0.5 + STRIPE_WIDTH_METERS * 0.5
    local stripeLengthIndex = getStripeLengthIndex(length)
    local visibleWidth = width + STRIPE_WIDTH_METERS * 2
    local triggerLength = math.max(length + TRIGGER_MARGIN_METERS * 2, TRIGGER_MIN_LENGTH_METERS)
    local triggerWidth = visibleWidth + TRIGGER_MARGIN_METERS * 2

    spec.widthMeters = width
    spec.lengthMeters = length

    for _, stripeData in ipairs({
        { node = spec.stripeLeftNode, offset = -stripeOffset },
        { node = spec.stripeRightNode, offset = stripeOffset },
    }) do
        if stripeData.node ~= nil then
            setTranslation(stripeData.node, 0, 0, stripeData.offset)
            setScale(stripeData.node, 1, 1, 1)

            for childIndex = 0, getNumOfChildren(stripeData.node) - 1 do
                setVisibility(getChildAt(stripeData.node, childIndex), childIndex + 1 == stripeLengthIndex)
            end
        end
    end

    if spec.triggerNode ~= nil then
        setPhysicsNodeScale(spec.triggerNode, triggerLength, 1, triggerWidth)
    end

    if spec.selectionNode ~= nil then
        setPhysicsNodeScale(spec.selectionNode, length, 0.025, visibleWidth)
    end

    if spec.clearAreaStartNode ~= nil then
        setTranslation(spec.clearAreaStartNode, length * 0.5, 0, -visibleWidth * 0.5)
    end
    if spec.clearAreaWidthNode ~= nil then
        setTranslation(spec.clearAreaWidthNode, 0, 0, visibleWidth)
    end
    if spec.clearAreaHeightNode ~= nil then
        setTranslation(spec.clearAreaHeightNode, -length, 0, 0)
    end

    if spec.levelAreaStartNode ~= nil then
        setTranslation(spec.levelAreaStartNode, -length * 0.5, 0, -visibleWidth * 0.5)
    end
    if spec.levelAreaWidthNode ~= nil then
        setTranslation(spec.levelAreaWidthNode, 0, 0, visibleWidth)
    end
    if spec.levelAreaHeightNode ~= nil then
        setTranslation(spec.levelAreaHeightNode, length, 0, 0)
    end

    if spec.testAreaStartNode ~= nil then
        setTranslation(spec.testAreaStartNode, length * 0.5, 0, -visibleWidth * 0.5)
    end
    if spec.testAreaEndNode ~= nil then
        setTranslation(spec.testAreaEndNode, -length, 6, visibleWidth)
    end

    local placementSpec = self.spec_placement
    if placementSpec ~= nil and self.loadTestArea ~= nil then
        placementSpec.testAreas = {}
        self.xmlFile:iterate("placeable.placement.testAreas.testArea", function(_, key)
            local testArea = {}
            if self:loadTestArea(self.xmlFile, key, testArea) then
                table.insert(placementSpec.testAreas, testArea)
            end
        end)
    end
end

function Service:ServiceStationGetRootVehicle(vehicle)
    if vehicle == nil then
        return nil
    end

    if vehicle.getRootVehicle ~= nil then
        local rootVehicle = vehicle:getRootVehicle()
        if rootVehicle ~= nil then
            return rootVehicle
        end
    end

    return vehicle.rootVehicle or vehicle
end

function Service:ServiceStationGetVehicleChain(rootVehicle)
    if rootVehicle == nil then
        return {}
    end

    if rootVehicle.getChildVehicles ~= nil then
        local vehicles = rootVehicle:getChildVehicles()
        if vehicles ~= nil and #vehicles > 0 then
            return vehicles
        end
    end

    return { rootVehicle }
end

function Service:ServiceStationGetVehicleFarmId(vehicle)
    if vehicle ~= nil and vehicle.getOwnerFarmId ~= nil then
        local farmId = vehicle:getOwnerFarmId()
        if farmId ~= nil then
            return farmId
        end
    end

    if self.getOwnerFarmId ~= nil then
        return self:getOwnerFarmId()
    end

    return 1
end

function Service:ServiceStationGetCanServiceVehicle(vehicle)
    if not isVehicleObjectValid(vehicle) then
        return false
    end

    if Service.settings.requireFarmAccess ~= false then
        local accessHandler = g_currentMission ~= nil and g_currentMission.accessHandler or nil
        if accessHandler ~= nil and accessHandler.canFarmAccess ~= nil then
            local farmId = self:ServiceStationGetVehicleFarmId(vehicle)
            if accessHandler:canFarmAccess(farmId, self) == false then
                return false
            end
        end
    end

    return true
end

function Service:ServiceStationTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if not self.isServer or not (onEnter or onLeave) then
        return
    end

    local spec = self.spec_ServiceStation
    local vehicle = g_currentMission ~= nil and g_currentMission:getNodeObject(otherId) or nil

    if onEnter then
        if not isVehicleObjectValid(vehicle) then
            return
        end

        local previousVehicle = spec.triggerNodeObjects[otherId]
        if previousVehicle ~= nil and previousVehicle ~= vehicle then
            removeTriggerNodeObject(self, otherId, true)
        end

        if spec.triggerNodeObjects[otherId] == nil then
            spec.triggerNodeObjects[otherId] = vehicle
            local count = spec.triggerVehicles[vehicle] or 0
            if count == 0 and vehicle.addDeleteListener ~= nil then
                vehicle:addDeleteListener(self, Service.ServiceStationOnVehicleDeleted)
            end
            spec.triggerVehicles[vehicle] = count + 1
        end
    end

    if onLeave then
        removeTriggerNodeObject(self, otherId, true)
    end

    self:ServiceStationRefreshActiveRoots(true)
    if self.raiseActive ~= nil then
        self:raiseActive()
    end
end

function Service:ServiceStationOnVehicleDeleted(vehicle)
    local spec = self.spec_ServiceStation
    if spec == nil then
        return
    end

    for otherId, triggerVehicle in pairs(spec.triggerNodeObjects) do
        if triggerVehicle == vehicle then
            spec.triggerNodeObjects[otherId] = nil
        end
    end
    spec.triggerVehicles[vehicle] = nil
    spec.triggerSessionVehicles[vehicle] = nil
    spec.lastServiceTimes[vehicle] = nil

    self:ServiceStationRefreshActiveRoots(true)
    if self.raiseActive ~= nil then
        self:raiseActive()
    end
end

function Service:ServiceStationRefreshActiveRoots(processNewRoots)
    local spec = self.spec_ServiceStation
    local currentRoots = {}

    for vehicle, count in pairs(spec.triggerVehicles) do
        if count > 0 and isVehicleObjectValid(vehicle) then
            local rootVehicle = self:ServiceStationGetRootVehicle(vehicle)
            local rootKey = getRootKey(rootVehicle)
            if rootKey ~= nil and isVehicleObjectValid(rootVehicle) then
                local rootData = currentRoots[rootKey]
                if rootData == nil then
                    rootData = {
                        rootVehicle = rootVehicle,
                        chainHash = getVehicleChainHash(rootVehicle),
                        triggerVehicles = {},
                    }
                    currentRoots[rootKey] = rootData
                end
                rootData.triggerVehicles[vehicle] = true
            end
        end
    end

    for rootKey in pairs(spec.activeRoots) do
        if currentRoots[rootKey] == nil then
            spec.activeRoots[rootKey] = nil
            spec.activeRootHashes[rootKey] = nil
            spec.fillCompletedRoots[rootKey] = nil
            spec.electricCompletedRoots[rootKey] = nil
            spec.energyAccumulatorMs[rootKey] = nil
        end
    end

    for rootKey, rootData in pairs(currentRoots) do
        local previousRootVehicle = spec.activeRoots[rootKey]
        local wasActive = previousRootVehicle == rootData.rootVehicle
        local chainChanged = wasActive and spec.activeRootHashes[rootKey] ~= rootData.chainHash
        local wasAlreadyPresent = false
        for vehicle in pairs(rootData.triggerVehicles) do
            if spec.triggerSessionVehicles[vehicle] == true then
                wasAlreadyPresent = true
                break
            end
        end

        spec.activeRoots[rootKey] = rootData.rootVehicle
        spec.activeRootHashes[rootKey] = rootData.chainHash

        if not wasActive then
            spec.fillCompletedRoots[rootKey] = Service.settings.fillChargeInstant == true
            spec.electricCompletedRoots[rootKey] = Service.settings.electricChargeInstant == true
            spec.energyAccumulatorMs[rootKey] = 0

            if processNewRoots ~= false and not wasAlreadyPresent then
                local now = getTimeMillis()
                local cooldown = math.max(tonumber(Service.settings.cooldownSeconds) or 0, 0) * 1000
                local vehicleChain = self:ServiceStationGetVehicleChain(rootData.rootVehicle)
                local isInCooldown = false

                for _, chainVehicle in ipairs(vehicleChain) do
                    local lastServiceTime = spec.lastServiceTimes[chainVehicle]
                    if lastServiceTime ~= nil and now - lastServiceTime < cooldown then
                        isInCooldown = true
                        break
                    end
                end

                if not isInCooldown then
                    for _, chainVehicle in ipairs(vehicleChain) do
                        spec.lastServiceTimes[chainVehicle] = now
                    end
                    self:ServiceStationProcessInstantChain(rootData.rootVehicle)
                end
            end
        elseif chainChanged then
            spec.energyAccumulatorMs[rootKey] = 0
            if Service.settings.fillChargeInstant ~= true then
                spec.fillCompletedRoots[rootKey] = false
            end
            if Service.settings.electricChargeInstant ~= true then
                spec.electricCompletedRoots[rootKey] = false
            end
        end

        for vehicle in pairs(rootData.triggerVehicles) do
            spec.triggerSessionVehicles[vehicle] = true
        end
    end

    self:ServiceStationUpdateAutoDriveRefuelTrigger()
end

function Service:ServiceStationProcessInstantChain(rootVehicle)
    local spec = self.spec_ServiceStation
    local processed = {}
    local fillInstant = Service.settings.fillChargeInstant == true
    local electricInstant = Service.settings.electricChargeInstant == true

    for _, vehicle in ipairs(self:ServiceStationGetVehicleChain(rootVehicle)) do
        local key = vehicle ~= nil and (vehicle.rootNode or vehicle.id) or nil
        if key ~= nil and processed[key] ~= true then
            processed[key] = true

            if self:ServiceStationGetCanServiceVehicle(vehicle) then
                if spec.wash then
                    self:ServiceStationWashVehicle(vehicle)
                end

                if spec.repair then
                    self:ServiceStationRepairVehicle(vehicle)
                end

                if spec.repaint then
                    self:ServiceStationRepaintVehicle(vehicle)
                end

                if fillInstant and spec.energyDiesel and FillType.DIESEL ~= nil then
                    self:ServiceStationFillConsumer(vehicle, FillType.DIESEL, nil, true)
                end

                if fillInstant and spec.energyDiesel and FillType.DEF ~= nil then
                    self:ServiceStationFillConsumer(vehicle, FillType.DEF, nil, true)
                end

                if fillInstant and spec.energyMethane and FillType.METHANE ~= nil then
                    self:ServiceStationFillConsumer(vehicle, FillType.METHANE, nil, true)
                end

                if electricInstant and spec.energyElectric and FillType.ELECTRICCHARGE ~= nil then
                    self:ServiceStationFillConsumer(vehicle, FillType.ELECTRICCHARGE, nil, true)
                end
            end
        end
    end

    local rootKey = getRootKey(rootVehicle)
    if rootKey ~= nil then
        if fillInstant then
            spec.fillCompletedRoots[rootKey] = true
        end
        if electricInstant then
            spec.electricCompletedRoots[rootKey] = true
        end
    end
end

local function hasPendingEnergyForRoot(spec, rootKey)
    local fillEnabled = (spec.energyDiesel and (FillType.DIESEL ~= nil or FillType.DEF ~= nil))
        or (spec.energyMethane and FillType.METHANE ~= nil)
    local fillCanRun = fillEnabled
        and Service.settings.fillChargeInstant ~= true
        and Service.getFillChargeSpeedFactor() > 0
    local electricCanRun = spec.energyElectric
        and FillType.ELECTRICCHARGE ~= nil
        and Service.settings.electricChargeInstant ~= true
        and Service.getElectricChargeSpeedFactor() > 0

    return (fillCanRun and spec.fillCompletedRoots[rootKey] ~= true)
        or (electricCanRun and spec.electricCompletedRoots[rootKey] ~= true)
end

function Service.ServiceStationHasPendingEnergy(spec)
    for rootKey in pairs(spec.activeRoots) do
        if hasPendingEnergyForRoot(spec, rootKey) then
            return true
        end
    end
    return false
end

function Service:onUpdate(dt)
    if not self.isServer then
        return
    end

    local spec = self.spec_ServiceStation
    if spec == nil then
        return
    end

    self:ServiceStationRefreshActiveRoots(true)

    if next(spec.activeRoots) == nil then
        spec.energyAccumulatorMs = {}
        return
    end

    for rootKey, rootVehicle in pairs(spec.activeRoots) do
        if hasPendingEnergyForRoot(spec, rootKey) then
            local accumulatorMs = (spec.energyAccumulatorMs[rootKey] or 0) + dt
            spec.energyAccumulatorMs[rootKey] = accumulatorMs

            if accumulatorMs >= ENERGY_UPDATE_INTERVAL_MS then
                local elapsedSeconds = accumulatorMs * 0.001
                spec.energyAccumulatorMs[rootKey] = 0

                local dieselPerUpdate = spec.baseDieselLitersPerSecond
                    * Service.getFillChargeSpeedFactor()
                    * elapsedSeconds
                local methanePerUpdate = spec.baseMethaneUnitsPerSecond
                    * Service.getFillChargeSpeedFactor()
                    * elapsedSeconds
                local electricPerUpdate = spec.baseChargeUnitsPerSecond
                    * Service.getElectricChargeSpeedFactor()
                    * elapsedSeconds
                if
                    Service.settings.electricChargeUseTimeScale ~= false
                    and g_currentMission ~= nil
                    and g_currentMission.getEffectiveTimeScale ~= nil
                then
                    electricPerUpdate = electricPerUpdate * math.max(g_currentMission:getEffectiveTimeScale(), 0)
                end

                if Service.settings.fillChargeInstant ~= true and spec.fillCompletedRoots[rootKey] ~= true then
                    local allFull = true
                    local dieselFull = true
                    if spec.energyDiesel and FillType.DIESEL ~= nil then
                        dieselFull = self:ServiceStationFillEnergyChain(rootVehicle, FillType.DIESEL, dieselPerUpdate)
                        allFull = dieselFull and allFull
                    end
                    if spec.energyDiesel and FillType.DEF ~= nil then
                        if dieselFull then
                            allFull = self:ServiceStationFillEnergyChain(rootVehicle, FillType.DEF, dieselPerUpdate)
                                and allFull
                        else
                            allFull = false
                        end
                    end
                    if spec.energyMethane and FillType.METHANE ~= nil then
                        allFull = self:ServiceStationFillEnergyChain(rootVehicle, FillType.METHANE, methanePerUpdate)
                            and allFull
                    end
                    spec.fillCompletedRoots[rootKey] = allFull
                end

                if
                    Service.settings.electricChargeInstant ~= true
                    and spec.energyElectric
                    and FillType.ELECTRICCHARGE ~= nil
                    and spec.electricCompletedRoots[rootKey] ~= true
                then
                    spec.electricCompletedRoots[rootKey] =
                        self:ServiceStationFillEnergyChain(rootVehicle, FillType.ELECTRICCHARGE, electricPerUpdate)
                end
            end
        else
            spec.energyAccumulatorMs[rootKey] = 0
        end
    end

    self:ServiceStationUpdateAutoDriveRefuelTrigger()

    if Service.ServiceStationHasPendingEnergy(spec) and self.raiseActive ~= nil then
        self:raiseActive()
    end
end

function Service:ServiceStationFillEnergyChain(rootVehicle, fillTypeIndex, unitsPerVehicle)
    local processed = {}
    local allFull = true

    for _, vehicle in ipairs(self:ServiceStationGetVehicleChain(rootVehicle)) do
        local key = vehicle ~= nil and (vehicle.rootNode or vehicle.id) or nil
        if key ~= nil and processed[key] ~= true then
            processed[key] = true

            if self:ServiceStationGetCanServiceVehicle(vehicle) then
                local _, hasConsumer, isFull =
                    self:ServiceStationFillConsumer(vehicle, fillTypeIndex, unitsPerVehicle, false)
                if hasConsumer and not isFull then
                    allFull = false
                end
            end
        end
    end

    return allFull
end

function Service:ServiceStationWashVehicle(vehicle)
    local dirtAmount = getVehicleMaxDirtAmount(vehicle)
    if vehicle.cleanVehicle == nil or dirtAmount <= FILL_EPSILON or dirtAmount < Service.getWashMinimumDirt() then
        return false
    end

    local triggerWashType = Washable ~= nil and Washable.WASHTYPE_TRIGGER or nil
    if
        triggerWashType ~= nil
        and vehicle.getAllowsWashingByType ~= nil
        and not vehicle:getAllowsWashingByType(triggerWashType)
    then
        return false
    end

    vehicle:cleanVehicle(1)
    if getVehicleMaxDirtAmount(vehicle) > FILL_EPSILON and vehicle.setDirtAmount ~= nil then
        vehicle:setDirtAmount(0)
    end

    chargeFarm(
        self:ServiceStationGetVehicleFarmId(vehicle),
        self.spec_ServiceStation.baseWashPrice,
        MoneyType.VEHICLE_RUNNING_COSTS,
        true,
        true
    )
    return true
end

function Service:ServiceStationRepairVehicle(vehicle)
    if vehicle.getDamageAmount == nil or vehicle:getDamageAmount() <= 0.0001 then
        return
    end

    local farmId = self:ServiceStationGetVehicleFarmId(vehicle)
    if vehicle.getRepairPrice ~= nil then
        chargeFarm(farmId, vehicle:getRepairPrice(), MoneyType.VEHICLE_REPAIR, true, false)
    end

    if vehicle.setDamageAmount ~= nil then
        vehicle:setDamageAmount(0, true)
    elseif vehicle.addDamageAmount ~= nil then
        vehicle:addDamageAmount(-math.huge, true)
    end

    if g_farmManager ~= nil and g_achievementManager ~= nil then
        local total = g_farmManager:updateFarmStats(farmId, "repairVehicleCount", 1)
        if total ~= nil then
            g_achievementManager:tryUnlock("VehicleRepairFirst", total)
            g_achievementManager:tryUnlock("VehicleRepair", total)
        end
    end

    if g_server ~= nil and WearableRepairEvent ~= nil then
        g_server:broadcastEvent(WearableRepairEvent.new(vehicle, false))
    end
    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.VEHICLE_REPAIRED ~= nil then
        g_messageCenter:publish(MessageType.VEHICLE_REPAIRED, vehicle, false)
    end
end

function Service:ServiceStationRepaintVehicle(vehicle)
    if vehicle.getWearTotalAmount == nil or vehicle:getWearTotalAmount() <= 0.0001 then
        return
    end

    local farmId = self:ServiceStationGetVehicleFarmId(vehicle)
    if vehicle.getRepaintPrice ~= nil then
        chargeFarm(farmId, vehicle:getRepaintPrice(), MoneyType.VEHICLE_REPAIR, true, false)
    end

    if vehicle.addWearAmount ~= nil then
        vehicle:addWearAmount(-math.huge, true)
    end

    if g_farmManager ~= nil and g_achievementManager ~= nil then
        local total = g_farmManager:updateFarmStats(farmId, "repaintVehicleCount", 1)
        if total ~= nil then
            g_achievementManager:tryUnlock("VehicleRepaint", total)
        end
    end

    if g_server ~= nil and WearableRepaintEvent ~= nil then
        g_server:broadcastEvent(WearableRepaintEvent.new(vehicle))
    end
    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.VEHICLE_REPAINTED ~= nil then
        g_messageCenter:publish(MessageType.VEHICLE_REPAINTED, vehicle)
    end
end

function Service:ServiceStationFillConsumer(vehicle, fillTypeIndex, maxLiters, showMoneyChange)
    if
        vehicle.getConsumerFillUnitIndex == nil
        or vehicle.addFillUnitFillLevel == nil
        or vehicle.getFillUnitCapacity == nil
        or vehicle.getFillUnitFillLevel == nil
    then
        return 0, false, true
    end

    local fillUnitIndex = vehicle:getConsumerFillUnitIndex(fillTypeIndex)
    if fillUnitIndex == nil then
        return 0, false, true
    end

    local capacity = vehicle:getFillUnitCapacity(fillUnitIndex)
    local fillLevel = vehicle:getFillUnitFillLevel(fillUnitIndex)
    if capacity == nil or fillLevel == nil or capacity <= 0 or capacity >= math.huge then
        return 0, false, true
    end

    local remaining = math.max(capacity - fillLevel, 0)
    if remaining <= FILL_EPSILON then
        return 0, true, true
    end
    if maxLiters ~= nil and maxLiters <= 0 then
        return 0, true, false
    end

    local delta = remaining
    if maxLiters ~= nil then
        delta = math.min(delta, math.max(maxLiters, 0))
    end

    local farmId = self:ServiceStationGetVehicleFarmId(vehicle)
    local added = vehicle:addFillUnitFillLevel(farmId, fillUnitIndex, delta, fillTypeIndex, ToolType.TRIGGER, nil) or 0
    if added <= 0 then
        return 0, true, false
    end

    local price = added * getFillTypePricePerLiter(fillTypeIndex)
    chargeFarm(farmId, price, MoneyType.PURCHASE_FUEL, showMoneyChange, true)
    local fillLevelAfter = vehicle:getFillUnitFillLevel(fillUnitIndex) or fillLevel
    return added, true, capacity - fillLevelAfter <= FILL_EPSILON
end
