local addonVer = "1.2.0.0" --don't use letters or numbers > 10
local debugLevel = TWA.DEBUG.VERBOSE;

TWA = TWA or {}

TWA.version = addonVer;
TWA.me = UnitName('player')

local TWATargetsDropDown = CreateFrame('Frame', 'TWATargetsDropDown', UIParent, 'UIDropDownMenuTemplate')
local TWATanksDropDown = CreateFrame('Frame', 'TWATanksDropDown', UIParent, 'UIDropDownMenuTemplate')
local TWAHealersDropDown = CreateFrame('Frame', 'TWAHealersDropDown', UIParent, 'UIDropDownMenuTemplate')

local TWATemplates = CreateFrame('Frame', 'TWATemplates', UIParent, 'UIDropDownMenuTemplate')

function twaprint(a)
    if a == nil then
        DEFAULT_CHAT_FRAME:AddMessage('|cff69ccf0[TWA]|cff0070de:' ..
            time() .. '|cffffffff attempt to print a nil value.')
        return false
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[TWA] |cffffffff" .. a)
end

function twaerror(a)
    DEFAULT_CHAT_FRAME:AddMessage('|cff69ccf0[TWA]|cff0070de:' .. time() .. '|cffffffff[' .. a .. ']')
end

function twadebug(a)
    if (TWA.me == 'Kzktst' or TWA.me == 'Xerrtwo' or TWA.me == 'Tantomon' or TWA.me == 'Gergrutaa') and debugLevel > TWA.DEBUG.DISABLED then
        twaprint('|cff0070de[TWADEBUG:' .. time() .. ']|cffffffff[' .. a .. ']')
    end
end

TWA:RegisterEvent("ADDON_LOADED")
TWA:RegisterEvent("PLAYER_LOGIN")
TWA:RegisterEvent("RAID_ROSTER_UPDATE")
TWA:RegisterEvent("CHAT_MSG_ADDON")
TWA:RegisterEvent("CHAT_MSG_WHISPER")
TWA:RegisterEvent("PARTY_MEMBERS_CHANGED")

---@return boolean
function TWA_CanMakeChanges()
    if not TWA.InParty() then
        twaprint('You must be in a group to do that.')
        return false
    end
    if TWA.InParty() and not TWA.InRaid() then
        if not IsPartyLeader() then
            twaprint('You must be the party leader to do that.')
            return false
        end
    end
    if TWA.InRaid() and not ((IsRaidLeader()) or (IsRaidOfficer())) then
        twaprint("You need to be a raid leader or assistant to do that.")
        return false
    end
    return true
end

function TWA.loadTemplate(template, load)
    if load ~= nil and load == true then
        TWA.data = {}
        for i, d in next, TWA.twa_templates[template] do
            TWA.data[i] = d
        end
        TWA.PopulateTWA()
        twaprint('Loaded template |cff69ccf0' .. template)
        --getglobal('TWA_MainTemplates'):SetText(template)
        TWA.loadedTemplate = template
        getglobal('selectTemplate'):SetText(template)
        return true
    end
    TWA.sync.SendAddonMessage(TWA.MESSAGE.LoadTemplate .. "=" .. template)
end

---@return TWARoster
function TWA.GetCompleteRoster()
    ---@type TWARoster
    local completeRoster = {
        ['druid'] = {},
        ['hunter'] = {},
        ['mage'] = {},
        ['paladin'] = {},
        ['priest'] = {},
        ['rogue'] = {},
        ['shaman'] = {},
        ['warlock'] = {},
        ['warrior'] = {},
    }

    -- Helper function to add names to the completeRoster without duplicates per class
    local function addNamesToRoster(class, names)
        local seenNames = {} -- Track names already added to the class
        -- Add existing names in completeRoster to seenNames
        for _, name in ipairs(completeRoster[class]) do
            seenNames[name] = true
        end
        -- Add new names if they are not already in seenNames
        for _, name in ipairs(names) do
            if not seenNames[name] then
                table.insert(completeRoster[class], name)
                seenNames[name] = true
            end
        end
    end

    -- Merge TWA.roster into completeRoster
    for class, names in pairs(TWA.roster) do
        addNamesToRoster(class, names)
    end

    -- Merge TWA.foreignRosters into completeRoster
    for _, otherRoster in pairs(TWA.foreignRosters) do
        for class, names in pairs(otherRoster) do
            addNamesToRoster(class, names)
        end
    end

    return completeRoster
end

---Is the player in a party?
---@return boolean
function TWA.InParty()
    return (GetNumPartyMembers() > 0) or TWA.InRaid()
end

---Is the player in a raid group?
---@return boolean
function TWA.InRaid()
    return GetNumRaidMembers() > 0
end

---Serialize a roster
---To test: set up roster and /script twadebug(TWA.SerializeRoster(TWA.roster))
---@param roster TWARoster The roster to serialize
---@return string serializedRoster The serialized roster
function TWA.SerializeRoster(roster)
    local classesWithNames = {}
    for i, class in ipairs(TWA.SORTED_CLASS_NAMES) do
        if roster[class] ~= nil and table.getn(roster[class]) > 0 then
            table.insert(classesWithNames, class)
        end
    end

    local classesWithNamesLen = table.getn(classesWithNames)
    local result = '{' .. (classesWithNamesLen > 0 and '\n' or '')

    for i, class in ipairs(classesWithNames) do
        result = result .. '  [' .. '\"' .. class .. '\"' .. '] = {'
        for j, name in ipairs(roster[class]) do
            result = result .. ' \"' .. name .. '\"' .. (j < table.getn(roster[class]) and ', ' or ' ')
        end
        result = result .. '}' .. (i < classesWithNamesLen and ',' or '') .. '\n'
    end
    return result .. '}'
end

---Serializes the current content of TWA.data
---@return string dataStr The contents of TWA.data serialized to a string
function TWA.SerializeCurrentData()
    local twaDataLen = table.getn(TWA.data)
    local result = '{' .. (twaDataLen > 0 and '\n' or '')
    for i = 1, twaDataLen do
        result = result .. '  [' .. i .. '] = {'
        for j = 1, 7 do
            result = result .. ' \"' .. TWA.data[i][j] .. '\"' .. (j < 7 and ', ' or ' ')
        end
        result = result .. '}' .. (i < twaDataLen and ',' or '') .. '\n'
    end
    return result .. '}'
end

---Remove foreign roster entries from people who are neither an assistant nor leader of the raid
function TWA.CleanUpForeignRoster()
    local assistantCache = {} ---@type table<string, boolean>

    -- Cache names of current assistants in the raid
    for i = 1, GetNumRaidMembers() do
        if GetRaidRosterInfo(i) then
            local name, rank, _, _, _, _, z = GetRaidRosterInfo(i);
            if rank == 1 or rank == 2 then
                assistantCache[name] = true
            end
        end
    end

    -- Mark rosters for deletion if they don't match current assistants
    local rostersToDelete = {} ---@type table<string, boolean>
    for name, roster in pairs(TWA.foreignRosters) do
        if not assistantCache[name] then
            rostersToDelete[name] = true
        end
    end

    -- Delete outdated rosters
    for name, _ in pairs(rostersToDelete) do
        TWA.foreignRosters[name] = nil
    end
end

TWA.InitializeGroupState = function()
    if TWA._playerGroupStateInitialized then return end
    TWA._playerGroupStateInitialized = true;
    TWA.CleanUpForeignRoster()
    TWA.PlayerGroupStateUpdate()
end

---Updates the player's group state, and runs appropriate side effects on changes (for example, request sync if logging in while in raid)
function TWA.PlayerGroupStateUpdate()
    if not TWA._playerGroupStateInitialized then
        twadebug('player group state not initialized, ignored update')
        return
    end

    ---@param newState TWAGroupState
    local function setGroupState(newState)
        local oldState = TWA._playerGroupState or 'NIL';
        if oldState ~= newState then
            twadebug('state changed from ' .. oldState .. ' to ' .. newState)
        end

        TWA._playerGroupState = newState
    end

    if TWA._playerGroupState == nil then
        twadebug('i just logged in')
        -- reloaded ui or logged in
        setGroupState('alone')

        if TWA.InParty() then
            -- logged in while in party
            setGroupState('party')
            if TWA.InRaid() then
                -- logged in while in raid
                setGroupState('raid')
            end
            TWA.sync.RequestFullSync()
            TWA.sync.RequestAssistantRosters()
        end
    elseif TWA._playerGroupState == 'alone' and TWA.InParty() then
        -- joined a group of some kind
        setGroupState('party')
        if TWA.InRaid() then
            -- joined a raid
            setGroupState('raid')
            TWA.sync.RequestFullSync()
            TWA.sync.RequestAssistantRosters()
        else
            -- joined a party
            if GetNumPartyMembers() == 1 then
                -- you and the other player just formed the party.
                if not IsPartyLeader() then
                    TWA.sync.RequestFullSync()
                    TWA.sync.RequestAssistantRosters()
                else
                    TWA._firstSyncComplete = true; -- edge case, set true so that the leader will respond to the sync.
                end
            else
                -- joined an already existing party.
                TWA.sync.RequestFullSync()
                TWA.sync.RequestAssistantRosters()
            end
        end
    elseif (TWA._playerGroupState == 'party' or TWA._playerGroupState == 'raid') and not TWA.InParty() then
        -- left the group
        TWA._firstSyncComplete = false
        TWA._syncConversations = {}
        for cid, tid in pairs(TWA.syncRequestTimeouts) do
            twaprint("Leaving group - sync cancelled.")
            TWA.timeout.clear(tid)
        end
        TWA.foreignRosters = {}
        TWA.persistForeignRosters()

        setGroupState('alone')
    elseif TWA._playerGroupState == 'party' and TWA.InRaid() then
        -- party was converted to raid
        setGroupState('raid')
    end
end

-- Consolidate event handlers into a table
TWA.eventHandlers = {
    ADDON_LOADED = function(arg1)
        if arg1 ~= "TWAssignments" then return end
        twaprint("ADDON_LOADED")

        if not TWA_PRESETS then
            TWA_PRESETS = {}
        end

        if not TWA_DATA then
            TWA_DATA = {
                [1] = { '-', '-', '-', '-', '-', '-', '-' },
            }
        end
        TWA.data = TWA_DATA

        if TWA_ROSTER and TWA.testRoster == nil then
            TWA.roster = TWA_ROSTER
        end

        if TWA_FOREIGN_ROSTERS then
            TWA.foreignRosters = TWA_FOREIGN_ROSTERS
        end

        TWA.fillRaidData()
        TWA.PopulateTWA()

        tinsert(UISpecialFrames, "TWA_Main") --makes window close with Esc key
        tinsert(UISpecialFrames, "TWA_RosterManager")

        -- Register slash command for template reassign
        SLASH_TWAREPLACE1 = '/twareplace'
        SlashCmdList["TWAREPLACE"] = function(msg)
            local currentAssignee, newAssignee = strsplit(" ", msg, 2)
            if currentAssignee and newAssignee then
                TWA.ReplaceAssigneeInPresets(currentAssignee, newAssignee)
            else
                twaprint("Usage: /twareplace <currentAssignee> <newAssignee>")
            end
        end
    end,
    PLAYER_LOGIN = function()
        TWA.timeout.set(function()
            twadebug('initializing group state')
            TWA.InitializeGroupState()
        end, TWA.LOGIN_GRACE_PERIOD)
    end,
    RAID_ROSTER_UPDATE = function()
        twadebug("RAID_ROSTER_UPDATE")
        if TWA.partyAndRaidCombinedEventTimeoutId ~= nil then
            TWA.timeout.clear(TWA.partyAndRaidCombinedEventTimeoutId)
            TWA.partyAndRaidCombinedEventTimeoutId = nil
        end
        TWA.PlayerGroupStateUpdate()
        TWA.fillRaidData()
        TWA.PopulateTWA()
    end,
    PARTY_MEMBERS_CHANGED = function()
        twadebug("PARTY_MEMBERS_CHANGED")
        TWA.partyAndRaidCombinedEventTimeoutId = TWA.timeout.set(function()
            TWA.PlayerGroupStateUpdate()
        end, TWA.DOUBLE_EVENT_TIMEOUT)
    end,
    CHAT_MSG_ADDON = function(arg1, arg2, arg3, arg4)
        if (arg1 == "TWA" or arg1 == "TWABW") then
            if debugLevel >= TWA.DEBUG.VERBOSE then
                twadebug(arg4 .. ' says: ' .. arg2)
            end
            if arg1 == "TWA" then
                TWA.sync.processPacket(arg1, arg2, arg3, arg4)
            end
        end

        if arg1 == "QH" then
            TWA.sync.handleQHSync(arg1, arg2, arg3, arg4)
        end
    end,
    CHAT_MSG_WHISPER = function(arg1, arg2)
        if arg1 == 'heal' then
            local lineToSend = ''
            for _, row in next, TWA.data do
                local mark = ''
                local tank = ''
                for i, cell in next, row do
                    if i == 1 then
                        mark = cell
                        tank = mark
                    end
                    if i == 2 or i == 3 or i == 4 then
                        if cell ~= '-' then
                            tank = ''
                        end
                    end
                    if i == 2 or i == 3 or i == 4 then
                        if cell ~= '-' then
                            tank = tank .. cell .. ' '
                        end
                    end
                    if arg2 == cell then
                        if i == 2 or i == 3 or i == 4 then
                            if lineToSend == '' then
                                lineToSend = 'You are assigned to ' .. mark
                            else
                                lineToSend = lineToSend .. ' and ' .. mark
                            end
                        end
                        if i == 5 or i == 6 or i == 7 then
                            if lineToSend == '' then
                                lineToSend = 'You are assigned to Heal ' .. tank
                            else
                                lineToSend = lineToSend .. ' and ' .. tank
                            end
                        end
                    end
                end
            end
            if lineToSend == '' then
                ChatThrottleLib:SendChatMessage("BULK", "TWA", 'You are not assigned.', "WHISPER", "Common", arg2);
            else
                ChatThrottleLib:SendChatMessage("BULK", "TWA", lineToSend, "WHISPER", "Common", arg2);
            end
        end
    end
}

-- Simpler event handling
TWA:SetScript("OnEvent", function()
    if TWA.eventHandlers[event] then
        TWA.eventHandlers[event](arg1, arg2, arg3, arg4)
    end
end)

function TWA.markOrPlayerUsed(markOrPlayer)
    for row, data in next, TWA.data do
        for _, as in next, data do
            if as == markOrPlayer then
                return true
            end
        end
    end
    return false
end

function TWA.persistRoster()
    TWA_ROSTER = TWA.roster
end

function TWA.persistForeignRosters()
    TWA_FOREIGN_ROSTERS = TWA.foreignRosters
end

---Call when a player was promoted to raid leader or assist.
---They should broadcast their roster.
---@param name string
function TWA.PlayerWasPromoted(name)
    if TWA._raidStateInitialized then
        twadebug('player was promoted: ' .. name)
        if name == TWA.me then TWA.sync.BroadcastRoster(TWA.roster, true) end
    end
end

---Call when a player is either
---* No longer has either lead or assist role
---* Is removed from the group
---
---Drops their roster entries.
---@param name string
function TWA.PlayerWasDemoted(name)
    twadebug('player was demoted: ' .. name)
    TWA.foreignRosters[name] = nil
    TWA.persistForeignRosters()
end

function TWA.CheckIfPromoted(name, newRank)
    if newRank > 0 then
        if not (TWA._assistants[name] or TWA._leader == name) then
            TWA.PlayerWasPromoted(name)
        end
    end
end

function TWA.CheckIfDemoted(name) -- new rank is always "normal" (neither assistant nor leader)
    if TWA._leader == name or TWA._assistants[name] then
        TWA.PlayerWasDemoted(name)
    end
end

function TWA.updateRaidStatus()
    local oldLeader = TWA._leader;
    local newLeader = nil;

    ---Holds the name of the player, and their index in the group (for use in GetRaidRosterInfo(index))
    ---@type table<string, integer>
    local nameCache = {}

    for i = 1, GetNumRaidMembers() do
        if GetRaidRosterInfo(i) then
            local name, rank, _, _, _, _, z = GetRaidRosterInfo(i);
            local _, unitClass = UnitClass('raid' .. i)
            unitClass = string.lower(unitClass)
            nameCache[name] = i

            if rank == 2 then -- leader
                TWA.CheckIfPromoted(name, rank)
                newLeader = name
            elseif rank == 1 then -- assist
                TWA.CheckIfPromoted(name, rank)
                TWA._assistants[name] = true
            else -- pleb
                TWA.CheckIfDemoted(name)
                if TWA._leader == name then
                    TWA._leader = nil
                elseif TWA._assistants[name] then
                    TWA._assistants[name] = nil
                end
            end
        else
            twadebug('GetRaidRosterInfo(' .. i .. ') returned nothing')
        end
    end

    TWA._leader = newLeader;

    -- check all current assists and leader if they have left the group
    if oldLeader ~= nil and nameCache[oldLeader] == nil then
        twadebug('leader left the raid: ' .. oldLeader)
        TWA.foreignRosters[oldLeader] = nil
        TWA.persistForeignRosters()
    end

    for name, _ in pairs(TWA._assistants) do
        if nameCache[name] == nil then
            twadebug('assistant left the raid: ' .. name)
            TWA.foreignRosters[name] = nil
            TWA._assistants[name] = nil
            TWA.persistForeignRosters()
        end
    end

    TWA._raidStateInitialized = true
end

function TWA.fillRaidData()
    twadebug('fill raid data')

    TWA.updateRaidStatus()

    TWA.raid = {
        ['warrior'] = {},
        ['paladin'] = {},
        ['druid'] = {},
        ['warlock'] = {},
        ['mage'] = {},
        ['priest'] = {},
        ['rogue'] = {},
        ['shaman'] = {},
        ['hunter'] = {},
    }
    -- current raid members
    for i = 0, GetNumRaidMembers() do
        if GetRaidRosterInfo(i) then
            local name, _, _, _, _, _, z = GetRaidRosterInfo(i);
            local _, unitClass = UnitClass('raid' .. i)
            unitClass = string.lower(unitClass)
            table.insert(TWA.raid[unitClass], name)
            table.sort(TWA.raid[unitClass])
        end
    end
    -- roster list (see TWA.roster)
    for class, names in pairs(TWA.GetCompleteRoster()) do
        for _, name in pairs(names) do
            if not TWA.util.tableContains(TWA.raid[class], name) then
                table.insert(TWA.raid[class], name)
            end
            table.sort(TWA.raid[class])
        end
    end
end

function TWA.isPlayerLeadOrAssist(name)
    return TWA._assistants[name] ~= nil or TWA._leader == name
end

function TWA.isPlayerOffline(name)
    local playerFound = false;
    for i = 0, GetNumRaidMembers() do
        if (GetRaidRosterInfo(i)) then
            local n, _, _, _, _, _, z = GetRaidRosterInfo(i);
            if n == name then
                playerFound = true
                if z == 'Offline' then
                    return true
                end
            end
        end
        if playerFound then break end
    end
    if not playerFound then
        return true -- if not in group, treat as offline (can be in roster yet not in group)
    end
    return false
end

---Handles adding players from other people's rosters to TWA.foreignRosters.
---Duplicate names are not allowed within a class, but is OK across classes.
---@param rosterOwner any
---@param class any
---@param player any
function TWA.addToForeignRoster(rosterOwner, class, player)
    -- Ensure the rosterOwner has a roster in TWA.foreignRosters
    if not TWA.foreignRosters[rosterOwner] then
        TWA.foreignRosters[rosterOwner] = {
            ['druid'] = {},
            ['hunter'] = {},
            ['mage'] = {},
            ['paladin'] = {},
            ['priest'] = {},
            ['rogue'] = {},
            ['shaman'] = {},
            ['warlock'] = {},
            ['warrior'] = {},
        }
    end

    -- Access the roster for this specific rosterOwner
    local ownerRoster = TWA.foreignRosters[rosterOwner]

    -- Check if the player is already in the class list
    if TWA.util.tableContains(ownerRoster[class], player) then return end

    -- If player isn't in the list, add them to the class
    table.insert(ownerRoster[class], player)
    table.sort(ownerRoster[class])
end

function TWA.buildTargetsDropdown()
    if UIDROPDOWNMENU_MENU_LEVEL == 1 then
        local Title = {}
        Title.text = "Target"
        Title.isTitle = true
        UIDropDownMenu_AddButton(Title, UIDROPDOWNMENU_MENU_LEVEL);

        local separator = {};
        separator.text = ""
        separator.disabled = true
        UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

        local Marks = {}
        Marks.text = "Marks"
        Marks.notCheckable = true
        Marks.hasArrow = true
        Marks.value = {
            ['key'] = 'marks'
        }
        UIDropDownMenu_AddButton(Marks, UIDROPDOWNMENU_MENU_LEVEL);

        local Sides = {}
        Sides.text = "Sides"
        Sides.notCheckable = true
        Sides.hasArrow = true
        Sides.value = {
            ['key'] = 'sides'
        }
        UIDropDownMenu_AddButton(Sides, UIDROPDOWNMENU_MENU_LEVEL);

        local Coords = {}
        Coords.text = "Coords"
        Coords.notCheckable = true
        Coords.hasArrow = true
        Coords.value = {
            ['key'] = 'coords'
        }
        UIDropDownMenu_AddButton(Coords, UIDROPDOWNMENU_MENU_LEVEL);

        local Targets = {}
        Targets.text = "Misc"
        Targets.notCheckable = true
        Targets.hasArrow = true
        Targets.value = {
            ['key'] = 'misc'
        }
        UIDropDownMenu_AddButton(Targets, UIDROPDOWNMENU_MENU_LEVEL);

        local Groups = {}
        Groups.text = "Groups"
        Groups.notCheckable = true
        Groups.hasArrow = true
        Groups.value = {
            ['key'] = 'groups'
        }
        UIDropDownMenu_AddButton(Groups, UIDROPDOWNMENU_MENU_LEVEL);

        local separator = {};
        separator.text = ""
        separator.disabled = true
        UIDropDownMenu_AddButton(separator);

        local clear = {};
        clear.text = "Clear"
        clear.disabled = false
        clear.isTitle = false
        clear.notCheckable = true
        clear.func = TWA.changeCell
        clear.arg1 = TWA.currentRow * 100 + TWA.currentCell
        clear.arg2 = 'Clear'
        UIDropDownMenu_AddButton(clear, UIDROPDOWNMENU_MENU_LEVEL);
    end

    if UIDROPDOWNMENU_MENU_LEVEL == 2 then
        if (UIDROPDOWNMENU_MENU_VALUE["key"] == 'marks') then
            local Title = {}
            Title.text = "Marks"
            Title.isTitle = true
            UIDropDownMenu_AddButton(Title, UIDROPDOWNMENU_MENU_LEVEL);

            local separator = {};
            separator.text = ""
            separator.disabled = true
            UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

            for mark, color in next, TWA.marks do
                local dropdownItem = {}
                dropdownItem.text = color .. mark
                dropdownItem.checked = TWA.markOrPlayerUsed(mark)

                dropdownItem.icon = 'Interface\\TargetingFrame\\UI-RaidTargetingIcons'

                if mark == 'Skull' then
                    dropdownItem.tCoordLeft = 0.75
                    dropdownItem.tCoordRight = 1
                    dropdownItem.tCoordTop = 0.25
                    dropdownItem.tCoordBottom = 0.5
                end
                if mark == 'Cross' then
                    dropdownItem.tCoordLeft = 0.5
                    dropdownItem.tCoordRight = 0.75
                    dropdownItem.tCoordTop = 0.25
                    dropdownItem.tCoordBottom = 0.5
                end
                if mark == 'Square' then
                    dropdownItem.tCoordLeft = 0.25
                    dropdownItem.tCoordRight = 0.5
                    dropdownItem.tCoordTop = 0.25
                    dropdownItem.tCoordBottom = 0.5
                end
                if mark == 'Moon' then
                    dropdownItem.tCoordLeft = 0
                    dropdownItem.tCoordRight = 0.25
                    dropdownItem.tCoordTop = 0.25
                    dropdownItem.tCoordBottom = 0.5
                end
                if mark == 'Triangle' then
                    dropdownItem.tCoordLeft = 0.75
                    dropdownItem.tCoordRight = 1
                    dropdownItem.tCoordTop = 0
                    dropdownItem.tCoordBottom = 0.25
                end
                if mark == 'Diamond' then
                    dropdownItem.tCoordLeft = 0.5
                    dropdownItem.tCoordRight = 0.75
                    dropdownItem.tCoordTop = 0
                    dropdownItem.tCoordBottom = 0.25
                end
                if mark == 'Circle' then
                    dropdownItem.tCoordLeft = 0.25
                    dropdownItem.tCoordRight = 0.5
                    dropdownItem.tCoordTop = 0
                    dropdownItem.tCoordBottom = 0.25
                end
                if mark == 'Star' then
                    dropdownItem.tCoordLeft = 0
                    dropdownItem.tCoordRight = 0.25
                    dropdownItem.tCoordTop = 0
                    dropdownItem.tCoordBottom = 0.25
                end

                dropdownItem.func = TWA.changeCell
                dropdownItem.arg1 = TWA.currentRow * 100 + TWA.currentCell
                dropdownItem.arg2 = mark
                UIDropDownMenu_AddButton(dropdownItem, UIDROPDOWNMENU_MENU_LEVEL);
                dropdownItem = nil
            end
        end

        if (UIDROPDOWNMENU_MENU_VALUE["key"] == 'sides') then
            local Title = {}
            Title.text = "Sides"
            Title.isTitle = true
            UIDropDownMenu_AddButton(Title, UIDROPDOWNMENU_MENU_LEVEL);

            local separator = {};
            separator.text = ""
            separator.disabled = true
            UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

            local left = {};
            left.text = TWA.sides['Left'] .. 'Left'
            left.checked = TWA.markOrPlayerUsed('Left')
            left.func = TWA.changeCell
            left.arg1 = TWA.currentRow * 100 + TWA.currentCell
            left.arg2 = 'Left'
            UIDropDownMenu_AddButton(left, UIDROPDOWNMENU_MENU_LEVEL);

            local right = {};
            right.text = TWA.sides['Right'] .. 'Right'
            right.checked = TWA.markOrPlayerUsed('Right')
            right.func = TWA.changeCell
            right.arg1 = TWA.currentRow * 100 + TWA.currentCell
            right.arg2 = 'Right'
            UIDropDownMenu_AddButton(right, UIDROPDOWNMENU_MENU_LEVEL);
        end

        if (UIDROPDOWNMENU_MENU_VALUE["key"] == 'coords') then
            local Title = {}
            Title.text = "Coords"
            Title.isTitle = true
            UIDropDownMenu_AddButton(Title, UIDROPDOWNMENU_MENU_LEVEL);

            local separator = {};
            separator.text = ""
            separator.disabled = true
            UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

            local n = {};
            n.text = TWA.coords['North'] .. 'North'
            n.checked = TWA.markOrPlayerUsed('North')
            n.func = TWA.changeCell
            n.arg1 = TWA.currentRow * 100 + TWA.currentCell
            n.arg2 = 'North'
            UIDropDownMenu_AddButton(n, UIDROPDOWNMENU_MENU_LEVEL);
            local s = {};
            s.text = TWA.coords['South'] .. 'South'
            s.checked = TWA.markOrPlayerUsed('South')
            s.func = TWA.changeCell
            s.arg1 = TWA.currentRow * 100 + TWA.currentCell
            s.arg2 = 'South'
            UIDropDownMenu_AddButton(s, UIDROPDOWNMENU_MENU_LEVEL);
            local e = {};
            e.text = TWA.coords['East'] .. 'East'
            e.checked = TWA.markOrPlayerUsed('East')
            e.func = TWA.changeCell
            e.arg1 = TWA.currentRow * 100 + TWA.currentCell
            e.arg2 = 'East'
            UIDropDownMenu_AddButton(e, UIDROPDOWNMENU_MENU_LEVEL);
            local w = {};
            w.text = TWA.coords['West'] .. 'West'
            w.checked = TWA.markOrPlayerUsed('West')
            w.func = TWA.changeCell
            w.arg1 = TWA.currentRow * 100 + TWA.currentCell
            w.arg2 = 'West'
            UIDropDownMenu_AddButton(w, UIDROPDOWNMENU_MENU_LEVEL);
        end

        if (UIDROPDOWNMENU_MENU_VALUE["key"] == 'misc') then
            local Title = {}
            Title.text = "Misc"
            Title.isTitle = true
            UIDropDownMenu_AddButton(Title, UIDROPDOWNMENU_MENU_LEVEL);

            local separator = {};
            separator.text = ""
            separator.disabled = true
            UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

            for mark, color in next, TWA.misc do
                local markings = {};
                markings.text = color .. mark
                markings.checked = TWA.markOrPlayerUsed(mark)
                markings.func = TWA.changeCell
                markings.arg1 = TWA.currentRow * 100 + TWA.currentCell
                markings.arg2 = mark
                UIDropDownMenu_AddButton(markings, UIDROPDOWNMENU_MENU_LEVEL);
            end
        end

        if (UIDROPDOWNMENU_MENU_VALUE["key"] == 'groups') then
            local Title = {}
            Title.text = "Groups"
            Title.isTitle = true
            UIDropDownMenu_AddButton(Title, UIDROPDOWNMENU_MENU_LEVEL);

            local separator = {};
            separator.text = ""
            separator.disabled = true
            UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

            for mark, color in pairsByKeys(TWA.groups) do
                local markings = {};
                markings.text = color .. mark
                markings.checked = TWA.markOrPlayerUsed(mark)
                markings.func = TWA.changeCell
                markings.arg1 = TWA.currentRow * 100 + TWA.currentCell
                markings.arg2 = mark
                UIDropDownMenu_AddButton(markings, UIDROPDOWNMENU_MENU_LEVEL);
            end
        end
    end
end

function TWA.buildTanksDropdown()
    if UIDROPDOWNMENU_MENU_LEVEL == 1 then
        local Title = {}
        Title.text = "Tanks"
        Title.isTitle = true
        UIDropDownMenu_AddButton(Title, UIDROPDOWNMENU_MENU_LEVEL);

        local separator = {};
        separator.text = ""
        separator.disabled = true
        UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

        local Warriors = {}
        Warriors.text = TWA.classColors['warrior'].c .. 'Warriors'
        Warriors.notCheckable = true
        Warriors.hasArrow = true
        Warriors.value = {
            ['key'] = 'warrior'
        }
        UIDropDownMenu_AddButton(Warriors, UIDROPDOWNMENU_MENU_LEVEL);

        local Druids = {}
        Druids.text = TWA.classColors['druid'].c .. 'Druids'
        Druids.notCheckable = true
        Druids.hasArrow = true
        Druids.value = {
            ['key'] = 'druid'
        }
        UIDropDownMenu_AddButton(Druids, UIDROPDOWNMENU_MENU_LEVEL);

        local Paladins = {}
        Paladins.text = TWA.classColors['paladin'].c .. 'Paladins'
        Paladins.notCheckable = true
        Paladins.hasArrow = true
        Paladins.value = {
            ['key'] = 'paladin'
        }
        UIDropDownMenu_AddButton(Paladins, UIDROPDOWNMENU_MENU_LEVEL);

        local separator = {};
        separator.text = ""
        separator.disabled = true
        UIDropDownMenu_AddButton(separator);

        local Warlocks = {}
        Warlocks.text = TWA.classColors['warlock'].c .. 'Warlocks'
        Warlocks.notCheckable = true
        Warlocks.hasArrow = true
        Warlocks.value = {
            ['key'] = 'warlock'
        }
        UIDropDownMenu_AddButton(Warlocks, UIDROPDOWNMENU_MENU_LEVEL);

        local Mages = {}
        Mages.text = TWA.classColors['mage'].c .. 'Mages'
        Mages.notCheckable = true
        Mages.hasArrow = true
        Mages.value = {
            ['key'] = 'mage'
        }
        UIDropDownMenu_AddButton(Mages, UIDROPDOWNMENU_MENU_LEVEL);

        local Priests = {}
        Priests.text = TWA.classColors['priest'].c .. 'Priests'
        Priests.notCheckable = true
        Priests.hasArrow = true
        Priests.value = {
            ['key'] = 'priest'
        }
        UIDropDownMenu_AddButton(Priests, UIDROPDOWNMENU_MENU_LEVEL);

        local Rogues = {}
        Rogues.text = TWA.classColors['rogue'].c .. 'Rogues'
        Rogues.notCheckable = true
        Rogues.hasArrow = true
        Rogues.value = {
            ['key'] = 'rogue'
        }
        UIDropDownMenu_AddButton(Rogues, UIDROPDOWNMENU_MENU_LEVEL);

        local Hunters = {}
        Hunters.text = TWA.classColors['hunter'].c .. 'Hunters'
        Hunters.notCheckable = true
        Hunters.hasArrow = true
        Hunters.value = {
            ['key'] = 'hunter'
        }
        UIDropDownMenu_AddButton(Hunters, UIDROPDOWNMENU_MENU_LEVEL);

        local Shamans = {}
        Shamans.text = TWA.classColors['shaman'].c .. 'Shamans'
        Shamans.notCheckable = true
        Shamans.hasArrow = true
        Shamans.value = {
            ['key'] = 'shaman'
        }
        UIDropDownMenu_AddButton(Shamans, UIDROPDOWNMENU_MENU_LEVEL);

        local separator = {};
        separator.text = ""
        separator.disabled = true
        UIDropDownMenu_AddButton(separator);

        -- Add the "Groups" menu item
        local Groups = {}
        Groups.text = "Groups"
        Groups.notCheckable = true
        Groups.hasArrow = true
        Groups.value = "GroupsSubMenu"
        UIDropDownMenu_AddButton(Groups, UIDROPDOWNMENU_MENU_LEVEL)

        local clear = {}
        clear.text = "Clear"
        clear.disabled = false
        clear.isTitle = false
        clear.notCheckable = true
        clear.func = TWA.changeCell
        clear.arg1 = TWA.currentRow * 100 + TWA.currentCell
        clear.arg2 = 'Clear'
        UIDropDownMenu_AddButton(clear, UIDROPDOWNMENU_MENU_LEVEL)
    end

    if UIDROPDOWNMENU_MENU_LEVEL == 2 then
        if UIDROPDOWNMENU_MENU_VALUE == "GroupsSubMenu" then
            for i = 1, 8 do
                local groupIndex = i  -- Create a local copy of i
                local groupInfo = {}
                groupInfo.text = "Group" .. groupIndex
                groupInfo.notCheckable = true
                groupInfo.func = function()
                    print("Selected Group" .. groupIndex)
                    TWA.changeCell(TWA.currentRow * 100 + TWA.currentCell, "Group " .. groupIndex)
                end
                UIDropDownMenu_AddButton(groupInfo, UIDROPDOWNMENU_MENU_LEVEL)
            end
        else
            for i, tank in next, TWA.raid[UIDROPDOWNMENU_MENU_VALUE['key']] do
                local Tanks = {}

                local color = TWA.classColors[UIDROPDOWNMENU_MENU_VALUE['key']].c

                if TWA.isPlayerOffline(tank) then
                    color = '|cffff0000'
                end

                Tanks.text = color .. tank
                Tanks.checked = TWA.markOrPlayerUsed(tank)
                Tanks.func = TWA.changeCell
                Tanks.arg1 = TWA.currentRow * 100 + TWA.currentCell
                Tanks.arg2 = tank
                UIDropDownMenu_AddButton(Tanks, UIDROPDOWNMENU_MENU_LEVEL)
            end
        end
    end
end

function TWA.buildHealersDropdown()
    if UIDROPDOWNMENU_MENU_LEVEL == 1 then
        local Healers = {}
        Healers.text = "Healers"
        Healers.isTitle = true
        UIDropDownMenu_AddButton(Healers, UIDROPDOWNMENU_MENU_LEVEL);

        local separator = {};
        separator.text = ""
        separator.disabled = true
        UIDropDownMenu_AddButton(separator, UIDROPDOWNMENU_MENU_LEVEL);

        local Priests = {}
        Priests.text = TWA.classColors['priest'].c .. 'Priests'
        Priests.notCheckable = true
        Priests.hasArrow = true
        Priests.value = {
            ['key'] = 'priest'
        }
        UIDropDownMenu_AddButton(Priests, UIDROPDOWNMENU_MENU_LEVEL);

        local Druids = {}
        Druids.text = TWA.classColors['druid'].c .. 'Druids'
        Druids.notCheckable = true
        Druids.hasArrow = true
        Druids.value = {
            ['key'] = 'druid'
        }
        UIDropDownMenu_AddButton(Druids, UIDROPDOWNMENU_MENU_LEVEL);

        local Shamans = {}
        Shamans.text = TWA.classColors['shaman'].c .. 'Shamans'
        Shamans.notCheckable = true
        Shamans.hasArrow = true
        Shamans.value = {
            ['key'] = 'shaman'
        }
        UIDropDownMenu_AddButton(Shamans, UIDROPDOWNMENU_MENU_LEVEL);

        local Paladins = {}
        Paladins.text = TWA.classColors['paladin'].c .. 'Paladins'
        Paladins.notCheckable = true
        Paladins.hasArrow = true
        Paladins.value = {
            ['key'] = 'paladin'
        }
        UIDropDownMenu_AddButton(Paladins, UIDROPDOWNMENU_MENU_LEVEL);

        local separator = {};
        separator.text = ""
        separator.disabled = true
        UIDropDownMenu_AddButton(separator);

        local clear = {};
        clear.text = "Clear"
        clear.disabled = false
        clear.isTitle = false
        clear.notCheckable = true
        clear.func = TWA.changeCell
        clear.arg1 = TWA.currentRow * 100 + TWA.currentCell
        clear.arg2 = 'Clear'
        UIDropDownMenu_AddButton(clear, UIDROPDOWNMENU_MENU_LEVEL);
    end
    if UIDROPDOWNMENU_MENU_LEVEL == 2 then
        for _, healer in next, TWA.raid[UIDROPDOWNMENU_MENU_VALUE['key']] do
            local Healers = {}

            local color = TWA.classColors[UIDROPDOWNMENU_MENU_VALUE['key']].c

            if TWA.isPlayerOffline(healer) then
                color = '|cffff0000'
            end

            Healers.text = color .. healer
            Healers.checked = TWA.markOrPlayerUsed(healer)
            Healers.func = TWA.changeCell
            Healers.arg1 = TWA.currentRow * 100 + TWA.currentCell
            Healers.arg2 = healer
            UIDropDownMenu_AddButton(Healers, UIDROPDOWNMENU_MENU_LEVEL);
        end
    end
end

function TWA.changeCell(xy, to, dontOpenDropdown)
    dontOpenDropdown = dontOpenDropdown and 1 or 0
    TWA.sync.SendAddonMessage(TWA.MESSAGE.ChangeCell .. "=" .. xy .. "=" .. to .. "=" .. dontOpenDropdown)
    CloseDropDownMenus()
end

function TWA.change(xy, to, sender, dontOpenDropdown)
    local x = math.floor(xy / 100)
    local y = xy - x * 100

    if to ~= 'Clear' then
        TWA.data[x][y] = to
    else
        TWA.data[x][y] = '-'
    end

    TWA.PopulateTWA()
end

function TWA.PopulateTWA()
    twadebug('PopulateTWA')

    for i = 1, 25 do
        if TWA.rows[i] then
            TWA.rows[i]:Hide()
        end
    end

    for index, data in next, TWA.data do
        if not TWA.rows[index] then
            TWA.rows[index] = CreateFrame('Frame', 'TWRow' .. index, getglobal("TWA_Main"), 'TWRow')
        end

        TWA.rows[index]:Show()

        TWA.rows[index]:SetBackdropColor(0, 0, 0, .2);

        TWA.rows[index]:SetPoint("TOP", getglobal("TWA_Main"), "TOP", 0, -25 - index * 21)
        if not TWA.cells[index] then
            TWA.cells[index] = {}
        end

        getglobal('TWRow' .. index .. 'CloseRow'):SetID(index)

        local line = ''

        for i, name in data do
            if not TWA.cells[index][i] then
                TWA.cells[index][i] = CreateFrame('Frame', 'TWCell' .. index .. i, TWA.rows[index], 'TWCell')
            end

            TWA.cells[index][i]:SetPoint("LEFT", TWA.rows[index], "LEFT", -82 + i * 82, 0)

            getglobal('TWCell' .. index .. i .. 'Button'):SetID((index * 100) + i)

            local color = TWA.classColors['priest'].c
            TWA.cells[index][i]:SetBackdropColor(.2, .2, .2, .7);
            if i > 1 then
                for c, n in next, TWA.raid do
                    for _, raidMember in next, n do
                        if raidMember == name then
                            color = TWA.classColors[c].c
                            local r = TWA.classColors[c].r
                            local g = TWA.classColors[c].g
                            local b = TWA.classColors[c].b
                            TWA.cells[index][i]:SetBackdropColor(r, g, b, .7);
                            break
                        end
                    end
                end
            end

            if TWA.marks[name] then
                color = TWA.marks[name]
            end
            if TWA.sides[name] then
                color = TWA.sides[name]
            end
            if TWA.coords[name] then
                color = TWA.coords[name]
            end
            if TWA.misc[name] then
                color = TWA.misc[name]
            end
            if TWA.groups[name] then
                color = TWA.groups[name]
            end

            if name == '-' then
                name = ''
            end

            if i > 1 and name ~= '' and TWA.isPlayerOffline(name) then
                color = '|cffff0000'
            end

            getglobal('TWCell' .. index .. i .. 'Text'):SetText(color .. name)

            getglobal('TWCell' .. index .. i .. 'Icon'):Hide()
            getglobal('TWCell' .. index .. i .. 'Icon'):SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons");

            if name == 'Skull' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0.75, 1, 0.25, 0.5)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end
            if name == 'Cross' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0.5, 0.75, 0.25, 0.5)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end
            if name == 'Square' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0.25, 0.5, 0.25, 0.5)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end
            if name == 'Moon' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0, 0.25, 0.25, 0.5)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end
            if name == 'Triangle' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0.75, 1, 0, 0.25)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end
            if name == 'Diamond' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0.5, 0.75, 0, 0.25)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end
            if name == 'Circle' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0.25, 0.5, 0, 0.25)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end
            if name == 'Star' then
                getglobal('TWCell' .. index .. i .. 'Icon'):SetTexCoord(0, 0.25, 0, 0.25)
                getglobal('TWCell' .. index .. i .. 'Icon'):Show()
            end

            line = line .. name .. '-'
        end
    end

    getglobal('TWA_Main'):SetHeight(75 + table.getn(TWA.data) * 21)
    TWA_DATA = TWA.data
end

function Buttoane_OnEnter(id)
    local index = math.floor(id / 100)

    if id < 100 then
        index = id
    end

    getglobal('TWRow' .. index):SetBackdropColor(1, 1, 1, .2)
end

function Buttoane_OnLeave(id)
    local index = math.floor(id / 100)

    if id < 100 then
        index = id
    end

    getglobal('TWRow' .. index):SetBackdropColor(0, 0, 0, .2)
end


function TWAHandleRosterEditBox(editBox)
    local scrollBar = getglobal(editBox:GetParent():GetName() .. "ScrollBar")
    editBox:GetParent():UpdateScrollChildRect();

    local _, max = scrollBar:GetMinMaxValues();
    scrollBar.prevMaxValue = scrollBar.prevMaxValue or max

    if math.abs(scrollBar.prevMaxValue - scrollBar:GetValue()) <= 1 then
        -- if scroll is down and add new line then move scroll
        scrollBar:SetValue(max);
    end
    if max ~= scrollBar.prevMaxValue then
        -- save max value
        scrollBar.prevMaxValue = max
    end
end

TWA.currentRow = 0
TWA.currentCell = 0

function targetDropdown()
    UIDropDownMenu_Initialize(TWATargetsDropDown, TWA.buildTargetsDropdown, "MENU");
    ToggleDropDownMenu(1, nil, TWATargetsDropDown, "cursor", 2, 3);
end

function tankDropdown()
    UIDropDownMenu_Initialize(TWATanksDropDown, TWA.buildTanksDropdown, "MENU");
    ToggleDropDownMenu(1, nil, TWATanksDropDown, "cursor", 2, 3);
end

function healerDropdown()
    UIDropDownMenu_Initialize(TWAHealersDropDown, TWA.buildHealersDropdown, "MENU");
    ToggleDropDownMenu(1, nil, TWAHealersDropDown, "cursor", 2, 3);
end 

function TWCell_OnClick(id)
    if not TWA_CanMakeChanges() then return end
    TWA.currentRow = math.floor(id / 100)
    TWA.currentCell = id - TWA.currentRow * 100

    --targets
    if TWA.currentCell == 1 then 
        targetDropdown() 
    elseif TWA.currentCell < 5 then
        tankDropdown()
    else
        healerDropdown()
    end

    if IsControlKeyDown() then
        CloseDropDownMenus()
        TWA.changeCell(TWA.currentRow * 100 + TWA.currentCell, "Clear")
    end
end

function ForceSync_OnClick()
    if not TWA_CanMakeChanges() then return end

    StaticPopupDialogs["TWA_FORCE_SYNC_CONFIRM"] = {
        text = "This will overwrite everyone's table of assignments with your table. Are you sure?",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            TWA.sync.BroadcastFullSync()
            TWA.sync.BroadcastFullSync_LEGACY() -- so that old clients can at least receive table data.
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3, -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    }
    StaticPopup_Show("TWA_FORCE_SYNC_CONFIRM")
end

function AddLine_OnClick()
    if not TWA_CanMakeChanges() then return end
    TWA.sync.SendAddonMessage(TWA.MESSAGE.AddLine)
end

function TWA.AddLine()
    if table.getn(TWA.data) < 10 then
        TWA.data[table.getn(TWA.data) + 1] = { '-', '-', '-', '-', '-', '-', '-' };
        TWA.PopulateTWA()
    end
end

function SpamRaid_OnClick()
    if not TWA_CanMakeChanges() then return end
    ChatThrottleLib:SendChatMessage("BULK", "TWA", "Assignments: " .. TWA.loadedTemplate, "RAID_WARNING")

    for _, data in next, TWA.data do
        local line = ''
        local dontPrintLine = true
        local healers = 0
        for i, name in data do
            if i > 4 and name ~= "-" then
                healers = healers + 1
            end
        end
        -- print("This row has " .. healers .. " healers")

        for i, name in data do
            if i == 2 then
                if oRALMainTank and oRALMainTank.core then
                    if name ~= "-" then
                        if oRALMainTank.core.maintanktable[_] ~= name then
                            DEFAULT_CHAT_FRAME.editBox:SetText("/oracl mt set " .. _ .. " " .. name)
                            ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 1)
                        end
                    else
                        if oRALMainTank.core.maintanktable[_] then
                            DEFAULT_CHAT_FRAME.editBox:SetText("/oracl mt remove " .. _)
                            ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 1)
                        end
                    end
                    
                end
            end

            if i > 1 then
                dontPrintLine = dontPrintLine and name == '-'
            end

            local separator = ''
            if i == 1 then
                separator = ' : '
            end
            if i == 4 and healers ~= 0 then
                separator = ' || Healers: '
            end

            if name == '-' then
                name = ''
            end

            if TWA.loadedTemplate == "The Four Horsemen" or TWA.loadedTemplate == "Loatheb" then
                if name ~= '' and i >= 5 then
                    name = '[' .. i - 4 .. ']' .. name
                end
            end

            local bw_icon_replace = {
                ['Skull'] = '|cFFF1EFE4[Skull]|r',
                ['Cross'] = '|cFFB20A05[Cross]|r',
                ['Square'] = '|cFF00B9F3[Square]|r',
                ['Moon'] = '|cFF8FB9D0[Moon]|r',
                ['Triangle'] = '|cFF2BD923[Triangle]|r',
                ['Diamond'] = '|cffB035F2[Diamond]|r',
                ['Circle'] = '|cFFE76100[Circle]|r',
                ['Star'] = '|cFFF7EF52[Star]|r',
            }

            local bw_icon = bw_icon_replace[name]
            
            if bw_icon then
                name = bw_icon
            end

            line = line .. name .. ' ' .. separator
        end

        if not dontPrintLine then
            ChatThrottleLib:SendChatMessage("BULK", "TWA", line, "RAID")
        end
    end
    ChatThrottleLib:SendChatMessage("BULK", "TWA",
        "Not assigned, heal the raid. Whisper me 'heal' if you forget your assignment.", "RAID")
end

function RemRow_OnClick(id)
    if not TWA_CanMakeChanges() then return end
    TWA.sync.SendAddonMessage(TWA.MESSAGE.RemRow .. "=" .. id)
end

function TWA.RemRow(id, sender)
    if TWA.data[id + 1] then
        TWA.data[id] = TWA.data[id + 1]
    end

    local last

    for i in next, TWA.data do
        if i > id then
            if TWA.data[i + 1] then
                TWA.data[i] = TWA.data[i + 1]
            end
        end
        last = i
    end

    TWA.data[last] = nil

    TWA.PopulateTWA()
end

function TWA.restoreDefault()
    template = TWA.loadedTemplate
    
    TWA.data = {}
    for i, d in next, TWA.backupTemplates[template] do
        TWA.data[i] = d
    end
    TWA.PopulateTWA()
    twaprint('Loading defaults for |cff69ccf0' .. template)

    return true
end

function Reset_OnClick()
    if not TWA_CanMakeChanges() then return end

    StaticPopupDialogs["TWA_RESET_CONFIRM"] = {
        text = "Are you sure you want to clear current assignments?",
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
            TWA.restoreDefault()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3, -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    }
    StaticPopup_Show("TWA_RESET_CONFIRM")
end


function TWA.WipeTable()
    for i = 1, table.getn(TWA.data) do
        for j = 2, 7 do -- skip target col
            TWA.data[i][j] = '-'
        end
    end
    TWA.PopulateTWA()
end

function CloseTWA_OnClick()
    getglobal('TWA_Main'):Hide()
    getglobal('TWA_RosterManager'):Hide()
    getglobal('QuickFill'):Hide()
end

function toggle_TWA_Main()
    if (getglobal('TWA_Main'):IsVisible()) then
        CloseTWA_OnClick()
    else
        getglobal('TWA_Main'):Show()
    end
end

function ToggleQuickFill_OnClick()
    if getglobal('QuickFill'):IsVisible() then
        getglobal('QuickFill'):Hide()
    else
        getglobal('QuickFill'):Show()
    end
end

function LoadPreset_OnClick()
    if not TWA_CanMakeChanges() then return end
    if TWA.loadedTemplate == '' then
        twaprint('Please load a template first.')
    else
        TWA.loadTemplate(TWA.loadedTemplate)
        TWA.sync.BroadcastWipeTable()
        if TWA_PRESETS[TWA.loadedTemplate] then
            for index, data in next, TWA_PRESETS[TWA.loadedTemplate] do
                for i, name in data do
                    if i ~= 1 and name ~= '-' then
                        TWA.changeCell(index * 100 + i, name, true)
                    end
                end
            end
        else
            twaprint('No preset saved for |cff69ccf0' .. TWA.loadedTemplate)
        end
    end
end

function SavePreset_OnClick()
    if not TWA_CanMakeChanges() then return end
    if TWA.loadedTemplate == '' then
        twaprint('Please load a template first.')
    else
        local preset = {}
        for index, data in next, TWA.data do
            preset[index] = {}
            for i, name in data do
                table.insert(preset[index], name)
            end
        end
        TWA_PRESETS[TWA.loadedTemplate] = preset
        twaprint('Saved preset for |cff69ccf0' .. TWA.loadedTemplate)
    end
end


---@param delimiter string
---@return table<integer, string>
function string:split(delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(self, delimiter, from)
    while delim_from do
        table.insert(result, string.sub(self, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(self, delimiter, from)
    end
    table.insert(result, string.sub(self, from))
    return result
end

function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a, function(a, b)
        return a < b
    end)
    local i = 0 -- iterator variable
    local iter = function()
        -- iterator function
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end

-- Helper function to capitalize first letter
local function strCapitalize(str)
    return string.upper(string.sub(str, 1, 1)) .. string.lower(string.sub(str, 2))
end

-- Function to replace assignee in current template
function TWA.ReplaceAssigneeInData(currentAssignee, newAssignee)
    if not currentAssignee or not newAssignee then
        twaprint("Error: Both currentAssignee and newAssignee must be provided.")
        return
    end

    local currentLower = string.lower(currentAssignee)
    local formattedNewAssignee = strCapitalize(string.lower(newAssignee))
    
    for rowIndex, row in ipairs(TWA_DATA) do
        if type(row) == "table" then
            for colIndex, assignee in ipairs(row) do
                if string.lower(assignee) == currentLower then
                    local xy = rowIndex * 100 + colIndex
                    TWA.change(xy, formattedNewAssignee, "system", true)
                    print('Replaced ' .. assignee .. ' with ' .. formattedNewAssignee)
                end
            end
        end
    end
    twaprint('Replaced ' .. currentAssignee .. ' with ' .. newAssignee .. ' in the current template.')
end

-- Function to switch to the next or previous template
function TWA:SwitchTemplate(direction)
    if not TWA.templatesMenu then
        print("Debug: No template menu available")
        return
    end

    -- Find current template index
    local currentIndex = 1
    local templateCount = table.getn(TWA.templatesMenu)
    
    for i, template in ipairs(TWA.templatesMenu) do
        if template[1] == TWA.loadedTemplate then
            currentIndex = i
            break
        end
    end
    
    -- Calculate new index with wrapping
    local newIndex = currentIndex
    if direction == "next" then
        newIndex = currentIndex == templateCount and 1 or currentIndex + 1
    elseif direction == "previous" then
        newIndex = currentIndex == 1 and templateCount or currentIndex - 1
    end
    
    -- Load new template
    local newTemplate = TWA.templatesMenu[newIndex][1]
    TWA.loadTemplate(newTemplate)
end



-- Function to check input boxes and replace assignees
function QuickFillReplace_OnClick()
    local boxTypes = {
        { prefix = "MT", count = 4 },
        { prefix = "Heal", count = 4 }
    }
    
    local inputBoxes = {}
    for _, type in ipairs(boxTypes) do
        for i = 1, type.count do
            table.insert(inputBoxes, {
                box = type.prefix .. i .. "InputBox",
                assignee = type.prefix .. i
            })
        end
    end

    for _, entry in ipairs(inputBoxes) do
        local inputBox = getglobal(entry.box)
        if inputBox then
            local newAssignee = inputBox:GetText()
            if newAssignee and newAssignee ~= "" then
                TWA.ReplaceAssigneeInData(entry.assignee, newAssignee)
            end
        else
            print(entry.box .. " not found")
        end
    end
end

