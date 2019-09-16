util.AddNetworkString( "AlertUsersOfRestart" )

local DesiredRestartHour = 3 -- The hour to initiate a restart. Must be between 0-24

local RestartUrl = file.Read( "cfc/restart/url.txt", "DATA" )
RestartUrl = string.Replace(RestartUrl, "\r", "")
RestartUrl = string.Replace(RestartUrl, "\n", "")

local DailyRestartTimerName = "CFC_DailyRestartTimer"

-- DISABLE THIS IF NOT IN TESTING
local TESTING_BOOLEAN = true

local SERVER_START_TIME = os.time()
local MINIMUM_HOURS_BEFORE_RESTART = 3
local MINIMUM_SECONDS_BEFORE_RESTART = MINIMUM_HOURS_BEFORE_RESTART * 3600
local EARLIEST_RESTART_TIME = SERVER_START_TIME + MINIMUM_SECONDS_BEFORE_RESTART

-- HELPERS --

local BaseAlertIntervalsInSeconds = {
    3600, -- 60 minutes
    2700, -- 45 minutes 
    1800, -- 30 minutes
    900,  -- 15 minutes
    600,  -- 10 minutes
    540,  -- 9 minutes
    480,  -- 8 minutes
    420,  -- 7 minutes
    360,  -- 6 minutes
    300,  -- 5 minutes
    240,  -- 4 minutes
    180,  -- 3 minutes
    120,  -- 2 minutes
    60,   -- 1 minute
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

DailyRestartTests = {}

TestAlertIntervalsInSeconds = {
    60,
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

local AlertDeltas = {}

local alertIntervalsInSeconds = {}
local function initializeAlertIntervals()
    if TESTING_BOOLEAN then
        alertIntervalsInSeconds = table.Copy( TestAlertIntervalsInSeconds )
    else
        alertIntervalsInSeconds = table.Copy( BaseAlertIntervalsInSeconds )
    end

    -- Fill AlertDeltas with the diffs between times
    for i=2, #alertIntervalsInSeconds do
        table.insert( AlertDeltas, alertIntervalsInSeconds[i-1] - alertIntervalsInSeconds[i] )
    end

    table.insert( AlertDeltas, alertIntervalsInSeconds[#alertIntervalsInSeconds] )
end

local SECONDS_IN_MINUTE = 60
local function secondsToMinutes( minutes )
      return math.floor( minutes / SECONDS_IN_MINUTE )
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

local function handleFailedRestart( result )
    if result then print( result ) end
    -- TODO WEBHOOK
end

local function handleSuccessfulRestart( result )
    if result then print( result ) end
    --if result then print( result .. " But like... how?") end
end

local function restartServer()

    local restartToken = file.Read( "cfc/restart/token.txt", "DATA" )

    if not TESTING_BOOLEAN then
        sendAlertToClients("Restarting server!")
        http.Post( RestartUrl, { ["RestartToken"] = restartToken }, handleSuccessfulRestart, handleFailedRestart )
    else
        sendAlertToClients("Restarting server (not really, this is a test)!")
    end
end

DailyRestartTests.restartServer = function()
    restartServer()
end

local function allRestartAlertsGiven()
    return table.Count( alertIntervalsInSeconds ) == 0
end

local function canRestartServer()
    if os.time() < EARLIEST_RESTART_TIME then return false end
    if allRestartAlertsGiven() then return true end

    local playersInServer = player.GetHumans()
    local serverIsEmpty = table.Count( playersInServer ) == 0

    return serverIsEmpty
end

local function getSecondsUntilAlertAndRestart()
    return table.remove( AlertDeltas, 1 ), table.remove( alertIntervalsInSeconds, 1 )
end

local function onAlertTimeout()
    if canRestartServer() then return restartServer() end

    local secondsUntilNextAlert, secondsUntilNextRestart = getSecondsUntilAlertAndRestart()
    if secondsUntilNextAlert == nil or secondsUntilNextRestart == nil then return restartServer() end

    local msg = "Restarting server in "
    
    local minutesUntilNextRestart = secondsToMinutes( secondsUntilNextRestart )
    if ( minutesUntilNextRestart >= 1 ) then
        msg = msg .. minutesUntilNextRestart .. " minute"
        if ( minutesUntilNextRestart > 1 ) then msg = msg .. "s" end
    else
        msg = msg .. secondsUntilNextRestart .. " second"
        if ( secondsUntilNextRestart > 1 ) then msg = msg .. "s" end
    end    
    msg = msg .. "!"

    sendAlertToClients( msg )

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


local SECONDS_IN_HOUR = 3600

local function createRestartTimer(seconds)
    timer.Create( DailyRestartTimerName, seconds, 1, onAlertTimeout )
end

-- Calculates up to 23:59:59 to wait until restart
local function waitUntilRestartHour()
    local currentMinute = tonumber( os.date("%M") )
    local currentSecond = tonumber( os.date("%S") )

    local hoursLeft = getHoursUntilRestartHour()

    local secondsOffset = 60 - currentSecond
    local minutesOffset = 60 - currentMinute - 1

    -- We are this many seconds into the hour
    local secondsAndMinutes = secondsOffset + ( minutesOffset * 60 )

    local secondsToWait = (hoursLeft * SECONDS_IN_MINUTE) + secondsAndMinutes

    local timeToRestart = currentTime() + secondsToWait
    sendRestartTimeToClients( timeToRestart )

    createRestartTimer( secondsToWait )
end

local function test_waitUntilRestartHour()
    EARLIEST_RESTART_TIME = os.time() + 100
    createRestartTimer(0)
end

initializeAlertIntervals()
if TESTING_BOOLEAN then
    test_waitUntilRestartHour()
else
    waitUntilRestartHour()
end


DailyRestartTests.renew = function()
    test_waitUntilRestartHour()   
end
