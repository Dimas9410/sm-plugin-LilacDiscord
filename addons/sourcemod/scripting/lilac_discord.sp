#include <sourcemod>
#include <ripext>
#include <lilac>

#pragma newdecls required
#pragma semicolon 1

#define COLOR_DETECTED 16753920
#define COLOR_BANNED   16711680

ConVar g_cvEnable;
ConVar g_cvWebhookURL;
ConVar g_cvFallbackWebhook; /* sm_discord_webhook from the DiscordChat plugin (optional) */
ConVar g_cvSendDetected;
ConVar g_cvSendBanned;
ConVar g_cvCooldown;
ConVar g_cvShowIP;
ConVar g_cvMentionRole;
ConVar g_cvBotName;
ConVar g_cvAvatarURL;

float g_fLastAlert[MAXPLAYERS + 1][CHEAT_MAX];

public Plugin myinfo =
{
	name        = "Lilac Discord Alert",
	author      = "Dimas9410",
	description = "Sends Little Anti-Cheat (Lilac) detections and bans to a Discord webhook",
	version     = "1.0",
	url         = "amyserver.xyz"
};

public void OnPluginStart()
{
	g_cvEnable      = CreateConVar("sm_lilac_discord_enable", "1", "Enable Lilac alerts to Discord (1 = enabled)", _, true, 0.0, true, 1.0);
	g_cvWebhookURL  = CreateConVar("sm_lilac_discord_webhook", "", "Discord Webhook URL for Lilac alerts. Leave empty to use sm_discord_webhook (DiscordChat)", FCVAR_PROTECTED);
	g_cvSendDetected = CreateConVar("sm_lilac_discord_detected", "1", "Send an alert when a player is detected / flagged (1 = yes)", _, true, 0.0, true, 1.0);
	g_cvSendBanned  = CreateConVar("sm_lilac_discord_banned", "1", "Send an alert when Lilac is about to ban a player (1 = yes)", _, true, 0.0, true, 1.0);
	g_cvCooldown    = CreateConVar("sm_lilac_discord_cooldown", "30.0", "Minimum delay (seconds) between alerts for the same player + cheat type (anti-spam)", _, true, 0.0);
	g_cvShowIP      = CreateConVar("sm_lilac_discord_showip", "0", "Show the player's IP in the alert (1 = yes)", _, true, 0.0, true, 1.0);
	g_cvMentionRole = CreateConVar("sm_lilac_discord_mentionrole", "", "Discord role ID to mention on alerts (leave empty for no mention)");
	g_cvBotName     = CreateConVar("sm_lilac_discord_botname", "Lilac Anti-Cheat", "Webhook sender name shown in Discord");
	g_cvAvatarURL   = CreateConVar("sm_lilac_discord_avatar", "https://media.discordapp.net/attachments/1541220210554437673/1563540123591643287/LOGO_ADS.png?ex=6addffb6&is=6adcae36&hm=fa09c0724de5db3d53a6743e13f6753ae103dcd69cf0897022fe602117aa8bd3&=&format=webp&quality=lossless&width=512&height=512", "Webhook avatar image URL shown in Discord (leave empty to use the webhook's default avatar)");

	RegAdminCmd("sm_lilacdiscord_test", Command_Test, ADMFLAG_RCON, "Test the Lilac Discord webhook: sm_lilacdiscord_test [ping|detected|banned]");

	AutoExecConfig(true, "lilac_discord");
}

public void OnAllPluginsLoaded()
{
	/* Grab the DiscordChat convar if present, used as a fallback webhook. */
	g_cvFallbackWebhook = FindConVar("sm_discord_webhook");
}

public void OnClientDisconnect(int client)
{
	for (int i = 0; i < CHEAT_MAX; i++)
		g_fLastAlert[client][i] = 0.0;
}

public void lilac_cheater_detected(int client, int cheat)
{
	if (!g_cvEnable.BoolValue || !g_cvSendDetected.BoolValue)
		return;

	if (cheat < 0 || cheat >= CHEAT_MAX || !IsValidClient(client))
		return;

	/* Anti-spam: Lilac may call this forward many times. */
	float now = GetGameTime();
	float cooldown = g_cvCooldown.FloatValue;
	if (cooldown > 0.0 && g_fLastAlert[client][cheat] > 0.0 && (now - g_fLastAlert[client][cheat]) < cooldown)
		return;

	g_fLastAlert[client][cheat] = now;

	SendLilacAlert(client, cheat, false);
}

public void lilac_cheater_banned(int client, int cheat)
{
	if (!g_cvEnable.BoolValue || !g_cvSendBanned.BoolValue)
		return;

	if (cheat < 0 || cheat >= CHEAT_MAX || !IsValidClient(client))
		return;

	SendLilacAlert(client, cheat, true);
}

void SendLilacAlert(int client, int cheat, bool banned, bool test = false, int reportTo = 0)
{
	char webhook[256];
	if (!GetWebhookURL(webhook, sizeof(webhook)))
		return;

	int apiIndex = StrContains(webhook, "/api/webhooks/", false);
	if (apiIndex == -1)
	{
		LogError("[LilacDiscord] Invalid webhook URL format.");
		return;
	}

	char path[256];
	strcopy(path, sizeof(path), webhook[apiIndex]);

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	SanitizeForDiscord(name, sizeof(name));

	char steam2[32], steam64[32], profile[128];
	if (!GetClientAuthId(client, AuthId_Steam2, steam2, sizeof(steam2)))
		strcopy(steam2, sizeof(steam2), "N/A");

	if (GetClientAuthId(client, AuthId_SteamID64, steam64, sizeof(steam64)))
		FormatEx(profile, sizeof(profile), "[%s](https://steamcommunity.com/profiles/%s)", steam2, steam64);
	else
		strcopy(profile, sizeof(profile), steam2);

	char cheatName[32];
	GetCheatName(cheat, cheatName, sizeof(cheatName));

	char details[512];
	if (test)
		strcopy(details, sizeof(details), "This is a test alert, no real detection.");
	else if (lilac_GetDetectedInfos(client, details, sizeof(details)) != 1 || details[0] == '\0')
		strcopy(details, sizeof(details), "-");
	ReplaceString(details, sizeof(details), "`", "'");

	char hostname[128], map[64];
	FindConVar("hostname").GetString(hostname, sizeof(hostname));
	GetCurrentMap(map, sizeof(map));

	char timeStr[64];
	FormatTime(timeStr, sizeof(timeStr), "%d/%m/%Y %H:%M:%S");

	char title[96], desc[256], botName[64];
	g_cvBotName.GetString(botName, sizeof(botName));

	if (banned)
	{
		FormatEx(title, sizeof(title), "%s🔨 Player Banned by Lilac", test ? "[TEST] " : "");
		FormatEx(desc, sizeof(desc), "**%s** is about to be banned for **%s**.", name, cheatName);
	}
	else
	{
		FormatEx(title, sizeof(title), "%s⚠️ Cheat Detected", test ? "[TEST] " : "");
		FormatEx(desc, sizeof(desc), "**%s** was flagged by Lilac: **%s**.", name, cheatName);
	}

	JSONArray fields = new JSONArray();
	AddField(fields, "Player", name, true);
	AddField(fields, "SteamID", profile, true);
	AddField(fields, "Cheat", cheatName, true);

	if (g_cvShowIP.BoolValue)
	{
		char ip[32];
		if (GetClientIP(client, ip, sizeof(ip)))
			AddField(fields, "IP", ip, true);
	}

	char ping[16];
	FormatEx(ping, sizeof(ping), "%d ms", RoundToNearest(GetClientAvgLatency(client, NetFlow_Outgoing) * 1000.0));
	AddField(fields, "Ping", ping, true);
	AddField(fields, "Map", map, true);

	char detailBlock[560];
	FormatEx(detailBlock, sizeof(detailBlock), "```%s```", details);
	AddField(fields, "Detail", detailBlock, false);

	JSONObject footer = new JSONObject();
	char footerText[256];
	FormatEx(footerText, sizeof(footerText), "%s | %s", hostname, timeStr);
	footer.SetString("text", footerText);

	JSONObject embed = new JSONObject();
	embed.SetString("title", title);
	embed.SetString("description", desc);
	embed.SetInt("color", banned ? COLOR_BANNED : COLOR_DETECTED);
	embed.Set("fields", fields);
	embed.Set("footer", footer);

	JSONArray embeds = new JSONArray();
	embeds.Push(embed);

	/* Role mention (optional) + block all other mentions */
	char roleId[32];
	g_cvMentionRole.GetString(roleId, sizeof(roleId));
	TrimString(roleId);

	JSONObject allowed = new JSONObject();
	JSONArray parse = new JSONArray();
	allowed.Set("parse", parse); /* empty = no mentions are parsed automatically */

	JSONObject payload = new JSONObject();
	payload.SetString("username", botName);
	SetWebhookAvatar(payload);

	if (!test && roleId[0] != '\0' && IsNumeric(roleId))
	{
		char content[64];
		FormatEx(content, sizeof(content), "<@&%s>", roleId);
		payload.SetString("content", content);

		JSONArray roles = new JSONArray();
		roles.PushString(roleId);
		allowed.Set("roles", roles);
		delete roles;
	}

	payload.Set("allowed_mentions", allowed);
	payload.Set("embeds", embeds);

	PostToDiscord(path, payload, test, reportTo);

	delete payload;
	delete allowed;
	delete parse;
	delete embeds;
	delete embed;
	delete footer;
	delete fields;
}

void OnWebhookSent(HTTPResponse response, any value)
{
	if (response.Status != HTTPStatus_OK && response.Status != HTTPStatus_NoContent)
		LogError("[LilacDiscord] Failed to send alert to Discord, status: %d", response.Status);
}

void SetWebhookAvatar(JSONObject payload)
{
	char avatar[512];
	g_cvAvatarURL.GetString(avatar, sizeof(avatar));
	TrimString(avatar);

	if (avatar[0] != '\0')
		payload.SetString("avatar_url", avatar);
}

void PostToDiscord(const char[] path, JSONObject payload, bool test, int reportTo)
{
	HTTPClient http = new HTTPClient("https://discord.com");

	if (test)
		http.Post(path, payload, OnTestSent, reportTo);
	else
		http.Post(path, payload, OnWebhookSent);

	delete http;
}

public Action Command_Test(int client, int args)
{
	char mode[16];
	strcopy(mode, sizeof(mode), "ping");
	if (args >= 1)
		GetCmdArg(1, mode, sizeof(mode));

	bool isPing     = StrEqual(mode, "ping", false);
	bool isDetected = StrEqual(mode, "detected", false);
	bool isBanned   = StrEqual(mode, "banned", false);

	if (!isPing && !isDetected && !isBanned)
	{
		ReplyToCommand(client, "[LilacDiscord] Usage: sm_lilacdiscord_test [ping|detected|banned]");
		ReplyToCommand(client, "[LilacDiscord]   ping     = simple test message (default)");
		ReplyToCommand(client, "[LilacDiscord]   detected = fake 'Cheat Detected' alert using your own info (in-game only)");
		ReplyToCommand(client, "[LilacDiscord]   banned   = fake 'Player Banned' alert using your own info (in-game only)");
		return Plugin_Handled;
	}

	if ((isDetected || isBanned) && !IsValidClient(client))
	{
		ReplyToCommand(client, "[LilacDiscord] The '%s' test must be run by a real player in-game.", mode);
		return Plugin_Handled;
	}

	/* Check the webhook config and report found */
	char own[256];
	g_cvWebhookURL.GetString(own, sizeof(own));
	TrimString(own);

	char webhook[256];
	if (!GetWebhookURL(webhook, sizeof(webhook)))
	{
		ReplyToCommand(client, "[LilacDiscord] FAILED: no webhook set. Set sm_lilac_discord_webhook (or sm_discord_webhook from DiscordChat).");
		return Plugin_Handled;
	}

	int apiIndex = StrContains(webhook, "/api/webhooks/", false);
	if (apiIndex == -1)
	{
		ReplyToCommand(client, "[LilacDiscord] FAILED: webhook URL is invalid, it must contain /api/webhooks/<id>/<token>.");
		return Plugin_Handled;
	}

	char webhookId[32];
	if (SplitString(webhook[apiIndex + 14], "/", webhookId, sizeof(webhookId)) == -1)
		strcopy(webhookId, sizeof(webhookId), "?");

	ReplyToCommand(client, "[LilacDiscord] Webhook source: %s | webhook ID: %s",
		own[0] != '\0' ? "sm_lilac_discord_webhook" : "sm_discord_webhook (DiscordChat fallback)", webhookId);
	ReplyToCommand(client, "[LilacDiscord] Plugin enabled: %s | detected alerts: %s | banned alerts: %s",
		g_cvEnable.BoolValue ? "yes" : "NO", g_cvSendDetected.BoolValue ? "yes" : "NO", g_cvSendBanned.BoolValue ? "yes" : "NO");

	if (!g_cvEnable.BoolValue)
		ReplyToCommand(client, "[LilacDiscord] Note: sm_lilac_discord_enable is 0, so real alerts are OFF. The test below is still sent.");

	ReplyToCommand(client, "[LilacDiscord] Sending '%s' test to Discord...", mode);

	int reportTo = (client > 0) ? GetClientUserId(client) : 0;

	if (isPing)
		SendTestPing(client, webhook[apiIndex], reportTo);
	else
		SendLilacAlert(client, CHEAT_AIMBOT, isBanned, true, reportTo);

	return Plugin_Handled;
}

void SendTestPing(int client, const char[] path, int reportTo)
{
	char hostname[128], map[64], sender[MAX_NAME_LENGTH], botName[64], timeStr[64];
	FindConVar("hostname").GetString(hostname, sizeof(hostname));
	GetCurrentMap(map, sizeof(map));
	g_cvBotName.GetString(botName, sizeof(botName));
	FormatTime(timeStr, sizeof(timeStr), "%d/%m/%Y %H:%M:%S");

	if (client > 0)
	{
		GetClientName(client, sender, sizeof(sender));
		SanitizeForDiscord(sender, sizeof(sender));
	}
	else
	{
		strcopy(sender, sizeof(sender), "Server console");
	}

	JSONArray fields = new JSONArray();
	AddField(fields, "Server", hostname, true);
	AddField(fields, "Map", map, true);
	AddField(fields, "Triggered by", sender, true);

	JSONObject footer = new JSONObject();
	char footerText[256];
	FormatEx(footerText, sizeof(footerText), "%s | %s", hostname, timeStr);
	footer.SetString("text", footerText);

	JSONObject embed = new JSONObject();
	embed.SetString("title", "✅ Lilac Discord test");
	embed.SetString("description", "If you can see this message, the webhook works and Lilac alerts will be delivered to this channel.");
	embed.SetInt("color", 3066993);
	embed.Set("fields", fields);
	embed.Set("footer", footer);

	JSONArray embeds = new JSONArray();
	embeds.Push(embed);

	JSONObject allowed = new JSONObject();
	JSONArray parse = new JSONArray();
	allowed.Set("parse", parse);

	JSONObject payload = new JSONObject();
	payload.SetString("username", botName);
	SetWebhookAvatar(payload);
	payload.Set("allowed_mentions", allowed);
	payload.Set("embeds", embeds);

	PostToDiscord(path, payload, true, reportTo);

	delete payload;
	delete allowed;
	delete parse;
	delete embeds;
	delete embed;
	delete footer;
	delete fields;
}

void OnTestSent(HTTPResponse response, any value)
{
	int userid = view_as<int>(value);
	int status = view_as<int>(response.Status);
	char msg[320];

	if (response.Status == HTTPStatus_OK || response.Status == HTTPStatus_NoContent)
	{
		FormatEx(msg, sizeof(msg), "[LilacDiscord] SUCCESS: Discord accepted the test message (HTTP %d). Check your channel.", status);
		ReportTest(userid, msg);
		return;
	}

	char reason[128];
	reason[0] = '\0';

	JSON data = response.Data;
	if (data != null)
	{
		JSONObject obj = view_as<JSONObject>(data);
		if (obj.HasKey("message"))
			obj.GetString("message", reason, sizeof(reason));
		delete data;
	}

	char hint[128];
	switch (status)
	{
		case 0:   strcopy(hint, sizeof(hint), "No response. Server can't reach discord.com (firewall/DNS) or ripext failed.");
		case 400: strcopy(hint, sizeof(hint), "Bad request. The payload was rejected by Discord.");
		case 401: strcopy(hint, sizeof(hint), "Webhook token is wrong. Re-copy the full webhook URL.");
		case 403: strcopy(hint, sizeof(hint), "Forbidden. The webhook was blocked or lacks permission.");
		case 404: strcopy(hint, sizeof(hint), "Webhook not found. It was probably deleted, create a new one.");
		case 429: strcopy(hint, sizeof(hint), "Rate limited by Discord. Wait a bit and try again.");
		default:  strcopy(hint, sizeof(hint), "Unexpected response from Discord.");
	}

	FormatEx(msg, sizeof(msg), "[LilacDiscord] FAILED (HTTP %d): %s%s%s", status, hint, reason[0] != '\0' ? " Discord says: " : "", reason);
	ReportTest(userid, msg);
	LogError("%s", msg);
}

/* Print to whoever ran the test (server console if userid is 0), and always to the server console. */
void ReportTest(int userid, const char[] msg)
{
	PrintToServer("%s", msg);

	if (userid == 0)
		return;

	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client))
		PrintToChat(client, "%s", msg);
}

bool GetWebhookURL(char[] buffer, int maxlen)
{
	g_cvWebhookURL.GetString(buffer, maxlen);
	TrimString(buffer);

	if (buffer[0] == '\0' && g_cvFallbackWebhook != null)
	{
		g_cvFallbackWebhook.GetString(buffer, maxlen);
		TrimString(buffer);
	}

	return buffer[0] != '\0';
}

void AddField(JSONArray fields, const char[] name, const char[] value, bool inlineField)
{
	JSONObject field = new JSONObject();
	field.SetString("name", name);
	if (value[0] != '\0')
		field.SetString("value", value);
	else
		field.SetString("value", "-");
	field.SetBool("inline", inlineField);
	fields.Push(field);
	delete field;
}

/* Prevent mentions (@everyone/@here/@user) and broken markdown from player names. */
void SanitizeForDiscord(char[] text, int maxlen)
{
	ReplaceString(text, maxlen, "@", "＠"); /* full-width '@' */
	ReplaceString(text, maxlen, "\\", "\\\\");
	ReplaceString(text, maxlen, "`", "\\`");
	ReplaceString(text, maxlen, "*", "\\*");
	ReplaceString(text, maxlen, "_", "\\_");
	ReplaceString(text, maxlen, "~", "\\~");
	ReplaceString(text, maxlen, "|", "\\|");
	ReplaceString(text, maxlen, ">", "\\>");
}

bool IsNumeric(const char[] str)
{
	for (int i = 0; str[i] != '\0'; i++)
	{
		if (str[i] < '0' || str[i] > '9')
			return false;
	}
	return true;
}

bool IsValidClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client));
}
