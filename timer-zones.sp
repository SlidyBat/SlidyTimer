#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <slidy-timer>

#define TIMER_INTERVAL 1.0

enum
{
	GlowSprite,
	HaloSprite,
	BlueLightning,
	Barrel,
	TOTAL_SPRITES
}

/* Forwards */
Handle      g_hForward_OnEnterZone;
Handle      g_hForward_OnExitZone;

/* Globals */
bool			g_bLoaded;
Database		g_hDatabase;
char			g_cCurrentMap[PLATFORM_MAX_PATH];

bool			g_bZoning[MAXPLAYERS + 1];
int			g_iZoningStage[MAXPLAYERS + 1];
ZoneTrack	g_ztCurrentSelectedTrack[MAXPLAYERS + 1];
float		g_fZonePointCache[MAXPLAYERS + 1][2][3];

bool			g_bSnapToWall[MAXPLAYERS + 1] = { true, ... };
bool        g_bZoneEyeAngle[MAXPLAYERS + 1];

int         g_nZoningPlayers;

int         g_Sprites[TOTAL_SPRITES];

ArrayList   g_aZones;
ArrayList   g_aZoneSpawnCache;

ZoneType    g_PlayerCurrentZoneType[MAXPLAYERS + 1];
ZoneTrack   g_PlayerCurrentZoneTrack[MAXPLAYERS + 1];
int			g_PlayerCurrentZoneSubIndex[MAXPLAYERS + 1];

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
	g_aZones = new ArrayList( ZONE_DATA ); // arraylist that holds all current map zone data
	g_aZoneSpawnCache = new ArrayList( 3 );
	
	GetCurrentMap( g_cCurrentMap, sizeof( g_cCurrentMap ) );
	
	// Commands
	RegAdminCmd( "sm_zone", Command_Zone, ADMFLAG_CHANGEMAP );
	RegAdminCmd( "sm_zones", Command_Zone, ADMFLAG_CHANGEMAP );
	RegConsoleCmd( "sm_test", Command_Test );
	
	RegConsoleCmd( "sm_r", Command_Restart );
	RegConsoleCmd( "sm_restart", Command_Restart );
	RegConsoleCmd( "sm_start", Command_Restart );
	RegConsoleCmd( "sm_b", Command_Bonus );
	RegConsoleCmd( "sm_bonus", Command_Bonus );
	
	AddCommandListener( Command_JoinTeam, "jointeam" );
	
	
	// Forwards
	g_hForward_OnEnterZone = CreateGlobalForward( "Timer_OnEnterZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnExitZone = CreateGlobalForward( "Timer_OnExitZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );

	HookEvent( "round_start", Hook_RoundStartPost, EventHookMode_Post );
	
	if( LibraryExists( "timer-core" ) )
	{
		g_hDatabase = Timer_GetDatabase();
		SetSQLInfo();
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// zone natives
	CreateNative( "Timer_GetClientZoneType", Native_GetClientZoneType );
	CreateNative( "Timer_GetClientZoneTrack", Native_GetClientZoneTrack );
	CreateNative( "Timer_TeleportClientToZone", Native_TeleportClientToZone );

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("timer-zones");

	return APLRes_Success;
}

public void OnLibraryAdded( const char[] name )
{
	if(StrEqual(name, "timer-core"))
	{
		g_hDatabase = Timer_GetDatabase();
		SetSQLInfo();
	}
}

public void OnMapStart()
{
	GetCurrentMap( g_cCurrentMap, sizeof( g_cCurrentMap ) );
	
	g_Sprites[GlowSprite] = PrecacheModel( "materials/sprites/blueglow1.vmt" );
	g_Sprites[HaloSprite] = PrecacheModel( "materials/sprites/glow01.vmt" );
	g_Sprites[BlueLightning] = PrecacheModel( "materials/sprites/trails/bluelightningscroll3.vmt" );
	g_Sprites[Barrel] = PrecacheModel( "models/props/de_train/barrel.mdl" );
	
	AddFileToDownloadsTable( "materials/sprites/trails/bluelightningscroll3.vmt" );
	AddFileToDownloadsTable( "materials/sprites/trails/bluelightningscroll3.vtf" );
	
	CreateTimer( TIMER_INTERVAL, Timer_DrawZones, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
	
	SQL_LoadZones();
}

public void OnMapEnd()
{
	g_aZones.Clear();
	g_aZoneSpawnCache.Clear();
	g_bLoaded = false;
}

public void OnClientDisconnnect( int client )
{
	StopZoning( client );
	g_bSnapToWall[client] = true;
	g_bZoneEyeAngle[client] = false;
}

void StartZoning( int client )
{
	if( g_bZoning[client] == false )
	{
		g_bZoning[client] = true;
		g_nZoningPlayers++;
		g_iZoningStage[client] = 0;
	}
	
	OpenCreateZoneMenu( client );
}

void StopZoning( int client )
{
	g_bZoning[client] = false;
	g_nZoningPlayers--;
}

int GetZoneTypeCount( ZoneType zoneType )
{
	int length = g_aZones.Length;
	
	if( !length )
	{
		return 0;
	}
	
	int count = 0;
	for( int i = 0; i < length; i++ )
	{
		if( g_aZones.Get( i, ZD_ZoneType ) == zoneType )
		{
			count++;
		}
	}
	
	return count;
}

void OpenZonesMenu( int client )
{
	char buffer[128];
	Menu menu = new Menu( ZonesMenuHandler );
	
	Format( buffer, sizeof( buffer ), "Timer - Zones menu" );
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

void TeleportClientToZone( int client, ZoneType zoneType, ZoneTrack zoneTrack, int subindex = 0 )
{
	int index = GetZoneIndex( zoneType, zoneTrack, subindex );
	
	if( index == -1 )
	{
		char sZoneType[64], sZoneTrack[64];
		Timer_GetZoneTypeName( zoneType, sZoneType, sizeof( sZoneType ) );
		Timer_GetZoneTrackName( zoneTrack, sZoneTrack, sizeof( sZoneTrack ) );
		PrintToChat( client, "[Timer] %s %s zone does not exist", sZoneTrack, sZoneType );
		
		return;
	}
	
	if( !IsPlayerAlive( client ) )
	{
		CS_RespawnPlayer( client );
	}
	
	float spawn[3];
	g_aZoneSpawnCache.GetArray( index, spawn );
	
	Timer_StopTimer( client );
	g_PlayerCurrentZoneType[client] = zoneType;
	g_PlayerCurrentZoneTrack[client] = zoneTrack;
	g_PlayerCurrentZoneSubIndex[client] = subindex;
	
	TeleportEntity( client, spawn, NULL_VECTOR, view_as<float>( { 0.0, 0.0, 0.0 } ) );
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
		char zonename[64];
		Timer_GetZoneTrackName( g_ztCurrentSelectedTrack[client], zonename, sizeof( zonename ) );
		Format( buffer, sizeof( buffer ), "Select Track: %s\n \n", zonename );
		menu.AddItem( "track", buffer );
		
		for( int i = 0; i < view_as<int>( TOTAL_ZONE_TYPES ); i++ )
		{
			Timer_GetZoneTypeName( view_as<ZoneType>( i ), zonename, sizeof( zonename ) );
			menu.AddItem( zonename, zonename );
		}
	}
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int CreateZoneMenuHandler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		if( g_iZoningStage[param1] < 2 )
		{
			GetZoningPoint( param1, g_fZonePointCache[param1][g_iZoningStage[param1]] );
			
			if( g_iZoningStage[param1] == 1 )
			{
				g_fZonePointCache[param1][1][2] += 150.0;
			}
			
			g_iZoningStage[param1]++;
			
			OpenCreateZoneMenu( param1 );
		}
		else
		{
			switch( param2 )
			{
				case 0: // Clicked "Select Track"
				{
					g_ztCurrentSelectedTrack[param1]++;
					
					if( g_ztCurrentSelectedTrack[param1] == TOTAL_ZONE_TRACKS )
					{
						g_ztCurrentSelectedTrack[param1] = ZT_Main;
					}
					
					OpenCreateZoneMenu( param1 );
				}
				default:
				{
					ZoneType zoneType = view_as<ZoneType>( param2 - 1 );
					ZoneTrack zoneTrack = g_ztCurrentSelectedTrack[param1];
					
					int subindex = ( zoneType >= Zone_Checkpoint ) ? GetZoneTypeCount( zoneType ) : 0;
					SQL_InsertZone( g_fZonePointCache[param1][0], g_fZonePointCache[param1][1], zoneType, zoneTrack, subindex );
					g_iZoningStage[param1] = 0;
					OpenCreateZoneMenu( param1 );
				}
			}
			
		}
	}
	else if( action == MenuAction_Cancel )
	{
		StopZoning( param1 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void GetZoningPoint( int client, float pos[3] )
{
	if( g_bZoneEyeAngle[client] )
	{
		GetEyeAnglePosition( client, pos );
	}
	else
	{
		GetClientAbsOrigin( client, pos );
	}

	SnapToGrid( pos, 1.0 ); // SNAPS TO GRID, MIGHT MAKE SETTING LATER
	
	// TODO: maybe implement zone to edge

	if( g_bSnapToWall[client] )
	{
		GetWallSnapPosition( client, pos );
	}
}

void SnapToGrid( float pos[3], float gridsnap )
{
	for( int i = 0; i < 2; i++ )
	{
		pos[i] = RoundFloat( pos[i] / gridsnap ) * gridsnap;
	}
}

void GetWallSnapPosition( int client, float pos[3] )
{
	float end[3];
	
	for( int i = 0; i < 4; i++ )
	{
		end = pos;
		end[i / 2] += ( i % 2 ) ? -23.0 : 23.0;

		TR_TraceRayFilter( pos, end, MASK_SOLID, RayType_EndPoint, TraceRay_NoClient, client );

		if( TR_DidHit() )
		{
			TR_GetEndPosition( end );
			pos[i / 2] = end[i / 2];
		}
	}
}

stock void AddZoneEntity( const any zone[ZONE_DATA], int index )
{
	int entity = CreateEntityByName( "trigger_multiple" );

	if( IsValidEntity( entity ) )
	{
		SetEntityModel( entity, "models/props/de_train/barrel.mdl" );

		char name[128];
		Format( name, sizeof( name ), "%i: Timer_Zone", index );

		DispatchKeyValue( entity, "spawnflags", "257" );
		DispatchKeyValue( entity, "StartDisabled", "0" );
		DispatchKeyValue( entity, "targetname", name );

		if( DispatchSpawn(entity) )
		{
			ActivateEntity( entity );
			
			float midpoint[3];
			float pointA[3], pointB[3];
			float mins[3], maxs[3];
			
			for( int i = 0; i < 3; i++ )
			{
				pointA[i] = zone[ZD_x1 + i];
				pointB[i] = zone[ZD_x2 + i];
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

stock void AddZone( const any zone[ZONE_DATA] )
{
	int index = g_aZones.Length;
	g_aZones.PushArray( zone );
	
	float spawn[3];
	
	for( int i = 0; i < 3; i++ )
	{
		spawn[i] = ( view_as<float>( zone[ZD_x1 + i] ) + view_as<float>( zone[ZD_x2 + i] ) ) / 2.0;
	}
	spawn[2] = view_as<float>( zone[ZD_z1] ) + 10.0;
	g_aZoneSpawnCache.PushArray( spawn );

	AddZoneEntity( zone, index );
}

stock int GetZoneID( ZoneType zoneType, ZoneTrack zoneTrack, int subindex = 0 ) // database id
{
	for( int i = 0; i < g_aZones.Length; i++ )
	{
		if( g_aZones.Get( i, ZD_ZoneType ) == zoneType
			&& g_aZones.Get( i, ZD_ZoneTrack ) == zoneTrack
			&& g_aZones.Get( i, ZD_ZoneSubindex ) == subindex )
		{
			return g_aZones.Get( i, ZD_ZoneId );
		}
	}
	
	return -1;
}

stock int GetZoneIndex( ZoneType zoneType, ZoneTrack zoneTrack, int subindex = 0 ) // array index
{
	for( int i = 0; i < g_aZones.Length; i++ )
	{
		if( g_aZones.Get( i, ZD_ZoneType ) == zoneType
			&& g_aZones.Get( i, ZD_ZoneTrack ) == zoneTrack
			&& g_aZones.Get( i, ZD_ZoneSubindex ) == subindex )
		{
			return i;
		}
	}
	
	return -1;
}

stock void ClearZoneEntities()
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
}

stock void ReloadZoneEntities()
{
	if( g_aZones.Length )
	{
		ClearZoneEntities();
		
		for( int i = 0; i < g_aZones.Length; i++ )
		{
			any zone[ZONE_DATA];
			g_aZones.GetArray( i, zone );
			
			AddZoneEntity( zone, i );
		}
	}
}

stock void ClearZones()
{
	if( g_aZones.Length )
	{
		ClearZoneEntities();
		g_aZones.Clear();
		g_aZoneSpawnCache.Clear();
	}
}

stock void DrawZoneFromPoints( float points[8][3], const int color[4] = { 255, 178, 0, 255 }, int client = 0 )
{
	CreateZonePoints( points );
	
	for( int i = 0 , i2 = 3; i2 >= 0; i += i2-- )
	{
		for( int j = 1; j <= 7; j += ( j / 2 ) + 1 )
		{
			if( j != 7 - i )
			{
				TE_SetupBeamPoints( points[i], points[j], g_Sprites[BlueLightning], g_Sprites[HaloSprite], 0, 0, TIMER_INTERVAL, 5.0, 5.0, 0, 0.0, color, 0);
				
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

stock void DrawZone( const any zone[ZONE_DATA], int client = 0 )
{
	float points[8][3];
	
	for( int i = 0; i < 3; i++ )
	{
		points[0][i] = zone[ZD_x1 + i];
		points[7][i] = zone[ZD_x2 + i];
	}
	
	int colour[4];
	Timer_GetZoneColour( zone[ZD_ZoneType], zone[ZD_ZoneTrack], colour );
	
	DrawZoneFromPoints( points, colour, client );
}


/* Hooks */

public Action Hook_RoundStartPost( Event event, const char[] name, bool dontBroadcast )
{
	ReloadZoneEntities(); // re-hook zones because hooks disappear on round start

	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsValidClient( i, true ) )
		{
			TeleportClientToZone( i, Zone_Start, ZT_Main );
		}
	}
}

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
		int subindex = g_aZones.Get( index, view_as<int>( ZD_ZoneSubindex ) );
		
		Call_StartForward( g_hForward_OnEnterZone );
		Call_PushCell( activator );
		Call_PushCell( g_aZones.Get( index, ZD_ZoneId ) );
		Call_PushCell( zoneType );
		Call_PushCell( zoneTrack );
		Call_PushCell( g_aZones.Get( index, ZD_ZoneSubindex ) );
		Call_Finish();
		
		g_PlayerCurrentZoneType[activator] = zoneType;
		g_PlayerCurrentZoneSubIndex[activator] = subindex;
		
		if( zoneType == Zone_Start )
		{
			g_PlayerCurrentZoneTrack[activator] = zoneTrack;
		}
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

public Action Command_Restart( int client, int args )
{
	if( IsValidClient( client ) )
	{		
		if( !IsPlayerAlive( client ) )
		{
			ChangeClientTeam( client, CS_TEAM_T );
		}
		TeleportClientToZone( client, Zone_Start, ZT_Main );
	}
	
	return Plugin_Handled;
}

public Action Command_Bonus( int client, int args )
{
	if( IsValidClient( client ) )
	{	
		if( !IsPlayerAlive( client ) )
		{
			ChangeClientTeam( client, CS_TEAM_T );
		}
		TeleportClientToZone( client, Zone_Start, ZT_Bonus );
	}
	
	return Plugin_Handled;
}

public Action Command_JoinTeam( int client, const char[] command, int args )
{
	if( !IsValidClient( client ) )
		return Plugin_Continue;
	
	char arg[32];
	int value;

	GetCmdArg( 1, arg, 32 );
	value = StringToInt( arg );
	ChangeClientTeam( client, value );

	if( value > 1 )
	{
		TeleportClientToZone( client, Zone_Start, ZT_Main );
	}

	return Plugin_Handled;
}

public Action Command_Test( int client, int args ) // TODO: determine if players should be permitted to zone before zones have been loaded
{
	PrintZones();
	
	return Plugin_Handled;
}


/* Timers */

public Action Timer_DrawZones( Handle timer, any data )
{
	if( g_nZoningPlayers > 0 )
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( g_bZoning[i] )
			{
				if( g_iZoningStage[i] == 0 )
				{
					float pos[3];
					GetZoningPoint( i, pos );

					TE_SetupGlowSprite( pos, g_Sprites[GlowSprite], 0.1, 0.1, 100 );
					TE_SendToClient( i );
				}
				else if( g_iZoningStage[i] == 1 )
				{
					float pos[3];
					GetZoningPoint( i, pos );
					pos[2] += 150.0;
					
					float points[8][3];
					points[0] = g_fZonePointCache[i][0];
					points[7] = pos;
					
					DrawZoneFromPoints( points, { 255, 255, 102, 255 } );
					
					TE_SetupGlowSprite( g_fZonePointCache[i][0], g_Sprites[GlowSprite], 0.1, 0.1, 100 );
					TE_SendToClient( i );
					
					TE_SetupGlowSprite( pos, g_Sprites[GlowSprite], 0.1, 0.1, 100 );
					TE_SendToClient( i );
				}
				else
				{
					float points[8][3];
					points[0] = g_fZonePointCache[i][0];
					points[7] = g_fZonePointCache[i][1];
					
					DrawZoneFromPoints( points, { 255, 255, 102, 255 } );
					
					TE_SetupGlowSprite( g_fZonePointCache[i][0], g_Sprites[GlowSprite], 0.1, 0.1, 100 );
					TE_SendToClient( i );
					
					TE_SetupGlowSprite( g_fZonePointCache[i][1], g_Sprites[GlowSprite], 0.1, 0.1, 100 );
					TE_SendToClient( i );
				}
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

public int Native_TeleportClientToZone(Handle handler, int numParams)
{
	TeleportClientToZone( GetNativeCell( 1 ), view_as<ZoneType>( GetNativeCell( 2 ) ), view_as<ZoneTrack>( GetNativeCell( 3 ) ), GetNativeCell( 4 ) );
}

/* Database stuff */

public void OnDatabaseLoaded()
{
	g_hDatabase = Timer_GetDatabase();
	SQL_CreateTables();
}

public Action CheckForSQLInfo( Handle timer, any data )
{
	return SetSQLInfo();
}

Action SetSQLInfo()
{
	if( g_hDatabase == null )
	{
		g_hDatabase = Timer_GetDatabase();
		CreateTimer( 0.5, CheckForSQLInfo );
	}
	else
	{
		SQL_CreateTables();
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void SQL_CreateTables()
{
	if( g_bLoaded )
	{
		return;
	}
	
	Transaction txn = SQL_CreateTransaction();
	
	char query[512];
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_zones` (mapname CHAR(128) NOT NULL, zoneid INT NOT NULL AUTO_INCREMENT, subindex INT NOT NULL, zonetype INT NOT NULL, zonetrack INT NOT NULL, a_x FLOAT NOT NULL, a_y FLOAT NOT NULL, a_z FLOAT NOT NULL, b_x FLOAT NOT NULL, b_y FLOAT NOT NULL, b_z FLOAT NOT NULL, PRIMARY KEY (`zoneid`));" );
	txn.AddQuery( query );
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_checkpoints` (mapname CHAR(128) NOT NULL, playerid INT NOT NULL, subindex INT NOT NULL, checkpointtime INT NOT NULL, style INT NOT NULL, zonetrack INT NOT NULL, PRIMARY KEY (`mapname`, `playerid`, `subindex`, `style`, `zonetrack`));" );
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
	
	Format( query, sizeof( query ), "SELECT zoneid, subindex, zonetype, zonetrack, a_x, a_y, a_z, b_x, b_y, b_z FROM `t_zones` WHERE mapname = '%s' ORDER BY `zoneid` ASC", g_cCurrentMap );
	g_hDatabase.Query( LoadZones_Callback, query, _, DBPrio_High );
}

public void LoadZones_Callback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadZones_Callback) - %s", error );
		return;
	}
	
	if( results.RowCount > 0 )
	{
		ClearZones();

		while( results.FetchRow() )
		{
			any zone[ZONE_DATA];
			
			zone[ZD_ZoneId] = results.FetchInt( 0 );
			zone[ZD_ZoneSubindex] = results.FetchInt( 1 );
			zone[ZD_ZoneType] = view_as<ZoneType>( results.FetchInt( 2 ) );
			zone[ZD_ZoneTrack] = view_as<ZoneType>( results.FetchInt( 3 ) );
			zone[ZD_x1] = results.FetchFloat( 4 );
			zone[ZD_y1] = results.FetchFloat( 5 );
			zone[ZD_z1] = results.FetchFloat( 6 );
			zone[ZD_x2] = results.FetchFloat( 7 );
			zone[ZD_y2] = results.FetchFloat( 8 );
			zone[ZD_z2] = results.FetchFloat( 9 );
			
			AddZone( zone );
		}
	}
	
	g_bLoaded = true;
}

void SQL_InsertZone( float pointA[3], float pointB[3], ZoneType zoneType, ZoneTrack zoneTrack, int subindex = 0 )
{
	char query[512];
	
	// swap zones to ensure bottom point is pointA and top point is pointB
	if( pointA[2] > pointB[2] )
	{
		float temp;
		for( int i = 0; i < 3; i++ )
		{
			temp = pointA[i];
			pointA[i] = pointB[i];
			pointB[i] = temp;
		}
	}
	
	int id = GetZoneID( zoneType, zoneTrack );
	
	if( zoneType >= Zone_Checkpoint || id == -1 )
	{
		// insert the zone
		Format( query, sizeof( query ), "INSERT INTO `t_zones` (mapname, zoneid, subindex, zonetype, zonetrack, a_x, a_y, a_z, b_x, b_y, b_z) VALUES ('%s', '0', '%i', '%i', '%i', '%.3f', '%.3f', '%.3f', '%.3f', '%.3f', '%.3f')", g_cCurrentMap, subindex, view_as<int>( zoneType ), view_as<int>( zoneTrack ), pointA[0], pointA[1], pointA[2], pointB[0], pointB[1], pointB[2] );
	}
	else
	{
		// replace current zone
		Format( query, sizeof( query ), "UPDATE `t_zones` SET a_x = '%.3f', a_y = '%.3f', a_z = '%.3f', b_x = '%.3f', b_y = '%.3f', b_z = '%.3f' WHERE zoneid = '%i'", pointA[0], pointA[1], pointA[2], pointB[0], pointB[1], pointB[2], id );
	}
	
	g_hDatabase.Query( InsertZone_Callback, query, _, DBPrio_High );
}

public void InsertZone_Callback( Database db, DBResultSet results, const char[] error, any data )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertZone_Callback) - %s", error );
		return;
	}
	
	ClearZones();
	SQL_LoadZones();
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

public void GetEyeAnglePosition( int client, float pos[3] )
{
	float eyePos[3], angles[3];

	GetClientEyeAngles( client, angles );
	GetClientEyePosition( client, eyePos );

	TR_TraceRayFilter( eyePos, angles, MASK_SOLID, RayType_Infinite, TraceRay_NoClient, client );

	if( TR_DidHit( INVALID_HANDLE ) )
	{
		TR_GetEndPosition( pos );
	}
}

public bool TraceRay_NoClient( int entity, int contentsMask, any data )
{
	return ( entity != data && !IsValidClient( data ) );
}

stock void PrintZones()
{
	for( int i = 0; i < g_aZones.Length; i++ )
	{
		any zone[ZONE_DATA];
		g_aZones.GetArray( i, zone );
		
		for( int j = 0; j < ZONE_DATA; j++ )
		{
			char buffer[512];
			Format( buffer, sizeof( buffer ), "%i", zone[j] );
			PrintToServer( buffer );
		}
	}
}