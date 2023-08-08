package src;

// StreamerStatus is the object of a streamer in the main array of watched streamers
// we use almost the same properties as in OnlineStreamer because we will pass StreamerStatus to the streamlink process that will also create a json containing this data
typedef StreamerStatus = {
	// the username supplied in the list of streamers to watch
	streamer_input_username:String,
	// the real username of the streamer
	streamer_username:String,
	// the display username of the streamer
	streamer_display_name:String,
	online:Bool,
	chat_only:Bool,
	recording_since:String,
	filename:String,
	title:String,
	started_at:String,
	game_id:String,
	game_name:String,
	language:String,
	tag_ids:String,
	is_mature:String
}

// OnlineStreamer is the object of a streamer that got processed from the API call to twitch and returned to the main loop
// everything is optional except status because in case of an error there's only status
typedef OnlineStreamer = {
	status:String,
	?stream_id:String,
	?user_id:String,
	?user_login:String,
	?user_name:String,
	?title:String,
	?started_at:String,
	?game_id:String,
	?game_name:String,
	?language:String,
	?tag_ids:String,
	?is_mature:String
}
