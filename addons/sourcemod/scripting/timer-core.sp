#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>
#include <sdktools>
#include <geoip>

public Plugin myinfo = 
{
	name = "Slidy's Timer - Core component",
	author = "SlidyBat",
	description = "Core component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

Database		g_hDatabase;

float			g_fFrameTime;
char			g_cMapName[PLATFORM_MAX_PATH];
int			g_iMapId = -1;

Handle		g_hForward_OnDatabaseLoaded;
Handle		g_hForward_OnMapLoaded;
Handle		g_hForward_OnClientLoaded;
Handle		g_hForward_OnPlayerRunCmdPost;
Handle		g_hForward_OnStylesLoaded;
Handle		g_hForward_OnStyleChangedPre;
Handle		g_hForward_OnStyleChangedPost;
Handle		g_hForward_OnTimerFinishPre;
Handle		g_hForward_OnTimerFinishPost;
Handle		g_hForward_OnTimerStart;

any			g_StyleSettings[MAX_STYLES][styleSettings];
StringMap	g_StyleSettingStrings[MAX_STYLES];
StringMap		g_smStyleCommands;
int			g_iTotalStyles;

/* Player Data */
int			g_PlayerCurrentStyle[MAXPLAYERS + 1];
bool			g_bTimerRunning[MAXPLAYERS + 1]; // whether client timer is running or not, regardless of if its paused
bool			g_bTimerPaused[MAXPLAYERS + 1];

/* PLAYER RECORD DATA */
int			g_iPlayerId[MAXPLAYERS + 1] = { -1, ... };

int			g_nPlayerFrames[MAXPLAYERS + 1];
int			g_nPlayerJumps[MAXPLAYERS + 1];
int			g_nPlayerStrafes[MAXPLAYERS + 1];
int			g_iPlayerSSJ[MAXPLAYERS + 1];
int			g_nPlayerSyncedFrames[MAXPLAYERS + 1];
int			g_nPlayerAirFrames[MAXPLAYERS + 1];
int			g_nPlayerAirStrafeFrames[MAXPLAYERS + 1];

bool			g_bNoclip[MAXPLAYERS + 1];

int			g_iClientBlockTickStart[MAXPLAYERS + 1];
int			g_nClientBlockTicks[MAXPLAYERS + 1];

ConVar		sv_autobunnyhopping;

public void OnPluginStart()
{
	/* Forwards */
	g_hForward_OnDatabaseLoaded = CreateGlobalForward( "Timer_OnDatabaseLoaded", ET_Ignore );
	g_hForward_OnMapLoaded = CreateGlobalForward( "Timer_OnMapLoaded", ET_Ignore, Param_Cell );
	g_hForward_OnClientLoaded = CreateGlobalForward( "Timer_OnClientLoaded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnPlayerRunCmdPost = CreateGlobalForward( "Timer_OnPlayerRunCmdPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Array );
	g_hForward_OnStylesLoaded = CreateGlobalForward( "Timer_OnStylesLoaded", ET_Ignore, Param_Cell );
	g_hForward_OnStyleChangedPre = CreateGlobalForward( "Timer_OnStyleChangedPre", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnStyleChangedPost = CreateGlobalForward( "Timer_OnStyleChangedPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnTimerFinishPre = CreateGlobalForward( "Timer_OnTimerFinishPre", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnTimerFinishPost = CreateGlobalForward( "Timer_OnTimerFinishPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnTimerStart = CreateGlobalForward( "Timer_OnTimerStart", ET_Event, Param_Cell );
	
	/* Commands */
	RegConsoleCmd( "sm_nc", Command_Noclip );
	
	RegConsoleCmd( "sm_style", Command_Styles );
	RegConsoleCmd( "sm_styles", Command_Styles );
	
	/* Hooks */
	HookEvent( "player_jump", HookEvent_PlayerJump );
	
	SQL_DBConnect();
	
	g_fFrameTime = GetTickInterval();
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	CreateNative( "Timer_GetDatabase", Native_GetDatabase );
	CreateNative( "Timer_GetMapId", Native_GetMapId );
	CreateNative( "Timer_IsClientLoaded", Native_IsClientLoaded );
	CreateNative( "Timer_GetClientPlayerId", Native_GetClientPlayerId );
	CreateNative( "Timer_GetClientCurrentTime", Native_GetClientCurrentTime );
	CreateNative( "Timer_GetClientCurrentJumps", Native_GetClientCurrentJumps );
	CreateNative( "Timer_GetClientCurrentStrafes", Native_GetClientCurrentStrafes );
	CreateNative( "Timer_GetClientCurrentSync", Native_GetClientCurrentSync );
	CreateNative( "Timer_GetClientCurrentStrafeTime", Native_GetClientCurrentStrafeTime );
	CreateNative( "Timer_GetClientCurrentSSJ", Native_GetClientCurrentSSJ );
	CreateNative( "Timer_GetClientTimerStatus", Native_GetClientTimerStatus );
	CreateNative( "Timer_SetClientStyle", Native_SetClientStyle );
	CreateNative( "Timer_GetClientStyle", Native_GetClientStyle );
	CreateNative( "Timer_GetClientTimerData", Native_GetClientTimerData );
	CreateNative( "Timer_SetClientTimerData", Native_SetClientTimerData );
	CreateNative( "Timer_GetStyleCount", Native_GetStyleCount );
	CreateNative( "Timer_GetStyleSettings", Native_GetStyleSettings );
	CreateNative( "Timer_GetStyleName", Native_GetStyleName );
	CreateNative( "Timer_GetStylePrefix", Native_GetStylePrefix );
	CreateNative( "Timer_StyleHasSetting", Native_StyleHasSetting );
	CreateNative( "Timer_IsTimerRunning", Native_IsTimerRunning );
	CreateNative( "Timer_StopTimer", Native_StopTimer );
	CreateNative( "Timer_BlockTimer", Native_BlockTimer );

	RegPluginLibrary( "timer-core" );
	
	sv_autobunnyhopping = FindConVar( "sv_autobunnyhopping" );
	sv_autobunnyhopping.BoolValue = false;

	return APLRes_Success;
}

public void OnMapStart()
{
	if( !LoadStyles() )
	{
		SetFailState( "Failed to find sourcemod/configs/Timer/timer-styles.cfg, make sure it exists and is properly filled." );
	}

	GetCurrentMap( g_cMapName, sizeof( g_cMapName ) );
	
	SQL_LoadMap();
}

public void OnClientAuthorized( int client, const char[] auth )
{
	if( !IsFakeClient( client ) )
	{
		SQL_LoadPlayerID( client );
		sv_autobunnyhopping.ReplicateToClient( client, "1" );
	}
	
	StopTimer( client );
	ClearPlayerData( client );
}

public void OnClientDisconnect( int client )
{
	g_iPlayerId[client] = -1;
	g_iClientBlockTickStart[client] = 0;
	g_nClientBlockTicks[client] = 0;
	g_bNoclip[client] = false;
}

public Action OnPlayerRunCmd( int client, int& buttons, int& impulse, float vel[3], float angles[3] )
{
	if( IsPlayerAlive( client ) )
	{	
		static any settings[styleSettings];
		settings = g_StyleSettings[g_PlayerCurrentStyle[client]];
		
		int lastButtons = GetEntProp( client, Prop_Data, "m_nOldButtons" );
		static float lastYaw[MAXPLAYERS + 1];
		
		float fDeltaYaw = angles[1] - lastYaw[client];
		NormalizeAngle( fDeltaYaw );
		
		bool bButtonError = false;
		
		// sanity check, if player pressing buttons but not moving then somethings wrong
		if( ( ( buttons & IN_FORWARD ) || ( buttons & IN_BACK ) ) && ( vel[0] == 0.0 ) )
		{
			bButtonError = true;
		}
		else if( ( ( buttons & IN_MOVELEFT ) || ( buttons & IN_MOVERIGHT ) ) && ( vel[1] == 0.0 ) )
		{
			bButtonError = true;
		}
		
		if( Timer_GetClientZoneType( client ) == Zone_Start )
		{
			if( buttons & IN_JUMP && !settings[StartBhop] )
			{
				buttons &= ~IN_JUMP;
			}
			
			if( !g_bNoclip[client] && settings[PreSpeed] != 0.0 && GetClientSpeedSq( client ) > settings[PreSpeed]*settings[PreSpeed] )
			{
				float speed = GetClientSpeed( client );
				float scale = settings[PreSpeed] / speed;
				
				float vVel[3];
				GetEntPropVector( client, Prop_Data, "m_vecAbsVelocity", vVel );
				ScaleVector( vVel, scale );
				
				TeleportEntity( client, NULL_VECTOR, NULL_VECTOR, vVel );
			}
		}
		
		if( !( GetEntityFlags( client ) & FL_ONGROUND ) && buttons & IN_JUMP )
		{
			if( settings[AutoBhop] &&
				GetEntityMoveType( client ) != MOVETYPE_NONE &&
				GetEntityMoveType( client ) != MOVETYPE_LADDER &&
				GetEntityMoveType( client ) != MOVETYPE_NOCLIP &&
				GetEntProp( client, Prop_Data, "m_nWaterLevel" ) < 2 )
			{
				buttons &= ~IN_JUMP;
			}
		}
		
		// blocking keys (only in air)
		if( !( GetEntityFlags( client ) & FL_ONGROUND ) && GetEntityMoveType( client ) == MOVETYPE_WALK )
		{
			if( settings[PreventLeft] && ( buttons & IN_MOVELEFT ) ||
				settings[PreventRight] && ( buttons & IN_MOVERIGHT ) ||
				settings[PreventForward] && ( buttons & IN_FORWARD ) ||
				settings[PreventBack] && ( buttons & IN_BACK ) )
			{
				bButtonError = true;
			}
			else if( settings[HSW] && 
					!( ( buttons & IN_FORWARD ) && ( ( buttons & IN_MOVELEFT ) || ( buttons & IN_MOVERIGHT ) ) ) )
			{
				bButtonError = true;
			}
		}
		
		if( bButtonError )
		{
			vel[0] = 0.0;
			vel[1] = 0.0;
		}

		if( g_bTimerRunning[client] && !g_bTimerPaused[client] )
		{
			g_nPlayerFrames[client]++;
			
			if( !( GetEntityFlags( client ) & FL_ONGROUND ) )
			{
				g_nPlayerAirFrames[client]++;
				
				if( fDeltaYaw != 0.0 )
				{
					g_nPlayerAirStrafeFrames[client]++;
				}
				
				if( settings[Sync] &&
					( ( fDeltaYaw > 0.0 && ( buttons & IN_MOVELEFT ) && !( buttons & IN_MOVERIGHT ) ) ||
					( fDeltaYaw < 0.0 && ( buttons & IN_MOVERIGHT ) && !( buttons & IN_MOVELEFT ) ) ) )
				{
					g_nPlayerSyncedFrames[client]++;
				}
			}
			
			if( settings[HSW] )
			{
				if( ( buttons & IN_FORWARD ) && ( lastButtons & IN_FORWARD ) )
				{
					if( !( lastButtons & IN_LEFT ) && ( buttons & IN_LEFT ) )
					{
						g_nPlayerStrafes[client]++;
					}
					else if( !( lastButtons & IN_RIGHT ) && ( buttons & IN_RIGHT ) )
					{
						g_nPlayerStrafes[client]++;
					}
				}
			}
			else
			{
				if( settings[CountLeft] && !( lastButtons & IN_MOVELEFT ) && ( buttons & IN_MOVELEFT ) )
				{
					g_nPlayerStrafes[client]++;
				}
				else if( settings[CountRight] && !( lastButtons & IN_MOVERIGHT ) && ( buttons & IN_MOVERIGHT ) )
				{
					g_nPlayerStrafes[client]++;
				}
				else if( settings[CountForward] && !( lastButtons & IN_FORWARD ) && ( buttons & IN_FORWARD ) )
				{
					g_nPlayerStrafes[client]++;
				}
				else if( settings[CountBack] && !( lastButtons & IN_BACK ) && ( buttons & IN_BACK ) )
				{
					g_nPlayerStrafes[client]++;
				}
			}
		}
		
		lastYaw[client] = angles[1];
	}
	
	Call_StartForward( g_hForward_OnPlayerRunCmdPost );
	Call_PushCell( client );
	Call_PushCell( buttons );
	Call_PushCell( impulse );
	Call_PushArray( vel, 3 );
	Call_PushArray( angles, 3 );
	Call_Finish();
}

void ClearPlayerData( int client )
{
	g_nPlayerFrames[client] = 0;
	
	g_nPlayerJumps[client] = 0;
	g_nPlayerStrafes[client] = 0;
	g_iPlayerSSJ[client] = 0;
	g_nPlayerSyncedFrames[client] = 0;
	g_nPlayerAirStrafeFrames[client] = 0;
	g_nPlayerAirFrames[client] = 0;
}

void StartTimer( int client )
{
	if( g_bNoclip[client] || Timer_GetClientZoneType( client ) == Zone_End )
	{
		return;
	}

	Action result = Plugin_Continue;
	Call_StartForward( g_hForward_OnTimerStart );
	Call_PushCell( client );
	Call_Finish( result );
	
	if( result != Plugin_Continue && result != Plugin_Changed )
	{
		StopTimer( client );
		return;
	}

	g_bTimerRunning[client] = true;
	g_bTimerPaused[client] = false;
	
	ClearPlayerData( client );
}

void StopTimer( int client )
{
	// dont clear player data until they actually reset
	// just in case this data is needed again
	// e.g. in TAS/Segmenting
	
	g_bTimerRunning[client] = false;
	g_bTimerPaused[client] = false;
}

void FinishTimer( int client )
{
	if( !IsPlayerAlive( client ) )
	{
		return;
	}
	
	float time = g_nPlayerFrames[client] * g_fFrameTime;
	
	int track = Timer_GetClientZoneTrack( client );
	int style = g_PlayerCurrentStyle[client];
	
	Action result = Plugin_Continue;
	Call_StartForward( g_hForward_OnTimerFinishPre );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushCell( time );
	Call_Finish( result );
	
	if( result == Plugin_Stop || result == Plugin_Handled )
	{
		return;
	}
	
	if( result != Plugin_Changed )
	{		
		char sTime[64];
		Timer_FormatTime( time, sTime, sizeof( sTime ) );
	
		char sZoneTrack[64];
		Timer_GetZoneTrackName( track, sZoneTrack, sizeof( sZoneTrack ) );
		Timer_PrintToChatAll( "[{secondary}%s{white}] {name}%N {primary}finished on {secondary}%s {primary}timer in {secondary}%ss", g_StyleSettings[style][StyleName], client, sZoneTrack, sTime );
	}
	
	Call_StartForward( g_hForward_OnTimerFinishPost );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushCell( time );
	Call_Finish();
	
	StopTimer( client );
}

bool LoadStyles()
{
	g_iTotalStyles = 0;
	
	delete g_smStyleCommands;
	g_smStyleCommands = new StringMap();
	
	for( int i = 0; i < MAX_STYLES; i++ )
	{
		delete g_StyleSettingStrings[i];
	}

	// load styles from cfg file
	char path[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, path, sizeof( path ), "configs/Timer/timer-styles.cfg" );

	KeyValues kvStyles = new KeyValues( "Styles" );
	if( !kvStyles.ImportFromFile( path ) || !kvStyles.GotoFirstSubKey() )
	{
		return false;
	}

	do
	{
		kvStyles.GetString( "stylename", g_StyleSettings[g_iTotalStyles][StyleName], 64 );
		kvStyles.GetString( "styleprefix", g_StyleSettings[g_iTotalStyles][StylePrefix], 16 );
		kvStyles.GetString( "aliases", g_StyleSettings[g_iTotalStyles][Aliases], 512 );
		kvStyles.GetString( "settings", g_StyleSettings[g_iTotalStyles][SettingString], 256 );
		
		g_StyleSettingStrings[g_iTotalStyles] = new StringMap();
		
		char settings[20][24];
		int nSettings = ExplodeString( g_StyleSettings[g_iTotalStyles][SettingString], ";", settings, sizeof(settings), sizeof(settings[]) );
		
		for( int i = 0; i < nSettings; i++ )
		{
			g_StyleSettingStrings[g_iTotalStyles].SetValue( settings[i], 0 ); // value isnt used, SM doesn't have a set type though so just use 0
		}

		g_StyleSettings[g_iTotalStyles][Ranked] = 			kvStyles.GetNum( "ranked", 1 ) != 0;
		g_StyleSettings[g_iTotalStyles][AutoBhop] =			kvStyles.GetNum( "autobhop", 1 ) != 0;
		g_StyleSettings[g_iTotalStyles][StartBhop] =			kvStyles.GetNum( "startbhop", 0 ) != 0;

		g_StyleSettings[g_iTotalStyles][Gravity] =			kvStyles.GetFloat( "gravity", 0.0 );
		g_StyleSettings[g_iTotalStyles][Timescale] =			kvStyles.GetFloat( "timescale", 1.0 );
		g_StyleSettings[g_iTotalStyles][MaxSpeed] =			kvStyles.GetFloat( "maxspeed", 0.0 );
		g_StyleSettings[g_iTotalStyles][Fov] =				kvStyles.GetNum( "fov", 90 );

		g_StyleSettings[g_iTotalStyles][Sync] =				kvStyles.GetNum( "sync", 1 ) != 0;

		g_StyleSettings[g_iTotalStyles][PreventLeft] =		kvStyles.GetNum( "prevent_left", 0 ) != 0;
		g_StyleSettings[g_iTotalStyles][PreventRight] =		kvStyles.GetNum( "prevent_right", 0 ) != 0;
		g_StyleSettings[g_iTotalStyles][PreventForward] =	kvStyles.GetNum( "prevent_forward", 0 ) != 0;
		g_StyleSettings[g_iTotalStyles][PreventBack] =		kvStyles.GetNum( "prevent_back", 0 ) != 0;

		g_StyleSettings[g_iTotalStyles][CountLeft] =			kvStyles.GetNum( "count_left", 1 ) != 0;
		g_StyleSettings[g_iTotalStyles][CountRight] =		kvStyles.GetNum( "count_right", 1 ) != 0;
		g_StyleSettings[g_iTotalStyles][CountForward] =		kvStyles.GetNum( "count_forward", 0 ) != 0;
		g_StyleSettings[g_iTotalStyles][CountBack] = 		kvStyles.GetNum( "count_back", 0 ) != 0;
		
		g_StyleSettings[g_iTotalStyles][HSW] = 				kvStyles.GetNum( "hsw", 0 ) != 0;
		
		g_StyleSettings[g_iTotalStyles][PreSpeed] = 			kvStyles.GetFloat( "prespeed", 290.0 );

		g_StyleSettings[g_iTotalStyles][MainReplayBot] = 	kvStyles.GetNum( "main_bot", 0 ) != 0;
		g_StyleSettings[g_iTotalStyles][BonusReplayBot] =	kvStyles.GetNum( "bonus_bot", 0 ) != 0;
		
		g_StyleSettings[g_iTotalStyles][ExpMultiplier] = 	kvStyles.GetFloat( "expmultiplier", 1.0 );

		g_StyleSettings[g_iTotalStyles][StyleId] = 			g_iTotalStyles;

		
		char splitString[16][32];
		int nAliases = ExplodeString( g_StyleSettings[g_iTotalStyles][Aliases], ",", splitString, sizeof( splitString ), sizeof( splitString[] ) );
		
		for( int i = 0; i < nAliases; i++ )
		{
			TrimString( splitString[i] );
			
			char command[32];
			Format( command, sizeof( command ), "sm_%s", splitString[i] );
			
			g_smStyleCommands.SetValue( command, g_iTotalStyles );
			
			if( !CommandExists( command ) )
			{
				RegConsoleCmd( command, Command_ChangeStyle );
			}
		}
		
		g_iTotalStyles++;
	} while( kvStyles.GotoNextKey() );

	delete kvStyles;
	
	Call_StartForward( g_hForward_OnStylesLoaded );
	Call_PushCell( g_iTotalStyles );
	Call_Finish();
	
	return true;
}

public void SetClientStyle( int client, int style )
{
	Action result = Plugin_Continue;
	Call_StartForward( g_hForward_OnStyleChangedPre );
	Call_PushCell( client );
	Call_PushCell( g_PlayerCurrentStyle[client] );
	Call_PushCell( style );
	Call_Finish( result );
	
	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	int oldstyle = g_PlayerCurrentStyle[client];
	g_PlayerCurrentStyle[client] = style;
	
	SetEntProp( client, Prop_Send, "m_iFOV", g_StyleSettings[style][Fov] );
	SetEntProp( client, Prop_Send, "m_iDefaultFOV", g_StyleSettings[style][Fov] );

	SetEntityGravity( client, ( 1.0 - g_StyleSettings[style][Gravity] ) );
	
	SetEntPropFloat( client, Prop_Data, "m_flLaggedMovementValue", view_as<float>( g_StyleSettings[style][Timescale] ) );
	
	sv_autobunnyhopping.ReplicateToClient( client, g_StyleSettings[style][AutoBhop] ? "1" : "0" );
	Timer_DebugPrint( "SetClientStyle: Set %N sv_autobunnyhopping=%s", client, g_StyleSettings[style][AutoBhop] ? "1" : "0" );
	
	Timer_TeleportClientToZone( client, Zone_Start, ZoneTrack_Main );
	
	Timer_PrintToChat( client, "{primary}Style now: {secondary}%s", g_StyleSettings[style][StyleName] );
	
	Call_StartForward( g_hForward_OnStyleChangedPost );
	Call_PushCell( client );
	Call_PushCell( oldstyle );
	Call_PushCell( style );
	Call_Finish();
}

public void Timer_OnEnterZone( int client, int id, int zoneType, int zoneTrack, int subindex )
{
	switch( zoneType )
	{
		case Zone_Start:
		{
			g_bTimerRunning[client] = false;
		}
		case Zone_End:
		{
			if( g_bTimerRunning[client] && !g_bTimerPaused[client] && Timer_GetClientZoneTrack( client ) == zoneTrack && Timer_GetClientZoneType( client ) == Zone_None )
			{
				FinishTimer( client );
			}
		}
		case Zone_Checkpoint:
		{
			// TODO: implement some checkpoint stuff MUCH LATER
		}
		case Zone_Cheatzone:
		{
			if( g_bTimerRunning[client] )
			{
				StopTimer( client );
			}
		}
	}
}

public void Timer_OnExitZone( int client, int id, int zoneType, int zoneTrack, int subindex )
{
	switch( zoneType )
	{
		case Zone_Start:
		{
			if( GetGameTickCount() - g_iClientBlockTickStart[client] <= g_nClientBlockTicks[client] ) // anti abuse system
			{
				return;
			}
			
			StartTimer( client );
			
			if( !( GetEntityFlags( client ) & FL_ONGROUND ) )
			{
				g_nPlayerJumps[client] = 1;
			}
		}
		case Zone_End:
		{
		}
		case Zone_Checkpoint:
		{
		}
		case Zone_Cheatzone:
		{
		}
	}
}

public Action HookEvent_PlayerJump( Event event, const char[] name, bool dontBroadcast )
{
	int userid = event.GetInt( "userid" );
	int client = GetClientOfUserId( userid );
	if( Timer_IsTimerRunning( client ) )
	{	
		if( ++g_nPlayerJumps[client] == 6 )
		{
			g_iPlayerSSJ[client] = RoundFloat( GetClientSpeed( client ) );
		}
		
		int style = Timer_GetClientStyle( client );
		if( g_StyleSettings[style][MaxSpeed] != 0.0 && GetClientSpeedSq( client ) > g_StyleSettings[style][MaxSpeed]*g_StyleSettings[style][MaxSpeed] )
		{
			DataPack pack = new DataPack();
			pack.WriteCell( userid );
			pack.WriteFloat( g_StyleSettings[style][MaxSpeed] );
			RequestFrame( LimitSpeed, pack );
		}
	}
}

public void LimitSpeed( DataPack pack )
{
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	float maxspeed = pack.ReadFloat() * 0.9;
	delete pack;
	
	float speed = GetClientSpeed( client );
	float scale = maxspeed / speed;
	
	float vel[3];
	GetEntPropVector( client, Prop_Data, "m_vecAbsVelocity", vel );
	ScaleVector( vel, scale );
	
	TeleportEntity( client, NULL_VECTOR, NULL_VECTOR, vel );
}

/* Database */

void SQL_DBConnect()
{
	delete g_hDatabase;
	
	char error[256];
	g_hDatabase = SQL_Connect( "Slidy-Timer", true, error, sizeof(error) );

	if( g_hDatabase == null )
	{
		SetFailState( "[SQL ERROR] (SQL_DBConnect) - %s", error );
	}
	
	// support unicode names
	g_hDatabase.SetCharset( "utf8" );

	Call_StartForward( g_hForward_OnDatabaseLoaded );
	Call_Finish();
	
	SQL_CreateTables();
}

void SQL_CreateTables()
{
	Transaction txn = new Transaction();

	char query[512];
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_maps` ( mapid INT NOT NULL AUTO_INCREMENT, \
																		mapname CHAR( 128 ) NOT NULL, \
																		maptier INT NOT NULL, \
																		lastplayed INT NOT NULL, \
																		playcount INT NOT NULL, \
																		PRIMARY KEY (`mapid`) );" );
	txn.AddQuery( query );
	
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_players` ( playerid INT NOT NULL AUTO_INCREMENT, \
																			steamaccountid INT NOT NULL, \
																			lastname CHAR(64) NOT NULL, \
																			firstconnect INT(16) NOT NULL, \
																			lastconnect INT(16) NOT NULL, \
																			country CHAR(32) NOT NULL, \
																			ip CHAR(64) NOT NULL, \
																			PRIMARY KEY (`playerid`) );" );
	txn.AddQuery( query );
	
	g_hDatabase.Execute( txn, CreateTableSuccess_Callback, CreateTableFailure_Callback, _, DBPrio_High );
}

public void CreateTableSuccess_Callback( Database db, any data, int numQueries, DBResultSet[] results, any[] queryData )
{
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && IsClientAuthorized( i ) && !IsFakeClient( i ) )
		{
			SQL_LoadPlayerID( i );
		}
	}
}

public void CreateTableFailure_Callback( Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData )
{
	SetFailState( "[SQL ERROR] (CreateTableFailure_Callback) - %s", error );
}

void SQL_LoadPlayerID( int client )
{
	char query[128];
	Format( query, sizeof( query ), "SELECT playerid FROM `t_players` WHERE steamaccountid = '%i';", GetSteamAccountID( client ) );
	
	g_hDatabase.Query( LoadPlayerID_Callback, query, GetClientUserId( client ), DBPrio_High );
}

public void LoadPlayerID_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadPlayerID_Callback) - %s", error );
		return;
	}
	
	int client = GetClientOfUserId( uid );
	if( !client ) // client no longer valid since id loaded :(
	{
		Timer_DebugPrint( "LoadPlayerID_Callback: Invalid userid %i (%i)", uid, client );
		return;
	}
	
	char ip[64];
	GetClientIP( client, ip, sizeof(ip) );
	
	char country[64];
	if( !GeoipCountry( ip, country, sizeof(country) ) )
	{
		strcopy( country, sizeof(country), "LAN" );
	}
	
	if( results.RowCount ) // playerid already exists, this is returning user
	{
		if( results.FetchRow() )
		{		
			char name[MAX_NAME_LENGTH * 2 + 1]; // worst case: every character is escaped + null character
			GetClientName( client, name, sizeof( name ) );
			g_hDatabase.Escape( name, name, sizeof( name ) );
			
			g_iPlayerId[client] = results.FetchInt( 0 );
			
			// update info
			char query[256];
			Format( query, sizeof( query ), "UPDATE `t_players` SET lastname = '%s', lastconnect = '%i', country = '%s', ip = '%s' WHERE playerid = '%i';", name, GetTime(), country, ip, g_iPlayerId[client] );
			
			Timer_DebugPrint( "LoadPlayerID_Callback: Existing user %L (playerid=%i)", client, g_iPlayerId[client] );
			
			g_hDatabase.Query( UpdatePlayerInfo_Callback, query, uid, DBPrio_Normal );
		}
	}
	else  // new user
	{
		Timer_DebugPrint( "LoadPlayerID_Callback: New user %L", client );
	
		int timestamp = GetTime();
		
		char name[MAX_NAME_LENGTH * 2 + 1]; // worst case: every character is escaped + null character
		GetClientName( client, name, sizeof( name ) );
		g_hDatabase.Escape( name, name, sizeof( name ) );

		char query[256];
		Format( query, sizeof( query ), "INSERT INTO `t_players` (`steamaccountid`, `lastname`, `firstconnect`, `lastconnect`, `country`, `ip`) VALUES ('%i', '%s', '%i', '%i', '%s', '%s');", GetSteamAccountID( client ), name, timestamp, timestamp, country, ip );
		
		Timer_DebugPrint( "LoadPlayerID_Callback: %s", query );
		
		g_hDatabase.Query( InsertPlayerInfo_Callback, query, uid, DBPrio_High );
	}
}

public void UpdatePlayerInfo_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdatePlayerInfo_Callback) - %s", error );
		return;
	}
	
	int client = GetClientOfUserId( uid );
	if( !client )
	{
		return;
	}
	
	Call_StartForward( g_hForward_OnClientLoaded );
	Call_PushCell( client );
	Call_PushCell( g_iPlayerId[client] );
	Call_PushCell( false );
	Call_Finish();
}

public void InsertPlayerInfo_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertPlayerInfo_Callback) - %s", error );
		return;
	}
	
	int client = GetClientOfUserId( uid );
	g_iPlayerId[client] = results.InsertId;
	
	Call_StartForward( g_hForward_OnClientLoaded );
	Call_PushCell( client );
	Call_PushCell( g_iPlayerId[client] );
	Call_PushCell( true );
	Call_Finish();
}

void SQL_LoadMap()
{
	g_iMapId = -1;

	char query[512];
	Format( query, sizeof(query), "SELECT mapid FROM `t_maps` WHERE mapname = '%s'", g_cMapName );
	g_hDatabase.Query( LoadMap_Callback, query );
}

public void LoadMap_Callback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadMap_Callback) - %s", error );
		return;
	}
	
	if( results.RowCount > 0 && results.FetchRow() )
	{
		g_iMapId = results.FetchInt( 0 );
		
		Call_StartForward( g_hForward_OnMapLoaded );
		Call_PushCell( g_iMapId );
		Call_Finish();
		
		char query[512];
		Format( query, sizeof(query), "UPDATE `t_maps` SET lastplayed = '%i', playcount = playcount + 1 WHERE mapid = '%i'", GetTime(), g_iMapId );
		
		g_hDatabase.Query( UpdateMap_Callback, query );
	}
	else
	{
		char query[512];
		Format( query, sizeof(query), "INSERT INTO `t_maps` (mapname, maptier, lastplayed, playcount) VALUE ('%s', '0', '%i', 1)", g_cMapName, GetTime() );
		
		g_hDatabase.Query( InsertMap_Callback, query );
	}
}

public void UpdateMap_Callback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdateMap_Callback) - %s", error );
		return;
	}
}

public void InsertMap_Callback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertMap_Callback) - %s", error );
		return;
	}
	
	g_iMapId = results.InsertId;
	
	Call_StartForward( g_hForward_OnMapLoaded );
	Call_PushCell( g_iMapId );
	Call_Finish();
}

/* Commands */

public Action Command_Noclip( int client, int args )
{
	g_bNoclip[client] = !g_bNoclip[client];
	
	if( g_bNoclip[client] )
	{
		SetEntityMoveType( client, MOVETYPE_NOCLIP );
		StopTimer( client );
	}
	else
	{
		SetEntityMoveType( client, MOVETYPE_WALK );
	}
	
	return Plugin_Handled;
}

public Action Command_Styles( int client, int args )
{
	Timer_OpenSelectStyleMenu( client, SetClientStyle );
	
	return Plugin_Handled;
}

public Action Command_ChangeStyle( int client, int args )
{
	char command[64];
	GetCmdArg( 0, command, sizeof( command ) );
	
	int style = 0;
	if( g_smStyleCommands.GetValue( command, style ) )
	{
		SetClientStyle( client, style );
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/* Natives */

public int Native_GetDatabase( Handle handler, int numParams )
{
	return view_as<int>(CloneHandle( g_hDatabase, handler ));
}

public int Native_GetMapId( Handle handler, int numParams )
{
	return g_iMapId;
}

public int Native_IsClientLoaded( Handle handler, int numParams )
{
	return g_iPlayerId[GetNativeCell( 1 )] > -1;
}

public int Native_GetClientPlayerId( Handle handler, int numParams )
{
	return g_iPlayerId[GetNativeCell( 1 )];
}

public int Native_GetClientTimerData( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );

	any data[TIMER_DATA_SIZE];
	data[Timer_FrameCount] = g_nPlayerFrames[client];
	data[Timer_Jumps] = g_nPlayerJumps[client];
	data[Timer_AirFrames] = g_nPlayerAirFrames[client];
	data[Timer_SyncedFrames] = g_nPlayerSyncedFrames[client];
	data[Timer_StrafedFrames] = g_nPlayerAirStrafeFrames[client];
	data[Timer_Strafes] = g_nPlayerStrafes[client];
	data[Timer_SSJ] = g_iPlayerSSJ[client];
	data[Timer_ZoneTrack] = Timer_GetClientZoneTrack( client );
	data[Timer_ZoneType] = Timer_GetClientZoneType( client );
	
	SetNativeArray( 2, data, TIMER_DATA_SIZE );
	
	return 1;
}

public int Native_SetClientTimerData( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	
	any data[TIMER_DATA_SIZE];
	GetNativeArray( 2, data, TIMER_DATA_SIZE );
	
	g_nPlayerFrames[client] = data[Timer_FrameCount];
	g_nPlayerJumps[client] = data[Timer_Jumps];
	g_nPlayerAirFrames[client] = data[Timer_AirFrames];
	g_nPlayerSyncedFrames[client] = data[Timer_SyncedFrames];
	g_nPlayerAirStrafeFrames[client] = data[Timer_StrafedFrames];
	g_nPlayerStrafes[client] = data[Timer_Strafes];
	g_iPlayerSSJ[client] = data[Timer_SSJ];
	Timer_SetClientZoneTrack( client, data[Timer_ZoneTrack] );
	Timer_SetClientZoneType( client, data[Timer_ZoneType] );
	
	if( Timer_GetClientZoneType( client ) == Zone_None )
	{
		g_bTimerRunning[client] = true;
		g_bTimerPaused[client] = false;
	}
	
	return 1;
}

public int Native_GetClientCurrentTime( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return view_as<int>( g_nPlayerFrames[client] * g_fFrameTime );
}

public int Native_GetClientCurrentJumps( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return g_nPlayerJumps[client];
}

public int Native_GetClientCurrentStrafes( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return g_nPlayerStrafes[client];
}

public int Native_GetClientCurrentSync( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return view_as<int>( ( g_nPlayerAirStrafeFrames[client] == 0 || g_nPlayerSyncedFrames[client] == 0 ) ? 100.0 : ( g_nPlayerSyncedFrames[client] * 100.0 ) / g_nPlayerAirStrafeFrames[client] );
}

public int Native_GetClientCurrentStrafeTime( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return view_as<int>( ( g_nPlayerAirFrames[client] == 0 || g_nPlayerAirStrafeFrames[client] == 0 ) ? 0.0 : ( g_nPlayerAirStrafeFrames[client] * 100.0 ) / g_nPlayerAirFrames[client] );
}

public int Native_GetClientCurrentSSJ( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return g_iPlayerSSJ[client];
}

public int Native_GetClientTimerStatus( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	
	if( !g_bTimerRunning[client] )
	{
		return view_as<int>( TimerStatus_Stopped );
	}
	else if( g_bTimerPaused[client] )
	{
		return view_as<int>( TimerStatus_Paused );
	}
	
	return view_as<int>( TimerStatus_Running );
}

public int Native_GetStyleCount( Handle handler, int numParams )
{
	return g_iTotalStyles;
}

public int Native_GetStyleSettings( Handle handler, int numParams )
{
	SetNativeArray( 2, g_StyleSettings[GetNativeCell( 1 )], styleSettings );
}

public int Native_GetStyleName( Handle handler, int numParams )
{
	SetNativeString( 2, g_StyleSettings[GetNativeCell( 1 )][StyleName], GetNativeCell( 3 ) );
}

public int Native_GetStylePrefix( Handle handler, int numParams )
{
	SetNativeString( 2, g_StyleSettings[GetNativeCell( 1 )][StylePrefix], GetNativeCell( 3 ) );
}

public int Native_StyleHasSetting( Handle handler, int numParams )
{
	char settingString[24];
	GetNativeString( 2, settingString, sizeof(settingString) );
	
	int dummy;
	return g_StyleSettingStrings[GetNativeCell( 1 )].GetValue( settingString, dummy );
}

public int Native_SetClientStyle( Handle handler, int numParams )
{
	SetClientStyle( GetNativeCell( 1 ), GetNativeCell( 2 ) );
	
	return 1;
}

public int Native_GetClientStyle( Handle handler, int numParams )
{
	return g_PlayerCurrentStyle[GetNativeCell( 1 )];
}

public int Native_IsTimerRunning( Handle handler, int numParams )
{
	return g_bTimerRunning[GetNativeCell( 1 )] && !g_bTimerPaused[GetNativeCell( 1 )];
}

public int Native_StopTimer( Handle handler, int numParams )
{
	StopTimer( GetNativeCell( 1 ) );
}

public int Native_BlockTimer( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );

	g_iClientBlockTickStart[client] = GetGameTickCount();
	g_nClientBlockTicks[client] = GetNativeCell( 2 );
}
