public void GetSpeedString( int client, char[] output, int maxlen )
{
	int speed = RoundFloat( GetClientSpeed( client ) );
	IntToString( speed, output, maxlen );
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
	FormatEx( output, maxlen, "%.2f", sync );
}

public void GetStrafeTimeString( int client, char[] output, int maxlen )
{
	float strafetime = Timer_GetClientCurrentStrafeTime( client );
	FormatEx( output, maxlen, "%.2f", strafetime );
}

public void GetWRTimeString( int client, char[] output, int maxlen )
{
	float wrtime = Timer_GetWRTime( Timer_GetClientZoneTrack( client ), Timer_GetClientStyle( client ) );
	FormatEx( output, maxlen, "%.2f", wrtime );
}

public void GetPBTimeString( int client, char[] output, int maxlen )
{
	float pbtime = Timer_GetClientPBTime( client, Timer_GetClientZoneTrack( client ), Timer_GetClientStyle( client ) );
	FormatEx( output, maxlen, "%.2f", pbtime );
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
	int type = Timer_GetClientZoneType( client );
	
	if( type == Zone_Start )
	{
		Timer_GetZoneTrackName( Timer_GetClientZoneTrack( client ), output, maxlen );
		FormatEx( output, maxlen, "%s Start Zone", output );
	}
	else
	{
		TimerStatus ts = Timer_GetClientTimerStatus( client );
		
		switch( ts )
		{
			case TimerStatus_Stopped:
			{
				FormatEx( output, maxlen, "Time: <font color='#DB1A40'>Stopped</font>\t" );
			}
			case TimerStatus_Paused:
			{
				FormatEx( output, maxlen, "Time: <font color='#333399'>Paused</font>\t" );
			}
			case TimerStatus_Running:
			{
				float time = Timer_GetClientCurrentTime( client );
				Timer_FormatTime( time, output, maxlen );
				
				int track = Timer_GetClientZoneTrack( client );
				int style = Timer_GetClientStyle( client );
				
				char sTimeColour[8];
				GetTimeColour( sTimeColour, time, Timer_GetClientPBTime( client, track, style ), Timer_GetWRTime( track, style ) );
				Format( output, maxlen, "Time: <font color='%s'>%s</font>", sTimeColour, output );
			}
		}
	}
}