-- bcc-doorlocks' boundary to the Feather Framework (client side).
-- Keeps the call shapes the existing menus use (DBG, FeatherRPC:Call, Notify)
-- on top of feather-core, feather-notify and feather-toolkit.

local function debugPrinter(color, label)
    return function(first, second)
        if not Config.devMode.active then return end
        local message = first == DBG and second or first
        print(('^%d[bcc-doorlocks %s]^0 %s'):format(color, label, tostring(message)))
    end
end

DBG = {
    Info = debugPrinter(4, 'info'),
    Success = debugPrinter(2, 'ok'),
    Warning = debugPrinter(3, 'warn'),
    Error = debugPrinter(1, 'error')
}

FeatherRPC = {}

-- Returns the server handler's reply, or nil on transport failure.
function FeatherRPC:CallAsync(name, params)
    local result, transportError = exports['feather-core']:CallRPCAsync(name, params or {})
    if result == nil and type(transportError) == 'table' then
        DBG:Error(('rpc %s failed: %s'):format(name, tostring(transportError.code or transportError.message)))
    end
    return result, transportError
end

function FeatherRPC:Call(name, params, callback)
    CreateThread(function()
        local result, extra = self:CallAsync(name, params)
        if callback then callback(result, extra) end
    end)
end

function Notify(message, duration)
    local result = exports['feather-notify']:ShowNotification({
        style = 'right',
        message = tostring(message),
        duration = tonumber(duration) or 4000
    })
    if type(result) ~= 'table' or result.ok ~= true then
        DBG:Warning('notification failed: ' .. (type(result) == 'table' and tostring(result.code) or 'invalid_result'))
    end
end

Toolkit = exports['feather-toolkit']

function DrawText3D(x, y, z, text)
    Toolkit:DrawText3D({ x = x, y = y, z = z, text = text, scale = 0.35, shadow = true })
end

-- Lockpicking needs the configured minigame resource to be running.
function LockpickingAvailable()
    if not Config.LockPicking.allowlockpicking then return false end
    local script = Config.LockPicking.minigameScript == 'rsd_lockpick' and 'rsd_lockpick' or 'bcc-minigames'
    return GetResourceState(script) == 'started'
end
