/*  
*    Copyright (C) 2021  LuxLuma
*
*    This program is free software: you can redistribute it and/or modify
*    it under the terms of the GNU General Public License as published by
*    the Free Software Foundation, either version 3 of the License, or
*    (at your option) any later version.
*
*    This program is distributed in the hope that it will be useful,
*    but WITHOUT ANY WARRANTY; without even the implied warranty of
*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*    GNU General Public License for more details.
*
*    You should have received a copy of the GNU General Public License
*    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <lux_library>


#define REQUIRE_EXTENSIONS
#include <clientprefs>
#undef REQUIRE_EXTENSIONS

#pragma newdecls required

#define PLUGIN_VERSION "0.8.2"

#define DEBUG false


#define COLOUR "5 5 5"
#define BRIGHTNESS "5"
#define INNER_CONE "1"
#define OUTERCONE "37"
#define SPOTLIGHT_RANGE 700.0
#define SPOTLIGHT_SIZE 200.0

#define COOKIE_DEFAULT "1"


public Plugin myinfo =
{
	name = "[L4D/L4D2]team_lights",
	author = "Lux",
	description = "Team lights!",
	version = PLUGIN_VERSION,
	url = "-"
};


enum
{
	EF_BONEMERGE			= 0x001,	// Performs bone merge on client side
	EF_BRIGHTLIGHT 			= 0x002,	// DLIGHT centered at entity origin
	EF_DIMLIGHT 			= 0x004,	// player flashlight
	EF_NOINTERP				= 0x008,	// don't interpolate the next frame
	EF_NOSHADOW				= 0x010,	// Don't cast no shadow
	EF_NODRAW				= 0x020,	// don't draw entity
	EF_NORECEIVESHADOW		= 0x040,	// Don't receive no shadow
	EF_BONEMERGE_FASTCULL	= 0x080,	// For use with EF_BONEMERGE. If this is set, then it places this ent's origin at its
										// parent and uses the parent's bbox + the max extents of the aiment.
										// Otherwise, it sets up the parent's bones every frame to figure out where to place
										// the aiment, which is inefficient because it'll setup the parent's bones even if
										// the parent is not in the PVS.
	EF_ITEM_BLINK			= 0x100,	// blink an item so that the user notices it.
	EF_PARENT_ANIMATES		= 0x200,	// always assume that the parent entity is animating
	EF_MAX_BITS = 10
};

//flashlight
int g_LightOwner[2048+1];
//spec check bool do it once not on every light :P
int g_Spec[MAXPLAYERS+1];

enum struct FlashLightData
{
	int m_client;
	int m_flashLightRef;
	
	int m_lastActiveWeaponRef;
	bool m_bflashLightWeapon;
	
	bool m_bShowFlashLights;
	
	//makes use of clientside cone model illumination rather than the spotlight illumination, spotlight only illuminates on geometry, displacements ect.
	bool MakeFlashLight()
	{
		if(this.FlashLightIsValid())
			return true;
		
		this.m_flashLightRef = CreateEntityByName("light_dynamic");
		if(this.m_flashLightRef == -1)
		{
			return false;
		}
		
		DispatchKeyValue(this.m_flashLightRef, "brightness", BRIGHTNESS);
		DispatchKeyValueFloat(this.m_flashLightRef, "spotlight_radius", SPOTLIGHT_SIZE);
		DispatchKeyValueFloat(this.m_flashLightRef, "distance", SPOTLIGHT_RANGE);
		DispatchKeyValue(this.m_flashLightRef, "style", "-1");
		
		DispatchKeyValue(this.m_flashLightRef, "_light", COLOUR);
		
		DispatchKeyValue(this.m_flashLightRef, "_inner_cone", INNER_CONE);
		DispatchKeyValue(this.m_flashLightRef, "_cone", OUTERCONE);
		
		DispatchKeyValue(this.m_flashLightRef, "spawnflags", "0");
		
		DispatchSpawn(this.m_flashLightRef);
		AcceptEntityInput(this.m_flashLightRef, "TurnOn");
		
		g_LightOwner[this.m_flashLightRef] = this.m_client;
		this.m_flashLightRef = EntIndexToEntRef(this.m_flashLightRef);
		SDKHook(this.m_flashLightRef, SDKHook_SetTransmit, HideFlashLightFromOwner);
		return true;
	}
	void SetupFlashLight()
	{
		int weaponRef = GetEntPropEnt(this.m_client, Prop_Data, "m_hActiveWeapon");
		if(weaponRef == INVALID_ENT_REFERENCE)
		{
			this.DeleteFlashLight();
			return;
		}
		
		weaponRef = EntIndexToEntRef(weaponRef);
		if(this.m_lastActiveWeaponRef != weaponRef)
		{
			this.m_lastActiveWeaponRef = weaponRef;
			
			char classname[64];
			GetEntityClassname(this.m_lastActiveWeaponRef, classname, sizeof(classname));
			if(IsNonFlashLightWeapon(classname))
			{
				this.DeleteFlashLight();
				this.m_bflashLightWeapon = false;
				return;
			}
			
			this.m_bflashLightWeapon = true;
		}
		
		int viewModel = GetEntPropEnt(this.m_client, Prop_Send, "m_hViewModel");
		if(viewModel == -1)
		{
			this.DeleteFlashLight();
			return;
		}
		
		int iFlags = GetEntProp(viewModel, Prop_Data, "m_fEffects");
		if(iFlags & EF_NODRAW)
		{
			this.DeleteFlashLight();
			return;
		}
		
		iFlags = GetEntProp(this.m_client, Prop_Data, "m_fEffects");
		#if DEBUG
		if(this.m_bflashLightWeapon)
		#else
		if(this.m_bflashLightWeapon && (iFlags & EF_DIMLIGHT))
		#endif
		{
			if(this.MakeFlashLight())
			{
				this.TeleportLight();
			}
		}
		else
		{
			this.DeleteFlashLight();
		}
	}
	void TeleportLight()
	{
		static float vecPos[3];
		static float vecAng[3];
		
		GetClientEyePosition(this.m_client, vecPos);
		GetClientEyeAngles(this.m_client, vecAng);
		
		OriginMove(vecPos, vecAng, vecPos, 20.0);
		SetAbsOrigin(this.m_flashLightRef, vecPos);
		SetAbsAngles(this.m_flashLightRef, vecAng);
	}
	void DeleteFlashLight()
	{
		if(this.FlashLightIsValid())
		{
			RemoveEntity(this.m_flashLightRef);
		}
	}
	bool FlashLightIsValid()
	{
		return IsValidEntRef(this.m_flashLightRef);
	}
	void DeleteAllLights()
	{
		this.DeleteFlashLight();
	}
}

FlashLightData g_FlashLightData[MAXPLAYERS+1];

Cookie g_CookieFlashLight;


public void OnPluginStart()
{
	CreateConVar("team_lights_version", PLUGIN_VERSION, "", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_CookieFlashLight = new Cookie("flashlight_cookie", "", CookieAccess_Private); //no cookie handler included
	for(int i = 1; i <= MAXPLAYERS; ++i)
	{
		g_FlashLightData[i].m_client = i;
	}
	for(int i = 1; i <= MaxClients; ++i)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MAXPLAYERS; ++i)
	{
		g_FlashLightData[i].DeleteAllLights();
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PreThinkPost, DoLightStuff);
	
	if(!AreClientCookiesCached(client) && !IsFakeClient(client))
	{
		g_FlashLightData[client].m_bShowFlashLights = false;
	}
}

public void OnClientDisconnect(int client)
{
	g_FlashLightData[client].DeleteAllLights();
}


public void DoLightStuff(int client)
{
	int team = GetClientTeam(client);
	int alive = IsPlayerAlive(client);
	if(alive && (team == 2 || team == 4))
	{
		g_FlashLightData[client].SetupFlashLight();
		return;
	}
	else
	{
		g_FlashLightData[client].DeleteAllLights();
	}
	
	g_Spec[client] = -1;
	if(alive || IsFakeClient(client) || GetEntProp(client, Prop_Send, "m_iObserverMode") != 4)
		return;
	
	g_Spec[client] = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
}

public Action HideFlashLightFromOwner(int entity, int client)
{
	if(!g_FlashLightData[client].m_bShowFlashLights)
		return Plugin_Handled;
	
	#if !DEBUG
	if(g_LightOwner[entity] == client)
		return Plugin_Handled;
	#endif
	
	if(g_Spec[client] == g_LightOwner[entity])
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public void OnGameFrame()
{
	if(!IsServerProcessing())
		return;
	
	static int client;
	if(client > MaxClients || client < 1)
		client = 1;
	
	if(IsClientInGame(client) && !IsFakeClient(client))
	{
		if(AreClientCookiesCached(client))
		{
			char cookie[2];
			g_CookieFlashLight.Get(client, cookie, sizeof(cookie));
			g_FlashLightData[client].m_bShowFlashLights = view_as<bool>(StringToInt(cookie));// i'm lazy fuck off
		}
		else
		{
			g_FlashLightData[client].m_bShowFlashLights = false;
		}
	}
	++client;
}

StringMap CreateNonFlashLightWeaponClassnameHashMap(StringMap hNonFlashLightWeaponClassnameHashMap)
{
	hNonFlashLightWeaponClassnameHashMap = CreateTrie();
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_melee", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_chainsaw", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_vomitjar", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_pipe_bomb", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_molotov", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_defibrillator", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_first_aid_kit", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_upgradepack_explosive", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_upgradepack_incendiary", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_pain_pills", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_adrenaline", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_cola_bottles", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_fireworkcrate", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_gascan", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_gnome", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_oxygentank", true);
	hNonFlashLightWeaponClassnameHashMap.SetValue("weapon_propanetank", true);
	return hNonFlashLightWeaponClassnameHashMap;
}

bool IsNonFlashLightWeapon(const char[] classname)
{
	static StringMap hNonFlashLightWeaponClassnameHashMap;
	
	if(hNonFlashLightWeaponClassnameHashMap == INVALID_HANDLE)
		hNonFlashLightWeaponClassnameHashMap = CreateNonFlashLightWeaponClassnameHashMap(hNonFlashLightWeaponClassnameHashMap);
	
	bool bNonLight;
	hNonFlashLightWeaponClassnameHashMap.GetValue(classname, bNonLight);
	return bNonLight;
}

public void OnClientCookiesCached(int client)
{
	char cookie[2];
	g_CookieFlashLight.Get(client, cookie, sizeof(cookie));
	if(cookie[0] == '\0')
	{
		g_CookieFlashLight.Set(client, COOKIE_DEFAULT);
		cookie = COOKIE_DEFAULT;
	}
	
	g_FlashLightData[client].m_bShowFlashLights = view_as<bool>(StringToInt(cookie));
}

stock void OriginMove(float fStartOrigin[3], float fStartAngles[3], float EndOrigin[3], float fDistance)
{
	float fDirection[3];
	GetAngleVectors(fStartAngles, fDirection, NULL_VECTOR, NULL_VECTOR);

	EndOrigin[0] = fStartOrigin[0] + fDirection[0] * fDistance;
	EndOrigin[1] = fStartOrigin[1] + fDirection[1] * fDistance;
	EndOrigin[2] = fStartOrigin[2] + fDirection[2] * fDistance;
}

stock bool IsValidEntRef(int iEntRef)
{
	return (iEntRef != 0 && EntRefToEntIndex(iEntRef) != INVALID_ENT_REFERENCE);
}