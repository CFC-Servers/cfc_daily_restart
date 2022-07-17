local hudElement

local function createHUDElement( seconds )
    hudElement = vgui.Create( "CFCRestartTimer" )
    hudElement.restartTime = seconds
end

local function destroyHUDElement()
    hudElement:Destroy()
end

net.Receive( "AlertUsersOfRestart", function( len )
    local restartTime = net.ReadFloat()

    createHUDElement( restartTime )
end )

net.Receive( "RestartCreateHUDElement", function( len )
    local restartTime = net.ReadFloat()

    createHUDElement( restartTime )
end )

net.Receive( "RestartDestroyHUDElement", function( len )
    destroyHUDElement()
end )
