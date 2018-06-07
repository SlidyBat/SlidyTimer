#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <slidy-timer>

#define MAX_TEAMS 12
#define MAX_TEAM_MEMBERS 10

Database g_hDatabase;
char g_cMapName[PLATFORM_MAX_PATH];

ConVar g_cvMaxPasses;
ConVar g_cvMaxUndos;

// invite system
int g_iInviteStyle[MAXPLAYERS + 1];
bool g_bCreatingTeam[MAXPLAYERS + 1];
ArrayList g_aInvitedPlayers[MAXPLAYERS + 1];
bool g_bInvitedPlayer[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_nDeclinedPlayers[MAXPLAYERS + 1];
ArrayList g_aAcceptedPlayers[MAXPLAYERS + 1];

// teams system
bool g_bAllowReset[MAXPLAYERS + 1];
bool g_bAllowStyleChange[MAXPLAYERS + 1];

int g_nUndoCount[MAX_TEAMS];
bool g_bDidUndo[MAX_TEAMS];
any g_LastCheckpoint[MAX_TEAMS][eCheckpoint];

char g_cTeamName[MAX_TEAMS][MAX_NAME_LENGTH];
int g_nPassCount[MAX_TEAMS];
int g_nRelayCount[MAX_TEAMS];
int g_iCurrentPlayer[MAX_TEAMS];
bool g_bTeamTaken[MAX_TEAMS];
int g_nTeamPlayerCount[MAX_TEAMS];

int g_iTeamIndex[MAXPLAYERS + 1] = { -1, ... };
int g_iNextTeamMember[MAXPLAYERS + 1];
char g_cPlayerTeamName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

// records system
ArrayList g_aCurrentSegmentStartTicks[MAX_TEAMS];
ArrayList g_aCurrentSegmentPlayers[MAX_TEAMS];

StringMap g_smSegmentPlayerNames[TOTAL_ZONE_TRACKS][MAX_STYLES];

ArrayList g_aMapTopRecordIds[TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList g_aMapTopTimes[TOTAL_ZONE_TRACKS][MAX_STYLES];
ArrayList g_aMapTopNames[TOTAL_ZONE_TRACKS][MAX_STYLES];

int g_iRecordId[MAXPLAYERS + 1][TOTAL_ZONE_TRACKS][MAX_STYLES];
float g_fPersonalBest[MAXPLAYERS + 1][TOTAL_ZONE_TRACKS][MAX_STYLES];

public Plugin myinfo = 
{
	name = "Slidy's Timer - Tagteam relay",
	author = "SlidyBat",
	description = "Plugin that manages the tagteam relay style",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	CreateNative( "Timer_IsClientInTagTeam", Native_IsClientInTagTeam );
	CreateNative( "Timer_GetClientTeamIndex", Native_GetClientTeamIndex );
	CreateNative( "Timer_GetTeamName", Native_GetTeamName );

	RegPluginLibrary( "timer-tagteam" );
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_aMapTopRecordIds[i][j] = new ArrayList();
			g_aMapTopTimes[i][j] = new ArrayList();
			g_aMapTopNames[i][j] = new ArrayList( ByteCountToCells( MAX_NAME_LENGTH ) );
		}
	}

	g_cvMaxPasses = CreateConVar( "sm_timer_tagteam_maxpasses", "-1", "Maximum number of passes a team can make or -1 for unlimited passes", _, true, -1.0, false );
	g_cvMaxUndos = CreateConVar( "sm_timer_tagteam_maxundos", "3", "Maximum number of undos a team can make or -1 for unlimited undos", _, true, -1.0, false );
	AutoExecConfig( true, "tagteam", "SlidyTimer" );
	
	RegConsoleCmd( "sm_teamname", Command_TeamName );
	RegConsoleCmd( "sm_exitteam", Command_ExitTeam );
	RegConsoleCmd( "sm_pass", Command_Pass );
	RegConsoleCmd( "sm_undo", Command_Undo );
	
	g_hDatabase = Timer_GetDatabase();
	SQL_CreateTables();
	
	GetCurrentMap( g_cMapName, sizeof(g_cMapName) );
}

public void OnMapStart()
{
	GetCurrentMap( g_cMapName, sizeof(g_cMapName) );
}

public void Timer_OnMapLoaded( int mapid )
{
	if( g_hDatabase != null )
	{
		SQL_LoadAllMapRecords();
	}
}

public void Timer_OnDatabaseLoaded()
{
	if( g_hDatabase == null )
	{
		g_hDatabase = Timer_GetDatabase();
		SQL_CreateTables();
	}
}

public void Timer_OnStylesLoaded( int totalstyles )
{
	for( int i = 0; i < totalstyles; i++ )
	{
		if( Timer_StyleHasSetting( i, "tagteam" ) )
		{
			Timer_SetCustomRecordsHandler( i, OnTimerFinishCustom );
		}
	}
}

public void Timer_OnReplayLoadedPost( int track, int style, int recordid, ArrayList frames )
{
	delete g_smSegmentPlayerNames[track][style];
	
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		SQL_LoadSegments( track, style, recordid );
	}
}

public void OnClientPutInServer( int client )
{
	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < MAX_STYLES; j++ )
		{
			g_fPersonalBest[client][i][j] = 0.0;
			g_iRecordId[client][i][j] = -1;
		}
	}
	
	Format( g_cPlayerTeamName[client], sizeof(g_cPlayerTeamName[]), "Team %N", client );
}

public void Timer_OnClientLoaded( int client, int playerid, bool newplayer )
{
	if( !newplayer )
	{
		SQL_LoadAllPlayerTimes( client );
	}
}

public void OnClientDisconnect( int client )
{
	if( !IsFakeClient( client ) && g_iTeamIndex[client] != -1 )
	{
		ExitTeam( client );
	}
}

public Action OnPlayerRunCmd( int client )
{
	int tick = Timer_GetReplayBotCurrentFrame( client );
	int track = Timer_GetReplayBotTrack( client );
	int style = Timer_GetReplayBotStyle( client );
	
	// not a valid replay bot or not currently replaying
	if( tick == -1 || track == -1 || style == -1 )
	{
		return Plugin_Continue;
	}
	
	if( g_smSegmentPlayerNames[track][style] == null )
	{
		return Plugin_Continue;
	}
	
	char sTick[8];
	IntToString( tick, sTick, sizeof(sTick) );
	char name[MAX_NAME_LENGTH];
	if( !g_smSegmentPlayerNames[track][style].GetString( sTick, name, sizeof(name) ) )
	{
		return Plugin_Continue;
	}
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i == client )
		{
			continue;
		}
		
		if( IsClientInGame( i ) && GetClientObserverTarget( i ) == client )
		{
			Timer_PrintToChat( i, "{primary}Current section by: {name}%s", name );
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_OnStyleChangedPre( int client, int oldstyle, int newstyle )
{
	if( Timer_StyleHasSetting( newstyle, "tagteam" ) )
	{
		if( g_iTeamIndex[client] == -1 ) // not in a team, make them create or join one before changing style
		{
			OpenInviteSelectMenu( client, 0, true, newstyle );
			Timer_PrintToChat( client, "{primary}Created '{secondary}%s{primary}'! Use {secondary}!teamname {primary}to set your team name.", g_cPlayerTeamName[client] );
			return Plugin_Handled;
		}
		
		return Plugin_Continue;
	}
	else if( Timer_StyleHasSetting( oldstyle, "tagteam" ) )
	{
		if( g_iTeamIndex[client] != -1 && !g_bAllowStyleChange[client] )
		{
			Timer_PrintToChat( client, "{primary}You cannot change style until you leave the team! Type {secondary}!exitteam {primary}to leave your team" );
			return Plugin_Handled;
		}
		if( g_bAllowStyleChange[client] )
		{
			g_bAllowStyleChange[client] = false;
		}
		
		return Plugin_Continue;
	}
	
	return Plugin_Continue;
}

public Action Timer_OnTimerFinishPre( int client, int track, int style, float time )
{
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		char sTime[64];
		Timer_FormatTime( time, sTime, sizeof(sTime) );
	
		char sZoneTrack[64];
		Timer_GetZoneTrackName( track, sZoneTrack, sizeof(sZoneTrack) );
	
		char sStyleName[32];
		Timer_GetStyleName( style, sStyleName, sizeof(sStyleName) );
		
		Timer_PrintToChatAll( "[{secondary}%s{white}] {name}%s {primary}finished on {secondary}%s {primary}timer in {secondary}%ss", sStyleName, g_cTeamName[g_iTeamIndex[client]], sZoneTrack, sTime );
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public Action Timer_OnClientTeleportToZonePre( int client, int zoneType, int zoneTrack, int subindex )
{
	if( g_iTeamIndex[client] != -1 && !g_bAllowReset[client] && !(g_nRelayCount[g_iTeamIndex[client]] == 0 && g_iCurrentPlayer[g_iTeamIndex[client]] == client) )
	{
		Timer_PrintToChat( client, "{primary}You cannot reset or teleport until you leave the team! Type {secondary}!exitteam {primary}to leave your team" );
		return Plugin_Handled;
	}
	if( g_bAllowReset[client] )
	{
		g_bAllowReset[client] = false;
	}
	
	return Plugin_Continue;
}

void OpenInviteSelectMenu( int client, int firstItem, bool reset = false, int style = 0 )
{
	if( reset )
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			g_bInvitedPlayer[client][i] = false;
		}
		
		g_bCreatingTeam[client] = true;
		g_iInviteStyle[client] = style;
		g_nDeclinedPlayers[client] = 0;
		
		delete g_aAcceptedPlayers[client];
		g_aAcceptedPlayers[client] = new ArrayList();
		
		delete g_aInvitedPlayers[client];
		g_aInvitedPlayers[client] = new ArrayList();
	}

	Menu menu = new Menu( InviteSelectMenu_Handler );
	menu.SetTitle( "Select players to invite:\n \n" );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i == client || !IsClientInGame( i ) || IsFakeClient( i ) || g_iTeamIndex[i] != -1 )
		{
			continue;
		}
	
		char name[MAX_NAME_LENGTH + 32];
		Format( name, sizeof(name), "[%s] %N", g_bInvitedPlayer[client][i] ? "X" : " ", i );
	
		char userid[8];
		IntToString( GetClientUserId( i ), userid, sizeof(userid) );
		
		menu.AddItem( userid, name );
	}
	
	menu.AddItem( "send", "Send Invites!", g_aInvitedPlayers[client].Length == 0 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT );
	
	menu.DisplayAt( client, firstItem, MENU_TIME_FOREVER );
}

public int InviteSelectMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char info[8];
		menu.GetItem( param2, info, sizeof(info) );
		
		if( StrEqual( info, "send" ) ) // send the invites!
		{
			int length = g_aInvitedPlayers[param1].Length;
			for( int i = 0; i < length; i++ )
			{
				SendInvite( param1, GetClientOfUserId( g_aInvitedPlayers[param1].Get( i ) ) );
			}
			
			Timer_PrintToChat( param1, "Invites sent!" );
			
			OpenLobbyMenu( param1 );
		}
		else
		{
			int userid = StringToInt( info );
			int target = GetClientOfUserId( userid );
			if( 0 < target <= MaxClients )
			{
				g_bInvitedPlayer[param1][target] = !g_bInvitedPlayer[param1][target];
				if( g_bInvitedPlayer[param1][target] )
				{
					g_aInvitedPlayers[param1].Push( userid );
				}
				else
				{
					int idx = g_aInvitedPlayers[param1].FindValue( userid );
					if( idx != -1 )
					{
						g_aInvitedPlayers[param1].Erase( idx );
					}
				}
			}
			
			OpenInviteSelectMenu( param1, (param2 / 6) * 6 );
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void SendInvite( int client, int target )
{
	Menu menu = new Menu( InviteMenu_Handler );
	
	char buffer[256];
	Format( buffer, sizeof(buffer), "%N has invited you to play tagteam!\nAccept?\n \n", client );
	menu.SetTitle( buffer );
	
	char userid[8];
	IntToString( GetClientUserId( client ), userid, sizeof(userid) );
	
	menu.AddItem( userid, "Yes" );
	menu.AddItem( userid, "No" );
	
	menu.Display( target, 20 );
}

public int InviteMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char info[8];
		menu.GetItem( param2, info, sizeof(info) );
		
		int client = GetClientOfUserId( StringToInt( info ) );
		if( !( 0 < client <= MaxClients ) )
		{
			return 0;
		}
	
		if( param2 == 0 ) // yes
		{
			if( !g_bCreatingTeam[client] )
			{
				Timer_PrintToChat( param1, "The team has been cancelled or has already started the run" );
			}
			if( g_aAcceptedPlayers[client].Length >= MAX_TEAM_MEMBERS )
			{
				Timer_PrintToChat( param1, "The team is now full, cannot join" );
			}
			else
			{
				g_aAcceptedPlayers[client].Push( GetClientUserId( param1 ) );
				OpenLobbyMenu( client );
			}
		}
		else // no
		{
			g_nDeclinedPlayers[client]++;
			Timer_PrintToChat( client, "{name}%N {primary}has declined your invite", param1 );
		}
		
		Timer_DebugPrint( "InviteMenu_Handler: %i + %i, %i", g_aAcceptedPlayers[client].Length, g_nDeclinedPlayers[client], g_aInvitedPlayers[client].Length );
		if( g_aAcceptedPlayers[client].Length + g_nDeclinedPlayers[client] == g_aInvitedPlayers[client].Length ) // everyone responded
		{
			FinishInvite( client );
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
	
	return 0;
}

void OpenLobbyMenu( int client )
{
	Menu menu = new Menu( LobbyMenu_Handler );
	
	char buffer[512];
	Format( buffer, sizeof(buffer), "%s\n \nMembers:\n%N\n", g_cPlayerTeamName[client], client );
	
	int length = g_aAcceptedPlayers[client].Length;
	for( int i = 0; i < length; i++ )
	{
		Format( buffer, sizeof(buffer), "%N\n", GetClientOfUserId( g_aAcceptedPlayers[client].Get( i ) ) );
	}
	
	menu.SetTitle( buffer );
	
	menu.AddItem( "start", "Start", (length > 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );
	menu.AddItem( "cancel", "Cancel" );
	
	menu.ExitButton = false;
	menu.Display( client, MENU_TIME_FOREVER );
}

public int LobbyMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		if( param1 == 0 ) // start
		{
			FinishInvite( param1 );
		}
		else if( param1 == 1 ) // cancel
		{
			CancelInvite( param1 );
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void FinishInvite( int client )
{
	g_bCreatingTeam[client] = false;

	int length = g_aAcceptedPlayers[client].Length;
	
	if( length < 1 )
	{
		Timer_PrintToChat( client, "{primary}Not enough players to create a team" );
		return;
	}
	
	int[] members = new int[length + 1];
	
	members[0] = client;
	for( int i = 0; i < length; i++ )
	{
		members[i + 1] = GetClientOfUserId( g_aAcceptedPlayers[client].Get( i ) );
	}
	
	CreateTeam( members, length + 1, g_iInviteStyle[client] );
	
	int letters;
	char buffer[512];
	for( int i = 0; i <= length; i++ )
	{
		letters += Format( buffer, sizeof(buffer), "%s{name}%N{primary}, ", buffer, members[i] );
	}
	buffer[letters - 3] = '\0';
	
	PrintToTeam( g_iTeamIndex[client], "{secondary}%s has been assembled! Members: %s", g_cTeamName[g_iTeamIndex[client]], buffer );
}

void CancelInvite( int client )
{
	g_bCreatingTeam[client] = false;
}

void CreateTeam( int[] members, int memberCount, int style )
{
	Timer_DebugPrint( "CreateTeam: memberCount=%i", memberCount );

	int teamindex = -1;
	for( int i = 0; i < MAX_TEAMS; i++ )
	{
		if( !g_bTeamTaken[i] )
		{
			teamindex = i;
			break;
		}
	}
	
	if( teamindex == -1 )
	{
		LogError( "Not enough teams" );
		return;
	}
	
	g_nUndoCount[teamindex] = 0;
	g_nPassCount[teamindex] = 0;
	g_nRelayCount[teamindex] = 0;
	g_bTeamTaken[teamindex] = true;
	g_nTeamPlayerCount[teamindex] = memberCount;
	strcopy( g_cTeamName[teamindex], sizeof(g_cTeamName[]), g_cPlayerTeamName[members[0]] );
	
	delete g_aCurrentSegmentStartTicks[teamindex];
	g_aCurrentSegmentStartTicks[teamindex] = new ArrayList();
	delete g_aCurrentSegmentPlayers[teamindex];
	g_aCurrentSegmentPlayers[teamindex] = new ArrayList();
	
	g_aCurrentSegmentStartTicks[teamindex].Push( 2 ); // not zero so that it doesnt spam print during first tick freeze time
	g_aCurrentSegmentPlayers[teamindex].Push( Timer_GetClientPlayerId( members[0] ) );
	
	int next = members[0];
	for( int i = memberCount - 1; i >= 0; i-- )
	{
		Timer_DebugPrint( "CreateTeam: Adding member %N", members[i] );
	
		g_iNextTeamMember[members[i]] = next;
		next = members[i];
		
		g_iTeamIndex[members[i]] = teamindex;
		
		g_bAllowStyleChange[members[i]] = true;
		Timer_SetClientStyle( members[i], style );
	}
	
	TeleportClientToZone( members[0], Zone_Start, ZoneTrack_Main );
	Timer_OpenCheckpointsMenu( members[0] );
	g_iCurrentPlayer[teamindex] = members[0];
	
	for( int i = 1; i < memberCount; i++ )
	{
		Timer_DebugPrint( "CreateTeam: Moving %N to spec %N", members[i], members[0] );
	
		ChangeClientTeam( members[i], CS_TEAM_SPECTATOR );
		SetEntPropEnt( members[i], Prop_Send, "m_hObserverTarget", members[0] );
		SetEntProp( members[i], Prop_Send, "m_iObserverMode", 4 );
	}
}

bool ExitTeam( int client )
{
	if( g_iTeamIndex[client] == -1 )
	{
		Timer_SetClientStyle( client, 0 );
		TeleportClientToZone( client, Zone_Start, ZoneTrack_Main );
		return false;
	}
	
	int teamidx = g_iTeamIndex[client];
	g_iTeamIndex[client] = -1;
	
	g_nTeamPlayerCount[teamidx]--;
	if( g_nTeamPlayerCount[teamidx] <= 1 )
	{
		g_bTeamTaken[teamidx] = false;
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( i != client && g_iTeamIndex[i] == teamidx )
			{
				Timer_PrintToChat( i, "{primary}All your team members have left, your team has been disbanded!" );
				ExitTeam( i );
				break;
			}
		}
	}
	else
	{
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( g_iNextTeamMember[i] == client )
			{
				g_iNextTeamMember[i] = g_iNextTeamMember[client];
			}
		}
	}
	
	g_iNextTeamMember[client] = -1;
	
	Timer_SetClientStyle( client, 0 );
	TeleportClientToZone( client, Zone_Start, ZoneTrack_Main );
	
	return true;
}

public Action Timer_OnCPLoadedPre( int client, int idx )
{
	if( g_iTeamIndex[client] != -1 && g_iCurrentPlayer[g_iTeamIndex[client]] != client )
	{
		Timer_PrintToChat( client, "{primary}Cannot load when it is not your turn" );
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Timer_OnCPSavedPre( int client, int target, int idx )
{
	if( g_iTeamIndex[client] != -1 && client != target )
	{
		Timer_PrintToChat( client, "{primary}Cannot save when it is not your turn" );
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void Timer_OnCPSavedPost( int client, int target, int idx )
{
	if( g_iTeamIndex[client] != -1 )
	{
		int teamidx = g_iTeamIndex[client];
		
		if( !g_bDidUndo[teamidx] )
		{
			delete g_LastCheckpoint[teamidx][CP_ReplayFrames];
		}
		Timer_GetClientCheckpoint( client, 0, g_LastCheckpoint[teamidx] );
		
		// 'frames' will be deleted by PassToNext
		ArrayList frames = g_LastCheckpoint[teamidx][CP_ReplayFrames];
		g_LastCheckpoint[teamidx][CP_ReplayFrames] = frames.Clone();
		
		g_nRelayCount[teamidx]++;
		int next = g_iNextTeamMember[client];
	
		any checkpoint[eCheckpoint];
		Timer_GetClientCheckpoint( client, idx, checkpoint );
		
		g_aCurrentSegmentStartTicks[teamidx].Push( checkpoint[CP_ReplayFrames].Length - 1 );
		g_aCurrentSegmentPlayers[teamidx].Push( Timer_GetClientPlayerId( next ) );
		
		PassToNext( client, next, checkpoint );
		
		g_bDidUndo[teamidx] = false;
	}
}

// Commands

public Action Command_TeamName( int client, int args )
{
	GetCmdArgString( g_cPlayerTeamName[client], sizeof(g_cPlayerTeamName[]) );
	if( g_iTeamIndex[client] != -1 )
	{
		strcopy( g_cTeamName[g_iTeamIndex[client]], sizeof(g_cTeamName[]), g_cPlayerTeamName[client] );
	}
	
	Timer_ReplyToCommand( client, "{primary}Team name set to: {secondary}%s", g_cPlayerTeamName[client] );
	
	return Plugin_Handled;
}

public Action Command_ExitTeam( int client, int args )
{
	if( !ExitTeam( client ) )
	{
		Timer_ReplyToCommand( client, "{primary}You are not currently in a team" );
	}
	
	return Plugin_Handled;
}

public Action Command_Pass( int client, int args )
{
	if( g_iTeamIndex[client] == -1 )
	{
		Timer_ReplyToCommand( client, "{primary}You are not currently in a team" );
		return Plugin_Handled;
	}
	
	int teamidx = g_iTeamIndex[client];
	int maxPasses = g_cvMaxPasses.IntValue;
	
	if( maxPasses > -1 && g_nPassCount[teamidx] >= maxPasses )
	{
		Timer_ReplyToCommand( client, "{primary}Your team has used all %i passes", maxPasses );
		return Plugin_Handled;
	}
	
	if( g_iCurrentPlayer[teamidx] != client )
	{
		Timer_ReplyToCommand( client, "{primary}You cannot pass when it is not your turn" );
		return Plugin_Handled;
	}
	
	g_nPassCount[teamidx]++;
	
	any checkpoint[eCheckpoint];
	bool usecp = Timer_GetTotalCheckpoints( client ) > 0;
	
	if( usecp )
	{
		Timer_GetClientCheckpoint( client, 0, checkpoint );
	}
	
	PassToNext( client, g_iNextTeamMember[client], checkpoint, usecp );
	
	int lastidx = g_aCurrentSegmentPlayers[teamidx].Length - 1;
	g_aCurrentSegmentPlayers[teamidx].Set( lastidx, Timer_GetClientPlayerId( g_iNextTeamMember[client] ) );
	
	if( maxPasses > -1 )
	{
		PrintToTeam( teamidx, "{name}%N {primary}has passed! It is now {name}%N{primary}'s turn. {secondary}%i/%i {primary}passes used.", client, g_iNextTeamMember[client], g_nPassCount[teamidx], maxPasses );
	}
	else
	{
		PrintToTeam( teamidx, "{name}%N {primary}has passed! It is now {name}%N{primary}'s turn.", client, g_iNextTeamMember[client] );
	}
	
	return Plugin_Handled;
}

public Action Command_Undo( int client, int args )
{
	if( g_iTeamIndex[client] == -1 )
	{
		Timer_ReplyToCommand( client, "{primary}You are not currently in a team" );
		return Plugin_Handled;
	}
	
	int teamidx = g_iTeamIndex[client];
	
	int maxUndos = g_cvMaxUndos.IntValue;
	if( maxUndos == -1 || g_nUndoCount[teamidx] >= maxUndos )
	{
		Timer_ReplyToCommand( client, "{primary}Your team has already used all %i undos", maxUndos );
		return Plugin_Handled;
	}
	
	if( g_iCurrentPlayer[teamidx] != client )
	{
		Timer_ReplyToCommand( client, "{primary}You cannot undo when it is not your turn" );
		return Plugin_Handled;
	}
	
	if( g_nRelayCount[teamidx] == 0 )
	{
		Timer_ReplyToCommand( client, "{primary}Cannot undo when no one has saved!" );
		return Plugin_Handled;
	}
	
	if( g_bDidUndo[teamidx] )
	{
		Timer_ReplyToCommand( client, "{primary}Your team has already undo-ed this turn" );
		return Plugin_Handled;
	}
	
	int last = -1;
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_iNextTeamMember[i] == client )
		{
			last = i;
			break;
		}
	}
	
	if( last == -1 )
	{
		LogError( "Failed to find last player" );
		return Plugin_Handled;
	}
	
	PassToNext( client, last, g_LastCheckpoint[teamidx] );
	g_aCurrentSegmentStartTicks[teamidx].Erase( g_aCurrentSegmentStartTicks[teamidx].Length - 1 );
	g_aCurrentSegmentPlayers[teamidx].Erase( g_aCurrentSegmentPlayers[teamidx].Length - 1 );
	g_bDidUndo[teamidx] = true;
	g_nUndoCount[teamidx]++;
	
	if( maxUndos > -1 )
	{
		PrintToTeam( teamidx, "{name}%N {primary}used an undo! It is now {name}%N{primary}'s turn again. {secondary}%i/%i {primary}undos used.", client, last, g_nUndoCount[teamidx], maxUndos );
	}
	else
	{
		PrintToTeam( teamidx, "{name}%N {primary}used an undo! It is now {name}%N{primary}'s turn again.", client, last );
	}
	return Plugin_Handled;
}

// Records/Database stuff

void OnTimerFinishCustom( int client, int track, int style, float time, Handle fwdInsertedPre, Handle fwdInsertedPost, Handle fwdUpdatedPre, Handle fwdUpdatedPost )
{
	if( g_iTeamIndex[client] == -1 )
	{
		LogError( "%N finished on tagteam without a team!", client );
		return;
	}
	
	ArrayList frames = Timer_GetClientReplayFrames( client );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i != client && g_iTeamIndex[i] == g_iTeamIndex[client] )
		{
			Timer_SetClientReplayFrames( i, frames );
		}
	}
	
	delete frames;
	
	SQL_InsertRecord( client, g_iTeamIndex[client], track, style, time, fwdInsertedPre, fwdInsertedPost, fwdUpdatedPre, fwdUpdatedPost );
}

void SQL_CreateTables()
{
	if( g_hDatabase == null )
	{
		return;
	}
	
	Transaction txn = new Transaction();
	
	// makes a table that links multiple players to 1 record
	char query[512];
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_tagteam_records` ( tt_recordid INT NOT NULL AUTO_INCREMENT, \
																					teamname CHAR(64) NOT NULL, \
																					mapid INT NOT NULL, \
																					timestamp INT NOT NULL, \
																					time FLOAT NOT NULL, \
																					track INT NOT NULL, \
																					style INT NOT NULL, \
																					jumps INT NOT NULL, \
																					strafes INT NOT NULL, \
																					sync FLOAT NOT NULL, \
																					strafetime FLOAT NOT NULL, \
																					ssj INT NOT NULL, \
																					PRIMARY KEY (`tt_recordid`) );" );
																					
	txn.AddQuery( query );
	
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_tagteam_pb` ( tt_timeid INT NOT NULL AUTO_INCREMENT, \
																				playerid INT NOT NULL, \
																				tt_recordid INT NOT NULL, \
																				PRIMARY KEY (`tt_timeid`) );" );
	
	txn.AddQuery( query );
	
	Format( query, sizeof(query), "CREATE TABLE IF NOT EXISTS `t_tagteam_segments` ( tt_segmentid INT NOT NULL AUTO_INCREMENT, \
																					playerid INT NOT NULL, \
																					recordid INT NOT NULL, \
																					starttick INT NOT NULL, \
																					PRIMARY KEY (`tt_segmentid`) );" );
	
	txn.AddQuery( query );
	
	g_hDatabase.Execute( txn, CreateTableSuccess_Callback, CreateTableFailure_Callback, _, DBPrio_High );
}

public void CreateTableSuccess_Callback( Database db, any data, int numQueries, DBResultSet[] results, any[] queryData )
{
	if( Timer_GetMapId() > -1 )
	{
		SQL_LoadAllMapRecords();
	}
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( Timer_IsClientLoaded( i ) )
		{
			SQL_LoadAllPlayerTimes( i );
		}
	}
}

public void CreateTableFailure_Callback( Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData )
{
	SetFailState( "[SQL ERROR] (CreateTableFailure_Callback) - %s", error );
}

void SQL_LoadAllPlayerTimes( int client )
{
	int styles = Timer_GetStyleCount();
	for( int i = 0; i < styles; i++ )
	{
		if( Timer_StyleHasSetting( i, "tagteam" ) )
		{
			SQL_LoadPlayerTime( client, ZoneTrack_Main, i );
			SQL_LoadPlayerTime( client, ZoneTrack_Bonus, i );
		}
	}
}

void SQL_LoadPlayerTime( int client, int track, int style )
{
	char query[512];
	Format( query, sizeof(query), "SELECT r.tt_recordid, r.time FROM `t_tagteam_records` r \
								JOIN `t_tagteam_pb` t ON r.tt_recordid = t.tt_recordid \
								WHERE t.playerid = '%i' AND r.mapid = '%i' AND r.track = '%i' AND r.style = '%i'",
								Timer_GetClientPlayerId( client ),
								Timer_GetMapId(),
								track,
								style );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	g_hDatabase.Query( LoadPlayerTime_Callback, query, pack );
}

public void LoadPlayerTime_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadPlayerTime_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	if( !( 0 < client <= MaxClients ) )
	{
		return;
	}
	
	if( results.FetchRow() )
	{
		g_iRecordId[client][track][style] = results.FetchInt( 0 );
		g_fPersonalBest[client][track][style] = results.FetchFloat( 1 );
		Timer_DebugPrint( "LoadPlayerTime_Callback: %N recordid=%i pb=%f", client, g_iRecordId[client][track][style], g_fPersonalBest[client][track][style] );
	}
}

void SQL_InsertRecord( int client, int teamidx, int track, int style, float time, Handle fwdInsertedPre, Handle fwdInsertedPost, Handle fwdUpdatedPre, Handle fwdUpdatedPost )
{
	char query[512];
	Format( query, sizeof(query), "INSERT INTO `t_tagteam_records` (teamname, mapid, timestamp, time, track, style, jumps, strafes, sync, strafetime, ssj) \
								VALUES ('%s', '%i', '%i', '%f', '%i', '%i', '%i', '%i', '%f', '%f', '%i')",
								g_cTeamName[teamidx],
								Timer_GetMapId(),
								GetTime(),
								time,
								track,
								style,
								Timer_GetClientCurrentJumps( client ),
								Timer_GetClientCurrentStrafes( client ),
								Timer_GetClientCurrentSync( client ),
								Timer_GetClientCurrentStrafeTime( client ),
								Timer_GetClientCurrentSSJ( client ) );
	
	DataPack pack = new DataPack();
	pack.WriteCell( teamidx );
	pack.WriteCell( track );
	pack.WriteCell( style );
	pack.WriteFloat( time );
	pack.WriteCell( fwdInsertedPre );
	pack.WriteCell( fwdInsertedPost );
	pack.WriteCell( fwdUpdatedPre );
	pack.WriteCell( fwdUpdatedPost );
	
	g_hDatabase.Query( InsertRecord_Callback, query, pack );
}

public void InsertRecord_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertRecord_Callback) - %s", error );
		delete pack;
		return;
	}
	
	int recordid = results.InsertId;
	
	pack.Reset();
	int teamidx = pack.ReadCell();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	float time = pack.ReadFloat();
	Handle fwdInsertedPre = pack.ReadCell();
	Handle fwdInsertedPost = pack.ReadCell();
	Handle fwdUpdatedPre = pack.ReadCell();
	Handle fwdUpdatedPost = pack.ReadCell();
	delete pack;
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_iTeamIndex[i] == teamidx )
		{
			if( g_fPersonalBest[i][track][style] == 0.0 || time <= g_fPersonalBest[i][track][style] )
			{
				if( g_fPersonalBest[i][track][style] == 0.0 )
				{
					SQL_InsertPlayerTime( i, track, style, time, recordid, fwdInsertedPre, fwdInsertedPost );
				}
				else
				{
					SQL_UpdatePlayerTime( i, track, style, time, recordid, fwdUpdatedPre, fwdUpdatedPost );
				}
			}
		}
	}
	
	SQL_InsertSegments( teamidx, track, style, recordid );
	
	SQL_LoadMapRecords( track, style );
}

void SQL_InsertPlayerTime( int client, int track, int style, float time, int recordid, Handle fwdInsertedPre, Handle fwdInsertedPost )
{
	Timer_DebugPrint( "Inserting time for %N", client );

	any result = Plugin_Continue;
	Call_StartForward( fwdInsertedPre );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_Finish( result );
	
	if( result == Plugin_Handled || result == Plugin_Stop )
	{
		return;
	}

	g_iRecordId[client][track][style] = recordid;
	g_fPersonalBest[client][track][style] = time;
	
	char query[512];
	Format( query, sizeof(query), "INSERT INTO `t_tagteam_pb` (playerid, tt_recordid) \
								VALUES ('%i', '%i')",
								Timer_GetClientPlayerId( client ), recordid );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( track );
	pack.WriteCell( style );
	pack.WriteFloat( time );
	pack.WriteCell( recordid );
	pack.WriteCell( fwdInsertedPost );
	
	g_hDatabase.Query( InsertPlayerTime_Callback, query, pack );
}

public void InsertPlayerTime_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertPlayerTime_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	float time = pack.ReadFloat();
	int recordid = pack.ReadCell();
	Handle fwdInsertedPost = pack.ReadCell();
	delete pack;
	
	if( !( 0 < client <= MaxClients ) )
	{
		return;
	}
	
	Call_StartForward( fwdInsertedPost );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_PushCell( recordid );
	Call_Finish();
}

void SQL_UpdatePlayerTime( int client, int track, int style, float time, int recordid, Handle fwdUpdatedPre, Handle fwdUpdatedPost )
{
	any result = Plugin_Continue;
	Call_StartForward( fwdUpdatedPre );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_Finish( result );
	
	if( result == Plugin_Handled || result == Plugin_Stop )
	{
		return;
	}

	char query[512];
	Format( query, sizeof(query), "UPDATE `t_tagteam_pb` SET tt_recordid = '%i' \
								WHERE playerid = '%i' AND tt_recordid = '%i'",
								recordid, g_iRecordId[client] );
	
	DataPack pack = new DataPack();
	pack.WriteCell( GetClientUserId( client ) );
	pack.WriteCell( track );
	pack.WriteCell( style );
	pack.WriteFloat( time );
	pack.WriteCell( recordid );
	pack.WriteCell( fwdUpdatedPost );
	
	g_hDatabase.Query( UpdatePlayerTime_Callback, query, pack );
	
	g_iRecordId[client][track][style] = recordid;
	g_fPersonalBest[client][track][style] = time;
}

public void UpdatePlayerTime_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (UpdatePlayerTime_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int client = GetClientOfUserId( pack.ReadCell() );
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	float time = pack.ReadFloat();
	int recordid = pack.ReadCell();
	Handle fwdUpdatedPost = pack.ReadCell();
	delete pack;
	
	if( !( 0 < client <= MaxClients ) )
	{
		return;
	}
	
	Call_StartForward( fwdUpdatedPost );
	Call_PushCell( client );
	Call_PushCell( track );
	Call_PushCell( style );
	Call_PushFloat( time );
	Call_PushCell( recordid );
	Call_Finish();
}

void SQL_LoadAllMapRecords()
{
	int styles = Timer_GetStyleCount();
	for( int i = 0; i < styles; i++ )
	{
		if( Timer_StyleHasSetting( i, "tagteam" ) )
		{
			SQL_LoadMapRecords( ZoneTrack_Main, i );
			SQL_LoadMapRecords( ZoneTrack_Bonus, i );
		}
	}
}

void SQL_LoadMapRecords( int track, int style )
{
	Timer_DebugPrint( "SQL_LoadMapRecords: Loading map records" );

	char query[512];
	Format( query, sizeof(query), "SELECT tt_recordid, time, teamname FROM `t_tagteam_records` \
									WHERE mapid = '%i' AND track = '%i' AND style = '%i' \
									ORDER BY time ASC", 
									Timer_GetMapId(), track, style );
	
	DataPack pack = new DataPack();
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	g_hDatabase.Query( LoadMapRecords_Callback, query, pack, DBPrio_High );
}

public void LoadMapRecords_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadMapRecords_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	g_aMapTopRecordIds[track][style].Clear();
	g_aMapTopTimes[track][style].Clear();
	g_aMapTopNames[track][style].Clear();
	
	
	Timer_DebugPrint( "LoadMapRecords_Callback: Got %i rows", results.RowCount );
	
	char name[MAX_NAME_LENGTH];
	while( results.FetchRow() )
	{
		g_aMapTopRecordIds[track][style].Push( results.FetchInt( 0 ) );
		g_aMapTopTimes[track][style].Push( results.FetchFloat( 1 ) );
		results.FetchString( 2, name, sizeof(name) );
		g_aMapTopNames[track][style].PushString( name );
	}
}

void SQL_InsertSegments( int teamidx, int track, int style, int recordid )
{
	char query[256];

	int length = g_aCurrentSegmentStartTicks[teamidx].Length;
	for( int i = 0; i < length; i++ )
	{
		DataPack pack = new DataPack();
		pack.WriteCell( track );
		pack.WriteCell( style );
		pack.WriteCell( recordid );
	
		Format( query, sizeof(query), "INSERT INTO `t_tagteam_segments` (playerid, recordid, starttick) VALUES ('%i', '%i', '%i')",
										g_aCurrentSegmentPlayers[teamidx].Get( i ),
										recordid,
										g_aCurrentSegmentStartTicks[teamidx].Get( i ) );
										
		g_hDatabase.Query( InsertSegments_Callback, query, pack );
	}
}

public void InsertSegments_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (InsertSegments_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	int recordid = Timer_GetReplayRecordId( track, style );
	if( recordid > -1 )
	{
		SQL_LoadSegments( track, style, recordid );
	}
}

void SQL_LoadSegments( int track, int style, int recordid )
{
	char query[512];
	Format( query, sizeof(query), "SELECT s.starttick, p.lastname FROM `t_tagteam_segments` s \
								JOIN `t_players` p ON p.playerid = s.playerid \
								WHERE s.recordid = '%i' \
								ORDER BY s.starttick ASC", recordid );
	
	DataPack pack = new DataPack();
	pack.WriteCell( track );
	pack.WriteCell( style );
	
	g_hDatabase.Query( LoadSegments_Callback, query, pack );
}

public void LoadSegments_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (LoadSegments_Callback) - %s", error );
		delete pack;
		return;
	}
	
	pack.Reset();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	delete g_smSegmentPlayerNames[track][style];
	g_smSegmentPlayerNames[track][style] = new StringMap();
	
	char sStartTick[8];
	char name[MAX_NAME_LENGTH];
	while( results.FetchRow() )
	{
		IntToString( results.FetchInt( 0 ), sStartTick, sizeof(sStartTick) );
		results.FetchString( 1, name, sizeof(name) );
		
		g_smSegmentPlayerNames[track][style].SetString( sStartTick, name );
	}
}

public Action Timer_OnClientRankRequested( int client, int track, int style, int& rank )
{
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		rank = GetClientMapRank( client, track, style );
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_OnClientPBTimeRequested( int client, int track, int style, float& time )
{
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		time = g_fPersonalBest[client][track][style];
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_OnWRTimeRequested( int track, int style, float& time )
{
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		if( g_aMapTopTimes[track][style].Length > 0 )
		{
			time = g_aMapTopTimes[track][style].Get( 0 );
		}
		else
		{
			time = 0.0;
		}
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_OnWRNameRequested( int track, int style, char name[MAX_NAME_LENGTH] )
{
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		g_aMapTopNames[track][style].GetString( 0, name, sizeof(name) );
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_OnRecordsCountRequested( int track, int style, int& recordcount )
{
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		recordcount = g_aMapTopTimes[track][style].Length;
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_OnLeaderboardRequested( int client, int track, int style )
{
	if( Timer_StyleHasSetting( style, "tagteam" ) )
	{
		int length = g_aMapTopTimes[track][style].Length;
		
		if( length == 0 )
		{
			Timer_PrintToChat( client, "{primary}No records found" );
			return Plugin_Handled;
		}
		
		Menu menu = new Menu( Leaderboard_Handler );
		menu.SetTitle( "Tagteam leaderboard\n \n" );
		
		char buffer[256];
		
		int max = length > 50 ? 50 : length;
		for( int i = 0; i < max; i++ )
		{
			char name[MAX_NAME_LENGTH];
			g_aMapTopNames[track][style].GetString( i, name, sizeof(name) );
			
			float time = g_aMapTopTimes[track][style].Get( i );
			char sTime[32];
			Timer_FormatTime( time, sTime, sizeof(sTime) );
			
			char sRecordId[8];
			IntToString( g_aMapTopRecordIds[track][style].Get( i ), sRecordId, sizeof(sRecordId) );
			
			Format( buffer, sizeof(buffer), "[#%i] %s (%s)", i + 1, name, sTime );
			
			menu.AddItem( sRecordId, buffer );
		}
		
		menu.Display( client, MENU_TIME_FOREVER );
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public int Leaderboard_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char info[8];
		menu.GetItem( param2, info, sizeof(info) );
		
		int recordid = StringToInt( info );
		SQL_ShowStats( param1, recordid );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void SQL_ShowStats( int client, int recordid )
{
	Timer_PrintToChat( client, "{primary}Tagteam record stats soon! (%i)", recordid );
}

int GetRankForTime( float time, int track, int style )
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

int GetClientMapRank( int client, int track, int style )
{
	// subtract 1 because when times are equal, it counts as next rank
	return GetRankForTime( g_fPersonalBest[client][track][style], track, style ) - 1;
}

// natives

public int Native_IsClientInTagTeam( Handle handler, int numParams )
{
	int client = GetNativeCell( 1 );
	int teamidx = GetNativeCell( 2 );

	if( teamidx == -1 )
	{
		return g_iTeamIndex[client] != -1;
	}
	
	return g_iTeamIndex[client] == teamidx;
}

public int Native_GetClientTeamIndex( Handle handler, int numParams )
{
	return g_iTeamIndex[GetNativeCell( 1 )];
}

public int Native_GetTeamName( Handle handler, int numParams )
{
	int teamidx = GetNativeCell( 1 );
	if( !g_bTeamTaken[teamidx] )
	{
		return false;
	}
	
	SetNativeString( 2, g_cTeamName[teamidx], GetNativeCell( 3 ) );
	
	return true;
}

// helper functions

void TeleportClientToZone( int client, int zoneType, int zoneTrack )
{
	g_bAllowReset[client] = true;
	Timer_TeleportClientToZone( client, zoneType, zoneTrack );
}

void PassToNext( int client, int next, any checkpoint[eCheckpoint], bool usecp = true )
{
	int length;
	
	length = Timer_GetTotalCheckpoints( client );
	for( int i = 0; i < length; i++ )
	{
		any cp[eCheckpoint];
		Timer_GetClientCheckpoint( client, i, cp );
		
		if( cp[CP_ReplayFrames] != checkpoint[CP_ReplayFrames] )
		{
			delete cp[CP_ReplayFrames];
		}
	}
	
	length = Timer_GetTotalCheckpoints( next );
	for( int i = 0; i < length; i++ )
	{
		any cp[eCheckpoint];
		Timer_GetClientCheckpoint( next, i, cp );
		
		if( cp[CP_ReplayFrames] != checkpoint[CP_ReplayFrames] )
		{
			delete cp[CP_ReplayFrames];
		}
	}

	Timer_ClearClientCheckpoints( client );
	Timer_ClearClientCheckpoints( next );
	
	if( usecp )
	{
		Timer_SetClientCheckpoint( next, -1, checkpoint );
	}
	ChangeClientTeam( next, CS_TEAM_SPECTATOR );
	ChangeClientTeam( next, CS_TEAM_T );
	CS_RespawnPlayer( next );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && !IsFakeClient( i ) && IsClientObserver( i ) && GetEntPropEnt( client, Prop_Send, "m_hObserverTarget" ) == client )
		{
			SetEntPropEnt( client, Prop_Send, "m_hObserverTarget", next );
			SetEntProp( client, Prop_Send, "m_iObserverMode", 4 );
		}
	}
	
	ChangeClientTeam( client, CS_TEAM_SPECTATOR );
	SetEntPropEnt( client, Prop_Send, "m_hObserverTarget", next );
	SetEntProp( client, Prop_Send, "m_iObserverMode", 4 );
	
	g_iCurrentPlayer[g_iTeamIndex[client]] = next;
	
	if( usecp )
	{
		Timer_TeleportClientToCheckpoint( next, 0 );
	}
	Timer_OpenCheckpointsMenu( next );
}

void PrintToTeam( int teamidx, char[] message, any ... )
{
	char buffer[512];
	VFormat( buffer, sizeof(buffer), message, 3 );
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_iTeamIndex[i] == teamidx )
		{
			Timer_PrintToChat( i, buffer );
		}
	}
}