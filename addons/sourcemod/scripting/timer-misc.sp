#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <slidy-timer>
#include <menu_targeting>

/*
 * Collision groups
 * Taken from hl2sdk-ob-valve/public/const.h
 */
enum Collision_Group_t
{
	COLLISION_GROUP_NONE  = 0,
	COLLISION_GROUP_DEBRIS,				// Collides with nothing but world and static stuff
	COLLISION_GROUP_DEBRIS_TRIGGER,		// Same as debris, but hits triggers
	COLLISION_GROUP_INTERACTIVE_DEB,	// Collides with everything except other interactive debris or debris
	COLLISION_GROUP_INTERACTIVE,		// Collides with everything except interactive debris or debris
	COLLISION_GROUP_PLAYER,
	COLLISION_GROUP_BREAKABLE_GLASS,
	COLLISION_GROUP_VEHICLE,
	COLLISION_GROUP_PLAYER_MOVEMENT,	// For HL2, same as Collision_Group_Player, for
										// TF2, this filters out other players and CBaseObjects
	COLLISION_GROUP_NPC,				// Generic NPC group
	COLLISION_GROUP_IN_VEHICLE,			// for any entity inside a vehicle
	COLLISION_GROUP_WEAPON,				// for any weapons that need collision detection
	COLLISION_GROUP_VEHICLE_CLIP,		// vehicle clip brush to restrict vehicle movement
	COLLISION_GROUP_PROJECTILE,			// Projectiles!
	COLLISION_GROUP_DOOR_BLOCKER,		// Blocks entities not permitted to get near moving doors
	COLLISION_GROUP_PASSABLE_DOOR,		// Doors that the player shouldn't collide with
	COLLISION_GROUP_DISSOLVING,			// Things that are dissolving are in this group
	COLLISION_GROUP_PUSHAWAY,			// Nonsolid on client and server, pushaway in player code

	COLLISION_GROUP_NPC_ACTOR,			// Used so NPCs in scripts ignore the player.
	COLLISION_GROUP_NPC_SCRIPTED		// USed for NPCs in scripts that should not collide with each other
};

ConVar	g_cvCreateSpawnPoints;
char		g_cCurrentMap[PLATFORM_MAX_PATH];

bool g_bHidePlayers[MAXPLAYERS + 1];

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
	RegConsoleCmd( "sm_tpto", Command_TeleportTo );
	RegConsoleCmd( "sm_hide", Command_Hide );
	
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
	SDKHook( client, SDKHook_SetTransmit, Hook_OnTransmit );
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

public Action Hook_OnTransmit( int entity, int client )
{
	if( entity != client && g_bHidePlayers[client] )
	{
		if( IsClientObserver( client ) )
		{
			int target = GetClientObserverTarget( client );
			if( target != -1 && target != entity )
			{
				return Plugin_Handled;
			}
		}
		else
		{
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
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
	Format( buffer, sizeof( buffer ), "{name}%N {primary}has left the server", client );
	Timer_PrintToChatAll( buffer );

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

		if( !SelectTarget( client, arg, SetClientObserverTarget ) )
		{
			Timer_ReplyToCommand( client, "{primary}No matching players" );	
		}
	}
	
	return Plugin_Handled;
}

public void SetClientObserverTarget( int client, int target )
{
	if( IsClientInGame( target ) && IsPlayerAlive( target ) )
	{
		SetEntPropEnt( client, Prop_Send, "m_hObserverTarget", target );
		SetEntProp( client, Prop_Send, "m_iObserverMode", 4 );
	}
	else
	{
		Timer_ReplyToCommand( client, "{name}%N {primary}is not alive", target );
	}
}

public Action Command_Hide( int client, int args )
{
	g_bHidePlayers[client] = !g_bHidePlayers[client];
	Timer_ReplyToCommand( client, "{primary}Players now: {secondary}%s", g_bHidePlayers[client] ? "Hidden" : "Visible" );
	
	return Plugin_Handled;
}

public Action Command_TeleportTo( int client, int args )
{
	Timer_StopTimer( client );

	if( args )
	{
		char arg[MAX_NAME_LENGTH];
		GetCmdArgString( arg, sizeof( arg ) );

		if( !SelectTarget( client, arg, TeleportTo ) )
		{
			Timer_ReplyToCommand( client, "{primary}No matching players" );	
		}
	}
	
	return Plugin_Handled;
}

public void TeleportTo( int client, int target )
{
	if( IsClientInGame( target ) && IsPlayerAlive( target ) )
	{
		float pos[3];
		GetClientAbsOrigin( target, pos );
		
		Timer_BlockTimer( client, 1 );
		TeleportEntity( client, pos, NULL_VECTOR, NULL_VECTOR );
	}
	else
	{
		Timer_ReplyToCommand( client, "{name}%N {primary}is not alive", target );
	}
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
	FindConVar( "mp_do_warmup_period" ).BoolValue = false;
	FindConVar( "mp_warmuptime" ).IntValue = 0;
	FindConVar( "sv_accelerate_use_weapon_speed" ).BoolValue = false;
	FindConVar( "mp_free_armor" ).BoolValue = true;
	FindConVar( "sv_full_alltalk" ).IntValue = 1;
	FindConVar( "sv_alltalk" ).BoolValue = true;
	FindConVar( "sv_talk_enemy_dead" ).BoolValue = true;
	FindConVar( "sv_friction" ).FloatValue = 4.0;
	FindConVar( "sv_accelerate" ).FloatValue = 5.0;
	FindConVar( "sv_airaccelerate" ).FloatValue = 1000.0;
}

stock bool File_Copy( const char[] source, const char[] destination )
{
	File file_source = OpenFile(source, "rb");

	if( file_source == null )
	{
		return false;
	}

	File file_destination = OpenFile( destination, "wb" );

	if( file_destination == null )
	{
		delete file_source;
		return false;
	}

	int buffer[32];
	int cache;

	while( !IsEndOfFile( file_source ) )
	{
		cache = ReadFile( file_source, buffer, sizeof(buffer), 1 );
		WriteFile( file_destination, buffer, cache, 1 );
	}

	delete file_source;
	delete file_destination;

	return true;
}