local PANEL = {}
local COLOR_CFC_BLUE = Color( 42, 47, 74 )

function PANEL:Init()
    self:SetSize( 158, 69 )
    self:SetColor( COLOR_CFC_BLUE )

    local header = vgui.Create( "DPanel", self )
    header:SetColor( COLOR_CFC_BLUE )
    header:SetAlpha( 255 - ( 255 * 0.1 ) ) -- 90%
    header:Dock( TOP )
    header:SetTall( 20 )

    local headerText = vgui.Create( "DLabel", header )
    headerText:SetText( "Restarting in:" )

    local timerText = vgui.Create( "DLabel", self )
    timerText:SetText( "12:00" )
end

vgui.Register( "CFCRestartTimer", PANEL )
