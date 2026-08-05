local ADDON_NAME = "Manastormer"
local VERSION_PREFIX = "MSMVersion"
local MAX_PLAYERS = 15
local ICON_PATH = "Interface\\AddOns\\Manastormer\\Assets\\ManastormerIcon"
local FONT_TITLE = "Fonts\\MORPHEUS.TTF"
local FONT_BODY = "Fonts\\FRIZQT__.TTF"
local UI_COLORS = {
    bg = { 0.025, 0.03, 0.055, 0.98 },
    panel = { 0.055, 0.065, 0.11, 0.98 },
    panel2 = { 0.075, 0.085, 0.14, 1 },
    header = { 0.035, 0.04, 0.07, 1 },
    border = { 0.25, 0.24, 0.20, 1 },
    gold = { 0.91, 0.79, 0.43, 1 },
    goldDark = { 0.42, 0.34, 0.17, 1 },
    text = { 0.92, 0.93, 0.97, 1 },
    muted = { 0.55, 0.57, 0.65, 1 },
    green = { 0.35, 0.85, 0.50, 1 },
    red = { 0.90, 0.32, 0.32, 1 },
}
local ROLE_TARGET = { tank = 2, healer = 3, aura = 3 }
local ROLE_CODE = { ["1"] = "tank", ["2"] = "healer", ["3"] = "aura" }
local ROLE_LABEL = { tank = "TANKS", healer = "HEALERS", aura = "AURAS" }
local ROLE_ORDER = { "tank", "healer", "aura" }

local addon = CreateFrame("Frame")
local db
local panel
local statusText
local level59Text
local listenButton
local readyCheckButton
local enterManastormButton
local recruitmentButton
local minimizeButton
local minimapButton
local pageButton
local whisperPanel
local whisperEmptyText
local whisperRows = {}
local whisperScrollOffset = 0
local whisperScrollText
local chatScannerPanel
local chatScannerEmptyText
local chatScannerRows = {}
local chatScannerScrollOffset = 0
local chatScannerScrollText
local settingsUIElements = {}
local settingsValueLabels = {}
local settingsSummaryText
local settingsChannelLabel
local settingsChaoticSlider
local settingsChaoticLabel
local settingsChaoticCheck
local activePage = "raid"
local compactText
local kick60Button
local kick59Button
local roleBoxes = {}
local fullUIElements = {}
local sessionActive = false
local readyCheckArmed = false
local manastormEntryArmed = false
local readyResponses = {}
local warningSeen = {}
local chaoticLinkStacks = {}
local chaoticLinkLastWarning = {}
local chaoticLinkLastAnnouncedStack = {}
local chaoticLinkBrokenAt = {}
local raidReportQueue
local pendingLevel60Kicks = {}
local pendingLevel59Kicks = {}
local previousRosterNames
local recentDepartures = {}
local lastWipeWarningKey
local activeManastormLevel = 0
local panelIsMinimized = false
local pendingMinimizedState
local pendingPanelShown
local delayed = {}
local Refresh
local SetMinimized
local UpdateKickButton
local UpdateKick59Button
local PositionKickButton
local RefreshWhisperPanel
local RefreshChatScannerPanel
local RefreshSettingsPage
local newerVersionAvailable
local warnedVersion
local lastVersionBroadcast = 0
local whisperCapacityReplies = {}
local lastActivityAllowed
local Sync = {
    lastAuraCoverageNotice = 0,
    nextAuraCoverageCheck = 0,
    roleSyncSnapshots = {},
    lastRoleSyncRequest = 0,
    lastRoleSyncSnapshot = 0,
    addonUsers = {},
    raidReset = nil,
    resetButton = nil,
}

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ShortName(name)
    return (name and name:match("^[^-]+")) or name or "Unknown"
end

local function NormalizedName(name)
    return tostring(name or ""):lower():gsub("%s+", "")
end

local function HasRealmSuffix(name)
    return tostring(name or ""):find("-", 1, true) ~= nil
end

local function SameName(left, right)
    if not left or not right then
        return false
    end
    if NormalizedName(left) == NormalizedName(right) then
        return true
    end
    if HasRealmSuffix(left) and HasRealmSuffix(right) then
        return false
    end
    return ShortName(left):lower() == ShortName(right):lower()
end

local function InterfaceCompatibilityMode()
    if type(IsAddOnLoaded) == "function" and IsAddOnLoaded("ElvUI") then
        return "ElvUI-safe"
    end
    return "Native WoW-safe"
end

local function NameKey(name)
    return NormalizedName(name)
end

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return math.floor(value)
end

local function ApplyRequirements()
    if not db then return end
    db.requirements = db.requirements or { total = 15, tank = 2, healer = 3, aura = 3 }
    db.chaoticLinkInterval = Clamp(db.chaoticLinkInterval or 4, 1, 10)
    if db.chaoticLinkReporting == nil then
        db.chaoticLinkReporting = true
    end
    local requirements = db.requirements
    requirements.total = Clamp(requirements.total, 1, 15)
    requirements.tank = Clamp(requirements.tank, 0, requirements.total)
    requirements.healer = Clamp(requirements.healer, 0, requirements.total - requirements.tank)
    requirements.aura = Clamp(requirements.aura, 0, requirements.total)
    MAX_PLAYERS = requirements.total
    ROLE_TARGET.tank = requirements.tank
    ROLE_TARGET.healer = requirements.healer
    ROLE_TARGET.aura = requirements.aura
end

local function DPSTarget()
    return math.max(0, MAX_PLAYERS - ROLE_TARGET.tank - ROLE_TARGET.healer)
end

local function RecruitmentChannelNumber()
    if not db then return 7 end
    db.recruitmentChannel = Clamp(db.recruitmentChannel or 7, 1, 10)
    return db.recruitmentChannel
end

local function RecruitmentChannelText()
    local channel = RecruitmentChannelNumber()
    local channelID, channelName = GetChannelName(channel)
    if channelID and channelID > 0 and channelName and channelName ~= "" then
        return "/" .. channel .. " " .. channelName
    end
    return "/" .. channel
end

local function UnitFullName(unit)
    local name, realm = UnitName(unit)
    if name and realm and realm ~= "" then
        return name .. "-" .. realm:gsub("%s+", "")
    end
    return name
end

local function IsSelf(name)
    return SameName(name, UnitFullName("player"))
end

local function InRaid()
    return GetNumRaidMembers() > 0
end

local function InParty()
    return GetNumPartyMembers() > 0
end

local function GroupSize()
    if InRaid() then
        return GetNumRaidMembers()
    end
    return GetNumPartyMembers() + 1
end

local function InstanceNameIsManastorm()
    if type(GetInstanceInfo) ~= "function" then
        return false
    end
    local instanceName = GetInstanceInfo()
    instanceName = tostring(instanceName or ""):lower():gsub("%s+", "")
    return instanceName:find("manastorm", 1, true) ~= nil
end

local function IsInsideManastorm()
    local manastormAPI = _G.C_Manastorm
    if type(manastormAPI) == "table" and type(manastormAPI.IsInManastorm) == "function" then
        local ok, active = pcall(manastormAPI.IsInManastorm)
        if ok and active == true then
            return true
        end
    end
    local inInstance = type(IsInInstance) == "function" and IsInInstance()
    if not inInstance then
        return false
    end
    return activeManastormLevel > 0 or InstanceNameIsManastorm()
end

local function IsDungeonFinderActive()
    if type(GetLFGMode) ~= "function" then
        return false
    end
    local ok, mode, submode = pcall(GetLFGMode)
    if not ok then
        return false
    end
    mode = Trim(mode):lower()
    submode = Trim(submode):lower()
    if mode == "lfgparty" or submode == "lfgparty" then
        return true
    end
    if InParty() or InRaid() then
        return mode == "rolecheck"
            or mode == "proposal"
            or submode == "rolecheck"
            or submode == "proposal"
    end
    return false
end

local function ManastormAutomationAllowed()
    local inInstance = type(IsInInstance) == "function" and IsInInstance()
    if IsInsideManastorm() then
        return true
    end
    return not inInstance and not IsDungeonFinderActive()
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe8c96aManastormer:|r " .. tostring(message))
end

local function IsManastormerAwake()
    return panel and panel:IsShown() and true or false
end

local function UpdateActivityState(announce)
    local allowed = ManastormAutomationAllowed()
    if announce and lastActivityAllowed ~= nil and allowed ~= lastActivityAllowed then
        if allowed then
            Print("Automatic Manastorm features resumed.")
        else
            Print("Automatic features suspended for Dungeon Finder or a non-Manastorm instance.")
        end
    end
    if not allowed then
        raidReportQueue = nil
        readyCheckArmed = false
        manastormEntryArmed = false
        pendingLevel60Kicks = {}
        pendingLevel59Kicks = {}
        if UpdateKickButton then
            UpdateKickButton()
        end
        if UpdateKick59Button then
            UpdateKick59Button()
        end
    end
    lastActivityAllowed = allowed
    return allowed
end

local function Schedule(delay, callback)
    table.insert(delayed, { at = GetTime() + delay, callback = callback })
end

local function MessageDeniesAura(message)
    local words = " " .. Trim(message):lower():gsub("[^%a]+", " "):gsub("%s+", " ") .. " "
    return words:find(" no aura ", 1, true)
        or words:find(" no auras ", 1, true)
        or words:find(" without aura ", 1, true)
        or words:find(" without an aura ", 1, true)
        or words:find(" not aura ", 1, true)
        or words:find(" do not have aura ", 1, true)
        or words:find(" do not have an aura ", 1, true)
        or words:find(" dont have aura ", 1, true)
        or words:find(" dont have an aura ", 1, true)
        or words:find(" don t have aura ", 1, true)
        or words:find(" don t have an aura ", 1, true)
end

local function ParseRoles(message)
    local deniesAura = MessageDeniesAura(message)
    local compact = Trim(message):gsub("%s+", "")
    if compact ~= "" and not compact:find("[^123]") then
        local roles = {}
        for digit in compact:gmatch(".") do
            roles[ROLE_CODE[digit]] = true
        end
        return roles
    end

    local roles = {}
    local foundRole = false
    local allowedWords = {
        ["i"] = true,
        ["m"] = true,
        ["im"] = true,
        ["as"] = true,
        ["and"] = true,
        ["but"] = true,
        ["can"] = true,
        ["join"] = true,
        ["inv"] = true,
        ["invite"] = true,
        ["me"] = true,
        ["please"] = true,
        ["pls"] = true,
        ["need"] = true,
        ["loom"] = true,
        ["looms"] = true,
        ["heirloom"] = true,
        ["heirlooms"] = true,
    }
    local word
    for word in Trim(message):lower():gmatch("%a+") do
        if word == "tank" or word == "tanks" then
            roles.tank = true
            foundRole = true
        elseif word == "heal" or word == "heals" or word == "healer" or word == "healers" then
            roles.healer = true
            foundRole = true
        elseif word == "aura" or word == "auras" then
            if not deniesAura then
                roles.aura = true
                foundRole = true
            end
        elseif word == "dps" or word == "damage" then
            roles.dps = true
            foundRole = true
        elseif deniesAura and (
            word == "no" or word == "without" or word == "an"
                or word == "not" or word == "do" or word == "dont"
                or word == "don" or word == "t" or word == "have"
                or word == "has" or word == "got"
        ) then
            -- These words are only accepted when the complete message contains
            -- a recognized Aura-negation phrase.
        elseif not allowedWords[word] then
            return nil
        end
    end
    if deniesAura then
        roles.aura = nil
        if not foundRole then
            roles.dps = true
            foundRole = true
        end
    end
    return foundRole and roles or nil
end

-- Recruitment whispers are often longer than role-check replies (for example,
-- "DPS LFG MS full looms"). Scan those messages loosely so the whisper window
-- can still identify every role without making public-chat assignment too broad.
local function ParseWhisperRoles(message)
    local parsed = ParseRoles(message)
    if parsed then return parsed end

    local deniesAura = MessageDeniesAura(message)
    local roles = {}
    local foundRole = false
    local word
    for word in Trim(message):lower():gmatch("%a+") do
        if word == "tank" or word == "tanks" then
            roles.tank = true
            foundRole = true
        elseif word == "heal" or word == "heals" or word == "healer" or word == "healers" then
            roles.healer = true
            foundRole = true
        elseif word == "dps" or word == "damage" then
            roles.dps = true
            foundRole = true
        elseif (word == "aura" or word == "auras") and not deniesAura then
            roles.aura = true
            foundRole = true
        end
    end
    if deniesAura then
        roles.aura = nil
        if not foundRole then
            roles.dps = true
            foundRole = true
        end
    end
    return foundRole and roles or nil
end

local function IsLFGManastormPost(message, roles)
    if not roles then return false end
    local words = {}
    local word
    for word in Trim(message):lower():gmatch("%a+") do
        words[word] = true
    end
    return words.lfg and words.ms and not words.lfm
end

local function ChatSource(event, channelName)
    if event == "CHAT_MSG_CHANNEL" then
        return channelName and channelName ~= "" and channelName or "Channel"
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING" then
        return "Raid"
    elseif event == "CHAT_MSG_PARTY" then
        return "Party"
    elseif event == "CHAT_MSG_BATTLEGROUND" or event == "CHAT_MSG_BATTLEGROUND_LEADER" then
        return "Battleground"
    elseif event == "CHAT_MSG_GUILD" then
        return "Guild"
    elseif event == "CHAT_MSG_OFFICER" then
        return "Officer"
    elseif event == "CHAT_MSG_YELL" then
        return "Yell"
    elseif event == "CHAT_MSG_SAY" then
        return "Say"
    end
    return "Whisper"
end

local function RoleText(roles)
    local labels = {}
    if roles and roles.tank then
        table.insert(labels, "Tank")
    end
    if roles and roles.healer then
        table.insert(labels, "Healer")
    end
    if roles and roles.aura then
        table.insert(labels, "Aura")
    end
    if roles and roles.dps then
        table.insert(labels, "DPS")
    end
    return table.concat(labels, "/")
end

local function GetRoster()
    local roster = {}
    if InRaid() then
        local index
        for index = 1, GetNumRaidMembers() do
            local name, rank, subgroup, level, _, classFile, _, online = GetRaidRosterInfo(index)
            if name then
                table.insert(roster, {
                    name = name,
                    rank = rank,
                    subgroup = subgroup,
                    level = level,
                    classFile = classFile,
                    online = online,
                    unit = "raid" .. index,
                    raidIndex = index,
                })
            end
        end
    else
        table.insert(roster, {
            name = UnitFullName("player"),
            rank = UnitIsPartyLeader("player") and 2 or 0,
            subgroup = 1,
            level = UnitLevel("player"),
            classFile = select(2, UnitClass("player")),
            online = true,
            unit = "player",
        })
        local index
        for index = 1, GetNumPartyMembers() do
            local unit = "party" .. index
            table.insert(roster, {
                name = UnitFullName(unit),
                rank = UnitIsPartyLeader(unit) and 2 or 0,
                subgroup = 1,
                level = UnitLevel(unit),
                classFile = select(2, UnitClass(unit)),
                online = UnitIsConnected(unit),
                unit = unit,
            })
        end
    end
    return roster
end

local function VerifiedMemberLevel(member)
    if not member then return nil end
    local unitLevel = member.unit and UnitLevel(member.unit) or nil
    local rosterLevel = tonumber(member.level)
    unitLevel = tonumber(unitLevel)
    if unitLevel and unitLevel > 0 and rosterLevel and rosterLevel > 0 then
        -- Require both live sources to catch up before declaring level 60.
        -- This avoids a recycled raid unit briefly reporting its prior player.
        return math.min(unitLevel, rosterLevel)
    end
    if unitLevel and unitLevel > 0 then return unitLevel end
    if rosterLevel and rosterLevel > 0 then return rosterLevel end
    return nil
end

local function FindSignup(name)
    local _, signup
    for _, signup in ipairs(db.signups) do
        if SameName(signup.name, name) then
            return signup
        end
    end
    return nil
end

local function IsBlocked60(name)
    local blockedName, record
    local now = time()
    for blockedName, record in pairs(db.blocked60 or {}) do
        local blockedAt = type(record) == "table" and tonumber(record.at) or nil
        if type(record) ~= "table" then
            -- Older builds stored only a short-name boolean. It cannot safely
            -- distinguish another character with the same name.
            db.blocked60[blockedName] = nil
        elseif not blockedAt or now - blockedAt > 7200 then
            db.blocked60[blockedName] = nil
        elseif NormalizedName(blockedName) == NormalizedName(name) then
            return true
        end
    end
    return false
end

local function RememberLevel60(name, unit)
    if not name then return end
    db.blocked60[name] = {
        at = time(),
        guid = unit and type(UnitGUID) == "function" and UnitGUID(unit) or nil,
    }
end

local function ClearLevel60Record(name, unit)
    if not name then return end
    local guid = unit and type(UnitGUID) == "function" and UnitGUID(unit) or nil
    local blockedName, record
    for blockedName, record in pairs(db.blocked60 or {}) do
        local recordGUID = type(record) == "table" and record.guid or nil
        if NormalizedName(blockedName) == NormalizedName(name)
            or (guid and recordGUID and guid == recordGUID)
        then
            db.blocked60[blockedName] = nil
        end
    end
    local pendingName
    for pendingName in pairs(pendingLevel60Kicks) do
        if NormalizedName(pendingName) == NormalizedName(name) then
            pendingLevel60Kicks[pendingName] = nil
        end
    end
    warningSeen[name .. ":60"] = nil
end

local function IsGrouped(name)
    local _, member
    for _, member in ipairs(GetRoster()) do
        if SameName(member.name, name) then
            return true
        end
    end
    return false
end

local function PlayerRaidRank()
    if not InRaid() then
        return UnitIsPartyLeader("player") and 2 or 0
    end
    local playerName = UnitFullName("player")
    local index
    for index = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(index)
        if SameName(name, playerName) then
            return rank or 0
        end
    end
    return 0
end

local function CanManageRaid()
    return PlayerRaidRank() > 0
end

local function HasAutomationAuthority()
    if not InRaid() and not InParty() then
        return true
    end
    return CanManageRaid()
end

local function IsRaidLeader()
    return PlayerRaidRank() == 2
end

local function LocalWarning(message)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo.RAID_WARNING)
    end
    if PlaySound then
        PlaySound("RaidWarning")
    end
    Print(message)
end

local function AddonVersion()
    if type(GetAddOnMetadata) == "function" then
        return tostring(GetAddOnMetadata(ADDON_NAME, "Version") or "0")
    end
    return "0"
end

local function IsNewerVersion(candidate, installed)
    local candidateParts = {}
    local installedParts = {}
    local value
    for value in tostring(candidate or ""):gmatch("%d+") do
        table.insert(candidateParts, tonumber(value) or 0)
    end
    for value in tostring(installed or ""):gmatch("%d+") do
        table.insert(installedParts, tonumber(value) or 0)
    end
    local length = math.max(#candidateParts, #installedParts)
    local index
    for index = 1, length do
        local candidatePart = candidateParts[index] or 0
        local installedPart = installedParts[index] or 0
        if candidatePart ~= installedPart then
            return candidatePart > installedPart
        end
    end
    return false
end

local function BroadcastVersion(force)
    if type(SendAddonMessage) ~= "function" or (not InRaid() and not InParty()) then
        return
    end
    local now = GetTime()
    if not force and now - lastVersionBroadcast < 10 then
        return
    end
    lastVersionBroadcast = now
    pcall(
        SendAddonMessage,
        VERSION_PREFIX,
        "V:" .. AddonVersion(),
        InRaid() and "RAID" or "PARTY"
    )
end

function Sync.SendGroupAddonMessage(message)
    if not IsManastormerAwake()
        or type(SendAddonMessage) ~= "function"
        or (not InRaid() and not InParty())
    then
        return false
    end
    return pcall(
        SendAddonMessage,
        VERSION_PREFIX,
        message,
        InRaid() and "RAID" or "PARTY"
    )
end

local function ReceiveVersion(message, sender)
    if not message or IsSelf(sender) then
        return
    end
    local candidate = tostring(message):match("^V:([%d%.]+)$")
    if not candidate or not IsNewerVersion(candidate, AddonVersion()) then
        return
    end
    if not newerVersionAvailable or IsNewerVersion(candidate, newerVersionAvailable) then
        newerVersionAvailable = candidate
    end
    if warnedVersion ~= newerVersionAvailable then
        warnedVersion = newerVersionAvailable
        LocalWarning(
            "A newer Manastormer version is available: v"
                .. newerVersionAvailable .. " (you have v" .. AddonVersion() .. ")."
        )
    end
    Refresh()
end

local function WarnRaid(message)
    if not IsManastormerAwake() or not HasAutomationAuthority() then
        return
    end
    LocalWarning(message)
    if InRaid() and CanManageRaid() then
        SendChatMessage("[Mana Storm] " .. message, "RAID_WARNING")
    elseif InParty() then
        SendChatMessage("[Mana Storm] " .. message, "PARTY")
    end
end

local function RoleCounts()
    local counts = { tank = 0, healer = 0, aura = 0 }
    local names = { tank = {}, healer = {}, aura = {} }
    local _, signup, role
    for _, signup in ipairs(db.signups) do
        if (IsSelf(signup.name) or IsGrouped(signup.name))
            and (IsSelf(signup.name) or not IsBlocked60(signup.name))
        then
            for _, role in ipairs(ROLE_ORDER) do
                if signup.roles[role] then
                    counts[role] = counts[role] + 1
                    table.insert(names[role], ShortName(signup.name))
                end
            end
        end
    end
    return counts, names
end

local function AuraCoverage()
    local occupiedGroups = {}
    local auraGroups = {}
    local _, member
    for _, member in ipairs(GetRoster()) do
        local group = member.subgroup or 1
        occupiedGroups[group] = true
        local signup = FindSignup(member.name)
        if signup
            and signup.roles
            and signup.roles.aura
            and (IsSelf(member.name) or not IsBlocked60(member.name))
        then
            auraGroups[group] = true
        end
    end

    local missingGroups = {}
    local group
    for group in pairs(occupiedGroups) do
        if not auraGroups[group] then
            table.insert(missingGroups, group)
        end
    end
    table.sort(missingGroups)
    return #missingGroups == 0, missingGroups
end

function Sync.MaybeNotifyMissingAuraGroups()
    if not sessionActive
        or not IsManastormerAwake()
        or not InRaid()
        or not IsRaidLeader()
        or not ManastormAutomationAllowed()
    then
        return
    end
    local now = GetTime()
    if now < Sync.nextAuraCoverageCheck then return end
    Sync.nextAuraCoverageCheck = now + 5
    local covered, missingGroups = AuraCoverage()
    if covered then return end
    if now - Sync.lastAuraCoverageNotice < 120 then return end
    Sync.lastAuraCoverageNotice = now
    SendChatMessage(
        "[Manastormer] No Aura assigned to occupied Group(s): "
            .. table.concat(missingGroups, ", ") .. ".",
        "RAID"
    )
end

local function FindRaidIndex(name)
    local index
    for index = 1, GetNumRaidMembers() do
        local raidName = GetRaidRosterInfo(index)
        if SameName(raidName, name) then
            return index
        end
    end
    return nil
end


function Sync.SenderIsGroupLeader(name)
    if not name then return false end
    if InRaid() then
        local index = FindRaidIndex(name)
        if not index then return false end
        local _, rank = GetRaidRosterInfo(index)
        return rank == 2
    end
    if SameName(name, UnitFullName("player")) then
        return UnitIsPartyLeader("player")
    end
    local index
    for index = 1, GetNumPartyMembers() do
        local unit = "party" .. index
        if SameName(name, UnitFullName(unit)) then
            return UnitIsPartyLeader(unit)
        end
    end
    return false
end

function Sync.GroupLeaderName()
    local _, member
    for _, member in ipairs(GetRoster()) do
        if member.rank == 2 then return member.name end
    end
    if InParty() then
        if UnitIsPartyLeader("player") then return UnitFullName("player") end
        local index
        for index = 1, GetNumPartyMembers() do
            local unit = "party" .. index
            if UnitIsPartyLeader(unit) then return UnitFullName(unit) end
        end
    end
    return nil
end

function Sync.StatusLine()
    if not sessionActive then
        return "|cffaaaaaaPAUSED - press Listen to start watching|r"
    end
    if not InRaid() and not InParty() then
        return "|cff888888SYNC: waiting for a group|r"
    end
    local leader = Sync.GroupLeaderName()
    if not leader then return "|cff888888SYNC: finding group leader|r" end
    if IsSelf(leader) then
        return "|cff55ff88SYNC HOST: You are sharing roles as raid leader|r"
    end
    local user = Sync.addonUsers[NameKey(leader)]
    if user and GetTime() - user.seen <= 300 then
        return "|cff55ff88SYNCED: Raid leader " .. ShortName(leader) .. " is sharing roles|r"
    end
    return "|cffffcc55SYNC: Waiting for raid leader " .. ShortName(leader) .. "'s addon|r"
end

function Sync.RoleFlags(roles)
    local flags = ""
    if roles and roles.tank then flags = flags .. "1" end
    if roles and roles.healer then flags = flags .. "2" end
    if roles and roles.aura then flags = flags .. "3" end
    if roles and roles.dps then flags = flags .. "4" end
    return flags
end

function Sync.RolesFromFlags(flags)
    local roles = {}
    for flag in tostring(flags or ""):gmatch(".") do
        if flag == "1" then roles.tank = true
        elseif flag == "2" then roles.healer = true
        elseif flag == "3" then roles.aura = true
        elseif flag == "4" then roles.dps = true
        end
    end
    return next(roles) and roles or nil
end

function Sync.BroadcastSignup(signup)
    if not signup or not signup.name or not signup.roles or not HasAutomationAuthority() then return end
    if not IsGrouped(signup.name) then return end
    local safeName = tostring(signup.name):gsub("|", "")
    Sync.SendGroupAddonMessage(
        "S|" .. safeName .. "|" .. Sync.RoleFlags(signup.roles)
            .. "|" .. tostring(tonumber(signup.updated) or time())
    )
end

function Sync.BroadcastSignupDelete(name)
    if not name or not HasAutomationAuthority() or not IsGrouped(name) then return end
    Sync.SendGroupAddonMessage("D|" .. tostring(name):gsub("|", "") .. "|" .. tostring(time()))
end

function Sync.SendRoleSyncSnapshot()
    if not sessionActive then return end
    if not IsRaidLeader() and not (InParty() and UnitIsPartyLeader("player")) then return end
    local now = GetTime()
    if now - Sync.lastRoleSyncSnapshot < 2 then return end
    Sync.lastRoleSyncSnapshot = now
    local stamp = tostring(time())
    Sync.SendGroupAddonMessage("B|" .. stamp)
    local _, signup
    for _, signup in ipairs(db.signups) do
        if IsSelf(signup.name) or IsGrouped(signup.name) then
            Sync.BroadcastSignup(signup)
        end
    end
    Sync.SendGroupAddonMessage("E|" .. stamp)
end

function Sync.RequestRoleSync(force)
    if not sessionActive
        or not IsManastormerAwake()
        or (not InRaid() and not InParty())
    then
        return
    end
    local now = GetTime()
    if not force and now - Sync.lastRoleSyncRequest < 10 then return end
    Sync.lastRoleSyncRequest = now
    Sync.SendGroupAddonMessage("Q")
end

function Sync.ReceiveRoleSync(message, sender)
    if not sessionActive
        or not IsManastormerAwake()
        or not ManastormAutomationAllowed()
        or not sender
        or IsSelf(sender)
        or not IsGrouped(sender)
    then
        return false
    end
    if message == "Q" then
        Sync.SendRoleSyncSnapshot()
        return true
    end

    local kind, name, value, updated = tostring(message or ""):match("^([S])|([^|]+)|([^|]*)|(%d+)$")
    if kind == "S" then
        if not IsGrouped(name) then return true end
        local roles = Sync.RolesFromFlags(value)
        if not roles then return true end
        updated = tonumber(updated) or 0
        local snapshot = Sync.roleSyncSnapshots[NameKey(sender)]
        local signup = FindSignup(name)
        if not signup then
            db.nextOrder = (db.nextOrder or 0) + 1
            signup = { name = name, roles = roles, order = db.nextOrder, updated = updated }
            table.insert(db.signups, signup)
        elseif snapshot or updated >= (tonumber(signup.updated) or 0) then
            signup.roles = roles
            signup.updated = updated
        end
        if snapshot then snapshot.seen[NameKey(name)] = true end
        Refresh()
        return true
    end

    local deleteName = tostring(message or ""):match("^D|([^|]+)|%d+$")
    if deleteName then
        local index
        for index = #db.signups, 1, -1 do
            if SameName(db.signups[index].name, deleteName) then
                table.remove(db.signups, index)
            end
        end
        Refresh()
        return true
    end

    local beginStamp = tostring(message or ""):match("^B|(%d+)$")
    if beginStamp and Sync.SenderIsGroupLeader(sender) then
        Sync.roleSyncSnapshots[NameKey(sender)] = { stamp = beginStamp, seen = {} }
        return true
    end
    local endStamp = tostring(message or ""):match("^E|(%d+)$")
    local snapshot = Sync.roleSyncSnapshots[NameKey(sender)]
    if endStamp and snapshot and snapshot.stamp == endStamp and Sync.SenderIsGroupLeader(sender) then
        local index
        for index = #db.signups, 1, -1 do
            local signup = db.signups[index]
            if (IsSelf(signup.name) or IsGrouped(signup.name))
                and not snapshot.seen[NameKey(signup.name)]
            then
                table.remove(db.signups, index)
            end
        end
        Sync.roleSyncSnapshots[NameKey(sender)] = nil
        Refresh()
        return true
    end
    return false
end

function Sync.StartRoleSync()
    if not sessionActive then return end
    BroadcastVersion(true)
    if IsRaidLeader() or (InParty() and UnitIsPartyLeader("player")) then
        Sync.SendRoleSyncSnapshot()
    else
        Sync.RequestRoleSync(true)
    end
end

local function PlayerReportRole(name)
    local signup = FindSignup(name)
    local roles = {}
    if signup and signup.roles then
        if signup.roles.tank then
            table.insert(roles, "Tank")
        end
        if signup.roles.healer then
            table.insert(roles, "Healer")
        end
        if signup.roles.dps then
            table.insert(roles, "DPS")
        end
    end
    if #roles == 0 then
        table.insert(roles, "DPS")
    end
    return table.concat(roles, "/"), signup and signup.roles and signup.roles.aura
end

local function StartRaidLevelReport()
    if not InRaid() then
        LocalWarning("You must be in a raid to report levels and roles.")
        return
    end
    if not CanManageRaid() then
        LocalWarning("You need raid leader or assistant for Raid Warning.")
        return
    end

    local lines = {}
    local _, member
    for _, member in ipairs(GetRoster()) do
        local level = VerifiedMemberLevel(member)
        if not level or level <= 0 then
            level = "?"
        end
        local roleText, hasAura = PlayerReportRole(member.name)
        local line = ShortName(member.name) .. " Level " .. tostring(level)
            .. " (" .. roleText .. ")"
        if hasAura then
            line = line .. " {star} Aura {star}"
        end
        table.insert(lines, line)
    end
    raidReportQueue = {
        lines = lines,
        index = 1,
        nextAt = 0,
    }
    Print("Reporting " .. #lines .. " player levels and roles to /rw.")
end

local function ProcessRaidLevelReport()
    if not IsManastormerAwake() then
        raidReportQueue = nil
        return
    end
    if not raidReportQueue or GetTime() < raidReportQueue.nextAt then
        return
    end
    local line = raidReportQueue.lines[raidReportQueue.index]
    if not line then
        raidReportQueue = nil
        Print("Level and role report complete.")
        return
    end
    SendChatMessage(line, "RAID_WARNING")
    raidReportQueue.index = raidReportQueue.index + 1
    raidReportQueue.nextAt = GetTime() + 0.4
end

local function AssignTankMarkers()
    if not sessionActive or not IsManastormerAwake() then return end
    if not IsInsideManastorm() or not InRaid() or not CanManageRaid() then
        return
    end

    local raidIndex
    for raidIndex = 1, GetNumRaidMembers() do
        SetRaidTarget("raid" .. raidIndex, 0)
    end

    -- Square and Diamond are assigned first, followed by the remaining markers.
    local tankMarkers = { 6, 3, 2, 1, 4, 5, 7, 8 }
    local markerNumber = 1
    local _, member
    for _, member in ipairs(GetRoster()) do
        local signup = FindSignup(member.name)
        if signup and signup.roles.tank and tankMarkers[markerNumber] then
            raidIndex = FindRaidIndex(member.name)
            if raidIndex then
                SetRaidTarget("raid" .. raidIndex, tankMarkers[markerNumber])
                markerNumber = markerNumber + 1
            end
        end
    end
    Print("Entered Mana Storm: Tank raid markers applied.")
end

local function WidgetText(widget)
    if not widget then
        return nil
    end
    if type(widget.GetText) == "function" then
        local ok, value = pcall(widget.GetText, widget)
        if ok and value then
            return tostring(value)
        end
    end
    local regionNames = { "Text", "text", "Label", "label", "Name", "name", "Title", "title" }
    local _, regionName
    for _, regionName in ipairs(regionNames) do
        local textRegion = widget[regionName]
        if textRegion and type(textRegion.GetText) == "function" then
            local ok, value = pcall(textRegion.GetText, textRegion)
            if ok and value then
                return tostring(value)
            end
        end
    end
    if type(widget.GetFontString) == "function" then
        local ok, textRegion = pcall(widget.GetFontString, widget)
        if ok and textRegion and type(textRegion.GetText) == "function" then
            local textOK, value = pcall(textRegion.GetText, textRegion)
            if textOK and value then
                return tostring(value)
            end
        end
    end
    return nil
end

local function IsManastormLevelOne(widget)
    local text = WidgetText(widget)
    return text and tonumber(text:match("[Ll]evel%s+(%d+)")) == 1
end

local function FindManastormLevelOneButton()
    local levelList = _G.ManastormQueueFrameRightPanelLevelSelectScrollList
    local scrollFrame = levelList and (levelList.ScrollFrame or levelList)
    local buttons = scrollFrame and scrollFrame.buttons
    if type(buttons) == "table" then
        local _, button
        for _, button in pairs(buttons) do
            if IsManastormLevelOne(button) and type(button.Click) == "function" then
                return button
            end
        end
    end

    -- Ascension has used more than one ScrollList implementation. Search every
    -- descendant as well as the optional .buttons cache used by older builds.
    local roots = {
        _G.ManastormQueueFrameRightPanelLevelSelect,
        levelList,
        scrollFrame,
    }
    local seen = {}
    local function FindInChildren(frame, depth)
        if not frame or seen[frame] or depth > 8 then
            return nil
        end
        seen[frame] = true
        if IsManastormLevelOne(frame) and type(frame.Click) == "function" then
            return frame
        end
        if type(frame.GetChildren) == "function" then
            local children = { frame:GetChildren() }
            local _, child
            for _, child in ipairs(children) do
                local found = FindInChildren(child, depth + 1)
                if found then
                    return found
                end
            end
        end
        return nil
    end
    local _, root
    for _, root in ipairs(roots) do
        local found = FindInChildren(root, 0)
        if found then
            return found
        end
    end
    return nil
end

local function ClickManastormEnter()
    -- Ascension protects its queue path. Validate the native control here and
    -- let Manastormer's SecureActionButton perform the final hardware click.
    local queueFrame = _G.ManastormQueueFrame
    local enterButton = _G.ManastormQueueFrameRightPanelEnterButton
    local dropdown = _G.ManastormQueueFrameRightPanelLevelDropDown
    if not queueFrame or not enterButton or not dropdown
        or (type(queueFrame.IsShown) == "function" and not queueFrame:IsShown())
    then
        LocalWarning("Open Ascension's Mana Storm panel, select Level 1, then click its Enter Group Manastorm button.")
        return false
    end
    if not IsManastormLevelOne(dropdown) then
        LocalWarning("Select Level 1 on Ascension's Mana Storm panel first.")
        return false
    end
    if type(enterButton.IsEnabled) == "function" and not enterButton:IsEnabled() then
        LocalWarning("Ascension's Enter Group Manastorm button is currently disabled.")
        return false
    end
    return true, enterButton
end

local function QueueForManastorm()
    return ClickManastormEnter()
end

local function PrintManastormDiagnostics()
    Print("Manastorm API/frame diagnostics:")
    local api = _G.C_Manastorm
    if type(api) == "table" then
        local names = {}
        local key, value
        for key, value in pairs(api) do
            table.insert(names, tostring(key) .. "(" .. type(value) .. ")")
        end
        table.sort(names)
        local index = 1
        while index <= #names do
            local line = {}
            local stopAt = math.min(index + 3, #names)
            while index <= stopAt do
                table.insert(line, names[index])
                index = index + 1
            end
            Print("C_Manastorm: " .. table.concat(line, ", "))
        end

        if type(api.GetEnterableLevels) == "function" then
            local ok, levels = pcall(api.GetEnterableLevels)
            if ok and type(levels) == "table" then
                local values = {}
                local key, value
                for key, value in pairs(levels) do
                    if type(value) == "table" then
                        table.insert(values, tostring(value.level or value.id or key))
                    else
                        table.insert(values, tostring(value))
                    end
                end
                Print("GetEnterableLevels(): " .. (#values > 0 and table.concat(values, ", ") or "<empty>"))
            else
                Print("GetEnterableLevels(): " .. (ok and tostring(levels) or "ERROR"))
            end
        end
        if type(api.CanEnter) == "function" then
            local ok, allowed, reason = pcall(api.CanEnter, 1)
            Print("CanEnter(1): " .. (ok and tostring(allowed) or "ERROR")
                .. (reason ~= nil and ", " .. tostring(reason) or ""))
        end
    else
        Print("C_Manastorm is not available on this client/realm.")
    end

    local frameNames = {
        "ManastormQueueFrame",
        "ManastormQueueFrameRightPanelLevelDropDown",
        "ManastormQueueFrameRightPanelLevelSelect",
        "ManastormQueueFrameRightPanelLevelSelectScrollList",
        "ManastormQueueFrameRightPanelEnterButton",
    }
    local _, frameName
    for _, frameName in ipairs(frameNames) do
        local frame = _G[frameName]
        if frame then
            local shown = type(frame.IsShown) == "function" and frame:IsShown() and "shown" or "hidden"
            local enabled = type(frame.IsEnabled) ~= "function" or frame:IsEnabled()
            Print(frameName .. ": " .. shown .. ", " .. (enabled and "enabled" or "disabled")
                .. ", text=" .. tostring(WidgetText(frame) or "<none>"))
        else
            Print(frameName .. ": NOT LOADED")
        end
    end
    local levelOne = FindManastormLevelOneButton()
    if levelOne then
        local name = type(levelOne.GetName) == "function" and levelOne:GetName()
        local parent = type(levelOne.GetParent) == "function" and levelOne:GetParent()
        local parentName = parent and type(parent.GetName) == "function" and parent:GetName()
        Print("Detected Level 1 control: " .. tostring(name or "<unnamed>")
            .. ", parent=" .. tostring(parentName or "<unnamed>")
            .. ", text=" .. tostring(WidgetText(levelOne) or "<none>"))
    else
        Print("Detected Level 1 control: NOT FOUND (open the level list and run /msm api again)")
    end
end

local function FinishReadyCheckQueue()
    if not readyCheckArmed then
        return
    end
    readyCheckArmed = false

    local notReady = {}
    local index
    for index = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(index)
        local status = GetReadyCheckStatus("raid" .. index)
        local key = NameKey(name)
        if status == "ready" then
            readyResponses[key] = true
        elseif status == "notready" then
            readyResponses[key] = false
        end
        if readyResponses[key] ~= true then
            table.insert(notReady, ShortName(name))
        end
    end

    if readyCheckButton then readyCheckButton:SetText("READY CHECK") end
    if #notReady > 0 then
        LocalWarning("Not ready: " .. table.concat(notReady, ", ") .. ".")
        return
    end
    LocalWarning("All " .. GroupSize() .. " raid members are ready. Open Ascension's Mana Storm panel, select Level 1, then click Manastormer's ENTER MANASTORM 1 button.")
end

local function TryFinishReadyCheckEarly()
    if not readyCheckArmed then
        return
    end
    local index
    for index = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(index)
        local key = NameKey(name)
        local status = GetReadyCheckStatus("raid" .. index)
        if status == "ready" then
            readyResponses[key] = true
        elseif status == "notready" then
            readyResponses[key] = false
        end
        if readyResponses[key] ~= true then
            return
        end
    end
    FinishReadyCheckQueue()
end

local function StartReadyCheckQueue()
    if not InRaid() then
        LocalWarning("You must be in a raid.")
        return
    end
    if not CanManageRaid() then
        LocalWarning("You need raid leader or assistant to start a ready check.")
        return
    end
    readyCheckArmed = true
    manastormEntryArmed = false
    if enterManastormButton then enterManastormButton:SetText("ENTER MANASTORM 1") end
    readyResponses = {}
    readyResponses[NameKey(UnitFullName("player"))] = true
    if readyCheckButton then
        readyCheckButton:SetText("WAITING: " .. GroupSize() .. " PLAYERS")
    end
    DoReadyCheck()
    Print("Ready check started for " .. GroupSize() .. " players. This button will not queue the Manastorm.")
end

local function SelfHasMainRole()
    local signup = FindSignup(UnitFullName("player"))
    return signup
        and signup.roles
        and (signup.roles.tank or signup.roles.healer or signup.roles.dps)
end

local function PostRecruitmentMessage()
    local counts = RoleCounts()
    local groupSize = GroupSize()
    local filledTankSlots = math.min(counts.tank, ROLE_TARGET.tank)
    local filledHealerSlots = math.min(counts.healer, ROLE_TARGET.healer)
    local assignedGroupSize = groupSize - (SelfHasMainRole() and 0 or 1)
    local dpsCount = math.max(0, assignedGroupSize - filledTankSlots - filledHealerSlots)
    local tankNeeded = math.max(0, ROLE_TARGET.tank - counts.tank)
    local healerNeeded = math.max(0, ROLE_TARGET.healer - counts.healer)
    local dpsTarget = DPSTarget()
    local dpsNeeded = math.max(0, dpsTarget - dpsCount)
    local auraNeeded = math.max(0, ROLE_TARGET.aura - counts.aura)
    local message = "[Manastormer] LFM MS - "
        .. counts.tank .. "/" .. ROLE_TARGET.tank .. " Tanks, "
        .. counts.healer .. "/" .. ROLE_TARGET.healer .. " Healers, "
        .. dpsCount .. "/" .. dpsTarget .. " DPS, "
        .. counts.aura .. "/" .. ROLE_TARGET.aura .. " Auras - "
        .. groupSize .. "/" .. MAX_PLAYERS .. " total - Need: "
        .. tankNeeded .. " Tank, "
        .. healerNeeded .. " Healer, "
        .. dpsNeeded .. " DPS, "
        .. auraNeeded .. " Aura"

    local channel = RecruitmentChannelNumber()
    local channelID = GetChannelName(channel)
    if not channelID or channelID == 0 then
        LocalWarning("You are not joined to recruitment channel /" .. channel .. ". Choose another channel in Settings.")
        return
    end
    SendChatMessage(message, "CHANNEL", nil, channel)
    Print("Posted to " .. RecruitmentChannelText() .. ": " .. message)
end

local function MaybeReplyRoleCapacity(author, roles)
    if not author or not roles or IsSelf(author) or IsGrouped(author) then
        return
    end
    if not IsManastormerAwake()
        or not sessionActive
        or not HasAutomationAuthority()
        or not ManastormAutomationAllowed()
    then
        return
    end

    local counts = RoleCounts()
    local groupSize = GroupSize()
    local filledTankSlots = math.min(counts.tank, ROLE_TARGET.tank)
    local filledHealerSlots = math.min(counts.healer, ROLE_TARGET.healer)
    local assignedGroupSize = groupSize - (SelfHasMainRole() and 0 or 1)
    local dpsCount = math.max(0, assignedGroupSize - filledTankSlots - filledHealerSlots)
    local capacity = {
        tank = counts.tank < ROLE_TARGET.tank,
        healer = counts.healer < ROLE_TARGET.healer,
        dps = dpsCount < DPSTarget(),
        aura = counts.aura < ROLE_TARGET.aura,
    }
    local labels = { tank = "Tank", healer = "Healer", dps = "DPS", aura = "Aura" }
    local order = { "tank", "healer", "dps", "aura" }
    local full = {}
    local needed = {}
    local _, role
    for _, role in ipairs(order) do
        if roles[role] then
            if groupSize >= MAX_PLAYERS or not capacity[role] then
                table.insert(full, labels[role])
            else
                table.insert(needed, labels[role])
            end
        end
    end
    if #full == 0 then
        return
    end

    local reply
    if groupSize >= MAX_PLAYERS then
        reply = "[Manastormer] Thanks, but the raid is currently full ("
            .. groupSize .. "/" .. MAX_PLAYERS .. ")."
    elseif #needed > 0 then
        reply = "[Manastormer] Thanks! We are currently full on "
            .. table.concat(full, "/") .. ", but still need "
            .. table.concat(needed, "/") .. "."
    else
        reply = "[Manastormer] Thanks! We are currently full on "
            .. table.concat(full, "/") .. "."
    end

    local key = NameKey(author)
    local previous = whisperCapacityReplies[key]
    local now = GetTime()
    if previous and previous.reply == reply and now - previous.at < 120 then
        return
    end
    if previous and now - previous.at < 30 then
        return
    end
    whisperCapacityReplies[key] = { reply = reply, at = now }
    SendChatMessage(reply, "WHISPER", nil, author)
    Print("Capacity reply sent to " .. ShortName(author) .. ": " .. reply)
end

local function TrackChaoticLink(...)
    if not sessionActive
        or not IsManastormerAwake()
        or not HasAutomationAuthority()
        or not IsInsideManastorm()
        or (db and db.chaoticLinkReporting == false)
    then
        return
    end
    local _, combatEvent, _, _, _, destGUID, destName, _, spellID, _, _, _, amount = ...
    if tonumber(spellID) ~= 93459 or not destGUID then
        return
    end

    local now = GetTime()
    local function AnnounceBroken()
        local lastBroken = chaoticLinkBrokenAt[destGUID]
        chaoticLinkStacks[destGUID] = 0
        chaoticLinkLastAnnouncedStack[destGUID] = 0
        if lastBroken and now - lastBroken < 12 then return end
        chaoticLinkBrokenAt[destGUID] = now
        chaoticLinkLastWarning[destGUID] = now
        WarnRaid("CHAOTIC LINK - " .. (destName or "Boss") .. ": 0 STACKS - LINK BROKEN!")
    end

    if combatEvent == "SPELL_AURA_APPLIED" then
        chaoticLinkStacks[destGUID] = 1
        chaoticLinkLastWarning[destGUID] = nil
        chaoticLinkLastAnnouncedStack[destGUID] = nil
        chaoticLinkBrokenAt[destGUID] = nil
    elseif combatEvent == "SPELL_AURA_APPLIED_DOSE" then
        chaoticLinkStacks[destGUID] = tonumber(amount) or chaoticLinkStacks[destGUID]
        chaoticLinkBrokenAt[destGUID] = nil
    elseif combatEvent == "SPELL_AURA_REMOVED_DOSE" then
        local remaining = tonumber(amount) or 0
        local previous = chaoticLinkStacks[destGUID]
        chaoticLinkStacks[destGUID] = remaining
        if remaining <= 0 then
            AnnounceBroken()
            return
        end
        if previous and remaining >= previous then return end
        if chaoticLinkLastAnnouncedStack[destGUID] == remaining then return end
        local lastWarning = chaoticLinkLastWarning[destGUID]
        local warningInterval = db and tonumber(db.chaoticLinkInterval) or 4
        warningInterval = math.max(1, math.min(10, warningInterval))
        if not lastWarning or now - lastWarning >= warningInterval then
            chaoticLinkLastWarning[destGUID] = now
            chaoticLinkLastAnnouncedStack[destGUID] = remaining
            WarnRaid("CHAOTIC LINK - " .. (destName or "Boss") .. ": " .. remaining .. " stack(s) remaining!")
        end
    elseif combatEvent == "SPELL_AURA_REMOVED" then
        AnnounceBroken()
    end
end

local function AddSignup(name, roles)
    name = Trim(name)
    local signup = FindSignup(name)
    if signup then
        signup.roles = roles
        signup.updated = time()
        Print(ShortName(name) .. " updated: " .. RoleText(roles))
    else
        db.nextOrder = (db.nextOrder or 0) + 1
        signup = {
            name = name,
            roles = roles,
            order = db.nextOrder,
            updated = time(),
        }
        table.insert(db.signups, signup)
        Print(ShortName(name) .. " signed: " .. RoleText(roles))
    end
    Sync.BroadcastSignup(signup)
end

local function RemoveSignup(name)
    local removed = false
    local index
    for index = #db.signups, 1, -1 do
        if SameName(db.signups[index].name, name) then
            table.remove(db.signups, index)
            removed = true
        end
    end
    if removed then Sync.BroadcastSignupDelete(name) end
end

function Sync.ClearAllSignups()
    local _, signup
    for _, signup in ipairs(db.signups) do
        Sync.BroadcastSignupDelete(signup.name)
    end
    db.signups = {}
end

function Sync.SendFarewellWhisper(name, level, departed)
    if not name or IsSelf(name) or type(SendChatMessage) ~= "function" then return end
    Sync.farewellSent = Sync.farewellSent or {}
    local farewellKey = NameKey(name) .. ":" .. tostring(level)
    local lastSent = Sync.farewellSent[farewellKey]
    if lastSent and GetTime() - lastSent < 60 then return end
    Sync.farewellSent[farewellKey] = GetTime()
    local levelReason
    if departed then
        levelReason = "You left at level " .. tostring(level) .. ", helping protect the group scaling. "
    else
        levelReason = "You were removed at level " .. tostring(level) .. " to protect the group scaling. "
    end
    SendChatMessage(
        "Thanks for joining our Manastorm group, and good luck with your rolls! "
            .. levelReason .. "Download Manastormer: "
            .. "https://github.com/nesscafe213-bit/Manastormer",
        "WHISPER",
        nil,
        name
    )
end

function Sync.UpdateResetButton(text)
    if Sync.resetButton then
        Sync.resetButton:SetText(text or "DISBAND + AUTO REINVITE")
    end
end

function Sync.ResetGroupMessage(message)
    LocalWarning(message)
    if InRaid() then
        SendChatMessage("[Manastormer] " .. message, "RAID")
    elseif InParty() then
        SendChatMessage("[Manastormer] " .. message, "PARTY")
    end
end

function Sync.SaveRaidResetSnapshot()
    local snapshot = { created = time(), members = {} }
    local _, member
    for _, member in ipairs(GetRoster()) do
        local level = VerifiedMemberLevel(member)
        if not IsSelf(member.name) and (not level or level < 60) and not IsBlocked60(member.name) then
            table.insert(snapshot.members, {
                name = member.name,
                subgroup = member.subgroup or 1,
                level = level,
            })
        end
    end
    db.resetSnapshot = snapshot
    return snapshot
end

function Sync.BeginRaidReset()
    if not InRaid() or not IsRaidLeader() then
        LocalWarning("Only the raid leader can start Disband + Auto Reinvite.")
        return
    end
    if Sync.raidReset then
        LocalWarning("A disband/reinvite sequence is already active.")
        return
    end
    local snapshot = Sync.SaveRaidResetSnapshot()
    if #snapshot.members == 0 then
        LocalWarning("There are no eligible players to snapshot and reinvite.")
        return
    end
    Sync.raidReset = {
        stage = "countdown",
        snapshot = snapshot,
        names = {},
        index = 1,
        nextAt = GetTime() + 5,
        retries = 0,
    }
    local _, member
    for _, member in ipairs(snapshot.members) do
        table.insert(Sync.raidReset.names, member.name)
    end
    db.autoReinvitePending = true
    Sync.UpdateResetButton("DISBANDING IN 5...")
    Sync.ResetGroupMessage(
        "Raid will disband in 5 seconds. The leader will confirm Ascension's secure disband control, then the saved group will be reinvited automatically after leaving the dungeon."
    )
end

function Sync.RemoveResetMember(name)
    if type(UninviteUnit) == "function" then
        return pcall(UninviteUnit, name)
    end
    if C_PartyInfo and type(C_PartyInfo.UninviteUnit) == "function" then
        return pcall(C_PartyInfo.UninviteUnit, name, "Manastorm reset", true)
    end
    return false
end

function Sync.InviteResetMember(name)
    if type(InviteUnit) == "function" then
        return pcall(InviteUnit, name)
    end
    if C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" then
        return pcall(C_PartyInfo.InviteUnit, name)
    end
    return false
end

function Sync.FinishRaidReset(message)
    db.autoReinvitePending = false
    Sync.raidReset = nil
    if Sync.resetSecureButton and not (InCombatLockdown and InCombatLockdown()) then
        Sync.resetSecureButton:Hide()
        Sync.resetSecureButton:SetAttribute("macrotext", "")
    end
    Sync.UpdateResetButton()
    LocalWarning(message)
end

function Sync.MoveResetToWaitingExit()
    local reset = Sync.raidReset
    if not reset then return end
    if Sync.resetSecureButton and not (InCombatLockdown and InCombatLockdown()) then
        Sync.resetSecureButton:Hide()
        Sync.resetSecureButton:SetAttribute("macrotext", "")
    end
    reset.stage = "waiting_exit"
    reset.index = 1
    reset.nextAt = GetTime() + 1
    Sync.UpdateResetButton("WAITING OUTSIDE DUNGEON...")
    LocalWarning("Raid disbanded. Auto reinvite is armed for when you leave the dungeon.")
end

function Sync.PrepareSecureResetBatch()
    local reset = Sync.raidReset
    local button = Sync.resetSecureButton
    if not reset or not button then
        Sync.FinishRaidReset("The secure disband control could not be created.")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        reset.stage = "waiting_combat"
        reset.nextAt = GetTime() + 1
        Sync.UpdateResetButton("WAITING FOR COMBAT...")
        return
    end

    local macroText = ""
    local count = 0
    local _, name
    for _, name in ipairs(reset.names) do
        if IsGrouped(name) and not IsSelf(name) then
            local line = "/uninvite " .. name
            local candidate = macroText == "" and line or (macroText .. "\n" .. line)
            if #candidate <= 240 then
                macroText = candidate
                count = count + 1
            end
        end
    end
    if count == 0 then
        Sync.MoveResetToWaitingExit()
        return
    end

    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", macroText)
    button:SetText("CLICK TO DISBAND SAVED RAID (" .. count .. ")")
    PositionKickButton()
    button:Show()
    reset.stage = "await_secure_click"
    reset.nextAt = GetTime() + 86400
    Sync.UpdateResetButton("CLICK RED DISBAND CONTROL")
    LocalWarning(
        "Ascension requires a secure click to remove the saved raid. Click the red DISBAND SAVED RAID control now."
    )
end

function Sync.ProcessRaidReset()
    local reset = Sync.raidReset
    if not reset or GetTime() < (reset.nextAt or 0) then return end

    if reset.stage == "countdown" or reset.stage == "waiting_combat" then
        if InCombatLockdown and InCombatLockdown() then
            reset.stage = "waiting_combat"
            reset.nextAt = GetTime() + 1
            Sync.UpdateResetButton("WAITING FOR COMBAT...")
            return
        end
        reset.stage = "secure_remove"
        reset.index = 1
        reset.retries = 0
        reset.nextAt = 0
        Sync.UpdateResetButton("PREPARING SECURE DISBAND...")
    end

    if reset.stage == "secure_remove" then
        Sync.PrepareSecureResetBatch()
        return
    end

    if reset.stage == "secure_verify" then
        reset.stage = "secure_remove"
        reset.nextAt = 0
        Sync.PrepareSecureResetBatch()
        return
    end

    if reset.stage == "waiting_exit" then
        local inInstance = type(IsInInstance) == "function" and IsInInstance()
        if inInstance then
            reset.nextAt = GetTime() + 2
            return
        end
        reset.stage = "invite_first"
        reset.index = 1
        reset.inviteSentAt = nil
        reset.nextAt = 0
        Sync.UpdateResetButton("AUTO REINVITING...")
        LocalWarning("Outside the dungeon. Starting automatic reinvites from the saved snapshot.")
    end

    if reset.stage == "invite_first" then
        if InCombatLockdown and InCombatLockdown() then
            reset.nextAt = GetTime() + 1
            return
        end
        if InRaid() or InParty() then
            if InParty() and not InRaid() and type(ConvertToRaid) == "function" then
                pcall(ConvertToRaid)
            end
            reset.stage = "invite_rest"
            reset.index = 1
            reset.nextAt = GetTime() + 1
            return
        end
        local name = reset.names[reset.index]
        while name and (IsBlocked60(name) or IsSelf(name)) do
            reset.index = reset.index + 1
            reset.inviteSentAt = nil
            name = reset.names[reset.index]
        end
        if not name then
            Sync.FinishRaidReset("No saved player accepted the first reinvite. Snapshot remains saved.")
            return
        end
        if not reset.inviteSentAt then
            Sync.InviteResetMember(name)
            reset.inviteSentAt = GetTime()
            reset.nextAt = GetTime() + 1
        elseif GetTime() - reset.inviteSentAt >= 15 then
            reset.index = reset.index + 1
            reset.inviteSentAt = nil
            reset.nextAt = 0
        else
            reset.nextAt = GetTime() + 1
        end
        return
    end

    if reset.stage == "invite_rest" then
        if InCombatLockdown and InCombatLockdown() then
            reset.nextAt = GetTime() + 1
            return
        end
        if InParty() and not InRaid() and type(ConvertToRaid) == "function" then
            pcall(ConvertToRaid)
            reset.nextAt = GetTime() + 0.5
            return
        end
        local name = reset.names[reset.index]
        while name and (IsSelf(name) or IsGrouped(name) or IsBlocked60(name)) do
            reset.index = reset.index + 1
            name = reset.names[reset.index]
        end
        if not name then
            Sync.FinishRaidReset("Automatic reinvite pass complete. Declined or offline players remain in the saved snapshot.")
            return
        end
        Sync.InviteResetMember(name)
        reset.index = reset.index + 1
        reset.nextAt = GetTime() + 0.8
    end
end

local function ToggleManualRole(name, role)
    if not name or not role then
        return
    end
    local signup = FindSignup(name)
    if not signup then
        db.nextOrder = (db.nextOrder or 0) + 1
        signup = {
            name = name,
            roles = {},
            order = db.nextOrder,
            updated = time(),
        }
        table.insert(db.signups, signup)
    end
    signup.roles[role] = not signup.roles[role]
    signup.updated = time()

    if not signup.roles.tank
        and not signup.roles.healer
        and not signup.roles.aura
        and not signup.roles.dps
    then
        RemoveSignup(name)
        Print(ShortName(name) .. " has no Mana Storm role.")
    else
        Print(ShortName(name) .. " manually set: " .. RoleText(signup.roles))
        Sync.BroadcastSignup(signup)
    end
    Refresh()
end

Sync.roleMenuValues = {
    tank = "MANASTORMER_ROLE_TANK",
    healer = "MANASTORMER_ROLE_HEALER",
    dps = "MANASTORMER_ROLE_DPS",
    aura = "MANASTORMER_ROLE_AURA",
    clear = "MANASTORMER_ROLE_CLEAR",
}

function Sync.RoleMenuTargetName(dropdown)
    if not dropdown then return nil end
    if dropdown.unit and type(UnitName) == "function" and UnitName(dropdown.unit) then
        return UnitFullName(dropdown.unit)
    end
    return dropdown.name
end

function Sync.AddRoleMenuOption(menuName, value, afterValue)
    local menu = UnitPopupMenus and UnitPopupMenus[menuName]
    if type(menu) ~= "table" then return end
    local _, existing
    for _, existing in ipairs(menu) do
        if existing == value then return end
    end
    local index, menuValue
    for index, menuValue in ipairs(menu) do
        if menuValue == afterValue then
            table.insert(menu, index + 1, value)
            return
        end
    end
    table.insert(menu, math.max(1, #menu), value)
end

function Sync.UpdateRoleMenuVisibility()
    local dropdown = UIDROPDOWNMENU_INIT_MENU
    local level = UIDROPDOWNMENU_MENU_LEVEL or 1
    if not dropdown or not UnitPopupShown or not UnitPopupShown[level] then return end
    local targetName = Sync.RoleMenuTargetName(dropdown)
    local visible = targetName and (IsSelf(targetName) or IsGrouped(targetName))
    local menuName = UIDROPDOWNMENU_MENU_VALUE or dropdown.which
    local menu = UnitPopupMenus and UnitPopupMenus[menuName]
    if type(menu) ~= "table" then return end
    local index, value
    for index, value in ipairs(menu) do
        if value == Sync.roleMenuValues.tank
            or value == Sync.roleMenuValues.healer
            or value == Sync.roleMenuValues.dps
            or value == Sync.roleMenuValues.aura
            or value == Sync.roleMenuValues.clear
        then
            UnitPopupShown[level][index] = visible and 1 or 0
        end
    end
end

function Sync.InstallRoleMenus()
    if Sync.roleMenusInstalled
        or type(UnitPopupButtons) ~= "table"
        or type(UnitPopupMenus) ~= "table"
        or type(hooksecurefunc) ~= "function"
        or type(UnitPopup_HideButtons) ~= "function"
        or type(UnitPopup_OnClick) ~= "function"
    then
        return
    end
    Sync.roleMenusInstalled = true
    UnitPopupButtons[Sync.roleMenuValues.tank] = { text = "Manastormer: Toggle Tank", dist = 0 }
    UnitPopupButtons[Sync.roleMenuValues.healer] = { text = "Manastormer: Toggle Healer", dist = 0 }
    UnitPopupButtons[Sync.roleMenuValues.dps] = { text = "Manastormer: Toggle DPS", dist = 0 }
    UnitPopupButtons[Sync.roleMenuValues.aura] = { text = "Manastormer: Toggle Aura", dist = 0 }
    UnitPopupButtons[Sync.roleMenuValues.clear] = { text = "Manastormer: Clear Roles", dist = 0 }

    local _, menuName
    for _, menuName in ipairs({ "SELF", "PLAYER", "PARTY", "RAID_PLAYER" }) do
        local afterValue = "INSPECT"
        Sync.AddRoleMenuOption(menuName, Sync.roleMenuValues.tank, afterValue)
        afterValue = Sync.roleMenuValues.tank
        Sync.AddRoleMenuOption(menuName, Sync.roleMenuValues.healer, afterValue)
        afterValue = Sync.roleMenuValues.healer
        Sync.AddRoleMenuOption(menuName, Sync.roleMenuValues.dps, afterValue)
        afterValue = Sync.roleMenuValues.dps
        Sync.AddRoleMenuOption(menuName, Sync.roleMenuValues.aura, afterValue)
        afterValue = Sync.roleMenuValues.aura
        Sync.AddRoleMenuOption(menuName, Sync.roleMenuValues.clear, afterValue)
    end

    hooksecurefunc("UnitPopup_HideButtons", Sync.UpdateRoleMenuVisibility)
    hooksecurefunc("UnitPopup_OnClick", function(button)
        if not button then return end
        local dropdown = UIDROPDOWNMENU_INIT_MENU
        local targetName = Sync.RoleMenuTargetName(dropdown)
        if not targetName or (not IsSelf(targetName) and not IsGrouped(targetName)) then return end
        if button.value == Sync.roleMenuValues.clear then
            RemoveSignup(targetName)
            Print(ShortName(targetName) .. " roles cleared.")
            Refresh()
            return
        end
        local role, value
        for role, value in pairs(Sync.roleMenuValues) do
            if role ~= "clear" and button.value == value then
                ToggleManualRole(targetName, role)
                return
            end
        end
    end)
end

local function CurrentLevel60Members()
    local players = {}
    local _, member
    for _, member in ipairs(GetRoster()) do
        local level = VerifiedMemberLevel(member)
        if not IsSelf(member.name) and level and level >= 60 then
            table.insert(players, member.name)
        end
    end
    table.sort(players, function(left, right)
        return ShortName(left):lower() < ShortName(right):lower()
    end)
    return players
end

-- Keep the protected level-60 fallback independent from the main window.
-- Parenting or anchoring it to the panel causes Ascension to protect the whole
-- panel, which prevents compact/full layout changes during combat.
PositionKickButton = function()
    if not kick60Button or not kick59Button or not panel then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    local left = panel:GetLeft()
    local top = panel:GetTop()
    if not left or not top then
        return
    end
    kick60Button:ClearAllPoints()
    kick60Button:SetPoint(
        "TOPLEFT",
        UIParent,
        "BOTTOMLEFT",
        left + 10,
        top - (db and db.minimized and 112 or 387)
    )
    kick59Button:ClearAllPoints()
    kick59Button:SetPoint(
        "TOPLEFT",
        UIParent,
        "BOTTOMLEFT",
        left + 10,
        top - (db and db.minimized and 144 or 419)
    )
    if Sync.resetSecureButton then
        Sync.resetSecureButton:ClearAllPoints()
        Sync.resetSecureButton:SetPoint(
            "TOPLEFT",
            UIParent,
            "BOTTOMLEFT",
            left + 10,
            top - (db and db.minimized and 176 or 451)
        )
    end
end

local function LiveGroupedLevel(name)
    local _, member
    for _, member in ipairs(GetRoster()) do
        if SameName(member.name, name) then
            return VerifiedMemberLevel(member), member.name
        end
    end
    return nil, nil
end

UpdateKickButton = function()
    if not kick60Button then
        return
    end
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not sessionActive or not IsManastormerAwake() then
        if not inCombat then kick60Button:Hide() end
        return
    end
    local kickName
    local name
    for name in pairs(pendingLevel60Kicks) do
        local liveLevel = LiveGroupedLevel(name)
        if liveLevel and liveLevel >= 60 then
            kickName = name
            break
        else
            pendingLevel60Kicks[name] = nil
        end
    end

    if not HasAutomationAuthority() then
        if not inCombat then
            kick60Button:Hide()
        end
        return
    end

    if not kickName then
        if inCombat then
            return
        end
        kick60Button:Hide()
        return
    end

    if inCombat then
        return
    else
        kick60Button:SetText("KICK LEVEL 60: " .. ShortName(kickName))
        kick60Button:Enable()
        kick60Button:SetAttribute("type", "macro")
        kick60Button:SetAttribute("macrotext", "/uninvite " .. kickName)
        kick60Button.targetName = kickName
    end
    PositionKickButton()
    kick60Button:Show()
end

UpdateKick59Button = function()
    if not kick59Button then return end
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not sessionActive or not IsManastormerAwake() then
        if not inCombat then kick59Button:Hide() end
        return
    end
    local kickName
    local name
    for name in pairs(pendingLevel59Kicks) do
        local liveLevel, liveName = LiveGroupedLevel(name)
        if liveLevel == 59 and liveName and not IsSelf(liveName) then
            kickName = liveName
            break
        else
            pendingLevel59Kicks[name] = nil
        end
    end

    if not IsManastormerAwake() or not HasAutomationAuthority() or not kickName then
        if not inCombat then kick59Button:Hide() end
        return
    end
    if inCombat then return end

    kick59Button:SetText("KICK LEVEL 59: " .. ShortName(kickName))
    kick59Button:Enable()
    kick59Button:SetAttribute("type", "macro")
    kick59Button:SetAttribute("macrotext", "/uninvite " .. kickName)
    kick59Button.targetName = kickName
    PositionKickButton()
    kick59Button:Show()
end

local function AttemptLevel60Kick(name)
    if not sessionActive
        or not IsManastormerAwake()
        or not HasAutomationAuthority()
        or not ManastormAutomationAllowed()
        or not name
        or IsSelf(name)
        or not IsGrouped(name)
    then
        return
    end
    pendingLevel60Kicks[name] = true
    if SetMinimized then
        SetMinimized(true)
    end
    UpdateKickButton()

    if not CanManageRaid() then
        LocalWarning("LEVEL 60: " .. ShortName(name) .. " must be removed by the raid leader.")
        return
    end
    LocalWarning(
        "LEVEL 60: click the red KICK LEVEL 60 button for "
            .. ShortName(name) .. (InCombatLockdown and InCombatLockdown()
                and " as soon as combat ends." or ".")
    )
end

local function UpdateRosterDepartures()
    local current = {}
    local _, member
    for _, member in ipairs(GetRoster()) do
        current[NameKey(member.name)] = member.name
    end
    if previousRosterNames then
        local key, name
        for key, name in pairs(previousRosterNames) do
            if not current[key] and not IsSelf(name) then
                local pending59Name
                for pending59Name in pairs(pendingLevel59Kicks) do
                    if SameName(pending59Name, name) then
                        Sync.SendFarewellWhisper(name, 59, true)
                        break
                    end
                end
                table.insert(recentDepartures, {
                    name = ShortName(name),
                    at = GetTime(),
                })
                Schedule(31, function()
                    Refresh()
                end)
            end
        end
    end
    previousRosterNames = current

    local index = #recentDepartures
    while index >= 1 do
        if GetTime() - recentDepartures[index].at > 30 then
            table.remove(recentDepartures, index)
        end
        index = index - 1
    end

    local pendingName
    for pendingName in pairs(pendingLevel60Kicks) do
        if not IsGrouped(pendingName) then
            pendingLevel60Kicks[pendingName] = nil
        end
    end
    for pendingName in pairs(pendingLevel59Kicks) do
        if not IsGrouped(pendingName) then
            pendingLevel59Kicks[pendingName] = nil
        end
    end
    UpdateKickButton()
    UpdateKick59Button()
end

local function WarnWipeForLevel60(newLevel)
    if not sessionActive or not IsManastormerAwake() or not HasAutomationAuthority() then
        return
    end
    local players = CurrentLevel60Members()
    if #players == 0 then
        lastWipeWarningKey = nil
        return
    end
    local shortNames = {}
    local _, name
    for _, name in ipairs(players) do
        table.insert(shortNames, ShortName(name))
        local _, member
        for _, member in ipairs(GetRoster()) do
            if SameName(member.name, name) then
                RememberLevel60(member.name, member.unit)
                break
            end
        end
        pendingLevel60Kicks[name] = true
    end
    local warningKey = tostring(newLevel or "?") .. ":" .. table.concat(shortNames, ",")
    if warningKey == lastWipeWarningKey then
        return
    end
    lastWipeWarningKey = warningKey
    if SetMinimized then
        SetMinimized(true)
    end
    UpdateKickButton()

    local message = "WIPE! LEVEL 60 ENTERED MANASTORM: "
        .. table.concat(shortNames, ", ")
        .. " - THIS LEVEL SCALED TO 60!"
    local repeatNumber
    for repeatNumber = 0, 2 do
        Schedule(repeatNumber * 0.8, function()
            WarnRaid(message)
        end)
    end
end

local function CheckLevels()
    if not sessionActive
        or not IsManastormerAwake()
        or not HasAutomationAuthority()
        or not ManastormAutomationAllowed()
    then
        return
    end
    local _, member
    for _, member in ipairs(GetRoster()) do
        local level = VerifiedMemberLevel(member)
        local signup = FindSignup(member.name)
        local pending59Name
        for pending59Name in pairs(pendingLevel59Kicks) do
            if SameName(pending59Name, member.name) and level ~= 59 then
                pendingLevel59Kicks[pending59Name] = nil
            end
        end
        if level == 59 and not IsSelf(member.name) then
            pendingLevel59Kicks[member.name] = true
        end
        if level and level > 0 and level < 60 then
            ClearLevel60Record(member.name, member.unit)
        end
        if sessionActive and signup and level == 59 then
            local key = member.name .. ":59:" .. RoleText(signup.roles)
            if not warningSeen[key] then
                warningSeen[key] = true
                WarnRaid(ShortName(member.name) .. " is LEVEL 59 (" .. RoleText(signup.roles) .. ")!")
            end
        end
        if level and level >= 60 and not IsSelf(member.name) then
            local key = member.name .. ":60"
            if not warningSeen[key] then
                warningSeen[key] = true
                RememberLevel60(member.name, member.unit)
                WarnRaid(ShortName(member.name) .. " HIT LEVEL 60! STOP - removing them from the group.")
            end
            if not pendingLevel60Kicks[member.name] then
                AttemptLevel60Kick(member.name)
            end
        end
    end
    UpdateKick59Button()
end

local function SetRoleBox(role, count, names)
    local box = roleBoxes[role]
    local target = ROLE_TARGET[role]
    local ready = count >= target
    if ready then
        box:SetBackdropColor(unpack(UI_COLORS.panel2))
        box:SetBackdropBorderColor(unpack(UI_COLORS.green))
        box.count:SetTextColor(unpack(UI_COLORS.green))
    else
        box:SetBackdropColor(unpack(UI_COLORS.panel2))
        box:SetBackdropBorderColor(unpack(UI_COLORS.red))
        box.count:SetTextColor(unpack(UI_COLORS.red))
    end
    box.count:SetText(count .. "/" .. target)
    if role == "aura" and box.warning then
        local covered, missingGroups = AuraCoverage()
        box.missingAuraGroups = missingGroups
        if covered then
            box.warning:Hide()
        else
            box.warning:Show()
        end
    end
    if #names > 0 then
        box.names:SetText(table.concat(names, ", "))
    else
        box.names:SetText("none")
    end
end

Refresh = function()
    if not panel then
        return
    end
    local counts, names = RoleCounts()
    local auraGroupsCovered, missingAuraGroups = AuraCoverage()
    local _, role
    for _, role in ipairs(ROLE_ORDER) do
        SetRoleBox(role, counts[role], names[role])
    end

    local level59Players = {}
    local _, member
    for _, member in ipairs(GetRoster()) do
        local signup = FindSignup(member.name)
        local level = member.unit and UnitLevel(member.unit) or member.level
        if sessionActive and signup and level == 59 then
            table.insert(
                level59Players,
                ShortName(member.name) .. " (" .. RoleText(signup.roles) .. ")"
            )
        end
    end
    if #level59Players > 0 then
        level59Text:SetText("|cffffaa33LEVEL 59:|r " .. table.concat(level59Players, ", "))
    else
        level59Text:SetText("|cff888888LEVEL 59: none|r")
    end

    if compactText then
        local compactLines = {}
        local groupSize = GroupSize()
        local missingPlayers = math.max(0, MAX_PLAYERS - groupSize)
        table.insert(
            compactLines,
            "|cffe8c96aRaid " .. groupSize .. "/" .. MAX_PLAYERS .. "|r"
                .. (missingPlayers > 0 and "  |cffff7777Missing " .. missingPlayers .. " player(s)|r" or "  |cff55ff66Full|r")
        )

        if sessionActive and not HasAutomationAuthority() then
            table.insert(compactLines, "|cffaaaaaaSILENT - you are not leader or assistant|r")
        end

        local tankNeeded = math.max(0, ROLE_TARGET.tank - counts.tank)
        local healerNeeded = math.max(0, ROLE_TARGET.healer - counts.healer)
        local auraNeeded = math.max(0, ROLE_TARGET.aura - counts.aura)
        if sessionActive and (tankNeeded > 0 or healerNeeded > 0 or auraNeeded > 0) then
            table.insert(
                compactLines,
                "|cffffcc66Need:|r " .. tankNeeded .. " Tank  "
                    .. healerNeeded .. " Healer  " .. auraNeeded .. " Aura"
            )
        elseif sessionActive then
            table.insert(compactLines, "|cff55ff66Tank, Healer and Aura coverage ready|r")
        end

        if sessionActive and not auraGroupsCovered then
            table.insert(
                compactLines,
                "|cffffcc33! Missing Aura in Group "
                    .. table.concat(missingAuraGroups, ", ") .. "|r"
            )
        end

        if newerVersionAvailable then
            table.insert(
                compactLines,
                "|cffffcc33New Manastormer v" .. newerVersionAvailable .. " available|r"
            )
        end

        table.insert(compactLines, Sync.StatusLine())

        if #level59Players > 0 then
            table.insert(compactLines, "|cffffaa33Level 59:|r " .. table.concat(level59Players, ", "))
        end

        local level60Players = sessionActive and CurrentLevel60Members() or {}
        if #level60Players > 0 then
            local shortNames = {}
            local _, name
            for _, name in ipairs(level60Players) do
                table.insert(shortNames, ShortName(name))
            end
            table.insert(compactLines, "|cffff3333LEVEL 60 - KICK: " .. table.concat(shortNames, ", ") .. "|r")
        end

        local departureNames = {}
        local departureCount = 0
        local index = #recentDepartures
        while index >= 1 do
            if GetTime() - recentDepartures[index].at > 30 then
                table.remove(recentDepartures, index)
            else
                departureCount = departureCount + 1
                if #departureNames < 3 then
                    table.insert(departureNames, recentDepartures[index].name)
                end
            end
            index = index - 1
        end
        if sessionActive and #departureNames > 0 then
            local extra = departureCount - #departureNames
            table.insert(
                compactLines,
                "|cffff8888Left:|r " .. table.concat(departureNames, ", ")
                    .. (extra > 0 and " +" .. extra .. " more" or "")
            )
        end
        compactText:SetText(table.concat(compactLines, "\n"))
        if panelIsMinimized then
            local compactHeight = math.max(68, (#compactLines * 12) + 4)
            compactText:SetHeight(compactHeight)
            panel:SetHeight(math.max(116, compactHeight + 48))
        end
    end

    local hasAuthority = HasAutomationAuthority()
    local activityAllowed = ManastormAutomationAllowed()
    local state
    if not hasAuthority then
        state = "|cffaaaaaaSILENT (NOT LEAD/ASSIST)|r"
    elseif sessionActive and not activityAllowed then
        state = "|cffffcc55SUSPENDED (DUNGEON GROUP)|r"
    else
        state = sessionActive and "|cff55ff66LISTENING|r" or "|cffaaaaaaPAUSED|r"
    end
    local groupSize = GroupSize()
    local filledTankSlots = math.min(counts.tank, ROLE_TARGET.tank)
    local filledHealerSlots = math.min(counts.healer, ROLE_TARGET.healer)
    local assignedGroupSize = groupSize - (SelfHasMainRole() and 0 or 1)
    local dpsCount = math.max(0, assignedGroupSize - filledTankSlots - filledHealerSlots)
    local tankNeeded = math.max(0, ROLE_TARGET.tank - counts.tank)
    local healerNeeded = math.max(0, ROLE_TARGET.healer - counts.healer)
    local dpsTarget = DPSTarget()
    local dpsNeeded = math.max(0, dpsTarget - dpsCount)
    local auraNeeded = math.max(0, ROLE_TARGET.aura - counts.aura)
    local needs = tankNeeded .. "T " .. healerNeeded .. "H "
        .. dpsNeeded .. "D " .. auraNeeded .. "A"
    local compositionLine
    if tankNeeded == 0 and healerNeeded == 0 and dpsNeeded == 0 and auraNeeded == 0 then
        compositionLine = state .. "  " .. groupSize .. "/" .. MAX_PLAYERS
            .. "  DPS " .. dpsCount .. "/" .. dpsTarget .. "  |cff55ff66READY|r"
    else
        compositionLine = state .. "  " .. groupSize .. "/" .. MAX_PLAYERS
            .. "  DPS " .. dpsCount .. "/" .. dpsTarget .. "  |cffff6666NEED " .. needs .. "|r"
    end
    statusText:SetText(compositionLine .. "\n" .. Sync.StatusLine())
    listenButton:SetText(not hasAuthority and "Silent" or (sessionActive and "Pause" or "Listen"))
end

local BUTTON_THEMES = {
    blue = {
        normal = UI_COLORS.panel2,
        hover = { 0.11, 0.12, 0.19, 1 },
        border = UI_COLORS.border,
    },
    green = {
        normal = UI_COLORS.panel2,
        hover = { 0.07, 0.17, 0.12, 1 },
        border = { 0.20, 0.55, 0.32, 1 },
    },
    red = {
        normal = UI_COLORS.panel2,
        hover = { 0.20, 0.075, 0.085, 1 },
        border = { 0.58, 0.20, 0.21, 1 },
    },
    slate = {
        normal = UI_COLORS.panel2,
        hover = { 0.11, 0.12, 0.19, 1 },
        border = UI_COLORS.border,
    },
}

local function TrackFullUI(element)
    table.insert(fullUIElements, element)
    return element
end

local function TrackSettingsUI(element)
    table.insert(settingsUIElements, element)
    return element
end

local function ApplyPageVisibility()
    local minimized = db and db.minimized
    local _, element
    for _, element in ipairs(fullUIElements) do
        if minimized or activePage ~= "raid" then element:Hide() else element:Show() end
    end
    for _, element in ipairs(settingsUIElements) do
        if minimized or activePage ~= "settings" then element:Hide() else element:Show() end
    end
    if pageButton then
        if minimized then
            pageButton:Hide()
        else
            pageButton:Show()
            pageButton:SetText(activePage == "settings" and "RAID" or "SETTINGS")
        end
    end
end

local function AttachTooltip(frame, title, description)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, unpack(UI_COLORS.gold))
        if description and description ~= "" then
            GameTooltip:AddLine(description, UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3], true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function AttachRoleTooltip(frame, role, description)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        local counts, names = RoleCounts()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(
            ROLE_LABEL[role] .. "  " .. counts[role] .. "/" .. ROLE_TARGET[role],
            unpack(UI_COLORS.gold)
        )
        GameTooltip:AddLine(description, UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3], true)
        GameTooltip:AddLine(" ")

        if role == "aura" then
            local covered, missingGroups = AuraCoverage()
            if not covered then
                GameTooltip:AddLine(
                    "CAUTION: No Aura in Group " .. table.concat(missingGroups, ", "),
                    1,
                    0.8,
                    0.15,
                    true
                )
                GameTooltip:AddLine(" ")
            end
            local found = false
            local _, member
            for _, member in ipairs(GetRoster()) do
                local signup = FindSignup(member.name)
                if signup
                    and signup.roles
                    and signup.roles.aura
                    and (IsSelf(member.name) or not IsBlocked60(member.name))
                then
                    found = true
                    GameTooltip:AddDoubleLine(
                        ShortName(member.name),
                        "Group " .. tostring(member.subgroup or 1),
                        1,
                        1,
                        1,
                        0.45,
                        1,
                        0.65
                    )
                end
            end
            if not found then
                GameTooltip:AddLine("No Aura players assigned.", 0.65, 0.68, 0.72)
            end
        elseif #names[role] > 0 then
            GameTooltip:AddLine("Players:", 0.45, 1, 0.65)
            local _, name
            for _, name in ipairs(names[role]) do
                GameTooltip:AddLine(name, 1, 1, 1)
            end
        else
            GameTooltip:AddLine("No players assigned.", 0.65, 0.68, 0.72)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function StyleButton(button, themeName, tooltipTitle, tooltipBody)
    local theme = BUTTON_THEMES[themeName or "blue"] or BUTTON_THEMES.blue
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    button:SetBackdropColor(unpack(theme.normal))
    button:SetBackdropBorderColor(unpack(theme.border))

    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT_BODY, 11, "")
    label:SetPoint("CENTER", 0, 0)
    label:SetTextColor(unpack(UI_COLORS.text))
    button:SetFontString(label)
    button.manastormerLabel = label
    button.manastormerTheme = theme

    button:EnableMouse(true)
    button:SetScript("OnEnter", function(self)
        local activeTheme = self.manastormerTheme
        self:SetBackdropColor(unpack(activeTheme.hover))
        self:SetBackdropBorderColor(unpack(UI_COLORS.gold))
        self.manastormerLabel:SetTextColor(unpack(UI_COLORS.gold))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipTitle or "Manastormer", unpack(UI_COLORS.gold))
        if tooltipBody and tooltipBody ~= "" then
            GameTooltip:AddLine(tooltipBody, UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3], true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(self.manastormerTheme.normal))
        self:SetBackdropBorderColor(unpack(self.manastormerTheme.border))
        self.manastormerLabel:SetTextColor(unpack(UI_COLORS.text))
        GameTooltip:Hide()
    end)
end

local function MakeButton(parent, text, width, callback, tooltipTitle, tooltipBody, themeName)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(width)
    button:SetHeight(28)
    StyleButton(button, themeName, tooltipTitle, tooltipBody)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return TrackFullUI(button)
end

RefreshSettingsPage = function()
    if not db or not db.requirements then return end
    for key, label in pairs(settingsValueLabels) do
        label:SetText(tostring(db.requirements[key] or 0))
    end
    if settingsSummaryText then
        settingsSummaryText:SetText(
            MAX_PLAYERS .. " Total  |  " .. ROLE_TARGET.tank .. " Tank  |  "
                .. ROLE_TARGET.healer .. " Heal  |  " .. DPSTarget() .. " DPS  |  "
                .. ROLE_TARGET.aura .. " Aura"
        )
    end
    if settingsChannelLabel then
        settingsChannelLabel:SetText(RecruitmentChannelText())
    end
    if settingsChaoticSlider and db.chaoticLinkInterval then
        settingsChaoticSlider:SetValue(db.chaoticLinkInterval)
    end
    if settingsChaoticLabel then
        settingsChaoticLabel:SetText(tostring(db.chaoticLinkInterval or 4) .. " sec")
    end
    if settingsChaoticCheck then
        local reporting = db.chaoticLinkReporting ~= false
        settingsChaoticCheck:SetChecked(reporting)
        settingsChaoticSlider:SetAlpha(reporting and 1 or 0.4)
        settingsChaoticLabel:SetAlpha(reporting and 1 or 0.4)
        if reporting then settingsChaoticSlider:Enable() else settingsChaoticSlider:Disable() end
    end
    if recruitmentButton then
        recruitmentButton:SetText("POST LFM TO " .. RecruitmentChannelText())
    end
end

local function AdjustRequirement(key, amount)
    local requirements = db.requirements
    requirements[key] = (tonumber(requirements[key]) or 0) + amount
    ApplyRequirements()
    RefreshSettingsPage()
    Refresh()
end

local function CreateSettingsUI(parent)
    local title = parent:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT_TITLE, 19, "")
    title:SetTextColor(unpack(UI_COLORS.gold))
    title:SetPoint("TOPLEFT", 24, -86)
    title:SetText("MANASTORM REQUIREMENTS")
    TrackSettingsUI(title)

    local description = parent:CreateFontString(nil, "OVERLAY")
    description:SetFont(FONT_BODY, 10, "")
    description:SetTextColor(unpack(UI_COLORS.muted))
    description:SetPoint("TOPLEFT", 25, -116)
    description:SetPoint("TOPRIGHT", -25, -116)
    description:SetHeight(24)
    description:SetJustifyH("LEFT")
    description:SetText("Set one group plan and one LFM channel. DPS = Total minus Tanks and Healers; Aura overlaps roles.")
    TrackSettingsUI(description)

    local rows = {
        { key = "total", label = "Total Players", y = -147 },
        { key = "tank", label = "Tanks", y = -185 },
        { key = "healer", label = "Healers", y = -223 },
        { key = "aura", label = "Auras", y = -261 },
    }
    local _, info
    for _, info in ipairs(rows) do
        local row = CreateFrame("Frame", nil, parent)
        row:SetWidth(360)
        row:SetHeight(36)
        row:SetPoint("TOPLEFT", 25, info.y)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row:SetBackdropColor(unpack(UI_COLORS.panel))
        row:SetBackdropBorderColor(unpack(UI_COLORS.border))
        TrackSettingsUI(row)

        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetFont(FONT_BODY, 12, "")
        label:SetTextColor(unpack(UI_COLORS.text))
        label:SetPoint("LEFT", 14, 0)
        label:SetText(info.label)

        local minus = CreateFrame("Button", nil, row)
        minus:SetWidth(32)
        minus:SetHeight(26)
        minus:SetPoint("RIGHT", -92, 0)
        StyleButton(minus, "slate", "Decrease " .. info.label, "Reduces this requirement by one.")
        minus:SetText("-")
        local minusKey = info.key
        minus:SetScript("OnClick", function() AdjustRequirement(minusKey, -1) end)

        local value = row:CreateFontString(nil, "OVERLAY")
        value:SetFont(FONT_TITLE, 17, "")
        value:SetTextColor(unpack(UI_COLORS.gold))
        value:SetWidth(42)
        value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        value:SetJustifyH("CENTER")
        settingsValueLabels[info.key] = value

        local plus = CreateFrame("Button", nil, row)
        plus:SetWidth(32)
        plus:SetHeight(26)
        plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
        StyleButton(plus, "slate", "Increase " .. info.label, "Raises this requirement by one.")
        plus:SetText("+")
        local plusKey = info.key
        plus:SetScript("OnClick", function() AdjustRequirement(plusKey, 1) end)
    end

    local channelRow = CreateFrame("Frame", nil, parent)
    channelRow:SetWidth(360)
    channelRow:SetHeight(36)
    channelRow:SetPoint("TOPLEFT", 25, -299)
    channelRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    channelRow:SetBackdropColor(unpack(UI_COLORS.panel))
    channelRow:SetBackdropBorderColor(unpack(UI_COLORS.border))
    TrackSettingsUI(channelRow)

    local channelTitle = channelRow:CreateFontString(nil, "OVERLAY")
    channelTitle:SetFont(FONT_BODY, 12, "")
    channelTitle:SetTextColor(unpack(UI_COLORS.text))
    channelTitle:SetPoint("LEFT", 14, 0)
    channelTitle:SetText("LFM Post Channel")

    local channelMinus = CreateFrame("Button", nil, channelRow)
    channelMinus:SetWidth(32)
    channelMinus:SetHeight(26)
    channelMinus:SetPoint("RIGHT", -132, 0)
    StyleButton(channelMinus, "slate", "Previous Channel", "Selects one lower numbered channel. Manastormer posts to one channel only.")
    channelMinus:SetText("-")
    channelMinus:SetScript("OnClick", function()
        db.recruitmentChannel = math.max(1, RecruitmentChannelNumber() - 1)
        RefreshSettingsPage()
    end)

    settingsChannelLabel = channelRow:CreateFontString(nil, "OVERLAY")
    settingsChannelLabel:SetFont(FONT_BODY, 10, "")
    settingsChannelLabel:SetTextColor(unpack(UI_COLORS.gold))
    settingsChannelLabel:SetWidth(82)
    settingsChannelLabel:SetPoint("LEFT", channelMinus, "RIGHT", 4, 0)
    settingsChannelLabel:SetJustifyH("CENTER")

    local channelPlus = CreateFrame("Button", nil, channelRow)
    channelPlus:SetWidth(32)
    channelPlus:SetHeight(26)
    channelPlus:SetPoint("LEFT", settingsChannelLabel, "RIGHT", 4, 0)
    StyleButton(channelPlus, "slate", "Next Channel", "Selects one higher numbered channel. Manastormer posts to one channel only.")
    channelPlus:SetText("+")
    channelPlus:SetScript("OnClick", function()
        db.recruitmentChannel = math.min(10, RecruitmentChannelNumber() + 1)
        RefreshSettingsPage()
    end)

    local chaoticRow = CreateFrame("Frame", nil, parent)
    chaoticRow:SetWidth(360)
    chaoticRow:SetHeight(36)
    chaoticRow:SetPoint("TOPLEFT", 25, -337)
    chaoticRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    chaoticRow:SetBackdropColor(unpack(UI_COLORS.panel))
    chaoticRow:SetBackdropBorderColor(unpack(UI_COLORS.border))
    TrackSettingsUI(chaoticRow)

    local chaoticTitle = chaoticRow:CreateFontString(nil, "OVERLAY")
    chaoticTitle:SetFont(FONT_BODY, 11, "")
    chaoticTitle:SetTextColor(unpack(UI_COLORS.text))
    chaoticTitle:SetPoint("LEFT", 12, 0)
    chaoticTitle:SetText("Chaotic Link")

    settingsChaoticCheck = CreateFrame("CheckButton", nil, chaoticRow, "UICheckButtonTemplate")
    settingsChaoticCheck:SetWidth(24)
    settingsChaoticCheck:SetHeight(24)
    settingsChaoticCheck:SetPoint("LEFT", 92, 0)
    settingsChaoticCheck:SetChecked(db.chaoticLinkReporting ~= false)
    local chaoticCheckLabel = chaoticRow:CreateFontString(nil, "OVERLAY")
    chaoticCheckLabel:SetFont(FONT_BODY, 9, "")
    chaoticCheckLabel:SetTextColor(unpack(UI_COLORS.gold))
    chaoticCheckLabel:SetPoint("LEFT", settingsChaoticCheck, "RIGHT", -1, 0)
    chaoticCheckLabel:SetText("Report")
    AttachTooltip(
        settingsChaoticCheck,
        "Report Chaotic Link",
        "When unchecked, Manastormer sends no Chaotic Link raid warnings, including the 0-stack LINK BROKEN warning."
    )
    settingsChaoticCheck:SetScript("OnClick", function(self)
        db.chaoticLinkReporting = self:GetChecked() and true or false
        chaoticLinkStacks = {}
        chaoticLinkLastWarning = {}
        chaoticLinkLastAnnouncedStack = {}
        chaoticLinkBrokenAt = {}
        RefreshSettingsPage()
    end)

    settingsChaoticLabel = chaoticRow:CreateFontString(nil, "OVERLAY")
    settingsChaoticLabel:SetFont(FONT_BODY, 10, "")
    settingsChaoticLabel:SetTextColor(unpack(UI_COLORS.gold))
    settingsChaoticLabel:SetWidth(42)
    settingsChaoticLabel:SetPoint("RIGHT", -8, 0)
    settingsChaoticLabel:SetJustifyH("RIGHT")

    settingsChaoticSlider = CreateFrame(
        "Slider",
        "ManastormerChaoticLinkSlider",
        chaoticRow,
        "OptionsSliderTemplate"
    )
    settingsChaoticSlider:SetWidth(102)
    settingsChaoticSlider:SetHeight(16)
    settingsChaoticSlider:SetPoint("RIGHT", settingsChaoticLabel, "LEFT", -8, 0)
    settingsChaoticSlider:SetMinMaxValues(1, 10)
    settingsChaoticSlider:SetValueStep(1)
    if _G.ManastormerChaoticLinkSliderLow then
        _G.ManastormerChaoticLinkSliderLow:SetText("")
    end
    if _G.ManastormerChaoticLinkSliderHigh then
        _G.ManastormerChaoticLinkSliderHigh:SetText("")
    end
    if _G.ManastormerChaoticLinkSliderText then
        _G.ManastormerChaoticLinkSliderText:SetText("")
    end
    settingsChaoticSlider:SetScript("OnValueChanged", function(self, value)
        value = Clamp(value, 1, 10)
        db.chaoticLinkInterval = value
        if settingsChaoticLabel then
            settingsChaoticLabel:SetText(value .. " sec")
        end
    end)
    AttachTooltip(
        settingsChaoticSlider,
        "Chaotic Link Spam Threshold",
        "Minimum seconds between normal Chaotic Link stack raid warnings. The 0-stack LINK BROKEN warning always fires immediately."
    )
    TrackSettingsUI(settingsChaoticSlider)

    settingsSummaryText = parent:CreateFontString(nil, "OVERLAY")
    settingsSummaryText:SetFont(FONT_BODY, 10, "")
    settingsSummaryText:SetTextColor(unpack(UI_COLORS.gold))
    settingsSummaryText:SetPoint("TOPLEFT", 20, -379)
    settingsSummaryText:SetPoint("TOPRIGHT", -20, -379)
    settingsSummaryText:SetHeight(18)
    settingsSummaryText:SetJustifyH("CENTER")
    TrackSettingsUI(settingsSummaryText)

    local reset = CreateFrame("Button", nil, parent)
    reset:SetWidth(160)
    reset:SetHeight(28)
    reset:SetPoint("TOP", 0, -403)
    StyleButton(reset, "red", "Reset Requirements", "Restores 15 players, 2 Tanks, 3 Healers and 3 Auras.")
    reset:SetText("RESET TO 15 PLAYER")
    reset:SetScript("OnClick", function()
        db.requirements = { total = 15, tank = 2, healer = 3, aura = 3 }
        ApplyRequirements()
        RefreshSettingsPage()
        Refresh()
    end)
    TrackSettingsUI(reset)

    RefreshSettingsPage()
end

local function WhisperRoleText(roles)
    if not roles then return "Unassigned" end
    local labels = {}
    if roles.tank then table.insert(labels, "Tank") end
    if roles.healer then table.insert(labels, "Healer") end
    if roles.dps then table.insert(labels, "DPS") end
    if roles.aura then table.insert(labels, "Aura") end
    return #labels > 0 and table.concat(labels, "/") or "Unassigned"
end

local function IsPriorityWhisper(roles)
    return roles and (roles.tank or roles.healer or roles.aura) and true or false
end

local function WhisperHighlight(roles)
    if roles and roles.aura then
        return { 0.17, 0.13, 0.035, 1 }, { 1, 0.78, 0.12, 1 }, { 1, 0.86, 0.28, 1 }
    elseif roles and roles.tank then
        return { 0.035, 0.10, 0.20, 1 }, { 0.18, 0.55, 1, 1 }, { 0.38, 0.72, 1, 1 }
    elseif roles and roles.healer then
        return { 0.035, 0.15, 0.075, 1 }, { 0.20, 0.82, 0.38, 1 }, { 0.42, 1, 0.58, 1 }
    end
    return UI_COLORS.panel, UI_COLORS.border, UI_COLORS.text
end

local function SetRegionShown(region, shown)
    if not region then return end
    if shown then region:Show() else region:Hide() end
end

local auraIconTexture
local auraIconLastScan = 0
local AURA_ITEM_ID = 818059
local AURA_ICON_FALLBACK = "Interface\\Icons\\Achievement_GuildPerk_FastTrack"

local function ResolveAuraIconTexture()
    if type(GetItemIcon) == "function" then
        local itemIcon = GetItemIcon(AURA_ITEM_ID)
        if itemIcon then
            auraIconTexture = itemIcon
            return auraIconTexture
        end
    end
    if auraIconTexture then return auraIconTexture end
    local now = GetTime()
    if now - auraIconLastScan < 5 then return AURA_ICON_FALLBACK end
    auraIconLastScan = now

    local spellNames = { "Bonus XP", "Bonus Experience", "Experience Aura", "XP Aura" }
    local _, spellName
    for _, spellName in ipairs(spellNames) do
        local name, _, icon = GetSpellInfo(spellName)
        if name and icon then
            auraIconTexture = icon
            return auraIconTexture
        end
    end

    local units = { "player" }
    local _, member
    for _, member in ipairs(GetRoster()) do
        if member.unit then table.insert(units, member.unit) end
    end
    local _, unit
    for _, unit in ipairs(units) do
        local auraIndex
        for auraIndex = 1, 40 do
            local name, _, icon = UnitBuff(unit, auraIndex)
            if not name then break end
            local lowerName = name:lower()
            if (lowerName:find("bonus") and (lowerName:find("xp") or lowerName:find("experience")))
                or lowerName:find("experience aura")
            then
                auraIconTexture = icon
                return auraIconTexture
            end
        end
    end

    if type(EnumerateFrames) == "function" then
        local frame = EnumerateFrames()
        while frame do
            if type(frame.GetRegions) == "function" then
                local frameName = type(frame.GetName) == "function" and frame:GetName()
                local lowerFrameName = type(frameName) == "string" and frameName:lower() or ""
                local namedBonusXP = lowerFrameName:find("bonus")
                    and (lowerFrameName:find("xp") or lowerFrameName:find("experience"))
                local regions = { frame:GetRegions() }
                local _, region
                for _, region in ipairs(regions) do
                    if region and type(region.GetTexture) == "function" then
                        local texture = region:GetTexture()
                        local regionName = type(region.GetName) == "function" and region:GetName()
                        local lowerRegionName = type(regionName) == "string" and regionName:lower() or ""
                        local namedRegion = lowerRegionName:find("bonus")
                            and (lowerRegionName:find("xp") or lowerRegionName:find("experience"))
                        if texture and (namedBonusXP or namedRegion) then
                            auraIconTexture = texture
                            return auraIconTexture
                        end
                        if type(texture) == "string" then
                            local lowerTexture = texture:lower()
                            if lowerTexture:find("bonus")
                                and (lowerTexture:find("xp") or lowerTexture:find("experience"))
                            then
                                auraIconTexture = texture
                                return auraIconTexture
                            end
                        end
                    end
                end
            end
            frame = EnumerateFrames(frame)
        end
    end
    return AURA_ICON_FALLBACK
end

local function LayoutWhisperRoleIcons(row, roles)
    local iconCount = 0
    if roles.tank then iconCount = iconCount + 1 end
    if roles.healer then iconCount = iconCount + 1 end
    if roles.dps then iconCount = iconCount + 1 end
    local itemCount = iconCount + (roles.aura and 1 or 0)
    if itemCount == 0 then return end

    local iconWidth = 24
    local auraWidth = 24
    local gap = 3
    local totalWidth = (iconCount * iconWidth) + (roles.aura and auraWidth or 0)
        + (math.max(0, itemCount - 1) * gap)
    local cursor = 405 + ((105 - totalWidth) / 2)
    local _, role
    for _, role in ipairs({ "tank", "healer", "dps" }) do
        local roleIcon = row.roleIcons[role]
        roleIcon:ClearAllPoints()
        if roles[role] then
            roleIcon:SetPoint("LEFT", row, "LEFT", cursor, 0)
            cursor = cursor + iconWidth + gap
        end
    end
    row.aura:ClearAllPoints()
    if roles.aura then
        row.aura:SetPoint("LEFT", row, "LEFT", cursor, 0)
    end
end

local function CreateAuraSparkleBorder(row)
    local border = CreateFrame("Frame", nil, row)
    border:SetAllPoints(row)
    border:SetFrameLevel(row:GetFrameLevel() + 3)
    border:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(1, 0.72, 0.08, 0.95)
    border.sparkles = {}

    local sparklePoints = {
        { "TOPLEFT", 8, -1 }, { "TOPLEFT", 82, -1 },
        { "TOP", -150, -1 }, { "TOP", 0, -1 }, { "TOP", 150, -1 },
        { "TOPRIGHT", -82, -1 }, { "TOPRIGHT", -8, -1 },
        { "BOTTOMLEFT", 8, 1 }, { "BOTTOMLEFT", 82, 1 },
        { "BOTTOM", -150, 1 }, { "BOTTOM", 0, 1 }, { "BOTTOM", 150, 1 },
        { "BOTTOMRIGHT", -82, 1 }, { "BOTTOMRIGHT", -8, 1 },
        { "LEFT", 1, 0 }, { "RIGHT", -1, 0 },
    }
    local index, pointInfo
    for index, pointInfo in ipairs(sparklePoints) do
        local sparkle = border:CreateTexture(nil, "OVERLAY")
        local size = index % 3 == 0 and 6 or 4
        sparkle:SetTexture("Interface\\Buttons\\WHITE8X8")
        sparkle:SetBlendMode("ADD")
        sparkle:SetWidth(size)
        sparkle:SetHeight(size)
        sparkle:SetPoint(pointInfo[1], border, pointInfo[1], pointInfo[2], pointInfo[3])
        sparkle:SetVertexColor(1, 0.82, 0.20, 0.9)
        border.sparkles[index] = sparkle
    end

    border.elapsed = 0
    border:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.04 then return end
        self.elapsed = 0
        local now = GetTime()
        local sparkleIndex, sparkle
        for sparkleIndex, sparkle in ipairs(self.sparkles) do
            local wave = (math.sin((now * 4.2) + (sparkleIndex * 1.73)) + 1) * 0.5
            local alpha = 0.12 + (wave * wave * 0.88)
            sparkle:SetVertexColor(1, 0.72 + (wave * 0.20), 0.10, alpha)
        end
        local borderPulse = 0.72 + (((math.sin(now * 2.8) + 1) * 0.5) * 0.28)
        self:SetBackdropBorderColor(1, 0.65 + (borderPulse * 0.15), 0.08, borderPulse)
    end)
    border:Hide()
    return border
end

local function InviteWhisperPlayer(entry)
    if not entry or not entry.name then return end
    if IsBlocked60(entry.name) then
        LocalWarning(ShortName(entry.name) .. " is blocked because they reached level 60.")
        return
    end
    if IsGrouped(entry.name) then
        Print(ShortName(entry.name) .. " is already in the group.")
        RefreshWhisperPanel()
        return
    end
    if (InParty() or InRaid()) and not CanManageRaid() then
        LocalWarning("You need leader or assistant to invite " .. ShortName(entry.name) .. ".")
        return
    end
    if entry.roles then
        AddSignup(entry.name, entry.roles)
        Refresh()
        Print(ShortName(entry.name) .. " will join as " .. RoleText(entry.roles) .. ".")
    end
    InviteUnit(entry.name)
    Print("Invited " .. ShortName(entry.name) .. " from recruitment.")
end

local function VisibleRecruitmentRows(frame, rows)
    if not frame then return 9 end
    local visible = math.floor((frame:GetHeight() - 172) / 34) + 1
    return math.max(1, math.min(#rows, visible))
end

RefreshWhisperPanel = function()
    if not whisperPanel then return end
    local log = db and db.whispers or {}
    if whisperEmptyText then
        if #log == 0 then whisperEmptyText:Show() else whisperEmptyText:Hide() end
    end
    local visibleRows = VisibleRecruitmentRows(whisperPanel, whisperRows)
    local rowIndex
    for rowIndex = 1, #whisperRows do
        local row = whisperRows[rowIndex]
        local entry = rowIndex <= visibleRows and log[#log - whisperScrollOffset - rowIndex + 1] or nil
        row.data = entry
        if entry then
            local priority = IsPriorityWhisper(entry.roles)
            local backgroundColor, borderColor, nameColor = WhisperHighlight(entry.roles)
            row:SetBackdropColor(unpack(backgroundColor))
            row:SetBackdropBorderColor(unpack(borderColor))
            row.name:SetFont(FONT_BODY, 11, priority and "OUTLINE" or "")
            row.name:SetTextColor(unpack(nameColor))
            row.name:SetText(ShortName(entry.name))
            row.message:SetText(entry.message or "")
            local roles = entry.roles or {}
            SetRegionShown(row.roleIcons.tank, roles.tank and true or false)
            SetRegionShown(row.roleIcons.healer, roles.healer and true or false)
            SetRegionShown(row.roleIcons.dps, roles.dps and true or false)
            SetRegionShown(row.aura, roles.aura and true or false)
            SetRegionShown(row.auraSparkleBorder, roles.aura and true or false)
            if roles.aura then row.aura:SetTexture(ResolveAuraIconTexture()) end
            SetRegionShown(row.unassigned, not roles.tank and not roles.healer and not roles.dps and not roles.aura)
            LayoutWhisperRoleIcons(row, roles)
            local timeText = entry.at and date("%H:%M", entry.at) or ""
            row.time:SetText(timeText .. (entry.source and "  " .. entry.source or ""))
            if IsBlocked60(entry.name) then
                row.invite:SetText("BLOCKED 60")
                row.invite:Disable()
            elseif IsGrouped(entry.name) then
                row.invite:SetText("GROUPED")
                row.invite:Disable()
            else
                row.invite:SetText("INVITE")
                row.invite:Enable()
            end
            row:Show()
        else
            row.roleIcons.tank:Hide()
            row.roleIcons.healer:Hide()
            row.roleIcons.dps:Hide()
            row.aura:Hide()
            row.auraSparkleBorder:Hide()
            row.unassigned:Hide()
            row:Hide()
        end
    end
    if whisperScrollText then
        if #log == 0 then
            whisperScrollText:SetText("0 messages")
        else
            local newest = #log - whisperScrollOffset
            local oldest = math.max(1, newest - visibleRows + 1)
            whisperScrollText:SetText(oldest .. "-" .. newest .. " of " .. #log .. "  |  Mouse wheel to scroll")
        end
    end
end

local function ScrollWhispers(amount)
    local log = db and db.whispers or {}
    local maximum = math.max(0, #log - VisibleRecruitmentRows(whisperPanel, whisperRows))
    whisperScrollOffset = Clamp(whisperScrollOffset + amount, 0, maximum)
    RefreshWhisperPanel()
end

function Sync.ScannerRoleMarkup(roles)
    if not roles then return "UNASSIGNED" end
    local parts = {}
    if roles.tank then
        table.insert(parts, "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:24:24:0:0:256:256:5:63:69:127|t")
    end
    if roles.healer then
        table.insert(parts, "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:24:24:0:0:256:256:72:130:2:60|t")
    end
    if roles.dps then
        table.insert(parts, "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:24:24:0:0:256:256:72:130:69:127|t")
    end
    if roles.aura then
        table.insert(parts, "|T" .. tostring(ResolveAuraIconTexture()) .. ":24:24:0:0|t")
    end
    return #parts > 0 and table.concat(parts, " ") or "UNASSIGNED"
end

RefreshChatScannerPanel = function()
    if not chatScannerPanel then return end
    local log = db and db.chatScanner or {}
    if chatScannerEmptyText then
        if #log == 0 then chatScannerEmptyText:Show() else chatScannerEmptyText:Hide() end
    end
    local visibleRows = VisibleRecruitmentRows(chatScannerPanel, chatScannerRows)
    local rowIndex
    for rowIndex = 1, #chatScannerRows do
        local row = chatScannerRows[rowIndex]
        local entry = rowIndex <= visibleRows and log[#log - chatScannerScrollOffset - rowIndex + 1] or nil
        row.data = entry
        if entry then
            row:SetBackdropColor(0.025, 0.085, 0.14, 0.98)
            row:SetBackdropBorderColor(0.12, 0.60, 0.86, 1)
            row.name:SetTextColor(0.35, 0.82, 1, 1)
            row.name:SetText(ShortName(entry.name))
            row.message:SetText(entry.message or "")
            row.roles:SetText(Sync.ScannerRoleMarkup(entry.roles))
            local timeText = entry.at and date("%H:%M", entry.at) or ""
            row.time:SetText(timeText .. (entry.source and "  " .. entry.source or ""))
            if IsBlocked60(entry.name) then
                row.invite:SetText("BLOCKED 60")
                row.invite:Disable()
            elseif IsGrouped(entry.name) then
                row.invite:SetText("GROUPED")
                row.invite:Disable()
            else
                row.invite:SetText("INVITE")
                row.invite:Enable()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    if chatScannerScrollText then
        if #log == 0 then
            chatScannerScrollText:SetText("0 posts")
        else
            local newest = #log - chatScannerScrollOffset
            local oldest = math.max(1, newest - visibleRows + 1)
            chatScannerScrollText:SetText(oldest .. "-" .. newest .. " of " .. #log .. "  |  Mouse wheel to scroll")
        end
    end
end

function Sync.ScrollChatScanner(amount)
    local log = db and db.chatScanner or {}
    local maximum = math.max(0, #log - VisibleRecruitmentRows(chatScannerPanel, chatScannerRows))
    chatScannerScrollOffset = Clamp(chatScannerScrollOffset + amount, 0, maximum)
    RefreshChatScannerPanel()
end

function Sync.PositionChatScanner()
    if not chatScannerPanel or not whisperPanel then return end
    chatScannerPanel:ClearAllPoints()
    local dock = db.chatScannerDock
    if dock == nil then dock = "right" end
    if dock == "left" then
        chatScannerPanel:SetPoint("TOPRIGHT", whisperPanel, "TOPLEFT", -8, 0)
    elseif dock == "top" then
        chatScannerPanel:SetPoint("BOTTOMLEFT", whisperPanel, "TOPLEFT", 0, 8)
    elseif dock == "bottom" then
        chatScannerPanel:SetPoint("TOPLEFT", whisperPanel, "BOTTOMLEFT", 0, -8)
    elseif dock == "free" and db.chatScannerPosition then
        local saved = db.chatScannerPosition
        chatScannerPanel:SetPoint(
            saved.point or "CENTER",
            UIParent,
            saved.relativePoint or "CENTER",
            saved.x or 0,
            saved.y or 0
        )
    else
        db.chatScannerDock = "right"
        chatScannerPanel:SetPoint("TOPLEFT", whisperPanel, "TOPRIGHT", 8, 0)
    end
end

function Sync.FinishChatScannerMove(self)
    self:StopMovingOrSizing()
    local snapDistance = 45
    local scannerLeft, scannerRight = self:GetLeft(), self:GetRight()
    local scannerTop, scannerBottom = self:GetTop(), self:GetBottom()
    local whisperLeft, whisperRight = whisperPanel:GetLeft(), whisperPanel:GetRight()
    local whisperTop, whisperBottom = whisperPanel:GetTop(), whisperPanel:GetBottom()
    local dock
    local overlapping = scannerLeft and scannerRight and scannerTop and scannerBottom
        and whisperLeft and whisperRight and whisperTop and whisperBottom
        and scannerLeft < whisperRight
        and scannerRight > whisperLeft
        and scannerBottom < whisperTop
        and scannerTop > whisperBottom

    if overlapping then
        local scannerCenter = (scannerLeft + scannerRight) / 2
        local whisperCenter = (whisperLeft + whisperRight) / 2
        dock = scannerCenter >= whisperCenter and "right" or "left"
    elseif scannerLeft and whisperRight
        and math.abs(scannerLeft - whisperRight) <= snapDistance
        and scannerBottom <= whisperTop + snapDistance
        and scannerTop >= whisperBottom - snapDistance
    then
        dock = "right"
    elseif scannerRight and whisperLeft
        and math.abs(scannerRight - whisperLeft) <= snapDistance
        and scannerBottom <= whisperTop + snapDistance
        and scannerTop >= whisperBottom - snapDistance
    then
        dock = "left"
    elseif scannerBottom and whisperTop
        and math.abs(scannerBottom - whisperTop) <= snapDistance
        and scannerRight >= whisperLeft - snapDistance
        and scannerLeft <= whisperRight + snapDistance
    then
        dock = "top"
    elseif scannerTop and whisperBottom
        and math.abs(scannerTop - whisperBottom) <= snapDistance
        and scannerRight >= whisperLeft - snapDistance
        and scannerLeft <= whisperRight + snapDistance
    then
        dock = "bottom"
    end

    if dock then
        db.chatScannerDock = dock
        db.chatScannerPosition = nil
        Sync.PositionChatScanner()
    else
        local point, _, relativePoint, x, y = self:GetPoint(1)
        db.chatScannerDock = "free"
        db.chatScannerPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end
end

function Sync.CreateChatScannerPanel(parent)
    chatScannerPanel = CreateFrame("Frame", nil, parent)
    chatScannerPanel:SetWidth(560)
    chatScannerPanel:SetHeight(parent:GetHeight())
    Sync.PositionChatScanner()
    chatScannerPanel:SetMovable(true)
    chatScannerPanel:SetClampedToScreen(true)
    chatScannerPanel:RegisterForDrag("LeftButton")
    chatScannerPanel:EnableMouse(true)
    chatScannerPanel:EnableMouseWheel(true)
    chatScannerPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    chatScannerPanel:SetBackdropColor(0.015, 0.045, 0.085, 0.98)
    chatScannerPanel:SetBackdropBorderColor(0.10, 0.55, 0.82, 1)
    chatScannerPanel:SetScript("OnDragStart", chatScannerPanel.StartMoving)
    chatScannerPanel:SetScript("OnDragStop", Sync.FinishChatScannerMove)
    chatScannerPanel:SetScript("OnMouseWheel", function(_, delta)
        Sync.ScrollChatScanner(delta > 0 and -1 or 1)
    end)

    local header = chatScannerPanel:CreateTexture(nil, "BACKGROUND")
    header:SetTexture("Interface\\Buttons\\WHITE8X8")
    header:SetVertexColor(0.02, 0.09, 0.16, 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(64)

    local title = chatScannerPanel:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT_TITLE, 20, "")
    title:SetTextColor(0.35, 0.82, 1, 1)
    title:SetPoint("TOPLEFT", 18, -10)
    title:SetText("CHAT SCANNER")

    local subtitle = chatScannerPanel:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont(FONT_BODY, 10, "")
    subtitle:SetTextColor(0.50, 0.72, 0.86, 1)
    subtitle:SetPoint("TOPLEFT", 19, -38)
    subtitle:SetText("LIVE: LFG + MS + role. Repeated posts from one player are filtered.")

    local headings = {
        { text = "PLAYER", x = 20 },
        { text = "PUBLIC POST", x = 125 },
        { text = "ROLE", x = 345, width = 98, centered = true },
        { text = "ACTION", x = 465 },
    }
    local _, heading
    for _, heading in ipairs(headings) do
        local label = chatScannerPanel:CreateFontString(nil, "OVERLAY")
        label:SetFont(FONT_BODY, 9, "")
        label:SetTextColor(0.35, 0.82, 1, 1)
        label:SetPoint("TOPLEFT", heading.x, -72)
        if heading.width then label:SetWidth(heading.width) end
        if heading.centered then label:SetJustifyH("CENTER") end
        label:SetText(heading.text)
    end

    local index
    for index = 1, 18 do
        local row = CreateFrame("Frame", nil, chatScannerPanel)
        row:SetWidth(520)
        row:SetHeight(32)
        row:SetPoint("TOPLEFT", 20, -88 - ((index - 1) * 34))
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.name = row:CreateFontString(nil, "OVERLAY")
        row.name:SetFont(FONT_BODY, 11, "OUTLINE")
        row.name:SetWidth(92)
        row.name:SetPoint("LEFT", 8, 5)
        row.name:SetJustifyH("LEFT")
        row.time = row:CreateFontString(nil, "OVERLAY")
        row.time:SetFont(FONT_BODY, 8, "")
        row.time:SetTextColor(0.42, 0.66, 0.80, 1)
        row.time:SetPoint("BOTTOMLEFT", 8, 3)
        row.message = row:CreateFontString(nil, "OVERLAY")
        row.message:SetFont(FONT_BODY, 10, "")
        row.message:SetTextColor(unpack(UI_COLORS.text))
        row.message:SetWidth(220)
        row.message:SetHeight(14)
        row.message:SetPoint("LEFT", 105, 0)
        row.message:SetJustifyH("LEFT")
        row.roles = row:CreateFontString(nil, "OVERLAY")
        row.roles:SetFont(FONT_BODY, 9, "")
        row.roles:SetWidth(98)
        row.roles:SetPoint("LEFT", 325, 0)
        row.roles:SetJustifyH("CENTER")
        row.invite = CreateFrame("Button", nil, row)
        row.invite:SetWidth(82)
        row.invite:SetHeight(24)
        row.invite:SetPoint("RIGHT", -7, 0)
        StyleButton(row.invite, "green", "Invite This Player", "Saves this player's detected roles, then invites only the player shown on this public recruitment post.")
        row.invite:SetText("INVITE")
        local rowRef = row
        row.invite:SetScript("OnClick", function() InviteWhisperPlayer(rowRef.data) end)
        row:Hide()
        chatScannerRows[index] = row
    end

    chatScannerEmptyText = chatScannerPanel:CreateFontString(nil, "OVERLAY")
    chatScannerEmptyText:SetFont(FONT_BODY, 12, "")
    chatScannerEmptyText:SetTextColor(0.42, 0.66, 0.80, 1)
    chatScannerEmptyText:SetPoint("CENTER", 0, -10)
    chatScannerEmptyText:SetText("Watching all chat channels for LFG MS role posts...")

    local older = CreateFrame("Button", nil, chatScannerPanel)
    older:SetWidth(72)
    older:SetHeight(28)
    older:SetPoint("BOTTOMLEFT", 20, 14)
    StyleButton(older, "slate", "Older Scanner Posts", "Moves back through saved public recruitment posts.")
    older:SetText("OLDER")
    older:SetScript("OnClick", function() Sync.ScrollChatScanner(5) end)

    local newer = CreateFrame("Button", nil, chatScannerPanel)
    newer:SetWidth(72)
    newer:SetHeight(28)
    newer:SetPoint("LEFT", older, "RIGHT", 5, 0)
    StyleButton(newer, "slate", "Newer Scanner Posts", "Moves forward toward the latest public recruitment posts.")
    newer:SetText("NEWER")
    newer:SetScript("OnClick", function() Sync.ScrollChatScanner(-5) end)

    chatScannerScrollText = chatScannerPanel:CreateFontString(nil, "OVERLAY")
    chatScannerScrollText:SetFont(FONT_BODY, 9, "")
    chatScannerScrollText:SetTextColor(0.42, 0.66, 0.80, 1)
    chatScannerScrollText:SetPoint("BOTTOM", 0, 23)

    local clear = CreateFrame("Button", nil, chatScannerPanel)
    clear:SetWidth(110)
    clear:SetHeight(28)
    clear:SetPoint("BOTTOMRIGHT", -20, 14)
    StyleButton(clear, "red", "Clear Scanner", "Removes the saved public recruitment-post history.")
    clear:SetText("CLEAR SCAN")
    clear:SetScript("OnClick", function()
        db.chatScanner = {}
        chatScannerScrollOffset = 0
        RefreshChatScannerPanel()
    end)
end

function Sync.CreateWhisperPanel()
    if whisperPanel then return end
    whisperPanel = CreateFrame("Frame", "ManastormerWhisperPanel", UIParent)
    whisperPanel:SetWidth(640)
    db.whisperHeight = math.max(462, math.min(768, tonumber(db.whisperHeight) or 462))
    whisperPanel:SetHeight(db.whisperHeight)
    if db.whisperPosition then
        whisperPanel:SetPoint(
            db.whisperPosition.point or "CENTER",
            UIParent,
            db.whisperPosition.relativePoint or "CENTER",
            db.whisperPosition.x or 240,
            db.whisperPosition.y or 0
        )
    else
        whisperPanel:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
    end
    db.whisperScale = 1
    whisperPanel:SetScale(1)
    whisperPanel:SetFrameStrata("HIGH")
    whisperPanel:SetMovable(true)
    whisperPanel:EnableMouse(true)
    whisperPanel:EnableMouseWheel(true)
    whisperPanel:RegisterForDrag("LeftButton")
    whisperPanel:SetClampedToScreen(true)
    whisperPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    whisperPanel:SetBackdropColor(unpack(UI_COLORS.bg))
    whisperPanel:SetBackdropBorderColor(unpack(UI_COLORS.goldDark))
    whisperPanel:SetScript("OnDragStart", whisperPanel.StartMoving)
    whisperPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        db.whisperPosition = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end)
    whisperPanel:SetScript("OnMouseWheel", function(_, delta)
        ScrollWhispers(delta > 0 and -1 or 1)
    end)

    local header = whisperPanel:CreateTexture(nil, "BACKGROUND")
    header:SetTexture("Interface\\Buttons\\WHITE8X8")
    header:SetVertexColor(unpack(UI_COLORS.header))
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(64)

    local icon = whisperPanel:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON_PATH)
    icon:SetWidth(46)
    icon:SetHeight(46)
    icon:SetPoint("TOPLEFT", 10, -9)
    icon:SetTexCoord(0.035, 0.965, 0.035, 0.965)

    local title = whisperPanel:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT_TITLE, 20, "")
    title:SetTextColor(unpack(UI_COLORS.gold))
    title:SetPoint("TOPLEFT", 68, -10)
    title:SetText("RECRUITMENT WHISPERS")

    local subtitle = whisperPanel:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont(FONT_BODY, 10, "")
    subtitle:SetTextColor(unpack(UI_COLORS.muted))
    subtitle:SetPoint("TOPLEFT", 69, -38)
    subtitle:SetText("Tank, Healer and DPS use role icons. Aura uses Ascension's Bonus XP icon.")

    local close = CreateFrame("Button", nil, whisperPanel)
    close:SetWidth(30)
    close:SetHeight(28)
    close:SetPoint("TOPRIGHT", -10, -10)
    StyleButton(close, "slate", "Close Whispers", "Closes the live recruitment whisper panel.")
    close:SetText("X")
    close:SetScript("OnClick", function() whisperPanel:Hide() end)

    local headings = {
        { text = "PLAYER", x = 20 },
        { text = "MESSAGE", x = 135 },
        { text = "ROLE", x = 425, width = 105, centered = true },
        { text = "ACTION", x = 535 },
    }
    local _, heading
    for _, heading in ipairs(headings) do
        local label = whisperPanel:CreateFontString(nil, "OVERLAY")
        label:SetFont(FONT_BODY, 9, "")
        label:SetTextColor(unpack(UI_COLORS.gold))
        label:SetPoint("TOPLEFT", heading.x, -72)
        if heading.width then label:SetWidth(heading.width) end
        if heading.centered then label:SetJustifyH("CENTER") end
        label:SetText(heading.text)
    end

    local index
    for index = 1, 18 do
        local row = CreateFrame("Frame", nil, whisperPanel)
        row:SetWidth(600)
        row:SetHeight(32)
        row:SetPoint("TOPLEFT", 20, -88 - ((index - 1) * 34))
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.name = row:CreateFontString(nil, "OVERLAY")
        row.name:SetWidth(102)
        row.name:SetPoint("LEFT", 8, 5)
        row.name:SetJustifyH("LEFT")
        row.time = row:CreateFontString(nil, "OVERLAY")
        row.time:SetFont(FONT_BODY, 8, "")
        row.time:SetTextColor(unpack(UI_COLORS.muted))
        row.time:SetPoint("BOTTOMLEFT", 8, 3)
        row.message = row:CreateFontString(nil, "OVERLAY")
        row.message:SetFont(FONT_BODY, 10, "")
        row.message:SetTextColor(unpack(UI_COLORS.text))
        row.message:SetWidth(280)
        row.message:SetHeight(14)
        row.message:SetPoint("LEFT", 115, 0)
        row.message:SetJustifyH("LEFT")
        row.roleIcons = {}
        local roleIconInfo = {
            tank = { x = 405, coords = { 5 / 256, 63 / 256, 69 / 256, 127 / 256 } },
            healer = { x = 427, coords = { 72 / 256, 130 / 256, 2 / 256, 60 / 256 } },
            dps = { x = 449, coords = { 72 / 256, 130 / 256, 69 / 256, 127 / 256 } },
        }
        local roleName, iconInfo
        for roleName, iconInfo in pairs(roleIconInfo) do
            local roleIcon = row:CreateTexture(nil, "ARTWORK")
            roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
            roleIcon:SetWidth(24)
            roleIcon:SetHeight(24)
            roleIcon:SetPoint("LEFT", iconInfo.x, 0)
            roleIcon:SetTexCoord(unpack(iconInfo.coords))
            roleIcon:Hide()
            row.roleIcons[roleName] = roleIcon
        end
        row.aura = row:CreateTexture(nil, "OVERLAY")
        row.aura:SetTexture(ResolveAuraIconTexture())
        row.aura:SetWidth(24)
        row.aura:SetHeight(24)
        row.aura:SetPoint("LEFT", 470, 0)
        row.aura:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        row.aura:Hide()
        row.unassigned = row:CreateFontString(nil, "OVERLAY")
        row.unassigned:SetFont(FONT_BODY, 9, "")
        row.unassigned:SetTextColor(unpack(UI_COLORS.muted))
        row.unassigned:SetWidth(92)
        row.unassigned:SetPoint("LEFT", 410, 0)
        row.unassigned:SetJustifyH("CENTER")
        row.unassigned:SetText("UNASSIGNED")
        row.unassigned:Hide()
        row.invite = CreateFrame("Button", nil, row)
        row.invite:SetWidth(82)
        row.invite:SetHeight(24)
        row.invite:SetPoint("RIGHT", -7, 0)
        StyleButton(row.invite, "green", "Invite This Player", "Invites only the player shown on this row.")
        row.invite:SetText("INVITE")
        local rowRef = row
        row.invite:SetScript("OnClick", function() InviteWhisperPlayer(rowRef.data) end)
        row.auraSparkleBorder = CreateAuraSparkleBorder(row)
        row:Hide()
        whisperRows[index] = row
    end

    whisperEmptyText = whisperPanel:CreateFontString(nil, "OVERLAY")
    whisperEmptyText:SetFont(FONT_BODY, 12, "")
    whisperEmptyText:SetTextColor(unpack(UI_COLORS.muted))
    whisperEmptyText:SetPoint("CENTER", 0, -10)
    whisperEmptyText:SetText("No recruitment whispers received yet.")

    local older = CreateFrame("Button", nil, whisperPanel)
    older:SetWidth(72)
    older:SetHeight(28)
    older:SetPoint("BOTTOMLEFT", 20, 14)
    StyleButton(older, "slate", "Older Whispers", "Moves back through saved recruitment whispers.")
    older:SetText("OLDER")
    older:SetScript("OnClick", function() ScrollWhispers(5) end)

    local newer = CreateFrame("Button", nil, whisperPanel)
    newer:SetWidth(72)
    newer:SetHeight(28)
    newer:SetPoint("LEFT", older, "RIGHT", 5, 0)
    StyleButton(newer, "slate", "Newer Whispers", "Moves forward toward the latest recruitment whispers.")
    newer:SetText("NEWER")
    newer:SetScript("OnClick", function() ScrollWhispers(-5) end)

    whisperScrollText = whisperPanel:CreateFontString(nil, "OVERLAY")
    whisperScrollText:SetFont(FONT_BODY, 9, "")
    whisperScrollText:SetTextColor(unpack(UI_COLORS.muted))
    whisperScrollText:SetPoint("BOTTOM", 0, 23)

    local clear = CreateFrame("Button", nil, whisperPanel)
    clear:SetWidth(120)
    clear:SetHeight(28)
    clear:SetPoint("BOTTOMRIGHT", -20, 14)
    StyleButton(clear, "red", "Clear Whisper List", "Removes the saved recruitment whisper history.")
    clear:SetText("CLEAR WHISPERS")
    clear:SetScript("OnClick", function()
        db.whispers = {}
        whisperScrollOffset = 0
        RefreshWhisperPanel()
    end)

    local resizeGrip = CreateFrame("Button", nil, whisperPanel)
    resizeGrip:SetWidth(20)
    resizeGrip:SetHeight(20)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    resizeGrip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Resize Recruitment Windows", unpack(UI_COLORS.gold))
        GameTooltip:AddLine("Drag downward to reveal more chat rows. Right-click to reset the height.", UI_COLORS.text[1], UI_COLORS.text[2], UI_COLORS.text[3], true)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local panelLeft, panelTop = whisperPanel:GetLeft(), whisperPanel:GetTop()
        if panelLeft and panelTop then
            whisperPanel:ClearAllPoints()
            whisperPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", panelLeft, panelTop)
            db.whisperPosition = {
                point = "TOPLEFT",
                relativePoint = "BOTTOMLEFT",
                x = panelLeft,
                y = panelTop,
            }
        end
        if db.chatScannerDock == "free" and chatScannerPanel then
            local scannerLeft, scannerTop = chatScannerPanel:GetLeft(), chatScannerPanel:GetTop()
            if scannerLeft and scannerTop then
                chatScannerPanel:ClearAllPoints()
                chatScannerPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", scannerLeft, scannerTop)
                db.chatScannerPosition = {
                    point = "TOPLEFT",
                    relativePoint = "BOTTOMLEFT",
                    x = scannerLeft,
                    y = scannerTop,
                }
            end
        end
        local _, cursorY = GetCursorPosition()
        self.startCursorY = cursorY
        self.startHeight = whisperPanel:GetHeight()
        self.resizing = true
    end)
    resizeGrip:SetScript("OnUpdate", function(self)
        if not self.resizing then return end
        local _, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        local delta = (self.startCursorY - cursorY) / uiScale
        local newHeight = math.max(462, math.min(768, self.startHeight + delta))
        whisperPanel:SetHeight(newHeight)
        chatScannerPanel:SetHeight(newHeight)
        db.whisperHeight = newHeight
        RefreshWhisperPanel()
        RefreshChatScannerPanel()
    end)
    resizeGrip:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            whisperPanel:SetHeight(462)
            chatScannerPanel:SetHeight(462)
            db.whisperHeight = 462
            RefreshWhisperPanel()
            RefreshChatScannerPanel()
        end
        self.resizing = false
    end)

    Sync.CreateChatScannerPanel(whisperPanel)
    whisperPanel:Hide()
end

function Sync.ToggleWhisperPanel()
    if not whisperPanel then Sync.CreateWhisperPanel() end
    if whisperPanel:IsShown() then
        whisperPanel:Hide()
    else
        RefreshWhisperPanel()
        RefreshChatScannerPanel()
        whisperPanel:Show()
        Schedule(0.05, function()
            if whisperPanel and whisperPanel:IsShown() and chatScannerPanel then
                Sync.FinishChatScannerMove(chatScannerPanel)
            end
        end)
    end
end

function Sync.CaptureWhisper(author, message, roles, source)
    if not db or not author or not message then return end
    if IsSelf(author) then return end
    local lowerMessage = Trim(message):lower()
    local word
    for word in lowerMessage:gmatch("%a+") do
        if word == "lfm" then return end
    end
    local askingForRoom = lowerMessage:find("got%s+room")
        or lowerMessage:find("got%s+any%s+room")
    if not roles and not askingForRoom then
        return
    end
    db.whispers = db.whispers or {}
    table.insert(db.whispers, {
        name = author,
        message = message,
        roles = roles,
        source = source or "Whisper",
        at = time(),
    })
    while #db.whispers > 50 do table.remove(db.whispers, 1) end
    whisperScrollOffset = 0
    RefreshWhisperPanel()
    return true
end

function Sync.NormalizeRecruitmentMessage(message)
    local normalized = Trim(message):lower()
    normalized = normalized:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    normalized = normalized:gsub("|h", ""):gsub("|H", "")
    normalized = normalized:gsub("[%p%s]+", " ")
    return Trim(normalized)
end

function Sync.IsDuplicateChatScan(author, message)
    local log = db and db.chatScanner or {}
    local authorKey = NameKey(author)
    local normalized = Sync.NormalizeRecruitmentMessage(message)
    local now = time()
    local index
    for index = #log, 1, -1 do
        local entry = log[index]
        if entry.at and now - entry.at > 60 then break end
        if NameKey(entry.name) == authorKey
            and Sync.NormalizeRecruitmentMessage(entry.message) == normalized
        then
            return true
        end
    end
    return false
end

function Sync.CaptureChatScan(author, message, roles, source)
    if not db or not author or not message or not roles then return end
    if IsSelf(author) then return end
    if Sync.IsDuplicateChatScan(author, message) then return end
    db.chatScanner = db.chatScanner or {}
    table.insert(db.chatScanner, {
        name = author,
        message = message,
        roles = roles,
        source = source or "Channel",
        at = time(),
    })
    while #db.chatScanner > 50 do table.remove(db.chatScanner, 1) end
    chatScannerScrollOffset = 0
    RefreshChatScannerPanel()
end

function Sync.MakeRoleBox(parent, role, x)
    local box = CreateFrame("Frame", nil, parent)
    box:SetWidth(124)
    box:SetHeight(68)
    box:SetPoint("TOPLEFT", x, -74)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    local label = box:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT_BODY, 11, "")
    label:SetPoint("TOP", 0, -8)
    label:SetText(ROLE_LABEL[role])
    label:SetTextColor(unpack(UI_COLORS.gold))

    box.count = box:CreateFontString(nil, "OVERLAY")
    box.count:SetFont(FONT_TITLE, 17, "")
    box.count:SetPoint("CENTER", 0, 2)

    box.names = box:CreateFontString(nil, "OVERLAY")
    box.names:SetFont(FONT_BODY, 9, "")
    box.names:SetTextColor(unpack(UI_COLORS.muted))
    box.names:SetPoint("BOTTOMLEFT", 5, 6)
    box.names:SetPoint("BOTTOMRIGHT", -5, 6)
    box.names:SetJustifyH("CENTER")
    if role == "aura" then
        box.warning = box:CreateTexture(nil, "OVERLAY")
        box.warning:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        box.warning:SetWidth(20)
        box.warning:SetHeight(20)
        box.warning:SetPoint("TOPRIGHT", -4, -4)
        box.warning:Hide()
    end
    local descriptions = {
        tank = "Signed Tanks currently in the raid. Turns green when the Settings target is met. Tank/Aura combinations count in both boxes.",
        healer = "Signed Healers currently in the raid. Turns green when the Settings target is met. Healer/Aura combinations count in both boxes.",
        aura = "Signed Aura players currently in the raid. The yellow caution sign means an occupied raid group has no Aura player. Hover to see Aura players and their groups.",
    }
    AttachRoleTooltip(box, role, descriptions[role])
    roleBoxes[role] = box
    TrackFullUI(box)
end

SetMinimized = function(minimized)
    if not panel or not db then
        return
    end
    minimized = minimized and true or false
    if InCombatLockdown and InCombatLockdown() then
        pendingMinimizedState = minimized
        LocalWarning(
            "Manastormer will switch to "
                .. (minimized and "compact" or "full")
                .. " view when combat ends."
        )
        return false
    end
    pendingMinimizedState = nil
    panelIsMinimized = minimized
    db.minimized = minimized and true or false
    ApplyPageVisibility()
    if compactText then
        if db.minimized then
            compactText:Show()
        else
            compactText:Hide()
        end
    end
    if Sync.panelAccent then
        if db.minimized then
            Sync.panelAccent:Hide()
        else
            Sync.panelAccent:Show()
        end
    end
    panel:SetHeight(db.minimized and 116 or 456)
    if minimizeButton then
        minimizeButton:SetText(db.minimized and "+" or "-")
    end
    PositionKickButton()
    UpdateKickButton()
    UpdateKick59Button()
end

function Sync.SetPanelShown(shown)
    shown = shown and true or false
    if InCombatLockdown and InCombatLockdown() then
        pendingPanelShown = shown
        LocalWarning("Manastormer will " .. (shown and "open" or "close") .. " when combat ends.")
        return false
    end
    pendingPanelShown = nil
    if shown then
        panel:Show()
        UpdateActivityState(false)
        UpdateRosterDepartures()
        CheckLevels()
        Refresh()
        Schedule(0.5, function()
            BroadcastVersion(true)
            if IsRaidLeader() or (InParty() and UnitIsPartyLeader("player")) then
                Sync.SendRoleSyncSnapshot()
            else
                Sync.RequestRoleSync(true)
            end
        end)
    else
        raidReportQueue = nil
        readyCheckArmed = false
        manastormEntryArmed = false
        pendingLevel60Kicks = {}
        pendingLevel59Kicks = {}
        chaoticLinkStacks = {}
        chaoticLinkLastWarning = {}
        chaoticLinkLastAnnouncedStack = {}
        chaoticLinkBrokenAt = {}
        if whisperPanel then whisperPanel:Hide() end
        if enterManastormButton then enterManastormButton:SetText("ENTER MANASTORM 1") end
        UpdateKickButton()
        UpdateKick59Button()
        panel:Hide()
    end
    return true
end

function Sync.PositionMinimapButton()
    if not minimapButton or not db or not db.minimap then return end
    local radians = math.rad(db.minimap.angle or 225)
    local radius = 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(radians) * radius,
        math.sin(radians) * radius
    )
end

function Sync.UpdateMinimapDrag(button)
    local minimapX, minimapY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local dx, dy = cursorX - minimapX, cursorY - minimapY
    local angle
    if dx == 0 then
        angle = dy >= 0 and 90 or 270
    else
        angle = math.deg(math.atan(dy / dx))
        if dx < 0 then
            angle = angle + 180
        elseif dy < 0 then
            angle = angle + 360
        end
    end
    db.minimap.angle = angle
    Sync.PositionMinimapButton()
end

function Sync.SetMinimapButtonShown(shown)
    if not minimapButton then return end
    db.minimap.hide = not shown
    if shown then
        minimapButton:Show()
        Print("Minimap button shown.")
    else
        minimapButton:Hide()
        Print("Minimap button hidden. Type /msm minimap to restore it.")
    end
end

function Sync.CreateMinimapButton()
    if minimapButton then return end
    minimapButton = CreateFrame("Button", "ManastormerMinimapButton", Minimap)
    minimapButton:SetWidth(33)
    minimapButton:SetHeight(33)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    local background = minimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetWidth(22)
    background:SetHeight(22)
    background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(22)
    icon:SetHeight(22)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON_PATH)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local highlight = minimapButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetWidth(33)
    highlight:SetHeight(33)
    highlight:SetPoint("CENTER")

    minimapButton:SetScript("OnDragStart", function(self)
        self.wasDragged = true
        self:SetScript("OnUpdate", Sync.UpdateMinimapDrag)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    minimapButton:SetScript("OnClick", function(self, mouseButton)
        if self.wasDragged then
            self.wasDragged = nil
            return
        end
        if mouseButton == "LeftButton" then
            Sync.SetPanelShown(not panel:IsShown())
        else
            Sync.SetMinimapButtonShown(false)
        end
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Manastormer", unpack(UI_COLORS.gold))
        GameTooltip:AddLine("Left-click: Open or close", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Hide button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Sync.PositionMinimapButton()
    if db.minimap.hide then minimapButton:Hide() else minimapButton:Show() end
end

function Sync.CreatePanel()
    panel = CreateFrame("Frame", "ManastormerFrame", UIParent)
    panel:SetWidth(410)
    panel:SetHeight(456)
    panel:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 0)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    panel:SetBackdropColor(unpack(UI_COLORS.bg))
    panel:SetBackdropBorderColor(unpack(UI_COLORS.goldDark))
    panel:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then
            LocalWarning("Manastormer cannot be moved during combat.")
            return
        end
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        db.point = point
        db.relativePoint = relativePoint
        db.x = x
        db.y = y
        PositionKickButton()
    end)

    local header = panel:CreateTexture(nil, "BACKGROUND")
    header:SetTexture("Interface\\Buttons\\WHITE8X8")
    header:SetVertexColor(unpack(UI_COLORS.header))
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(64)

    local headerIcon = panel:CreateTexture(nil, "ARTWORK")
    headerIcon:SetTexture(ICON_PATH)
    headerIcon:SetWidth(46)
    headerIcon:SetHeight(46)
    headerIcon:SetPoint("TOPLEFT", 10, -9)
    headerIcon:SetTexCoord(0.035, 0.965, 0.035, 0.965)

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT_TITLE, 22, "")
    title:SetPoint("TOPLEFT", 67, -10)
    title:SetText("MANASTORMER")
    title:SetTextColor(unpack(UI_COLORS.gold))

    local subtitle = panel:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont(FONT_BODY, 10, "")
    subtitle:SetTextColor(unpack(UI_COLORS.muted))
    subtitle:SetPoint("TOPLEFT", 68, -38)
    subtitle:SetText("ASCENSION RAID CONTROL - LEVEL 1")
    TrackFullUI(subtitle)

    local accent = panel:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetVertexColor(unpack(UI_COLORS.goldDark))
    accent:SetHeight(1)
    accent:SetPoint("TOPLEFT", 1, -64)
    accent:SetPoint("TOPRIGHT", -1, -64)
    Sync.panelAccent = accent

    local close = CreateFrame("Button", nil, panel)
    close:SetWidth(30)
    close:SetHeight(28)
    close:SetPoint("TOPRIGHT", -9, -10)
    StyleButton(close, "slate", "Close Manastormer", "Hides the panel. Click the minimap button or type /msm to show it again.")
    close:SetText("X")
    close:SetScript("OnClick", function() Sync.SetPanelShown(false) end)

    minimizeButton = CreateFrame("Button", nil, panel)
    minimizeButton:SetWidth(30)
    minimizeButton:SetHeight(28)
    minimizeButton:SetPoint("RIGHT", close, "LEFT", -5, 0)
    StyleButton(
        minimizeButton,
        "slate",
        "Compact View",
        "Collapses Manastormer to raid size, missing roles, level 59/60 alerts and recent departures."
    )
    minimizeButton:SetText("-")
    minimizeButton:SetScript("OnClick", function()
        local currentState = pendingMinimizedState
        if currentState == nil then
            currentState = panelIsMinimized
        end
        SetMinimized(not currentState)
        Refresh()
    end)

    pageButton = CreateFrame("Button", nil, panel)
    pageButton:SetWidth(78)
    pageButton:SetHeight(28)
    pageButton:SetPoint("TOPRIGHT", -79, -10)
    StyleButton(pageButton, "slate", "Switch Page", "Switches between raid controls and flexible Manastorm requirements.")
    pageButton:SetText("SETTINGS")
    pageButton:SetScript("OnClick", function()
        local currentPage = Sync.pendingPage or activePage
        local requestedPage = currentPage == "raid" and "settings" or "raid"
        if InCombatLockdown and InCombatLockdown() then
            Sync.pendingPage = requestedPage
            LocalWarning("Manastormer will open the " .. requestedPage .. " page when combat ends.")
            return
        end
        activePage = requestedPage
        if activePage == "settings" then RefreshSettingsPage() end
        ApplyPageVisibility()
    end)

    compactText = panel:CreateFontString(nil, "OVERLAY")
    compactText:SetFont(FONT_BODY, 10, "")
    compactText:SetTextColor(unpack(UI_COLORS.text))
    compactText:SetPoint("TOPLEFT", 68, -40)
    compactText:SetPoint("TOPRIGHT", -12, -39)
    compactText:SetHeight(68)
    compactText:SetJustifyH("LEFT")
    compactText:SetJustifyV("TOP")
    compactText:Hide()

    Sync.MakeRoleBox(panel, "tank", 10)
    Sync.MakeRoleBox(panel, "healer", 143)
    Sync.MakeRoleBox(panel, "aura", 276)

    listenButton = MakeButton(panel, "Listen", 120, function()
        sessionActive = not sessionActive
        warningSeen = {}
        if sessionActive then
            Print("Listening for 1 Tank, 2 Healer, 3 Aura.")
            Sync.StartRoleSync()
            CheckLevels()
        else
            pendingLevel60Kicks = {}
            pendingLevel59Kicks = {}
            UpdateKickButton()
            UpdateKick59Button()
            Print("Signup listening paused.")
        end
        Refresh()
    end, "Listen for Roles", "Starts or pauses automatic role detection from chat. Manastormer automatically suspends for Dungeon Finder queues/groups and inside normal, heroic, mythic and raid instances, then resumes afterward. While listening, leader/assist also replies when a whispered role is already full.", "blue")
    listenButton:SetPoint("TOPLEFT", 10, -149)

    local askButton = MakeButton(panel, "ROLE CHECK /RW", 120, function()
        sessionActive = true
        warningSeen = {}
        Sync.StartRoleSync()
        local roleCheckMessage = "[Manastormer Addon] ROLE CHECK: Tanks type 1, Healers type 2, Auras type 3. Combos like 13 (Tank/Aura) or 23 (Healer/Aura) work."
        if InRaid() and CanManageRaid() then
            SendChatMessage(roleCheckMessage, "RAID_WARNING")
        elseif InParty() then
            SendChatMessage(roleCheckMessage, "PARTY")
        else
            Print("Join a group first, or use Listen and post the question yourself.")
        end
        CheckLevels()
        Refresh()
    end, "Manastormer Role Check", "Posts the numbered Tank 1, Healer 2 and Aura 3 role check, including the 13 and 23 combinations, then starts listening.", "blue")
    askButton:SetPoint("LEFT", listenButton, "RIGHT", 5, 0)

    local inviteButton = MakeButton(panel, "WHISPERS", 140, function()
        Sync.ToggleWhisperPanel()
    end, "Recruitment Whispers", "Opens the live whisper list. Each player has a separate Invite button; there is no bulk auto-invite.", "blue")
    inviteButton:SetPoint("LEFT", askButton, "RIGHT", 5, 0)

    recruitmentButton = MakeButton(panel, "POST LFM TO " .. RecruitmentChannelText(), 390, function()
        PostRecruitmentMessage()
    end, "Post Recruitment", "Posts the live Tank, Healer, DPS and Aura requirements to the single channel selected in Settings.", "blue")
    recruitmentButton:SetPoint("TOPLEFT", 10, -183)

    readyCheckButton = MakeButton(panel, "READY CHECK", 192, function()
        StartReadyCheckQueue()
    end, "Ready Check Only", "Starts and tracks a normal raid ready check. It does not enter or queue a Manastorm.", "green")
    readyCheckButton:SetPoint("TOPLEFT", 10, -217)

    enterManastormButton = CreateFrame(
        "Button",
        "ManastormerSecureEnterButton",
        panel,
        "SecureActionButtonTemplate"
    )
    enterManastormButton:SetWidth(192)
    enterManastormButton:SetHeight(28)
    StyleButton(
        enterManastormButton,
        "green",
        "Enter Manastorm Level 1",
        "Securely presses Ascension's native Enter Group Manastorm control. Open Ascension's Mana Storm panel and select Level 1 first. A user click is required by WoW's protected-action rules."
    )
    enterManastormButton:SetText("ENTER MANASTORM 1")
    enterManastormButton:SetAttribute("type", "click")
    enterManastormButton:SetScript("PreClick", function(self)
        self:SetAttribute("clickbutton", nil)
        if not InRaid() then
            LocalWarning("You must be in a raid to enter Group Manastorm.")
            return
        end
        if not CanManageRaid() then
            LocalWarning("You need raid leader or assistant to enter Group Manastorm.")
            return
        end
        local ready, nativeButton = QueueForManastorm()
        if ready and nativeButton then
            manastormEntryArmed = true
            self:SetAttribute("clickbutton", nativeButton)
            self:SetText("ENTERING...")
        else
            manastormEntryArmed = false
            self:SetText("ENTER MANASTORM 1")
        end
    end)
    enterManastormButton:SetScript("PostClick", function(self)
        if manastormEntryArmed then
            Schedule(2, function()
                if manastormEntryArmed then
                    manastormEntryArmed = false
                    self:SetText("ENTER MANASTORM 1")
                end
            end)
        end
    end)
    TrackFullUI(enterManastormButton)
    enterManastormButton:SetPoint("LEFT", readyCheckButton, "RIGHT", 6, 0)

    level59Text = panel:CreateFontString(nil, "OVERLAY")
    level59Text:SetFont(FONT_BODY, 10, "")
    level59Text:SetTextColor(unpack(UI_COLORS.text))
    level59Text:SetPoint("TOPLEFT", 12, -254)
    level59Text:SetPoint("TOPRIGHT", -12, -254)
    level59Text:SetHeight(28)
    level59Text:SetJustifyH("LEFT")
    level59Text:SetJustifyV("TOP")
    TrackFullUI(level59Text)
    local level59Hover = CreateFrame("Frame", nil, panel)
    level59Hover:SetPoint("TOPLEFT", 10, -250)
    level59Hover:SetPoint("TOPRIGHT", -10, -250)
    level59Hover:SetHeight(32)
    AttachTooltip(
        level59Hover,
        "Level 59 Watch",
        "Lists signed Tank, Healer or Aura players at level 59 so the raid can prepare before anyone reaches level 60."
    )
    TrackFullUI(level59Hover)

    Sync.resetButton = MakeButton(panel, "DISBAND + AUTO REINVITE", 274, function()
        Sync.BeginRaidReset()
    end, "Disband and Auto Reinvite", "Snapshots every eligible raid member, warns the raid, waits 5 seconds, then disbands. If you are in combat it waits until combat ends. Reinvites begin automatically only after you are outside the dungeon. Level 60 and blocked players are excluded.", "red")
    Sync.resetButton:SetPoint("TOPLEFT", 10, -319)

    local clearButton = MakeButton(panel, "Clear Roles", 110, function()
        Sync.ClearAllSignups()
        db.nextOrder = 0
        warningSeen = {}
        Print("Role signups cleared.")
        Refresh()
    end, "Clear All Roles", "Removes every saved Tank, Healer, DPS and Aura assignment.", "red")
    clearButton:SetPoint("TOPLEFT", 290, -319)

    local reportButton = MakeButton(panel, "REPORT LEVELS + ROLES /RW", 390, function()
        StartRaidLevelReport()
    end, "Report Raid Levels and Roles", "Posts one Raid Warning per player with their current level, selected main role and highlighted Aura status. Players without a selected main role are listed as DPS.", "blue")
    reportButton:SetPoint("TOPLEFT", 10, -353)

    statusText = panel:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(FONT_BODY, 10, "")
    statusText:SetTextColor(unpack(UI_COLORS.text))
    statusText:SetPoint("TOPLEFT", 12, -289)
    statusText:SetPoint("TOPRIGHT", -12, -289)
    statusText:SetHeight(26)
    statusText:SetJustifyH("CENTER")
    statusText:SetJustifyV("TOP")
    TrackFullUI(statusText)
    local statusHover = CreateFrame("Frame", nil, panel)
    statusHover:SetPoint("TOPLEFT", 10, -283)
    statusHover:SetPoint("TOPRIGHT", -10, -283)
    statusHover:SetHeight(30)
    AttachTooltip(
        statusHover,
        "Raid Composition",
        "Shows raid size, assigned DPS and missing roles using the targets selected on the Settings page. Aura is an overlapping requirement."
    )
    TrackFullUI(statusHover)

    local help = panel:CreateFontString(nil, "OVERLAY")
    help:SetFont(FONT_BODY, 9, "")
    help:SetTextColor(unpack(UI_COLORS.muted))
    help:SetPoint("BOTTOM", 0, 9)
    local addonVersion = type(GetAddOnMetadata) == "function"
        and GetAddOnMetadata(ADDON_NAME, "Version") or "?"
    help:SetText("MANASTORMER v" .. tostring(addonVersion) .. "  |  /msm")
    TrackFullUI(help)

    -- This secure action must not be a child of the main panel. Ascension would
    -- otherwise protect the panel itself and block compact view during combat.
    kick60Button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    kick60Button:SetWidth(390)
    kick60Button:SetHeight(28)
    StyleButton(
        kick60Button,
        "red",
        "Remove Level 60 Player",
        "Ascension can protect raid removal from automatic addon actions. Click this fallback immediately if the automatic kick did not complete."
    )
    kick60Button:SetText("KICK LEVEL 60")
    kick60Button:SetScript("PostClick", function(self)
        local removedName = self.targetName
        Schedule(0.1, function()
            Sync.SendFarewellWhisper(removedName, 60)
        end)
        Schedule(1, function()
            UpdateRosterDepartures()
            UpdateKickButton()
            Refresh()
        end)
    end)
    kick60Button:Hide()

    kick59Button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    kick59Button:SetWidth(390)
    kick59Button:SetHeight(28)
    StyleButton(
        kick59Button,
        "red",
        "Remove Level 59 Player",
        "Removes the displayed live level-59 player from the group. The button rechecks the current roster level before it appears."
    )
    kick59Button:SetText("KICK LEVEL 59")
    kick59Button:SetScript("PostClick", function(self)
        local removedName = self.targetName
        Schedule(0.1, function()
            Sync.SendFarewellWhisper(removedName, 59)
        end)
        Schedule(1, function()
            UpdateRosterDepartures()
            UpdateKickButton()
            UpdateKick59Button()
            Refresh()
        end)
    end)
    kick59Button:Hide()

    Sync.resetSecureButton = CreateFrame(
        "Button",
        "ManastormerSecureRaidResetButton",
        UIParent,
        "SecureActionButtonTemplate"
    )
    Sync.resetSecureButton:SetWidth(390)
    Sync.resetSecureButton:SetHeight(28)
    StyleButton(
        Sync.resetSecureButton,
        "red",
        "Securely Disband Saved Raid",
        "Ascension protects raid removal. After the five-second warning, click this control out of combat. If every saved name does not fit in one secure macro, Manastormer prepares the next batch for another click."
    )
    Sync.resetSecureButton:SetText("CLICK TO DISBAND SAVED RAID")
    Sync.resetSecureButton:SetAttribute("type", "macro")
    Sync.resetSecureButton:SetAttribute("macrotext", "")
    Sync.resetSecureButton:SetScript("PostClick", function(self)
        local reset = Sync.raidReset
        if not reset or reset.stage ~= "await_secure_click" then return end
        if not (InCombatLockdown and InCombatLockdown()) then self:Hide() end
        reset.stage = "secure_verify"
        reset.nextAt = GetTime() + 1
        Sync.UpdateResetButton("VERIFYING SECURE DISBAND...")
    end)
    Sync.resetSecureButton:Hide()

    CreateSettingsUI(panel)
    ApplyPageVisibility()

    UpdateRosterDepartures()
    SetMinimized(db.minimized == true)
    Refresh()
    Sync.CreateMinimapButton()
    -- Login and /reload always begin closed and paused. The minimap button and
    -- /msm remain available when the player wants to begin a Manastorm session.
    panel:Hide()
end

local CHAT_EVENTS = {
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_BATTLEGROUND = true,
    CHAT_MSG_BATTLEGROUND_LEADER = true,
}

addon:SetScript("OnUpdate", function()
    -- An explicitly started raid reset must keep progressing while the panel is
    -- closed, in combat, or waiting for the player to leave the dungeon.
    Sync.ProcessRaidReset()
    if IsManastormerAwake() and HasAutomationAuthority() then
        ProcessRaidLevelReport()
        Sync.MaybeNotifyMissingAuraGroups()
    else
        raidReportQueue = nil
        readyCheckArmed = false
        manastormEntryArmed = false
    end
    local now = GetTime()
    local index = #delayed
    while index >= 1 do
        if now >= delayed[index].at then
            local callback = delayed[index].callback
            table.remove(delayed, index)
            callback()
        end
        index = index - 1
    end
end)

addon:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON_NAME then
            return
        end
        if not ManastormerDB then
            ManastormerDB = ManaStormAscensionDB or {}
        end
        db = ManastormerDB
        db.signups = db.signups or {}
        db.blocked60 = db.blocked60 or {}
        db.nextOrder = db.nextOrder or #db.signups
        db.whispers = db.whispers or {}
        db.chatScanner = db.chatScanner or {}
        ApplyRequirements()
        if type(db.minimap) ~= "table" then db.minimap = { hide = false, angle = 225 } end
        if db.minimap.angle == nil then db.minimap.angle = 225 end
        local blockedName
        for blockedName in pairs(db.blocked60) do
            if IsSelf(blockedName) then
                db.blocked60[blockedName] = nil
            end
        end
        Sync.CreatePanel()
        Sync.InstallRoleMenus()
        if type(RegisterAddonMessagePrefix) == "function" then
            pcall(RegisterAddonMessagePrefix, VERSION_PREFIX)
        end
        Print(
            "Loaded for Project Ascension in " .. InterfaceCompatibilityMode()
                .. " mode. Protected raid frames are untouched. Type /msm to show the panel."
        )
    elseif event == "PLAYER_LOGIN" then
        Schedule(2, function()
            if IsManastormerAwake() then
                BroadcastVersion(true)
                Sync.RequestRoleSync(true)
            end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if IsManastormerAwake() and prefix == VERSION_PREFIX then
            if sender and not IsSelf(sender) and IsGrouped(sender) then
                Sync.addonUsers[NameKey(sender)] = { name = sender, seen = GetTime() }
            end
            ReceiveVersion(message, sender)
            Sync.ReceiveRoleSync(message, sender)
            Refresh()
        end
    elseif CHAT_EVENTS[event] then
        local message, author, _, channelName = ...
        local roles = event == "CHAT_MSG_WHISPER" and ParseWhisperRoles(message) or ParseRoles(message)
        local activityAllowed = sessionActive
            and IsManastormerAwake()
            and ManastormAutomationAllowed()
        if event == "CHAT_MSG_WHISPER" and author and activityAllowed then
            local captured = Sync.CaptureWhisper(author, message, roles, "Whisper")
            if captured then
                MaybeReplyRoleCapacity(author, roles)
            end
        elseif activityAllowed and whisperPanel and whisperPanel:IsShown() and author then
            local recruitmentRoles = ParseWhisperRoles(message)
            if IsLFGManastormPost(message, recruitmentRoles) then
                Sync.CaptureChatScan(author, message, recruitmentRoles, ChatSource(event, channelName))
            end
        end
        if sessionActive and HasAutomationAuthority() and ManastormAutomationAllowed()
            and roles and author
        then
            AddSignup(author, roles)
            Refresh()
        end
    elseif event == "RAID_ROSTER_UPDATE"
        or event == "PARTY_MEMBERS_CHANGED"
        or event == "UNIT_LEVEL"
        or event == "PLAYER_LEVEL_UP"
    then
        Schedule(0.3, function()
            UpdateRosterDepartures()
            if not HasAutomationAuthority() then
                raidReportQueue = nil
                readyCheckArmed = false
                manastormEntryArmed = false
                pendingLevel60Kicks = {}
                pendingLevel59Kicks = {}
                chaoticLinkStacks = {}
                chaoticLinkLastWarning = {}
                chaoticLinkLastAnnouncedStack = {}
                chaoticLinkBrokenAt = {}
                UpdateKickButton()
                UpdateKick59Button()
            end
            CheckLevels()
            Refresh()
            RefreshWhisperPanel()
            RefreshChatScannerPanel()
        end)
        Schedule(1, function()
            if IsManastormerAwake() then
                BroadcastVersion(false)
                Sync.RequestRoleSync(false)
            end
        end)
    elseif event == "LFG_UPDATE"
        or event == "LFG_QUEUE_STATUS_UPDATE"
        or event == "LFG_ROLE_CHECK_SHOW"
        or event == "LFG_ROLE_CHECK_HIDE"
        or event == "LFG_PROPOSAL_SHOW"
        or event == "LFG_PROPOSAL_SUCCEEDED"
        or event == "LFG_PROPOSAL_FAILED"
    then
        Schedule(0.2, function()
            if IsManastormerAwake() then
                UpdateActivityState(true)
                Refresh()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        activeManastormLevel = 0
        local inInstance = type(IsInInstance) == "function" and IsInInstance()
        if inInstance and not InstanceNameIsManastorm() then
            pendingLevel60Kicks = {}
            pendingLevel59Kicks = {}
            UpdateKickButton()
            UpdateKick59Button()
        end
        Schedule(1, function()
            UpdateRosterDepartures()
            if IsManastormerAwake() then
                UpdateActivityState(true)
                CheckLevels()
                Refresh()
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingPanelShown ~= nil then
            local requestedVisibility = pendingPanelShown
            pendingPanelShown = nil
            Sync.SetPanelShown(requestedVisibility)
        end
        if pendingMinimizedState ~= nil then
            local requestedState = pendingMinimizedState
            pendingMinimizedState = nil
            SetMinimized(requestedState)
        end
        if Sync.pendingPage then
            activePage = Sync.pendingPage
            Sync.pendingPage = nil
            if activePage == "settings" then RefreshSettingsPage() end
            ApplyPageVisibility()
        end
        local names = {}
        local name
        for name in pairs(pendingLevel60Kicks) do
            table.insert(names, name)
        end
        local _, pendingName
        for _, pendingName in ipairs(names) do
            AttemptLevel60Kick(pendingName)
        end
        UpdateKickButton()
        UpdateKick59Button()
    elseif event == "READY_CHECK_FINISHED" then
        if IsManastormerAwake() and HasAutomationAuthority() then
            FinishReadyCheckQueue()
        else
            readyCheckArmed = false
        end
    elseif event == "READY_CHECK_CONFIRM" then
        -- Ascension supplies a unit token such as "raid2" here. Its generated
        -- API documentation labels this as a number, which caused older builds
        -- to associate a ready response with the wrong player.
        local unitOrID, response = ...
        if IsManastormerAwake() and readyCheckArmed and unitOrID ~= nil then
            local unit = unitOrID
            if type(unitOrID) == "number" then
                unit = "raid" .. unitOrID
            end
            local name = type(unit) == "string" and UnitName(unit)
            if not name and type(unitOrID) == "number" then
                name = GetRaidRosterInfo(unitOrID)
            end
            if name then
                readyResponses[NameKey(name)] = response == true or response == 1
            end
            Schedule(0.15, TryFinishReadyCheckEarly)
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if IsManastormerAwake() then TrackChaoticLink(...) end
    elseif event == "ENTER_MANASTORM_RESULT" then
        local result = ...
        manastormEntryArmed = false
        if enterManastormButton then enterManastormButton:SetText("ENTER MANASTORM 1") end
        if IsManastormerAwake() then
            if result and result ~= "ENTER_MANASTORM_OK" then
                LocalWarning("Manastorm entry failed: " .. tostring(result))
            else
                Print("Manastorm entry confirmed: " .. tostring(result or "success"))
            end
        end
    elseif event == "ACTIVE_MANASTORM_UPDATED" then
        local previousLevel, newLevel = ...
        previousLevel = tonumber(previousLevel)
        newLevel = tonumber(newLevel)
        activeManastormLevel = newLevel or 0
        if IsManastormerAwake() and newLevel and newLevel > 0 and previousLevel ~= newLevel then
            manastormEntryArmed = false
            if enterManastormButton then enterManastormButton:SetText("ENTER MANASTORM 1") end
            WarnWipeForLevel60(newLevel)
        end
        if IsManastormerAwake() and previousLevel == 0 and newLevel and newLevel >= 1 then
            AssignTankMarkers()
        end
    end
end)

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("RAID_ROSTER_UPDATE")
addon:RegisterEvent("PARTY_MEMBERS_CHANGED")
addon:RegisterEvent("UNIT_LEVEL")
addon:RegisterEvent("PLAYER_LEVEL_UP")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon:RegisterEvent("LFG_UPDATE")
addon:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
addon:RegisterEvent("LFG_ROLE_CHECK_SHOW")
addon:RegisterEvent("LFG_ROLE_CHECK_HIDE")
addon:RegisterEvent("LFG_PROPOSAL_SHOW")
addon:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
addon:RegisterEvent("LFG_PROPOSAL_FAILED")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:RegisterEvent("READY_CHECK_FINISHED")
addon:RegisterEvent("READY_CHECK_CONFIRM")
addon:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
pcall(addon.RegisterEvent, addon, "CHAT_MSG_ADDON")
pcall(addon.RegisterEvent, addon, "ENTER_MANASTORM_RESULT")
pcall(addon.RegisterEvent, addon, "ACTIVE_MANASTORM_UPDATED")
local event
for event in pairs(CHAT_EVENTS) do
    addon:RegisterEvent(event)
end

SLASH_MANASTORMER1 = "/msm"
SLASH_MANASTORMER2 = "/manastorm"
SLASH_MANASTORMER3 = "/manastormer"
SlashCmdList["MANASTORMER"] = function(message)
    local command, rest = Trim(message):match("^(%S*)%s*(.-)$")
    command = command and command:lower() or ""

    if command == "add" then
        local name, code = rest:match("^(%S+)%s+([123]+)$")
        local roles = ParseRoles(code)
        if name and roles then
            AddSignup(name, roles)
            Refresh()
        else
            Print("Usage: /msm add PlayerName 13")
        end
    elseif command == "listen" then
        sessionActive = true
        warningSeen = {}
        Sync.StartRoleSync()
        CheckLevels()
        Refresh()
    elseif command == "pause" then
        sessionActive = false
        pendingLevel60Kicks = {}
        pendingLevel59Kicks = {}
        UpdateKickButton()
        UpdateKick59Button()
        Refresh()
    elseif command == "clear" then
        Sync.ClearAllSignups()
        db.nextOrder = 0
        warningSeen = {}
        Refresh()
    elseif command == "api" or command == "debugapi" then
        PrintManastormDiagnostics()
    elseif command == "minimap" then
        Sync.SetMinimapButtonShown(not minimapButton:IsShown())
    elseif command == "whispers" or command == "invite" then
        Sync.ToggleWhisperPanel()
    elseif command == "resetraid" or command == "disband" then
        Sync.BeginRaidReset()
    elseif command == "tank" or command == "healer" or command == "dps" or command == "aura" then
        local name = Trim(rest)
        if name == "" then
            name = UnitFullName("target")
        end
        if name then
            ToggleManualRole(name, command)
        else
            Print("Target a player or use /msm " .. command .. " PlayerName")
        end
    elseif command == "clearrole" then
        local name = Trim(rest)
        if name == "" then
            name = UnitFullName("target")
        end
        if name then
            RemoveSignup(name)
            Print(ShortName(name) .. " roles cleared.")
            Refresh()
        else
            Print("Target a player or use /msm clearrole PlayerName")
        end
    elseif command == "help" then
        Print("/msm - show or hide")
        Print("/msm add PlayerName 13 - manual Tank/Aura signup")
        Print("/msm listen, /msm pause, /msm clear")
        Print("/msm minimap - show or hide the minimap button")
        Print("/msm whispers - open or close the recruitment whisper list")
        Print("/msm resetraid - snapshot, disband and auto reinvite outside the dungeon")
        Print("/msm api - show Ascension Manastorm API/frame diagnostics")
        Print("/msm tank, healer, dps, aura - toggle role on your target")
        Print("/msm clearrole - clear your target's Mana Storm roles")
    else
        if panel:IsShown() then
            Sync.SetPanelShown(false)
        else
            Sync.SetPanelShown(true)
        end
    end
end
