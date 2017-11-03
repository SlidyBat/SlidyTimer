#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <slidy-timer>

#define TIMER_INTERVAL 0.1

/* Forwards */
Handle      g_hForward_OnEnterZone;
Handle      g_hForward_OnExitZone;

/* Globals */
bool        g_bLoaded;
Database    g_hDatabase;
char        g_cCurrentMap[PLATFORM_MAX_PATH];

bool        g_bZoning[MAXPLAYERS + 1];
int         g_iZoningStage[MAXPLAYERS + 1];
float       g_fZonePointCache[MAXPLAYERS + 1][2][3];

bool        g_bSnapToWall[MAXPLAYERS + 1] = { true, ... };

int         g_nZoningPlayers;

ArrayList   g_aZones;

ZoneType    g_PlayerCurrentZoneType[MAXPLAYERS + 1];
ZoneTrack   g_PlayerCurrentZoneTrack[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "Slidy's Timer - Zones component",
	author = "SlidyBat",
	description = "Zones component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public void OnPluginStart()
{
	CreateTimer( TIMER_INTERVAL, Timer_Zones, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE ); // creates timer that handles zone drawing
	g_aZones = new ArrayList( ZONE_DATA ); // arraylist that holds all current map zone data
	
	GetCurrentMap( g_cCurrentMap, sizeof( g_cCurrentMap ) );
	
	// Commands
	RegAdminCmd( "sm_zone", Command_Zone, ADMFLAG_CHANGEMAP );
	RegAdminCmd( "sm_zones", Command_Zone, ADMFLAG_CHANGEMAP );
	
	// Forwards
	g_hForward_OnEnterZone = CreateGlobalForward( "Timer_OnEnterZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnExitZone = CreateGlobalForward( "Timer_OnExitZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// zone natives
	CreateNative("Timer_GetClientZoneType", Native_GetClientZoneType);
	CreateNative("Timer_GetClientZoneTrack", Native_GetClientZoneTrack);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("timer-zones");

	return APLRes_Success;
}

public void OnClientDisconnnect( int client )
{
	StopZoning( client );
	g_bSnapToWall[client] = true;
}

public void OnMapStart()
{
	GetCurrentMap( g_cCurrentMap, sizeof( g_cCurrentMap ) );
}

public void OnMapEnd()
{
	g_aZones.Clear();
	g_bLoaded = false;
}

void StartZoning( int client )
{
	g_bZoning[client] = true;
	g_nZoningPlayers++;
	g_iZoningStage[client] = 0;
	
	OpenCreateZoneMenu( client );
}

void StopZoning( int client )
{
	g_bZoning[client] = false;
	g_nZoningPlayers--;
}

public void OpenZonesMenu( int client )
{
	char buffer[128];
	Menu menu = new Menu( ZonesMenuHandler );
	
	Format( buffer, sizeof( buffer ), "%s - Zones menu" );
	menu.SetTitle( buffer );
	
	menu.AddItem( "add", "Create zone" );
	menu.AddItem( "delete", "Delete zone" );
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int ZonesMenuHandler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		switch ( param2 )
		{
			case 0:
			{
				StartZoning( param1 );
			}
			case 1:
			{
				// OpenDeleteZoneMenu( client );
				// TODO: implement zone deletion
			}
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void OpenCreateZoneMenu( int client )
{
	char buffer[128];
	
	Menu menu = new Menu( CreateZoneMenuHandler );
	
	Format( buffer, sizeof( buffer ), "%s - Creating zone", MENU_PREFIX );
	menu.SetTitle( buffer );
	
	if( g_iZoningStage[client] < 2 )
	{
		Format( buffer, sizeof( buffer ), "Set point %i\n \n", g_iZoningStage[client] + 1 );
		menu.AddItem( "select", buffer );
	}
	else
	{
		// zone saving
	}
}

public int CreateZoneMenuHandler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		if( g_iZoningStage[param1] < 2 )
		{
			GetClientAbsOrigin( param1, g_fZonePointCache[param1][g_iZoningStage[param1]] );
			g_iZoningStage[param1]++;
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

stock void AddZone( const any zone[ZONE_DATA] )
{
	int index = g_aZones.Length;
	g_aZones.PushArray( zone );

	int entity = CreateEntityByName( "trigger_multiple" );

	if( IsValidEntity( entity ) )
	{
		SetEntityModel( entity, "models/props/de_train/barrel.mdl" );

		char name[128];
		Format( C_buffer, 512, "%i: Timer_Zone", index );

		DispatchKeyValue( I_Entity, "spawnflags", "257" );
		DispatchKeyValue( I_Entity, "StartDisabled", "0" );
		DispatchKeyValue( I_Entity, "targetname", name );

		if( DispatchSpawn( entity ) )
		{
			ActivateEntity( entity );
			
			float midpoint[3];
			float pointA[3], pointB[3];
			float mins[3], maxs[3];
			
			for( int i = 0; i < 3; i++ )
			{
				pointA[i] = zone[x1 + i];
				pointB[i] = zone[x1 + i + 3];
				midpoint[i] = ( pointA[i] + pointB[i] ) / 2.0;
			}
			midpoint[2] = pointA[2];

			MakeVectorFromPoints( midpoint, pointA, mins );
			MakeVectorFromPoints( pointB, midpoint, maxs );

			for( int i = 0; i < 3; i++ )
			{
				if( mins[i] > 0 )
				{
					mins[i] = -mins[i];
				}
				if( maxs[i] < 0 )
				{
					maxs[i] = -maxs[i];
				}
				
				mins[i] += 16;
				maxs[i] -= 16;
			}

			SetEntPropVector( entity, Prop_Send, "m_vecMins", mins );
			SetEntPropVector( entity, Prop_Send, "m_vecMaxs", maxs );

			SetEntProp( entity, Prop_Send, "m_nSolidType", 2 );
			SetEntProp( entity, Prop_Send, "m_fEffects", GetEntProp( entity, Prop_Send, "m_fEffects" ) | 32 );

			TeleportEntity( entity, midpoint, NULL_VECTOR, NULL_VECTOR );
			SDKHook( entity, SDKHook_StartTouch, Entity_StartTouch );
			SDKHook( entity, SDKHook_EndTouch, Entity_EndTouch );
		}
	}
}

stock void ClearZones()
{
	if( g_aZones.Length )
	{
		char name[512];
	
		for( int i = MaxClients + 1; i <= GetMaxEntities(); i++ )
		{
			if( IsValidEdict( i ) && IsValidEntity( i ) )
			{
				if( GetEntPropString( i, Prop_Data, "m_iName", name, sizeof( name ) ) )
				{
					if( StrContains( name, "Timer_Zone" ) > -1 )
					{
						AcceptEntityInput( i, "Kill" );
					}
				}
			}
		}
		
		g_aZones.Clear();
	}
}

stock void DrawZone( any zone[ZONE_DATA], int client = 0 )
{
	float points[8][3];
	
	for( int i = 0; i < 3; i++ )
	{
		points[0][i] = zone[i];
		points[7][i] = zone[i + 3];
	}
	
	CreateZonePoints( points );
	
	// int color[] = { 255, 178, 0, 255 };
	
	for( int i = 0 , i2 = 3; i2 >= 0; i += i2-- )
	{
		for( int j = 1; j <= 7; j += ( j / 2 ) + 1 )
		{
			if( j != 7 - i )
			{
				// TE_SetupBeamPoints( points[i], points[j], g_Sprites[0], g_Sprites[1], 0, 0, 1.0, 5.0, 5.0, 0, 0.0, color, 0);
				// TODO: load zone sprites
				
				if(0 < client <= MaxClients)
				{
					TE_SendToClient( client, 0.0 );
				}
				else
				{
					TE_SendToAll(0.0);
				}
			}
		}
	}
}


/* Hooks */

public Action Entity_StartTouch( int caller, int activator )
{
	if( IsValidClient( activator ) )
	{
		char entName[512];
		GetEntPropString( caller, Prop_Data, "m_iName", entName, sizeof( entName ) );
		
		char zoneIndex[8];
		SplitString( entName, ":", zoneIndex, sizeof( zoneIndex ) );

		int index = StringToInt( zoneIndex );
		ZoneType zoneType = view_as<ZoneType>( g_aZones.Get( index, view_as<int>( ZD_ZoneType ) ) );
		ZoneTrack zoneTrack = view_as<ZoneTrack>( g_aZones.Get( index, view_as<int>( ZD_ZoneTrack ) ) );

		Call_StartForward( g_hForward_OnEnterZone );
		Call_PushCell( activator );
		Call_PushCell( g_aZones.Get( index, ZD_ZoneId ) );
		Call_PushCell( zoneType );
		Call_PushCell( zoneTrack );
		Call_PushCell( g_aZones.Get( index, ZD_ZoneSubindex ) );
		Call_Finish();
		
		g_PlayerCurrentZoneType[activator] = zoneType;
		g_PlayerCurrentZoneTrack[activator] = zoneTrack;
	}
}

public Action Entity_EndTouch( int caller, int activator )
{
	if( IsValidClient( activator ) )
	{
		char entName[512];
		GetEntPropString( caller, Prop_Data, "m_iName", entName, sizeof( entName ) );
		
		char zoneIndex[8];
		SplitString( entName, ":", zoneIndex, sizeof( zoneIndex ) );

		int index = StringToInt( zoneIndex );
		ZoneType zoneType = view_as<ZoneType>( g_aZones.Get( index, view_as<int>( ZD_ZoneType ) ) );
		ZoneTrack zoneTrack = view_as<ZoneTrack>( g_aZones.Get( index, view_as<int>( ZD_ZoneTrack ) ) );

		Call_StartForward( g_hForward_OnExitZone );
		Call_PushCell( activator );
		Call_PushCell( g_aZones.Get( index, ZD_ZoneId ) );
		Call_PushCell( zoneType );
		Call_PushCell( zoneTrack );
		Call_PushCell( g_aZones.Get( index, ZD_ZoneSubindex ) );
		Call_Finish();
		
		g_PlayerCurrentZoneType[activator] = Zone_None;
	}
}


/* Commands */

public Action Command_Zone( int client, int args ) // TODO: determine if players should be permitted to zone before zones have been loaded
{
	OpenZonesMenu( client );
	
	return Plugin_Handled;
}


/* Timers */

public Action Timer_Zones( Handle timer, any data )
{
	if( g_nZoningPlayers > 0 )
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( g_bZoning[i] )
			{
				// DrawZoningPoints( i );
				// TODO: implement function to draw points for players that are zoning
			}
		}
	}
	
	if( g_bLoaded && g_aZones.Length )
	{
		for( int i = 0; i < g_aZones.Length; i++ )
		{
			any zone[ZONE_DATA];
			g_aZones.GetArray( i, zone );
			
			DrawZone( zone );
		}
	}
}


/* Natives */

public int Native_GetClientZoneType(Handle handler, int numParams)
{
	return view_as<int>( g_PlayerCurrentZoneType[GetNativeCell( 1 )] );
}

public int Native_GetClientZoneTrack(Handle handler, int numParams)
{
	return view_as<int>( g_PlayerCurrentZoneTrack[GetNativeCell( 1 )] );
}


/* Database stuff */

public void OnDatabaseLoaded()
{
	Timer_GetDatabase( g_hDatabase );
	SQL_CreateTables();
	SQL_LoadZones();
}

void SQL_CreateTables()
{
	Transaction txn = SQL_CreateTransaction();
	
	char query[512];
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_zones` ( mapname VARCHAR( 128 ) NOT NULL, zoneid INT NOT NULL AUTO_INCREMENT, zonetype INT NOT NULL, zonegroup INT NOT NULL, a_x FLOAT NOT NULL, a_y FLOAT NOT NULL, a_z FLOAT NOT NULL, b_x FLOAT NOT NULL, b_y FLOAT NOT NULL, b_z FLOAT NOT NULL, checkpointid INT NOT NULL, PRIMARY KEY ( `zoneid` ) );" );
	txn.AddQuery( query );
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_checkpoints` ( mapname VARCHAR( 128 ) NOT NULL, uid INT NOT NULL, checkpointid INT NOT NULL, checkpointtime INT NOT NULL, style INT NOT NULL, zonegroup INT NOT NULL, PRIMARY KEY ( `mapname`, `uid`, `checkpointid`, `style`, `zonegroup` ) );" );
	txn.AddQuery( query );
	
	g_hDatabase.Execute( txn, SQL_OnCreateTableSuccess, SQL_OnCreateTableFailure, _, DBPrio_High );
}

public void SQL_OnCreateTableSuccess( Database db, any data, int numQueries, DBResultSet[] results, any[] queryData )
{
	SQL_LoadZones();
}

public void SQL_OnCreateTableFailure( Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData )
{
	SetFailState( "[SQL ERROR] (SQL_CreateTables) - %s", error );
}

void SQL_LoadZones()
{
	char query[512];
	
	Format( query, sizeof( query ), "SELECT * FROM `t_zones` WHERE mapname = '%s' ORDER BY `zonied` ASC", g_cCurrentMap );
	g_hDatabase.Query( LoadZones_Callback, query, _, DBPrio_High );
}

public void LoadZones_Callback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LogLoadZonesCallback) - %s", error );
		return;
	}
	
	if( results.RowCount > 0 )
	{
		ClearZones();
		// any zone[ZONE_DATA];

		while( results.FetchRow() )
		{
			/* id,
			index, // index used for zone types that can have more than one of same zone, ie. checkpoint/anticheat
			Float:x1,
			Float:y1,
			Float:z1,
			Float:x2,
			Float:y2,
			Float:z2,
			ZoneType:type,
			ZoneTrack:track
			ZONE_DATA */
			
			// TODO: figure out how zones should be loaded
		}
	}
	
	g_bLoaded = true;
}

/* Stocks */

stock void CreateZonePoints( float point[8][3] )
{
	for( int i = 1; i < 7; i++ )
	{
		for( int j = 0; j < 3; j++ )
		{
			point[i][j] = point[((i >> (2-j)) & 1) * 7][j];
		}
	}
}