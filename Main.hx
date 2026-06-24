import DateTools;
import sys.io.File;
import sys.FileSystem;
import sys.thread.Thread;
import haxe.Timer;
import haxe.Http;
import haxe.Json;
import src.ProcessRecording;
import src.Recording;
import src.Config;
import src.Util;
import src.Types;

using StringTools;
using Std;

// Color codes in terminal
final COLOR_RESET = "\033[m";
final COLOR_RED = "\033[38;5;1m";
final COLOR_GREEN = "\033[38;5;2m";

// currentlyWatchedStreamers is the array of the streamers names that are currently watched, without modifiers because this list is passed to the twitch api
var currentlyWatchedStreamers:Array<String> = [];

// status contains infos about watched streamers
var status:Array<StreamerStatus> = [];

class Main {
	static macro function getDefine(key:String):haxe.macro.Expr {
		return macro $v{haxe.macro.Context.definedValue(key)};
	}

	static macro function getBuildTime() {
		return macro $v{DateTools.format(Date.now(), "%Y-%m-%d at %H:%M:%S")};
	}

	static public function main() {
		var version = getDefine("version");
		var buildDate = getBuildTime();
		Sys.println('Starting streamscope v${version == null ? " dev" : version} built on $buildDate');

		// generate config if it does not exist
		if (!FileSystem.exists("./config.json")) {
			var configToWrite = File.write("./config.json");
			configToWrite.writeString(freshConfig);
			configToWrite.close();
			Sys.println("Generated a new configuration file (config.json), you need to check and tweak the values in it before using streamscope.");
			Sys.exit(0);
		}

		// init config
		try {
			config = Json.parse(File.getContent("./config.json"));
		} catch (e) {
			Sys.println('Invalid configuration file: $e');
			Sys.exit(1);
		}

		// check config values
		if (!FileSystem.exists(config.temp_path)) return Sys.println("The temp file path in the configuration file is invalid.");
		if (!FileSystem.exists(config.processed_path)) return Sys.println("The processed file path in the configuration file is invalid.");
		if (!FileSystem.exists(config.problematic_path)) return Sys.println("The problematic file path in the configuration file is invalid.");

		// check if no path for the list of streamers to watch is supplied
		if (Sys.args()[0] == null) return Sys.println("No path selected for the list of streamers to record.");
		var listPath = Sys.args()[0];

		// check if the list exists
		if (!FileSystem.exists(listPath)) return Sys.println("The supplied list of streamers to record does not exist.");

		// check that required external tools are available
		if (!isCommandAvailable("streamlink", "--version")) return Sys.println("streamlink is not installed or not in PATH.");
		if (!isCommandAvailable("ffmpeg", "-version")) return Sys.println("ffmpeg is not installed or not in PATH.");

		// check and process leftover streams in another thread
		Thread.create(checkLeftovers);

		refreshStreamers(listPath);

		Sys.println("Getting Twitch client credentials...");
		var credentials = getAccessToken();
		if (credentials == "ERROR") {
			Sys.println("Failed to get Twitch client credentials after all attempts, exiting.");
			Sys.exit(1);
		}
		if (config.debug) trace('The Twitch access token is $credentials');
		Sys.println("Got Twitch credentials!");

		// main loop
		var timer = new Timer(config.query_time * 1000);
		timer.run = () -> {
			refreshStreamers(listPath);

			var twitchResponse = checkStreamersOnline(currentlyWatchedStreamers, credentials);

			// twitch response array values:
			// {status: "OK", ...}: List of online streamers, empty if nobody is online
			// {status: "ERR_UNKNOWN"}: Unknown error
			// {status: "ERR_REGEN_CREDS"}: Need to regen the credentials, got status 401

			if (twitchResponse.contains({status: "ERR_REGEN_CREDS"})) {
				Sys.println("Got error 401, need to regen the credentials.");
				var newCredentials = getAccessToken();
				if (newCredentials != "ERROR") {
					credentials = newCredentials;
					if (config.debug) trace('The regenerated Twitch access token is $credentials');
					Sys.println("Regenerated Twitch credentials!");
				} else {
					Sys.println("Failed to regenerate Twitch credentials after all attempts.");
				}
			} else if (twitchResponse.contains({status: "ERR_UNKNOWN"})) {
				Sys.println('Got an unknown error when fetching online streamers, retrying in ${config.query_time} seconds.');
			} else {
				// onlineStreamersNames is used to set online/offline status of the streamers in the loop
				var onlineStreamersNames:Array<String> = [];

				for (streamer in twitchResponse) {
					onlineStreamersNames.push(streamer.user_login.toLowerCase());
					for (streamerStatus in status) {
						if (streamerStatus.streamer_input_username.toLowerCase() == streamer.user_login) {
							if (streamerStatus.online == false) {
								// if streamer just got online we start recording
								streamerStatus.streamer_username = streamer.user_login;
								streamerStatus.streamer_display_name = streamer.user_name;
								streamerStatus.online = true;

								// using UTC date
								var now = Date.now();
								streamerStatus.recording_since = '${now.getFullYear()}-${toTwoDigits(now.getUTCMonth() + 1)}-${toTwoDigits(now.getUTCDate())} ${toTwoDigits(now.getUTCHours())}:${toTwoDigits(now.getUTCMinutes())}:${toTwoDigits(now.getUTCSeconds())}';

								streamerStatus.title = streamer.title;
								streamerStatus.started_at = streamer.started_at;
								streamerStatus.game_id = streamer.game_id;
								streamerStatus.game_name = streamer.game_name;
								streamerStatus.language = streamer.language;
								streamerStatus.tag_ids = streamer.tag_ids;
								streamerStatus.is_mature = streamer.is_mature;
								var filename:String = startRecording(streamerStatus);
								// getting the filename here to be able to send it to updateStreamInfo() when the title of the stream changes for example
								streamerStatus.filename = filename;
								break;
							} else {
								// if the streamer is already online
								var path = '${config.processed_path}/${streamer.user_login}';
								if (streamer.title.toString() != streamerStatus.title.toString()) {
									updateStreamInfo("title", streamer.title, streamerStatus.filename, path);
									streamerStatus.title = streamer.title;
								}
								if (streamer.game_id.toString() != streamerStatus.game_id.toString()) {
									updateStreamInfo("game_id", streamer.game_id, streamerStatus.filename, path);
									streamerStatus.game_id = streamer.game_id;
								}
								if (streamer.game_name.toString() != streamerStatus.game_name.toString()) {
									updateStreamInfo("game_name", streamer.game_name, streamerStatus.filename, path);
									streamerStatus.game_name = streamer.game_name;
								}
								break;
							}
						}
					}
				}

				// mark streamers that went offline and handle cleanup
				for (streamerStatus in status) {
					if (streamerStatus.online == true) {
						if (!onlineStreamersNames.contains(streamerStatus.streamer_username.toLowerCase())) {
							streamerStatus.online = false;

							if (streamerStatus.chat_thread != null) {
								streamerStatus.chat_thread.sendMessage("end");
								streamerStatus.chat_thread = null;
							}

							// streamlink thread will exit on its own after the process ends
							streamerStatus.streamlink_thread = null;
						}
					}
				}

				// log current status for watched streamers
				Sys.println('\n--- ${Date.now().toString()} ---');
				for (streamer in status) {
					if (streamer.online) {
						var streamingSince = '${streamer.started_at.split("T")[0]} ${streamer.started_at.split("T")[1].replace("Z", "")}';
						var log = '${streamer.streamer_username}: ${COLOR_GREEN}ONLINE${COLOR_RESET} since ${streamingSince}, currently on ${streamer.game_name} - ';
						if (streamer.chat_only) {
							log += 'Recording chat since ${streamer.recording_since}';
						} else {
							if (streamlinkProcesses.exists(streamer.streamer_username)) {
								log += 'Recording since ${streamer.recording_since}';
							} else if (!streamer.was_online) {
								log += 'Not recording (starting up)';
							} else {
								log += 'Not recording (process may have been killed)';
							}
						}
						Sys.println(log);
					} else {
						if (streamlinkProcesses.exists(streamer.streamer_username)) {
							Sys.println('${streamer.streamer_input_username}: ${COLOR_RED}OFFLINE${COLOR_RESET} - Waiting for streamlink to stop...');
						} else {
							Sys.println('${streamer.streamer_input_username}: ${COLOR_RED}OFFLINE${COLOR_RESET}');
						}
					}
				}
				// newline
				Sys.println('');

				// update was_online for next tick
				for (streamerStatus in status) {
					streamerStatus.was_online = streamerStatus.online;
				}
			}
		}
	}

	static public function getAccessToken():String {
		var maxRetries = 5;
		for (attempt in 0...maxRetries) {
			var result:String = null;
			var twitch = new Http('https://id.twitch.tv/oauth2/token?client_id=${config.twitch_id}&client_secret=${config.twitch_secret}&grant_type=client_credentials');
			twitch.onData = s -> result = Json.parse(s).access_token;
			twitch.onError = e -> {
				Sys.println('Error when trying to get the Twitch client credentials: $e');
				result = "ERROR";
			};
			twitch.request(true);
			if (result != "ERROR") return result;
			if (attempt < maxRetries - 1) {
				Sys.println('Failed to get Twitch client credentials, retrying in 10 seconds... (${attempt + 1}/$maxRetries)');
				Sys.sleep(10);
			}
		}
		return "ERROR";
	}

	static public function checkStreamersOnline(streamers:Array<String>, credentials:String):Array<OnlineStreamer> {
		var streamersQuery = "";
		for (streamer in streamers) {
			if (streamersQuery == "") {
				streamersQuery += '?user_login=$streamer';
			} else {
				streamersQuery += '&user_login=$streamer';
			}
		}

		var result:Array<OnlineStreamer> = [];
		var twitch = new Http('https://api.twitch.tv/helix/streams$streamersQuery');
		twitch.addHeader("Client-ID", config.twitch_id);
		twitch.addHeader("Authorization", 'Bearer $credentials');
		twitch.onData = data -> {
			// here twitch sends us an array of objects in the data property of the online streamers.
			// offline streamers aren't present in there.

			var streamersInfo:Array<{
				id:String,
				user_id:String,
				user_login:String,
				user_name:String,
				game_id:String,
				game_name:String,
				title:String,
				started_at:String,
				language:String,
				tag_ids:String,
				is_mature:String
			}> = Json.parse(data).data;

			for (streamerInfo in streamersInfo) {
				result.push({
					status: "OK",
					stream_id: streamerInfo.id,
					user_id: streamerInfo.user_id,
					user_login: streamerInfo.user_login,
					user_name: streamerInfo.user_name,
					game_id: streamerInfo.game_id,
					game_name: streamerInfo.game_name,
					title: streamerInfo.title,
					started_at: streamerInfo.started_at,
					language: streamerInfo.language,
					tag_ids: streamerInfo.tag_ids,
					is_mature: streamerInfo.is_mature
				});
			}
		}
		twitch.onError = data -> {
			if (data == "Http Error #401") {
				result = [{status: "ERR_REGEN_CREDS"}];
			} else {
				Sys.println('Unknown error when trying to fetch online streamers: $data');
				result = [{status: "ERR_UNKNOWN"}];
			}
		}
		twitch.request();
		return result;
	}

	static public function refreshStreamers(listPath) {
		// refreshStreamers is called when starting the app and for each loop iteration, to check if a new streamer is supplied to the list in real time

		var newWatchedStreamers:Array<String> = [];
		var lines = File.getContent(listPath).split("\n");

		// filter comments and empty lines (iterate in reverse to safely remove while iterating)
		var i = lines.length - 1;
		while (i >= 0) {
			var line = lines[i];
			if (line.startsWith("//") || line.trim() == "") lines.remove(line);
			i--;
		}

		// find streamers to start watching
		// every line here is a streamer name in the list, eventually with modifiers (eg chat:streamer) (NOT IMPLEMENTED)
		for (line in lines) {
			var isChatOnly = line.split(":")[0] == "chat" ? true : false;
			var streamerInputUsername = isChatOnly ? line.split(":")[1] : line;
			newWatchedStreamers.push(streamerInputUsername);
			if (!currentlyWatchedStreamers.contains(streamerInputUsername)) {
				Sys.println('Starting to watch for $streamerInputUsername');
				status.push({
					streamer_input_username: streamerInputUsername,
					streamer_username: "",
					streamer_display_name: "",
					online: false,
					was_online: false,
					chat_only: isChatOnly,
					recording_since: "",
					filename: "",
					title: "",
					started_at: "",
					game_id: "",
					game_name: "",
					language: "",
					tag_ids: "",
					is_mature: ""
				});
			}
		}

		// find streamers to stop watching
		for (streamer in currentlyWatchedStreamers) {
			if (!newWatchedStreamers.contains(streamer)) {
				for (watchedStreamer in status) {
					if (watchedStreamer.streamer_input_username == streamer) {
						if (watchedStreamer.online == true) {
							Sys.println('Stopping recording for $streamer.');
							killStreamlink(watchedStreamer);
							if (watchedStreamer.chat_thread != null) {
								watchedStreamer.chat_thread.sendMessage("end");
								watchedStreamer.chat_thread = null;
							}
							watchedStreamer.streamlink_thread = null;
						} else {
							Sys.println('Stopping to watch for $streamer.');
						}
						status.remove(watchedStreamer);
						break;
					}
				}
			}
		}

		currentlyWatchedStreamers = newWatchedStreamers;
	}

	static public function isCommandAvailable(command:String, versionFlag:String):Bool {
		var process = new sys.io.Process(command, [versionFlag]);
		var exitCode = process.exitCode(true);
		process.close();
		return exitCode == 0;
	}
}
