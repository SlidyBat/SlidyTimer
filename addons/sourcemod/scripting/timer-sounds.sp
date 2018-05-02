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

char[TOTAL_SOUND_TYPES][] g_cSoundTypePath = 
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
		return; // will be handled by OnWRBeaten forward
	}

	if( pbtime == 0.0 || time < pbtime )
	{
		// pb sound
		PlayRandomSound( SoundType_PBSound, client );		
	}
	else
	{
		// normal finish sound
		PlayRandomSound( SoundType_FinishSound, client );
	}
}

public void Timer_OnWRBeaten( int client, int track, int style, float time, float oldwrtime )
{
	// play wr sound
	PlayRandomSound( SoundType_WRSound );
}

void PrecacheSounds()
{
	for( int i = 0; i < TOTAL_SOUND_TYPES; i++ )
	{
		g_nSounds[i] = 0;

		char path[PLATFORM_MAX_PATH];
		BuildPath( Path_SM, path, sizeof(path), "configs/Timer/%s.txt", g_cSoundTypePath[i] )
		
		File file = OpenFile( path );

		char line[PLATFORM_MAX_PATH];
		while( file.ReadLine( line, sizeof(line) ) && g_nSounds < MAX_SOUNDS )
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