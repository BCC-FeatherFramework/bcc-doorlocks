-- Every handler derives the player from the feather-core session and checks its
-- own permission on the server. Staff actions need the Authority capability
-- (Config.Admin.capability); locking needs a matching job, key item or
-- allowed character; a lockpick result is only accepted after this server
-- started that lockpick for that player and door.

local function SafeDecode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    if ok and decoded ~= nil then return decoded end
    return fallback
end

-- A door is { hash, model, name, x, y, z }; a double door is a list of two.
local function IsWhole(value)
    return type(value) == 'number' and value % 1 == 0
end

local function IsDoorEntry(entry)
    return type(entry) == 'table' and IsWhole(entry[1]) and IsWhole(entry[2])
        and type(entry[3]) == 'string' and #entry[3] <= 128
        and type(entry[4]) == 'number' and type(entry[5]) == 'number' and type(entry[6]) == 'number'
end

local function IsDoorTable(doorTable)
    if IsDoorEntry(doorTable) then return true end
    return type(doorTable) == 'table' and #doorTable == 2 and IsDoorEntry(doorTable[1]) and IsDoorEntry(doorTable[2])
end

local function DoorEntries(doorTable)
    return IsDoorEntry(doorTable) and { doorTable } or doorTable
end

-- Server-side distance check against the nearest linked door. Skipped when the
-- server cannot see the player's position (coordinates at the origin).
local function IsNearDoor(src, doorTable)
    if not Config.ServerDistanceCheck then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local coords = GetEntityCoords(ped)
    if coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0 then return true end
    local limit = (tonumber(Config.DoorRadius) or 1.5) + 3.0
    for _, entry in ipairs(DoorEntries(doorTable)) do
        if #(coords - vector3(entry[4], entry[5], entry[6])) <= limit then return true end
    end
    return false
end

local function IsAdmin(src)
    local allowed = DoorAuthority.IsAllowed(src)
    return allowed == true
end

-- Validates the access lists a staff member submits. Jobs are feather-jobs keys,
-- ids are character UUIDs or connected server IDs (resolved to UUIDs here).
local function CleanJobs(jobs)
    local cleaned = {}
    if type(jobs) ~= 'table' then return cleaned end
    for _, job in ipairs(jobs) do
        local key = type(job) == 'string' and job:lower() or nil
        if DoorJobs.IsJobKey(key) and #cleaned < 32 then cleaned[#cleaned + 1] = key end
    end
    return cleaned
end

local function CleanIds(ids)
    local cleaned, seen = {}, {}
    if type(ids) ~= 'table' then return cleaned end
    for _, id in ipairs(ids) do
        local characterId = DoorCharacters.Resolve(id)
        if characterId and not seen[characterId] and #cleaned < 64 then
            seen[characterId] = true
            cleaned[#cleaned + 1] = characterId
        end
    end
    return cleaned
end

local function CleanKeyItem(keyItem)
    if DoorInventory.IsItemName(keyItem) then return keyItem end
    return 'none'
end

local function SetDoorLocked(doorTable, locked, src)
    DB.exec('UPDATE `doorlocks` SET `locked` = ? WHERE `doorinfo` = ?', locked and 'true' or 'false', json.encode(doorTable))
    TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', -1, doorTable, locked, true, false, true, src)
end

RegisterNetEvent('bcc-doorlocks:InsertIntoDB', function(doorTable, jobs, keyItem, ids)
    local src = source
    if not IsAdmin(src) then return DBG:Warning('InsertIntoDB denied for ' .. tostring(src)) end
    if not IsDoorTable(doorTable) then return NotifyClient(src, _U("dbError"), 4000) end
    DBG:Info("InsertIntoDB triggered with doorTable: " .. json.encode(doorTable))

    local kItem = CleanKeyItem(keyItem)
    local pIds = json.encode(CleanIds(ids))
    local allowedJobs = json.encode(CleanJobs(jobs))
    local doorJson = json.encode(doorTable)

    local doesDoorExist = DB.query('SELECT `doorid` FROM `doorlocks` WHERE `doorinfo` = ?', doorJson)
    if not doesDoorExist then
        DBG:Error("Database query failed while checking if the door exists.")
        return NotifyClient(src, _U("dbError"), 4000)
    end
    if #doesDoorExist <= 0 then
        DB.exec(
            'INSERT INTO `doorlocks` (`jobsallowedtoopen`, `keyitem`, `locked`, `doorinfo`, `ids_allowed`) VALUES (?, ?, ?, ?, ?)',
            allowedJobs, kItem, 'true', doorJson, pIds)
        DBG:Success("Door inserted into DB with jobs: " .. allowedJobs .. ", key: " .. kItem .. ", ids: " .. pIds)
        TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', -1, doorTable, true, true, false, false)
        NotifyClient(src, _U("doorCreated"), 4000)
    else
        DBG:Warning("Door already exists in DB")
        NotifyClient(src, _U("doorExists"), 4000)
    end

    local created = DB.query('SELECT `doorid` FROM `doorlocks` WHERE `doorinfo` = ?', doorJson)
    if created and #created > 0 then
        TriggerClientEvent('bcc-doorlocks:ExportCreationIdCatch', src, created[1].doorid)
    end
end)

FeatherRPC:Register('bcc-doorlocks:AdminCheck', function(_, cb, src)
    cb(IsAdmin(src))
end)

RegisterNetEvent('bcc-doorlocks:InitLoadDoorLocks', function()
    local src = source
    if not DoorCharacters.Get(src) then return end
    DBG:Info("InitLoadDoorLocks triggered by source: " .. src)

    for _, v in ipairs(DB.query('SELECT `doorinfo`, `locked` FROM `doorlocks`') or {}) do
        local doorTable = SafeDecode(v.doorinfo, nil)
        if IsDoorTable(doorTable) then
            TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', src, doorTable, v.locked == 'true', true, false, false)
        end
    end
end)

-- Staff only: grants a character access to a door, creating the door if needed.
-- Other resources should use the server API (exports['bcc-doorlocks']:getDoorLocksAPI()).
RegisterNetEvent('bcc-doorlocks:AddPlayerToDoor', function(door, playerId)
    local src = source
    if not IsAdmin(src) then return DBG:Warning('AddPlayerToDoor denied for ' .. tostring(src)) end
    local characterId = DoorCharacters.Resolve(playerId)
    if not IsDoorTable(door) or not characterId then
        return DBG:Error("Invalid door or player in AddPlayerToDoor event.")
    end

    local doorJson = json.encode(door)
    local result = DB.query("SELECT `doorid`, `ids_allowed` FROM doorlocks WHERE doorinfo = ?", doorJson)
    local doorId

    if result and #result > 0 then
        local idsAllowed = SafeDecode(result[1].ids_allowed, {})
        if not table.contains(idsAllowed, characterId) then
            table.insert(idsAllowed, characterId)
            DB.exec("UPDATE doorlocks SET ids_allowed = ? WHERE doorinfo = ?", json.encode(idsAllowed), doorJson)
        end
        doorId = result[1].doorid
    else
        local insertResult = DB.raw("INSERT INTO doorlocks (doorinfo, ids_allowed, locked) VALUES (?, ?, ?)",
            doorJson, json.encode({ characterId }), 'true')
        if insertResult and insertResult.insertId then
            doorId = insertResult.insertId
        else
            return DBG:Error("Failed to insert door into database.")
        end
    end

    TriggerClientEvent('bcc-doorlocks:ExportCreationIdCatch', src, doorId)
end)

RegisterNetEvent('bcc-doorlocks:GetAllDoorlocks', function()
    local src = source
    if not IsAdmin(src) then return end
    local result = DB.query('SELECT * FROM doorlocks')
    if result then
        TriggerClientEvent('bcc-doorlocks:ReceiveAllDoorlocks', src, result)
    else
        NotifyClient(src, _U("dbError"), 4000)
    end
end)

FeatherRPC:Register("bcc-doorlocks:GetDoorField", function(params, cb, src)
    if not IsAdmin(src) then return cb(nil) end
    local door = DoorLocksAPI:GetDoorById(tonumber(params.doorId))
    if not door then return cb(nil) end

    local result
    if params.field == 'jobsallowedtoopen' then
        result = door:GetAllowedJobs()
    elseif params.field == 'ids_allowed' then
        result = door:GetAllowedIds()
    elseif params.field == 'keyitem' then
        result = door:GetKeyItem()
    else
        return cb(nil)
    end
    cb(json.encode(result))
end)

FeatherRPC:Register("bcc-doorlocks:UpdateDoorlock", function(params, cb, src)
    if not IsAdmin(src) then return cb(false) end
    local door = DoorLocksAPI:GetDoorById(tonumber(params.doorId))
    if not door or params.value == nil then return cb(false) end

    local field, value = params.field, params.value
    if field == 'jobsallowedtoopen' then
        local jobs = type(value) == "string" and SafeDecode(value, nil) or value
        if type(jobs) ~= "table" then return cb(false) end
        door:UpdateAllowedJobs(CleanJobs(jobs))
    elseif field == 'keyitem' then
        if type(value) ~= "string" then return cb(false) end
        door:UpdateKeyItem(CleanKeyItem(value))
    elseif field == 'ids_allowed' then
        local ids = type(value) == "string" and SafeDecode(value, nil) or value
        if type(ids) ~= "table" then return cb(false) end
        door:UpdateAllowedIds(CleanIds(ids))
    else
        return cb(false)
    end
    DBG:Success(("Updated %s for door ID: %s"):format(field, tostring(params.doorId)))
    cb(true)
end)

RegisterNetEvent('bcc-doorlocks:GetDoorlockDetails', function(doorId)
    local src = source
    if not IsAdmin(src) then return end
    local result = DB.query('SELECT * FROM doorlocks WHERE doorid = ?', tonumber(doorId))
    if result and #result > 0 then
        TriggerClientEvent('bcc-doorlocks:ReceiveDoorlockDetails', src, result[1])
    else
        NotifyClient(src, _U("doorNotFound"), 4000)
    end
end)

FeatherRPC:Register("bcc-doorlocks:DeleteDoorlock", function(params, cb, src)
    if not IsAdmin(src) then return cb(false) end
    local doorlockId = tonumber(params.doorlockId)
    local result = doorlockId and DB.query('SELECT `doorinfo` FROM doorlocks WHERE doorid = ?', doorlockId)
    if not result or #result == 0 then return cb(false) end

    DB.exec('DELETE FROM doorlocks WHERE doorid = ?', doorlockId)
    local doorTable = SafeDecode(result[1].doorinfo, nil)
    if IsDoorTable(doorTable) then
        TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', -1, doorTable, false, false, true, false)
    end
    DBG:Success("Deleted door lock ID: " .. tostring(doorlockId))
    NotifyClient(src, _U("doorDeleted"), 4000)
    cb(true)
end)

RegisterNetEvent('bcc-doorlocks:DeleteDoor', function(doorTable)
    local src = source
    if not IsAdmin(src) or not IsDoorTable(doorTable) then return end
    DB.exec('DELETE FROM `doorlocks` WHERE `doorinfo` = ?', json.encode(doorTable))
    TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', -1, doorTable, false, false, true, false)
    NotifyClient(src, _U("doorDeleted"), 4000)
end)

-- Lockpicking ------------------------------------------------------------------
-- The server starts a lockpick only for a player who holds the item and stands
-- at the door, and remembers it briefly. The client's minigame result is only
-- accepted for that same door within the window, once.

local pendingLockpicks = {} -- src -> { door = doorJson, expires = ms }
local LOCKPICK_WINDOW_MS = 120000

local function TakePendingLockpick(src, doorTable)
    local pending = pendingLockpicks[src]
    pendingLockpicks[src] = nil
    return pending ~= nil and pending.door == json.encode(doorTable) and GetGameTimer() <= pending.expires
end

AddEventHandler('playerDropped', function()
    pendingLockpicks[source] = nil
end)

RegisterNetEvent('bcc-doorlocks:ServDoorStatusSet', function(doorTable, locked, lockpicked)
    local src = source
    local characterId = DoorCharacters.Get(src)
    if not characterId or not IsDoorTable(doorTable) or type(locked) ~= 'boolean' then return end
    if not IsNearDoor(src, doorTable) then return DBG:Warning('Door toggle out of range for ' .. tostring(src)) end

    if lockpicked == true then
        if locked == false and TakePendingLockpick(src, doorTable) then
            DBG:Info("Lockpick successful for doorTable: " .. json.encode(doorTable))
            return SetDoorLocked(doorTable, false, src)
        end
        return DBG:Warning('Unverified lockpick result from ' .. tostring(src))
    end

    if IsAdmin(src) then return SetDoorLocked(doorTable, locked, src) end

    local result = DB.query('SELECT * FROM `doorlocks` WHERE `doorinfo` = ?', json.encode(doorTable))
    if not result or #result == 0 then return DBG:Error("Door not found in database.") end
    local doorData = result[1]

    for _, job in ipairs(SafeDecode(doorData.jobsallowedtoopen, {})) do
        if DoorJobs.Holds(characterId, job) then
            DBG:Info("Job match found for character: " .. characterId)
            return SetDoorLocked(doorTable, locked, src)
        end
    end

    if doorData.keyitem ~= 'none' and DoorInventory.Count(src, doorData.keyitem) >= 1 then
        DBG:Info("Key item found for character: " .. characterId)
        return SetDoorLocked(doorTable, locked, src)
    end

    for _, id in ipairs(SafeDecode(doorData.ids_allowed, {})) do
        if id == characterId then
            DBG:Info("ID match found for character: " .. characterId)
            return SetDoorLocked(doorTable, locked, src)
        end
    end

    DBG:Error("Access denied for character: " .. characterId .. " to doorTable: " .. json.encode(doorTable))
    NotifyClient(src, _U("noAccess"), 4000)
end)

RegisterNetEvent('bcc-doorlocks:LockPickCheck', function(doorTable)
    local src = source
    if not Config.LockPicking.allowlockpicking or not DoorCharacters.Get(src) or not IsDoorTable(doorTable) then return end
    if not IsNearDoor(src, doorTable) then return end
    if GetResourceState('bcc-minigames') ~= 'started' and Config.LockPicking.minigameScript == 'bcc_minigames' then
        return NotifyClient(src, _U("lockpickUnavailable"), 4000)
    end

    if DoorInventory.Count(src, Config.LockPicking.minigameSettings.lockpickitem) >= 1 then
        pendingLockpicks[src] = { door = json.encode(doorTable), expires = GetGameTimer() + LOCKPICK_WINDOW_MS }
        TriggerClientEvent('bcc-doorlocks:lockpickingMinigame', src, doorTable)
    else
        NotifyClient(src, _U("noLockpick"), 4000)
    end
end)

-- A failed lockpick costs the pick; only after this server started one.
RegisterNetEvent('bcc-doorlocks:RemoveLockpick', function(doorTable)
    local src = source
    if not TakePendingLockpick(src, doorTable) then return end
    local removed = DoorInventory.Remove(src, Config.LockPicking.minigameSettings.lockpickitem, 1)
    if not removed.ok then DBG:Error("Failed to remove lockpick for user: " .. src) end
end)

-- Read-only release check, server console only.
RegisterCommand('DoorlocksReleaseSmokeTest', function(source)
    if source ~= 0 then return end
    local probe = '00000000-0000-0000-0000-000000000000'
    local jobs = Doorlocks.Call('feather-jobs', 'CheckAssignment', { characterId = probe, jobKey = 'doorlocks_probe' })
    local role = Doorlocks.Call('feather-authority', 'FindRoleByKey', { roleKey = Config.Admin.role })
    local legacy = DB.value([[SELECT COUNT(*) FROM `doorlocks`
        WHERE `jobsallowedtoopen` NOT LIKE '[%' OR `ids_allowed` IS NULL OR `ids_allowed` REGEXP '[\\[,][0-9]']])
    local inventory = GetResourceState('feather-inventory') == 'started'
        and exports['feather-inventory']:initiate() or nil
    local lockpickItem = inventory and inventory.Items.ItemExists(Config.LockPicking.minigameSettings.lockpickitem)
    local tests = {
        { 'development disabled', Config.devMode.active == false },
        { 'jobs trust', jobs.ok == true },
        { 'authority role owned', role.ok == true and role.value.ownerResource == GetCurrentResourceName() },
        { 'no legacy access rows', tonumber(legacy) == 0 },
        { 'lockpick item defined', not Config.LockPicking.allowlockpicking
            or (type(lockpickItem) == 'table' and lockpickItem.ok == true and lockpickItem.value == true) }
    }
    local passed = 0
    for _, test in ipairs(tests) do
        if test[2] then passed = passed + 1 end
        print(('[DoorlocksReleaseSmokeTest] %-24s %s'):format(test[1], test[2] and 'PASS' or 'FAIL'))
    end
    print(('[DoorlocksReleaseSmokeTest] lockpicking %s'):format(
        GetResourceState('bcc-minigames') == 'started' and 'available (bcc-minigames)' or 'hidden (no minigame running)'))
    print(('[DoorlocksReleaseSmokeTest] done %d/%d passed (read-only)'):format(passed, #tests))
end, true)

-- Read-only, server console only: what a job door decides for a character. The
-- character may be offline. Usage: DoorlocksJobCheck <characterUuid> <jobKey>
RegisterCommand('DoorlocksJobCheck', function(source, args)
    if source ~= 0 then return end
    local characterId, jobKey = args[1] and args[1]:lower(), args[2]
    if not DoorCharacters.IsUuid(characterId) or not DoorJobs.IsJobKey(jobKey) then
        return print('[DoorlocksJobCheck] usage: DoorlocksJobCheck <characterUuid> <jobKey>')
    end
    local held = Doorlocks.Call('feather-jobs', 'CheckAssignment', { characterId = characterId, jobKey = jobKey })
    print(('[DoorlocksJobCheck] %s holds %s: %s; requireOnDuty=%s; door opens: %s'):format(
        characterId, jobKey, held.ok and tostring(held.value.matched) or ('error ' .. tostring(held.code)),
        tostring(Config.JobAccess.requireOnDuty), tostring(DoorJobs.Holds(characterId, jobKey))))
end, true)

function table.contains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end
