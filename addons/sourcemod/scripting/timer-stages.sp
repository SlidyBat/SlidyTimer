#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>

#define MAX_WRCP_CACHE 30

public Plugin myinfo = 
{
	name = "Slidy's Timer - Stages component",
	author = "SlidyBat",
	description = "Stages component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

#define MAX_STAGES 64

Database		g_hDatabase;

ArrayList		g_aMapTopRecordIds[MAX_STAGES][TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList		g_aMapTopTimes[MAX_STAGES][TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList		g_aMapTopNames[MAX_STAGES][TOTAL_ZONE_TRACKS][MAX_STYLES];

int			g_iPlayerRecordId[MAXPLAYERS + 1][MAX_STAGES][TOTAL_ZONE_TRACKS][MAX_STYLES];
float			g_fPlayerPersonalBest[MAXPLAYERS + 1][MAX_STAGES][TOTAL_ZONE_TRACKS][MAX_STYLES];

int			g_iPlayerStartStage[MAXPLAYERS + 1];
int			g_nPlayerStartFrame[MAXPLAYERS + 1];

int			g_iSelectedStage[MAXPLAYERS + 1];

char g_cMapName[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	/* Commands */
	RegConsoleCmd( "sm_pbcp", Command_PBCP );
	RegConsoleCmd( "sm_bpbcp", Command_Bonus_PBCP );
	RegConsoleCmd( "sm_wrcp", Command_WRCP );
	RegConsoleCmd( "sm_bwrcp", Command_Bonus_WRCP );
	
	for( int i = 0; i < MAX_STAGES; i++)
	{
		for( int j = 0; j < TOTAL_ZONE_TRACKS; j++ )
		{
			for( int k = 0; k < MAX_STYLES; k++ )
			{
				g_aMapTopRecordIds[i][j][k] = new ArrayList();
				g_aMapTopTimes[i][j][k] = new ArrayList();
				g_aMapTopNames[i][j][k] = new ArrayList( ByteCountToCells( MAX_NAME_LENGTH ) );
			}
		}
	}
	
	g_hDatabase = Timer_GetDatabase();
	SQL_CreateTables();
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	RegPluginLibrary( "timer-stages" );
	
	return APLRes_Success;
}

public void Timer_OnMapLoaded()
{
	GetCurrentMap( g_cMapName, sizeof( g_cMapName ) );
	
	for( int i = 0; i < MAX_STAGES; i++)
	{
		for( int j = 0; j < TOTAL_ZONE_TRACKS; j++ )
		{
			for( int k = 0; k < MAX_STYLES; k++ )
			{
				g_aMapTopRecordIds[i][j][k].Clear();
				g_aMapTopTimes[i][j][k].Clear();
				g_aMapTopNames[i][j][k].Clear();
				SQL_ReloadCache( i, j, k, true );
			}
		}
	}
}

public void OnClientConnected( int client )
{
	g_iPlayerStartStage[client] = -999;
	g_nPlayerStartFrame[client] = 0;
}

public void Timer_OnClientLoaded( int client, int playerid, bool newplayer )
{
	Timer_DebugPrint( "Timer_OnClientLoaded: Loading records for %N", client );

	for( int i = 0; i < MAX_STAGES; i++)
	{
		for( int j = 0; j < TOTAL_ZONE_TRACKS; j++ )
		{
			for( int k = 0; k < MAX_STYLES; k++ )
			{
				SQL_LoadRecords( client, i, j, k );
			}
		}
	}
}

public void Timer_OnEnterZone( int client, int zoneId, int zoneType, int zoneTrack, int subindex )
{
	if( zoneType != Zone_Checkpoint || zoneTrack != Timer_GetClientZoneTrack( client ) )
	{
		// Not a checkpoint on the player's track, nothing to do
		return;
	}
	
	if( subindex == g_iPlayerStartStage[client] + 1 )
	{
		int stage = subindex - 1;
		int track = zoneTrack;
		int style = Timer_GetClientStyle( client );
	
		float time = (GetGameTickCount() - g_nPlayerStartFrame[client]) * GetTickInterval();
		float pb = g_fPlayerPersonalBest[client][stage][track][style];
		float wr = 0.0;
		if( g_aMapTopTimes[stage][track][style].Length )
		{		
			wr = g_aMapTopTimes[stage][track][style].Get( 0 );
		}
		
		if( pb == 0.0 || time < pb ) // new record, save it
		{
			g_fPlayerPersonalBest[client][stage][track][style] = time;
			
			if( pb == 0.0 ) // new time
			{
				SQL_InsertRecord( client, stage, track, style, time );
			}
			else // existing time but beaten
			{
				SQL_UpdateRecord( client, stage, track, style, time );
			}
			
			if( wr == 0.0 || time < wr )
			{
				char sTime[64];
				Timer_FormatTime( time, sTime, sizeof( sTime ) );
				
				Timer_PrintToChatAll( "{primary}NEW WRCP!!!!! %N completed stage %i in %s", client, stage + 1, sTime );
			}
			else
			{
				char sTime[64];
				Timer_FormatTime( time, sTime, sizeof( sTime ) );
				
				Timer_PrintToChat( client, "{primary}NEW PBCP!!! Completed stage %i in %s", stage + 1, sTime );
			}
		}
		else
		{
			// they didnt beat their pb but we should update their attempts anyway
			char query[128];
			FormatEx( query, sizeof( query ), "UPDATE `t_records` SET `attempts` = `attempts` + 1 WHERE recordid = '%i'",
											g_iPlayerRecordId[client][track][style] );
			
			g_hDatabase.Query( UpdateAttempts_Callback, query, _, DBPrio_Low );
			
			
			char sTime[64];
			Timer_FormatTime( time, sTime, sizeof( sTime ) );
			
			Timer_PrintToChat( client, "{primary}Completed stage %i in %s", stage + 1, sTime );
		}
		
		SQL_ReloadCache( stage, track, style );
	}
}

public void Timer_OnExitZone( int client, int zoneId, int zoneType, int zoneTrack, int subindex )
{
	if( zoneType != Zone_Checkpoint || zoneTrack != Timer_GetClientZoneTrack( client ) )
	{
		// Not a checkpoint on the player's track, nothing to do
		return;
	}
	
	g_iPlayerStartStage[client] = subindex;
	g_nPlayerStartFrame[client] = GetGameTickCount();
}

stock int GetRankForTime( float time, int stage, int track, int style )
{
	if( time == 0.0 )
	{
		return 0;
	}
	
	int nRecords = g_aMapTopTimes[stage][track][style].Length;
	
	if( nRecords == 0 )
	{
		return 1;
	}
	
	for( int i = 0; i < nRecords; i++ )
	{
		float maptime = g_aMapTopTimes[stage][track][style].Get( i );
		if( time < maptime )
		{
			return i + 1;
		}
	}
	
	return nRecords + 1;
}

stock int GetClientMapRank( int client, int stage, int track, int style )
{
	// subtract 1 because when times are equal, it counts as next rank
	return GetRankForTime( g_fPlayerPersonalBest[client][track][style], stage, track, style ) - 1;
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
	
	char query[512];
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_stage_records` ( recordid INT NOT NULL AUTO_INCREMENT, \
																			mapid INT NOT NULL, \
																			playerid INT NOT NULL, \
																			timestamp INT(16) NOT NULL, \
																			attempts INT(8) NOT NULL, \
																			time FLOAT(23, 8) NOT NULL, \
																			stage INT NOT NULL, \
																			track INT NOT NULL, \
																			style INT NOT NULL, \
																			jumps INT NOT NULL, \
																			strafes INT NOT NULL, \
																			sync FLOAT NOT NULL, \
																			strafetime FLOAT NOT NULL, \
																			ssj INT NOT NULL, \
																			PRIMARY KEY (`recordid`) );" );
	
	g_hDatabase.Query( CreateTable_Callback, query, _, DBPrio_High );
}

public void CreateTable_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (CreateTable_Callback) - %s", error );
		return;
	}
}

void SQL_LoadRecords( int client, int stage, int track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "SELECT recordid, time FROM `t_stage_records` \
		WHERE playerid = '%i' AND stage = '%i' AND track = '%i' AND style = '%i' AND mapid = '%i';",
		Timer_GetClientPlayerId( client ), stage, track, style, Timer_GetMapId() );
	
	Timer_DebugPrint( "SQL_LoadRecords: %s", query );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( stage );
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
	int stage = pack.ReadCell();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	if( !client )
	{
		return;
	}
	
	if( results.FetchRow() )
	{
		g_iPlayerRecordId[client][stage][track][style] = results.FetchInt( 0 );
		g_fPlayerPersonalBest[client][stage][track][style] = results.FetchFloat( 1 );
		
		Timer_DebugPrint( "LoadRecords_Callback: stage=%i track=%i style=%i recordid=%i pb=%f", stage, track, style, g_iPlayerRecordId[client][track][style], g_fPlayerPersonalBest[client][track][style] );
	}
	else
	{
		g_iPlayerRecordId[client][stage][track][style] = -1;
		g_fPlayerPersonalBest[client][stage][track][style] = 0.0;
	}
}

void SQL_InsertRecord( int client, int stage, int track, int style, float time )
{
	char query[512];
	Format( query, sizeof( query ), "INSERT INTO `t_stage_records` (mapid, playerid, stage, track, style, timestamp, attempts, time, jumps, strafes, sync, strafetime, ssj) \
													VALUES ('%i', '%i', '%i', '%i', '%i', '%i', '%i', '%.5f', '%i', '%i', '%.2f', '%.2f', '%i');",
													Timer_GetMapId(),
													Timer_GetClientPlayerId( client ),
													stage, 
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
	pack.WriteCell( stage );
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
	int stage = pack.ReadCell();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	// float time = pack.ReadFloat();
	delete pack;
	
	g_iPlayerRecordId[client][stage][track][style] = results.InsertId;
}

void SQL_UpdateRecord( int client, int stage, int track, int style, float time )
{
	char query[312];
	Format( query, sizeof( query ), "UPDATE `t_stage_records` SET timestamp = '%i', attempts = attempts+1, time = '%f', jumps = '%i', strafes = '%i', sync = '%f', strafetime = '%f', ssj = '%i' \
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
	pack.WriteCell( stage );
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
	
	delete pack;
}

void SQL_DeleteRecord( int recordid, int stage, int track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "DELETE FROM `t_stage_records` WHERE recordid = '%i';", recordid );
	
	DataPack pack = new DataPack();
	pack.WriteCell( stage );
	pack.WriteCell( track );
	pack.WriteCell( style );
	pack.WriteCell( recordid );
	
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
	int stage = pack.ReadCell();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	int recordid = pack.ReadCell();
	delete pack;
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_iPlayerRecordId[i][stage][track][style] == recordid )
		{
			g_iPlayerRecordId[i][stage][track][style] = -1;
			g_fPlayerPersonalBest[i][stage][track][style] = 0.0;
		}
	}
	
	SQL_ReloadCache( stage, track, style );
}

void SQL_ReloadCache( int stage, int track, int style, bool reloadall = false )
{
	char query[512];
	Format( query, sizeof(query), "SELECT r.recordid, r.time, p.lastname \
									FROM `t_stage_records` r JOIN `t_players` p ON p.playerid = r.playerid \
									WHERE mapid = '%i' AND stage='%i' AND track = '%i' AND style = '%i'\
									ORDER BY r.time ASC;",
									Timer_GetMapId(),
									stage,
									track,
									style );
	
	DataPack pack = new DataPack();
	pack.WriteCell( stage );
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	Timer_DebugPrint( "SQL_ReloadCache: %s", query );
	
	g_hDatabase.Query( CacheRecords_Callback, query, pack, DBPrio_High );
	
	if( reloadall )
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( IsClientConnected( i ) && !IsFakeClient( i ) && Timer_IsClientLoaded( i ) )
			{
				SQL_LoadRecords( i, stage, track, style );
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
	int stage = pack.ReadCell();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	g_aMapTopRecordIds[stage][track][style].Clear();
	g_aMapTopTimes[stage][track][style].Clear();
	g_aMapTopNames[stage][track][style].Clear();
	
	while( results.FetchRow() )
	{
		g_aMapTopRecordIds[stage][track][style].Push( results.FetchInt( 0 ) );
		g_aMapTopTimes[stage][track][style].Push( results.FetchFloat( 1 ) );
		
		char lastname[MAX_NAME_LENGTH];
		results.FetchString( 2, lastname, sizeof(lastname) );
		
		g_aMapTopNames[stage][track][style].PushString( lastname );
	}
}

void SQL_ShowStats( int client, int recordid )
{
	char query[256];
	Format( query, sizeof(query), "SELECT r.playerid, p.lastname, r.timestamp, r.attempts, r.time, r.jumps, r.strafes, r.sync, r.strafetime, r.ssj, r.stage, r.track, r.style \
									FROM `t_stage_records` r JOIN `t_players` p ON p.playerid = r.playerid \
									WHERE recordid='%i'\
									ORDER BY r.time ASC;", recordid );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( recordid );
	
	g_hDatabase.Query( GetRecordStats_Callback, query, pack );
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
		
		int stage = results.FetchInt( 10 );
		int track = results.FetchInt( 11 );
		int style = results.FetchInt( 12 );
		
		ShowStats( client, stage, track, style, recordid, recordData );
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

public Action Command_PBCP( int client, int args )
{
	if( args != 1 )
	{
		Timer_ReplyToCommand( client, "{primary}Usage: {secondary}sm_pbcp <stage number>" );
		return Plugin_Handled;
	}
	
	char arg[16];
	GetCmdArg( 1, arg, sizeof(arg) );
	int stage = StringToInt( arg );
	g_iSelectedStage[client] = stage;

	Timer_OpenSelectStyleMenu( client, ShowPBCP );
	
	return Plugin_Handled;
}

public void ShowPBCP( int client, int style )
{
	int stage = g_iSelectedStage[client] - 1;
	if( g_iPlayerRecordId[client][stage][ZoneTrack_Main][style] != -1 )
	{
		SQL_ShowStats( client, g_iPlayerRecordId[client][stage][ZoneTrack_Main][style] );
	}
	else
	{
		Timer_PrintToChat( client, "{primary}No records found" );
	}
}

public Action Command_Bonus_PBCP( int client, int args )
{
	if( args != 1 )
	{
		Timer_ReplyToCommand( client, "{primary}Usage: {secondary}sm_bpbcp <stage number>" );
		return Plugin_Handled;
	}
	
	char arg[16];
	GetCmdArg( 1, arg, sizeof(arg) );
	int stage = StringToInt( arg );
	g_iSelectedStage[client] = stage;

	Timer_OpenSelectStyleMenu( client, ShowBonusPBCP );
	
	return Plugin_Handled;
}

public void ShowBonusPBCP( int client, int style )
{
	int stage = g_iSelectedStage[client] - 1;
	if( g_iPlayerRecordId[client][stage][ZoneTrack_Main][style] != -1 )
	{
		SQL_ShowStats( client, g_iPlayerRecordId[client][stage][ZoneTrack_Main][style] );
	}
	else
	{
		Timer_PrintToChat( client, "{primary}No records found" );
	}
}

public Action Command_WRCP( int client, int args )
{
	if( args != 1 )
	{
		Timer_ReplyToCommand( client, "{primary}Usage: {secondary}sm_bpbcp <stage number>" );
		return Plugin_Handled;
	}
	
	char arg[16];
	GetCmdArg( 1, arg, sizeof(arg) );
	int stage = StringToInt( arg );
	g_iSelectedStage[client] = stage;
	
	Timer_OpenSelectStyleMenu( client, ShowWRCPMenu );
	
	return Plugin_Handled;
}

public void ShowWRCPMenu( int client, int style )
{
	int stage = g_iSelectedStage[client] - 1;
	ShowLeaderboard( client, stage, ZoneTrack_Main, style );
}

public Action Command_Bonus_WRCP( int client, int args )
{
	if( args != 1 )
	{
		Timer_ReplyToCommand( client, "{primary}Usage: {secondary}sm_bpbcp <stage number>" );
		return Plugin_Handled;
	}
	
	char arg[16];
	GetCmdArg( 1, arg, sizeof(arg) );
	int stage = StringToInt( arg );
	g_iSelectedStage[client] = stage;
	
	Timer_OpenSelectStyleMenu( client, ShowBonusWRCPMenu );
	
	return Plugin_Handled;
}

public void ShowBonusWRCPMenu( int client, int style )
{
	int stage = g_iSelectedStage[client] - 1;
	ShowLeaderboard( client, stage, ZoneTrack_Bonus, style );
}

void ShowLeaderboard( int client, int stage, int track, int style )
{
	if( !g_aMapTopTimes[stage][track][style].Length )
	{
		Timer_PrintToChat( client, "{primary}No records found" );
		return;
	}
	
	Menu menu = new Menu( WRCPMenu_Handler );
	
	char trackName[32];
	Timer_GetZoneTrackName( track, trackName, sizeof(trackName) );
	
	char styleName[32];
	Timer_GetStyleName( style, styleName, sizeof(styleName) );
	
	char buffer[256];
	Format( buffer, sizeof( buffer ), "%s %s %s Stage %i Leaderboard", trackName, styleName, g_cMapName, stage + 1 );
	menu.SetTitle( buffer );
	
	char sTime[32], info[8];
	
	int max = ( MAX_WRCP_CACHE > g_aMapTopTimes[stage][track][style].Length ) ? g_aMapTopTimes[stage][track][style].Length : MAX_WRCP_CACHE;
	Timer_DebugPrint( "ShowLeaderboard: max=%i", max );
	for( int i = 0; i < max; i++ )
	{
		char name[MAX_NAME_LENGTH];
		g_aMapTopNames[stage][track][style].GetString( i, name, sizeof(name) );
	
		Timer_FormatTime( g_aMapTopTimes[stage][track][style].Get( i ), sTime, sizeof(sTime) );
		
		Format( buffer, sizeof(buffer), "[#%i] - %s (%s)", i + 1, name, sTime );
		Format( info, sizeof(info), "%i,%i,%i", stage, track, style );
		
		menu.AddItem( info, buffer );
	}
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int WRCPMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char info[8];
		menu.GetItem( param2, info, sizeof( info ) );
		
		char infoSplit[3][4];
		ExplodeString( info, ",", infoSplit, sizeof(infoSplit), sizeof(infoSplit[]) );
		
		int stage = StringToInt( infoSplit[0] );
		int track = StringToInt( infoSplit[1] );
		int style = StringToInt( infoSplit[2] );
		Timer_DebugPrint( "WRCPMenu_Handler: stage=%i track=%i style=%i", stage, track, style );
		
		//Timer_DebugPrint( "WRCPMenu_Handler: Loaded record (recordid=%i, time=%f)", g_aMapTopTimes[track][style].Get( param2, 0 ), g_aMapTopTimes[track][style].Get( param2, 1 ) );
		
		SQL_ShowStats( param1, g_aMapTopRecordIds[stage][track][style].Get( param2 ) );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void ShowStats( int client, int stage, int track, int style, int recordid, const any recordData[RecordData] )
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
	Format( sInfo, sizeof( sInfo ), "%i,%i,%i,%i,%i", recordData[RD_PlayerID], stage, track, style, recordid );
	
	char buffer[512];
	Format( buffer, sizeof( buffer ), "%s - Stage %i - %s %s\n \n", g_cMapName, stage + 1, sTrack, settings[StyleName] );
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
		
		char sSplitString[5][16];
		ExplodeString( sInfo, ",", sSplitString, sizeof( sSplitString ), sizeof( sSplitString[] ) );
		
		//int playerid = StringToInt( sSplitString[0] );
		int stage = StringToInt( sSplitString[1] );
		int track = StringToInt( sSplitString[2] );
		int style = StringToInt( sSplitString[3] );
		int recordid = StringToInt( sSplitString[4] );
		
		switch( param2 )
		{
			case 0: // TODO: implement showing player stats here
			{
			}
			case 1: // delete time
			{
				SQL_DeleteRecord( recordid, stage, track, style );
			}
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}