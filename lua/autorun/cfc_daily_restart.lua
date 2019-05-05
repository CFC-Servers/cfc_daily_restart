if SERVER then
    util.AddNetworkString("AlertUsersOfRestart")
    local desiredRestartTime = 3    -- The hour to initiate a restart. Must be between 0-24
    local warningTime = 15          -- How many minutes players have until restart...
    local restartAt                 -- Time at which the server will restart

    function restartServer()
        print("restarting server")
    end

    function alertClientsOfServerRestart()
        print("Alerting clients of Restart")
        restartAt = os.time() + (warningTime * 60)

        net.Start("AlertUsersOfRestart")
            net.WriteFloat(restartAt)
        net.Broadcast()
    end

    hook.Add("Think", "cfc_restart_think", function()
        theTime = os.date("*t", os.time())

        if (theTime.hour == desiredRestartTime) and (theTime.sec == 0) then
            local plyCount = table.Count(player.GetHumans())

            if plyCount == 0 then
                restartServer()
            else
                alertClientsOfServerRestart()
            end
        end
    end)
end