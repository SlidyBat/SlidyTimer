#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>
#include <clientprefs>

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

enum
{
	HudType_StartZone,
	HudType_Timing,
	HudType_ReplayBot,
	TOTAL_HUD_TYPES
}

float	g_fTickInterval;

bool g_bReplays; // if replays module is loaded

Handle g_hHudSynchronizer;

int		g_RainbowColour[3];
char		g_cRainbowColour[8];
bool		g_bSwapRainbowDirection;
int		g_iCount;

Handle	g_hSelectedHudCookie;
int		g_iSelectedHud[MAXPLAYERS + 1];
Handle	g_hHudSettingsCookie;
int		g_iHudSettings[MAXPLAYERS + 1];

char		g_cHudCache[TOTAL_HUD_TYPES][TOTAL_HUDS][256];
char		g_cHudNames[TOTAL_HUDS][64];
int		g_iTotalHuds;

StringMap	g_smHudElementCallbacks;

typedef HUDElementCB = function void ( int client, char[] output, int maxlen );

#include "timer-hudelements.sp"

public Plugin myinfo = 
{
	name = "Slidy's Timer - HUD component",
	author = "SlidyBat",
	description = "HUD component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	RegPluginLibrary( "timer-hud" );
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_fTickInterval = GetTickInterval();

	g_bReplays = LibraryExists( "timer-replays" );

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
	
	g_smHudElementCallbacks = new StringMap();
	AddHudElement( "time", GetTimeString );
	AddHudElement( "speed", GetSpeedString );
	AddHudElement( "jumps", GetJumpsString );
	AddHudElement( "strafes", GetStrafesString );
	AddHudElement( "sync", GetSyncString );
	AddHudElement( "strafetime", GetStrafeTimeString );
	AddHudElement( "wrtime", GetWRTimeString );
	AddHudElement( "pbtime", GetPBTimeString );
	AddHudElement( "style", GetStyleString );
	AddHudElement( "rainbow", GetRainbowString );
	AddHudElement( "zonetrack", GetZoneTrackString );
	AddHudElement( "zonetype", GetZoneTypeString );
	AddHudElement( "replayname", GetReplayBotNameString );
}

public void OnAllPluginsLoaded()
{
	g_bReplays = LibraryExists( "timer-replays" );
}

public void OnLibraryAdded( const char[] name )
{
	if( StrEqual( name, "timer-replays" ) )
	{
		g_bReplays = true;
	}
}

public void OnLibraryRemoved( const char[] name )
{
	if( StrEqual( name, "timer-replays" ) )
	{
		g_bReplays = false;
	}
}

stock void AddHudElement( const char[] element, HUDElementCB cb )
{
	DataPack pack = new DataPack();
	pack.WriteFunction( cb );
	g_smHudElementCallbacks.SetValue( element, pack );
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
	
	GetClientCookie( client, g_hSelectedHudCookie, sValue, sizeof(sValue) );
	g_iSelectedHud[client] = StringToInt( sValue );
	
	GetClientCookie( client, g_hHudSettingsCookie, sValue, sizeof(sValue) );
	if( strlen( sValue ) == 0 )
	{
		IntToString( HUD_DEFAULT, sValue, sizeof(sValue) );
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
	if( IsFakeClient( client ) || !( g_iHudSettings[client] & HUD_CENTRAL ) )
	{
		return Plugin_Continue;
	}
	
	int target = GetClientObserverTarget( client );
	if( target == -1 )
	{
		return Plugin_Continue;
	}

	int hudtype;
	if( g_bReplays && IsFakeClient( target ) ) // draw replay bot hud
	{
		hudtype = HudType_ReplayBot;
	}
	else
	{
		hudtype = (Timer_GetClientZoneType( client ) == Zone_Start) ? HudType_StartZone : HudType_Timing;
	}

	static char hudtext[256];
	int curHudChar = 0;
	
	bool bStartedElement;
	char element[64];
	int curElementChar = 0;
	
	for( int i = 0; g_cHudCache[hudtype][g_iSelectedHud[client]][i] != '\0'; i++ )
	{
		if( bStartedElement )
		{
			if( g_cHudCache[hudtype][g_iSelectedHud[client]][i] == '}' )
			{
				bStartedElement = false;
				element[curElementChar] = 0;
				curElementChar = 0;
				
				DataPack pack;
				if( g_smHudElementCallbacks.GetValue( element, pack ) )
				{
					pack.Reset();
					
					char replacement[64];

					Call_StartFunction( GetMyHandle(), pack.ReadFunction() );
					Call_PushCell( target );
					Call_PushStringEx( replacement, sizeof(replacement), 0, SM_PARAM_COPYBACK );
					Call_PushCell( sizeof(replacement) );
					Call_Finish();
					
					curHudChar += StrCat( hudtext, sizeof(hudtext), replacement );
				}
			}
			else
			{
				element[curElementChar++] = g_cHudCache[hudtype][g_iSelectedHud[client]][i];
			}
		}
		else
		{
			if( g_cHudCache[hudtype][g_iSelectedHud[client]][i] == '{' )
			{
				bStartedElement = true;
			}
			else
			{
				hudtext[curHudChar++] = g_cHudCache[hudtype][g_iSelectedHud[client]][i];
			}
		}
		hudtext[curHudChar] = 0;
	
		if( !bStartedElement && g_cHudCache[hudtype][g_iSelectedHud[client]][i] == '{' )
		{
			bStartedElement = true;
		}
	}
	
	static char buffer[64];
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i == client || !IsClientInGame( i ) || IsFakeClient( i ) || !IsClientObserver( i ) || GetEntPropEnt( i, Prop_Send, "m_hObserverTarget" ) != client )
		{
			continue;
		}
		
		PrintHintText( i, buffer );
	}
	
	PrintHintText( client, hudtext );

	return Plugin_Continue;
}

bool LoadHuds()
{
	g_iTotalHuds = 0;

	// load styles from cfg file
	char path[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, path, sizeof(path), "configs/Timer/timer-hud.cfg" );
	
	KeyValues kvHud = new KeyValues( "HUDS" );
	if( !kvHud.ImportFromFile( path ) || !kvHud.GotoFirstSubKey() )
	{
		return false;
	}
	
	do
	{
		kvHud.GetString( "name", g_cHudNames[g_iTotalHuds], sizeof(g_cHudNames[]) );

		File hudFile;
		char sFileName[32];

		kvHud.GetString( "starthud_filename", sFileName, sizeof(sFileName) );
		
		BuildPath( Path_SM, path, sizeof(path), "configs/Timer/HUD/%s.txt", sFileName );
		hudFile = OpenFile( path, "r" );
		hudFile.ReadString( g_cHudCache[HudType_StartZone][g_iTotalHuds], sizeof(g_cHudCache[][]) );
		hudFile.Close();

		kvHud.GetString( "timinghud_filename", sFileName, sizeof(sFileName) );
		
		BuildPath( Path_SM, path, sizeof(path), "configs/Timer/HUD/%s.txt", sFileName );
		hudFile = OpenFile( path, "r" );
		hudFile.ReadString( g_cHudCache[HudType_Timing][g_iTotalHuds], sizeof(g_cHudCache[][]) );
		hudFile.Close();

		kvHud.GetString( "replayhud_filename", sFileName, sizeof(sFileName) );
		
		BuildPath( Path_SM, path, sizeof(path), "configs/Timer/HUD/%s.txt", sFileName );
		hudFile = OpenFile( path, "r" );
		hudFile.ReadString( g_cHudCache[HudType_ReplayBot][g_iTotalHuds], sizeof(g_cHudCache[][]) );
		hudFile.Close();
		
		g_iTotalHuds++;
	} while( kvHud.GotoNextKey() );

	delete kvHud;
	
	return true;
}

void SetClientHudPreset( int client, int hud )
{
	char sValue[8];
	IntToString( hud, sValue, sizeof(sValue) );
	
	SetClientCookie( client, g_hSelectedHudCookie, sValue );
	
	g_iSelectedHud[client] = hud;
}

void SetClientHudSettings( int client, int hud )
{
	char sValue[8];
	IntToString( hud, sValue, sizeof(sValue) );
	
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
	
	Format( g_cRainbowColour, sizeof(g_cRainbowColour), "#%02X%02X%02X", g_RainbowColour[0], g_RainbowColour[1], g_RainbowColour[2] );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( !IsClientInGame( i ) || IsFakeClient( i ) )
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
	int[] spectators = new int[MaxClients + 1];
	int nSpectators = 0;
	
	int target = GetClientObserverTarget( client );

	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i == client || !IsClientInGame( i ) || IsFakeClient( i ) || !IsClientObserver( i ) || GetEntPropEnt( i, Prop_Send, "m_hObserverTarget" ) != target )
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
		
		FormatEx( buffer, sizeof(buffer), "Spectators (%i):\n", nSpectators );

		for( int i = 0; i < nSpectators; i++ )
		{
			if( i == 7 )
			{
				FormatEx( buffer, sizeof(buffer), "%s...", buffer );
				break;
			}

			if( GetClientName( spectators[i], name, sizeof(name) ) )
			{
				FormatEx( buffer, sizeof(buffer), "%s%s\n", buffer, name );
			}
		}
		
		SetHudTextParams( 0.7, 0.3, 0.1, 255, 255, 255, 255 );
		ShowSyncHudText( client, g_hHudSynchronizer, buffer );
	}
}

void DrawButtonsPanel( int client )
{
	int target = GetClientObserverTarget( client );
	if( !( 0 < target <= MaxClients ) )
	{
		return;
	}
	
	if( GetClientMenu( client, null ) == MenuSource_None || GetClientMenu( client, null ) == MenuSource_RawPanel )
	{
		Panel panel = new Panel();
		
		char buffer[128];
		
		int buttons = GetClientButtons( target );
		FormatEx( buffer, sizeof(buffer), "[%s]\n    %s\n%s   %s   %s", ( buttons & IN_DUCK ) > 0 ? "DUCK":"     ", ( buttons & IN_FORWARD ) > 0? "W":"-", ( buttons & IN_MOVELEFT ) > 0? "A":"-", ( buttons & IN_BACK ) > 0? "S":"-", ( buttons & IN_MOVERIGHT ) > 0? "D":"-" );
		
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
	if( !( 0 < target <= MaxClients ) )
	{
		return;
	}
	
	int track = Timer_GetClientZoneTrack( target );
	
	if( track == ZoneTrack_None )
	{
		return;
	}
	
	int style = Timer_GetClientStyle( target );
	
	float wrtime = Timer_GetWRTime( track, style );
	if( wrtime != 0.0 )
	{
		char sWRTime[16];
		Timer_FormatTime( wrtime, sWRTime, sizeof(sWRTime) );

		char sWRName[MAX_NAME_LENGTH];
		Timer_GetWRName( track, style, sWRName, sizeof(sWRName) );

		float pbtime = Timer_GetClientPBTime( target, track, style );

		char message[128];

		if( pbtime != 0.0 )
		{
			char sPBTime[16];
			Timer_FormatTime( pbtime, sPBTime, sizeof(sPBTime) );
			
			FormatEx( message, sizeof(message), "WR: %s (%s)\nPB: %s (#%i)", sWRTime, sWRName, sPBTime, Timer_GetClientRank( target, track, style ) );
		}
		else
		{
			FormatEx( message, sizeof(message), "WR: %s (%s)", sWRTime, sWRName );
		}

		SetHudTextParams( 0.01, 0.01, 2.5, 255, 255, 255, 255 );
		ShowSyncHudText( client, g_hHudSynchronizer, message );
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
	
	Format( buffer, sizeof(buffer), "Central HUD Preset: %s\n \n", g_cHudNames[g_iSelectedHud[client]] );
	menu.AddItem( "preset", buffer );
	
	Format( buffer, sizeof(buffer), "Central HUD: %s", ( g_iHudSettings[client] & HUD_CENTRAL ) ? "Enabled" : "Disabled" );
	menu.AddItem( "central", buffer );
	
	Format( buffer, sizeof(buffer), "Spectator List: %s", ( g_iHudSettings[client] & HUD_SPECLIST ) ? "Enabled" : "Disabled" );
	menu.AddItem( "speclist", buffer );
	
	Format( buffer, sizeof(buffer), "Buttons Panel: %s", ( g_iHudSettings[client] & HUD_BUTTONS ) ? "Enabled" : "Disabled" );
	menu.AddItem( "buttons", buffer );
	
	Format( buffer, sizeof(buffer), "Top Left Overlay: %s", ( g_iHudSettings[client] & HUD_TOPLEFT ) ? "Enabled" : "Disabled" );
	menu.AddItem( "topleft", buffer );
	
	Format( buffer, sizeof(buffer), "Hide Weapons: %s", ( g_iHudSettings[client] & HUD_HIDEWEAPONS ) ? "Enabled" : "Disabled" );
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