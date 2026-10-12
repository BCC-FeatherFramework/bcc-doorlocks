DoorLocksAPI = {} -- Set up the API table

exports("getDoorLocksAPI", function()
    return DoorLocksAPI
end)

-- Get a door by its ID
function DoorLocksAPI:GetDoorById(doorId)
    local doorData = DB.query("SELECT * FROM doorlocks WHERE doorid = ?", doorId)
    if #doorData > 0 then
        local door = {}
        door.id = doorData[1].doorid
        door.info = json.decode(doorData[1].doorinfo)
        door.jobs = json.decode(doorData[1].jobsallowedtoopen)
        door.keyItem = doorData[1].keyitem
        door.locked = doorData[1].locked == "true"
        door.idsAllowed = json.decode(doorData[1].ids_allowed)

        function door:GetDoorInfo()
            return self.info
        end

        function door:GetAllowedJobs()
            return self.jobs
        end

        function door:GetKeyItem()
            return self.keyItem
        end

        function door:IsLocked()
            return self.locked
        end

        function door:GetAllowedIds()
            return self.idsAllowed
        end

        function door:UpdateLockStatus(lockStatus)
            local lockValue = lockStatus and "true" or "false"
            DB.exec("UPDATE doorlocks SET locked = ? WHERE doorid = ?", lockValue, self.id)
            self.locked = lockStatus
            -- Every client applies the new state.
            TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', -1, self.info, lockStatus == true, true, false, false)
        end

        function door:UpdateAllowedJobs(newJobs)
            local jobsJSON = json.encode(newJobs)
            DB.exec("UPDATE doorlocks SET jobsallowedtoopen = ? WHERE doorid = ?", jobsJSON, self.id)
            self.jobs = newJobs
        end

        function door:UpdateKeyItem(newKeyItem)
            DB.exec("UPDATE doorlocks SET keyitem = ? WHERE doorid = ?", newKeyItem, self.id)
            self.keyItem = newKeyItem
        end

        function door:UpdateAllowedIds(newIds)
            local idsJSON = json.encode(newIds)
            DB.exec("UPDATE doorlocks SET ids_allowed = ? WHERE doorid = ?", idsJSON, self.id)
            self.idsAllowed = newIds
        end

        function door:DeleteDoor()
            DB.exec("DELETE FROM doorlocks WHERE doorid = ?", self.id)
            TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', -1, self.info, false, false, true, false)
        end

        return door
    else
        return false
    end
end

-- Get all doors
function DoorLocksAPI:GetAllDoors()
    local doorsData = DB.query("SELECT * FROM doorlocks")
    if #doorsData > 0 then
        local doors = {}
        for _, door in ipairs(doorsData) do
            table.insert(doors, {
                id = door.doorid,
                info = json.decode(door.doorinfo),
                jobs = json.decode(door.jobsallowedtoopen),
                keyItem = door.keyitem,
                locked = door.locked == "true",
                idsAllowed = json.decode(door.ids_allowed)
            })
        end
        return doors
    else
        return false
    end
end

-- Add a new door
-- Returns the new door ID (nil on failure). Every client receives the lock
-- straight away. doorInfo is the door hash table (or a JSON string of it);
-- allowedIds are Feather character UUIDs.
function DoorLocksAPI:AddDoor(doorInfo, allowedJobs, keyItem, allowedIds, lockStatus)
    if type(doorInfo) == "string" then
        local ok, decoded = pcall(json.decode, doorInfo)
        doorInfo = ok and decoded or nil
    end
    if type(doorInfo) ~= "table" then return nil end
    local lockValue = lockStatus and "true" or "false"
    local doorId = DB.insert(
        "INSERT INTO doorlocks (doorinfo, jobsallowedtoopen, keyitem, locked, ids_allowed) VALUES (?, ?, ?, ?, ?)",
        json.encode(doorInfo), json.encode(allowedJobs or {}), keyItem or "none", lockValue, json.encode(allowedIds or {})
    )
    TriggerClientEvent('bcc-doorlocks:ClientSetDoorStatus', -1, doorInfo, lockStatus == true, true, false, false)
    return tonumber(doorId)
end

local function firstHash(doorInfo)
    if type(doorInfo) ~= "table" then return nil end
    if type(doorInfo[1]) == "table" then return tonumber(doorInfo[1][1]) end -- double door
    return tonumber(doorInfo[1])
end

-- The door locking that door (matched by its door hash), or false.
function DoorLocksAPI:GetDoorByInfo(doorInfo)
    if type(doorInfo) == "string" then
        local ok, decoded = pcall(json.decode, doorInfo)
        doorInfo = ok and decoded or nil
    end
    local hash = firstHash(doorInfo)
    if not hash then return false end
    for _, row in ipairs(DB.query("SELECT doorid, doorinfo FROM doorlocks WHERE doorinfo LIKE ?", '%' .. tostring(math.floor(hash)) .. '%') or {}) do
        local ok, info = pcall(json.decode, row.doorinfo)
        if ok and firstHash(info) == hash then
            return self:GetDoorById(row.doorid)
        end
    end
    return false
end
