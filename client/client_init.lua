-- Menus run on feather-menu-v2 through the local compatibility layer.
FeatherMenu = FeatherMenuV2Compat

-- The bcc-minigames lockpick is optional: it is loaded only while that resource runs.
function GetMiniGame()
    if GetResourceState('bcc-minigames') ~= 'started' then return nil end
    local ok, api = pcall(function() return exports['bcc-minigames'].initiate() end)
    return ok and api or nil
end

-- Initialize random seed for better math.random usage
math.randomseed(GetGameTimer() + GetRandomIntInRange(1, 1000))
