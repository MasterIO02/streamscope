package src;

typedef Config = {
	debug:Bool,
	twitch_id:String,
	twitch_secret:String,
	query_time:Int,
	quality:String,
	video_container:String,
	temp_path:String,
	processed_path:String,
	problematic_path:String,
	download_chat:Bool,
	custom_chat:Bool,
	custom_chat_pattern:String,
	chat_var_when_empty:{
		room_id:String, user_id:String, user_type:String, display_name:String, badge_info:String, badges:String, client_nonce:String, color:String,
		emotes:String, flags:String, id:String, content:String
	}
}

var config:Config = {
	debug: false,
	twitch_id: "",
	twitch_secret: "",
	query_time: 15,
	quality: "best",
	video_container: "mkv",
	temp_path: "",
	processed_path: "",
	problematic_path: "",
	download_chat: true,
	custom_chat: true,
	custom_chat_pattern: "{{date}} | ({{badges}}) {{display_name}}: {{content}}",
	chat_var_when_empty: {
		room_id: "",
		user_id: "",
		user_type: "",
		display_name: "",
		badge_info: "",
		badges: "",
		client_nonce: "",
		color: "",
		emotes: "",
		flags: "",
		id: "",
		content: ""
	}
}

var freshConfig = '{
	"debug": false,
	"twitch_id": "",
	"twitch_secret": "",
	"query_time": 15,
	"quality": "best",
	"video_container": "mkv",
	"temp_path": "",
	"processed_path": "",
	"problematic_path": "",
	"download_chat": true,
	"custom_chat": true,
	"custom_chat_pattern": "{{date}} | ({{badges}}) {{display_name}}: {{content}}",
	"chat_var_when_empty": {
        "room_id": "",
        "user_id": "",
        "user_type": "",
        "display_name": "",
        "badge_info": "",
        "badges": "",
        "client_nonce": "",
        "color": "",
        "emotes": "",
        "flags": "",
        "id": "",
        "content": ""
    }
}
';
