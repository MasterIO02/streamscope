package src;

import sys.FileSystem;
import src.Util.toTwoDigits;
import src.ProcessRecording;
import src.ChatDownloader;
import src.Config;
import src.Types;
import sys.io.Process;
import sys.thread.Thread;
import sys.io.File;
import haxe.Json;

using StringTools;

var streamlinkProcesses:Map<String, Process> = new Map();

function startRecording(streamerInfo:StreamerStatus) {
	Sys.println('\nStarting record of ${streamerInfo.streamer_username}');

	var streamStartDate = streamerInfo.started_at.split("T")[0];
	var streamStartTime = streamerInfo.started_at.split("T")[1].replace("Z", "").split(":");
	var streamStartHours = streamStartTime[0];
	var streamStartMinutes = streamStartTime[1];
	var streamStartSeconds = streamStartTime[2];

	var now = Date.now();
	var recordStartDate = '${now.getFullYear()}-${toTwoDigits(now.getUTCMonth() + 1)}-${toTwoDigits(now.getUTCDate())}';
	var recordStartHours = toTwoDigits(now.getUTCHours());
	var recordStartMinutes = toTwoDigits(now.getUTCMinutes());
	var recordStartSeconds = toTwoDigits(now.getUTCSeconds());

	var filename = '${streamerInfo.streamer_username} - start ${streamStartDate} ${streamStartHours}h${streamStartMinutes}m${streamStartSeconds}s - rec ${recordStartDate} ${recordStartHours}h${recordStartMinutes}m${recordStartSeconds}s';
	var path = '${config.processed_path}/${streamerInfo.streamer_username}';
	if (!FileSystem.exists(path)) {
		FileSystem.createDirectory(path);
	}

	var recordStartFullDate = '${recordStartDate}T${recordStartHours}:${recordStartMinutes}:${recordStartSeconds}Z';

	var recordingInfo = {
		streamer_username: streamerInfo.streamer_username,
		streamer_display_username: streamerInfo.streamer_display_name,
		titles: [{date: recordStartFullDate, title: streamerInfo.title}],
		stream_started_at: streamerInfo.started_at,
		record_started_at: recordStartFullDate,
		game_ids: [{date: recordStartFullDate, game_id: streamerInfo.game_id}],
		game_names: [{date: recordStartFullDate, game_id: streamerInfo.game_name}],
		language: streamerInfo.language,
		tag_ids: streamerInfo.tag_ids,
		is_mature: streamerInfo.is_mature
	}

	var recordingInfoFile = File.write('${path}/$filename.json', false);
	recordingInfoFile.writeString(Json.stringify(recordingInfo), UTF8);
	recordingInfoFile.close();

	if (config.download_chat == true) {
		streamerInfo.chat_thread = Thread.create(runChatDownloader.bind(streamerInfo.streamer_username, filename));
	}

	if (!streamerInfo.chat_only) {
		// normal mode: also start the streamlink video recording process
		streamerInfo.streamlink_thread = Thread.create(streamlinkProcess.bind(streamerInfo, filename));
	}

	return filename;
}

/**
 * Run a streamlink thread
 * @param filename filename of the output video
 */
function streamlinkProcess(streamerInfo:StreamerStatus, filename:String) {
	final streamlinkCommand = 'streamlink --twitch-disable-hosting --twitch-disable-ads --twitch-disable-reruns twitch.tv/${streamerInfo.streamer_username} ${config.quality} -o "${config.temp_path}/$filename.${config.video_container}"';
	final streamlink = new Process(streamlinkCommand);
	streamlinkProcesses.set(streamerInfo.streamer_username, streamlink);

	var streamlinkEndedCleanly = false;
	while (streamlink.exitCode(false) == null) {
		try {
			var line = streamlink.stdout.readLine();
			if (line.contains("Stream ended")) {
				streamlinkEndedCleanly = true;
				Sys.println('Stream of ${streamerInfo.streamer_username} ended cleanly');
				killStreamlink(streamerInfo);
			}
		} catch (e:haxe.io.Eof) {}
	}

	if (!streamlinkEndedCleanly) {
		// check if the process was externally killed (e.g. streamer removed from list)
		if (streamlinkProcesses.exists(streamerInfo.streamer_username)) {
			Sys.println('Streamlink for ${streamerInfo.streamer_username} was killed externally');
			killStreamlink(streamerInfo);
		} else {
			Sys.println('Streamlink for ${streamerInfo.streamer_username} closed abruptly, processing the output video anyway');
			killStreamlink(streamerInfo); // we will try to kill it to make sure there are no zombie processes
		}
	}

	streamlinkProcesses.remove(streamerInfo.streamer_username);
	streamlink.close();

	processRecording('$filename.${config.video_container}');
}

/**
 * Update the JSON file arrays containing stream info
 * @param itemType what to update?
 * @param newItem what to push in the field to update?
 * @param filename name of the file to update
 * @param path path where the json files are located
 */
function updateStreamInfo(itemType:String, newItem:String, filename:String, path:String) {
	var now = Date.now();
	var currentDate = '${now.getFullYear()}-${toTwoDigits(now.getUTCMonth() + 1)}-${toTwoDigits(now.getUTCDate())}T${toTwoDigits(now.getUTCHours())}:${toTwoDigits(now.getUTCMinutes())}:${toTwoDigits(now.getUTCSeconds())}Z';

	var currentStreamInfoContent = File.getContent('$path/$filename.json');
	var currentStreamInfo = Json.parse(currentStreamInfoContent);
	switch (itemType) {
		case "title":
			currentStreamInfo.titles.push({title: newItem, date: currentDate});
		case "game_id":
			currentStreamInfo.game_ids.push({game_id: newItem, date: currentDate});
		case "game_name":
			currentStreamInfo.game_names.push({game_name: newItem, date: currentDate});
	}

	var newStreamInfoFile = File.write('$path/$filename.json', false);
	newStreamInfoFile.writeString(Json.stringify(currentStreamInfo), UTF8);
	newStreamInfoFile.close();

	if (config.debug) trace("Updated stream info");
}

function killStreamlink(streamerInfo:StreamerStatus) {
	// Try using the stored process handle first
	var storedProcess = streamlinkProcesses.get(streamerInfo.streamer_username);
	if (storedProcess != null) {
		try {
			storedProcess.kill();
		} catch (e) {
			if (config.debug) trace('Failed to kill stored process: $e');
		}
	}

	// also use pgrep as fallback, since streamlink spawns child processes that the Process handle doesn't directly manage
	var pidList:Array<String> = [];
	final pgrep = new Process('pgrep -f "twitch.tv/${streamerInfo.streamer_username}"');
	while (pgrep.exitCode(false) == null) {
		try {
			pidList.push(pgrep.stdout.readLine());
		} catch (e:haxe.io.Eof) {}
	}
	pgrep.close();
	if (config.debug) trace("pidList for killing streamlink is " + pidList);

	for (processId in pidList) {
		var killProcess = new Process('kill $processId');
		killProcess.exitCode(true);
		killProcess.close();
	}
}
