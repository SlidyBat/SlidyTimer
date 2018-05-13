#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <slidy-timer>

#define AUTO_SELECT_CP -1

#define DEFAULT_CP_SETTINGS ( (1 << 0) | (1 << 1) | (1 << 2) )

typedef CPSelectCallback = function void ( int client, int cpindex );

enum Checkpoint
{
	Float:CP_Pos[3],
	Float:CP_Ang[3],
	Float:CP_Vel[3],
	Float:CP_Basevel[3],
	Float:CP_Gravity,
	Float:CP_LaggedMovement,
	String:CP_Targetname[32],
	MoveType:CP_MoveType,
	CP_Flags,
	bool:CP_Ducked,
	bool:CP_Ducking,
	Float:CP_DuckAmount,
	Float:CP_DuckSpeed,
	CP_TimerData[TIMER_DATA_SIZE],
	ArrayList:CP_ReplayFrames
}

ArrayList				g_aCheckpoints[MAXPLAYERS + 1] = { null, ... };
bool						g_bUsedCP[MAXPLAYERS + 1];
int					g_iSelectedCheckpoint[MAXPLAYERS + 1];
CPSelectCallback	g_CPSelectCallback[MAXPLAYERS + 1];

int					g_iCPSettings[MAXPLAYERS + 1] = { DEFAULT_CP_SETTINGS, ... };
bool					g_bCPMenuOpen[MAXPLAYERS + 1];

enum (<<= 1)
{
	CPSettings_UsePos = 1,
	CPSettings_UseAng,
	CPSettings_UseVel,
}

char g_cCPSettingNames[][] = 
{
	"Use Position",
	"Use Angles",
	"Use Velocity"
};

public Plugin myinfo = 
{
	name = "Slidy's Timer - CP component",
	author = "SlidyBat",
	description = "Checkpoints component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	RegPluginLibrary( "timer-cp" );
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	for( int i = 1; i <= MaxClients; i++ )
	{
		g_aCheckpoints[i] = new ArrayList( view_as<int>(Checkpoint) );
	}
	
	RegConsoleCmd( "sm_cp", Command_OpenCheckpointMenu, "Opens checkpoint menu" );
	RegConsoleCmd( "sm_save", Command_Save, "Save checkpoint" );
	RegConsoleCmd( "sm_tele", Command_Tele, "Teleport to checkpoint" );
	RegConsoleCmd( "sm_delete", Command_Delete, "Delete a checkpoint" );
}

public void OnClientPutInServer( int client )
{
	int length = g_aCheckpoints[client].Length;
	for( int i = 0; i < length; i++ )
	{
		delete view_as<ArrayList>(g_aCheckpoints[client].Get( i, view_as<int>(CP_ReplayFrames) ));
	}
	g_aCheckpoints[client].Clear();
	g_iCPSettings[client] = DEFAULT_CP_SETTINGS;
	g_bUsedCP[client] = false;
	g_bCPMenuOpen[client] = false;
}

public Action Timer_OnTimerStart( int client )
{
	g_bUsedCP[client] = false;
}

public Action Timer_OnFinishPre( int client, int track, int style, float time, float pbtime, float wrtime )
{
	if( g_bUsedCP[client] )
	{
		if( Timer_StyleHasSetting( style, "segment" ) ) // only save time/replay if its a segment style
		{
			return Plugin_Continue;
		}
		
		Timer_PrintToChat( client, "{primary}Finished in {secondary}%.2fs {primary}(Practice Mode)" );
	
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void Timer_OnStyleChangedPost( int client, int oldstyle, int newstyle )
{
	if( Timer_StyleHasSetting( newstyle, "segment" ) )
	{
		OpenCPMenu( client );
	}
}

void SaveCheckpoint( int client, int index = AUTO_SELECT_CP )
{
	int target = GetClientObserverTarget( client );
	if( !( 0 < target <= MaxClients ) )
	{
		return;
	}

	if( index == AUTO_SELECT_CP )
	{
		index = g_aCheckpoints[client].Length;
		g_aCheckpoints[client].Push( 0 );
	}
	
	g_iSelectedCheckpoint[client] = index;
	
	any cp[Checkpoint];
	float temp[3];
	
	GetClientAbsOrigin( target, temp );
	CopyVector( temp, cp[CP_Pos] );
	GetClientEyeAngles( target, temp );
	CopyVector( temp, cp[CP_Ang] );
	GetEntityAbsVelocity( target, temp );
	CopyVector( temp, cp[CP_Vel] );
	GetEntityBaseVelocity( target, temp );
	CopyVector( temp, cp[CP_Basevel] );
	cp[CP_Gravity] = GetEntityGravity( target );
	cp[CP_LaggedMovement] = GetEntPropFloat( target, Prop_Data, "m_flLaggedMovementValue" );
	GetEntityTargetname( target, cp[CP_Targetname], 32 );
	cp[CP_MoveType] = GetEntityMoveType( target );
	cp[CP_Flags] = GetEntityFlags( target );
	cp[CP_Ducked] = view_as<bool>(GetEntProp( target, Prop_Send, "m_bDucked" ));
	cp[CP_Ducking] = view_as<bool>(GetEntProp( target, Prop_Send, "m_bDucking" ));
	cp[CP_DuckAmount] = GetEntPropFloat( target, Prop_Send, "m_flDuckAmount" );
	cp[CP_DuckSpeed] = GetEntPropFloat( target, Prop_Send, "m_flDuckSpeed" );
	Timer_GetClientTimerData( target, cp[CP_TimerData] );
	cp[CP_ReplayFrames] = Timer_GetClientReplayFrames( target );
	
	g_aCheckpoints[client].SetArray( index, cp[0] );
	
	if( g_bCPMenuOpen[client] )
	{
		OpenCPMenu( client );
	}
}

public void LoadCheckpoint( int client, int index )
{
	if( index == AUTO_SELECT_CP )
	{
		index = g_iSelectedCheckpoint[client];
	}
	
	Timer_StopTimer( client );
	Timer_BlockTimer( client, 1 );
	
	g_bUsedCP[client] = true;
	
	any cp[Checkpoint];
	
	g_aCheckpoints[client].GetArray( index, cp[0] );
	
	float pos[3], ang[3], vel[3], basevel[3];
	CopyVector( cp[CP_Pos], pos );
	CopyVector( cp[CP_Ang], ang );
	CopyVector( cp[CP_Vel], vel );
	CopyVector( cp[CP_Basevel], basevel );
	
	TeleportEntity( client,
					(g_iCPSettings[client] & CPSettings_UsePos) ? pos : NULL_VECTOR,
					(g_iCPSettings[client] & CPSettings_UseAng) ? ang : NULL_VECTOR,
					(g_iCPSettings[client] & CPSettings_UseVel) ? vel : NULL_VECTOR );
	
	SetEntityBaseVelocity( client, basevel );
	SetEntityGravity( client, cp[CP_Gravity] );
	SetEntPropFloat( client, Prop_Data, "m_flLaggedMovementValue", cp[CP_LaggedMovement] );
	SetEntityTargetname( client, cp[CP_Targetname] );
	SetEntityMoveType( client, cp[CP_MoveType] );
	SetEntityFlags( client, cp[CP_Flags] );
	SetEntProp( client, Prop_Send, "m_bDucked", cp[CP_Ducked] );
	SetEntProp( client, Prop_Send, "m_bDucking", cp[CP_Ducking] );
	SetEntPropFloat( client, Prop_Send, "m_flDuckAmount", cp[CP_DuckAmount] );
	SetEntPropFloat( client, Prop_Send, "m_flDuckSpeed", cp[CP_DuckSpeed] );
	Timer_SetClientTimerData( client, cp[CP_TimerData] );
	Timer_SetClientReplayFrames( client, cp[CP_ReplayFrames] );
	
	if( g_bCPMenuOpen[client] )
	{
		OpenCPMenu( client );
	}
}

public void DeleteCheckpoint( int client, int index )
{
	if( index != 0 && index <= g_iSelectedCheckpoint[client] )
	{
		g_iSelectedCheckpoint[client]--;
	}

	delete view_as<ArrayList>(g_aCheckpoints[client].Get( index, view_as<int>(CP_ReplayFrames) ));
	g_aCheckpoints[client].Erase( index );
}

void NextCheckpoint( int client )
{
	if( g_iSelectedCheckpoint[client] == g_aCheckpoints[client].Length - 1 )
	{
		Timer_PrintToChat( client, "{primary}No further checkpoints" );
	}
	else
	{
		g_iSelectedCheckpoint[client]++;
		LoadCheckpoint( client, AUTO_SELECT_CP );
		
		if( g_bCPMenuOpen[client] )
		{
			OpenCPMenu( client );
		}
	}
}

void PreviousCheckpoint( int client )
{
	if( g_iSelectedCheckpoint[client] == 0 )
	{
		Timer_PrintToChat( client, "{primary}No previous checkpoints" );
	}
	else
	{
		g_iSelectedCheckpoint[client]--;
		LoadCheckpoint( client, AUTO_SELECT_CP );
		
		if( g_bCPMenuOpen[client] )
		{
			OpenCPMenu( client );
		}
	}
}

public Action Command_OpenCheckpointMenu( int client, int args )
{
	OpenCPMenu( client );
	
	return Plugin_Handled;
}

void OpenCPMenu( int client )
{
	Menu menu = new Menu( CPMenu_Handler );

	menu.SetTitle( "Timer - Checkpoints Menu \n \n" );

	menu.AddItem( "save", "Save\n \n" );

	char cpcounter[32];
	Format( cpcounter, sizeof(cpcounter), "%i/%i", g_iSelectedCheckpoint[client] + 1, g_aCheckpoints[client].Length );
	
	char buffer[256];
	Format( buffer, sizeof(buffer), "Teleport\n" );
	Format( buffer, sizeof(buffer), "%s    >CP: %s\n \n", buffer, ( g_aCheckpoints[client].Length ) ? cpcounter : "N/A" );
	menu.AddItem( "tele", buffer, g_aCheckpoints[client].Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );
	
	menu.AddItem( "previous", "Previous\n", ( g_aCheckpoints[client].Length && g_iSelectedCheckpoint[client] != 0 ) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );
	menu.AddItem( "next", "Next\n \n", ( g_aCheckpoints[client].Length && g_iSelectedCheckpoint[client] != g_aCheckpoints[client].Length - 1 ) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );

	menu.AddItem( "select", "Select checkpoints", g_aCheckpoints[client].Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );
	menu.AddItem( "delete", "Delete checkpoints", g_aCheckpoints[client].Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );

	menu.AddItem( "settings", "Settings" );

	menu.Display( client, MENU_TIME_FOREVER );
	
	g_bCPMenuOpen[client] = true;
}

public int CPMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char sInfo[16];
		menu.GetItem( param2, sInfo, sizeof(sInfo) );
		
		if( StrEqual( sInfo, "save" ) )
		{
			SaveCheckpoint( param1 );
			OpenCPMenu( param1 );
		}
		else if( StrEqual( sInfo, "tele" ) )
		{
			if( !g_aCheckpoints[param1].Length )
			{
				Timer_PrintToChat( param1, "{primary}No checkpoints found" );
			}
			else
			{
				LoadCheckpoint( param1, AUTO_SELECT_CP );
			}
			OpenCPMenu( param1 );
		}
		else if( StrEqual( sInfo, "previous" ) )
		{
			PreviousCheckpoint( param1 );
			OpenCPMenu( param1 );
		}
		else if( StrEqual( sInfo, "next" ) )
		{
			NextCheckpoint( param1 );
			OpenCPMenu( param1 );
		}
		else if( StrEqual( sInfo, "select" ) )
		{
			if( g_aCheckpoints[param1].Length > 0 )
			{
				OpenSelectCPMenu( param1, LoadCheckpoint );
			}
			else
			{
				Timer_PrintToChat( param1, "{primary}No checkpoints found" );
			}
		}
		else if( StrEqual( sInfo, "delete" ) )
		{
			if( g_aCheckpoints[param1].Length > 0 )
			{
				OpenSelectCPMenu( param1, DeleteCheckpoint );
			}
			else
			{
				Timer_PrintToChat( param1, "{primary}No checkpoints found" );
			}
		}
		else if( StrEqual( sInfo, "settings" ) )
		{
			OpenCPSettingsMenu( param1 );
		}
	}
	else if( action == MenuAction_Cancel )
	{
		g_bCPMenuOpen[param1] = false;
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void OpenSelectCPMenu( int client, CPSelectCallback cb )
{
	g_CPSelectCallback[client] = cb;

	Menu menu = new Menu( CPSelect_Handler );
	
	menu.SetTitle( "Timer - Checkpoints Menu - Select CP\n \n" );

	char buffer[64];
	int totalcps = g_aCheckpoints[client].Length;
	for( int i = 1; i <= totalcps; i++ )
	{
		Format( buffer, sizeof(buffer), "Checkpoint %i", i );
		menu.AddItem( "cp", buffer );
	}

	menu.ExitBackButton = true;

	menu.Display( client, MENU_TIME_FOREVER );
}

public int CPSelect_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Cancel && param2 == MenuCancel_ExitBack )
	{
		OpenCPMenu( param1 );
	}
	else if( action == MenuAction_Select )
	{
		Call_StartFunction( GetMyHandle(), g_CPSelectCallback[param1] );
		Call_PushCell( param1 );
		Call_PushCell( param2 );
		Call_Finish();
		
		OpenSelectCPMenu( param1, g_CPSelectCallback[param1] );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void OpenCPSettingsMenu( int client )
{
	Menu menu = new Menu( CPSettings_Handler );
	
	menu.SetTitle( "Timer - Checkpoints Menu - Settings\n \n" );
	
	for( int i = 0; i < sizeof(g_cCPSettingNames); i++ )
	{
		char buffer[64];
		Format( buffer, sizeof(buffer), "%s: %s", g_cCPSettingNames[i], ( g_iCPSettings[client] & (1 << i) ) ? "Enabled" : "Disabled" );
		menu.AddItem( "cpsetting", buffer );
	}
	
	menu.ExitBackButton = true;
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int CPSettings_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Cancel && param2 == MenuCancel_ExitBack )
	{
		OpenCPMenu( param1 );
	}
	else if( action == MenuAction_Select )
	{
		g_iCPSettings[param1] ^= (1 << param2);
		OpenCPSettingsMenu( param1 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

public Action Command_Save( int client, int args )
{
	int index = AUTO_SELECT_CP;
	if( args > 0 )
	{
		if( !g_aCheckpoints[client].Length )
		{
			Timer_ReplyToCommand( client, "{primary}No checkpoints found" );
			return Plugin_Handled;
		}
	
		char sArg[32];
		GetCmdArg( 1, sArg, sizeof(sArg) );
		index = StringToInt( sArg );
	}
	
	if( index != AUTO_SELECT_CP && !( 0 < index < g_aCheckpoints[client].Length ) )
	{
		Timer_ReplyToCommand( client, "{primary}Invalid checkpoint %i", index );
		return Plugin_Handled;
	}
	
	SaveCheckpoint( client, index );
	
	return Plugin_Handled;
}

public Action Command_Tele( int client, int args )
{
	if( !g_aCheckpoints[client].Length )
	{
		Timer_ReplyToCommand( client, "{primary}No checkpoints found" );
		return Plugin_Handled;
	}

	int index = AUTO_SELECT_CP;
	if( args > 0 )
	{
		char sArg[32];
		GetCmdArg( 1, sArg, sizeof(sArg) );
		index = StringToInt( sArg );
	}
	
	if( index != AUTO_SELECT_CP && !( 0 < index < g_aCheckpoints[client].Length ) )
	{
		Timer_ReplyToCommand( client, "{primary}Invalid checkpoint {secondary}%i", index );
		return Plugin_Handled;
	}
	
	LoadCheckpoint( client, index );

	return Plugin_Handled;
}

public Action Command_Delete( int client, int args )
{
	if( !g_aCheckpoints[client].Length )
	{
		Timer_ReplyToCommand( client, "{primary}No checkpoints found" );
		return Plugin_Handled;
	}

	if( args < 1 )
	{
		OpenSelectCPMenu( client, DeleteCheckpoint );
		return Plugin_Handled;
	}
	
	char sArg[32];
	GetCmdArg( 1, sArg, sizeof(sArg) );
	int index = StringToInt( sArg );
	
	if( !( 0 < index < g_aCheckpoints[client].Length ) )
	{
		Timer_ReplyToCommand( client, "{primary}Invalid checkpoint {secondary}%i", index );
		return Plugin_Handled;
	}

	DeleteCheckpoint( client, index );
	
	return Plugin_Handled;
}

stock void GetEntityAbsVelocity( int entity, float out[3] )
{
	GetEntPropVector( entity, Prop_Data, "m_vecAbsVelocity", out );
}

stock void GetEntityBaseVelocity( int entity, float out[3] )
{
	GetEntPropVector( entity, Prop_Data, "m_vecBaseVelocity", out );
}

stock void SetEntityBaseVelocity( int entity, float basevel[3] )
{
	SetEntPropVector( entity, Prop_Data, "m_vecBaseVelocity", basevel );
	
	if( basevel[0] != 0.0 || basevel[0] != 0.0 || basevel[0] != 0.0 )
	{
		SetEntityFlags( entity, GetEntityFlags( entity ) | FL_BASEVELOCITY );
	}
}

stock void GetEntityTargetname( int entity, char[] buffer, int maxlen )
{
	GetEntPropString( entity, Prop_Data, "m_iName", buffer, maxlen );
}

stock void SetEntityTargetname( int entity, char[] buffer )
{
	SetEntPropString( entity, Prop_Data, "m_iName", buffer );
}

stock void CopyVector( const float[] a, float[] b )
{
	b[0] = a[0];
	b[1] = a[1];
	b[2] = a[2];
}