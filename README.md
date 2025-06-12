# DMCTV Stats
[![DMCTV.NET](https://www.compute32.com/theme/dmctv.webp)](https://www.dmctv.net)

This is an AMX Mod X plugin developed for the DMCTV server which uploads player statistics to our website via an SQL database. Our website then uses a php backend to parse and display this data.

## Features

- Separate kill and death fields for both bots and players
- Tracks time played in seconds
- Uploads last known in-game player username, uses SteamID to structure database
- Uploads kill count for all weapons so remote server can track player's favorite weapon
- Uses asynchronous SQL queries to mitigate game server lag.

## Requirements

- AMX Mod X (tested on 1.8.2, might work on other versions)
- SQL database with the following structure:

```sql
CREATE TABLE IF NOT EXISTS player_stats (
    steamid VARCHAR(32) NOT NULL PRIMARY KEY,
    last_username VARCHAR(32) NOT NULL DEFAULT '',
    time_played INT UNSIGNED NOT NULL DEFAULT 0,
    kills INT UNSIGNED NOT NULL DEFAULT 0,
    bot_kills INT UNSIGNED NOT NULL DEFAULT 0,
    deaths INT UNSIGNED NOT NULL DEFAULT 0,
    bot_deaths INT UNSIGNED NOT NULL DEFAULT 0,
    axe_kills INT UNSIGNED NOT NULL DEFAULT 0,
    shotgun_kills INT UNSIGNED NOT NULL DEFAULT 0,
    doubleshotgun_kills INT UNSIGNED NOT NULL DEFAULT 0,
    nailgun_kills INT UNSIGNED NOT NULL DEFAULT 0,
    supernail_kills INT UNSIGNED NOT NULL DEFAULT 0,
    grenadelauncher_kills INT UNSIGNED NOT NULL DEFAULT 0,
    rocketlauncher_kills INT UNSIGNED NOT NULL DEFAULT 0,
    lightninggun_kills INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## Config File

Config should be placed at `/addons/amxmodx/configs/dmctv_stats.cfg`

- `db_host` - Database IP
- `db_user` - Database username
- `db_pass` - Database password
- `db_name` - Database name

[![AMX Mod X](http://www.amxmodx.org/images/amxx.jpg)](http://www.amxmodx.org/)
