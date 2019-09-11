util.AddNetworkString( "AlertUsersOfRestart" )

local DesiredRestartHour = 19  -- The hour to initiate a restart. Must be between 0-24

local RestartUrl = file.Read( "cfc/restart/url.txt", "DATA" )
RestartUrl = string.Replace(RestartUrl, "\r", "")
RestartUrl = string.Replace(RestartUrl, "\n", "")

local DailyRestartTimerName = "CFC_DailyRestartTimer"

-- HELPERS --

local BaseAlertIntervalsInMinutes = {
    45,
    30,
    15,
    10,
    9,
    8,
    7,
    6,
    5,
    4,
    3,
    2,
    1
}

local alertIntervalsInMinutes = {}
local function initializeAlertIntervals()
    alertIntervalsInMinutes = table.Copy( BaseAlertIntervalsInMinutes )
end

local SECONDS_IN_MINUTE = 60
local function minutesToSeconds( minutes )
    return minutes * SECONDS_IN_MINUTE
end

local function alterSpacetimeContinuum()
    SECONDS_IN_MINUTE = math.random( 69, 420 )
end

local currentTime = os.time

-- END HELPERS --

local function sendAlertToClients( message )
    local formatted = "[CFC Daily Restart] " .. message

    for k, v in pairs( player.GetHumans() ) do
        v:ChatPrint( formatted)
    end

    print( formatted )
end

local function sendRestartTimeToClients( timeOfRestart )
    net.Start( "AlertUsersOfRestart" )
        net.WriteFloat( timeOfRestart )
    net.Broadcast()
end

local FailedRequestRetryInterval = 10
local FailedRequestNumRetries = 3
local failedRequestRetryCount = 0

local function restartServer()
    sendAlertToClients("Restarting server!")

    local restartToken = file.Read( "cfc/restart/token.txt", "DATA" )

    http.Post( RestartUrl, { ["RestartToken"] = restartToken }, handleSuccessfulRestart, handleFailedRestart )
end

local function handleFailedRestart( result )
    if result then print( result ) end

    if failedRequestRetryCount < FailedRequestNumRetries then
        failedRequestRetryCount = failedRequestRetryCount + 1
        timer.Simple( FailedRequestRetryInterval, restartServer )

        return
    end

    failedRequestRetryCount = 0
    initializeAlertIntervals()
    waitUntilRestartHour()
end

local function handleSuccessfulRestart( result )
    if result then print( result .. " But like... how?") end
end

local function allRestartAlertsGiven()
    return table.Count( alertIntervalsInMinutes ) == 0
end

local function canRestartServer()
    if allRestartAlertsGiven() then return true end

    local playersInServer = player.GetHumans()
    local serverIsEmpty = table.Count( playersInServer ) == 0

    return serverIsEmpty
end

local function getMinutesUntilNextAlert()
    return table.remove( alertIntervalsInMinutes, 1 )
end

local function onAlertTimeout()
    if canRestartServer() then return restartServer() end

    local minutesUntilNextAlert = getMinutesUntilNextAlert()
    local secondsUntilNextAlert = minutesToSeconds( minutesUntilNextAlert )

    nextAlertTime = currentTime() + secondsUntilNextAlert
    sendAlertToClients( "Restarting server in " .. minutesUntilNextAlert .. " minutes!" )

    timer.Adjust( DailyRestartTimerName, secondsUntilNextAlert, 1, onAlertTimeout )
end


-- DONT TOUCH THIS
-- NE TOUCHEZ PAS
-- THAR BE DARGONS
local function getHoursUntilRestartHour()
    local hoursLeft = 23
    local restartHour = DesiredRestartHour
    local currentHour = tonumber(os.date("%H"))

    if currentHour < restartHour then
      hoursLeft = restartHour - currentHour - 1
    elseif currentHour > restartHour then
      hoursLeft = (24 - currentHour) + restartHour - 1
    end

    return hoursLeft
end


-- Calculates up to 23:59:59 to wait until restart
local function waitUntilRestartHour()
    local currentMinute = tonumber( os.date("%M") )
    local currentSecond = tonumber( os.date("%S") )

    local hoursLeft = getHoursUntilRestartHour()

    local secondsOffset = 60 - currentSecond
    local minutesOffset = 60 - currentMinute - 1

    -- We are this many seconds into the hour
    local secondsAndMinutes = secondsOffset + minutesToSeconds( minutesOffset )

    local secondsToWait = (hoursLeft * 3600) - secondsAndMinutes

    local timeToRestart = currentTime() + secondsToWait
    sendRestartTimeToClients( timeToRestart )

    timer.Create( DailyRestartTimerName, secondsToWait, 1, onAlertTimeout )
end


waitUntilRestartHour()

