if not ULib then return end

CFCDailyRestart = CFCDailyRestart or {}

CFCUlxCommands = CFCUlxCommands or {}
CFCUlxCommands.stopRestart = {}
local cmd = CFCUlxCommands.stopRestart

local CATEGORY_TYPE = "Utility"

function cmd.tryStop( caller )
    if CLIENT then return end

    if not CFCDailyRestart.softRestartImminent then
        ULib.tsayError( caller, "There is no imminent soft restart!", true )

        return
    end

    CFCDailyRestart.stopSoftRestart( caller, true )
    ulx.fancyLogAdmin( caller, "#A canceled the soft restart" )
end

local stopCommand = ulx.command( CATEGORY_TYPE, "ulx stoprestart", cmd.tryStop, "!stoprestart" )
stopCommand:defaultAccess( ULib.ACCESS_ADMIN )
stopCommand:help( "Stops an imminent soft restart (changelevel) triggered by the daily restart system." )
