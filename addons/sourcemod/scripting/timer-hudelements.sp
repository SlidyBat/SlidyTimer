public void GetSpeedString( int client, char[] output, int maxlen )
{
	int speed = RoundFloat( GetClientSpeed( client ) );
	FormatEx( output, maxlen, "%03d%s", speed, (speed < 100) );
}

public void GetJumpsString( int client, char[] output, int maxlen )
{
	int jumps = Timer_GetClientCurrentJumps( client );
	IntToString( jumps, output, maxlen );
}

public void GetStrafesString( int client, char[] output, int maxlen )
{
	int strafes = Timer_GetClientCurrentStrafes( client );
	IntToString( strafes, output, maxlen );
}

public void GetSyncString( int client, char[] output, int maxlen )
{
	float sync = Timer_GetClientCurrentSync( client );
	if( sync < 100.0 )
	{
		FormatEx( output, maxlen, "%.2f\t", sync );
	}
	else
	{
		FormatEx( output, maxlen, "%.2f", sync );
	}
}

public void GetStrafeTimeString( int client, char[] output, int maxlen )
{
	float strafetime = Timer_GetClientCurrentStrafeTime( client );
	if( strafetime < 10.0 )
	{
		FormatEx( output, maxlen, "%.2f\t", strafetime );
	}
	else
	{
		FormatEx( output, maxlen, "%.2f", strafetime );
	}
}

public void GetWRTimeString( int client, char[] output, int maxlen )
{
	float wrtime = Timer_GetWRTime( Timer_GetClientZoneTrack( client ), Timer_GetClientStyle( client ) );
	
	if( wrtime == 0.0 )
	{
		FormatEx( output, maxlen, "N/A\t" );
	}
	else
	{
		Timer_FormatTime( wrtime, output, maxlen );
	}
}

public void GetPBTimeString( int client, char[] output, int maxlen )
{
	float pbtime = Timer_GetClientPBTime( client, Timer_GetClientZoneTrack( client ), Timer_GetClientStyle( client ) );
	if( pbtime == 0.0 )
	{
		FormatEx( output, maxlen, "N/A\t" );
	}
	else
	{
		Timer_FormatTime( pbtime, output, maxlen );
	}
}

public void GetStyleString( int client, char[] output, int maxlen )
{
	Timer_GetStyleName( Timer_GetClientStyle( client ), output, maxlen );
}

public void GetRainbowString( int client, char[] output, int maxlen )
{
	strcopy( output, maxlen, g_cRainbowColour );
}

public void GetTimeString( int client, char[] output, int maxlen )
{
	if( !IsFakeClient( client ) )
	{
		TimerStatus ts = Timer_GetClientTimerStatus( client );
		
		switch( ts )
		{
			case TimerStatus_Stopped:
			{
				FormatEx( output, maxlen, "<font color='#DB1A40'>Stopped</font>\t" );
			}
			case TimerStatus_Paused:
			{
				FormatEx( output, maxlen, "<font color='#333399'>Paused</font>\t" );
			}
			case TimerStatus_Running:
			{
				float time = Timer_GetClientCurrentTime( client );
				Timer_FormatTime( time, output, maxlen );
				
				int track = Timer_GetClientZoneTrack( client );
				int style = Timer_GetClientStyle( client );
				
				char sTimeColour[8];
				GetTimeColour( sTimeColour, time, Timer_GetClientPBTime( client, track, style ), Timer_GetWRTime( track, style ) );
				Format( output, maxlen, "<font color='%s'>%s\t</font>", sTimeColour, output );
			}
		}
	}
	else
	{
		int frames = Timer_GetReplayBotCurrentFrame( client );
		if( frames != -1 )
		{
			float time = frames * g_fTickInterval;
			Timer_FormatTime( time, output, maxlen );
		}
		else
		{
			Format( output, maxlen, "N/A" );
		}
		
		Format( output, maxlen, "%s\t", output );
	}
}

public void GetZoneTrackString( int client, char[] output, int maxlen )
{
	Timer_GetZoneTrackName( Timer_GetClientZoneTrack( client ), output, maxlen );
}

public void GetZoneTypeString( int client, char[] output, int maxlen )
{
	Timer_GetZoneTypeName( Timer_GetClientZoneType( client ), output, maxlen );
}

public void GetReplayBotNameString( int client, char[] output, int maxlen )
{
	Timer_GetReplayBotPlayerName( client, output, maxlen );
}