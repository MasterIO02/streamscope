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

function runStreamlink(streamerInfo:StreamerStatus) {
	Sys.println('\nStarting record of ${streamerInfo.streamer_username}');

	var streamStartDate = streamerInfo.started_at.split("T")[0];
	var streamStartTime = streamerInfo.started_at.split("T")[1].replace("Z", "").split(":");
	var streamStartHours = streamStartTime[0];
	var streamStartMinutes = streamStartTime[1];
	var streamStartSeconds = streamStartTime[2];

	// This commented code is to get the record starting date in the local time. we will use the UTC time instead
	/*var recordStartDate = Date.now().toString().split(" ")[0]; // in local time!
		var recordStartTime = Date.now().toString().split(" ")[1].split(":");
		var recordStartHours = recordStartTime[0];
		var recordStartMinutes = recordStartTime[1];
		var recordStartSeconds = recordStartTime[2]; */

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

	// spawns a thread for the streamlink (and chat downloader) process and sends the required informations to start recording
	var chatDownloaderThread:Thread = Thread.current();
	if (config.download_chat == true) chatDownloaderThread = Thread.create(runChatDownloader.bind(streamerInfo.streamer_username, filename));

	Thread.create(streamlinkProcess.bind(streamerInfo, filename, path, '${recordStartDate}T${recordStartHours}:${recordStartMinutes}:${recordStartSeconds}Z',
		chatDownloaderThread));

	return filename;
}

// streamlink thread function
function streamlinkProcess(streamerInfo:StreamerStatus, filename:String, path:String, recordStartFullDate:String, chatDownloaderThread:Thread) {
	var recordingInfo = {
		streamer_username: streamerInfo.streamer_username,
		streamer_display_username: streamerInfo.streamer_display_name,
		// initiating the first title of the stream
		titles: [{date: recordStartFullDate, title: streamerInfo.title}],
		stream_started_at: streamerInfo.started_at,
		/*record_started_at: Date.now()
			.toString()
			.split(" ")
			.join("T") + "Z", 
			This is an incorrect date, because it's in local time. keeping this in case we want to make a switch to use local time instead of UTC
		 */
		record_started_at: recordStartFullDate,
		// initiating the first game_id of the stream
		game_ids: [{date: recordStartFullDate, game_id: streamerInfo.game_id}],
		// initiating the first game_name of the stream
		game_names: [{date: recordStartFullDate, game_id: streamerInfo.game_name}],
		language: streamerInfo.language,
		tag_ids: streamerInfo.tag_ids,
		is_mature: streamerInfo.is_mature
	}

	var recordingInfoFile = File.write('${path}/$filename.json', false);
	recordingInfoFile.writeString(Json.stringify(recordingInfo), UTF8);
	recordingInfoFile.close();

	final streamlinkCommand = 'streamlink --twitch-disable-hosting --twitch-disable-ads --twitch-disable-reruns twitch.tv/${streamerInfo.streamer_username} ${config.quality} -o "${config.temp_path}/$filename.${config.video_container}"';
	final streamlink = new Process(streamlinkCommand);

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
		Sys.println('Looks like streamlink for ${streamerInfo.streamer_username} closed abruptly, processing the output video anyway');
		killStreamlink(streamerInfo); // we will try to kill it to make sure there are no zombie processes
	}

	if (config.download_chat == true) {
		if (config.debug) trace("[DEBUG] Closing chat downloader, stream ended");
		chatDownloaderThread.sendMessage("end");
	}
	processRecording('$filename.${config.video_container}');
}

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

	if (config.debug) trace("[DEBUG] Updated stream info");
}

function killStreamlink(streamerInfo:StreamerStatus) {
	// when we run streamlink, it's actually ran in a process not managed by streamscope so we need to find it to kill it
	// we only have the pid of the process that runs streamlink (generally "sh")
	// it's an issue (feature?) with streamlink itself, not streamscope
	var pidList:Array<String> = [];
	final pgrep = new Process('pgrep -f "twitch.tv/${streamerInfo.streamer_username}"');
	while (pgrep.exitCode(false) == null) {
		try {
			pidList.push(pgrep.stdout.readLine());
		} catch (e:haxe.io.Eof) {}
	}
	if (config.debug) trace("pidList for killing streamlink is " + pidList);

	for (processId in pidList) {
		var killProcess = new Process('kill $processId');
		killProcess.exitCode(true);
		killProcess.close();
	}
}
