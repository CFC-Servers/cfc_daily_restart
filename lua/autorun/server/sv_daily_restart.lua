require( "cfc_restart_lib" )
util.AddNetworkString( "AlertUsersOfRestart" )

CFCDailyRestart = CFCDailyRestart or {}

local Restarter = CFCRestartLib()
local DesiredRestartHour = 6 -- The hour to initiate a restart. Must be between 0-24

local DailyRestartTimerName = "CFC_DailyRestartTimer"
local SoftRestartTimerName = "CFC_SoftRestartTimer"
local AlertNotificationName = "CFC_DailyRestartAlert"

-- DISABLE THIS IF NOT IN TESTING
local TESTING_BOOLEAN = false

local SOFT_RESTART_STOP_COMMAND = "!stoprestart"
local MINIMUM_HOURS_BEFORE_RESTART = 3
local RESTART_BUFFER = 2 -- Will only trigger a soft restart if it isn't scheduled to be within this many hours of the hard restart
local SOFT_RESTART_WINDOWS = { -- { X, Y } = At X hours since game start, a changelevel will occur if there are no more than Y players
    {
        timeSinceStart = 4,
        playerMax = 4
    },
    {
        timeSinceStart = 4.5,
        playerMax = 4
    },
    {
        timeSinceStart = 5,
        playerMax = 8
    },
    {
        timeSinceStart = 5.5,
        playerMax = 10
    },
    {
        timeSinceStart = 6,
        playerMax = 12
    },
    {
        timeSinceStart = 6.5,
        playerMax = 14
    },
    {
        timeSinceStart = 7,
        playerMax = 20
    },
    {
        timeSinceStart = 7.5,
        playerMax = 24
    },
    {
        timeSinceStart = 8,
        playerMax = 10000
    },
}
local SOFT_RESTART_STOPPER_RANKS = { -- Players who either are superadmins or who have one of these ranks can stop soft restarts
    admin = true,
    superadmin = true,
    owner = true,
}

local SERVER_START_TIME = os.time()
local SECONDS_IN_HOUR = 3600
local MINIMUM_SECONDS_BEFORE_RESTART = MINIMUM_HOURS_BEFORE_RESTART * SECONDS_IN_HOUR
local EARLIEST_RESTART_TIME = SERVER_START_TIME + MINIMUM_SECONDS_BEFORE_RESTART
local LARGEST_ALERT_INTERVAL = 0
RESTART_BUFFER = RESTART_BUFFER * SECONDS_IN_HOUR

-- HELPERS --

local BaseAlertIntervalsInSeconds = {
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

local AlertNotificationColor = Color( 255, 255, 255, 255 )
local AlertNotificationDiscardColor = Color( 230, 153, 58, 255 )
local AlertIntervalsImportant = { -- { X, Y } = Alerts at time X will be accompanied by a CFC Notification which displays for Y seconds
    {
        1800, -- 30 minutes
        120
    },
    {
        900,  -- 15 minutes
        120
    },
    {
        600,  -- 10 minutes
        60
    },
    {
        300,  -- 5 minutes
        60
    },
    {
        60,   -- 1 minute
        60
    },
    {
        30, -- 30 seconds
        30
    },
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

do
    local AlertIntervalsImportantReformatted = {}

    for _, interval in pairs( AlertIntervalsImportant ) do
        AlertIntervalsImportantReformatted[interval[1]] = interval[2]
    end

    AlertIntervalsImportant = AlertIntervalsImportantReformatted
end

local AlertDeltas = {}
local alertIntervalsInSeconds = {}
local currentSoftRestartWindow = 1
CFCDailyRestart.softRestartImminent = false

local function initializeAlertIntervals()
    if TESTING_BOOLEAN then
        alertIntervalsInSeconds = table.Copy( TestAlertIntervalsInSeconds )
    else
        alertIntervalsInSeconds = table.Copy( BaseAlertIntervalsInSeconds )
    end

    AlertDeltas = {}

    -- Fill AlertDeltas with the diffs between times
    for i = 2, #alertIntervalsInSeconds do
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


local function sendAlertToClients( message, plys )
    local formatted = "[CFC Daily Restart] " .. message

    for k, v in pairs( plys or player.GetHumans() ) do
        v:ChatPrint( formatted )
    end

    print( formatted )
end

local function canStopSoftRestart( ply )
    if not IsValid( ply ) then return false end
    if ply:IsSuperAdmin() then return true end

    if ULib then
        if ULib.ucl.query( ply, "ulx stoprestart", true ) then return true end
    else
        if SOFT_RESTART_STOPPER_RANKS[string.lower( ply:GetUserGroup() )] then return true end
    end

    return false
end

local function splitPlayersBySoftRestartStopAccess()
    local noAccess = {}
    local hasAccess = {}
    local plys = player.GetHumans()

    for i = 1, #plys do
        local ply = plys[i]

        if canStopSoftRestart( ply ) then
            table.insert( hasAccess, ply )
        else
            table.insert( noAccess, ply )
        end
    end

    return noAccess, hasAccess
end

local function sendRestartTimeToClients( timeOfRestart )
    net.Start( "AlertUsersOfRestart" )
        net.WriteFloat( timeOfRestart )
    net.Broadcast()
end

local function tryAlertNotification( secondsUntilNextRestart, msg )
    if not CFCNotifications then return end

    local notificationAlertDuration = AlertIntervalsImportant[secondsUntilNextRestart]

    if notificationAlertDuration then
        local notif = CFCNotifications.new( AlertNotificationName, "Buttons", true )

        notif:SetTitle( "CFC Daily Restart" )
        notif:SetPriority( CFCNotifications.PRIORITY_MAX )
        notif:SetDisplayTime( notificationAlertDuration )
        notif:SetText( msg )
        notif:SetTextColor( AlertNotificationColor )
        notif:SetCloseable( true )
        notif:SetIgnoreable( false )
        notif:SetTimed( true )

        notif:AddButton( "Discard", AlertNotificationDiscardColor )

        notif:Send( player.GetHumans() )
    end
end

local function handleFailedRestart( result )
    if result then print( result ) end
    -- TODO WEBHOOK
end

local function handleSuccessfulRestart( result )
    if result then print( result ) end
    -- if result then print( result .. " But like... how?" ) end
end

local function restartServer()
    if not TESTING_BOOLEAN then
        sendAlertToClients( "Restarting server!" )
        Restarter:restart()
    else
        sendAlertToClients( "Restarting server ( not really, this is a test )!" )
    end
end

local function softRestartServer()
    if not TESTING_BOOLEAN then
        sendAlertToClients( "Soft-restarting server!" )

        if CFC_PropRestore then
            CFC_PropRestore.SaveProps()
        end

        game.ConsoleCommand( "changelevel " .. game.GetMap() ..  "\n" )
    else
        sendAlertToClients( "Soft-restarting server ( not really, this is a test )!" )
    end
end

DailyRestartTests.restartServer = function()
    restartServer()
end

local function allRestartAlertsGiven()
    return table.Count( alertIntervalsInSeconds ) == 0
end

local function timeSinceStart()
    return os.time() - SERVER_START_TIME
end

local function canRestartServer()
    if os.time() < EARLIEST_RESTART_TIME then return false end
    if allRestartAlertsGiven() then return true end

    local playersInServer = player.GetHumans()
    local serverIsEmpty = table.Count( playersInServer ) == 0

    return serverIsEmpty
end

local function canSoftRestartServer()
    local softRestartTime = SOFT_RESTART_WINDOWS[currentSoftRestartWindow].timeSinceStart * SECONDS_IN_HOUR

    if timeSinceStart() < softRestartTime then return false end
    if allRestartAlertsGiven() then return true end

    local playersInServer = player.GetHumans()
    local serverIsEmpty = table.Count( playersInServer ) == 0

    return serverIsEmpty
end

local function getSecondsUntilAlertAndRestart()
    return table.remove( AlertDeltas, 1 ), table.remove( alertIntervalsInSeconds, 1 )
end

local function formatAlertMessage( msg, secondsUntilNextRestart )
    local minutesUntilNextRestart = secondsToMinutes( secondsUntilNextRestart )
    if ( minutesUntilNextRestart >= 1 ) then
        msg = msg .. minutesUntilNextRestart .. " minute"
        if ( minutesUntilNextRestart > 1 ) then msg = msg .. "s" end
    else
        msg = msg .. secondsUntilNextRestart .. " second"
        if ( secondsUntilNextRestart > 1 ) then msg = msg .. "s" end
    end

    return msg .. "!"
end

local function onHardAlertTimeout()
    if canRestartServer() then return restartServer() end

    local secondsUntilNextAlert, secondsUntilNextRestart = getSecondsUntilAlertAndRestart()
    if secondsUntilNextAlert == nil or secondsUntilNextRestart == nil then return restartServer() end

    local msg = formatAlertMessage( "Restarting server in ", secondsUntilNextRestart )
    local notifMsg = msg .. "\nThis is a hard restart!\nThe server takes at most 3 minutes to come back online."

    sendAlertToClients( msg )
    tryAlertNotification( secondsUntilNextRestart, notifMsg )

    timer.Adjust( DailyRestartTimerName, secondsUntilNextAlert, 1, onHardAlertTimeout )
end

local function onSoftAlertTimeout()
    if canSoftRestartServer() then return softRestartServer() end

    local secondsUntilNextAlert, secondsUntilNextRestart = getSecondsUntilAlertAndRestart()
    if secondsUntilNextAlert == nil or secondsUntilNextRestart == nil then return softRestartServer() end

    local msg = formatAlertMessage( "Soft-restarting server in ", secondsUntilNextRestart )
    local notifMsg = msg .. "\nYou will remain connected and your props will be saved.\nThe restart will not take long."
    local noAccess, hasAccess = splitPlayersBySoftRestartStopAccess()

    sendAlertToClients( msg, noAccess )
    sendAlertToClients( msg .. " You can stop the changelevel with " .. SOFT_RESTART_STOP_COMMAND, hasAccess )
    tryAlertNotification( secondsUntilNextRestart, notifMsg )

    timer.Create( SoftRestartTimerName, secondsUntilNextAlert, 1, onSoftAlertTimeout )
end

local function getHoursUntilRestartHour()
    local hoursLeft = 24
    local restartHour = DesiredRestartHour
    local currentHour = tonumber( os.date( "%H" ) )

    if currentHour < restartHour then
      hoursLeft = restartHour - currentHour
    elseif currentHour > restartHour then
      hoursLeft = ( 24 - currentHour ) + restartHour
    end

    return hoursLeft
end

local SECONDS_IN_HOUR = 3600

local function createRestartTimer( seconds )
    timer.Create( DailyRestartTimerName, seconds, 1, onHardAlertTimeout )
end

-- Calculates up to 23:59:59 to wait until restart
local function waitUntilRestartHour()
    local currentMinute = tonumber( os.date( "%M" ) )
    local currentSecond = tonumber( os.date( "%S" ) )

    local hoursLeft = getHoursUntilRestartHour()

    local secondsOffset = 60 - currentSecond
    local minutesOffset = 60 - currentMinute - 1

    -- We are this many seconds into the hour
    local secondsAndMinutes = secondsOffset + ( minutesOffset * 60 )

    local secondsToWait = ( hoursLeft * SECONDS_IN_HOUR ) - secondsAndMinutes

    local timeToRestart = currentTime() + secondsToWait
    sendRestartTimeToClients( timeToRestart )

    createRestartTimer( secondsToWait )
end

local function waitForNextSoftRestartWindow()
    local window = SOFT_RESTART_WINDOWS[currentSoftRestartWindow]

    if not window then return end -- Only happens if none of the windows have a huge playerMax to guarantee being ran

    local timeUntilNextWindowAlert = window.timeSinceStart * SECONDS_IN_HOUR - timeSinceStart() - LARGEST_ALERT_INTERVAL

    if os.time() + timeUntilNextWindowAlert + RESTART_BUFFER < EARLIEST_RESTART_TIME then return end -- Hard restart is too close

    timer.Create( SoftRestartTimerName, timeUntilNextWindowAlert, 1, function()
        if #player.GetHumans() <= window.playerMax then
            CFCDailyRestart.softRestartImminent = true
            onSoftAlertTimeout()
        else
            currentSoftRestartWindow = currentSoftRestartWindow + 1
            waitForNextSoftRestartWindow() 
        end
    end )
end

local function test_waitUntilRestartHour()
    EARLIEST_RESTART_TIME = os.time() + 100
    createRestartTimer( 0 )
end

initializeAlertIntervals()
if TESTING_BOOLEAN then
    LARGEST_ALERT_INTERVAL = TestAlertIntervalsInSeconds[1]

    test_waitUntilRestartHour()
else
    LARGEST_ALERT_INTERVAL = BaseAlertIntervalsInSeconds[1]

    waitUntilRestartHour()
    waitForNextSoftRestartWindow()
end


DailyRestartTests.renew = function()
    test_waitUntilRestartHour()
end

function CFCDailyRestart.stopSoftRestart( hidePrint )
    CFCDailyRestart.softRestartImminent = false
    timer.Remove( SoftRestartTimerName )
    initializeAlertIntervals()

    if currentSoftRestartWindow < #SOFT_RESTART_WINDOWS then
        currentSoftRestartWindow = currentSoftRestartWindow + 1
        waitForNextSoftRestartWindow()
    end

    if CFCNotifications then
        local notif = CFCNotifications.get( AlertNotificationName )

        if notif then
            notif:Remove()
        end
    end

    if hidePrint then return end

    sendAlertToClients( "The soft restart has been canceled." )
end

if ULib then return end

hook.Add( "PlayerSay", "CFC_DailyRestart_StopSoftRestart", function( ply, msg )
    if msg ~= SOFT_RESTART_STOP_COMMAND then return end
    if not IsValid( ply ) then return end

    if not canStopSoftRestart( ply ) then
        ply:ChatPrint( "You do not have access to that command!" )
        
        return ""
    end

    if not CFCDailyRestart.softRestartImminent then
        ply:ChatPrint( "There is no imminent soft restart!" )

        return ""
    end

    CFCDailyRestart.stopSoftRestart()
end )
