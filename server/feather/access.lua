-- bcc-doorlocks' boundaries to feather-jobs and feather-inventory.
--
-- A door lists job keys (feather-jobs definition keys such as 'sheriff'); a
-- character qualifies when it holds an open assignment for one of them, and,
-- when Config.JobAccess.requireOnDuty is true, is on duty for it. Key items and
-- lockpicks are counted and removed through feather-inventory.

DoorJobs = {}

local JOB_KEY = '^[a-z][a-z0-9_]*$'

function DoorJobs.IsJobKey(value)
    return type(value) == 'string' and #value <= 48 and value:match(JOB_KEY) ~= nil
end

-- Facts only: true when the character holds the job (and the duty, if required).
function DoorJobs.Holds(characterId, jobKey)
    if not DoorCharacters.IsUuid(characterId) or not DoorJobs.IsJobKey(jobKey) then return false end
    local request = { characterId = characterId, jobKey = jobKey }
    if Config.JobAccess.requireOnDuty then request.dutyState = 'on_duty' end
    local result = Doorlocks.Call('feather-jobs', 'CheckAssignment', request)
    if not result.ok then
        DBG:Warning(('jobs check failed for %s: %s'):format(jobKey, tostring(result.code)))
        return false
    end
    return type(result.value) == 'table' and result.value.matched == true
end

DoorInventory = {}

local api

local function Api()
    if api then return api end
    if GetResourceState('feather-inventory') ~= 'started' then return nil end
    local called, value = pcall(function() return exports['feather-inventory']:initiate() end)
    api = called and type(value) == 'table' and value or nil
    return api
end

AddEventHandler('onResourceStart', function(resource)
    if resource == 'feather-inventory' then api = nil end
end)

local ITEM = '^[A-Za-z0-9_%-]+$'

function DoorInventory.IsItemName(value)
    return type(value) == 'string' and #value <= 50 and value:match(ITEM) ~= nil
end

-- Number of an item in the player's own inventory; 0 when unknown or on error.
function DoorInventory.Count(src, itemName)
    local inventory = Api()
    if not inventory or not DoorInventory.IsItemName(itemName) then return 0 end
    local result = inventory.Items.GetItemCount(itemName, src)
    if type(result) ~= 'table' or not result.ok then return 0 end
    return tonumber(result.value) or 0
end

function DoorInventory.Remove(src, itemName, quantity)
    local inventory = Api()
    if not inventory or not DoorInventory.IsItemName(itemName) then
        return Doorlocks.Err('dependency_unavailable', 'Inventory API is unavailable.')
    end
    local result = inventory.Items.RemoveItemByName(itemName, quantity or 1, src)
    if type(result) == 'table' and result.ok then return result end
    local problem = type(result) == 'table' and type(result.error) == 'table' and result.error or {}
    return Doorlocks.Err(problem.code or 'inventory_failed', problem.message)
end
