#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <smlib>
#include <slidy-timer>

#pragma newdecls required
#pragma semicolon 1

#define REPLAY_VERSION 1
#define MAGIC_NUMBER 0x59444C53 // "SLDY"

#define FRAME_DATA_SIZE 6

#define MAX_MULTIREPLAY_BOTS 5
#define MAX_STYLE_BOTS 5

enum
{
	ReplayBot_None,
	ReplayBot_Multireplay,
	ReplayBot_Style,
	TOTAL_REPALY_BOT_TYPES
}

enum ReplayHeader
{
	HD_MagicNumber,
	HD_ReplayVersion,
	HD_SteamAccountId,
	Float:HD_Time,
	HD_Size,
	HD_TickRate,
	HD_Timestamp
}

char g_cReplayFolders[][] = 
{
	"Replays",
	"ReplayBackups"
};

Database g_hDatabase;

ConVar 		bot_quota;

float			g_fFrameTime;
float			g_fTickRate;
char			g_cCurrentMap[PLATFORM_MAX_PATH];

ArrayList		g_aReplayQueue;

ArrayList		g_aReplayFrames[TOTAL_ZONE_TRACKS][MAX_STYLES];
float			g_fReplayRecordTimes[TOTAL_ZONE_TRACKS][MAX_STYLES];
char			g_cReplayRecordNames[TOTAL_ZONE_TRACKS][MAX_STYLES][MAX_NAME_LENGTH];

ConVar		g_cvMultireplayBots;
int			g_nMultireplayBots;
int			g_nExpectedMultireplayBots;
int			g_iMultireplayBotIndexes[MAX_MULTIREPLAY_BOTS];
int			g_MultireplayCurrentlyReplayingTrack[MAX_MULTIREPLAY_BOTS];
int			g_MultireplayCurrentlyReplayingStyle[MAX_MULTIREPLAY_BOTS];

int			g_nStyleBots;
int			g_nExpectedStyleBots;
int			g_iStyleBotIndexes[MAX_STYLE_BOTS];
int			g_StyleBotReplayingTrack[MAX_STYLE_BOTS];
int			g_StyleBotReplayingStyle[MAX_STYLE_BOTS];
bool			g_bStyleBotLoaded[TOTAL_ZONE_TRACKS][MAX_STYLES];

ConVar		g_cvStartDelay;
ConVar		g_cvEndDelay;

int			g_iBotType[MAXPLAYERS + 1];
int			g_iBotId[MAXPLAYERS + 1];

int			g_iCurrentFrame[MAXPLAYERS + 1];

ArrayList		g_aPlayerFrameData[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "Slidy's Timer - Replays component",
	author = "SlidyBat",
	description = "Replays component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public void OnPluginStart()
{
	bot_quota = FindConVar( "bot_quota" );
	bot_quota.AddChangeHook( OnBotQuotaChanged );
	
	RegConsoleCmd( "sm_replay", Command_Replay );
	
	g_cvMultireplayBots = CreateConVar( "sm_timer_multireplay_bots", "2", "Total amount of MultiReplay bots", _, true, 0.0, true, float( MAX_MULTIREPLAY_BOTS ) );
	g_cvMultireplayBots.AddChangeHook( OnMultireplayBotsChanged );
	g_nExpectedMultireplayBots = g_cvMultireplayBots.IntValue;
	
	g_cvStartDelay = CreateConVar( "sm_timer_replay_start_delay", "3.0", "Delay at beginning of replays before bots start", _, true, 0.0, false );
	g_cvEndDelay = CreateConVar( "sm_timer_replay_end_delay", "3.0", "Delay at end of replays before bots restart", _, true, 0.0, false );
	AutoExecConfig( true, "timer-replays", "Timer" );
	
	g_fFrameTime = GetTickInterval();
	g_fTickRate = 1.0 / g_fFrameTime;
	
	g_aReplayQueue = new ArrayList( 3 );
	
	char path[PLATFORM_MAX_PATH];

	BuildPath( Path_SM, path, sizeof( path ), "data/Timer" );

	if( !DirExists( path ) )
	{
		CreateDirectory( path, sizeof( path ) );
	}

	for( int i = 0; i < 2; i++ )
	{
		BuildPath( Path_SM, path, sizeof( path ), "data/Timer/%s", g_cReplayFolders[i] );

		if( !DirExists( path ) )
		{
			CreateDirectory( path, sizeof( path ) );
		}

		for( int x = 0; x < TOTAL_ZONE_TRACKS; x++ )
		{
			BuildPath( Path_SM, path, 512, "data/Timer/%s/%i", g_cReplayFolders[i], x );

			if( !DirExists( path ) )
			{
				CreateDirectory( path, sizeof( path ) );
			}

			for( int y = 0; y < MAX_STYLES; y++ )
			{
				BuildPath( Path_SM, path, sizeof( path ), "data/Timer/%s/%i/%i", g_cReplayFolders[i], x, y );

				if( !DirExists( path ) )
				{
					CreateDirectory( path, sizeof( path ) );
				}
			}
		}
	}
}

public void OnAllPluginsLoaded()
{
	if( g_hDatabase == null )
	{
		Timer_OnDatabaseLoaded();
	}
}

public void OnMapStart()
{
	GetCurrentMap( g_cCurrentMap, sizeof( g_cCurrentMap ) );
}

public void OnMapEnd()
{
	g_aReplayQueue.Clear();
	
	int totalstyles = Timer_GetStyleCount();
	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < totalstyles; j++ )
		{
			delete g_aReplayFrames[i][j];
			g_cReplayRecordNames[i][j] = "";
			g_fReplayRecordTimes[i][j] = 0.0;
			
			g_bStyleBotLoaded[i][j] = false;
		}
	}
	
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientConnected( i ) && IsFakeClient( i ) )
		{
			KickClient( i );
		}
	}
}

public void OnClientPutInServer( int client )
{
	if( !IsFakeClient( client ) )
	{
		if( g_aPlayerFrameData[client] != null )
		{
			delete g_aPlayerFrameData[client];
		}
		g_aPlayerFrameData[client] = new ArrayList( FRAME_DATA_SIZE );
	}
	else
	{
		if( g_nMultireplayBots < g_nExpectedMultireplayBots )
		{
			int botid = -1;
		
			for( int i = 0; i < g_nExpectedMultireplayBots; i++ )
			{
				if( g_iMultireplayBotIndexes[i] == 0 )
				{
					g_iMultireplayBotIndexes[i] = client;
					g_nMultireplayBots++;
					botid = i;
					break;
				}
			}
			
			if( botid > -1 )
			{
				InitializeBot( client, ReplayBot_Multireplay, botid );
			}
		}
		else if( g_nStyleBots < g_nExpectedStyleBots )
		{
			int botid = -1;
		
			for( int i = 0; i < g_nExpectedStyleBots; i++ )
			{
				if( g_iStyleBotIndexes[i] == 0 )
				{
					g_iStyleBotIndexes[i] = client;
					g_nStyleBots++;
					botid = i;
					break;
				}
			}
			
			if( botid > -1 )
			{
				InitializeBot( client, ReplayBot_Style, botid );
			}
		}
		else
		{
			KickClient( client );
		}
	}
}

public void OnClientDisconnect( int client )
{
	for( int i = 0; i < g_nExpectedStyleBots; i++ )
	{
		if( client == g_iMultireplayBotIndexes[i] )
		{
			g_iMultireplayBotIndexes[i] = 0;
			g_nMultireplayBots--;
			return;
		}
	}
	for( int i = 0; i < g_nExpectedStyleBots; i++ )
	{
		if( client == g_iStyleBotIndexes[i] )
		{
			g_iStyleBotIndexes[i] = 0;
			g_nStyleBots--;
			return;
		}
	}
}

public Action Timer_OnTimerStart( int client )
{
	g_aPlayerFrameData[client].Clear();
	g_iCurrentFrame[client] = 0;
}

public void Timer_OnFinishPost( int client, int track, int style, float time, float pbtime, float wrtime )
{
	if( g_fReplayRecordTimes[track][style] == 0.0 || time < g_fReplayRecordTimes[track][style] )
	{
		SaveReplay( client, time, track, style );
	}
}

public void Timer_OnStylesLoaded( int totalstyles )
{
	// load specific bots
	for( int i = 0; i < TOTAL_ZONE_TRACKS; i++ )
	{
		for( int j = 0; j < totalstyles; j++ )
		{
			LoadReplay( i, j );
		}
	}
	
	CreateMultireplayBots();
	CreateStyleBots();
	
	bot_quota.IntValue = g_nExpectedMultireplayBots + g_nExpectedStyleBots;
}

void CreateMultireplayBots()
{
	for( int i = 0; i < g_nExpectedMultireplayBots; i++ )
	{
		ServerCommand( "bot_add_ct" );
	}
}

void CreateStyleBots()
{
	g_nExpectedStyleBots = 0;
	
	int totalstyles = Timer_GetStyleCount();
	for( int i = 0; i < totalstyles; i++ )
	{
		any settings[styleSettings];
		Timer_GetStyleSettings( i, settings );
		
		if( settings[MainReplayBot] || settings[BonusReplayBot] )
		{
			g_nExpectedStyleBots++;
		}
	}
	
	for( int i = 0; i < g_nExpectedStyleBots; i++ )
	{
		ServerCommand( "bot_add_ct" );
	}
}

void InitializeBot( int client, int replaytype, int botid )
{
	char name[MAX_NAME_LENGTH];

	if( replaytype == ReplayBot_Multireplay )
	{
		g_iMultireplayBotIndexes[botid] = client;
		g_MultireplayCurrentlyReplayingTrack[botid] = ZoneTrack_None;
		g_MultireplayCurrentlyReplayingStyle[botid] = -1;
		
		if( botid == 0 )
		{
			Format( name, sizeof( name ), "MultiReplay (!replay)" );
		}
		else
		{
			Format( name, sizeof( name ), "MultiReplay %i (!replay)", botid + 1 );
		}
	}
	else if( replaytype == ReplayBot_Style )
	{
		g_iStyleBotIndexes[botid] = client;
	
		int totalstyles = Timer_GetStyleCount();
		for( int track = 0; track < TOTAL_ZONE_TRACKS; track++ )
		{
			bool assigned = false;
		
			for( int style; style < totalstyles; style++ )
			{
				any settings[styleSettings];
				Timer_GetStyleSettings( style, settings );
			
				int tracksetting = (track == ZoneTrack_Main) ? MainReplayBot : BonusReplayBot;
				if( settings[tracksetting] && !g_bStyleBotLoaded[track][style] )
				{
					g_StyleBotReplayingTrack[botid] = track;
					g_StyleBotReplayingStyle[botid] = style;
					
					char sTrack[32];
					Timer_GetZoneTrackName( track, sTrack, sizeof(sTrack) );
					char sStyle[16];
					strcopy( sStyle, sizeof(sStyle), settings[StylePrefix] );
					
					if( g_fReplayRecordTimes[track][style] == 0.0 )
					{
						Format( name, sizeof( name ), "[%s %s] N/A", sTrack, sStyle );
						delete g_aPlayerFrameData[client];
					}
					else
					{
						char sTime[32];
						Timer_FormatTime( g_fReplayRecordTimes[track][style], sTime, sizeof( sTime ) );
						Format( name, sizeof( name ), "[%s %s] %s (%s)", sTrack, sStyle, g_cReplayRecordNames[track][style], sTime );
						
						delete g_aPlayerFrameData[client];
						g_aPlayerFrameData[client] = g_aReplayFrames[track][style].Clone();
					}
					
					g_bStyleBotLoaded[track][style] = true;
					assigned = true;
					break;
				}
			}
			
			if( assigned )
			{
				break;
			}
		}
	}
	
	g_iBotId[client] = botid;
	g_iBotType[client] = replaytype;
	
	SetClientName( client, name );
	ChangeClientTeam( client, CS_TEAM_CT );
	Timer_TeleportClientToZone( client, Zone_Start, ZoneTrack_Main );
}

public Action OnPlayerRunCmd( int client, int& buttons, int& impulse, float vel[3], float angles[3] )
{
	if( !IsClientInGame( client ) || !IsPlayerAlive( client ) )
	{
		return;
	}
	
	any frameData[FrameData];
	float pos[3];
	
	if( !IsFakeClient( client ) )
	{
		if( Timer_IsTimerRunning( client ) )
		{
			// its a player, save frame data
			GetClientAbsOrigin( client, pos );
			
			frameData[FD_Pos][0] = pos[0];
			frameData[FD_Pos][1] = pos[1];
			frameData[FD_Pos][2] = pos[2];
			frameData[FD_Angles][0] = angles[0];
			frameData[FD_Angles][1] = angles[1];
			frameData[FD_Buttons] = buttons;
			
			g_aPlayerFrameData[client].PushArray( frameData[0] );
			g_iCurrentFrame[client]++;
			
			//PrintToServer( "Frame %i saved", g_iCurrentFrame[client] );
		}
	}
	else
	{
		vel[0] = 0.0;
		vel[1] = 0.0;
		vel[2] = 0.0;
		buttons = 0;
	
		if( g_iBotType[client] != ReplayBot_None && g_aPlayerFrameData[client] != null && g_aPlayerFrameData[client].Length )
		{
			// its a replay bot, move it
			if( g_iCurrentFrame[client] == 0 )
			{
				g_aPlayerFrameData[client].GetArray( g_iCurrentFrame[client], frameData[0] );
				
				pos[0] = frameData[FD_Pos][0];
				pos[1] = frameData[FD_Pos][1];
				pos[2] = frameData[FD_Pos][2];
				
				angles[0] = frameData[FD_Angles][0];
				angles[1] = frameData[FD_Angles][1];
				
				SetEntityMoveType( client, MOVETYPE_NONE );
				TeleportEntity( client, pos, angles, NULL_VECTOR );
				
				CreateTimer( g_cvStartDelay.FloatValue, Timer_StartBotDelayed, GetClientUserId( client ), TIMER_FLAG_NO_MAPCHANGE );
			}
			else if( g_iCurrentFrame[client] < g_aPlayerFrameData[client].Length )
			{
				SetEntityMoveType( client, MOVETYPE_WALK );
			
				g_aPlayerFrameData[client].GetArray( g_iCurrentFrame[client], frameData[0] );
				
				static float tmp[3];
				GetClientAbsOrigin( client, tmp );
				pos[0] = frameData[FD_Pos][0];
				pos[1] = frameData[FD_Pos][1];
				pos[2] = frameData[FD_Pos][2];
				
				MakeVectorFromPoints( tmp, pos, tmp );
				ScaleVector( tmp, g_fTickRate );
				
				angles[0] = frameData[FD_Angles][0];
				angles[1] = frameData[FD_Angles][1];
				
				buttons = frameData[FD_Buttons];
				
				TeleportEntity( client, NULL_VECTOR, angles, tmp );
				
				g_iCurrentFrame[client]++;
			}
			else
			{
				SetEntityMoveType( client, MOVETYPE_NONE );
				CreateTimer( g_cvEndDelay.FloatValue, Timer_EndBotDelayed, GetClientUserId( client ), TIMER_FLAG_NO_MAPCHANGE );
			}
		}
	}
}

void LoadReplay( int track, int style )
{
	char path[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, path, sizeof( path ), "data/Timer/%s/%i/%i/%s.rec", g_cReplayFolders[0], track, style, g_cCurrentMap );
	
	if( FileExists( path ) )
	{
		File file = OpenFile( path, "rb" );
		static any header[ReplayHeader];
		
		if( !file.Read( header[0], sizeof( header ), 4 ) )
		{
			return;
		}
		
		if( header[HD_MagicNumber] != MAGIC_NUMBER )
		{
			LogError( "%s does not contain correct header" );
			return;
		}
		if( header[HD_TickRate] != RoundFloat( 1.0 / g_fFrameTime ) )
		{
			LogError( "%s has a different tickrate than server (File: %i, Server: %i)", path, header[HD_TickRate], RoundFloat( 1.0 / g_fFrameTime ) );
			return;
		}
		
		g_fReplayRecordTimes[track][style] = header[HD_Time];
		
		char query[128];
		Format( query, sizeof( query ), "SELECT lastname FROM `t_players` WHERE steamaccountid = '%i'", header[HD_SteamAccountId] );
		DataPack pack = new DataPack();
		pack.WriteCell( track );
		pack.WriteCell( style );
		g_hDatabase.Query( GetName_Callback, query, pack, DBPrio_High );

		delete g_aReplayFrames[track][style];
		g_aReplayFrames[track][style] = new ArrayList( FRAME_DATA_SIZE );
		g_aReplayFrames[track][style].Resize( header[HD_Size] );

		any frameData[FrameData];
		for( int i = 0; i < header[HD_Size]; i++ )
		{
			if( file.Read( frameData[0], sizeof( frameData ), 4 ) >= 0 )
			{
				g_aReplayFrames[track][style].SetArray( i, frameData[0] );
			}
		}

		file.Close();
	}
}

void SaveReplay( int client, float time, int track, int style )
{
	if( !GetClientName( client, g_cReplayRecordNames[track][style], sizeof( g_cReplayRecordNames[][] ) ) )
	{
		LogError( "Failed to get client name when saving replay" );
		return;
	}
	
	g_fReplayRecordTimes[track][style] = time;
	
	delete g_aReplayFrames[track][style];
	g_aReplayFrames[track][style] = g_aPlayerFrameData[client].Clone();
	
	any header[ReplayHeader];
	header[HD_MagicNumber] = MAGIC_NUMBER;
	header[HD_ReplayVersion] = 1;
	header[HD_Size] = g_aReplayFrames[track][style].Length;
	header[HD_Time] = time;
	header[HD_SteamAccountId] = GetSteamAccountID( client );
	header[HD_TickRate] = RoundFloat( 1.0 / g_fFrameTime );
	header[HD_Timestamp] = GetTime();
	
	char path[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, path, sizeof( path ), "data/Timer/%s/%i/%i/%s.rec", g_cReplayFolders[0], track, style, g_cCurrentMap );
	
	if( FileExists( path ) )
	{
		int temp = -1;
		char copypath[PLATFORM_MAX_PATH];

		do
		{
			temp++;
			BuildPath( Path_SM, copypath, sizeof( copypath ), "data/Timer/%s/%i/%i/%s-%i.rec", g_cReplayFolders[1], track, style, g_cCurrentMap, temp );
		} while( FileExists( copypath ) );

		File_Copy( path, copypath );
		DeleteFile( path );
	}
	
	File file = OpenFile( path, "wb" );
	
	file.Write( header[0], sizeof( header ), 4 );
	
	any frameData[FrameData];
	for( int i = 0; i < header[HD_Size]; i++ )
	{
		g_aReplayFrames[track][style].GetArray( i, frameData[0] );
		file.Write( frameData[0], sizeof( frameData ), 4 );
	}
	
	file.Close();
	
	for( int i = 0; i < g_nStyleBots; i++ )
	{
		if( g_StyleBotReplayingStyle[i] == style && g_StyleBotReplayingTrack[i] == track )
		{
			int idx = g_iStyleBotIndexes[i];
			if( !IsPlayerAlive( idx ) )
			{
				CS_RespawnPlayer( idx );
			}
			
			// reset frames
			delete g_aPlayerFrameData[idx];
			g_aPlayerFrameData[idx] = g_aReplayFrames[track][style].Clone();
			g_iCurrentFrame[idx] = 0;
			
			char sTrack[16];
			Timer_GetZoneTrackName( track, sTrack, sizeof( sTrack ) );
			char sStyle[16];
			Timer_GetStylePrefix( style, sStyle, sizeof( sStyle ) );
			char sTime[16];
			Timer_FormatTime( g_fReplayRecordTimes[track][style], sTime, sizeof( sTime ) );
			
			char name[MAX_NAME_LENGTH + 32];
			Format( name, sizeof( name ), "[%s %s] %s (%s)", sTrack, sStyle, g_cReplayRecordNames[track][style], sTime );
			SetClientName( idx, name );
			
			break;
		}
	}
}

void StartReplay( int botid, int track, int style )
{
	int idx = g_iMultireplayBotIndexes[botid];
	
	g_MultireplayCurrentlyReplayingStyle[botid] = style;
	g_MultireplayCurrentlyReplayingTrack[botid] = track;
	
	delete g_aPlayerFrameData[idx];
	g_aPlayerFrameData[idx] = g_aReplayFrames[track][style].Clone();
	
	g_iCurrentFrame[idx] = 0;
	
	// TODO: can make some functions for replay bot names to make this bit more organised
	char sTrack[16];
	Timer_GetZoneTrackName( track, sTrack, sizeof( sTrack ) );
	char sStyle[16];
	Timer_GetStylePrefix( style, sStyle, sizeof( sStyle ) );
	char sTime[16];
	Timer_FormatTime( g_fReplayRecordTimes[track][style], sTime, sizeof( sTime ) );
	char name[MAX_NAME_LENGTH + 32];
	Format( name, sizeof( name ), "[%s %s] %s (%s)", sTrack, sStyle, g_cReplayRecordNames[track][style], sTime );
	SetClientName( idx, name );
}

void QueueReplay( int client, int track, int style )
{
	for( int i = 0; i < g_nExpectedMultireplayBots; i++ )
	{
		if( g_MultireplayCurrentlyReplayingStyle[i] == -1 &&
			g_MultireplayCurrentlyReplayingTrack[i] == ZoneTrack_None )
		{
			StartReplay( i, track, style );
			return;
		}
	}
	
	int index = g_aReplayQueue.Length;
	g_aReplayQueue.Push( 0 );
	g_aReplayQueue.Set( index, client, 0 );
	g_aReplayQueue.Set( index, track, 1 );
	g_aReplayQueue.Set( index, style, 2 );
	
	PrintToChat( client, "[Timer] Your replay has been queued" );
}

void StopReplayBot( int botidx )
{
	int botid = g_iBotId[botidx];

	g_MultireplayCurrentlyReplayingStyle[botid] = -1;
	g_MultireplayCurrentlyReplayingTrack[botid] = ZoneTrack_None;
	delete g_aPlayerFrameData[botidx];
	g_aPlayerFrameData[botidx] = new ArrayList( FRAME_DATA_SIZE );
	
	char name[MAX_NAME_LENGTH];
	if( botid == 0 )
	{
		Format( name, sizeof( name ), "MultiReplay (!replay)" );
	}
	else
	{
		Format( name, sizeof( name ), "MultiReplay %i (!replay)", botid + 1 );
	}
	SetClientName( botidx, name );
	
	Timer_TeleportClientToZone( botidx, Zone_Start, ZoneTrack_Main );
}

void EndReplayBot( int botidx )
{
	if( g_aReplayQueue.Length )
	{
		int client = g_aReplayQueue.Get( 0, 0 );
		int track = g_aReplayQueue.Get( 0, 1 );
		int style= g_aReplayQueue.Get( 0, 2 );
		g_aReplayQueue.Erase( 0 );
		
		StartReplay( g_iBotId[botidx], track, style );
		PrintToChat( client, "[Timer] Your replay has started" );
	}
	else
	{
		StopReplayBot( botidx );
	}
}

void OpenReplayMenu( int client, int track, int style )
{
	Menu menu = new Menu( ReplayMenu_Handler );
	menu.SetTitle( "Replay Menu\n \n" );
	
	char buffer[64], sInfo[8];
	
	Timer_GetZoneTrackName( track, buffer, sizeof( buffer ) );
	Format( buffer, sizeof( buffer ), "Track: %s\n\n", buffer );
	IntToString( track, sInfo, sizeof( sInfo ) );
	menu.AddItem( sInfo, buffer );
	
	IntToString( style, sInfo, sizeof( sInfo ) );
	Timer_GetStyleName( style, buffer, sizeof( buffer ) );
	Format( buffer, sizeof( buffer ), "Style Up\n  > Current Style: %s", buffer );
	menu.AddItem( sInfo, buffer );
	menu.AddItem( sInfo, "Style Down\n \n" );
	
	menu.AddItem( "play", "Play Replay", ( g_aReplayFrames[track][style] == null || !g_aReplayFrames[track][style].Length ) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT );
	
	menu.Display( client, 20 );
}

public int ReplayMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char sInfo[8];
		menu.GetItem( 0, sInfo, sizeof( sInfo ) );
		int track = StringToInt( sInfo );
		menu.GetItem( 1, sInfo, sizeof( sInfo ) );
		int style = StringToInt( sInfo );
		
		int totalstyles = Timer_GetStyleCount();
		
		switch( param2 )
		{
			case 0:
			{
				track++;
				if( track == TOTAL_ZONE_TRACKS )
				{
					track = ZoneTrack_Main;
				}
				
				OpenReplayMenu( param1, track, style );
			}
			case 1:
			{
				style -= 1;
				if( style < 0 )
				{
					style = totalstyles - 1;
				}
				
				OpenReplayMenu( param1, track, style );
			}
			case 2:
			{
				style += 1;
				if( style >= totalstyles )
				{
					style = 0;
				}
				
				OpenReplayMenu( param1, track, style );
			}
			case 3:
			{
				QueueReplay( param1, track, style );
			}
		}
	}
}

public void Timer_OnDatabaseLoaded()
{
	g_hDatabase = Timer_GetDatabase();
	SetSQLInfo();
}

public Action CheckForSQLInfo( Handle timer )
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
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public void GetName_Callback( Database db, DBResultSet results, const char[] error, DataPack pack )
{
	if( results == null )
	{
		LogError( "[SQL ERROR] (GetName_Callback) - %s", error );
		return;
	}
	
	pack.Reset();
	int track = pack.ReadCell();
	int style = pack.ReadCell();
	delete pack;
	
	if( results.FetchRow() )
	{
		results.FetchString( 0, g_cReplayRecordNames[track][style], MAX_NAME_LENGTH );
	}
}

public Action Command_Replay( int client, int args )
{
	OpenReplayMenu( client, ZoneTrack_Main, 0 );
	
	return Plugin_Handled;
}

public Action Timer_StartBotDelayed( Handle timer, int userid )
{
	int client = GetClientOfUserId( userid );
	g_iCurrentFrame[client]++;
}

public Action Timer_EndBotDelayed( Handle timer, int userid )
{
	int client = GetClientOfUserId( userid );
	if( g_iBotType[client] == ReplayBot_Style )
	{
		g_iCurrentFrame[client] = 0;
	}
	else
	{
		EndReplayBot( client );
	}
}

public void OnMultireplayBotsChanged( ConVar convar, const char[] oldValue, const char[] newValue )
{
	if( g_nExpectedMultireplayBots = g_cvMultireplayBots.IntValue; )
	{
		g_nExpectedMultireplayBots = g_cvMultireplayBots.IntValue;
	}
}

public void OnBotQuotaChanged( ConVar convar, const char[] oldValue, const char[] newValue )
{
	if( bot_quota.IntValue != g_nExpectedMultireplayBots + g_nExpectedStyleBots )
	{
		bot_quota.IntValue = g_nExpectedMultireplayBots + g_nExpectedStyleBots
	}
}