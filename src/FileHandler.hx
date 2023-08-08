package src;

import src.Config;
import sys.io.File;

var openedChats:Array<{channel:String, file:sys.io.FileOutput}> = [];

function openChat(channel:String, filename:String) {
	openedChats.push({channel: channel, file: File.append('${config.processed_path}/$channel/$filename - chat.txt', false)});
	if (config.debug) trace('[DEBUG] Opened chat file of channel ${channel}');
}

function closeChat(channel:String) {
	for (openedChat in openedChats) {
		if (openedChat.channel == channel) {
			openedChat.file.close();
			openedChats.remove(openedChat);
			if (config.debug) trace('[DEBUG] Closed chat file of channel ${openedChat.channel}');
		}
	}
}

function isChatOpened(channel:String) {
	for (openedChat in openedChats) {
		if (openedChat.channel == channel) return true;
	}
	return false;
}

function writeToChat(channel:String, message:String) {
	for (openedChat in openedChats) {
		if (openedChat.channel == channel) {
			openedChat.file.writeString(message + "\n", UTF8);
			openedChat.file.flush(); // flush forces the write to the file, else it writes all messages in some sort of cache of the FileOutput every ~30 secs
		}
	}
}
