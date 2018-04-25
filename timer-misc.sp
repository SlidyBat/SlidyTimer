#include <sourcemod>
#include <sdkhooks>
#include <smlib>
#include <cstrike>
#include <slidy-timer>

ConVar	g_cvCreateSpawnPoints;
char		g_cCurrentMap[PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = "Slidy's Timer - Misc",
	author = "SlidyBat",
	description = "Miscellaneous components of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	RegPluginLibrary( "timer-misc" );
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvCreateSpawnPoints = CreateConVar( "sm_create_spawnpoints", "10", "Number of spawn points to create", _, true, 0.0, true, 2048.0 );

	RegConsoleCmd( "sm_spec", Command_Spec );
	
	HookEvent( "game_end", HookEvent_GameEnd, EventHookMode_Pre );
	
	HookEvent( "player_spawn", HookEvent_PlayerSpawn, EventHookMode_Post );
	HookEvent( "player_connect", HookEvent_PlayerConnect, EventHookMode_Pre );
	HookEvent( "player_disconnect", HookEvent_PlayerDisconnect, EventHookMode_Pre );
	HookEvent( "player_team", HookEvent_PlayerTeam, EventHookMode_Pre );
	
	HookUserMessage( GetUserMessageId( "TextMsg" ), UserMsg_TextMsg, true );
	HookUserMessage( GetUserMessageId( "SayText2" ), UserMsg_SayText2, true );
	AddCommandListener( HookEvent_Chat, "say" );
	AddCommandListener( HookEvent_Chat, "say_team" );
}

public void OnMapStart()
{
	GetCurrentMap( g_cCurrentMap, sizeof( g_cCurrentMap ) );

	char path[PLATFORM_MAX_PATH];
	FormatEx( path, sizeof( path ), "maps/%s.nav", g_cCurrentMap );

	/* Automatically generate nav file if one doesn't exist (from shavits) */
	if( !FileExists( path ) )
	{
		File_Copy( "maps/replay.nav", path );
		Format( path, sizeof( path ), "%s.nav file generated", g_cCurrentMap );
		ForceChangeLevel( g_cCurrentMap, path );	
	}
	
	if ( g_cvCreateSpawnPoints.IntValue > 0 )
	{
		int entity = -1;
		float origin[3];

		if( (entity = FindEntityByClassname( entity, "info_player_terrorist" )) != INVALID_ENT_REFERENCE ||
			(entity = FindEntityByClassname( entity, "info_player_counterterrorist" )) != INVALID_ENT_REFERENCE ||
			(entity = FindEntityByClassname( entity, "info_player_start" )) != INVALID_ENT_REFERENCE )
		{
			GetEntPropVector( entity, Prop_Send, "m_vecOrigin", origin );
		}

		if(entity != -1)
		{
			for( int i = 1; i <= g_cvCreateSpawnPoints.IntValue; i++ )
			{
				for(int team = 1; team <= 2; team++)
				{
					int spawnpoint = CreateEntityByName( (team == 1) ? "info_player_terrorist" : "info_player_counterterrorist" );

					if( DispatchSpawn( spawnpoint ) )
					{
						TeleportEntity( spawnpoint, origin, view_as<float>( { 0.0, 0.0, 0.0 } ), NULL_VECTOR );
					}
				}
			}
		}
	}

	SetConVars();
}

public void OnClientPostAdminCheck( int client )
{
	SDKHook( client, SDKHook_OnTakeDamage, Hook_OnTakeDamageCallback );
	SDKHook( client, SDKHook_WeaponDropPost, Hook_OnWeaponDropPostCallback );
}

public void OnClientDisconnect( int client )
{
	SDKUnhook( client, SDKHook_OnTakeDamage, Hook_OnTakeDamageCallback );
}

public Action CS_OnTerminateRound( float& delay, CSRoundEndReason& reason )
{
	int timeleft;
	GetMapTimeLeft( timeleft );
	
	if( timeleft <= 0 )
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

public Action HookEvent_GameEnd( Event event, char[] name, bool dontBroadcast )
{
	int timeleft;
	GetMapTimeLeft( timeleft );
	
	if( timeleft <= 0 )
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

public Action Hook_OnTakeDamageCallback( int victim, int& attacker, int& inflictor, float& damage, int& damagetype )
{
	return Plugin_Handled;
}

public void Hook_OnWeaponDropPostCallback( int client, int weapon )
{
	if( IsValidEntity( weapon ) )
	{
		CreateTimer( 0.1, Timer_ClearEntity, EntIndexToEntRef( weapon ) );
	}
}

public Action HookEvent_PlayerSpawn( Event event, const char[] name, bool dontBroadcast )
{
	int client = GetClientOfUserId( event.GetInt( "userid" ) );

	if( IsValidEntity( client ) )
	{
		SetEntProp( client, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER );
		
		if( !IsFakeClient( client ) )
		{
			RequestFrame( HideRadar, client );

			SendConVarValue( client, FindConVar( "mp_playercashawards" ), "0" );
			SendConVarValue( client, FindConVar( "mp_teamcashawards" ), "0" );
		}
	}
}

public Action HookEvent_PlayerConnect( Event event, const char[] name, bool dontBroadcast )
{
	dontBroadcast = true;
	event.BroadcastDisabled = true;

	return Plugin_Handled;
}

public Action HookEvent_PlayerDisconnect( Event event, const char[] name, bool dontBroadcast )
{
	dontBroadcast = true;
	event.BroadcastDisabled = true;
	
	int client = GetClientOfUserId( event.GetInt( "userid" ) );

	if( client > 0 && IsFakeClient( client ) )
		return Plugin_Continue;
		
	char buffer[256];
	Format( buffer, sizeof( buffer ), "[\x07Disconnect\x01] \x03%N \x01has left the server", client );
	PrintToChatAll( buffer ); // TODO: maybe implement a timer print to chat that creates a SayText2 usermsg, so message appears in console

	return Plugin_Handled;
}

public Action HookEvent_PlayerTeam( Event event, const char[] name, bool dontBroadcast )
{
	dontBroadcast = true;
	event.BroadcastDisabled = true;

	return Plugin_Changed
}

public Action UserMsg_TextMsg( UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init )
{
	char buffer[512];
	msg.ReadString( "params", buffer, sizeof( buffer ), 0 );

	if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_YouGotCash" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_Spectators" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_EnemyGotCash" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_TeammateGotCash" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#game_respawn_as" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#game_spawn_as" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_Killed_Enemy" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Team_Cash_Award_Win_Time" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Point_Award_Assist_Enemy_Plural" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Point_Award_Assist_Enemy" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Point_Award_Killed_Enemy_Plural" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Point_Award_Killed_Enemy" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_Respawn" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_Get_Killed" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_Killed_Enemy" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_Killed_Enemy_Generic" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_Kill_Teammate" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Team_Cash_Award_Loser_Bonus" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Team_Cash_Award_Loser_Zero" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Team_Cash_Award_no_income" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Team_Cash_Award_Generic" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Team_Cash_Award_Custom" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_YouGotCash" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_TeammateGotCash" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_EnemyGotCash" ) )
		return Plugin_Handled;
	else if( StrEqual( buffer, "#Player_Cash_Award_ExplainSuicide_Spectators" ) )
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action UserMsg_SayText2( UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init )
{
	char buffer[512];
	msg.ReadString( "msg_name", buffer, sizeof( buffer ) );

	if( StrEqual( buffer, "#Cstrike_Name_Change" ) )
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action HookEvent_Chat( int client, char[] command, int args )
{
	char buffer[256];

	if( IsChatTrigger() )
	{
		return Plugin_Handled;
	}

	GetCmdArgString( buffer, sizeof( buffer ) );
	StripQuotes( buffer );

	if( ( buffer[0] == '!' ) || ( buffer[0] == '/' ) )
	{
		int len = strlen( buffer );
		for( int i = 0; i < len; i++)
		{
			buffer[i] = CharToLower( buffer[i + 1] );
		}

		FakeClientCommand( client, "sm_%s", buffer );
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Timer_ClearEntity( Handle timer, int entref )
{
	int entity = EntRefToEntIndex( entref );
	
	if( IsValidEntity( entity ) && IsValidEdict( entity ) )
	{
		if( GetEntProp( entity, Prop_Send, "m_hOwnerEntity" ) < 1 )
		{
			RemoveEdict( entity );
		}
	}
}

public void HideRadar( int client )
{
	SetEntProp( client, Prop_Send, "m_iHideHUD", GetEntProp( client, Prop_Send, "m_iHideHUD" ) | (1 << 12) );
}

public Action Command_Spec( int client, int args )
{
	Timer_StopTimer( client );
	ChangeClientTeam( client, CS_TEAM_SPECTATOR );

	if( args )
	{
		char arg[MAX_NAME_LENGTH];
		GetCmdArgString( arg, sizeof( arg ) );
		
		int target = FindTarget( client, arg, true, false );

		if( target > -1 )
		{
			if( IsClientInGame( target ) && IsPlayerAlive( target ) )
			{
				SetClientObserverTarget( client, target )
			}
			else
			{
				ReplyToCommand( client, "[Timer] %N is not alive", target );
			}
		}
		else
		{
			ReplyToCommand( client, "[Timer] No matching players" );	
		}
	}
	
	return Plugin_Handled;
}

stock void SetClientObserverTarget( int client, int target )
{
	SetEntPropEnt( client, Prop_Send, "m_hObserverTarget", target );
	SetEntProp( client, Prop_Send, "m_iObserverMode", 4 );
}

stock void SetConVars()
{
	FindConVar( "bot_quota_mode" ).SetString( "normal" );
	FindConVar( "bot_join_after_player" ).BoolValue = false;
	FindConVar( "mp_autoteambalance" ).BoolValue = false;
	FindConVar( "mp_limitteams" ).IntValue = 0;
	FindConVar( "bot_zombie" ).BoolValue = true;
	FindConVar( "sv_clamp_unsafe_velocities" ).BoolValue = false;
	FindConVar( "mp_maxrounds" ).IntValue = 0;
	FindConVar( "mp_timelimit" ).IntValue = 9999;
	FindConVar( "mp_roundtime" ).IntValue = 60;
	FindConVar( "mp_freezetime" ).IntValue = 0;
	FindConVar( "mp_ignore_round_win_conditions" ).BoolValue = false;
	FindConVar( "mp_match_end_changelevel" ).BoolValue = true;
	FindConVar( "sv_accelerate_use_weapon_speed" ).BoolValue = false;
	FindConVar( "mp_free_armor" ).BoolValue = true;
	FindConVar( "sv_full_alltalk" ).IntValue = 1;
	FindConVar( "sv_alltalk" ).BoolValue = true;
	FindConVar( "sv_talk_enemy_dead" ).BoolValue = true;
	FindConVar( "sv_friction" ).FloatValue = 4.0;
	FindConVar( "sv_accelerate" ).FloatValue = 5.0;
	FindConVar( "sv_airaccelerate" ).FloatValue = 1000.0;
}