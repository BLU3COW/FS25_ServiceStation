ServiceStation = ServiceStation or {}

local Service = ServiceStation
local modDirectory = g_currentModDirectory or ""
local SETTINGS_ROOT = "ServiceStationSettings"
local SETTINGS_KEY = SETTINGS_ROOT .. ".settings"
local MAX_PRICE_PERCENT = 100000
local MAX_SPEED_PERCENT = 100000
local MAX_COOLDOWN_SECONDS = 86400

Service.CONFIG_MODE = "ServiceStationMode"
Service.CONFIG_WIDTH = "ServiceStationWidth"
Service.CONFIG_LENGTH = "ServiceStationLength"
Service.settings = Service.settings
    or {
        pricePercent = 100,
        washMinimumDirtPercent = 5,
        fillChargeSpeedPercent = 100,
        fillChargeInstant = false,
        electricChargeSpeedPercent = 100,
        electricChargeInstant = false,
        electricChargeUseTimeScale = true,
        cooldownSeconds = 10,
        requireFarmAccess = true,
    }

local function normalizeSettingNumber(value, defaultValue, maximum)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        value = defaultValue
    end
    return math.clamp(value, 0, maximum)
end

local function normalizeSettings(settings)
    settings = settings or {}
    return {
        pricePercent = normalizeSettingNumber(settings.pricePercent, 100, MAX_PRICE_PERCENT),
        washMinimumDirtPercent = normalizeSettingNumber(settings.washMinimumDirtPercent, 5, 100),
        fillChargeSpeedPercent = normalizeSettingNumber(settings.fillChargeSpeedPercent, 100, MAX_SPEED_PERCENT),
        fillChargeInstant = settings.fillChargeInstant == true,
        electricChargeSpeedPercent = normalizeSettingNumber(
            settings.electricChargeSpeedPercent,
            100,
            MAX_SPEED_PERCENT
        ),
        electricChargeInstant = settings.electricChargeInstant == true,
        electricChargeUseTimeScale = settings.electricChargeUseTimeScale ~= false,
        cooldownSeconds = normalizeSettingNumber(settings.cooldownSeconds, 10, MAX_COOLDOWN_SECONDS),
        requireFarmAccess = settings.requireFarmAccess ~= false,
    }
end

ServiceStationConfigurationItem = {}
local ServiceStationConfigurationItem_mt = Class(ServiceStationConfigurationItem, PlaceableConfigurationItem)

function ServiceStationConfigurationItem.new(configName, customMt)
    local self = ServiceStationConfigurationItem:superClass()
        .new(configName, customMt or ServiceStationConfigurationItem_mt)

    self.wash = false
    self.repair = false
    self.repaint = false
    self.diesel = false
    self.electric = false
    self.methane = false

    return self
end

function ServiceStationConfigurationItem:loadFromXML(xmlFile, baseKey, configKey, baseDirectory, customEnvironment)
    if
        not ServiceStationConfigurationItem:superClass()
            .loadFromXML(self, xmlFile, baseKey, configKey, baseDirectory, customEnvironment)
    then
        return false
    end

    self.wash = xmlFile:getValue(configKey .. "#wash", self.wash)
    self.repair = xmlFile:getValue(configKey .. "#repair", self.repair)
    self.repaint = xmlFile:getValue(configKey .. "#repaint", self.repaint)
    self.diesel = xmlFile:getValue(configKey .. "#diesel", self.diesel)
    self.electric = xmlFile:getValue(configKey .. "#electric", self.electric)
    self.methane = xmlFile:getValue(configKey .. "#methane", self.methane)

    return true
end

function ServiceStationConfigurationItem.registerXMLPaths(schema, rootPath, configPath)
    ServiceStationConfigurationItem:superClass().registerXMLPaths(schema, rootPath, configPath)

    schema:register(XMLValueType.BOOL, configPath .. "#wash", "Wash complete vehicle chain", false)
    schema:register(XMLValueType.BOOL, configPath .. "#repair", "Repair complete vehicle chain", false)
    schema:register(XMLValueType.BOOL, configPath .. "#repaint", "Repaint complete vehicle chain", false)
    schema:register(
        XMLValueType.BOOL,
        configPath .. "#diesel",
        "Fill diesel consumers including basegame DEF handling",
        false
    )
    schema:register(XMLValueType.BOOL, configPath .. "#electric", "Charge electric consumers", false)
    schema:register(XMLValueType.BOOL, configPath .. "#methane", "Fill methane consumers", false)
end

ServiceStationDimensionConfigurationItem = {}
local ServiceStationDimensionConfigurationItem_mt =
    Class(ServiceStationDimensionConfigurationItem, PlaceableConfigurationItem)

function ServiceStationDimensionConfigurationItem.new(configName, customMt)
    local self = ServiceStationDimensionConfigurationItem:superClass()
        .new(configName, customMt or ServiceStationDimensionConfigurationItem_mt)

    self.meters = 0

    return self
end

function ServiceStationDimensionConfigurationItem:loadFromXML(
    xmlFile,
    baseKey,
    configKey,
    baseDirectory,
    customEnvironment
)
    if
        not ServiceStationDimensionConfigurationItem:superClass()
            .loadFromXML(self, xmlFile, baseKey, configKey, baseDirectory, customEnvironment)
    then
        return false
    end

    self.meters = math.max(xmlFile:getValue(configKey .. "#meters", self.meters), 0)
    local decimals = math.abs(self.meters - math.floor(self.meters)) > 0.001 and 1 or 0
    self.name = string.format("%s %s", g_i18n:formatNumber(self.meters, decimals, true), g_i18n:getText("unit_mShort"))

    return true
end

function ServiceStationDimensionConfigurationItem.registerXMLPaths(schema, rootPath, configPath)
    ServiceStationDimensionConfigurationItem:superClass().registerXMLPaths(schema, rootPath, configPath)
    schema:register(XMLValueType.FLOAT, configPath .. "#meters", "Configured station dimension in meters", 0)
end

local function getSettingsFilename()
    if getUserProfileAppPath == nil then
        return nil
    end

    local settingsDirectory = getUserProfileAppPath() .. "modSettings"
    if createFolder ~= nil then
        createFolder(settingsDirectory)
    end

    return settingsDirectory .. "/FS25_ServiceStation.xml"
end

local function getBoolOrDefault(value, defaultValue)
    if value == nil then
        return defaultValue
    end

    return value == true
end

local function getFloatValue(xmlFile, key, defaultValue)
    local value = getXMLFloat(xmlFile, key)
    return tonumber(value) or defaultValue
end

local function getBoolValue(xmlFile, key, defaultValue)
    local value = getXMLBool(xmlFile, key)
    return getBoolOrDefault(value, defaultValue)
end

local function setCompactXMLNumber(xmlFile, key, value)
    value = tonumber(value) or 0

    local text
    if value == math.floor(value) then
        text = tostring(math.floor(value))
    else
        text = string.format("%.6f", value):gsub("0+$", ""):gsub("%.$", "")
    end

    setXMLString(xmlFile, key, text)
end

function Service.applySettings(settings)
    local normalized = normalizeSettings(settings)
    for key, value in pairs(normalized) do
        Service.settings[key] = value
    end
end

local function loadSettingsFile(filename)
    if filename == nil or not fileExists(filename) then
        return false
    end

    local xmlFile = loadXMLFile("ServiceStationSettings", filename)
    if xmlFile == nil or xmlFile == 0 then
        return false
    end

    Service.applySettings({
        pricePercent = getFloatValue(xmlFile, SETTINGS_KEY .. ".price#percent", Service.settings.pricePercent),
        washMinimumDirtPercent = getFloatValue(
            xmlFile,
            SETTINGS_KEY .. ".wash#minimumDirtPercent",
            Service.settings.washMinimumDirtPercent
        ),
        fillChargeSpeedPercent = getFloatValue(
            xmlFile,
            SETTINGS_KEY .. ".fillCharge#speedPercent",
            Service.settings.fillChargeSpeedPercent
        ),
        fillChargeInstant = getBoolValue(
            xmlFile,
            SETTINGS_KEY .. ".fillCharge#instant",
            Service.settings.fillChargeInstant
        ),
        electricChargeSpeedPercent = getFloatValue(
            xmlFile,
            SETTINGS_KEY .. ".electricCharge#speedPercent",
            Service.settings.electricChargeSpeedPercent
        ),
        electricChargeInstant = getBoolValue(
            xmlFile,
            SETTINGS_KEY .. ".electricCharge#instant",
            Service.settings.electricChargeInstant
        ),
        electricChargeUseTimeScale = getBoolValue(
            xmlFile,
            SETTINGS_KEY .. ".electricCharge#useTimeScale",
            Service.settings.electricChargeUseTimeScale
        ),
        cooldownSeconds = getFloatValue(
            xmlFile,
            SETTINGS_KEY .. ".trigger#cooldownSeconds",
            Service.settings.cooldownSeconds
        ),
        requireFarmAccess = getBoolValue(
            xmlFile,
            SETTINGS_KEY .. ".access#requireFarmAccess",
            Service.settings.requireFarmAccess
        ),
    })

    delete(xmlFile)
    return true
end

local function writeSettingsFile(filename)
    local xmlFile = createXMLFile("ServiceStationSettingsWrite", filename, SETTINGS_ROOT)
    if xmlFile == nil or xmlFile == 0 then
        return false
    end

    setCompactXMLNumber(xmlFile, SETTINGS_KEY .. ".price#percent", Service.settings.pricePercent)
    setCompactXMLNumber(xmlFile, SETTINGS_KEY .. ".wash#minimumDirtPercent", Service.settings.washMinimumDirtPercent)
    setCompactXMLNumber(xmlFile, SETTINGS_KEY .. ".fillCharge#speedPercent", Service.settings.fillChargeSpeedPercent)
    setXMLBool(xmlFile, SETTINGS_KEY .. ".fillCharge#instant", Service.settings.fillChargeInstant == true)
    setCompactXMLNumber(
        xmlFile,
        SETTINGS_KEY .. ".electricCharge#speedPercent",
        Service.settings.electricChargeSpeedPercent
    )
    setXMLBool(xmlFile, SETTINGS_KEY .. ".electricCharge#instant", Service.settings.electricChargeInstant == true)
    setXMLBool(
        xmlFile,
        SETTINGS_KEY .. ".electricCharge#useTimeScale",
        Service.settings.electricChargeUseTimeScale ~= false
    )
    setCompactXMLNumber(xmlFile, SETTINGS_KEY .. ".trigger#cooldownSeconds", Service.settings.cooldownSeconds)
    setXMLBool(xmlFile, SETTINGS_KEY .. ".access#requireFarmAccess", Service.settings.requireFarmAccess ~= false)
    saveXMLFile(xmlFile)
    delete(xmlFile)
    return true
end

function Service.loadSettings()
    local settingsFilename = getSettingsFilename()
    if settingsFilename == nil then
        return
    end

    if not fileExists(settingsFilename) then
        if not writeSettingsFile(settingsFilename) then
            Logging.warning("ServiceStation: Could not create modSettings file '%s'", settingsFilename)
        end
    else
        if not loadSettingsFile(settingsFilename) then
            Logging.warning("ServiceStation: Could not load modSettings file '%s'", settingsFilename)
        elseif not writeSettingsFile(settingsFilename) then
            Logging.warning("ServiceStation: Could not update modSettings file '%s'", settingsFilename)
        end
    end
end

function Service.getPriceFactor()
    return normalizeSettingNumber(Service.settings.pricePercent, 100, MAX_PRICE_PERCENT) / 100
end

function Service.getWashMinimumDirt()
    return normalizeSettingNumber(Service.settings.washMinimumDirtPercent, 5, 100) / 100
end

function Service.getElectricChargeSpeedFactor()
    return normalizeSettingNumber(Service.settings.electricChargeSpeedPercent, 100, MAX_SPEED_PERCENT) / 100
end

function Service.getFillChargeSpeedFactor()
    return normalizeSettingNumber(Service.settings.fillChargeSpeedPercent, 100, MAX_SPEED_PERCENT) / 100
end

function Service.getCooldownSeconds()
    return normalizeSettingNumber(Service.settings.cooldownSeconds, 10, MAX_COOLDOWN_SECONDS)
end

ServiceStationSettingsEvent = {}
local ServiceStationSettingsEvent_mt = Class(ServiceStationSettingsEvent, Event)
InitEventClass(ServiceStationSettingsEvent, "ServiceStationSettingsEvent")

function ServiceStationSettingsEvent.emptyNew()
    return Event.new(ServiceStationSettingsEvent_mt)
end

function ServiceStationSettingsEvent.new(settings)
    local self = ServiceStationSettingsEvent.emptyNew()
    local normalized = normalizeSettings(settings)
    for key, value in pairs(normalized) do
        self[key] = value
    end
    return self
end

function ServiceStationSettingsEvent:readStream(streamId, connection)
    self.pricePercent = streamReadFloat32(streamId)
    self.washMinimumDirtPercent = math.clamp(streamReadFloat32(streamId), 0, 100)
    self.fillChargeSpeedPercent = streamReadFloat32(streamId)
    self.fillChargeInstant = streamReadBool(streamId)
    self.electricChargeSpeedPercent = streamReadFloat32(streamId)
    self.electricChargeInstant = streamReadBool(streamId)
    self.electricChargeUseTimeScale = streamReadBool(streamId)
    self.cooldownSeconds = streamReadFloat32(streamId)
    self.requireFarmAccess = streamReadBool(streamId)

    local normalized = normalizeSettings(self)
    for key, value in pairs(normalized) do
        self[key] = value
    end
    self:run(connection)
end

function ServiceStationSettingsEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.pricePercent)
    streamWriteFloat32(streamId, self.washMinimumDirtPercent)
    streamWriteFloat32(streamId, self.fillChargeSpeedPercent)
    streamWriteBool(streamId, self.fillChargeInstant == true)
    streamWriteFloat32(streamId, self.electricChargeSpeedPercent)
    streamWriteBool(streamId, self.electricChargeInstant == true)
    streamWriteBool(streamId, self.electricChargeUseTimeScale ~= false)
    streamWriteFloat32(streamId, self.cooldownSeconds)
    streamWriteBool(streamId, self.requireFarmAccess == true)
end

function ServiceStationSettingsEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        Service.applySettings(self)
    end
end

local function sendSettings(baseMission, connection)
    if g_server ~= nil and connection ~= nil then
        connection:sendEvent(ServiceStationSettingsEvent.new(Service.settings))
    end
end

if FSBaseMission ~= nil then
    FSBaseMission.onConnectionFinishedLoading =
        Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, sendSettings)
end

local function registerConfigurationTypes()
    if g_placeableConfigurationManager == nil then
        return
    end

    local function addConfigType(configName, titleKey, itemClass)
        if g_placeableConfigurationManager:getConfigurationDescByName(configName) == nil then
            g_placeableConfigurationManager:addConfigurationType(
                configName,
                g_i18n:getText(titleKey),
                "ServiceStation",
                itemClass
            )
        end
    end

    addConfigType(Service.CONFIG_MODE, "configuration_ServiceStationMode", ServiceStationConfigurationItem)
    addConfigType(Service.CONFIG_WIDTH, "configuration_ServiceStationWidth", ServiceStationDimensionConfigurationItem)
    addConfigType(Service.CONFIG_LENGTH, "configuration_ServiceStationLength", ServiceStationDimensionConfigurationItem)
end

local function init()
    if g_placeableSpecializationManager ~= nil then
        g_placeableSpecializationManager:addSpecialization(
            "FS25_ServiceStation",
            "ServiceStation",
            modDirectory .. "lua/ServiceStation.lua",
            nil
        )

        if Placeable ~= nil and Placeable.xmlSchema ~= nil and Service.registerXMLPaths ~= nil then
            Service.registerXMLPaths(Placeable.xmlSchema, "placeable")
        end
    end

    registerConfigurationTypes()
    Service.loadSettings()
end

init()
