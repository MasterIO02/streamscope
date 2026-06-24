package src;

import sys.thread.Thread;
import src.Config;
import hx.ws.WebSocket;
import hx.ws.Log;
import hx.ws.Types.MessageType;
import Std.parseFloat;
import src.Util.toTwoDigits;
import src.FileHandler.isChatOpened;
import src.FileHandler.openChat;
import src.FileHandler.writeToChat;
import src.FileHandler.closeChat;
import haxe.Timer;

using StringTools;

function runChatDownloader(channel:String, filename:String) {
	Log.mask = Log.INFO; // for the websocket
	var stopRequested = false;
	var currentWs:WebSocket = null;

	function connect() {
		var ws = new WebSocket("wss://irc-ws.chat.twitch.tv:443");
		currentWs = ws;
		ws.onopen = () -> {
			// using the same PASS and NICK that chat-downloader (https://github.com/xenova/chat-downloader) uses, it seems the PASS doesn't matter but the NICK matters, justinfan67420 is the correct public username
			ws.send('CAP REQ :twitch.tv/membership twitch.tv/tags twitch.tv/commands');
			ws.send('PASS SCHMOOPIIE');
			ws.send('NICK justinfan67420');
			ws.send('JOIN #$channel');
			if (config.debug) trace('Connected to Twitch chat for $channel');
		}
		ws.onmessage = (message:MessageType) -> {
			if (stopRequested) return;
			switch (message) {
				case BytesMessage(_):
					return;
				case StrMessage(content):
					if (content.contains("PRIVMSG")) {
						if (!isChatOpened(channel)) openChat(channel, filename);
						processMessage(content, channel, filename);
					} else if (content.contains("PING :")) {
						if (config.debug) trace('The Twitch WS sent "$content" for channel $channel');
						var toSend = content.split(":")[1];
						ws.send('PONG :$toSend');
						if (config.debug) trace('Responded "PONG :$toSend" to the Twitch WS for channel $channel.');
					}
			}
		}
		ws.onclose = () -> {
			if (!stopRequested) {
				Sys.println('Chat Websocket disconnected for $channel, reconnecting in 5 seconds...');
				Timer.delay(connect, 5000);
			} else {
				if (config.debug) trace('Disconnected from Twitch chat for $channel');
			}
		}
	}

	connect();

	if (Thread.readMessage(true) == "end") {
		stopRequested = true;
		if (config.debug) trace("Stopping chat downloader.");
		if (currentWs != null) {
			try {
				currentWs.close();
			} catch (e) {
				if (config.debug) trace('Failed to close WebSocket: $e');
			}
		}
		closeChat(channel);
	}
}

/**
 * Parse and write an incoming twitch message to a chat file
 * @param message complete message string as supplied by Twitch (with meta to parse)
 * @param channel name of the Twitch channel (used to directly append the message to the chat file in the "processed" folder)
 * @param filename filename of the chat file
 */
function processMessage(message:String, channel:String, filename:String) {
	if (!config.custom_chat) {
		// we remove the CRLF delimitation because writeToChat breaks the lines itself
		writeToChat(channel, message.replace("\r\n", ""));
		return;
	}

	var processedMessage = {
		timestamp: 0.0,
		room_id: config.chat_var_when_empty.room_id,
		user_id: config.chat_var_when_empty.user_id,
		user_type: config.chat_var_when_empty.user_type,
		display_name: config.chat_var_when_empty.display_name,
		badge_info: config.chat_var_when_empty.badge_info,
		badges: config.chat_var_when_empty.badges,
		client_nonce: config.chat_var_when_empty.client_nonce,
		color: config.chat_var_when_empty.color,
		emotes: config.chat_var_when_empty.emotes,
		flags: config.chat_var_when_empty.flags,
		id: config.chat_var_when_empty.id,
		is_first_message: false,
		is_moderator: false,
		is_subscriber: false,
		is_returning_chatter: false,
		is_turbo: false,
		content: config.chat_var_when_empty.content
	};

	try {
		for (element in message.split(";")) {
			var option = element.split("=")[0];
			var value = element.split("=")[1];

			var lastElement = element.split('PRIVMSG #$channel :');
			if (lastElement[1] != null) {
				var lastValue = lastElement[0].split(":");
				option = lastValue[0].split("=")[0];
				value = lastValue[0].split("=")[1];
				processedMessage.content = lastElement[1];
				continue;
			}

			// skip if the value is empty, so it stays to the default value specified in the config
			if (value.trim() == "") continue;

			switch (option) {
				case "badge-info":
					processedMessage.badge_info = value;
				case "badges":
					processedMessage.badges = value;
				case "client-nonce":
					processedMessage.client_nonce = value;
				case "color":
					processedMessage.color = value;
				case "display-name":
					processedMessage.display_name = value;
				case "emotes":
					processedMessage.emotes = value;
				case "first-msg":
					processedMessage.is_first_message = value == "1" ? true : false;
				case "flags":
					processedMessage.flags = value;
				case "id":
					processedMessage.id = value;
				case "mod":
					processedMessage.is_moderator = value == "1" ? true : false;
				case "returning-chatter":
					processedMessage.is_returning_chatter = value == "1" ? true : false;
				case "room-id":
					processedMessage.room_id = value;
				case "subscriber":
					processedMessage.is_subscriber = value == "1" ? true : false;
				case "tmi-sent-ts":
					processedMessage.timestamp = parseFloat(value);
				case "turbo":
					processedMessage.is_turbo = value == "1" ? true : false;
				case "user-id":
					processedMessage.user_id = value;
				case "user-type":
					processedMessage.user_type = value;
			}
		}

		var date = Date.fromTime(processedMessage.timestamp);
		var cleanDate = '${date.getFullYear()}-${toTwoDigits(date.getMonth() + 1)}-${toTwoDigits(date.getDate())} ${toTwoDigits(date.getHours())}:${toTwoDigits(date.getMinutes())}:${toTwoDigits(date.getSeconds())}';

		// process pattern in config
		var message:String = config.custom_chat_pattern.replace("{{date}}", cleanDate)
			.replace("{{badge_info}}", processedMessage.badge_info)
			.replace("{{badges}}", processedMessage.badges)
			.replace("{{client_nonce}}", processedMessage.client_nonce)
			.replace("{{color}}", processedMessage.color)
			.replace("{{display_name}}", processedMessage.display_name)
			.replace("{{emotes}}", processedMessage.emotes)
			.replace("{{is_first_message}}", '${processedMessage.is_first_message}')
			.replace("{{flags}}", processedMessage.flags)
			.replace("{{id}}", processedMessage.id)
			.replace("{{is_moderator}}", '${processedMessage.is_moderator}')
			.replace("{{is_returning_chatter}}", '${processedMessage.is_returning_chatter}')
			.replace("{{room_id}}", processedMessage.room_id)
			.replace("{{is_subscriber}}", '${processedMessage.is_subscriber}')
			.replace("{{timestamp}}", '${processedMessage.timestamp}')
			.replace("{{is_turbo}}", '${processedMessage.is_turbo}')
			.replace("{{user_id}}", processedMessage.user_id)
			.replace("{{user_type}}", processedMessage.user_type)
			.replace("{{content}}", processedMessage.content.replace("\r\n", ""));

		writeToChat(channel, message);
	} catch (e) {
		// twitch sent us poop
		trace(e);
	}
}
