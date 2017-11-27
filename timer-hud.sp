#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>
#include <clientprefs>
#include <colourmanip>

#define TOTAL_HUDS 2

#define HUD_NONE		0
#define HUD_CENTRAL		(1 << 0)
#define HUD_SPECLIST	(1 << 1)
#define HUD_BUTTONS		(1 << 2)
#define HUD_TOPLEFT		(1 << 3)
#define HUD_HIDEWEAPONS (1 << 4)

#define HUD_DEFAULT		(HUD_SPECLIST | HUD_CENTRAL | HUD_TOPLEFT)

enum
{
	HUD_Time,
	HUD_Jumps,
	HUD_Strafes,
	HUD_Sync,
	HUD_StrafeTime,
	HUD_WRTime,
	HUD_PBTime,
	HUD_Speed,
	HUD_Style,
	HUD_Rainbow,
	TOTAL_HUD_ITEMS
}

Handle g_hHudSynchronizer;

int		g_RainbowColour[3];
char		g_cRainbowColour[8];
bool		g_bSwapRainbowDirection;
int		g_iCount;

Handle	g_hSelectedHudCookie;
int		g_iSelectedHud[MAXPLAYERS + 1];
Handle	g_hHudSettingsCookie;
int		g_iHudSettings[MAXPLAYERS + 1];

char		g_cHudCache[TOTAL_HUDS][256];
bool		g_bHudItems[TOTAL_HUDS][TOTAL_HUD_ITEMS];
char		g_cHudNames[TOTAL_HUDS][64];
int		g_iTotalHuds;

public Plugin myinfo = 
{
	name = "Slidy's Timer - HUD component",
	author = "SlidyBat",
	description = "HUD component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public void OnPluginStart()
{
	g_hSelectedHudCookie = RegClientCookie( "Timer_HUD_Preset", "Selected HUD preset for Slidy's Timer", CookieAccess_Protected );
	g_hHudSettingsCookie = RegClientCookie( "Timer_HUD_Settings", "Selected HUD settings for Slidy's Timer", CookieAccess_Protected );
	
	RegConsoleCmd( "sm_hud", Command_Hud );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( AreClientCookiesCached( i ) )
		{
			OnClientCookiesCached( i );
		}
	}
}

public void OnMapStart()
{
	if( !LoadHuds() )
	{
		SetFailState( "Failed to find sourcemod/configs/Timer/timer-hud.cfg, make sure it exists and is filled properly." );
	}
	
	// reset rainbow colour
	g_bSwapRainbowDirection = false;
	g_RainbowColour[0] = 255;
	g_RainbowColour[1] = 24;
	g_RainbowColour[2] = 24;
	
	g_hHudSynchronizer = CreateHudSynchronizer();
	
	CreateTimer( 0.1, Timer_DrawHud, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
}

public void OnClientCookiesCached( int client )
{
	char sValue[8];
	
	GetClientCookie( client, g_hSelectedHudCookie, sValue, sizeof( sValue ) );
	g_iSelectedHud[client] = StringToInt( sValue );
	
	GetClientCookie( client, g_hHudSettingsCookie, sValue, sizeof( sValue ) );
	if( strlen( sValue ) == 0 )
	{
		IntToString( HUD_DEFAULT, sValue, sizeof( sValue ) );
		SetClientCookie( client, g_hHudSettingsCookie, sValue );
		g_iHudSettings[client] = HUD_DEFAULT;
	}
	else
	{
		g_iHudSettings[client] = StringToInt( sValue );
	}
}

public Action OnPlayerRunCmd( int client, int& buttons )
{
	if( IsFakeClient( client ) || !IsValidClient( client, true ) || !( g_iHudSettings[client] & HUD_CENTRAL ) )
	{
		return;
	}
	
	int target = GetClientObserverTarget( client );
	
	if( target != client )
	{
		if( IsFakeClient( target ) ) // draw replay bot hud
		{
			// TODO: add replay bot hud
		}
		return;
	}
	
	static char hudtext[256];
	hudtext = g_cHudCache[g_iSelectedHud[client]];
	
	static char buffer[64];
	ZoneType ztType = Timer_GetClientZoneType( client );
	ZoneTrack track = Timer_GetClientZoneTrack( client );
	int style = Timer_GetClientStyle( client );
	float pbtime, wrtime;
	
	if( track > ZT_None )
	{
		pbtime = Timer_GetClientPBTime( client, track, style );
		wrtime = Timer_GetWRTime( track, style );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_Speed] )
	{
		int speed = RoundFloat( GetClientSpeed( client ) );
		IntToString( speed, buffer, sizeof( buffer ) );
		ReplaceString( hudtext, sizeof( hudtext ), "{speed}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_Jumps] )
	{
		int jumps = Timer_GetClientCurrentJumps( client );
		IntToString( jumps, buffer, sizeof( buffer ) );
		ReplaceString( hudtext, sizeof( hudtext ), "{jumps}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_Strafes] )
	{
		int strafes = Timer_GetClientCurrentStrafes( client );
		IntToString( strafes, buffer, sizeof( buffer ) );
		ReplaceString( hudtext, sizeof( hudtext ), "{strafes}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_Sync] )
	{
		float sync = Timer_GetClientCurrentSync( client );
		FormatEx( buffer, sizeof( buffer ), "%.2f", sync );
		ReplaceString( hudtext, sizeof( hudtext ), "{sync}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_StrafeTime] )
	{
		float strafetime = Timer_GetClientCurrentStrafeTime( client );
		FormatEx( buffer, sizeof( buffer ), "%.2f", strafetime );
		ReplaceString( hudtext, sizeof( hudtext ), "{strafetime}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_WRTime] )
	{
		FormatEx( buffer, sizeof( buffer ), "%.2f", wrtime );
		ReplaceString( hudtext, sizeof( hudtext ), "{wrtime}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_PBTime] )
	{
		FormatEx( buffer, sizeof( buffer ), "%.2f", pbtime );
		ReplaceString( hudtext, sizeof( hudtext ), "{pbtime}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_Style] )
	{
		Timer_GetStyleName( style, buffer, sizeof( buffer ) );
		ReplaceString( hudtext, sizeof( hudtext ), "{style}", buffer );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_Rainbow] )
	{
		ReplaceString( hudtext, sizeof( hudtext ), "{rainbow}", g_cRainbowColour );
	}
	
	if( g_bHudItems[g_iSelectedHud[client]][HUD_Time] )
	{
		if( ztType == Zone_Start )
		{
			Timer_GetZoneTrackName( track, buffer, sizeof( buffer ) );
			
			FormatEx( buffer, sizeof( buffer ), "%s Start Zone", buffer );
		}
		else
		{
			TimerStatus ts = Timer_GetClientTimerStatus( client );
			
			switch( ts )
			{
				case TimerStatus_Stopped:
				{
					FormatEx( buffer, sizeof( buffer ), "Time: <font color='#DB1A40'>Stopped</font>\t" );
				}
				case TimerStatus_Paused:
				{
					FormatEx( buffer, sizeof( buffer ), "Time: <font color='#333399'>Paused</font>\t" );
				}
				case TimerStatus_Running:
				{
					float time = Timer_GetClientCurrentTime( client );
					Timer_FormatTime( time, buffer, sizeof( buffer ) );
					
					char sTimeColour[8];
					GetTimeColour( sTimeColour, time, pbtime, wrtime );
					Format( buffer, sizeof( buffer ), "Time: <font color='%s'>%s</font>", sTimeColour, buffer );
				}
			}
		}

		ReplaceString( hudtext, sizeof( hudtext ), "{time}", buffer );
	}
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i == client || !IsClientInGame( i ) || IsFakeClient( i ) || !IsClientObserver( i ) || GetEntPropEnt( i, Prop_Send, "m_hObserverTarget" ) != target )
		{
			continue;
		}
		
		PrintHintText( i, buffer );
	}
	
	PrintHintText( client, hudtext );
}

bool LoadHuds()
{
	g_iTotalHuds = 0;

	// load styles from cfg file
	char path[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, path, sizeof( path ), "configs/Timer/timer-hud.cfg" );
	
	KeyValues kvHud = new KeyValues( "HUDS" );
	if( !kvHud.ImportFromFile( path ) || !kvHud.GotoFirstSubKey() )
	{
		return false;
	}
	
	do
	{
		for( int i = 0; i < TOTAL_HUD_ITEMS; i++ )
		{
			g_bHudItems[g_iTotalHuds][i] = false;
		}
		
		char sFileName[32];
		kvHud.GetSectionName( g_cHudNames[g_iTotalHuds], sizeof( g_cHudNames[] ) );
		kvHud.GetString( "filename", sFileName, sizeof( sFileName ) );
		
		BuildPath( Path_SM, path, sizeof( path ), "configs/Timer/HUD/%s.txt", sFileName );
		File hud = OpenFile( path, "r" );
		hud.ReadString( g_cHudCache[g_iTotalHuds], sizeof( g_cHudCache[] ) );
		hud.Close();
		
		if( StrContains( g_cHudCache[g_iTotalHuds], "{time}" ) )
			g_bHudItems[g_iTotalHuds][HUD_Time] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{jumps}" ) )
			g_bHudItems[g_iTotalHuds][HUD_Jumps] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{strafes}" ) )
			g_bHudItems[g_iTotalHuds][HUD_Strafes] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{sync}" ) )
			g_bHudItems[g_iTotalHuds][HUD_Sync] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{strafetime}" ) )
			g_bHudItems[g_iTotalHuds][HUD_StrafeTime] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{wrtime}" ) )
			g_bHudItems[g_iTotalHuds][HUD_WRTime] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{pbtime}" ) )
			g_bHudItems[g_iTotalHuds][HUD_PBTime] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{speed}" ) )
			g_bHudItems[g_iTotalHuds][HUD_Speed] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{style}" ) )
			g_bHudItems[g_iTotalHuds][HUD_Style] = true;
		if( StrContains( g_cHudCache[g_iTotalHuds], "{rainbow}" ) )
			g_bHudItems[g_iTotalHuds][HUD_Rainbow] = true;
		
		g_iTotalHuds++;
	} while( kvHud.GotoNextKey() );

	delete kvHud;
	
	return true;
}

void SetClientHudPreset( int client, int hud )
{
	char sValue[8];
	IntToString( hud, sValue, sizeof( sValue ) );
	
	SetClientCookie( client, g_hSelectedHudCookie, sValue );
	
	g_iSelectedHud[client] = hud;
}

void SetClientHudSettings( int client, int hud )
{
	char sValue[8];
	IntToString( hud, sValue, sizeof( sValue ) );
	
	SetClientCookie( client, g_hHudSettingsCookie, sValue );
	
	g_iHudSettings[client] = hud;
}

stock void GetTimeColour( char buffer[8], float time, float pbtime, float wrtime )
{
	if( wrtime == 0.0 )
	{
		buffer = "#00FF00";
		return;
	}
	
	int r, g, b;
	float ratio = time / wrtime;

	if( ratio <= 0.5 )
	{
		r = RoundFloat( ratio * 510.0 ); // 2.0 * 255.0
		g = 255;	
	}
	else if( ratio <= 1.0 )
	{
		r = 255;
		g = RoundFloat( 510.0 * (  1 - ratio  ) ); // 
	}
	else
	{
		if( time < pbtime )
		{
			r = 239;
			g = 232;
			b = 98;	
		}
		else
		{
			r = 255;
			g = 255;
			b = 255;
		}
	}

	Format( buffer, 8, "#%02X%02X%02X", r, g, b );
}

public Action Timer_DrawHud( Handle timer )
{
	// update rainbow colour
	if( !g_bSwapRainbowDirection )
	{
		if( g_RainbowColour[0] == 255 && g_RainbowColour[1] != 255 )
			g_RainbowColour[1]++;
		else if( g_RainbowColour[0] != 24 && g_RainbowColour[1] == 255 )
			g_RainbowColour[0]--;
		else if( g_RainbowColour[0] == 24 && g_RainbowColour[1] == 255 )
			g_bSwapRainbowDirection = true;
	}
	else
	{
		if( g_RainbowColour[0] != 255 && g_RainbowColour[1] == 255 )
			g_RainbowColour[0]++;
		else if( g_RainbowColour[0] == 255 && g_RainbowColour[1] != 24 )
			g_RainbowColour[1]--;
		else if( g_RainbowColour[0] == 255 && g_RainbowColour[1] == 24 )
			g_bSwapRainbowDirection = false;
	}
	
	Format( g_cRainbowColour, sizeof( g_cRainbowColour ), "#%02X%02X%02X", g_RainbowColour[0], g_RainbowColour[1], g_RainbowColour[2] );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( !IsClientInGame( i ) )
		{
			continue;
		}
		
		SetEntProp( i, Prop_Data, "m_bDrawViewmodel", ( g_iHudSettings[i] & HUD_HIDEWEAPONS ) ? 0 : 1 );
		
		// speclist
		if( g_iHudSettings[i] & HUD_SPECLIST )
		{
			DrawSpecList( i );
		}
		
		// buttons
		if( g_iHudSettings[i] & HUD_BUTTONS )
		{
			DrawButtonsPanel( i );
		}
		
		// topleft
		if( g_iHudSettings[i] & HUD_TOPLEFT )
		{
			DrawTopLeftOverlay( i );
		}
	}
	
	g_iCount++;
	g_iCount %= 25;
}

void DrawSpecList( int client )
{
	int[] spectators = new int[MaxClients];
	int nSpectators = 0;
	
	int target = GetClientObserverTarget( client );

	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i == client || !IsValidClient( i ) || IsFakeClient( i ) || !IsClientObserver( i ) || GetEntPropEnt( i, Prop_Send, "m_hObserverTarget" ) != target )
		{
			continue;
		}

		int specmode = GetEntProp( i, Prop_Send, "m_iObserverMode" );

		if( specmode >= 3 && specmode <= 5 )
		{
			spectators[nSpectators++] = i;
		}
	}
	
	if( nSpectators > 0 )
	{
		char name[MAX_NAME_LENGTH];
		static char buffer[256];
		
		FormatEx( buffer, sizeof( buffer ), "Spectators (%i):\n", nSpectators );

		for( int i = 0; i < nSpectators; i++ )
		{
			if( i == 7 )
			{
				FormatEx( buffer, sizeof( buffer ), "%s...", buffer );
				break;
			}

			if( GetClientName( spectators[i], name, sizeof( name ) ) )
			{
				FormatEx( buffer, sizeof( buffer ), "%s%s\n", buffer, name );
			}
		}
		
		SetHudTextParams( 0.9, 0.3, 0.1, 255, 255, 255, 255 );
		ShowSyncHudText( client, g_hHudSynchronizer, buffer );
	}
}

void DrawButtonsPanel( int client )
{
	int target = GetClientObserverTarget( client );
	
	if( GetClientMenu( client, null ) == MenuSource_None || GetClientMenu( client, null ) == MenuSource_RawPanel )
	{
		Panel panel = new Panel();
		
		char buffer[128];
		
		int buttons = GetClientButtons( target );
		FormatEx( buffer, sizeof( buffer ), "[%s]\n    %s\n%s   %s   %s", ( buttons & IN_DUCK ) > 0 ? "DUCK":"     ", ( buttons & IN_FORWARD ) > 0? "W":"-", ( buttons & IN_MOVELEFT ) > 0? "A":"-", ( buttons & IN_BACK ) > 0? "S":"-", ( buttons & IN_MOVERIGHT ) > 0? "D":"-" );
		
		panel.DrawItem( buffer, ITEMDRAW_RAWLINE );
		
		panel.Send( client, PanelHandler_Nothing, 1 );
		
		delete panel;
	}
}

void DrawTopLeftOverlay( int client )
{
	if( g_iCount % 25 != 0 ) // delay it to run every 2.5s to avoid flicker
	{
		return;
	}
	
	int target = GetClientObserverTarget( client );
	ZoneTrack track = Timer_GetClientZoneTrack( target );
	
	if( track == ZT_None )
	{
		return;
	}
	
	int style = Timer_GetClientStyle( target );
	
	float wrtime = Timer_GetWRTime( track, style );

	if( wrtime != 0.0 )
	{
		char sWRTime[16];
		Timer_FormatTime( wrtime, sWRTime, sizeof( sWRTime ) );

		char sWRName[MAX_NAME_LENGTH];
		Timer_GetWRName( track, style, sWRName, sizeof( sWRName ) );

		float pbtime = Timer_GetClientPBTime( client, track, style );

		char sTopLeft[64];

		if( pbtime != 0.0 )
		{
			char sPBTime[16];
			Timer_FormatTime( pbtime, sPBTime, sizeof( sPBTime ) );
			
			FormatEx(sTopLeft, 64, "WR: %s (%s)\nPB: %s (#%i)", sWRTime, sWRName, sPBTime, Timer_GetClientRank( target, track, style ) );
		}
		else
		{
			FormatEx(sTopLeft, 64, "WR: %s (%s)", sWRTime, sWRName);
		}

		SetHudTextParams( 0.01, 0.01, 2.5, 255, 255, 255, 255 );
		ShowSyncHudText( client, g_hHudSynchronizer, sTopLeft );
	}
}

public int PanelHandler_Nothing( Menu menu, MenuAction action, int param1, int param2 )
{
	return 0;
}

void OpenHudSettingsMenu( int client )
{
	Menu menu = new Menu( HudSettings_Handler );
	menu.SetTitle( "HUD Settings\n \n" );
	
	char buffer[64];
	
	Format( buffer, sizeof( buffer ), "Central HUD Preset: %s\n \n", g_cHudNames[g_iSelectedHud[client]] );
	menu.AddItem( "preset", buffer );
	
	Format( buffer, sizeof( buffer ), "Central HUD: %s", ( g_iHudSettings[client] & HUD_CENTRAL ) ? "Enabled" : "Disabled" );
	menu.AddItem( "central", buffer );
	
	Format( buffer, sizeof( buffer ), "Spectator List: %s", ( g_iHudSettings[client] & HUD_SPECLIST ) ? "Enabled" : "Disabled" );
	menu.AddItem( "speclist", buffer );
	
	Format( buffer, sizeof( buffer ), "Buttons Panel: %s", ( g_iHudSettings[client] & HUD_BUTTONS ) ? "Enabled" : "Disabled" );
	menu.AddItem( "buttons", buffer );
	
	Format( buffer, sizeof( buffer ), "Top Left Overlay: %s", ( g_iHudSettings[client] & HUD_TOPLEFT ) ? "Enabled" : "Disabled" );
	menu.AddItem( "topleft", buffer );
	
	Format( buffer, sizeof( buffer ), "Hide Weapons: %s", ( g_iHudSettings[client] & HUD_HIDEWEAPONS ) ? "Enabled" : "Disabled" );
	menu.AddItem( "hidewep", buffer );
	
	menu.Display( client, 20 );
}

public int HudSettings_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		if( param2 == 0 )
		{
			if( ++g_iSelectedHud[param1] == g_iTotalHuds )
			{
				g_iSelectedHud[param1] = 0;
			}
			
			SetClientHudPreset( param1, g_iSelectedHud[param1] );
		}
		else
		{
			int setting = 1 << ( param2 - 1 );
			g_iHudSettings[param1] ^= setting;
			
			SetClientHudSettings( param1, g_iHudSettings[param1] );
		}
		
		OpenHudSettingsMenu( param1 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

public Action Command_Hud( int client, int args )
{
	OpenHudSettingsMenu( client );
	
	return Plugin_Handled;
}