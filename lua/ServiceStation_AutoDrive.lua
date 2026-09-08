ServiceStation = ServiceStation or {}

local Service = ServiceStation
local AVAILABLE_SUPPLY = 1000000000

local function getAllFillLevels(source, farmId)
    local station = source.ServiceStation
    if station == nil or station.isDeleting == true or station.isDeleted == true then
        return {}, 0
    end

    if Service.settings.requireFarmAccess ~= false then
        local accessHandler = g_currentMission ~= nil and g_currentMission.accessHandler or nil
        if accessHandler ~= nil and accessHandler.canFarmAccess ~= nil then
            local ok, canAccess = pcall(accessHandler.canFarmAccess, accessHandler, farmId, station)
            if not ok or canAccess == false then
                return {}, 0
            end
        end
    end

    local fillLevels = {}
    for fillTypeIndex in pairs(source.refuelTrigger.fillTypes) do
        fillLevels[fillTypeIndex] = AVAILABLE_SUPPLY
    end

    return fillLevels, AVAILABLE_SUPPLY
end

local function onFillTypeSelection(refuelTrigger, fillTypeIndex)
    refuelTrigger.selectedFillType = fillTypeIndex

    local station = refuelTrigger.ServiceStation
    if station ~= nil and station.spec_ServiceStation ~= nil then
        station:ServiceStationUpdateAutoDriveRefuelTrigger()
    else
        refuelTrigger.isLoading = false
    end
end

local function getTriggerManager()
    if ADTriggerManager ~= nil then
        return ADTriggerManager
    end

    local autoDriveEnvironment = FS25_AutoDrive
    return autoDriveEnvironment ~= nil and autoDriveEnvironment.ADTriggerManager or nil
end

function Service:ServiceStationSetupAutoDriveRefuelTrigger()
    local spec = self.spec_ServiceStation
    local triggerManager = getTriggerManager()
    if spec == nil or spec.autoDriveRefuelTrigger ~= nil or spec.triggerNode == nil or triggerManager == nil then
        return
    end

    local fillTypes = {}
    if spec.energyDiesel then
        if FillType.DIESEL ~= nil then
            fillTypes[FillType.DIESEL] = true
        end
        if FillType.DEF ~= nil then
            fillTypes[FillType.DEF] = true
        end
    end
    if spec.energyMethane and FillType.METHANE ~= nil then
        fillTypes[FillType.METHANE] = true
    end
    if spec.energyElectric and FillType.ELECTRICCHARGE ~= nil then
        fillTypes[FillType.ELECTRICCHARGE] = true
    end
    if next(fillTypes) == nil then
        return
    end

    local refuelTrigger = {
        triggerNode = spec.triggerNode,
        fillTypes = fillTypes,
        fillableObjects = {},
        effects = {},
        autoStart = true,
        isLoading = false,
        selectedFillType = nil,
        ServiceStation = self,
        onFillTypeSelection = onFillTypeSelection,
    }
    refuelTrigger.source = {
        ServiceStation = self,
        refuelTrigger = refuelTrigger,
        getAllFillLevels = getAllFillLevels,
    }

    spec.autoDriveRefuelTrigger = refuelTrigger
    spec.autoDriveTriggerManager = triggerManager
    spec.autoDrivePreviousLoadingStation = self.loadingStation
    spec.autoDriveLoadingStation = { loadTriggers = { refuelTrigger } }
    self.loadingStation = spec.autoDriveLoadingStation

    if g_currentMission ~= nil and g_currentMission.addNodeObject ~= nil then
        g_currentMission:addNodeObject(spec.triggerNode, refuelTrigger)
        spec.autoDriveTriggerNodeRegistered = true
    end

    triggerManager.searchedForTriggers = false
    self:ServiceStationUpdateAutoDriveRefuelTrigger()
end

function Service:ServiceStationDeleteAutoDriveRefuelTrigger()
    local spec = self.spec_ServiceStation
    local refuelTrigger = spec ~= nil and spec.autoDriveRefuelTrigger or nil
    if refuelTrigger == nil then
        return
    end

    if self.loadingStation == spec.autoDriveLoadingStation then
        self.loadingStation = spec.autoDrivePreviousLoadingStation
    end

    if
        spec.autoDriveTriggerNodeRegistered == true
        and g_currentMission ~= nil
        and g_currentMission.removeNodeObject ~= nil
    then
        g_currentMission:removeNodeObject(refuelTrigger.triggerNode)
    end

    refuelTrigger.isLoading = false
    refuelTrigger.ServiceStation = nil
    refuelTrigger.source.ServiceStation = nil
    spec.autoDriveRefuelTrigger = nil
    spec.autoDriveLoadingStation = nil
    spec.autoDrivePreviousLoadingStation = nil
    spec.autoDriveTriggerNodeRegistered = nil

    local triggerManager = spec.autoDriveTriggerManager or getTriggerManager()
    spec.autoDriveTriggerManager = nil
    if triggerManager ~= nil then
        triggerManager.searchedForTriggers = false
    end
end

function Service:ServiceStationUpdateAutoDriveRefuelTrigger()
    local spec = self.spec_ServiceStation
    local refuelTrigger = spec ~= nil and spec.autoDriveRefuelTrigger or nil
    if refuelTrigger == nil then
        return
    end

    table.clear(refuelTrigger.fillableObjects)
    for _, rootVehicle in pairs(spec.activeRoots) do
        refuelTrigger.fillableObjects[#refuelTrigger.fillableObjects + 1] = rootVehicle
    end

    refuelTrigger.isLoading = refuelTrigger.selectedFillType ~= nil and Service.ServiceStationHasPendingEnergy(spec)
    if not refuelTrigger.isLoading then
        refuelTrigger.selectedFillType = nil
    end
end
