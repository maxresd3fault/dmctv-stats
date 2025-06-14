/*
	* DMC TV STATS
	* Tracks kills & deaths (human/bot), play time, and weapon-specific stats in Deathmatch Classic.
	* Pushes data to an SQL server asynchronously to avoid lag.
	* Developed for DMCTV.NET by maxresdefault.
*/
#pragma semicolon 1

#include <amxmodx>
#include <amxmisc>
#include <sqlx>

#define MAX_PLAYERS 32
#define MAX_DMC_WEAPS 8

new g_sql_host[64];
new g_sql_user[64];
new g_sql_pass[64];
new g_sql_db[64];

new g_last_username[MAX_PLAYERS + 1][32];
new g_time_played[MAX_PLAYERS + 1];
new g_last_weapon[MAX_PLAYERS + 1][32];
new g_kills[MAX_PLAYERS + 1];
new g_bot_kills[MAX_PLAYERS + 1];
new g_deaths[MAX_PLAYERS + 1];
new g_bot_deaths[MAX_PLAYERS + 1];
new g_weapon_usage[MAX_PLAYERS + 1][MAX_DMC_WEAPS];

new bool:g_skip_player[MAX_PLAYERS + 1] = false;
new bool:g_upload_on_dcon = false;

new g_active_queries = 0;
new Handle:g_sql_tuple;

static const dmc_weapons[MAX_DMC_WEAPS][] = {
	"axe", "shotgun", "doubleshotgun", "nailgun", "supernail", "grenadelauncher", "rocketlauncher", "lightninggun"
}; // Internally DMC uses some names like 'axe' instead of 'crowbar'

public plugin_init() {
	register_plugin("DMC TV Stats", "R2.0", "maxresdefault");
	register_event("DeathMsg", "client_death", "a");
	register_event("CurWeapon", "event_curweapon", "be", "1=1");
	
	if (!load_sql_config()) {
		log_amx("[DMCTV Stats]: Failed to load SQL config");
		pause("c");
		return;
	}
	
	g_sql_tuple = SQL_MakeDbTuple(g_sql_host, g_sql_user, g_sql_pass, g_sql_db);
	set_task(1.0, "setup_timer", 1); // We have to wait for CVAR's to init. I hate AMX
}

public plugin_end() { // Pop out a warning just in case something goes wrong
	if (g_active_queries > 0) {
		log_amx("[DMCTV Stats]: Warning! There are still %d active queries during plugin shutdown!", g_active_queries);
	}
}

public setup_timer() {
	g_upload_on_dcon = true; // A slight buffer before we upload anything
	new g_time_limit = ((get_cvar_num("mp_timelimit") * 60) - 2);
	set_task(float(g_time_limit), "round_end", 1);
}

public round_end() {
	new g_time_left = get_timeleft(); // Check for map extension
	if (g_time_left > 0) {
		set_task((float(g_time_left) + 1.0), "round_end", 1); // Add a small buffer to make everything feel more consistent
	} else {
		g_upload_on_dcon = false; // Disable player disconnect uploads
		new players[32], count;
		get_players(players, count, "ch"); // Only reliable way to get list of all human id's
		
		for (new i = 0; i < count; i++) {
			new id = players[i];
			new session_time = get_user_time(id, 0);
			if (session_time > 0) {
				g_time_played[id] += session_time;
			}
			
			save_stats(id);
		}
	}
}

load_sql_config() { // Load DB info from config
	new path[128];
	get_configsdir(path, charsmax(path));
	format(path, charsmax(path), "%s/dmctv_stats.cfg", path);
	
	if (!file_exists(path)) {
		log_amx("[DMCTV Stats]: SQL config file not found: %s", path);
		return 0;
	}

	new line[128], key[32], value[96];
	new fp = fopen(path, "rt");
	
	while (!feof(fp)) {
		fgets(fp, line, charsmax(line));
		trim(line);
		if (line[0] == ';' || line[0] == 0) continue;
		
		parse(line, key, charsmax(key), value, charsmax(value));
		
		if (equal(key, "db_host")) copy(g_sql_host, charsmax(g_sql_host), value);
		else if (equal(key, "db_user")) copy(g_sql_user, charsmax(g_sql_user), value);
		else if (equal(key, "db_pass")) copy(g_sql_pass, charsmax(g_sql_pass), value);
		else if (equal(key, "db_name"))   copy(g_sql_db, charsmax(g_sql_db), value);
	}
	
	fclose(fp);
	return 1;
}

public client_putinserver(id) {
	if (!is_user_bot(id)) {
		get_user_name(id, g_last_username[id], charsmax(g_last_username[]));
		
		if (!is_username_safe(g_last_username[id])) {
			g_skip_player[id] = true;
			new data[1];
			data[0] = id;
			set_task(5.0, "warn_bad_username", id, data, sizeof(data)); // Add a delay to wait for client to load in
		}
	}
}

public client_disconnect(id) {
	if (g_upload_on_dcon && !is_user_bot(id)) {
		new session_time = get_user_time(id, 0);
		if (session_time > 0) {
			g_time_played[id] += session_time;
		}
		
		save_stats(id);
	}
}

public bool:is_username_safe(const username[]) { // We don't want weird usernames to screw up SQL queries
	if (username[0] == 0) {
		return false;
	}
	
	for (new i = 0; username[i] != 0; i++) {
		new c = username[i];
		
		if (c < 32 || c > 126) {
			return false;
		}
		
		if (c == '\'' || c == '"' || c == ';' || c == '\\') {
			return false;
		}
	}
	return true;
}

public warn_bad_username(data[]) {
	new id = data[0];
	client_print(id, print_chat, "[DMC TV Stats]: Your username contains invalid characters, your stats will not be uploaded");
}

reset_stats(id) {
	g_last_username[id][0] = 0;
	g_skip_player[id] = false;
	g_kills[id] = 0;
	g_bot_kills[id] = 0;
	g_deaths[id] = 0;
	g_bot_deaths[id] = 0;
	arrayset(g_weapon_usage[id], 0, MAX_DMC_WEAPS);
}

public event_curweapon(id) { // DMC does not provide weapon used in client_death read_data(4) so we must do this bullshit
	if (!is_user_connected(id) || is_user_bot(id)) {
		return;
	}
	
	new weaponID = read_data(2);
	new szFull[32];
	
	if (weaponID == 64) {
		copy(szFull, charsmax(szFull), "rocketlauncher"); // Insane
	} else if (weaponID == 128) {
		copy(szFull, charsmax(szFull), "lightninggun"); // Also insane
	} else if (weaponID == 32) {
		copy(szFull, charsmax(szFull), "grenadelauncher"); // Also also insane
	} else if (weaponID > 0 && weaponID < 32) {
		get_weaponname(weaponID, szFull, charsmax(szFull));
		replace(szFull, charsmax(szFull), "weapon_", "");
	} else {
		return;
	}
	
	copy(g_last_weapon[id], charsmax(g_last_weapon[]), szFull);
}

public client_death() {
	new killer = read_data(1);
	new victim = read_data(2);
	
	if ((killer <= 0 || killer > MAX_PLAYERS) && !is_user_bot(victim)) { // If killer is out of bounds must be suicide
		client_suicide(victim);
		return;
	} else if (is_user_bot(killer) && is_user_bot(victim)) { // No need to run this code if it's just bots
		return;
	}
	
	if (!is_user_bot(victim)) {
		if (is_user_bot(killer)) {
			g_bot_deaths[victim]++;
		} else if (killer == victim) {
			client_suicide(victim); // Call our suicide handler when player kills themself
			return;
		} else {
			g_deaths[victim]++;
		}
	}
	
	if (!is_user_bot(killer)) {
		if (is_user_bot(victim)) {
			g_bot_kills[killer]++;
		} else if (victim != killer) { // If it is a suicide don't increase our player kill count
			g_kills[killer]++;
		}
	}
	process_weapon_usage(killer, g_last_weapon[killer]);
}

public client_suicide(id) {
	new players[32], humanCount;
	get_players(players, humanCount, "ch");
	
	if (humanCount > 1) { // When other players are connected affect the player KDR
		g_deaths[id]++;
	} else if (humanCount == 1) { // When playing solo affect bot KDR
		g_bot_deaths[id]++;
	}
}

public process_weapon_usage(id, const szWeap[]) {
	new idx = get_dmc_weapon_index(szWeap);
	if (idx != -1) g_weapon_usage[id][idx]++;
}

public get_dmc_weapon_index(const name[]) {
	for (new i = 0; i < MAX_DMC_WEAPS; i++) {
		if (equal(name, dmc_weapons[i])) return i;
	}
	return -1;
}

save_stats(id) {
	if (g_skip_player[id]) {
		return;
	}
	log_amx("[DMC TV Stats]: Uploading data for: %s", g_last_username[id]);
	
	new steamid[32];
	get_user_authid(id, steamid, charsmax(steamid));
	if (equali(steamid, "UNKNOWN") || steamid[0] == 0) { // If player is using pirated copy of game we shouldn't add them to database since they have no SteamID
		return;
	}
	
	new query[1024];
	new weapon_fields[512], weapon_values[512], weapon_updates[512];
	new data[1];
	data[0] = id;
	
	weapon_fields[0] = 0;
	weapon_values[0] = 0;
	weapon_updates[0] = 0;
	
	new bool:first = true;
	for (new i = 0; i < MAX_DMC_WEAPS; i++) {
		if (first) {
			format(weapon_fields, charsmax(weapon_fields), "%s_kills", dmc_weapons[i]);
			format(weapon_values, charsmax(weapon_values), "%d", g_weapon_usage[id][i]);
			format(weapon_updates, charsmax(weapon_updates), "%s_kills = %s_kills + %d", dmc_weapons[i], dmc_weapons[i], g_weapon_usage[id][i]);
			first = false;
		} else {
			format(weapon_fields, charsmax(weapon_fields), "%s, %s_kills", weapon_fields, dmc_weapons[i]);
			format(weapon_values, charsmax(weapon_values), "%s, %d", weapon_values, g_weapon_usage[id][i]);
			format(weapon_updates, charsmax(weapon_updates), "%s, %s_kills = %s_kills + %d", weapon_updates, dmc_weapons[i], dmc_weapons[i], g_weapon_usage[id][i]);
		}
	}
	
	formatex(query, charsmax(query),
		"INSERT INTO player_stats (steamid, last_username, time_played, kills, bot_kills, deaths, bot_deaths, %s) VALUES ('%s', '%s', %d, %d, %d, %d, %d, %s) ON DUPLICATE KEY UPDATE last_username = '%s', time_played = time_played + %d, kills = kills + %d, bot_kills = bot_kills + %d, deaths = deaths + %d, bot_deaths = bot_deaths + %d, %s;",
		weapon_fields,
		steamid, g_last_username[id], g_time_played[id], g_kills[id], g_bot_kills[id], g_deaths[id], g_bot_deaths[id], weapon_values,
		g_last_username[id], g_time_played[id], g_kills[id], g_bot_kills[id], g_deaths[id], g_bot_deaths[id], weapon_updates
	);
	g_active_queries++;
	SQL_ThreadQuery(g_sql_tuple, "query_callback", query, data, sizeof(data));
}

public query_callback(FailState, Handle:query, error[], errcode, data[], datasize) {
	g_active_queries--;
	new id = data[0];
	if (FailState != TQUERY_SUCCESS) {
		log_amx("[DMCTV Stats]: SQL Error: %s", error);
	} else if (!g_upload_on_dcon) { // Print upload messages during talktime
		client_print(0, print_chat, "[DMC TV Stats]: Uploaded data for: %s", g_last_username[id]); // Print upload messages during talktime
	}
	reset_stats(id);
}
