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

char g_cSoundTypePath[TOTAL_SOUND_TYPES][] = 
{
	"timer-finishsounds",
	"timer-pbsounds",
	"timer-wrsounds",
};

int	g_nSounds[TOTAL_SOUND_TYPES];
char g_cSounds[TOTAL_SOUND_TYPES][MAX_SOUNDS][PLATFORM_MAX_PATH];

public void OnMapStart()
{
	PrecacheSounds();
}

public void Timer_OnFinishPost( int client, int track, int style, float time, float pbtime, float wrtime )
{
	if( wrtime == 0.0 || time < wrtime )
	{
		Timer_DebugPrint( "Timer_OnFinishPost: Exiting" );
		return; // will be handled by OnWRBeaten forward
	}

	if( pbtime == 0.0 || time < pbtime )
	{
		// pb sound
		PlayRandomSound( SoundType_PBSound, client );		
		Timer_DebugPrint( "Timer_OnFinishPost: Playing PB sound" );
	}
	else
	{
		// normal finish sound
		PlayRandomSound( SoundType_FinishSound, client );
		Timer_DebugPrint( "Timer_OnFinishPost: Playing finish sound" );
	}
}

public void Timer_OnWRBeaten( int client, int track, int style, float time, float oldwrtime )
{
	// play wr sound
	PlayRandomSound( SoundType_WRSound );
	Timer_DebugPrint( "Timer_OnFinishPost: Playing WR sound" );
}

void PrecacheSounds()
{
	for( int i = 0; i < TOTAL_SOUND_TYPES; i++ )
	{
		g_nSounds[i] = 0;

		char path[PLATFORM_MAX_PATH];
		BuildPath( Path_SM, path, sizeof(path), "configs/Timer/%s.txt", g_cSoundTypePath[i] );
		
		File file = OpenFile( path, "r" );

		char line[PLATFORM_MAX_PATH];
		while( file.ReadLine( line, sizeof(line) ) && g_nSounds[i] < MAX_SOUNDS )
		{
			Format( g_cSounds[i][g_nSounds[i]], sizeof(g_cSounds[][]), "*%s", line );
			g_nSounds[i]++;

			FakePrecacheSound( line );
			
			Format( line, sizeof(line), "sound/%s", line );
			AddFileToDownloadsTable( line );
		}

		file.Close();
	}
}

void PlayRandomSound( int soundtype, int client = 0 ) // client=0 means play to all
{
	if( g_nSounds[soundtype] == 0 )
	{
		Timer_DebugPrint( "PlayRandomSound: No sounds loaded, exiting" );
		return;
	}

	int rand = GetRandomInt( 0, g_nSounds[soundtype] - 1 );

	if( client == 0 )
	{
		EmitSoundToAll( g_cSounds[soundtype][rand] );
	}
	else
	{
		EmitSoundToClient( client, g_cSounds[soundtype][rand] );
	}
}