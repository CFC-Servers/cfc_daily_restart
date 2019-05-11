util.AddNetworkString("AlertUsersOfRestart")

local CFCDailyRestart = {}
CFCDailyRestart.desiredRestartTime      = 3                         -- The hour to initiate a restart. Must be between 0-24
CFCDailyRestart.warningTime             = 15                        -- How many minutes players have until restart...
CFCDailyRestart.restartAt               = nil                       -- Time at which the server will restart
CFCDailyRestart.fileName                = "CFC_LastDailyRestart"
CFCDailyRestart.countingDownToRestart   = false
CFCDailyRestart.lastRestart             = file.Read(fileName..".txt", "DATA")

local function CFCDailyRestart:restartServer()
    print("restarting server")
    
    file.Write(fileName..".txt", os.time())

    --local params = {}
    --local headers = {}
    --http.Post("localhost:2327/gmod/restart", params, function() end, function() end, headers)
end

local function CFCDailyRestart:sendAlertToClients(message)
    for k, v in pairs(player.GetHumans()) do
        v:ChatPrint(message)
    end
end

local function CFCDailyRestart:alertClientsOfServerRestart()
    print("Alerting clients of Restart")
    restartAt = os.time() + (warningTime * 60)

    -- TODO: Alert how many seconds left
    -- You'll want a logarithmic-ish function to alert at:
    -- 15 min, 10min, 5min, 4min, 3min,2min,1min,30s,15s,10,9,8.. so on


    sendAlertToClients()

    net.Start("AlertUsersOfRestart")
        net.WriteFloat(restartAt)
    net.Broadcast()
end

--TODO: Create a timer to 

timer.Create("CFC_DailyRestart", 1, 0, function()
    local lastScheduledRestart = CFCDailyRestart.lastRestart

    if not lastScheduledRestart == nil then
        if os.difftime(os.time(), lastScheduledRestart) <= 3600 then return end
    end
    -- if waitingForServerToEmpty then return

    theTime = os.date("*t", os.time())

    -- TODO: Also check each second within 1 hour leading up to the restart time. If the server is empty during this time, issue the restart and ensure we don't try to restart again at the desired time
    --
    -- TODO (Future): Perhaps if there are fewer than N players on the server leading up to the restart time, allow them to vote to restart now and get it out of the way

    if not countingDownToRestart then
        if (theTime.hour == desiredRestartTime) and (theTime.sec <= 30) then
            local plyCount = table.Count(player.GetHumans())

            if plyCount == 0 then
                restartServer()
            end

            -- When the server is not empty..
            -- TODO: Wait up to 45 minutes for players to leave organically
            -- If server still isn't empty by then, countdown restart
            -- You'll probably want to make a new function called waitForServerToEmpty() or something here and make sure the timer isn't triggering in the meantime
            -- You may want to keep a variable called "waitingForServerToEmpty" for this function to look at and no-op if so
            -- When the server is still not empty, you'll need to start the shutdown process. "countingDownToRestart" variable will tell this function not to re-initiate the process
            countingDownToRestart = true
            alertClientsOfServerRestart()
        end

        return
    end
end)
