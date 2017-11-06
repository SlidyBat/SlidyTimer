#include <sourcemod>
#include <sdkhooks>
#include <slidy-timer>
#include <cstrike>

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
}

public void OnMapStart()
{
	SetConVars();
}

public void OnClientPostAdminCheck( int client )
{
	SDKHook( client, SDKHook_OnTakeDamage, Hook_OnTakeDamageCallback );
}

public void OnClientDisconnect( int client )
{
	SDKUnhook( client, SDKHook_OnTakeDamage, Hook_OnTakeDamageCallback );
}

public Action Hook_OnTakeDamageCallback( int victim, int& attacker, int& inflictor, float& damage, int& damagetype )
{
	damage = 0.0;
	return Plugin_Handled;
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