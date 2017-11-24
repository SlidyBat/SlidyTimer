#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>
#include <clientprefs>
#include <colourmanip>

#define TOTAL_HUDS 2

#define HUD_NONE		0
#define HUD_SPECLIST	(1 << 0)
#define HUD_BUTTONS		(1 << 1)
#define HUD_HINT		(1 << 2)


Menu		g_mHudPresetMenu;

Handle	g_hSelectedHudCookie;
int		g_iSelectedHud[MAXPLAYERS + 1];

char		g_cHudCache[TOTAL_HUDS][256];
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
	g_hSelectedHudCookie = RegClientCookie( "Timer_HUD", "Selected HUD preset for Slidy's Timer", CookieAccess_Protected );
	
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
}

public void OnClientCookiesCached( int client )
{
	char sValue[8];
	GetClientCookie( client, g_hSelectedHudCookie, sValue, sizeof( sValue ) );
	
	g_iSelectedHud[client] = StringToInt( sValue );
}

public Action OnPlayerRunCmd( int client, int& buttons )
{
	if( IsFakeClient( client ) || !IsValidClient( client, true ) )
	{
		return;
	}
	
	static char hudtext[256];
	hudtext = g_cHudCache[g_iSelectedHud[client]];
	
	static char buffer[64];
	
	int speed = RoundFloat( GetClientSpeed( client ) );
	IntToString( speed, buffer, sizeof( buffer ) );
	ReplaceString( hudtext, sizeof( hudtext ), "{speed}", buffer );
	
	ZoneType ztType = Timer_GetClientZoneType( client );
	ZoneTrack track = Timer_GetClientZoneTrack( client );
	int style = Timer_GetClientStyle( client );
	
	int jumps = Timer_GetClientCurrentJumps( client );
	IntToString( jumps, buffer, sizeof( buffer ) );
	ReplaceString( hudtext, sizeof( hudtext ), "{jumps}", buffer );
	
	int strafes = Timer_GetClientCurrentStrafes( client );
	IntToString( strafes, buffer, sizeof( buffer ) );
	ReplaceString( hudtext, sizeof( hudtext ), "{strafes}", buffer );
	
	float sync = Timer_GetClientCurrentSync( client );
	FormatEx( buffer, sizeof( buffer ), "%.2f", sync );
	ReplaceString( hudtext, sizeof( hudtext ), "{sync}", buffer );
	
	float strafetime = Timer_GetClientCurrentStrafeTime( client );
	FormatEx( buffer, sizeof( buffer ), "%.2f", strafetime );
	ReplaceString( hudtext, sizeof( hudtext ), "{strafetime}", buffer );
	
	float wrtime = Timer_GetWRTime( track, style );
	FormatEx( buffer, sizeof( buffer ), "%.2f", wrtime );
	ReplaceString( hudtext, sizeof( hudtext ), "{wrtime}", buffer );
	
	float pbtime = Timer_GetClientPBTime( client, track, style );
	FormatEx( buffer, sizeof( buffer ), "%.2f", pbtime );
	ReplaceString( hudtext, sizeof( hudtext ), "{pbtime}", buffer );
	
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
				FormatEx( buffer, sizeof( buffer ), "<font color=\"red\">Stopped\t\t" );
			}
			case TimerStatus_Paused:
			{
				FormatEx( buffer, sizeof( buffer ), "<font color=\"purple\">Paused" );
			}
			case TimerStatus_Running:
			{
				float time = Timer_GetClientCurrentTime( client );
				Timer_FormatTime( time, buffer, sizeof( buffer ) );
				
				char sTimeColour[8];
				GetTimeColour( sTimeColour, time, pbtime, wrtime );
				Format( buffer, sizeof( buffer ), "Time: <font color='%s'>%s</font>\t", sTimeColour, buffer );
			}
		}
	}

	ReplaceString( hudtext, sizeof( hudtext ), "{time}", buffer );
	
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
		char sFileName[32];
		kvHud.GetSectionName( g_cHudNames[g_iTotalHuds], sizeof(  g_cHudNames ) );
		kvHud.GetString( "filename", sFileName, sizeof( sFileName ) );
		
		BuildPath( Path_SM, path, sizeof( path ), "configs/Timer/HUD/%s.txt", sFileName );
		File hud = OpenFile( path, "r" );
		hud.ReadString( g_cHudCache[g_iTotalHuds], sizeof( g_cHudCache[] ) );
		hud.Close();
		
		g_iTotalHuds++;
	} while( kvHud.GotoNextKey() );

	delete kvHud;
	
	// build menu
	delete g_mHudPresetMenu;
	g_mHudPresetMenu = new Menu( HudPreset_Handler );
	
	g_mHudPresetMenu.SetTitle( "Select HUD Preset\n \n" );
	
	for( int i = 0; i < g_iTotalHuds; i++ )
	{
		char info[8];
		IntToString( i, info, sizeof( info ) );
		
		g_mHudPresetMenu.AddItem( info, g_cHudNames[i] );
	}
	
	return true;
}

public int HudPreset_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		SetClientHudPreset( param1, param2 );
	}
}

void SetClientHudPreset( int client, int hud )
{
	char sValue[8];
	IntToString( hud, sValue, sizeof( sValue ) );
	
	SetClientCookie( client, g_hSelectedHudCookie, sValue );
	
	g_iSelectedHud[client] = hud;
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

public Action Command_Hud( int client, int args )
{
	g_mHudPresetMenu.Display( client, 20 );
	
	return Plugin_Handled;
}