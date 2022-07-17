local PANEL = {}

surface.CreateFont( "BigTime", {
    font = "Arial",
    extended = false,
    size = 50,
} )

function PANEL:formatTime()
    local restartTime = math.Clamp( self.restartTime - CurTime(), self.restartTime, 0 )

    local time = string.FormattedTime( restartTime )
    local m = time.m
    local s = time.s

    if m < 10 then
        m = "0" .. time.m
    end

    if s < 10 then
        s = "0" .. time.s
    end

    return m .. ":" .. s
end

function PANEL:Init()
    self:SetSize( 158, 69 )
    self:SetPos( 50, ScrH() / 2 )

    local header = vgui.Create( "DPanel", self )
    header:Dock( TOP )
    header:SetTall( 20 )

    function header:Paint( w, h )
        surface.SetDrawColor( 42, 47, 74 )
        surface.DrawRect( 0, 0, w, h )
    end

    self.headerText = vgui.Create( "DLabel", header )
    self.headerText:SetText( "Restarting in:" )
    self.headerText:Dock( FILL )
    self.headerText:DockMargin( 5, 0, 5, 0 )

    local fill = vgui.Create( "DPanel", self )
    fill:Dock( FILL )

    function fill:Paint( w, h )
        local t = self:GetParent():formatTime()
        draw.SimpleText( t, "BigTime", w / 2, h / 2, Color( 255, 255, 255 ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
    end
end

function PANEL:Paint( w, h )
    surface.SetDrawColor( 42, 47, 74, 255 - ( 255 * 0.1 ) )
    surface.DrawRect( 0, 0, w, h )
end

vgui.Register( "CFCRestartTimer", PANEL, "DPanel" )
