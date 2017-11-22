#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>

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

Handle		g_hForward_OnDatabaseReady;
Handle		g_hForward_OnClientLoaded;

int			g_ClientPlayerID[MAXPLAYERS + 1];

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
bool			g_bAutoBhop[MAXPLAYERS + 1];
bool			g_bNoclip[MAXPLAYERS + 1];

public void OnPluginStart()
{
	/* Forwards */
	g_hForward_OnDatabaseReady = CreateGlobalForward( "Timer_OnDatabaseReady", ET_Event );
	g_hForward_OnClientLoaded = CreateGlobalForward( "Timer_OnClientLoaded", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	
	/* Commands */
	RegConsoleCmd( "sm_nc", Command_Noclip );
	
	/* Hooks */
	HookEvent( "player_jump", HookEvent_PlayerJump );
	
	SQL_DBConnect();
	
	g_fFrameTime = GetTickInterval();
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	CreateNative( "Timer_GetDatabase", Native_GetDatabase );
	CreateNative( "Timer_StopTimer", Native_StopTimer );

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary( "timer-core" );
	
	sv_autobunnyhopping = FindConVar( "sv_autobunnyhopping" );
	sv_autobunnyhopping.BoolValue = false;

	return APLRes_Success;
}

public void OnClientPutInServer( int client )
{
	if( !IsFakeClient( client ) )
	{
		sv_autobunnyhopping.ReplicateToClient( client, g_bAutoBhop[client] ? "1" : "0" );
	}
}

public void OnClientPostAdminCheck( int client )
{
	if( !IsFakeClient( client ) )
	{
		SQL_LoadPlayerID( client );
	}
}

public void Timer_OnClientLoaded( int client, int playerid, bool newplayer )
{
	for( int i = 0; i < view_as<int>( TOTAL_ZONE_TRACKS ); i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_PlayerRecordData[client][i][j][RD_PlayerID] = playerid;
		}
	}
	
	SQL_LoadRecords( client );
}

public void OnPlayerRunCmd( int client, int& buttons, int& impulse, float vel[3], float angles[3] )
{
	if( IsValidClient( client, true ) )
	{	
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
				
				if( ( fDeltaYaw > 0.0 && ( buttons & IN_MOVELEFT ) && !( buttons & IN_MOVERIGHT ) ) ||
					( fDeltaYaw < 0.0 && ( buttons & IN_MOVERIGHT ) && !( buttons & IN_MOVELEFT ) ) )
				{
					g_nPlayerSyncedFrames[client]++;
				}
			}
			
			if( !( lastButtons[client] & IN_LEFT ) && ( buttons & IN_LEFT ) )
			{
				g_nPlayerStrafes[client]++;
			}
			else if( !( lastButtons[client] & IN_RIGHT ) && ( buttons & IN_RIGHT ) )
			{
				g_nPlayerStrafes[client]++;
			}
		}
		
		if( g_bAutoBhop[client] && buttons & IN_JUMP )
		{
			if( !( GetEntityMoveType( client ) & MOVETYPE_LADDER )
				&& !( GetEntityFlags( client ) & FL_ONGROUND )
				&& ( GetEntProp( client, Prop_Data, "m_nWaterLevel" ) < 2 ) )
			{
				buttons &= ~IN_JUMP;
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
	
	ZoneTrack track = Timer_GetClientZoneTrack( client );
	char sZoneTrack[64];
	Timer_GetZoneTrackName( track, sZoneTrack, sizeof( sZoneTrack ) );
	
	char buffer[256];
	Format( buffer, sizeof( buffer ), "[Timer] %N finished on %s timer in %ss", client, sZoneTrack, sTime );
	PrintToChatAll( buffer );
	
	int style = g_PlayerCurrentStyle[client];
	
	if( g_PlayerRecordData[client][track][style][RD_Time] == 0.0 ) // new time
	{
		SQL_InsertRecord( client, track, style, time );
	}
	else if( time < g_PlayerRecordData[client][track][style][RD_Time] ) // new pb
	{
		SQL_UpdateRecord( client, track, style, time );
	}
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

	Call_StartForward( g_hForward_OnDatabaseReady );
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
			Format( query, sizeof( query ), "UPDATE `t_players` SET lastname = '%s', lastconnect = '%i' WHERE uid = '%i';", name, GetTime(), g_ClientPlayerID[client] );
			
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

void SQL_LoadRecords( int client )
{
	char mapname[PLATFORM_MAX_PATH];
	GetCurrentMap( mapname, sizeof( mapname ) );
	
	char query[256];
	Format( query, sizeof( query ), "SELECT track, style, timestamp, time, jumps, strafes, sync, strafetime, ssj FROM `t_records` WHERE playerid = '%i' AND mapname = '%s'", g_ClientPlayerID[client], mapname );
	
	g_hDatabase.Query( LoadRecords_Callback, query, GetClientUserId( client ), DBPrio_High );
}

public void LoadRecords_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadRecords_Callback) - %s", error );
		return;
	}
	
	int client = GetClientOfUserId( uid );
	
	if( !IsValidClient( client ) )
	{
		return;
	}
	
	while( results.FetchRow() )
	{
		int track = results.FetchInt( 0 );
		int style = results.FetchInt( 1 );
		
		g_PlayerRecordData[client][track][style][RD_Timestamp] = results.FetchInt( 2 );
		g_PlayerRecordData[client][track][style][RD_Time] = results.FetchFloat( 3 );
		g_PlayerRecordData[client][track][style][RD_Jumps] = results.FetchInt( 4 );
		g_PlayerRecordData[client][track][style][RD_Strafes] = results.FetchInt( 5 );
		g_PlayerRecordData[client][track][style][RD_Sync] = results.FetchFloat( 6 );
		g_PlayerRecordData[client][track][style][RD_StrafeTime] = results.FetchFloat( 7 );
		g_PlayerRecordData[client][track][style][RD_SSJ] = results.FetchInt( 8 );
	}
}

void SQL_InsertRecord( int client, ZoneTrack track, int style, float time )
{
	float sync = float( g_nPlayerSyncedFrames[client] ) / g_nPlayerAirStrafeFrames[client];
	float strafetime = float( g_nPlayerAirStrafeFrames[client] ) / g_nPlayerAirFrames[client];
	
	g_PlayerRecordData[client][track][style][RD_Timestamp] = GetTime();
	g_PlayerRecordData[client][track][style][RD_Time] = time;
	g_PlayerRecordData[client][track][style][RD_Jumps] = g_nPlayerJumps[client];
	g_PlayerRecordData[client][track][style][RD_Strafes] = g_nPlayerStrafes[client];
	g_PlayerRecordData[client][track][style][RD_Sync] = sync;
	g_PlayerRecordData[client][track][style][RD_StrafeTime] = strafetime;
	g_PlayerRecordData[client][track][style][RD_SSJ] = g_iPlayerSSJ[client];
	
	char query[256];
	Format( query, sizeof( query ), "INSERT INTO `t_records` (track, style, timestamp, time, jumps, strafes, sync, strafetime, ssj) \
													VALUES (%i, %i, %i, %f, %i, %i, %f, %f, %i) \
													WHERE playerid = '%i'",
													view_as<int>( Timer_GetClientZoneTrack( client ) ),
													g_PlayerCurrentStyle[client],
													GetTime(),
													time,
													g_nPlayerJumps[client],
													g_nPlayerStrafes[client],
													sync,
													strafetime,
													g_iPlayerSSJ[client],
													g_ClientPlayerID[client]);
	
	g_hDatabase.Query( InsertRecord_Callback, query, _, DBPrio_High );
}

public void InsertRecord_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertRecord_Callback) - %s", error );
		return;
	}
}

void SQL_UpdateRecord( int client, ZoneTrack track, int style, float time )
{
	float sync = float( g_nPlayerSyncedFrames[client] ) / g_nPlayerAirStrafeFrames[client];
	float strafetime = float( g_nPlayerAirStrafeFrames[client] ) / g_nPlayerAirFrames[client];
	
	g_PlayerRecordData[client][track][style][RD_Timestamp] = GetTime();
	g_PlayerRecordData[client][track][style][RD_Time] = time;
	g_PlayerRecordData[client][track][style][RD_Jumps] = g_nPlayerJumps[client];
	g_PlayerRecordData[client][track][style][RD_Strafes] = g_nPlayerStrafes[client];
	g_PlayerRecordData[client][track][style][RD_Sync] = sync;
	g_PlayerRecordData[client][track][style][RD_StrafeTime] = strafetime;
	g_PlayerRecordData[client][track][style][RD_SSJ] = g_iPlayerSSJ[client];
	
	char query[256];
	Format( query, sizeof( query ), "UPDATE `t_records` SET timestamp = '%s', time = '%f', jumps = '%i', strafes = '%i', sync = '%f', strafetime = '%f', ssj = '%i') \
													WHERE playerid = '%s' AND track = '%i' AND style = '%i'",
													GetTime(),
													time,
													g_nPlayerJumps[client],
													g_nPlayerStrafes[client],
													sync,
													strafetime,
													g_iPlayerSSJ[client],
													g_ClientPlayerID[client],
													view_as<int>( track ),
													style );
	
	g_hDatabase.Query( UpdateRecord_Callback, query, _, DBPrio_High );
}

public void UpdateRecord_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertRecord_Callback) - %s", error );
		return;
	}
}

/* Commands */

public Action Command_Noclip( int client, int args )
{
	g_bNoclip[client] = !g_bNoclip[client];
	
	if( g_bNoclip[client] )
	{
		SetEntityMoveType( client, MOVETYPE_NOCLIP );
	}
	else
	{
		SetEntityMoveType( client, MOVETYPE_WALK );
	}
}


/* Natives */

public int Native_GetDatabase( Handle handler, int numParams )
{
	return view_as<int>( CloneHandle( g_hDatabase ) );
}

public int Native_StopTimer( Handle handler, int numParams )
{
	StopTimer( GetNativeCell( 1 ) );
}