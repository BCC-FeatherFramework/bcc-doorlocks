-- bcc-doorlocks' boundary to the Feather Framework (server side).
--
-- Keeps the call shapes the existing handlers were written against (DBG,
-- an RPC object, notifications) while every identity now comes from the
-- feather-core session. Character IDs are UUIDs; nothing the client sends
-- about who it is is trusted.

Doorlocks = Doorlocks or {}

function Doorlocks.Ok(value) return { ok = true, value = value } end
function Doorlocks.Err(code, message, details)
    return { ok = false, code = code, message = message, details = details }
end

-- Debug output, replaces the bcc-utils debugger. Supports DBG:Info and DBG.Info.
local function debugPrinter(color, label)
    return function(first, second)
        if not Config.devMode.active then return end
        local message = first == DBG and second or first
        -- One print per line, each ending with ^0 so the color never carries over.
        for line in (tostring(message) .. '\n'):gmatch('(.-)\n') do
            print(('^%d[bcc-doorlocks %s]^0 %s^0'):format(color, label, line))
        end
    end
end

DBG = {
    Info = debugPrinter(4, 'info'),
    Success = debugPrinter(2, 'ok'),
    Warning = debugPrinter(3, 'warn'),
    Error = debugPrinter(1, 'error')
}

-- RPC ------------------------------------------------------------------------
-- Same handler shape as bcc-utils: function(params, cb, source).

FeatherRPC = {}

function FeatherRPC:Register(name, handler, options)
    local registered = exports['feather-core']:RegisterRPC(name, function(params, respond, src)
        local called, problem = xpcall(handler, debug.traceback, params or {}, respond, src)
        if not called then
            print(('[bcc-doorlocks] rpc %s failed: %s'):format(name, tostring(problem)))
            respond(false)
        end
    end, options or { windowMs = 1000, maxCalls = 10, maxPayloadBytes = 8192, requireCharacter = true })
    if registered ~= true then
        print(('[bcc-doorlocks] rpc registration failed: %s'):format(name))
    end
end

-- Notifications ----------------------------------------------------------------

function NotifyClient(src, message, duration)
    if not src or tonumber(src) == 0 then return end
    local result = exports['feather-core']:SendNotification({
        source = tonumber(src),
        style = 'right',
        message = tostring(message),
        duration = tonumber(duration) or 4000
    })
    if type(result) ~= 'table' or result.ok ~= true then
        DBG:Warning('notification failed: ' .. tostring(type(result) == 'table' and result.code or 'invalid_result'))
    end
end

-- Characters -----------------------------------------------------------------

DoorCharacters = {}

local UUID = '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'

function DoorCharacters.IsUuid(value)
    return type(value) == 'string' and value:match(UUID) ~= nil
end

-- The active character UUID of a connected player, or nil.
function DoorCharacters.Get(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local session = exports['feather-core']:GetSessionContext(src)
    if type(session) ~= 'table' or not session.ok or type(session.value) ~= 'table'
        or not DoorCharacters.IsUuid(session.value.characterId) then
        return nil
    end
    return session.value.characterId:lower()
end

-- Accepts a connected player's server ID or a character UUID and returns the
-- character UUID, or nil. Staff type either one in the menus.
function DoorCharacters.Resolve(value)
    if DoorCharacters.IsUuid(value) then return value:lower() end
    local serverId = tonumber(value)
    if serverId and serverId % 1 == 0 then return DoorCharacters.Get(serverId) end
    return nil
end

-- Domain calls ---------------------------------------------------------------
-- Calls a Feather domain export so the invoking resource is bcc-doorlocks, and
-- turns exceptions or malformed replies into error envelopes.

function Doorlocks.Call(resource, operation, request)
    if GetResourceState(resource) ~= 'started' then
        return Doorlocks.Err('dependency_unavailable', resource .. ' is not started.')
    end
    local called, result = pcall(function()
        local provider = exports[resource]
        return provider[operation](provider, request)
    end)
    if not called or type(result) ~= 'table' or type(result.ok) ~= 'boolean' then
        return Doorlocks.Err('dependency_unavailable', ('%s %s failed.'):format(resource, operation))
    end
    return result
end
