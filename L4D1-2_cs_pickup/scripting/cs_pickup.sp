/*  
*    Copyright (C) 2022  LuxLuma
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

#pragma newdecls required


enum weaponSlotType
{
	WeaponSlotType_Unknown = -1,
	WeaponSlotType_Main = 0,
	WeaponSlotType_Second,
	WeaponSlotType_Throwable,
	WeaponSlotType_Medic,
	WeaponSlotType_Drugs
}

//yes fuck the double pistol shit

enum struct WeaponData
{
	int m_Index;
	int m_EntRef;
	weaponSlotType m_WeaponType;
	float m_flIgnorePickup;
	
	void ProcessWeapon(const char[] classname)
	{
		this.m_WeaponType = GetWeaponTypeFromClassname(classname);
		if(this.m_WeaponType == WeaponSlotType_Unknown)
			return;
		
		this.m_EntRef = EntIndexToEntRef(this.m_Index);
		this.m_flIgnorePickup = GetGameTime() + 0.5;
	}
	void ProcessPickup(int client)
	{
		if(this.m_WeaponType == WeaponSlotType_Unknown)
			return;
		
		float flGameTime = GetGameTime();
		if(this.m_flIgnorePickup > flGameTime || !IsValidEntRef(this.m_EntRef))
			return;
		
		if(!IsPlayerAlive(client) || GetClientTeam(client) != 2)
			return;
		
		int weaponIndex = GetPlayerWeaponSlot(client, this.m_WeaponType);
		if(weaponIndex != -1)
			return;
		
		if(GetEntPropEnt(this.m_Index, Prop_Send, "m_hOwnerEntity") != -1)
		{
			this.m_flIgnorePickup = flGameTime + 0.2;
			return;
		}
		
		AcceptEntityInput(this.m_Index, "use", client, client);
	}
	void ProcessWeaponDrop()
	{
		if(this.m_WeaponType != WeaponSlotType_Drugs || !IsValidEntRef(this.m_EntRef))
			return;
		
		this.m_flIgnorePickup = GetGameTime() + 2.0;// grabbing the pills you just tossed is fun :D
	}
}

WeaponData g_WeaponData[2048+1];

public Plugin myinfo =
{
	name = "CS_pickup",
	author = "Lux",
	description = "Yes play cs",
	version = "1.0.1",
	url = "https://www.youtube.com/watch?v=UOlaEZg1hlc"
};

public void OnPluginStart()
{
	for(int i = 1; i <= MaxClients; ++i)
	{
		if(!IsClientInGame(i))
			continue;

		OnClientPutInServer(i);
	}
	for(int i; i < sizeof(g_WeaponData); ++i)
	{
		g_WeaponData[i].m_Index = i;
		if(IsValidEntity(i))
		{
			
			char buf[64];
			GetEntityClassname(i, buf, sizeof(buf));
			g_WeaponData[i].ProcessWeapon(buf);
		}
	}
}


public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client))
		return;

	SDKHook(client, SDKHook_WeaponDropPost, DropWeapon);
	SDKHook(client, SDKHook_Touch, PickupTouch);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(entity < 0)
		return;
	
	g_WeaponData[entity].m_WeaponType = WeaponSlotType_Unknown;
	
	if(classname[0] != 'w')
		return;
	
	g_WeaponData[entity].ProcessWeapon(classname);
}

public void DropWeapon(int client, int weapon)
{
	if(weapon < 1 || g_WeaponData[weapon].m_WeaponType == WeaponSlotType_Unknown)
		return;
	
	g_WeaponData[weapon].ProcessWeaponDrop();
}


public Action PickupTouch(int client, int other)
{
	if(other <= MaxClients)
		return;

	g_WeaponData[other].ProcessPickup(client);
}

stock bool IsValidEntRef(int iEntRef)
{
	return (iEntRef != 0 && EntRefToEntIndex(iEntRef) != INVALID_ENT_REFERENCE);
}

StringMap CreateWeaponClassnameHashMap(StringMap hWeaponClassnameHashMap)
{
	hWeaponClassnameHashMap = CreateTrie();
	hWeaponClassnameHashMap.SetValue("weapon_pistol", WeaponSlotType_Second);
	hWeaponClassnameHashMap.SetValue("weapon_pistol_magnum", WeaponSlotType_Second);
	hWeaponClassnameHashMap.SetValue("weapon_rifle", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_rifle_ak47", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_rifle_desert", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_rifle_m60", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_rifle_sg552", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_hunting_rifle", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_sniper_awp", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_sniper_military", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_sniper_scout", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_smg", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_smg_silenced", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_smg_mp5", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_autoshotgun", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_shotgun_spas", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_pumpshotgun", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_shotgun_chrome", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_molotov", WeaponSlotType_Throwable);
	hWeaponClassnameHashMap.SetValue("weapon_pipe_bomb", WeaponSlotType_Throwable);
	hWeaponClassnameHashMap.SetValue("weapon_first_aid_kit", WeaponSlotType_Medic);
	hWeaponClassnameHashMap.SetValue("weapon_pain_pills", WeaponSlotType_Drugs);
	hWeaponClassnameHashMap.SetValue("weapon_vomitjar", WeaponSlotType_Throwable);
	hWeaponClassnameHashMap.SetValue("weapon_adrenaline", WeaponSlotType_Drugs);
	hWeaponClassnameHashMap.SetValue("weapon_chainsaw", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_defibrillator", WeaponSlotType_Medic);
	hWeaponClassnameHashMap.SetValue("weapon_grenade_launcher", WeaponSlotType_Main);
	hWeaponClassnameHashMap.SetValue("weapon_melee", WeaponSlotType_Second);
	hWeaponClassnameHashMap.SetValue("weapon_upgradepack_incendiary", WeaponSlotType_Medic);
	hWeaponClassnameHashMap.SetValue("weapon_upgradepack_explosive", WeaponSlotType_Medic);
	return hWeaponClassnameHashMap;
}

weaponSlotType GetWeaponTypeFromClassname(const char[] sClassname)
{
	static StringMap hWeaponClassnameHashMap;

	if(hWeaponClassnameHashMap == INVALID_HANDLE)
		hWeaponClassnameHashMap = CreateWeaponClassnameHashMap(hWeaponClassnameHashMap);

	static weaponSlotType WeaponType;
	if(!hWeaponClassnameHashMap.GetValue(sClassname, WeaponType))
		return WeaponSlotType_Unknown;

	return WeaponType;
}