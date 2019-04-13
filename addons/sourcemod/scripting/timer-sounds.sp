#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <slidy-timer>

#define MAX_SOUNDS 10 // max sounds per sound group/type

enum
{
	SoundType_FinishSound,
	SoundType_PBSound,
	SoundType_WRSound,
	TOTAL_SOUND_TYPES
}

StringMap g_smSoundTypes;
int	g_nSounds[TOTAL_SOUND_TYPES];
char g_cSounds[TOTAL_SOUND_TYPES][MAX_SOUNDS][PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = "Slidy's Timer - Sounds component",
	author = "SlidyBat",
	description = "Sounds component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public void OnPluginStart()
{
	g_smSoundTypes = new StringMap();
	
	g_smSoundTypes.SetValue( "#Finish sounds", SoundType_FinishSound );
	g_smSoundTypes.SetValue( "#PB sounds", SoundType_PBSound );
	g_smSoundTypes.SetValue( "#WR sounds", SoundType_WRSound );
}

public void OnMapStart()
{
	PrecacheSounds();
}

public void Timer_OnTimerFinishPost( int client, int track, int style, float time )
{
	float wrtime = Timer_GetWRTime( track, style );
	if( wrtime == 0.0 || time < wrtime )
	{
		Timer_DebugPrint( "Timer_OnTimerFinishPost: Exiting" );
		return; // will be handled by OnWRBeaten forward
	}

	float pbtime = Timer_GetClientPBTime( client, track, style );
	if( pbtime == 0.0 || time < pbtime )
	{
		// pb sound
		PlayRandomSound( SoundType_PBSound, client );		
		Timer_DebugPrint( "Timer_OnTimerFinishPost: Playing PB sound" );
	}
	else
	{
		// normal finish sound
		PlayRandomSound( SoundType_FinishSound, client );
		Timer_DebugPrint( "Timer_OnTimerFinishPost: Playing finish sound" );
	}
}

public void Timer_OnWRBeaten( int client, int track, int style, float time, float oldwrtime )
{
	// play wr sound
	PlayRandomSound( SoundType_WRSound );
	Timer_DebugPrint( "Timer_OnWRBeaten: Playing WR sound" );
}

void PrecacheSounds()
{
	int soundtype = -1;

	for( int i = 0; i < TOTAL_SOUND_TYPES; i++ )
	{
		g_nSounds[i] = 0;
	}
	
	char path[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, path, sizeof(path), "configs/timer/timer-sounds.txt" );
	
	File file = OpenFile( path, "r" );
	if( !file )
	{
		LogError( "Failed to open '%s'. Make sure it exists." );
	}

	char line[PLATFORM_MAX_PATH];
	while( file.ReadLine( line, sizeof(line) ) )
	{
		TrimString( line );
		if( line[0] == '\0' || ( line[0] == '/' && line[1] == '/' ) ) // skip empty lines and comments
		{
			continue;
		}
		
		int temp;
		if( g_smSoundTypes.GetValue( line, temp ) )
		{
			soundtype = temp;
			continue; // this line isn't a sound!
		}
		
		if( g_nSounds[soundtype] >= MAX_SOUNDS )
		{
			LogError( "Too many sounds being loaded, increase max sounds limit" );
			continue;
		}
		
		Format( g_cSounds[soundtype][g_nSounds[soundtype]], sizeof(g_cSounds[][]), "*%s", line );
		
		g_nSounds[soundtype]++;

		FakePrecacheSound( line );
		
		Format( line, sizeof(line), "sound/%s", line );
		AddFileToDownloadsTable( line );
	}

	file.Close();
}

void PlayRandomSound( int soundtype, int client = 0 ) // client=0 means play to all
{
	if( g_nSounds[soundtype] == 0 )
	{
		Timer_DebugPrint( "PlayRandomSound: No sounds loaded, exiting" );
		return;
	}

	int rand = GetRandomInt( 0, g_nSounds[soundtype] - 1 );
	
	Timer_DebugPrint( "PlayRandomSound: Playing %s", g_cSounds[soundtype][rand] );
	
	if( client == 0 )
	{
		EmitSoundToAll( g_cSounds[soundtype][rand] );
	}
	else
	{
		EmitSoundToClient( client, g_cSounds[soundtype][rand] );
	}
}