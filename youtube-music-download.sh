#!/bin/bash

read -p "Enter song link: " SONG_URL
read -p "Enter image link (press Enter to skip): " IMAGE_URL

./yt-dlp -x --audio-format m4a --embed-metadata --embed-thumbnail --no-playlist -o "output.m4a" "$SONG_URL"

if [[ ! -f "output.m4a" ]]; then
    echo "❌ Error: Failed to download audio file."
    exit 1
fi

TITLE=$(exiftool -s -s -s -Title output.m4a)
if [[ -z "$TITLE" ]]; then
    TITLE="output"
fi

SAFE_TITLE=$(echo "$TITLE" | sed 's#[/:*?"<>|]#_#g')

FINAL_AUDIO="${SAFE_TITLE}.m4a"
mv "output.m4a" "$FINAL_AUDIO"

echo "✅ Saved as: $FINAL_AUDIO"

if [[ -n "$IMAGE_URL" ]]; then
    ffmpeg -y -i "$FINAL_AUDIO" -i "$IMAGE_URL" \
        -map 0:a -map 1:v \
        -c:a copy -c:v mjpeg \
        -disposition:v attached_pic \
        "temp.m4a"

    mv -f "temp.m4a" "$FINAL_AUDIO"
    echo "✅ Embedded image into: $FINAL_AUDIO"
fi
