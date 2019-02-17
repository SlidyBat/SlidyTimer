#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>
#include <clientprefs>

#define MAX_ADVERTISEMENTS 20

bool		g_bLate;

ConVar	g_cvPrintInterval;

Handle	g_hPrintAdvertisementsCookie;
bool		g_bPrintAdvertisement[MAXPLAYERS + 1] = { true, ... };

char		g_cAdvertisements[MAX_ADVERTISEMENTS][512];
int		g_iTotalAdvertisements = 0;
int		g_iCurrentAdvertisement = 0;

public Plugin myinfo = 
{
	name = "Slidy's Timer - Advertisements component",
	author = "SlidyBat",
	description = "Prints timer related advertisements/tips in chat",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	RegPluginLibrary( "timer-advertisement" );
	g_bLate = late;
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hPrintAdvertisementsCookie = RegClientCookie( "timer_print_advertisements", "Whether to print timer related ads/tips to client", CookieAccess_Protected );
	
	g_cvPrintInterval = CreateConVar( "timer_advertisements_print_interval", "2", "Interval in minutes to print the advertisements", _, true, 0.0 );
	AutoExecConfig( true, "timer-advertisements", "SlidyTimer" );
	
	RegConsoleCmd( "sm_notifications", Command_Notifications );
	RegConsoleCmd( "sm_tips", Command_Notifications );

	if( g_bLate )
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( AreClientCookiesCached( i ) )
			{
				OnClientCookiesCached( i );
			}
		}
		OnMapStart();
	}
}

public void OnMapStart()
{
	if( !LoadAdvertisements() )
	{
		LogError( "Failed to load configs/timer-advertisements.txt, make sure it exists" );
	}
	CreateTimer( g_cvPrintInterval.FloatValue, Timer_PrintAdvertisement, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
}

public void OnClientPutInServer( int client )
{
	g_bPrintAdvertisement[client] = true;
}

public void OnClientCookiesCached( int client )
{
	char sValue[8];
	
	if( sValue[0] == '\0' )
	{
		SetClientCookie( client, g_hPrintAdvertisementsCookie, "1" );
		g_bPrintAdvertisement[client] = true;
	}
	else
	{
		g_bPrintAdvertisement[client] = (StringToInt( sValue ) != 0);
	}
}

bool LoadAdvertisements()
{
	g_iTotalAdvertisements = 0;
	
	// load advertisements from cfg file
	char path[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, path, sizeof(path), "configs/Timer/timer-advertisements.txt" );
	
	File adsFile = OpenFile( path, "r" );
	while( adsFile.ReadLine( g_cAdvertisements[g_iTotalAdvertisements++], sizeof(g_cAdvertisements[]) ) ) {}
	adsFile.Close();
	
	return true;
}

public Action Timer_PrintAdvertisement( Handle timer )
{
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && g_bPrintAdvertisement[i] )
		{
			Timer_PrintToChat( i, g_cAdvertisements[g_iCurrentAdvertisement] );
		}
	}
	
	g_iCurrentAdvertisement = (g_iCurrentAdvertisement + 1) % g_iTotalAdvertisements;
}

public Action Command_Notifications( int client, int args )
{
	g_bPrintAdvertisement[client] = !g_bPrintAdvertisement[client];
	Timer_PrintToChat( client, "{primary}Notifications: {secondary}%s", g_bPrintAdvertisement[client] ? "Enabled" : "Disabled" );
	
	SetClientCookie( client, g_hPrintAdvertisementsCookie, g_bPrintAdvertisement[client] ? "1" : "0" );
	
	return Plugin_Handled;
}