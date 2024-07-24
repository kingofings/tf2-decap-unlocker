#include <dhooks>
#include <tf2attributes>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name = "TF2 Decap Unlocker",
	author = "kingo",
	description = "Unlocks the eyelanders decapitation buff limits",
	version = "1.1.1",
	url = "https://github.com/kingofings/tf2-decap-unlimit"
};

Handle g_CTFSword_GetSwordSpeedMod;
Handle g_CTFSword_GetSwordHealthMod;
Handle g_SDKCTFDecapitationMeleeWeaponBase_CanDecapitate;

ConVar sm_decap_speed_limit;
ConVar sm_decap_speed_multiplier;
ConVar sm_decap_health_limit;
ConVar sm_decap_health_multiplier;
ConVar sm_decap_shield_bash_limit;
ConVar sm_decap_shield_bash_multiplier;

public void OnPluginStart()
{
	GameData gameConf = new GameData("tf2.decap_unlocker");

	if (!gameConf)SetFailState("Could not parse gamedata file tf2.decap_unlocker.txt, does it exist inside of the gamedata folder?");

	g_CTFSword_GetSwordSpeedMod = DHookCreateFromConf(gameConf, "CTFSword::GetSwordSpeedMod()");
	if (!g_CTFSword_GetSwordSpeedMod)SetFailState("Could not create Dhook CTFSword::GetSwordSpeedMod(), offsets mismatching due to game update?");

	g_CTFSword_GetSwordHealthMod = DHookCreateFromConf(gameConf, "CTFSword::GetSwordHealthMod()");
	if (!g_CTFSword_GetSwordHealthMod)SetFailState("Could not create Dhook CTFSword::GetSwordHealthMod(), offsets mismatching due to game update?");

	Handle dtCTFWearableDemoShield_CalculateChargeDamage = DHookCreateFromConf(gameConf, "CTFWearableDemoShield::CalculateChargeDamage()");
	if (!dtCTFWearableDemoShield_CalculateChargeDamage)SetFailState("Could not create detour CTFWearableDemoShield::CalculateChargeDamage(), signature mismatching due to game update?");
	DHookEnableDetour(dtCTFWearableDemoShield_CalculateChargeDamage, true, CTFWearableDemoShield_CalculateChargeDamagePost);

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gameConf, SDKConf_Virtual, "CTFDecapitationMeleeWeaponBase::CanDecapitate()");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_SDKCTFDecapitationMeleeWeaponBase_CanDecapitate = EndPrepSDKCall();
	if (!g_SDKCTFDecapitationMeleeWeaponBase_CanDecapitate)SetFailState("Could not prep SDKCall CTFDecapitationMeleeWeaponBase::CanDecapitate(), offsets mismatching due to game update?");

	delete gameConf;

	sm_decap_speed_limit = CreateConVar("sm_decap_speed_limit", "4", "The maximum amount of speed the eyelanders decapitation buff can give", FCVAR_NOTIFY);
	sm_decap_speed_multiplier = CreateConVar("sm_decap_speed_multiplier", "0.08", "The multiplier for the eyelanders decapitation buff speed per head", FCVAR_NOTIFY);
	sm_decap_health_limit = CreateConVar("sm_decap_health_limit", "4", "The maximum amount of health the eyelanders decapitation buff can give", FCVAR_NOTIFY);
	sm_decap_health_multiplier = CreateConVar("sm_decap_health_multiplier", "15.0", "The multiplier for the eyelanders decapitation buff health per head", FCVAR_NOTIFY);
	sm_decap_shield_bash_limit = CreateConVar("sm_decap_shield_bash_limit", "5", "The maximum amount of damage the shields decapitation buff can give", FCVAR_NOTIFY);
	sm_decap_shield_bash_multiplier = CreateConVar("sm_decap_shield_bash_multiplier", "0.1", "The multiplier for the shields decapitation buff damage per head", FCVAR_NOTIFY);

	AutoExecConfig(true, "tf2-decap-unlocker");
}

public void OnEntityCreated(int entity, const char[] className)
{
	if (!StrEqual(className, "tf_weapon_sword", false))return;

	DHookEntity(g_CTFSword_GetSwordSpeedMod, false, entity, _, CTFSword_GetSwordSpeedModPre);
	DHookEntity(g_CTFSword_GetSwordHealthMod, false, entity, _, CTFSword_GetSwordHealthModPre);
}

MRESReturn CTFSword_GetSwordSpeedModPre(int weapon, DHookReturn ret)
{
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	if (!owner)
	{
		DHookSetReturn(ret, 0.0);
		return MRES_Supercede;
	}

	if (!CTFDecapitationMeleeWeaponBase_CanDecapitate(weapon))
	{
		DHookSetReturn(ret, 1.0);
		return MRES_Supercede;
	}

	int decapCount = min(sm_decap_speed_limit.IntValue, GetEntProp(owner, Prop_Send, "m_iDecapitations"));

	DHookSetReturn(ret, 1.0 + (decapCount * sm_decap_speed_multiplier.FloatValue));
	return MRES_Supercede;
}

MRESReturn CTFSword_GetSwordHealthModPre(int weapon, DHookReturn ret)
{
	DHookSetReturn(ret, 0);
	
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	if (!owner)return MRES_Supercede;

	if (!CTFDecapitationMeleeWeaponBase_CanDecapitate(weapon))return MRES_Supercede;

	int decapCount = min(sm_decap_health_limit.IntValue, GetEntProp(owner, Prop_Send, "m_iDecapitations"));

	DHookSetReturn(ret, (decapCount * sm_decap_health_multiplier.IntValue));

	return MRES_Supercede;
}

MRESReturn CTFWearableDemoShield_CalculateChargeDamagePost(int wearable, DHookReturn ret, DHookParam params)
{
	float currentChargeMeter = DHookGetParam(params, 1);
	float impactDamage = RemapValClamped(currentChargeMeter, 90.0, 40.0, 15.0, 50.0);

	int owner = GetEntPropEnt(wearable, Prop_Send, "m_hOwnerEntity");
	if (!owner)
	{
		DHookSetReturn(ret, impactDamage);
		return MRES_Supercede;
	}

	int decapCount = min(sm_decap_shield_bash_limit.IntValue, GetEntProp(owner, Prop_Send, "m_iDecapitations"));
	if (decapCount > 0)impactDamage *= (1.0 + decapCount * sm_decap_shield_bash_multiplier.FloatValue);

	impactDamage *= TF2Attrib_HookValueFloat(1.0, "charge_impact_damage", owner);

	DHookSetReturn(ret, impactDamage);
	return MRES_Supercede;
}

bool CTFDecapitationMeleeWeaponBase_CanDecapitate(int weapon)
{
	return SDKCall(g_SDKCTFDecapitationMeleeWeaponBase_CanDecapitate, weapon);
}

int min(int a, int b) 
{
    return a < b ? a : b;
}

float ClampFloat(float value, float min, float max) 
{
	if (value > max)return max;
	else if (value < min)return min;

	return value;
}

float RemapValClamped( float val, float A, float B, float C, float D)
{
	if ( A == B )return val >= B ? D : C;
		
	float cVal = (val - A) / (B - A);
	cVal = ClampFloat( cVal, 0.0, 1.0 );

	return C + (D - C) * cVal;
}
