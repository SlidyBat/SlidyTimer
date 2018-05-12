#include <sourcemod>
#include <slidy-timer>
#include <clientprefs>

typedef SelectColourCB = function void ( int client, int colour, any data );

char g_cColourCodes[][] = 
{
	"\x01",
	"\x07",
	"\x0F",
	"\x02",
	"\x0A",
	"\x0B",
	"\x0C",
	"\x0E",
	"\x09",
	"\x10",
	"\x05",
	"\x04",
	"\x06",
	"\x08",
	"\x0D",
	"\x03",
}

char g_cColourNames[][] = 
{
	"{white}",
	"{red}",
	"{lightred}",
	"{darkred}",
	"{bluegrey}",
	"{blue}",
	"{darkblue}",
	"{orchid}",
	"{yellow}",
	"{gold}",
	"{lightgreen}",
	"{green}",
	"{lime}",
	"{grey}",
	"{grey2}",
	"{teamcolour}",
}

char g_cColourDisplayNames[][] = 
{
	"White",
	"Red",
	"Light Red",
	"Dark Red",
	"Blue-Grey",
	"Blue",
	"Dark Blue",
	"Orchid",
	"Yellow",
	"Gold",
	"Light Green",
	"Green",
	"Lime",
	"Grey",
	"Dark Grey",
	"Team Colour",
}

enum
{
	Colour_Primary,
	Colour_Secondary,
	Colour_Name,
	Colour_Message,
	TOTAL_COLOUR_SETTINGS
}

SelectColourCB g_SelectColourCB[MAXPLAYERS + 1];
any g_SelectColourData[MAXPLAYERS + 1];

int g_iColourSettings[MAXPLAYERS + 1][TOTAL_COLOUR_SETTINGS];

Handle g_hCookiePrimaryColour;
Handle g_hCookieSecondaryColour;
Handle g_hCookieNameColour;

public Plugin myinfo = 
{
	name = "Slidy's Timer - Chat",
	author = "SlidyBat",
	description = "Chat component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	CreateNative( "Timer_PrintToChat", Native_PrintToChat );
	CreateNative( "Timer_PrintToChatAll", Native_PrintToChatAll );
	CreateNative( "Timer_PrintToAdmins", Native_PrintToAdmins );
	CreateNative( "Timer_ReplyToCommand", Native_ReplyToCommand );

	RegPluginLibrary( "timer-chat" );
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hCookiePrimaryColour = RegClientCookie( "sm_primary_colour", "Timer primary colour", CookieAccess_Protected );
	g_hCookieSecondaryColour = RegClientCookie( "sm_secondary_colour", "Timer secondary colour", CookieAccess_Protected );
	g_hCookieNameColour = RegClientCookie( "sm_name_colour", "Timer name colour", CookieAccess_Protected );

	RegConsoleCmd( "sm_chatsettings", Command_ChatSettings );
}

public void OnClientPutInServer( int client )
{
	if( !GetClientCookieInt( client, g_hCookiePrimaryColour, g_iColourSettings[client][Colour_Primary] ) )
	{
		g_iColourSettings[client][Colour_Primary] = 2; // blue
		SetClientCookieInt( client, g_hCookiePrimaryColour, 5 );
	}
	if( !GetClientCookieInt( client, g_hCookieSecondaryColour, g_iColourSettings[client][Colour_Secondary] ) )
	{
		g_iColourSettings[client][Colour_Secondary] = 9; // gold
		SetClientCookieInt( client, g_hCookiePrimaryColour, 9 );
	}
	if( !GetClientCookieInt( client, g_hCookieNameColour, g_iColourSettings[client][Colour_Name] ) )
	{
		g_iColourSettings[client][Colour_Name] = 3; // dark red
		SetClientCookieInt( client, g_hCookiePrimaryColour, 2 );
	}
}

void OpenSelectColourMenu( int client, SelectColourCB callback, any data = 0 )
{
	g_SelectColourCB[client] = callback;
	g_SelectColourData[client] = data;
	
	Menu menu = new Menu( SelectColour_Handler );
	menu.SetTitle( "Select Colour\n \n" );
	
	for( int i = 0; i < sizeof(g_cColourDisplayNames); i++ )
	{
		menu.AddItem( g_cColourCodes[i], g_cColourDisplayNames[i] );
	}
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int SelectColour_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		Call_StartFunction( GetMyHandle(), g_SelectColourCB[param1] );
		Call_PushCell( param1 );
		Call_PushCell( param2 );
		Call_PushCell( g_SelectColourData[param1] );
		Call_Finish();
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void OpenChatSettingsMenu( int client )
{
	Menu menu = new Menu( ChatSettings_Handler );
	menu.SetTitle( "Timer - Chat Settings\n \n" );
	
	char buffer[128];
	
	Format( buffer, sizeof(buffer), "Primary: %s", g_cColourDisplayNames[g_iColourSettings[client][Colour_Primary]] );
	menu.AddItem( "primary", buffer );
	Format( buffer, sizeof(buffer), "Secondary: %s", g_cColourDisplayNames[g_iColourSettings[client][Colour_Secondary]] );
	menu.AddItem( "secondary", buffer );
	Format( buffer, sizeof(buffer), "Names: %s", g_cColourDisplayNames[g_iColourSettings[client][Colour_Name]] );
	menu.AddItem( "name", buffer );
	
	menu.Display( client, MENU_TIME_FOREVER );
}

public int ChatSettings_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		OpenSelectColourMenu( param1, ChangeClientChatSetting, param2 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void ChangeClientChatSetting( int client, int colour, int setting )
{
	g_iColourSettings[client][setting] = colour;
	
	switch( setting )
	{
		case Colour_Primary:
			SetClientCookieInt( client, g_hCookiePrimaryColour, colour );
		case Colour_Secondary:
			SetClientCookieInt( client, g_hCookieSecondaryColour, colour );
		case Colour_Name:
			SetClientCookieInt( client, g_hCookieNameColour, colour );
	}
	
	OpenChatSettingsMenu( client );
}

void RemoveColours( char[] message, int maxlen )
{
	for( int i = 0; i < sizeof(g_cColourNames); i++ )
	{
		ReplaceString( message, maxlen, g_cColourNames[i], "" );
	}
	
	ReplaceString( message, maxlen, "{primary}", "" );
	ReplaceString( message, maxlen, "{secondary}", "" );
	ReplaceString( message, maxlen, "{name}", "" );
}

void InsertColours( char[] message, int maxlen )
{
	for( int i = 0; i < sizeof(g_cColourNames); i++ )
	{
		ReplaceString( message, maxlen, g_cColourNames[i], g_cColourCodes[i] );
	}
}

void InsertClientColours( int client, char[] message, int maxlen )
{
	ReplaceString( message, maxlen, "{primary}", g_cColourCodes[g_iColourSettings[client][Colour_Primary]] );
	ReplaceString( message, maxlen, "{secondary}", g_cColourCodes[g_iColourSettings[client][Colour_Secondary]] );
	ReplaceString( message, maxlen, "{name}", g_cColourCodes[g_iColourSettings[client][Colour_Name]] );
}

// Commands

public Action Command_ChatSettings( int client, int args )
{
	OpenChatSettingsMenu( client );
	
	return Plugin_Handled;
}

// Natives

public int Native_PrintToChat( Handle handler, int numParams )
{
	Timer_DebugPrint( "Printing to chat" );

	char buffer[512];
	FormatNativeString( 0, 2, 3, sizeof(buffer), _, buffer );
	
	Timer_DebugPrint( buffer );
	
	Format( buffer, sizeof(buffer), "[{blue}Timer{white}] %s", buffer );
	InsertColours( buffer, sizeof(buffer) );
	
	int client = GetNativeCell( 1 );
	InsertClientColours( client, buffer, sizeof(buffer) );

	PrintToChat( client, buffer );
	
	return 1;
}

public int Native_PrintToChatAll( Handle handler, int numParams )
{
	char buffer[512];
	FormatNativeString( 0, 1, 2, sizeof(buffer), _, buffer );
	
	Format( buffer, sizeof(buffer), "[{blue}Timer{white}] %s", buffer );
	InsertColours( buffer, sizeof(buffer) );
	
	char buffer2[256];
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && !IsFakeClient( i ) )
		{
			strcopy( buffer2, sizeof(buffer2), buffer );
			InsertClientColours( i, buffer2, sizeof(buffer2) );
			
			PrintToChat( i, buffer2 );
		}
	}

	return 1;
}

public int Native_PrintToAdmins( Handle handler, int numParams )
{
	char buffer[512];
	FormatNativeString( 0, 1, 2, sizeof(buffer), _, buffer );
	
	Format( buffer, sizeof(buffer), "[{blue}Timer{white}] %s", buffer );
	InsertColours( buffer, sizeof(buffer) );
	
	int flags = GetNativeCell( 1 );
	
	char buffer2[512];
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( IsClientInGame( i ) && !IsFakeClient( i ) && CheckCommandAccess( i, "", flags ) )
		{
			strcopy( buffer2, sizeof(buffer2), buffer );
			InsertClientColours( i, buffer2, sizeof(buffer2) );
			
			PrintToChat( i, buffer2 );
		}
	}

	return 1;
}

public int Native_ReplyToCommand( Handle handler, int numParams )
{
	char buffer[512];
	FormatNativeString( 0, 2, 3, sizeof(buffer), _, buffer );
	
	int client = GetNativeCell( 1 );
	if( GetCmdReplySource() == SM_REPLY_TO_CHAT )
	{
		Format( buffer, sizeof(buffer), "[{blue}Timer{white}] %s", buffer );
		InsertColours( buffer, sizeof(buffer) );
		InsertClientColours( client, buffer, sizeof(buffer) );
		
		PrintToChat( client, buffer );
	}
	else
	{
		RemoveColours( buffer, sizeof(buffer) );
		Format( buffer, sizeof(buffer), "[Timer] %s", buffer );
		
		PrintToConsole( client, buffer );
	}
	
	return 1;
}

// Stocks

stock void SetClientCookieInt( int client, Handle cookie, int value )
{
	char sValue[8];
	IntToString( value, sValue, sizeof(sValue) );

	SetClientCookie( client, cookie, sValue );
}

stock bool GetClientCookieInt( int client, Handle cookie, int& value )
{
	char sValue[8];
	GetClientCookie( client, cookie, sValue, sizeof(sValue) );

	if( sValue[0] == '\0' )
	{
		return false;
	}

	value = StringToInt( sValue );
	return true;
}