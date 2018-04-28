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

float			g_fFrameTime;
char			g_cMapName[PLATFORM_MAX_PATH];

Handle		g_hForward_OnDatabaseLoaded;
Handle		g_hForward_OnClientLoaded;
Handle		g_hForward_OnStylesLoaded;
Handle		g_hForward_OnStyleChangedPre;
Handle		g_hForward_OnStyleChangedPost;
Handle		g_hForward_OnFinishPre;
Handle		g_hForward_OnFinishPost;
Handle		g_hForward_OnWRBeaten;
Handle		g_hForward_OnTimerStart;

int			g_iPlayerId[MAXPLAYERS + 1] = { -1, ... };

ArrayList		g_aMapTopRecordIds[TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList		g_aMapTopTimes[TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList		g_aMapTopNames[TOTAL_ZONE_TRACKS][MAX_STYLES];

any			g_StyleSettings[MAX_STYLES][styleSettings];
StringMap		g_smStyleCommands;
int			g_iTotalStyles;

/* Player Data */
int			g_iPlayerRecordId[MAXPLAYERS + 1][TOTAL_ZONE_TRACKS][MAX_STYLES];
float			g_fPlayerPersonalBest[MAXPLAYERS + 1][TOTAL_ZONE_TRACKS][MAX_STYLES];
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

bool			g_bNoclip[MAXPLAYERS + 1];

int			g_iClientBlockTickStart[MAXPLAYERS + 1];
int			g_nClientBlockTicks[MAXPLAYERS + 1];

ConVar		sv_autobunnyhopping;

public void OnPluginStart()
{
	/* Forwards */
	g_hForward_OnDatabaseLoaded = CreateGlobalForward( "Timer_OnDatabaseLoaded", ET_Event );
	g_hForward_OnClientLoaded = CreateGlobalForward( "Timer_OnClientLoaded", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnStylesLoaded = CreateGlobalForward( "Timer_OnStylesLoaded", ET_Event, Param_Cell );
	g_hForward_OnStyleChangedPre = CreateGlobalForward( "Timer_OnStyleChangedPre", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnStyleChangedPost = CreateGlobalForward( "Timer_OnStyleChangedPost", ET_Event, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnFinishPre = CreateGlobalForward( "Timer_OnFinishPre", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnFinishPost = CreateGlobalForward( "Timer_OnFinishPost", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnWRBeaten = CreateGlobalForward( "Timer_OnWRBeaten", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell );
	g_hForward_OnTimerStart = CreateGlobalForward( "Timer_OnTimerStart", ET_Event, Param_Cell );
	
	/* Commands */
	RegConsoleCmd( "sm_nc", Command_Noclip );
	RegConsoleCmd( "sm_reload1", Command_Reload1 );
	RegConsoleCmd( "sm_reload2", Command_Reload2 );
	
	RegConsoleCmd( "sm_style", Command_Styles );
	RegConsoleCmd( "sm_styles", Command_Styles );
	
	RegConsoleCmd( "sm_pb", Command_PB );
	RegConsoleCmd( "sm_bpb", Command_Bonus_PB );
	RegConsoleCmd( "sm_wr", Command_WR );
	RegConsoleCmd( "sm_bwr", Command_Bonus_WR );
	
	/* Hooks */
	HookEvent( "player_jump", HookEvent_PlayerJump );
	
	SQL_DBConnect();
	
	g_fFrameTime = GetTickInterval();
	
	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_aMapTopRecordIds[i][j] = new ArrayList();
			g_aMapTopTimes[i][j] = new ArrayList();
			g_aMapTopNames[i][j] = new ArrayList( ByteCountToCells( MAX_NAME_LENGTH ) );
		}
	}
	
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
	CreateNative( "Timer_GetStyleCount", Native_GetStyleCount );
	CreateNative( "Timer_GetStyleSettings", Native_GetStyleSettings );
	CreateNative( "Timer_GetStyleName", Native_GetStyleName );
	CreateNative( "Timer_GetStylePrefix", Native_GetStylePrefix );
	CreateNative( "Timer_GetClientTimerStatus", Native_GetClientTimerStatus );
	CreateNative( "Timer_GetClientRank", Native_GetClientRank );
	CreateNative( "Timer_GetDatabase", Native_GetDatabase );
	CreateNative( "Timer_IsClientLoaded", Native_IsClientLoaded );
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
	
	StopTimer( client );
	//should we always start with auto ?
	sv_autobunnyhopping.ReplicateToClient( client, "1" );
}

public void OnClientDisconnect( int client )
{
	g_iPlayerId[client] = -1;
	
	g_iClientBlockTickStart[client] = 0;
	g_nClientBlockTicks[client] = 0;
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
	
	ClearPlayerData( client );
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
			if( settings[PreventLeft] && ( buttons & IN_LEFT ) ||
				settings[PreventRight] && ( buttons & IN_RIGHT ) ||
				settings[PreventForward] && ( buttons & IN_FORWARD ) ||
				settings[PreventBack] && ( buttons & IN_BACK ) )
			{
				bButtonError = true;
			}
			else if( settings[HSW] && 
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
	// e.g. in TAS
	
	g_bTimerRunning[client] = false;
	g_bTimerPaused[client] = false;
}

void FinishTimer( int client )
{
	if( !IsPlayerAlive( client ) )
	{
		return;
	}
	
	char sTime[64];
	float time = g_nPlayerFrames[client] * g_fFrameTime;
	Timer_FormatTime( time, sTime, sizeof( sTime ) );
	
	StopTimer( client );
	
	int track = Timer_GetClientZoneTrack( client );
	int style = g_PlayerCurrentStyle[client];
	
	float pb = g_fPlayerPersonalBest[client][track][style]; // TODO: store pb time in seperate cache
	float wr = Timer_GetWRTime( track, style ); // store wr times
	
	Action result = Plugin_Continue;
	Call_StartForward( g_hForward_OnFinishPre );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushCell( time );
	Call_PushCell( pb );
	Call_PushCell( wr );
	Call_Finish( result );
	
	if( result == Plugin_Stop || result == Plugin_Handled )
	{
		return;
	}
	
	char sZoneTrack[64];
	Timer_GetZoneTrackName( track, sZoneTrack, sizeof( sZoneTrack ) );
	PrintToChatAll( "[%s] %N finished on %s timer in %ss (time=%f, wr=%f, pb=%f)", g_StyleSettings[style][StyleName], client, sZoneTrack, sTime, time, wr, pb );
	// TODO: store attempts in seperate cache
	//g_iPlayerRecordId[client][track][style][RD_Attempts]++;
	
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
			PrintToChatAll( "NEW WR!!!!!" );
			
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
			PrintToChatAll( "NEW PB!!!" );
		}
	}
	else
	{
		// they didnt beat their pb but we should update their attempts anyway
		char query[128];
		FormatEx( query, sizeof( query ), "UPDATE `t_records` SET `attempts` = `attempts` + 1 WHERE recordid = '%i'",
										g_iPlayerRecordId[client][track][style] );
										
		Timer_DebugPrint( "FinishTimer: %s", query );
		g_hDatabase.Query( UpdateAttempts_Callback, query, _, DBPrio_Low );
	}
	
	Call_StartForward( g_hForward_OnFinishPost );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushCell( time );
	Call_PushCell( pb );
	Call_PushCell( wr );
	Call_Finish();
	
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

stock int GetClientRank( int client, int track, int style )
{
	// subtract 1 because when times are equal, it counts as next rank
	return GetRankForTime( g_fPlayerPersonalBest[client][track][style], track, style ) - 1; // pb time
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

		g_StyleSettings[g_iTotalStyles][MainReplayBot] = view_as<bool>( kvStyles.GetNum( "main_bot" ) );
		g_StyleSettings[g_iTotalStyles][BonusReplayBot] = view_as<bool>( kvStyles.GetNum( "bonus_bot" ) );
		
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
	Timer_DebugPrint( "SetClientStyle: Set %N sv_autobunnyhopping=%s", g_StyleSettings[style][AutoBhop] ? "1" : "0" );
	
	Timer_TeleportClientToZone( client, Zone_Start, ZoneTrack_Main );
	
	PrintToChat( client, "[Timer] Style now: %s", g_StyleSettings[style][StyleName] );
	
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
	int client = GetClientOfUserId( event.GetInt( "userid" ) );
	if( Timer_IsTimerRunning( client ) )
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
	
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_players` ( playerid INT NOT NULL AUTO_INCREMENT, \
																			steamaccountid INT NOT NULL, \
																			lastname CHAR(64) NOT NULL, \
																			firstconnect INT(16) NOT NULL, \
																			lastconnect INT(16) NOT NULL, \
																			PRIMARY KEY (`playerid`) );" );
	txn.AddQuery( query );
	
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_records` ( recordid INT NOT NULL AUTO_INCREMENT, \
																			mapname CHAR( 128 ) NOT NULL, \
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
	char query[128];
	Format( query, sizeof( query ), "SELECT playerid FROM `t_players` WHERE steamaccountid = '%i';", GetSteamAccountID( client ) );
	
	Timer_DebugPrint( "SQL_LoadPlayerID: %s", query );
	
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
	Format( query, sizeof( query ), "SELECT recordid, time FROM `t_records` WHERE playerid = '%i' AND track = '%i' AND style = '%i' AND mapname = '%s';", g_iPlayerId[client], track, style, g_cMapName );
	
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
	// avoid dividing by 0
	float sync = ( g_nPlayerAirStrafeFrames[client] == 0 ) ? 100.0 : ( g_nPlayerSyncedFrames[client] * 100.0 ) / g_nPlayerAirStrafeFrames[client];
	float strafetime = ( g_nPlayerAirFrames[client] == 0 ) ? 0.0   : ( g_nPlayerAirStrafeFrames[client] * 100.0 ) / g_nPlayerAirFrames[client];

	char query[512];
	Format( query, sizeof( query ), "INSERT INTO `t_records` (mapname, playerid, track, style, timestamp, attempts, time, jumps, strafes, sync, strafetime, ssj) \
													VALUES ('%s', '%i', '%i', '%i', '%i', '%i', '%.5f', '%i', '%i', '%.2f', '%.2f', '%i');",
													g_cMapName,
													g_iPlayerId[client],
													track,
													style,
													GetTime(),
													1,
													time,
													g_nPlayerJumps[client],
													g_nPlayerStrafes[client],
													sync,
													strafetime,
													g_iPlayerSSJ[client]);
	
	Timer_DebugPrint( "SQL_InsertRecord: %s", query );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	g_hDatabase.Query( InsertRecord_Callback, query, pack, DBPrio_High );
}

public void InsertRecord_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertRecord_Callback) - %s", error );
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	g_iPlayerRecordId[client][track][style] = results.InsertId;
}

void SQL_UpdateRecord( int client, int track, int style, float time )
{
	// avoid dividing by 0
	float sync = ( g_nPlayerAirStrafeFrames[client] == 0 ) ? 100.0 : ( g_nPlayerSyncedFrames[client] * 100.0 ) / g_nPlayerAirStrafeFrames[client];
	float strafetime = ( g_nPlayerAirFrames[client] == 0 ) ? 0.0   : ( g_nPlayerAirStrafeFrames[client] * 100.0 ) / g_nPlayerAirFrames[client];

	char query[312];
	Format( query, sizeof( query ), "UPDATE `t_records` SET timestamp = '%i', attempts = attempts+1, time = '%f', jumps = '%i', strafes = '%i', sync = '%f', strafetime = '%f', ssj = '%i' \
													WHERE recordid = '%i';",
													GetTime(),
													time,
													g_nPlayerJumps[client],
													g_nPlayerStrafes[client],
													sync,
													strafetime,
													g_iPlayerSSJ[client],
													g_iPlayerRecordId[client][track][style] );
	
	Timer_DebugPrint( "SQL_UpdateRecord: %s", query );
	
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

void SQL_DeleteRecord( int playerid, int track, int style )
{
	char query[256];
	Format( query, sizeof( query ), "DELETE FROM `t_records` WHERE playerid = '%i' AND track = '%i' AND style = '%i';", playerid, track, style );
	
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
									WHERE mapname = '%s' AND track = '%i' AND style = '%i'\
									ORDER BY r.time ASC;", g_cMapName, track, style );
	
	DataPack pack = new DataPack();
	pack.WriteCell( track );
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
	
	g_hDatabase.Query( GetRecordStats_Callback, query, GetClientUserId( client ), DBPrio_Normal );
}

public void GetRecordStats_Callback( Database db, DBResultSet results, const char[] error, int uid )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (GetRecordStats_Callback) - %s", error );
		return;
	}
	
	int client = GetClientOfUserId( uid );
	if( !client )
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
		
		ShowStats( client, track, style, recordData );
	}
	else
	{
		LogError( "[SQL Error] (GetRecordStats_Callback) - Invalid recordid" );
	}
}

public void UpdateAttempts_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdateAttempts_Callback) - %s", error );
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
		StopTimer( client );
	}
	else
	{
		SetEntityMoveType( client, MOVETYPE_WALK );
	}
	
	return Plugin_Handled;
}

public Action Command_Reload1( int client, int args )
{
	SQL_ReloadCache( 0, 0, true );
}

public Action Command_Reload2( int client, int args )
{
	SQL_ReloadCache( 0, 0, false );
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
		PrintToChat( client, "[Timer] No records found" );
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
		PrintToChat( client, "[Timer] No records found" );
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
	if( !g_aMapTopTimes[track][style].Length )
	{
		PrintToChat( client, "[Timer] No records found" );
		return;
	}
	
	Menu menu = new Menu( WRMenu_Handler );
	
	char trackName[32];
	Timer_GetZoneTrackName( track, trackName, sizeof(trackName) );
	
	char buffer[256];
	Format( buffer, sizeof( buffer ), "%s %s %s Leaderboard", trackName, g_StyleSettings[style][StyleName], g_cMapName );
	menu.SetTitle( buffer );
	
	char sTime[32], info[8];
	
	int max = ( MAX_WR_CACHE > g_aMapTopTimes[track][style].Length ) ? g_aMapTopTimes[track][style].Length : MAX_WR_CACHE;
	Timer_DebugPrint( "ShowLeaderboard: max=%i", max );
	for( int i = 0; i < max; i++ )
	{
		char lastname[MAX_NAME_LENGTH];
		g_aMapTopNames[track][style].GetString( i, lastname, sizeof(lastname) );
	
		Timer_FormatTime( g_aMapTopTimes[track][style].Get( i ), sTime, sizeof(sTime) );
		
		Format( buffer, sizeof(buffer), "[#%i] - %s (%s)", i + 1, lastname, sTime );
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

void ShowStats( int client, int track, int style, const any recordData[RecordData] )
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
		
		char sSplitString[3][16];
		ExplodeString( sInfo, ",", sSplitString, sizeof( sSplitString ), sizeof( sSplitString[] ) );
		
		int playerid = StringToInt( sSplitString[0] );
		int track = StringToInt( sSplitString[1] );
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
	
	return view_as<int>( ( g_nPlayerAirStrafeFrames[client] == 0 || g_nPlayerSyncedFrames[client] == 0 ) ? 100.0 : ( g_nPlayerSyncedFrames[client] * 100.0 ) / g_nPlayerAirStrafeFrames[client] );
}

public int Native_GetClientCurrentStrafeTime( Handle handler, int numparams )
{
	int client = GetNativeCell( 1 );
	if( !g_bTimerRunning[client] )
	{
		return 0;
	}
	
	return view_as<int>( ( g_nPlayerAirFrames[client] == 0 || g_nPlayerAirStrafeFrames[client] == 0 ) ? 0.0 : ( g_nPlayerAirStrafeFrames[client] * 100.0 ) / g_nPlayerAirFrames[client] );
}

public int Native_GetWRTime( Handle handler, int numparams )
{
	int track = GetNativeCell( 1 );
	int style = GetNativeCell( 2 );
	
	if( g_aMapTopTimes[track][style].Length )
	{		
		return g_aMapTopTimes[track][style].Get( 0 );
	}
	
	return 0;
}

public int Native_GetWRName( Handle handler, int numparams )
{
	int track = GetNativeCell( 1 );
	int style = GetNativeCell( 2 );
	
	if( g_aMapTopNames[track][style].Length )
	{
		char lastname[MAX_NAME_LENGTH];
		g_aMapTopNames[track][style].GetString( 0, lastname, sizeof(lastname) );
	
		SetNativeString( 3, lastname, GetNativeCell( 4 ) );
	}
}

public int Native_GetClientPBTime( Handle handler, int numparams )
{
	return view_as<int>( g_fPlayerPersonalBest[GetNativeCell( 1 )][GetNativeCell( 2 )][GetNativeCell( 3 )] );
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

public int Native_GetClientStyle( Handle handler, int numParams )
{
	return g_PlayerCurrentStyle[GetNativeCell( 1 )];
}

public int Native_IsClientLoaded( Handle handler, int numParams )
{
	return g_iPlayerId[GetNativeCell( 1 )] > -1;
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
