#if defined _slidy_timer_included
  #endinput
#endif
#define _slidy_timer_included

#define TIMER_PLUGIN_VERSION "0.1"
#define MENU_PREFIX "Timer"

enum ZoneType
{
	Zone_None = -1,
	Zone_Start,
	Zone_End,
	Zone_Checkpoint,
	Zone_Cheatzone,
	TOTAL_ZONE_TYPES
}

static char g_cZoneTypeNames[][] =
{
	"Start Zone",
	"End Zone",
	"Checkpoint",
	"Cheatzone"
};

enum ZoneTrack
{
	ZT_Main,
	ZT_Bonus,
	TOTAL_ZONE_TRACKS
}

static char g_cZoneTrackNames[][] =
{
	"Main",
	"Bonus"
};

enum
{
	ZD_ZoneId,
	ZD_ZoneSubindex, // index used for zone types that can have more than one of same zone, ie. checkpoint/anticheat
	Float:ZD_x1,
	Float:ZD_y1,
	Float:ZD_z1,
	Float:ZD_x2,
	Float:ZD_y2,
	Float:ZD_z2,
	ZoneType:ZD_ZoneType,
	ZoneTrack:ZD_ZoneTrack,
	ZONE_DATA
}

stock bool IsValidClient(int client, bool bAlive = false) // when bAlive is false = technical checks, when it's true = gameplay checks
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

// from shavits because im not doing this
stock void TimerFormatTime( float time, char[] newtime, int newtimesize, bool precise = true )
{
	float fTempTime = time;

	if( fTempTime < 0.0 )
	{
		fTempTime = -fTempTime;
	}

	int iRounded = RoundToFloor( fTempTime );
	float fSeconds = ( iRounded % 60 ) + fTempTime - iRounded;

	char sSeconds[8];
	FormatEx( sSeconds, 8, precise ? "%s%.03f" : "%s%.01f", ( fSeconds < 0.0 ) ? "-" : "", fSeconds );

	if( fTempTime < 60.0 )
	{
		strcopy( newtime, newtimesize, sSeconds );
	}
	else
	{
		int iMinutes = ( iRounded / 60 );

		if( fTempTime < 3600.0 )
		{
			FormatEx( newtime, newtimesize, "%s%d:%s%s", ( time < 0.0 )? "-" : "", iMinutes, ( fSeconds < 10 )? "0" : "", sSeconds );
		}
		else
		{
			iMinutes %= 60;
			int iHours = ( iRounded / 3600 );

			FormatEx( newtime, newtimesize, "%s%d:%s%d:%s%s", ( time < 0.0 ) ? "-" : "", iHours, ( iMinutes < 10 ) ? "0" : "", iMinutes, ( fSeconds < 10 )? "0" : "", sSeconds );
		}
	}
}

stock void Timer_GetZoneTypeName( ZoneType zoneType, char[] buffer, int maxlen )
{
	strcopy( buffer, maxlen, g_cZoneTypeNames[view_as<int>( zoneType )] );
}

stock void Timer_GetZoneTrackName( ZoneTrack zoneTrack, char[] buffer, int maxlen )
{
	strcopy( buffer, maxlen, g_cZoneTrackNames[view_as<int>( zoneTrack )] );
}

/**
 * Called when Database handle has been loaded by core timer plugin
 *
 * @noreturn
 */
forward void Timer_OnDatabaseReady();

/**
 * Called when a client enters a zone
 *
 * @param client					Client index of player that entered zone
 * @param zone_id					id of zone (useful for identifying zone in db)
 * @param zoneType					type of zone (ie. start, end, checkpoint ...)
 * @param zoneTrack					track of zone (ie. main/bonus)
 * @param zone_subindex				subindex of zone, useful for identifying which checkpoint/anticheat zone was entered
 *
 * @noreturn
 */
forward void Timer_OnEnterZone( int client, int zone_id, ZoneType zoneType, ZoneTrack zoneTrack, int zone_subindex );

/**
 * Called when a client exits a zone
 *
 * @param client					Client index of player that exited zone
 * @param zone_id					id of zone (useful for identifying zone in db)
 * @param zoneType					type of zone (ie. start, end, checkpoint ...)
 * @param zoneTrack					track of zone (ie. main/bonus)
 * @param zone_subindex				subindex of zone, useful for identifying which checkpoint/anticheat zone was entered
 *
 * @noreturn
 */
forward void Timer_OnExitZone( int client, int zone_id, ZoneType zoneType, ZoneTrack zoneTrack, int zone_subindex );

/**
 * Provides database handle from timer
 *
 * @param handle					A handle of type Database passed in by reference to clone database into
 * @noreturn
 */
native void Timer_GetDatabase( Database& handle );

/**
 * Gets zone type client is currently in
 *
 * @param client					Client index.
 * @return							ZoneType of client current zone, or Zone_None if they are not in zone
 */
native ZoneType Timer_GetClientZoneType( int client );

/**
 * Gets track client is currently in (ie. main/bonus)
 *
 * @param client					Client index.
 * @return							Current ZoneTrack of client
 */
native ZoneTrack Timer_GetClientZoneTrack( int client );

public SharedPlugin __pl_slidy_timer =
{
	name = "slidy-timer",
	file = "timer-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_slidy_timer_SetNTVOptional()
{
	MarkNativeAsOptional("Timer_GetDatabase");
	MarkNativeAsOptional("Timer_GetClientZoneType");
	MarkNativeAsOptional("Timer_GetClientZoneTrack");
}
#endif