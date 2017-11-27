#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>
#include <sdktools>

#define MAX_WR_CACHE 50

public Plugin myinfo = 
{
	name = "Slidy's Timer - Core component",
	author = "SlidyBat",
	description = "Core component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

Database		g_hDatabase;

float		g_fFrameTime;
char			g_cMapName[PLATFORM_MAX_PATH];

Handle		g_hForward_OnDatabaseLoaded;
Handle		g_hForward_OnClientLoaded;
Handle		g_hForward_OnStylesLoaded;
Handle		g_hForward_OnStyleChangedPre;
Handle		g_hForward_OnStyleChangedPost;

int			g_ClientPlayerID[MAXPLAYERS + 1];
bool			g_bClientLoaded[MAXPLAYERS + 1];

ArrayList    g_aMapRecords[TOTAL_ZONE_TRACKS][MAX_STYLES];

any			g_StyleSettings[MAX_STYLES][StyleSettings];
StringMap	g_smStyleCommands;
int			g_iTotalStyles;

/* Player Data */
any			g_PlayerRecordData[MAXPLAYERS + 1][TOTAL_ZONE_TRACKS][MAX_STYLES][RecordData];
int			g_PlayerCurrentStyle[MAXPLAYERS + 1];
int			g_nPlayerFrames[MAXPLAYERS + 1];
bool			g_bTimerRunning[MAXPLAYERS + 1]; // whether client timer is running or not, regardless of if its paused
bool			g_bTimerPaused[MAXPLAYERS + 1];

/* PLAYER RECORD DATA */
int			g_nPlayerJumps[MAXPLAYERS + 1];
int			g_nPlayerStrafes[MAXPLAYERS + 1];
int			g_iPlayerSSJ[MAXPLAYERS + 1];
int			g_nPlayerSyncedFrames[MAXPLAYERS + 1];
int			g_nPlayerAirFrames[MAXPLAYERS + 1];
int			g_nPlayerAirStrafeFrames[MAXPLAYERS + 1];

ConVar		sv_autobunnyhopping;
bool			g_bNoclip[MAXPLAYERS + 1];

public void OnPluginStart()
{
	/* Forwards */
	g_hForward_OnDatabaseLoaded = CreateGlobalForward( "Timer_OnDatabaseLoaded", ET_Event );
	g_hForward_OnClientLoaded = CreateGlobalForward( "Timer_OnClientLoaded", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnStylesLoaded = CreateGlobalForward( "Timer_OnStylesLoaded", ET_Event, Param_Cell );
	g_hForward_OnStyleChangedPre = CreateGlobalForward( "Timer_OnStyleChangedPre", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnStyleChangedPost = CreateGlobalForward( "Timer_OnStyleChangedPost", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	
	/* Commands */
	RegConsoleCmd( "sm_nc", Command_Noclip );
	
	RegConsoleCmd( "sm_style", Command_Styles );
	RegConsoleCmd( "sm_styles", Command_Styles );
	
	RegConsoleCmd( "sm_pb", Command_PB );
	RegConsoleCmd( "sm_bpb", Command_Bonus_PB );
	RegConsoleCmd( "sm_wr", Command_WR );
	RegConsoleCmd( "sm_bwr", Command_Bonus_WR );
	
	/* Hooks */
	HookEvent( "player_jump", HookEvent_PlayerJump );
	
	for( int i = 0; i < view_as<int>( TOTAL_ZONE_TRACKS ); i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_aMapRecords[i][j] = new ArrayList( sizeof( g_PlayerRecordData[][][] ) );
		}
	}
	
	SQL_DBConnect();
	
	g_fFrameTime = GetTickInterval();
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	CreateNative( "Timer_GetClientCurrentTime", Native_GetClientCurrentTime );
	CreateNative( "Timer_GetClientCurrentJumps", Native_GetClientCurrentJumps );
	CreateNative( "Timer_GetClientCurrentStrafes", Native_GetClientCurrentStrafes );
	CreateNative( "Timer_GetClientCurrentSync", Native_GetClientCurrentSync );
	CreateNative( "Timer_GetClientCurrentStrafeTime", Native_GetClientCurrentStrafeTime );
	CreateNative( "Timer_GetWRTime", Native_GetWRTime );
	CreateNative( "Timer_GetWRName", Native_GetWRName );
	CreateNative( "Timer_GetClientPBTime", Native_GetClientPBTime );
	CreateNative( "Timer_GetClientStyle", Native_GetClientStyle );
	CreateNative( "Timer_GetStyleName", Native_GetStyleName );
	CreateNative( "Timer_GetClientTimerStatus", Native_GetClientTimerStatus );
	CreateNative( "Timer_GetClientRank", Native_GetClientRank );
	CreateNative( "Timer_GetDatabase", Native_GetDatabase );
	CreateNative( "Timer_IsClientLoaded", Native_IsClientLoaded );
	CreateNative( "Timer_StopTimer", Native_StopTimer );

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
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
	
	for( int i = 0; i < view_as<int>( TOTAL_ZONE_TRACKS ); i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_aMapRecords[i][j].Clear();
			SQL_ReloadCache( view_as<ZoneTrack>( i ), j );
		}
	}
}

public void OnClientPostAdminCheck( int client )
{
	if( !IsFakeClient( client ) )
	{
		SQL_LoadPlayerID( client );
	}
	
	StopTimer( client );
}

public void OnClientDisconnect( int client )
{
	g_bClientLoaded[client] = false;
}

public void Timer_OnClientLoaded( int client, int playerid, bool newplayer )
{
	for( int i = 0; i < view_as<int>( TOTAL_ZONE_TRACKS ); i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_PlayerRecordData[client][i][j][RD_PlayerID] = playerid;
			GetClientName( client, g_PlayerRecordData[client][i][j][RD_Name], MAX_NAME_LENGTH );
			SQL_LoadRecords( client, view_as<ZoneTrack>( i ), j );
		}
	}
	
	ClearPlayerData( client );
	
	g_bClientLoaded[client] = true;
}

public Action OnPlayerRunCmd( int client, int& buttons, int& impulse, float vel[3], float angles[3] )
{
	if( IsValidClient( client, true ) )
	{	
		static any styleSettings[StyleSettings];
		styleSettings = g_StyleSettings[g_PlayerCurrentStyle[client]];
		
		static int lastButtons[MAXPLAYERS + 1];
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
				
				if( styleSettings[Sync] &&
					( ( fDeltaYaw > 0.0 && ( buttons & IN_MOVELEFT ) && !( buttons & IN_MOVERIGHT ) ) ||
					( fDeltaYaw < 0.0 && ( buttons & IN_MOVERIGHT ) && !( buttons & IN_MOVELEFT ) ) ) )
				{
					g_nPlayerSyncedFrames[client]++;
				}
			}
			
			if( styleSettings[HSW] )
			{
				if( ( buttons & IN_FORWARD ) && ( lastButtons[client] & IN_FORWARD ) )
				{
					if( !( lastButtons[client] & IN_LEFT ) && ( buttons & IN_LEFT ) )
					{
						g_nPlayerStrafes[client]++;
					}
					else if( !( lastButtons[client] & IN_RIGHT ) && ( buttons & IN_RIGHT ) )
					{
						g_nPlayerStrafes[client]++;
					}
				}
			}
			else
			{
				if( styleSettings[CountLeft] && !( lastButtons[client] & IN_LEFT ) && ( buttons & IN_LEFT ) )
				{
					g_nPlayerStrafes[client]++;
				}
				else if( styleSettings[CountRight] && !( lastButtons[client] & IN_RIGHT ) && ( buttons & IN_RIGHT ) )
				{
					g_nPlayerStrafes[client]++;
				}
				else if( styleSettings[CountForward] && !( lastButtons[client] & IN_FORWARD ) && ( buttons & IN_FORWARD ) )
				{
					g_nPlayerStrafes[client]++;
				}
				else if( styleSettings[CountBack] && !( lastButtons[client] & IN_BACK ) && ( buttons & IN_BACK ) )
				{
					g_nPlayerStrafes[client]++;
				}
			}
		}
		
		if( Timer_GetClientZoneType( client ) == Zone_Start )
		{
			if( buttons & IN_JUMP && !styleSettings[StartBhop] )
			{
				buttons &= ~IN_JUMP;
			}
			
			if( styleSettings[PreSpeed] != 0.0 && GetClientSpeedSq( client ) > styleSettings[PreSpeed]*styleSettings[PreSpeed] )
			{
				float speed = GetClientSpeed( client );
				float scale = styleSettings[PreSpeed] / speed;
				
				float vVel[3];
				GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vVel);
				ScaleVector( vVel, scale );
				
				TeleportEntity( client, NULL_VECTOR, NULL_VECTOR, vVel );
			}
		}
		
		if( buttons & IN_JUMP )
		{
			if( !( GetEntityMoveType( client ) & MOVETYPE_LADDER )
				&& !( GetEntityFlags( client ) & FL_ONGROUND )
				&& ( GetEntProp( client, Prop_Data, "m_nWaterLevel" ) < 2 ) )
			{
				buttons &= ~IN_JUMP;
			}
		}
		
		// blocking keys (only in air)
		if( !( GetEntityFlags( client ) & FL_ONGROUND ) && GetEntityMoveType( client ) == MOVETYPE_WALK )
		{
			if( styleSettings[PreventLeft] && ( buttons & IN_LEFT ) ||
				styleSettings[PreventRight] && ( buttons & IN_RIGHT ) ||
				styleSettings[PreventForward] && ( buttons & IN_FORWARD ) ||
				styleSettings[PreventBack] && ( buttons & IN_BACK ) )
			{
				bButtonError = true;
			}
			else if( styleSettings[HSW] && 
					!( ( buttons & IN_FORWARD ) && ( ( buttons & IN_LEFT ) || ( buttons & IN_RIGHT ) ) ) )
			{
				bButtonError = true;
			}
		}
		
		if( bButtonError )
		{
			vel[0] = 0.0;
			vel[1] = 0.0;
		}
		
		lastButtons[client] = buttons;
		lastYaw[client] = angles[1];
	}
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
	if( g_bNoclip[client] )
	{
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
	// e.g. in TAS
	
	g_bTimerRunning[client] = false;
	g_bTimerPaused[client] = false;
}

void FinishTimer( int client )
{
	if( !IsValidClient( client ) )
	{
		return;
	}
	
	char sTime[64];
	float time = g_nPlayerFrames[client] * g_fFrameTime;
	Timer_FormatTime( time, sTime, sizeof( sTime ) );
	
	StopTimer( client );
	
	ZoneTrack ztTrack = Timer_GetClientZoneTrack( client );
	char sZoneTrack[64];
	Timer_GetZoneTrackName( ztTrack, sZoneTrack, sizeof( sZoneTrack ) );
	int track = view_as<int>( ztTrack );
	
	int style = g_PlayerCurrentStyle[client];
	
	float pb = g_PlayerRecordData[client][track][style][RD_Time];
	float wr = 0.0;
	if( g_aMapRecords[track][style].Length )
	{
		any wrRecordData[RecordData];
		g_aMapRecords[track][style].GetArray( 0, wrRecordData[0] );
		wr = wrRecordData[RD_Time];
	}
	
	PrintToChatAll( "[%s] %N finished on %s timer in %ss", g_StyleSettings[style][StyleName], client, sZoneTrack, sTime );
	
	if( pb == 0.0 || time < pb ) // new record, save it
	{	
		// avoid dividing by 0
		float sync = ( g_nPlayerAirStrafeFrames[client] == 0 ) ? 100.0 : float( g_nPlayerSyncedFrames[client] * 100 ) / g_nPlayerAirStrafeFrames[client];
		float strafetime = ( g_nPlayerAirFrames[client] == 0 ) ? 0.0   : float( g_nPlayerAirStrafeFrames[client] * 100 ) / g_nPlayerAirFrames[client];
		
		g_PlayerRecordData[client][track][style][RD_Timestamp] = GetTime();
		g_PlayerRecordData[client][track][style][RD_Time] = time;
		g_PlayerRecordData[client][track][style][RD_Jumps] = g_nPlayerJumps[client];
		g_PlayerRecordData[client][track][style][RD_Strafes] = g_nPlayerStrafes[client];
		g_PlayerRecordData[client][track][style][RD_Sync] = sync;
		g_PlayerRecordData[client][track][style][RD_StrafeTime] = strafetime;
		g_PlayerRecordData[client][track][style][RD_SSJ] = g_iPlayerSSJ[client];
		
		if( pb == 0.0 ) // new time
		{
			SQL_InsertRecord( client, ztTrack, style, time );
		}
		else // existing time but beaten
		{
			SQL_UpdateRecord( client, ztTrack, style, time );
		}
		
		if( wr == 0.0 || time < wr )
		{
			PrintToChatAll( "NEW WR!!!!!" );
		}
		else
		{
			PrintToChatAll( "NEW PB!!!" );
		}
	}
	
	SQL_ReloadCache( ztTrack, style );
}

stock int GetRankForTime( float time, ZoneTrack ztTrack, int style )
{
	if( time == 0.0 )
	{
		return 0;
	}
	
	int track = view_as<int>( ztTrack );
	if( g_aMapRecords[track][style].Length == 0 )
	{
		return 1;
	}
	
	any recordData[RecordData];
	for( int i = 0; i < g_aMapRecords[track][style].Length; i++ )
	{
		g_aMapRecords[track][style].GetArray( i, recordData[0] );
		if( time < recordData[RD_Time] )
		{
			return ++i;
		}
	}
	
	return g_aMapRecords[track][style].Length + 1;
}

stock int GetClientRank( int client, ZoneTrack track, int style )
{
	// subtract 1 because when times are equal, it counts as next rank
	return GetRankForTime( g_PlayerRecordData[client][view_as<int>( track )][style][RD_Time], track, style ) - 1;
}

bool LoadStyles()
{
	g_iTotalStyles = 0;
	
	delete g_smStyleCommands;
	g_smStyleCommands = new StringMap();

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
		kvStyles.GetString( "specialid", g_StyleSettings[g_iTotalStyles][SpecialId], 16 );

		g_StyleSettings[g_iTotalStyles][Ranked] = view_as<bool>( kvStyles.GetNum( "ranked" ) );
		g_StyleSettings[g_iTotalStyles][AutoBhop] = view_as<bool>( kvStyles.GetNum( "autobhop" ) );
		g_StyleSettings[g_iTotalStyles][StartBhop] = view_as<bool>( kvStyles.GetNum( "startbhop" ) );

		g_StyleSettings[g_iTotalStyles][Gravity] = kvStyles.GetFloat( "gravity" );
		g_StyleSettings[g_iTotalStyles][Timescale] = kvStyles.GetFloat( "timescale" );
		g_StyleSettings[g_iTotalStyles][MaxSpeed] = kvStyles.GetFloat( "maxspeed" );
		g_StyleSettings[g_iTotalStyles][Fov] = kvStyles.GetNum( "fov" );

		g_StyleSettings[g_iTotalStyles][Sync] = view_as<bool>( kvStyles.GetNum( "sync" ) );

		g_StyleSettings[g_iTotalStyles][PreventLeft] = view_as<bool>( kvStyles.GetNum( "prevent_left" ) );
		g_StyleSettings[g_iTotalStyles][PreventRight] = view_as<bool>( kvStyles.GetNum( "prevent_right" ) );
		g_StyleSettings[g_iTotalStyles][PreventForward] = view_as<bool>( kvStyles.GetNum( "prevent_forward" ) );
		g_StyleSettings[g_iTotalStyles][PreventBack] = view_as<bool>( kvStyles.GetNum( "prevent_back" ) );

		g_StyleSettings[g_iTotalStyles][CountLeft] = view_as<bool>( kvStyles.GetNum( "count_left" ) );
		g_StyleSettings[g_iTotalStyles][CountRight] = view_as<bool>( kvStyles.GetNum( "count_right" ) );
		g_StyleSettings[g_iTotalStyles][CountForward] = view_as<bool>( kvStyles.GetNum( "count_forward" ) );
		g_StyleSettings[g_iTotalStyles][CountBack] = view_as<bool>( kvStyles.GetNum( "count_back" ) );
		
		g_StyleSettings[g_iTotalStyles][HSW] = view_as<bool>( kvStyles.GetNum( "hsw" ) );

		g_StyleSettings[g_iTotalStyles][PreSpeed] = kvStyles.GetFloat( "prespeed" );

		g_StyleSettings[g_iTotalStyles][StyleId] = g_iTotalStyles;
		g_StyleSettings[g_iTotalStyles][ExpMultiplier] = kvStyles.GetFloat( "expmultiplier" );

		
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

void SetClientStyle( int client, int style )
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
	
	Timer_TeleportClientToZone( client, Zone_Start, ZT_Main );
	
	PrintToChat( client, "[Timer] Style now: %s", g_StyleSettings[style][StyleName] );
	
	Call_StartForward( g_hForward_OnStyleChangedPost );
	Call_PushCell( client );
	Call_PushCell( oldstyle );
	Call_PushCell( style );
	Call_Finish();
}

void OpenSelectStyleMenu( int client, MenuHandler handler )
{
	Menu menu = new Menu( handler );
	menu.SetTitle( "Select Style:\n \n" );
	
	for( int i = 0; i < g_iTotalStyles; i++ )
	{
		menu.AddItem( "style", g_StyleSettings[i][StyleName] );
	}
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public void Timer_OnEnterZone( int client, int id, ZoneType zoneType, ZoneTrack zoneTrack, int subindex )
{
	switch( zoneType )
	{
		case Zone_Start:
		{
		}
		case Zone_End:
		{
			if( g_bTimerRunning[client] && !g_bTimerPaused[client] && Timer_GetClientZoneTrack( client ) == zoneTrack )
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

public void Timer_OnExitZone( int client, int id, ZoneType zoneType, ZoneTrack zoneTrack, int subindex )
{
	switch( zoneType )
	{
		case Zone_Start:
		{
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
	int client = GetClientOfUserId( event.GetInt( "userid" ) );
	if( g_bTimerRunning[client] && !g_bTimerPaused[client] ) // TODO: consider making this a function (and possibly native)
	{	
		if( ++g_nPlayerJumps[client] == 6 )
		{
			g_iPlayerSSJ[client] = RoundFloat( GetClientSpeed( client ) );
		}
	}
}

/* Database stuff */

void SQL_DBConnect()
{
	delete g_hDatabase;
	
	char[] error = new char[255];
	g_hDatabase = SQL_Connect( "Slidy-Timer", true, error, 255 );

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
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_players` ( playerid INT NOT NULL AUTO_INCREMENT, \
																			steamid CHAR( 32 ) NOT NULL, \
																			lastname CHAR( 64 ) NOT NULL, \
																			firstconnect INT( 16 ) NOT NULL, \
																			lastconnect INT( 16 ) NOT NULL, \
																			PRIMARY KEY ( `playerid` ) );" );
	txn.AddQuery( query );
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_records` ( mapname CHAR( 128 ) NOT NULL, \
																			playerid INT NOT NULL, \
																			timestamp INT( 16 ) NOT NULL, \
																			time FLOAT NOT NULL, \
																			track INT NOT NULL, \
																			style INT NOT NULL, \
																			jumps INT NOT NULL, \
																			strafes INT NOT NULL, \
																			sync FLOAT NOT NULL, \
																			strafetime FLOAT NOT NULL, \
																			ssj INT NOT NULL, \
																			PRIMARY KEY ( `mapname`, `playerid`, `style`, `track` ) );" );
	txn.AddQuery( query );
	
	g_hDatabase.Execute( txn, SQL_OnCreateTableSuccess, SQL_OnCreateTableFailure, _, DBPrio_High );
}

public void SQL_OnCreateTableSuccess( Database db, any data, int numQueries, DBResultSet[] results, any[] queryData )
{
	//SQL_LoadPlayerData();
}

public void SQL_OnCreateTableFailure( Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData )
{
	SetFailState( "[SQL ERROR] (SQL_CreateTables) - %s", error );
}

void SQL_LoadPlayerID( int client )
{
	char steamid[32];
	GetClientAuthId( client, AuthId_Steam2, steamid, sizeof( steamid ) );
	
	char query[128];
	Format( query, sizeof( query ), "SELECT playerid FROM `t_players` WHERE steamid = '%s'", steamid );
	
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
	
	if( !IsValidClient( client ) ) // client no longer valid since id loaded :(
	{
		return;
	}
	
	if( results.RowCount ) // playerid already exists, this is returning user
	{
		if( results.FetchRow() )
		{
			char name[MAX_NAME_LENGTH * 2 + 1]; // worst case: every character is escaped + null character
			GetClientName( client, name, sizeof( name ) );
			g_hDatabase.Escape( name, name, sizeof( name ) );
			
			g_ClientPlayerID[client] = results.FetchInt( 0 );
			
			// update info
			char query[256];
			Format( query, sizeof( query ), "UPDATE `t_players` SET lastname = '%s', lastconnect = '%i' WHERE playerid = '%i';", name, GetTime(), g_ClientPlayerID[client] );
			
			g_hDatabase.Query( UpdatePlayerInfo_Callback, query, uid, DBPrio_Normal );
		}
	}
	else  // new user
	{
		int timestamp = GetTime();
		
		char name[MAX_NAME_LENGTH * 2 + 1]; // worst case: every character is escaped + null character
		GetClientName( client, name, sizeof( name ) );
		g_hDatabase.Escape( name, name, sizeof( name ) );
		
		char steamid[32];
		GetClientAuthId( client, AuthId_Steam2, steamid, sizeof( steamid ) );

		char query[256];
		Format( query, sizeof( query ), "INSERT INTO `t_players` VALUES ( 0, '%s', '%s', '%i', '%i' );", steamid, name, timestamp, timestamp );
		
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
	
	Call_StartForward( g_hForward_OnClientLoaded );
	Call_PushCell( client );
	Call_PushCell( g_ClientPlayerID[client] );
	Call_PushCell( false );
	Call_Finish();
}

public void InsertPlayerInfo_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdatePlayerInfo_Callback) - %s", error );
		return;
	}
	
	int client = GetClientOfUserId( uid );
	
	Call_StartForward( g_hForward_OnClientLoaded );
	Call_PushCell( client );
	Call_PushCell( g_ClientPlayerID[client] );
	Call_PushCell( true );
	Call_Finish();
}

void SQL_LoadRecords( int client, ZoneTrack track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "SELECT timestamp, time, jumps, strafes, sync, strafetime, ssj FROM `t_records` WHERE playerid = '%i' AND track = '%i' AND style = '%i' AND mapname = '%s'", g_ClientPlayerID[client], track, style, g_cMapName );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	g_hDatabase.Query( LoadRecords_Callback, query, pack, DBPrio_High );
}

public void LoadRecords_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadRecords_Callback) - %s", error );
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	if( !IsValidClient( client ) )
	{
		return;
	}
	
	while( results.FetchRow() )
	{
		g_PlayerRecordData[client][track][style][RD_Timestamp] = results.FetchInt( 0 );
		g_PlayerRecordData[client][track][style][RD_Time] = results.FetchFloat( 1 );
		g_PlayerRecordData[client][track][style][RD_Jumps] = results.FetchInt( 2 );
		g_PlayerRecordData[client][track][style][RD_Strafes] = results.FetchInt( 3 );
		g_PlayerRecordData[client][track][style][RD_Sync] = results.FetchFloat( 4 );
		g_PlayerRecordData[client][track][style][RD_StrafeTime] = results.FetchFloat( 5 );
		g_PlayerRecordData[client][track][style][RD_SSJ] = results.FetchInt( 6 );
	}
}

void SQL_InsertRecord( int client, ZoneTrack track, int style, float time )
{
	float sync = g_PlayerRecordData[client][view_as<int>( track )][style][RD_Sync];
	float strafetime = g_PlayerRecordData[client][view_as<int>( track )][style][RD_StrafeTime];
	
	char query[256];
	Format( query, sizeof( query ), "INSERT INTO `t_records` (mapname, playerid, track, style, timestamp, time, jumps, strafes, sync, strafetime, ssj) \
													VALUES ('%s', '%i', '%i', '%i', '%i', '%.5f', '%i', '%i', '%.2f', '%.2f', '%i')",
													g_cMapName,
													g_ClientPlayerID[client],
													view_as<int>( track ),
													style,
													GetTime(),
													time,
													g_nPlayerJumps[client],
													g_nPlayerStrafes[client],
													sync,
													strafetime,
													g_iPlayerSSJ[client]);
	
	g_hDatabase.Query( InsertRecord_Callback, query, _, DBPrio_High );
}

public void InsertRecord_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertRecord_Callback) - %s", g_ClientPlayerID[GetClientOfUserId( uid )], error );
		return;
	}
}

void SQL_UpdateRecord( int client, ZoneTrack track, int style, float time )
{
	float sync = g_PlayerRecordData[client][view_as<int>( track )][style][RD_Sync];
	float strafetime = g_PlayerRecordData[client][view_as<int>( track )][style][RD_StrafeTime];
	
	char query[256];
	Format( query, sizeof( query ), "UPDATE `t_records` SET timestamp = '%i', time = '%f', jumps = '%i', strafes = '%i', sync = '%f', strafetime = '%f', ssj = '%i' \
													WHERE playerid = '%i' AND track = '%i' AND style = '%i' AND mapname = '%s'",
													GetTime(),
													time,
													g_nPlayerJumps[client],
													g_nPlayerStrafes[client],
													sync,
													strafetime,
													g_iPlayerSSJ[client],
													g_ClientPlayerID[client],
													view_as<int>( track ),
													style,
													g_cMapName );
	
	g_hDatabase.Query( UpdateRecord_Callback, query, _, DBPrio_High );
}

public void UpdateRecord_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdateRecord_Callback) - %s", error );
		return;
	}
}

void SQL_DeleteRecord( int playerid, ZoneTrack track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "DELETE FROM `t_records` WHERE playerid = '%i' AND track = '%i' AND style = '%i'", playerid, track, style );
	
	DataPack pack = new DataPack();
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	g_hDatabase.Query( DeleteRecord_Callback, query, pack, DBPrio_Normal );
}

public void DeleteRecord_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (DeleteRecord_Callback) - %s", error );
		return;
	}
	
	pack.Reset();
	ZoneTrack track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	SQL_ReloadCache( track, style );
}

void SQL_ReloadCache( ZoneTrack track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "SELECT p.lastname, r.playerid, r.timestamp, r.time, r.jumps, r.strafes, r.sync, r.strafetime, r.ssj \
									FROM `t_records` r JOIN `t_players` p ON p.playerid = r.playerid \
									WHERE mapname = '%s' AND track = '%i' AND style = '%i'\
									ORDER BY r.time ASC", g_cMapName, view_as<int>( track ), style );
	
	DataPack pack = new DataPack();
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	g_hDatabase.Query( CacheRecords_Callback, query, pack, DBPrio_High );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_bClientLoaded[i] )
		{
			SQL_LoadRecords( i, track, style );
		}
	}
}

public void CacheRecords_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (CacheRecords_Callback) - %s", error );
		return;
	}
	
	pack.Reset();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	g_aMapRecords[track][style].Clear();
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		g_PlayerRecordData[i][track][style][RD_Time] = 0.0;
	}
	
	while( results.FetchRow() )
	{
		static any recordData[RecordData];
		
		results.FetchString( 0, recordData[RD_Name], MAX_NAME_LENGTH );
		recordData[RD_PlayerID] = results.FetchInt( 1 );
		recordData[RD_Timestamp] = results.FetchInt( 2 );
		recordData[RD_Time] = results.FetchFloat( 3 );
		recordData[RD_Jumps] = results.FetchInt( 4 );
		recordData[RD_Strafes] = results.FetchInt( 5 );
		recordData[RD_Sync] = results.FetchFloat( 6 );
		recordData[RD_StrafeTime] = results.FetchFloat( 7 );
		recordData[RD_SSJ] = results.FetchInt( 8 );
		
		g_aMapRecords[track][style].PushArray( recordData[0] );
	}
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
}

public Action Command_Styles( int client, int args )
{
	OpenSelectStyleMenu( client, ChangeStyle_Handler );
	
	return Plugin_Handled;
}

public int ChangeStyle_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		SetClientStyle( param1, param2 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
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

public Action Command_PB( int client, int args )
{
	OpenSelectStyleMenu( client, ShowPB_Handler );
	
	return Plugin_Handled;
}

public int ShowPB_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		if( g_PlayerRecordData[param1][view_as<int>( ZT_Main )][param2][RD_Time] != 0.0 )
		{
			ShowStats( param1, ZT_Main, param2, g_PlayerRecordData[param1][view_as<int>( ZT_Main )][param2] );
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

public Action Command_Bonus_PB( int client, int args )
{
	OpenSelectStyleMenu( client, ShowBonusPB_Handler );
	
	return Plugin_Handled;
}

public int ShowBonusPB_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		ShowStats( param1, ZT_Bonus, param2, g_PlayerRecordData[param1][view_as<int>( ZT_Bonus )][param2] );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

public Action Command_WR( int client, int args )
{
	OpenSelectStyleMenu( client, ShowWR_Handler );
	
	return Plugin_Handled;
}

public int ShowWR_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		ShowLeaderboard( param1, ZT_Main, param2 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

public Action Command_Bonus_WR( int client, int args )
{
	OpenSelectStyleMenu( client, ShowBonusWR_Handler );
	
	return Plugin_Handled;
}

public int ShowBonusWR_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		ShowLeaderboard( param1, ZT_Bonus, param2 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void ShowLeaderboard( int client, ZoneTrack ztTrack, int style )
{
	int track = view_as<int>( ztTrack );
	if( !g_aMapRecords[track][style].Length )
	{
		return;
	}
	
	Menu menu = new Menu( WRMenu_Handler );
	
	char trackName[32];
	Timer_GetZoneTrackName( ztTrack, trackName, sizeof( trackName ) );
	
	char buffer[256];
	Format( buffer, sizeof( buffer ), "%s %s %s Leaderboard", trackName, g_StyleSettings[style][StyleName], g_cMapName );
	menu.SetTitle( buffer );
	
	char sTime[32], info[8];
	
	int max = ( MAX_WR_CACHE > g_aMapRecords[track][style].Length ) ? g_aMapRecords[track][style].Length : MAX_WR_CACHE;
	for( int i = 0; i < max; i++ )
	{
		static any recordData[RecordData];
		g_aMapRecords[track][style].GetArray( i, recordData[0] );
		
		Timer_FormatTime( recordData[RD_Time], sTime, sizeof( sTime ) );
		Format( buffer, sizeof( buffer), "[#%i] - %s (%s)", i + 1, recordData[RD_Name], sTime );
		
		Format( info, sizeof( info ), "%i,%i", track, style );
		
		menu.AddItem( info, buffer );
	}
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int WRMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char info[8];
		menu.GetItem( param2, info, sizeof( info ) );
		
		char infoSplit[2][4];
		ExplodeString( info, ",", infoSplit, sizeof( infoSplit ), sizeof( infoSplit[] ) );
		
		int track = StringToInt( infoSplit[0] );
		int style = StringToInt( infoSplit[1] );
		
		any recordData[RecordData];
		g_aMapRecords[track][style].GetArray( 0, recordData[0] );
		ShowStats( param1, view_as<ZoneTrack>( track ), style, recordData );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void ShowStats( int client, ZoneTrack track, int style, const any recordData[RecordData] )
{
	Menu menu = new Menu( RecordInfo_Handler );
		
	char date[128];
	FormatTime( date, sizeof( date ), "%d/%m/%Y - %H:%M:%S", recordData[RD_Timestamp] );
	char sTime[64];
	Timer_FormatTime( recordData[RD_Time], sTime, sizeof( sTime ) );
	
	char sTrack[16];
	Timer_GetZoneTrackName( track, sTrack, sizeof( sTrack ) );
	
	char sSync[10];
	if( g_StyleSettings[style][Sync] )
	{
		Format( sSync, sizeof( sSync ), "(%.2f)", recordData[RD_Sync] );
	}
	
	char sInfo[16];
	Format( sInfo, sizeof( sInfo ), "%i,%i,%i", recordData[RD_PlayerID], track, style );
	
	char buffer[512];
	Format( buffer, sizeof( buffer ), "%s - %s %s\n \n", g_cMapName, sTrack, g_StyleSettings[style][StyleName] );
	menu.SetTitle( buffer );
	
	Format( buffer, sizeof( buffer ), "Player: %s\n", recordData[RD_Name] );
	Format( buffer, sizeof( buffer ), "%sDate: %s\n \n", buffer, date );
	Format( buffer, sizeof( buffer ), "%sTime: %s\n \n", buffer, sTime );
	Format( buffer, sizeof( buffer ), "%sJumps: %i\n", buffer, recordData[RD_Jumps] );
	Format( buffer, sizeof( buffer ), "%sStrafes: %i %s\n", buffer, recordData[RD_Strafes], sSync );
	Format( buffer, sizeof( buffer ), "%sStrafe Time %: %.2f\n", buffer, recordData[RD_StrafeTime] );
	Format( buffer, sizeof( buffer ), "%sSSJ: %i\n \n", buffer, recordData[RD_SSJ] );
	menu.AddItem( sInfo, buffer );
	
	if( CheckCommandAccess( client, "delete_time", ADMFLAG_RCON ) )
	{
		menu.AddItem( "delete", "Delete Time" );
	}
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int RecordInfo_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char sInfo[16];
		menu.GetItem( 0, sInfo, sizeof( sInfo ) );
		
		char sSplitString[3][16];
		ExplodeString( sInfo, ",", sSplitString, sizeof( sSplitString ), sizeof( sSplitString[] ) );
		
		int playerid = StringToInt( sSplitString[0] );
		ZoneTrack track = view_as<ZoneTrack>( StringToInt( sSplitString[1] ) );
		int style = StringToInt( sSplitString[2] );
		
		switch( param2 )
		{
			case 0: // TODO: implement showing player stats here
			{}
			case 1: // delete time
			{
				SQL_DeleteRecord( playerid, track, style );
			}
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

/* Natives */

public int Native_GetDatabase( Handle handler, int numParams )
{
	return view_as<int>( CloneHandle( g_hDatabase, handler ) );
}

public int Native_GetClientCurrentTime( Handle handler, int numparams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return view_as<int>( g_nPlayerFrames[client] * g_fFrameTime );
}

public int Native_GetClientCurrentJumps( Handle handler, int numparams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return g_nPlayerJumps[client];
}

public int Native_GetClientCurrentStrafes( Handle handler, int numparams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return g_nPlayerStrafes[client];
}

public int Native_GetClientCurrentSync( Handle handler, int numparams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return view_as<int>( ( g_nPlayerAirStrafeFrames[client] == 0 ) ? 100.0 : float( g_nPlayerSyncedFrames[client] * 100 ) / g_nPlayerAirStrafeFrames[client] );
}

public int Native_GetClientCurrentStrafeTime( Handle handler, int numparams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return view_as<int>( ( g_nPlayerAirFrames[client] == 0 ) ? 0.0 : float( g_nPlayerAirStrafeFrames[client] * 100 ) / g_nPlayerAirFrames[client] );
}

public int Native_GetWRTime( Handle handler, int numparams )
{
	int track = GetNativeCell( 1 );
	int style = GetNativeCell( 2 );
	
	if( g_aMapRecords[track][style].Length )
	{
		any recordData[RecordData];
		g_aMapRecords[track][style].GetArray( 0, recordData[0] );
		
		return view_as<int>( recordData[RD_Time] );
	}
	
	return 0;
}

public int Native_GetWRName( Handle handler, int numparams )
{
	int track = GetNativeCell( 1 );
	int style = GetNativeCell( 2 );
	
	if( g_aMapRecords[track][style].Length )
	{
		any recordData[RecordData];
		g_aMapRecords[track][style].GetArray( 0, recordData[0] );
		
		SetNativeString( 3, recordData[RD_Name], GetNativeCell( 4 ) );
	}
}

public int Native_GetClientPBTime( Handle handler, int numparams )
{
	return view_as<int>( g_PlayerRecordData[GetNativeCell( 1 )][GetNativeCell( 2 )][GetNativeCell( 3 )][RD_Time] );
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

public int Native_GetClientRank( Handle handler, int numParams )
{
	return GetClientRank( GetNativeCell( 1 ), GetNativeCell( 2 ), GetNativeCell( 3 ) );
}

public int Native_GetStyleName( Handle handler, int numParams )
{
	SetNativeString( 2, g_StyleSettings[GetNativeCell( 1 )][StyleName], GetNativeCell( 3 ) );
}

public int Native_GetClientStyle( Handle handler, int numParams )
{
	return g_PlayerCurrentStyle[GetNativeCell( 1 )];
}

public int Native_IsClientLoaded( Handle handler, int numParams )
{
	return g_bClientLoaded[GetNativeCell( 1 )];
}

public int Native_StopTimer( Handle handler, int numParams )
{
	StopTimer( GetNativeCell( 1 ) );
}