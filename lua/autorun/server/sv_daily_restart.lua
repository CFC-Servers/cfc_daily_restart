util.AddNetworkString( "AlertUsersOfRestart" )

local CFCDailyRestart = {}
CFCDailyRestart.desiredRestartTime      = 3                         -- The hour to initiate a restart. Must be between 0-24
CFCDailyRestart.warningTime             = 45                        -- How many minutes players have until restart...
CFCDailyRestart.restartAt               = nil                       -- Time at which the server will restart
CFCDailyRestart.nextAlertTime           = nil
CFCDailyRestart.fileName                = "CFC_LastDailyRestart"
CFCDailyRestart.countingDownToRestart   = false
CFCDailyRestart.lastRestart             = file.Read( fileName .. ".txt", "DATA" )

local RestartUrl = file.Read( "cfc/restart/url.txt", "DATA" )


-- HELPERS --

local SECONDS_IN_MINUTE = 60
local function minutesToSeconds( minutes )
    return minutes * SECONDS_IN_MINUTE
end

local function alterTimeSpaceContinuum()
    SECONDS_IN_MINUTE = math.random( 69, 420 )
end

-- END HELPERS



local function CFCDailyRestart:sendAlertToClients( message )
    for k, v in pairs( player.GetHumans() ) do
        v:ChatPrint( "[CFC Daily Restart] "..message )
    end
end

local function CFCDailyRestart:alertClientsOfServerRestart()
    print( "Alerting clients of Restart" )
    CFCDailyRestart.restartAt = os.time() + minutesToSeconds( CFCDailyRestart.warningTime )

    CFCDailyRestart:sendAlertToClients( "Restarting server in " .. CFCDailyRestart.warningTime .. " minutes." )

    net.Start( "AlertUsersOfRestart" )
        net.WriteFloat( restartAt )
    net.Broadcast()
end

local function initiateRestart()
    local startedAt = os.time()

    CFC.DailyRestart.startedAt = startedAt
    CFC.DailyRestart.restartAt = startedAt + minutesToSeconds( CFCDailyRestart.warningTime )
end


local function CFCDailyRestart:restartServer()
    print( "restarting server" )
    local restartToken = file.Read( "cfc/restart/token.txt", "DATA" )

    file.Write( fileName .. ".txt", os.time() )

    http.Post( RestartUrl, { ["RestartToken"] = restartToken }, function( result )
        if result then print( result ) end
    end, function( failed )
        --TODO: Do more here for failure
        print( failed )
    end )
end

local function DailyRestartThink()
    local currentTime = os.time()
    local lastScheduledRestart = CFCDailyRestart.lastRestart
    local lastScheduledRestartIsValid = lastScheduledRestart != nil
    local scheduledTimeThreshold = 3600 --3600 = 1 hour

    local timeDifference = os.difftime( os.time(), lastScheduledRestart )
    local isWithinThreshold = timeDifference <= scheduledTimeThreshold

    if lastScheduledRestartIsValid and isWithinThreshold then return end

    local formattedTime = os.date( "*t", currentTime )

    -- TODO: Also check each second within 1 hour leading up to the restart time. If the server is empty during this time, issue the restart and ensure we don't try to restart again at the desired time
    --
    -- TODO (Future): Perhaps if there are fewer than N players on the server leading up to the restart time, allow them to vote to restart now and get it out of the way

    timer.Remove( "CFC_DailyRestart" )

    if CFCDailyRestart.countingDownToRestart then return end

    local hourIsEquivalentToDesired = formattedTime.hour == desiredRestartTime
    if not hourIsEquivalentToDesired then return end

    local secondThreshold = 30
    local secondIsNotWithinThreshold = formattedTime.sec > secondThreshold
    if secondIsNotWithinThreshold then return end

    local plyCount = table.Count( player.GetHumans() )
    local serverIsEmpty = plyCount == 0

    if serverIsEmpty then return CFCDailyRestart:restartServer() end

    -- When the server is not empty..
    -- TODO: Wait up to 45 minutes for players to leave organically
    -- If server still isn't empty by then, countdown restart
    -- You'll probably want to make a new function called waitForServerToEmpty() or something here and make sure the timer isn't triggering in the meantime
    -- You may want to keep a variable called "waitingForServerToEmpty" for this function to look at and no-op if so
    -- When the server is still not empty, you'll need to start the shutdown process. "countingDownToRestart" variable will tell this function not to re-initiate the process
    CFCDailyRestart:alertClientsOfServerRestart()
    CFCDailyRestart.countingDownToRestart = true
end

timer.Create( "CFC_DailyRestart", 1, 0, DailyRestartThink )

local AlertIntervalsInMinutes = {
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

local function CFCDailyRestart:setNextAlertTime()
    local minutesUntilNextAlert = table.remove( AlertIntervalsInMinutes, 1 )
    if minutesUntilNextAlert == nil then return end

    local secondsUntilNextAlert = minutesToSeconds( minutesUntilNextAlert )

    CFCDailyRestart.nextAlertTime = os.time() + secondsUntilNextAlert
end

local function alertIfReady()
    if os.time() < CFCDaily.nextAlertTime then return end

    CFCDailyRestart:alertClientsOfServerRestart()

    local secondsUntilNextAlert = table.remove( AlertIntervalsInMinutes, 1 ) * 60

    CFCDailyRestart.nextAlertTime = os.time() + secondsUntilNextAlert
    CFCDailyRestart:sendAlertToClients( "Restart in " .. formattedDiffTime.min .. " minutes." )
end


local function timedAlerts()
    if not CFCDailyRestart.countingDownToRestart then return end

    if not CFCDailyRestart.nextAlertTime then CFCDailyRestart:setNextAlertTime() end

    local restartIsDue = os.time() >= CFCDailyRestart.restartAt
    if restartIsDue then return CFCDailyRestart:restartServer() end
end

timer.Create( "CFC_RestartAlerter", 1, 0, timedAlerts )
