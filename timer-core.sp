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

int			g_nPlayerFrames[MAXPLAYERS + 1];
bool			g_bTimerRunning[MAXPLAYERS + 1]; // whether client timer is running or not, regardless of if its paused
bool			g_bTimerPaused[MAXPLAYERS + 1];

ConVar		sv_autobunnyhopping
bool			g_bAutoBhop[MAXPLAYERS + 1];
bool			g_bNoclip[MAXPLAYERS + 1];

public void OnPluginStart()
{
	/* Forwards */
	g_hForward_OnDatabaseReady = CreateGlobalForward( "Timer_OnDatabaseReady", ET_Event );
	g_hForward_OnClientLoaded = CreateGlobalForward( "Timer_OnClientLoaded", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	
	/* Commands */
	RegConsoleCmd( "sm_nc", Command_Noclip );
	
	SQL_DBConnect();
	
	g_fFrameTime = GetTickInterval()
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

public void OnPlayerRunCmd( int client, int& buttons )
{
	if( IsValidClient( client, true ) )
	{
		if( g_bTimerRunning[client] && !g_bTimerPaused[client] )
		{
			g_nPlayerFrames[client]++;
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
	}
}


void StartTimer( int client )
{
	g_nPlayerFrames[client] = 0;
	g_bTimerRunning[client] = true;
	g_bTimerPaused[client] = false;
}

void StopTimer( int client )
{
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
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_players` ( playerid INT NOT NULL AUTO_INCREMENT, steamid CHAR( 32 ) NOT NULL, lastname CHAR( 64 ) NOT NULL, firstconnect INT( 16 ) NOT NULL, lastconnect INT( 16 ) NOT NULL, PRIMARY KEY ( `playerid` ) );" );
	txn.AddQuery( query );
	
	// Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_records` ( mapname VARCHAR( 128 ) NOT NULL, playerid INT NOT NULL, time INT( 8 ) NOT NULL, sync FLOAT NOT NULL, strafesync FLOAT NOT NULL, jumps INT NOT NULL, strafes INT NOT NULL, style INT NOT NULL, zonegroup INT NOT NULL, server VARCHAR( 18 ) NOT NULL, timestamp INT( 16 ) NOT NULL, PRIMARY KEY ( `mapname`, `playerid`, `style`, `zonegroup` ) );" );
	// put more thought into how you want to do this
	//txn.AddQuery( query );
	
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
			char[] name = new char[MAX_NAME_LENGTH * 2 + 1]; // worst case: every character is escaped + null character
			GetClientName( client, name, sizeof( name ) );
			g_hDatabase.Escape( name, sizeof( name ), name );
			
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
		
		char[] name = new char[MAX_NAME_LENGTH * 2 + 1]; // worst case: every character is escaped + null character
		GetClientName( client, name, sizeof( name ) );
		g_hDatabase.Escape( name, sizeof( name ), name );
		
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

void SQL_LoadPlayerData()
{
	// TODO: decide what to do here
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