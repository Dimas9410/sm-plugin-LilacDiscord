# Lilac Discord Alert

SourceMod plugin that sends [Little Anti-Cheat (Lilac)](https://github.com/J-Tanzanite/Little-Anti-Cheat) detections and bans to a Discord webhook.

## Installation

1. Install [Little Anti-Cheat (Lilac)](https://github.com/J-Tanzanite/Little-Anti-Cheat).
2. Install extension [SM-RIPExt](https://github.com/ErikMinekus/sm-ripext).
3. Upload `lilac_discord.smx` to `addons/sourcemod/plugins/`.
4. Restart the server or run `sm plugins load lilac_discord`.
5. Edit `cfg/sourcemod/lilac_discord.cfg` and fill in your webhook URL.

## ConVars

| ConVar | Default | Description |
|---|---|---|
| `sm_lilac_discord_enable` | `1` | Enable Lilac alerts to Discord (1 = enabled) |
| `sm_lilac_discord_webhook` | `""` | Discord webhook URL for Lilac alerts. Leave empty to use `sm_discord_webhook` (DiscordChat) |
| `sm_lilac_discord_detected` | `1` | Send an alert when a player is detected / flagged |
| `sm_lilac_discord_banned` | `1` | Send an alert when Lilac is about to ban a player |
| `sm_lilac_discord_cooldown` | `30.0` | Minimum delay (seconds) between alerts for the same player and cheat type |
| `sm_lilac_discord_showip` | `0` | Show the player's IP in the alert (1 = yes) |
| `sm_lilac_discord_mentionrole` | `""` | Discord role ID to mention on alerts (empty = no mention) |
| `sm_lilac_discord_botname` | `Lilac Anti-Cheat` | Webhook sender name shown in Discord |
| `sm_lilac_discord_avatar` | *(logo URL)* | Webhook avatar image URL |
