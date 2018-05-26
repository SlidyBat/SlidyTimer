#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>
#include <sdktools>

#define MAX_WR_CACHE 50

public Plugin myinfo = 
{
	name = "Slidy's Timer - Records component",
	author = "SlidyBat",
	description = "Records component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

char g_cMapName[PLATFORM_MAX_PATH];

Database		g_hDatabase;

Handle		g_hForward_OnClientLoaded;
Handle		g_hForward_OnWRBeaten;
Handle		g_hForward_OnRecordInsertedPre;
Handle		g_hForward_OnRecordInsertedPost;
Handle		g_hForward_OnRecordUpdatedPre;
Handle		g_hForward_OnRecordUpdatedPost;
Handle		g_hForward_OnClientRankRequested;
Handle 		g_hForward_OnClientPBTimeRequested;
Handle 		g_hForward_OnWRTimeRequested;
Handle 		g_hForward_OnWRNameRequested;
Handle 		g_hForward_OnRecordsCountRequested;
Handle		g_hForward_OnLeaderboardRequested;

ArrayList		g_aMapTopRecordIds[TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList		g_aMapTopTimes[TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList		g_aMapTopNames[TOTAL_ZONE_TRACKS][MAX_STYLES];

/* Player Data */
int			g_iPlayerId[MAXPLAYERS + 1] = { -1, ... };
int			g_iPlayerRecordId[MAXPLAYERS + 1][TOTAL_ZONE_TRACKS][MAX_STYLES];
float			g_fPlayerPersonalBest[MAXPLAYERS + 1][TOTAL_ZONE_TRACKS][MAX_STYLES];

public void OnPluginStart()
{
	/* Forwards */
	g_hForward_OnClientLoaded = CreateGlobalForward( "Timer_OnClientLoaded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnWRBeaten = CreateGlobalForward( "Timer_OnWRBeaten", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnRecordInsertedPre = CreateGlobalForward( "Timer_OnRecordInsertedPre", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_Float );
	g_hForward_OnRecordInsertedPost = CreateGlobalForward( "Timer_OnRecordInsertedPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Cell );
	g_hForward_OnRecordUpdatedPre = CreateGlobalForward( "Timer_OnRecordUpdatedPre", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Cell );
	g_hForward_OnRecordUpdatedPost = CreateGlobalForward( "Timer_OnRecordUpdatedPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Float, Param_Cell );
	g_hForward_OnClientRankRequested = CreateGlobalForward( "Timer_OnClientRankRequested", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_CellByRef );
	g_hForward_OnClientPBTimeRequested = CreateGlobalForward( "Timer_OnClientPBTimeRequested", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_FloatByRef );
	g_hForward_OnWRTimeRequested = CreateGlobalForward( "Timer_OnWRTimeRequested", ET_Event, Param_Cell, Param_Cell, Param_FloatByRef );
	g_hForward_OnWRNameRequested = CreateGlobalForward( "Timer_OnWRNameRequested", ET_Event, Param_Cell, Param_Cell, Param_String );
	g_hForward_OnRecordsCountRequested = CreateGlobalForward( "Timer_OnRecordsCountRequested", ET_Event, Param_Cell, Param_Cell, Param_CellByRef );
	g_hForward_OnLeaderboardRequested = CreateGlobalForward( "Timer_OnLeaderboardRequested", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	
	/* Commands */
	RegConsoleCmd( "sm_pb", Command_PB );
	RegConsoleCmd( "sm_bpb", Command_Bonus_PB );
	RegConsoleCmd( "sm_wr", Command_WR );
	RegConsoleCmd( "sm_bwr", Command_Bonus_WR );
	
	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_aMapTopRecordIds[i][j] = new ArrayList();
			g_aMapTopTimes[i][j] = new ArrayList();
			g_aMapTopNames[i][j] = new ArrayList( ByteCountToCells( MAX_NAME_LENGTH ) );
		}
	}
	
	g_hDatabase = Timer_GetDatabase();
	SQL_CreateTables();
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	CreateNative( "Timer_IsClientLoaded", Native_IsClientLoaded );
	CreateNative( "Timer_GetClientPlayerId", Native_GetClientPlayerId );
	CreateNative( "Timer_GetClientMapRank", Native_GetClientMapRank );
	CreateNative( "Timer_GetClientPBTime", Native_GetClientPBTime );
	CreateNative( "Timer_GetWRTime", Native_GetWRTime );
	CreateNative( "Timer_GetWRName", Native_GetWRName );
	CreateNative( "Timer_GetRecordsCount", Native_GetRecordsCount );

	RegPluginLibrary( "timer-records" );
	
	return APLRes_Success;
}

public void OnMapStart()
{
	GetCurrentMap( g_cMapName, sizeof( g_cMapName ) );
	
	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_aMapTopRecordIds[i][j].Clear();
			g_aMapTopTimes[i][j].Clear();
			g_aMapTopNames[i][j].Clear();
			SQL_ReloadCache( i, j, true );
		}
	}
}

public void OnClientAuthorized( int client, const char[] auth )
{
	if( !IsFakeClient( client ) )
	{
		Timer_DebugPrint( "OnClientAuthorized: %N", client );
		SQL_LoadPlayerID( client );
	}
}

public void OnClientDisconnect( int client )
{
	g_iPlayerId[client] = -1;
}

public void Timer_OnClientLoaded( int client, int playerid, bool newplayer )
{
	Timer_DebugPrint( "Timer_OnClientLoaded: Loading records for %N", client );

	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			SQL_LoadRecords( client, i, j );
		}
	}
}

public void Timer_OnTimerFinishPost( int client, int track, int style, float time )
{
	float pb = g_fPlayerPersonalBest[client][track][style];
	float wr = Timer_GetWRTime( track, style );
	
	if( pb == 0.0 || time < pb ) // new record, save it
	{
		g_fPlayerPersonalBest[client][track][style] = time;
		
		if( pb == 0.0 ) // new time
		{
			SQL_InsertRecord( client, track, style, time );
		}
		else // existing time but beaten
		{
			SQL_UpdateRecord( client, track, style, time );
		}
		
		if( wr == 0.0 || time < wr )
		{
			Timer_PrintToChatAll( "{primary}NEW WR!!!!!" );
			
			Call_StartForward( g_hForward_OnWRBeaten );
			Call_PushCell( client );
			Call_PushCell( track );
			Call_PushCell( style );
			Call_PushCell( time );
			Call_PushCell( wr );
			Call_Finish();
		}
		else
		{
			Timer_PrintToChat( client, "{primary}NEW PB!!!" );
		}
	}
	else
	{
		// they didnt beat their pb but we should update their attempts anyway
		char query[128];
		FormatEx( query, sizeof( query ), "UPDATE `t_records` SET `attempts` = `attempts` + 1 WHERE recordid = '%i'",
										g_iPlayerRecordId[client][track][style] );
		
		g_hDatabase.Query( UpdateAttempts_Callback, query, _, DBPrio_Low );
	}
	
	SQL_ReloadCache( track, style );
}

stock int GetRankForTime( float time, int track, int style )
{
	if( time == 0.0 )
	{
		return 0;
	}
	
	int nRecords = g_aMapTopTimes[track][style].Length;
	
	if( nRecords == 0 )
	{
		return 1;
	}
	
	for( int i = 0; i < nRecords; i++ )
	{
		float maptime = g_aMapTopTimes[track][style].Get( i );
		if( time < maptime )
		{
			return i + 1;
		}
	}
	
	return nRecords + 1;
}

int GetClientMapRank( int client, int track, int style )
{
	// subtract 1 because when times are equal, it counts as next rank
	return GetRankForTime( g_fPlayerPersonalBest[client][track][style], track, style ) - 1;
}

/* Database stuff */

public void Timer_OnDatabaseLoaded()
{
	if( g_hDatabase == null )
	{
		g_hDatabase = Timer_GetDatabase();
		SQL_CreateTables();
	}
}

void SQL_CreateTables()
{
	if( g_hDatabase == null )
	{
		return;
	}

	Transaction txn = new Transaction();
	
	char query[512];
	
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_players` ( playerid INT NOT NULL AUTO_INCREMENT, \
																			steamaccountid INT NOT NULL, \
																			lastname CHAR(64) NOT NULL, \
																			firstconnect INT(16) NOT NULL, \
																			lastconnect INT(16) NOT NULL, \
																			PRIMARY KEY (`playerid`) );" );
	txn.AddQuery( query );
	
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_records` ( recordid INT NOT NULL AUTO_INCREMENT, \
																			mapid INT NOT NULL, \
																			playerid INT NOT NULL, \
																			timestamp INT( 16 ) NOT NULL, \
																			attempts INT( 8 ) NOT NULL, \
																			time FLOAT NOT NULL, \
																			track INT NOT NULL, \
																			style INT NOT NULL, \
																			jumps INT NOT NULL, \
																			strafes INT NOT NULL, \
																			sync FLOAT NOT NULL, \
																			strafetime FLOAT NOT NULL, \
																			ssj INT NOT NULL, \
																			PRIMARY KEY (`recordid`) );" );
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
			Format( query, sizeof( query ), "UPDATE `t_players` SET lastname = '%s', lastconnect = '%i' WHERE playerid = '%i';", name, GetTime(), g_iPlayerId[client] );
			
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
		Format( query, sizeof( query ), "INSERT INTO `t_players` (`steamaccountid`, `lastname`, `firstconnect`, `lastconnect`) VALUES ('%i', '%s', '%i', '%i');", GetSteamAccountID( client ), name, timestamp, timestamp );
		
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

void SQL_LoadRecords( int client, int track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "SELECT recordid, time FROM `t_records` WHERE playerid = '%i' AND track = '%i' AND style = '%i' AND mapid = '%i';", g_iPlayerId[client], track, style, Timer_GetMapId() );
	
	Timer_DebugPrint( "SQL_LoadRecords: %s", query );
	
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
		delete pack;
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	if( !client )
	{
		return;
	}
	
	if( results.FetchRow() )
	{
		g_iPlayerRecordId[client][track][style] = results.FetchInt( 0 );
		g_fPlayerPersonalBest[client][track][style] = results.FetchFloat( 1 );
		
		Timer_DebugPrint( "LoadRecords_Callback: track=%i style=%i recordid=%i pb=%f", track, style, g_iPlayerRecordId[client][track][style], g_fPlayerPersonalBest[client][track][style] );
	}
	else
	{
		g_iPlayerRecordId[client][track][style] = -1;
		g_fPlayerPersonalBest[client][track][style] = 0.0;
	}
}

void SQL_InsertRecord( int client, int track, int style, float time )
{
	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnRecordInsertedPre );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_Finish( result );
	
	if( result == Plugin_Handled || result == Plugin_Stop )
	{
		return;
	}

	char query[512];
	Format( query, sizeof( query ), "INSERT INTO `t_records` (mapid, playerid, track, style, timestamp, attempts, time, jumps, strafes, sync, strafetime, ssj) \
													VALUES ('%i', '%i', '%i', '%i', '%i', '%i', '%.5f', '%i', '%i', '%.2f', '%.2f', '%i');",
													Timer_GetMapId(),
													g_iPlayerId[client],
													track,
													style,
													GetTime(),
													1,
													time,
													Timer_GetClientCurrentJumps( client ),
													Timer_GetClientCurrentStrafes( client ),
													Timer_GetClientCurrentSync( client ),
													Timer_GetClientCurrentStrafeTime( client ),
													Timer_GetClientCurrentSSJ( client ) );
	
	Timer_DebugPrint( "SQL_InsertRecord: %s", query );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( track );
	pack.WriteCell( style );
	pack.WriteFloat( time );
	
	g_hDatabase.Query( InsertRecord_Callback, query, pack, DBPrio_High );
}

public void InsertRecord_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertRecord_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	float time = pack.ReadFloat();
	delete pack;
	
	g_iPlayerRecordId[client][track][style] = results.InsertId;
	
	Call_StartForward( g_hForward_OnRecordInsertedPost );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_PushCell( results.InsertId );
	Call_Finish();
}

void SQL_UpdateRecord( int client, int track, int style, float time )
{
	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnRecordUpdatedPre );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_PushCell( g_iPlayerRecordId[client][track][style] );
	Call_Finish( result );
	
	if( result == Plugin_Handled || result == Plugin_Stop )
	{
		return;
	}

	char query[312];
	Format( query, sizeof( query ), "UPDATE `t_records` SET timestamp = '%i', attempts = attempts+1, time = '%f', jumps = '%i', strafes = '%i', sync = '%f', strafetime = '%f', ssj = '%i' \
													WHERE recordid = '%i';",
													GetTime(),
													time,
													Timer_GetClientCurrentJumps( client ),
													Timer_GetClientCurrentStrafes( client ),
													Timer_GetClientCurrentSync( client ),
													Timer_GetClientCurrentStrafeTime( client ),
													Timer_GetClientCurrentSSJ( client ),
													g_iPlayerRecordId[client][track][style] );
	
	Timer_DebugPrint( "SQL_UpdateRecord: %s", query );
	
	DataPack pack = new DataPack();
	pack.WriteCell( client );
	pack.WriteCell( track );
	pack.WriteCell( style );
	pack.WriteFloat( time );
	
	g_hDatabase.Query( UpdateRecord_Callback, query, pack, DBPrio_High );
}

public void UpdateRecord_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdateRecord_Callback) - %s", error );
		delete pack;
		return;
	}

	pack.Reset();
	int client = pack.ReadCell();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	float time = pack.ReadFloat();
	delete pack;
	
	Call_StartForward( g_hForward_OnRecordUpdatedPost );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_PushCell( g_iPlayerRecordId[client][track][style] );
	Call_Finish();
}

void SQL_DeleteRecord( int recordid, int track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "DELETE FROM `t_records` WHERE recordid = '%i';", recordid );
	
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
		delete pack;
		return;
	}
	
	pack.Reset();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	SQL_ReloadCache( track, style, true );
}

void SQL_ReloadCache( int track, int style, bool reloadall = false )
{
	char query[512];
	Format( query, sizeof( query ), "SELECT r.recordid, r.time, p.lastname \
									FROM `t_records` r JOIN `t_players` p ON p.playerid = r.playerid \
									WHERE mapid = '%i' AND track = '%i' AND style = '%i'\
									ORDER BY r.time ASC;", Timer_GetMapId(), track, style );
	
	DataPack pack = new DataPack();
	pack.WriteCell( track );
	pack.WriteCell( style );
	pack.WriteCell( style );
	
	Timer_DebugPrint( "SQL_ReloadCache: %s", query );
	
	g_hDatabase.Query( CacheRecords_Callback, query, pack, DBPrio_High );
	
	if( reloadall )
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientConnected( i ) && !IsFakeClient( i ) && g_iPlayerId[i] > -1 )
			{
				SQL_LoadRecords( i, track, style );
			}
		}
	}
}

public void CacheRecords_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (CacheRecords_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	g_aMapTopRecordIds[track][style].Clear();
	g_aMapTopTimes[track][style].Clear();
	g_aMapTopNames[track][style].Clear();
	
	while( results.FetchRow() )
	{
		g_aMapTopRecordIds[track][style].Push( results.FetchInt( 0 ) );
		g_aMapTopTimes[track][style].Push( results.FetchFloat( 1 ) );
		
		char lastname[MAX_NAME_LENGTH];
		results.FetchString( 2, lastname, sizeof(lastname) );
		
		g_aMapTopNames[track][style].PushString( lastname );
	}
}

void SQL_ShowStats( int client, int recordid )
{
	char query[256];
	Format( query, sizeof(query), "SELECT r.playerid, p.lastname, r.timestamp, r.attempts, r.time, r.jumps, r.strafes, r.sync, r.strafetime, r.ssj, r.track, r.style \
									FROM `t_records` r JOIN `t_players` p ON p.playerid = r.playerid \
									WHERE recordid='%i'\
									ORDER BY r.time ASC;", recordid );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( recordid );
	
	g_hDatabase.Query( GetRecordStats_Callback, query, pack );
}

void SQL_ShowPlayerStats( int client, int playerid )
{
	Timer_PrintToChat( client, "{primary}Player stats coming soon! (%i)", playerid );
}

public void GetRecordStats_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (GetRecordStats_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int recordid = pack.ReadCell();
	if( !(0 < client <= MaxClients) )
	{
		return;
	}
	
	if( results.FetchRow() )
	{
		any recordData[RecordData];
		
		recordData[RD_PlayerID] = results.FetchInt( 0 );
		results.FetchString( 1, recordData[RD_Name], MAX_NAME_LENGTH );
		recordData[RD_Timestamp] = results.FetchInt( 2 );
		recordData[RD_Attempts] = results.FetchInt( 3 );
		recordData[RD_Time] = results.FetchFloat( 4 );
		recordData[RD_Jumps] = results.FetchInt( 5 );
		recordData[RD_Strafes] = results.FetchInt( 6 );
		recordData[RD_Sync] = results.FetchFloat( 7 );
		recordData[RD_StrafeTime] = results.FetchFloat( 8 );
		recordData[RD_SSJ] = results.FetchInt( 9 );
		
		int track = results.FetchInt( 10 );
		int style = results.FetchInt( 11 );
		
		ShowStats( client, track, style, recordid, recordData );
	}
	else
	{
		LogError( "[SQL Error] (GetRecordStats_Callback) - Invalid recordid" );
	}
}

public void UpdateAttempts_Callback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdateAttempts_Callback) - %s", error );
		return;
	}
}

/* Commands */

public Action Command_PB( int client, int args )
{
	Timer_OpenSelectStyleMenu( client, ShowPB );
	
	return Plugin_Handled;
}

public void ShowPB( int client, int style )
{
	if( g_iPlayerRecordId[client][ZoneTrack_Main][style] != -1 )
	{
		SQL_ShowStats( client, g_iPlayerRecordId[client][ZoneTrack_Main][style] );
	}
	else
	{
		Timer_PrintToChat( client, "{primary}No records found" );
	}
}

public Action Command_Bonus_PB( int client, int args )
{
	Timer_OpenSelectStyleMenu( client, ShowBonusPB );
	
	return Plugin_Handled;
}

public void ShowBonusPB( int client, int style )
{
	if( g_iPlayerRecordId[client][ZoneTrack_Main][style] != -1 )
	{
		SQL_ShowStats( client, g_iPlayerRecordId[client][ZoneTrack_Main][style] );
	}
	else
	{
		Timer_PrintToChat( client, "{primary}No records found" );
	}
}

public Action Command_WR( int client, int args )
{
	Timer_OpenSelectStyleMenu( client, ShowWRMenu );
	
	return Plugin_Handled;
}

public void ShowWRMenu( int client, int style )
{
	ShowLeaderboard( client, ZoneTrack_Main, style );
}

public Action Command_Bonus_WR( int client, int args )
{
	Timer_OpenSelectStyleMenu( client, ShowBonusWRMenu );
	
	return Plugin_Handled;
}

public void ShowBonusWRMenu( int client, int style )
{
	ShowLeaderboard( client, ZoneTrack_Bonus, style );
}

void ShowLeaderboard( int client, int track, int style )
{
	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnLeaderboardRequested );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_Finish( result );
	
	if( result == Plugin_Handled || result == Plugin_Stop )
	{
		return;
	}

	if( !Timer_GetRecordsCount( track, style ) )
	{
		Timer_PrintToChat( client, "{primary}No records found" );
		return;
	}
	
	Menu menu = new Menu( WRMenu_Handler );
	
	char trackName[32];
	Timer_GetZoneTrackName( track, trackName, sizeof(trackName) );
	
	char styleName[32];
	Timer_GetStyleName( style, styleName, sizeof(styleName) );
	
	char buffer[256];
	Format( buffer, sizeof( buffer ), "%s %s %s Leaderboard", trackName, styleName, g_cMapName );
	menu.SetTitle( buffer );
	
	char sTime[32], info[8];
	
	int max = ( MAX_WR_CACHE > g_aMapTopTimes[track][style].Length ) ? g_aMapTopTimes[track][style].Length : MAX_WR_CACHE;
	Timer_DebugPrint( "ShowLeaderboard: max=%i", max );
	for( int i = 0; i < max; i++ )
	{
		char name[MAX_NAME_LENGTH];
		g_aMapTopNames[track][style].GetString( i, name, sizeof(name) );
	
		Timer_FormatTime( g_aMapTopTimes[track][style].Get( i ), sTime, sizeof(sTime) );
		
		Format( buffer, sizeof(buffer), "[#%i] - %s (%s)", i + 1, name, sTime );
		Format( info, sizeof(info), "%i,%i", track, style );
		
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
		ExplodeString( info, ",", infoSplit, sizeof(infoSplit), sizeof(infoSplit[]) );
		
		int track = StringToInt( infoSplit[0] );
		int style = StringToInt( infoSplit[1] );
		Timer_DebugPrint( "WRMenu_Handler: track=%i style=%i", track, style );
		
		//Timer_DebugPrint( "WRMenu_Handler: Loaded record (recordid=%i, time=%f)", g_aMapTopTimes[track][style].Get( param2, 0 ), g_aMapTopTimes[track][style].Get( param2, 1 ) );
		
		SQL_ShowStats( param1, g_aMapTopRecordIds[track][style].Get( param2 ) );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void ShowStats( int client, int track, int style, int recordid, const any recordData[RecordData] )
{
	Menu menu = new Menu( RecordInfo_Handler );
	
	char date[128];
	FormatTime( date, sizeof( date ), "%d/%m/%Y - %H:%M:%S", recordData[RD_Timestamp] );
	char sTime[64];
	Timer_FormatTime( recordData[RD_Time], sTime, sizeof( sTime ) );
	
	char sTrack[16];
	Timer_GetZoneTrackName( track, sTrack, sizeof( sTrack ) );
	
	any settings[styleSettings];
	Timer_GetStyleSettings( style, settings );
	
	char sSync[10];
	if( settings[Sync] )
	{
		Format( sSync, sizeof( sSync ), "(%.2f)", recordData[RD_Sync] );
	}
	
	char sInfo[64];
	Format( sInfo, sizeof( sInfo ), "%i,%i,%i,%i", recordData[RD_PlayerID], track, style, recordid );
	
	char buffer[512];
	Format( buffer, sizeof( buffer ), "%s - %s %s\n \n", g_cMapName, sTrack, settings[StyleName] );
	menu.SetTitle( buffer );
	
	Format( buffer, sizeof( buffer ), "Player: %s\n", recordData[RD_Name] );
	Format( buffer, sizeof( buffer ), "%sDate: %s\n", buffer, date );
	Format( buffer, sizeof( buffer ), "%sAttempts: %i\n \n", buffer, recordData[RD_Attempts] );
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
		
		char sSplitString[4][16];
		ExplodeString( sInfo, ",", sSplitString, sizeof( sSplitString ), sizeof( sSplitString[] ) );
		
		int playerid = StringToInt( sSplitString[0] );
		int track = StringToInt( sSplitString[1] );
		int style = StringToInt( sSplitString[2] );
		int recordid = StringToInt( sSplitString[3] );
		
		switch( param2 )
		{
			case 0: // TODO: implement showing player stats here
			{
				SQL_ShowPlayerStats( param1, playerid );
			}
			case 1: // delete time
			{
				SQL_DeleteRecord( recordid, track, style );
			}
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

/* Natives */

public int Native_IsClientLoaded( Handle handler, int numParams )
{
	return g_iPlayerId[GetNativeCell( 1 )] > -1;
}

public int Native_GetClientPlayerId( Handle handler, int numParams )
{
	return g_iPlayerId[GetNativeCell( 1 )];
}

public int Native_GetClientMapRank( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	int track = GetNativeCell( 2 );
	int style = GetNativeCell( 3 );
	int rank = GetClientMapRank( client, track, style );
	
	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnClientRankRequested );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	int temp = rank;
	Call_PushCellRef( temp );
	Call_Finish( result );

	if( result == Plugin_Changed || result == Plugin_Handled || result == Plugin_Stop )
	{
		return temp;
	}
	
	return rank;
}

public int Native_GetClientPBTime( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	int track = GetNativeCell( 2 );
	int style = GetNativeCell( 3 );
	float pb = g_fPlayerPersonalBest[client][track][style];

	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnClientPBTimeRequested );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloatRef( pb );
	Call_Finish( result );
	
	if( result == Plugin_Changed || result == Plugin_Handled || result == Plugin_Stop )
	{
		return view_as<int>( pb );
	}
	
	return view_as<int>( g_fPlayerPersonalBest[client][track][style] );
}

public int Native_GetWRTime( Handle handler, int numParams )
{
	int track = GetNativeCell( 1 );
	int style = GetNativeCell( 2 );
	
	float wr = 0.0;
	if( g_aMapTopTimes[track][style].Length )
	{		
		return g_aMapTopTimes[track][style].Get( 0 );
	}
	
	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnWRTimeRequested );
	Call_PushCell( track );
	Call_PushCell( style );
	float temp = wr;
	Call_PushFloatRef( wr );
	Call_Finish( result );
	
	if( result == Plugin_Changed || result == Plugin_Handled || result == Plugin_Stop )
	{
		return view_as<int>( temp );
	}
	
	return view_as<int>( wr );
}

public int Native_GetWRName( Handle handler, int numParams )
{
	int track = GetNativeCell( 1 );
	int style = GetNativeCell( 2 );
	
	char name[MAX_NAME_LENGTH];
	if( g_aMapTopNames[track][style].Length )
	{
		g_aMapTopNames[track][style].GetString( 0, name, sizeof(name) );
	}
	
	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnWRNameRequested );
	Call_PushCell( track );
	Call_PushCell( style );
	char temp[MAX_NAME_LENGTH];
	strcopy( temp, sizeof(temp), name );
	Call_PushStringEx( temp, sizeof(temp), SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK );
	Call_Finish( result );
	
	if( result == Plugin_Changed || result == Plugin_Handled || result == Plugin_Stop )
	{
		SetNativeString( 3, temp, GetNativeCell( 4 ) );
	}
	else
	{
		SetNativeString( 3, name, GetNativeCell( 4 ) );
	}
	
	return 1;
}

public int Native_GetRecordsCount( Handle handler, int numParams )
{
	int track = GetNativeCell( 1 );
	int style = GetNativeCell( 2 );
	int recordcount = g_aMapTopTimes[track][style].Length;
	
	any result = Plugin_Continue;
	Call_StartForward( g_hForward_OnRecordsCountRequested );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushCellRef( recordcount );
	Call_Finish( result );
	
	if( result == Plugin_Changed || result == Plugin_Handled || result == Plugin_Stop )
	{
		return recordcount;
	}
	
	return g_aMapTopTimes[track][style].Length;
}