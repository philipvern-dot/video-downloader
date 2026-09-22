# Video Downloader

A Windows program that downloads videos and playlists as MP4 files, or audio only as MP3.

Double-click **Video Downloader** in this folder. If that shortcut does nothing, open `app\launch.vbs` once. That starts the program and repairs the shortcut.

Paste one link, several links, or a playlist. New files go in the `downloads` folder next to the program until you choose another folder. That choice is saved for the next run.

## Tools

The program looks for these files in `tools\`:

- `yt-dlp.exe`
- `ffmpeg.exe`
- `ffprobe.exe`
- `deno.exe`

They are not in this repository. The FFmpeg programs are each larger than GitHub allows. Copy them into `tools\` yourself, or run the Windows setup program `video_downloader.exe`, which installs this program and those tools for the current user, adds a Start menu entry, and registers an uninstall entry.

FFmpeg's license is `tools\FFmpeg-LICENSE.txt`.

## License

This program is released under the MIT License. See [LICENSE](LICENSE).

yt-dlp, FFmpeg, and Deno are separate programs and keep their own licenses. FFmpeg is GPL-3.0.
