package src;

import sys.FileSystem;
import sys.io.Process;
import src.Config;

using StringTools;

function checkLeftovers() {
	Sys.println('Checking for leftover recordings to process...');
	var filesToProcess = FileSystem.readDirectory(config.temp_path);
	if (filesToProcess.length == 0) {
		Sys.println("No leftover recordings found!");
	} else {
		for (file in filesToProcess) {
			if (file.endsWith(".mp4") || file.endsWith(".mkv")) {
				processRecording(file);
			}
		}
		Sys.println('Finished processing leftover recordings!');
	}
}

function processRecording(filename:String) {
	var streamer = filename.split(" ")[0];
	Sys.println('Processing recording "$filename"...');
	final ffmpeg = new Process('ffmpeg -fflags +discardcorrupt -err_detect ignore_err -i "${config.temp_path}/$filename" -nostdin -c copy "${config.processed_path}/$streamer/$filename" -y');

	var ffmpegErrored = false;

	while (ffmpeg.exitCode(false) == null) {
		try {
			var line = ffmpeg.stderr.readLine();
			if (line.contains("Conversion failed!")) {
				ffmpegErrored = true;
				Sys.println('Cannot process recording "$filename". The source video/audio is maybe corrupted.');
				try {
					FileSystem.deleteFile('${config.processed_path}/$streamer/$filename');
					FileSystem.rename('${config.temp_path}/$filename', '${config.problematic_path}/$filename');
				} catch (e) {
					trace(e);
				}
			}
		} catch (e:haxe.io.Eof) {}
	}

	if (ffmpeg.exitCode() != 0) {
		Sys.println('Error while processing recording "$filename", FFmpeg exiting with code != ${ffmpeg.exitCode()}.');
	} else {
		if (!ffmpegErrored) {
			Sys.println('Processing of recording "$filename" finished.');
			try {
				FileSystem.deleteFile('${config.temp_path}/$filename');
			} catch (e) {
				trace(e);
			}
		}
	}

	ffmpeg.close();
}
