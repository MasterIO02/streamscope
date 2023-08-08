# streamscope
streamscope allows you to record Twitch streams in real time for archival purposes.
CLI-only, rather easy to set-up and use.

![image](https://github.com/MasterIO02/streamscope/assets/40836390/42b0d33c-b2ab-41db-b76d-b56ebdafde8f)

## Features
- Monitor up to 100 streamers to record at the same time (Twitch API limitation)
- Record live chats to a file, with customizable formatting
- Informations about a stream are written and updated in real-time (game name, stream title...)
- Adding and removing streamers to monitor can be done in real-time

## Usage
streamscope is a standalone application that should run on about any Linux machine, however it requires 2 third-party applications to work correctly:
- [streamlink](https://github.com/streamlink/streamlink): used to record the live streams
- [ffmpeg](https://ffmpeg.org): used to post-process recordings

Make sure to have them installed and available either in the same directory as streamscope or in the PATH. 

streamscope cannot run on Windows as it depends on Linux built-in commands (the "kill" command).

1. Run streamscope once to have it generate a config.json file
2. Fill or edit settings in that fresh config.json file
3. Create a text file somewhere, with the list of streamers (usernames) you want to monitor separated by new lines (you can also comment a line with `//` before the streamer username)
4. Run streamscope with the path of your text file containing the streamers to monitor as an argument
5. You're good to go!

## Configuration file
- `debug`: Print debug logs when performing various tasks
- `twitch_id`: Your Twitch client ID
- `twitch_secret`: Your Twitch client secret
- `query_time`: Check if the streamers are online every x seconds
- `quality`: The quality to record at, passed directly to streamlink, some possible values can be "best", "worst", "720p30", "160p" (see streamlink's documentation [here](https://streamlink.github.io/))
- `video_container`: The container to use for recording, should be "mp4" or "mkv"
- `temp_path`: The path where currently recording videos will go
- `processed_path`: The path where processed videos will go
- `problematic_path`: The path where problematic videos will go (when ffmpeg crashes while processing a recording)
- `download_chat`: "true" or "false", download chat or not
- `custom_chat`: "true" or "false", if false the chat text file will be filled with what Twitch sends us directly without processing the text, if true the `custom_chat_pattern` needs to be set
- `custom_chat_pattern`: The pattern to follow to write chat message lines (see the available variables below)
- `chat_var_when_empty`: An object containing pattern values, if one of the chat message field is empty, it will be replaced by a specified string

Available values for `custom_chat_pattern` (between double curly brackets):
- `date`: String, a date in the format "2000-12-31 23:59:59"
- `badge_info`: String
- `badges`: String
- `client_nonce`: String
- `color`: String
- `display_name`: String
- `emotes`: String
- `is_first_message`: Boolean
- `flags`: String
- `id`: String
- `is_moderator`: Boolean
- `is_returning_chatter`: Boolean
- `room_id`: String
- `is_subscriber`: Boolean
- `timestamp`: String
- `is_turbo`: Boolean
- `user_id`: String
- `user_type`: String
- `content`: String, the message content

## Compile
You need Haxe 4.3.0 minimum (and haxelib) to build the project.

The compiler target for streamscope is C++. Install hxcpp with haxelib.

Download the libraries listed in the compile.hxml file using haxelib (`haxelib install [dependency name]`), and run `haxe compile.hxml`, or the `run.sh` file to directly run streamscope.
