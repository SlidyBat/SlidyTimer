#include <sourcemod>
#include <sdkhooks>
#include <smlib>
#include <cstrike>
#include <slidy-timer>

char		g_cCurrentMap[PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = "Slidy's Timer - Misc",
	author = "SlidyBat",
	description = "Miscellaneous components of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public void OnPluginStart()
{
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

public Action HookEvent_GameEnd( Event E_Event, char[] C_Name, bool B_DontBroadcast )
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
		
		if( IsValidClient( client ) && !IsFakeClient( client ) )
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
	if( IsValidClient( client ) )
	{
		SetEntProp( client, Prop_Send, "m_iHideHUD", GetEntProp( client, Prop_Send, "m_iHideHUD" ) | (1 << 12) );
	}
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
			if( IsValidClient( target, true ) )
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
}

stock void SetClientObserverTarget( int client, int target )
{
	SetEntPropEnt( client, Prop_Send, "m_hObserverTarget", target );
	SetEntProp( client, Prop_Send, "m_iObserverMode", 4 );
}

stock void SetConVars()
{
	ConVar convar;

	convar = FindConVar( "bot_quota_mode" );
	convar.SetString( "normal" );
	
	convar = FindConVar( "bot_quota" );
	convar.IntValue = 0;

	convar = FindConVar( "bot_join_after_player" );
	convar.BoolValue = false;

	convar = FindConVar( "mp_autoteambalance" );
	convar.BoolValue = false;

	convar = FindConVar( "mp_limitteams" );
	convar.IntValue = 0;

	convar = FindConVar( "bot_zombie" );
	convar.BoolValue = true;

	convar = FindConVar( "sv_clamp_unsafe_velocities" );
	convar.BoolValue = false;

	convar = FindConVar( "mp_maxrounds" );
	convar.IntValue = 0;

	convar = FindConVar( "mp_timelimit" );
	convar.IntValue = 9999;

	convar = FindConVar( "mp_roundtime" );
	convar.IntValue = 60;

	convar = FindConVar( "mp_freezetime" );
	convar.IntValue = 0;

	convar = FindConVar( "mp_ignore_round_win_conditions" );
	convar.BoolValue = false;

	convar = FindConVar( "mp_match_end_changelevel" );
	convar.BoolValue = true;

	convar = FindConVar( "sv_accelerate_use_weapon_speed" );
	convar.BoolValue = false;

	convar = FindConVar( "mp_free_armor" );
	convar.BoolValue = true;

	convar = FindConVar( "sv_full_alltalk" );
	convar.IntValue = 1;

	convar = FindConVar( "sv_alltalk" );
	convar.BoolValue = true;

	convar = FindConVar( "sv_talk_enemy_dead" );
	convar.BoolValue = true;

	convar = FindConVar( "sv_friction" );
	convar.FloatValue = 4.0;

	convar = FindConVar( "sv_accelerate" );
	convar.FloatValue - 5.0;
	
	convar = FindConVar( "sv_airaccelerate" );
	convar.FloatValue = 1000.0;
}