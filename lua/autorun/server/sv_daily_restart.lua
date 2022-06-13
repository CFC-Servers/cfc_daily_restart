require( "cfc_restart_lib" )
util.AddNetworkString( "AlertUsersOfRestart" )

CFCDailyRestart = CFCDailyRestart or {}

local Restarter = CFCRestartLib()
local DESIRED_RESTART_HOUR = 6 -- The hour to initiate a restart. Must be between 0-23

local DAILY_RESTART_TIMER_NAME = "CFC_DailyRestartTimer"
local SOFT_RESTART_TIMER_NAME = "CFC_SoftRestartTimer"
local ALERT_NOTIFICATION_NAME = "CFC_DailyRestartAlert"
local ALERT_NOTIFICATION_ADMIN_NAME = "CFC_DailyRestartAlertAdmin"

-- DISABLE THIS IF NOT IN TESTING
local TESTING_BOOLEAN = false

local SOFT_RESTART_STOP_COMMAND = "!stoprestart"
local MINIMUM_HOURS_BEFORE_RESTART = 3
local RESTART_BUFFER = 5 -- Will only trigger a soft restart if it isn't scheduled to be within this many hours of the hard restart
local SOFT_RESTART_WINDOWS = { -- { X, Y } = At X hours since game start, a changelevel will occur if there are no more than Y players
    {
        timeSinceStart = 4,
        playerMax = 4,
        skippable = true
    },
    {
        timeSinceStart = 5,
        playerMax = 4,
        skippable = true
    },
    {
        timeSinceStart = 6,
        playerMax = 8,
        skippable = true
    },
    {
        timeSinceStart = 7,
        playerMax = 16,
        skippable = true
    },
    {
        timeSinceStart = 8,
        playerMax = 10000,
        skippable = false
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

local BASE_ALERT_INTERVALS_IN_SECONDS = {
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

local ALERT_NOTIFICATION_COLOR = Color( 255, 255, 255, 255 )
local ALERT_NOTIFICATION_DISCARD_COLOR = Color( 230, 153, 58, 255 )
local ALERT_NOTIFICATION_STOP_COLOR = Color( 41, 183, 185, 255 )
local ALERT_INTERVALS_IMPORTANT = { -- { X, Y } = Alerts at time X will be accompanied by a CFC Notification which displays for Y seconds
    {
        1800, -- 30 minutes
        10
    },
    {
        900,  -- 15 minutes
        10
    },
    {
        600,  -- 10 minutes
        10
    },
    {
        300,  -- 5 minutes
        15
    },
    {
        60,   -- 1 minute
        15
    },
    {
        30, -- 30 seconds
        15
    },
}

DAILY_RESTART_TESTS = {}

TEST_ALERT_INTERVALS_IN_SECONDS = {
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
    local ALERT_INTERVALS_IMPORTANT_REFORMATTED = {}

    for _, interval in pairs( ALERT_INTERVALS_IMPORTANT ) do
        ALERT_INTERVALS_IMPORTANT_REFORMATTED[interval[1]] = interval[2]
    end

    ALERT_INTERVALS_IMPORTANT = ALERT_INTERVALS_IMPORTANT_REFORMATTED
end

local AlertDeltas = {}
local alertIntervalsInSeconds = {}
local currentSoftRestartWindow = 1
CFCDailyRestart.softRestartImminent = false
CFCDailyRestart.softRestartSkippable = true
CFCDailyRestart.numSoftStops = CFCDailyRestart.numSoftStops or 0

ProtectedCall( function()
    require( "mixpanel" )
end )

local webhooker
if file.Exists( "includes/modules/webhooker_interface.lua", "LUA" ) then
    require( "webhooker_interface" )
    webhooker = WebhookerInterface()
end

local function logWebhook( str )
    local tbl = {
        source = "sv_daily_restart",
        text = str or nil
    }

    if not webhooker then
        PrintTable( tbl )
        return
    end

    webhooker:send( "testing-endpoint", tbl )
end

local function mixpanelTrackEvent( eventName, data, reliable )
    if not Mixpanel then return end
    Mixpanel:TrackEvent( eventName, data, reliable )
end

local function mixpanelTrackPlyEvent( eventName, ply, data, reliable )
    if not Mixpanel then return end
    Mixpanel:TrackPlyEvent( eventName, ply, data, reliable )
end

local function initializeAlertIntervals()
    if TESTING_BOOLEAN then
        alertIntervalsInSeconds = table.Copy( TEST_ALERT_INTERVALS_IN_SECONDS )
    else
        alertIntervalsInSeconds = table.Copy( BASE_ALERT_INTERVALS_IN_SECONDS )
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

local currentTime = os.time

-- END HELPERS --


local function sendAlertToClients( message, plys )
    local formatted = "[CFC Daily Restart] " .. message

    for _, v in pairs( plys or player.GetHumans() ) do
        v:ChatPrint( formatted )
    end

    print( formatted )
end

local function canStopSoftRestart( ply )
    if not CFCDailyRestart.softRestartSkippable then return end
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

local function newAlertNotification( notifID, msg, duration )
    local notif = CFCNotifications.new( notifID, "Buttons", true )

    notif:SetTitle( "CFC Daily Restart" )
    notif:SetPriority( CFCNotifications.PRIORITY_MAX )
    notif:SetDisplayTime( duration or 10 )
    notif:SetText( msg )
    notif:SetTextColor( ALERT_NOTIFICATION_COLOR )
    notif:SetCloseable( true )
    notif:SetIgnoreable( false )
    notif:SetTimed( true )

    return notif
end

local function tryAlertNotification( secondsUntilNextRestart, msg, msgAdmin, noAccess, hasAccess )
    if not CFCNotifications then return end

    local notificationAlertDuration = ALERT_INTERVALS_IMPORTANT[secondsUntilNextRestart]

    if notificationAlertDuration then
        local notif = newAlertNotification( ALERT_NOTIFICATION_NAME, msg, notificationAlertDuration )

        notif:AddButton( "Discard", ALERT_NOTIFICATION_DISCARD_COLOR )
        notif:Send( noAccess or player.GetHumans() )

        if not msgAdmin then return end

        local notifAdmin = newAlertNotification( ALERT_NOTIFICATION_ADMIN_NAME, msgAdmin, notificationAlertDuration )

        notifAdmin:AddButton( "Discard", ALERT_NOTIFICATION_DISCARD_COLOR, false )

        if CFCDailyRestart.softRestartSkippable then
            notifAdmin:AddButton( "Stop the Restart", ALERT_NOTIFICATION_STOP_COLOR, true )

            function notifAdmin:OnButtonPressed( ply, skip )
                if not skip then return end

                CFCDailyRestart.stopSoftRestart( ply )
            end
        end

        notifAdmin:Send( hasAccess or player.GetHumans() )
    end
end

local function restartServer()
    logWebhook( "Server hard restarting" )
    if not TESTING_BOOLEAN then
        sendAlertToClients( "Restarting server!" )
        Restarter:restart()
    else
        sendAlertToClients( "Restarting server ( not really, this is a test )!" )
    end
end

local function softRestartServer()
    logWebhook( "Server soft restarting" )
    if not TESTING_BOOLEAN then
        sendAlertToClients( "Soft-restarting server!" )

        hook.Run( "CFC_DailyRestart_SoftRestart" )

        game.ConsoleCommand( "changelevel " .. game.GetMap() ..  "\n" )
    else
        sendAlertToClients( "Soft-restarting server ( not really, this is a test )!" )
    end
end

DAILY_RESTART_TESTS.restartServer = function()
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

    local playersInServer = #player.GetHumans()

    return playersInServer == 0
end

local function canSoftRestartServer()
    local softRestartTime = SOFT_RESTART_WINDOWS[currentSoftRestartWindow].timeSinceStart * SECONDS_IN_HOUR

    if timeSinceStart() < softRestartTime then return false end
    if allRestartAlertsGiven() then return true end

    local playersInServer = #player.GetHumans()

    return playersInServer == 0
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

    timer.Adjust( DAILY_RESTART_TIMER_NAME, secondsUntilNextAlert, 1, onHardAlertTimeout )
end

local function onSoftAlertTimeout()
    if canSoftRestartServer() then return softRestartServer() end

    local secondsUntilNextAlert, secondsUntilNextRestart = getSecondsUntilAlertAndRestart()
    if secondsUntilNextAlert == nil or secondsUntilNextRestart == nil then return softRestartServer() end

    local msg = formatAlertMessage( "Soft-restarting server in ", secondsUntilNextRestart )
    local notifMsg = msg .. "\nYou will remain connected and your props will be saved.\nThe restart will not take long."
    local notifMsgAdmin
    local noAccess, hasAccess = splitPlayersBySoftRestartStopAccess()

    sendAlertToClients( msg, noAccess )

    if CFCDailyRestart.softRestartSkippable then
        msg = msg .. " You can stop the changelevel with " .. SOFT_RESTART_STOP_COMMAND
        notifMsgAdmin = notifMsg .. "\nYou can stop the changelevel with " .. SOFT_RESTART_STOP_COMMAND
    else
        msg = msg .. " **This changelevel cannot be stopped.**"
        notifMsgAdmin = notifMsg .. "\n**This changelevel cannot be stopped.**"
    end

    sendAlertToClients( msg, hasAccess )
    tryAlertNotification( secondsUntilNextRestart, notifMsg, notifMsgAdmin, noAccess, hasAccess )

    timer.Create( SOFT_RESTART_TIMER_NAME, secondsUntilNextAlert, 1, onSoftAlertTimeout )
end

local function getHoursUntilRestartHour()
    local hoursLeft = 24
    local restartHour = DESIRED_RESTART_HOUR
    local currentHour = tonumber( os.date( "%H" ) )

    if currentHour < restartHour then
        hoursLeft = restartHour - currentHour
    elseif currentHour > restartHour then
        hoursLeft = ( 24 - currentHour ) + restartHour
    end

    return hoursLeft
end

local function createRestartTimer( seconds )
    timer.Create( DAILY_RESTART_TIMER_NAME, seconds, 1, onHardAlertTimeout )
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

    if os.time() + timeUntilNextWindowAlert < EARLIEST_RESTART_TIME then return end -- Too early to restart
    if timeUntilNextWindowAlert + RESTART_BUFFER > getHoursUntilRestartHour() * SECONDS_IN_HOUR then return end -- Hard restart is too close

    timer.Create( SOFT_RESTART_TIMER_NAME, timeUntilNextWindowAlert, 1, function()
        if #player.GetHumans() <= window.playerMax then
            CFCDailyRestart.softRestartImminent = true
            CFCDailyRestart.softRestartSkippable = window.skippable
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
    LARGEST_ALERT_INTERVAL = TEST_ALERT_INTERVALS_IN_SECONDS[1]

    test_waitUntilRestartHour()
else
    LARGEST_ALERT_INTERVAL = BASE_ALERT_INTERVALS_IN_SECONDS[1]

    waitUntilRestartHour()
    waitForNextSoftRestartWindow()
end


DAILY_RESTART_TESTS.renew = function()
    test_waitUntilRestartHour()
end

function CFCDailyRestart.stopSoftRestart( ply, hidePrint )
    CFCDailyRestart.softRestartImminent = false
    timer.Remove( SOFT_RESTART_TIMER_NAME )
    initializeAlertIntervals()

    if currentSoftRestartWindow < #SOFT_RESTART_WINDOWS then
        currentSoftRestartWindow = currentSoftRestartWindow + 1
        waitForNextSoftRestartWindow()
    end

    if CFCNotifications then
        local notif = CFCNotifications.get( ALERT_NOTIFICATION_NAME )
        local notifAdmin = CFCNotifications.get( ALERT_NOTIFICATION_ADMIN_NAME )

        if notif then
            notif:Remove()
        end

        if notifAdmin then
            notifAdmin:Remove()
        end
    end

    local stopCount = CFCDailyRestart.numSoftStops + 1
    local mixPanelData = { playerCount = #player.GetHumans(), amountOfStops = stopCount }
    CFCDailyRestart.numSoftStops = stopCount

    if IsValid( ply ) and ply:IsPlayer() then
        mixpanelTrackPlyEvent( "Ply stopped soft restart", ply, mixPanelData )
    else
        mixpanelTrackEvent( "Soft restart stopped", mixPanelData )
    end

    if hidePrint then return end

    sendAlertToClients( "The soft restart has been canceled." )
end

if ULib then return end

hook.Add( "PlayerSay", "CFC_DailyRestart_StopSoftRestart", function( ply, msg )
    if msg ~= SOFT_RESTART_STOP_COMMAND then return end
    if not IsValid( ply ) then return end

    local canStop = canStopSoftRestart( ply )

    if canStop == nil then
        ply:ChatPrint( "This soft restart is unstoppable!" )

        return ""
    elseif not canStop then
        ply:ChatPrint( "You do not have access to that command!" )

        return ""
    end

    if not CFCDailyRestart.softRestartImminent then
        ply:ChatPrint( "There is no imminent soft restart!" )

        return ""
    end

    CFCDailyRestart.stopSoftRestart( ply )
end )
