#!/bin/sh

#
# user defined variables
#
debug=1 # 0 or 1
user="se"
# qualities="640_360_400k 640_360_800k 1280_720_1400k 1280_720_2800k" # width_height_bitrate
qualities="640_360_400k 960_540_800k 1280_720_1400k 1920_1080_2800k" # width_height_bitrate

Fail() { echo "ERROR: $@" 1>&2; exit 1; }

test "$(whoami)" == "root" && Fail "Error. Cannot run script via root user."

for c in flock ffmpeg ffprobe ; do
  which $c >/dev/null || Fail "$c not found"
done

home="/home/$user"

lock_file="$home/var/tmp/$(basename $0).lock"
 log_file="$home/var/log/$(basename $0).log"

Log() { test "$debug" == "1" && echo -e "$(date)\t$2\t$1" >> $log_file; }

files_dir="/home/$user/video_converter/video"

(
  flock -n 9 || exit 1

  for src in "$files_dir"/*.mov ; do

    test -f "$src" || Fail "File $src not found"

    s_src=$(basename "$src")

    dir_src=$(dirname "$src")

    # skip if .file.mov directory exists
    test "${dir_src##*.}" == "mov" && continue

    Log "$src" "Start"

    dst_dir="$dir_src/.$s_src"

    test ! -d "$dst_dir" && { mkdir "$dst_dir" > /dev/null 2>&1 || Fail "Cannot create directory $dst_dir"; }

    eval $(ffprobe -v error -of flat=s=_ -select_streams v:0 -show_entries stream=height,width,duration "$src")

### master playlist
    dst_master_m3u8="$dst_dir/master.m3u8"
    test -f "$dst_master_m3u8" && Log "Creating $dst_master_m3u8" "Processed" && continue

    echo "#EXTM3U" >> "$dst_master_m3u8"
    echo "#EXT-X-VERSION:3" >> "$dst_master_m3u8"
###

### subtitles
    dst_master_subs=""

    for sub in "$files_dir"/"${s_src%.*}"_*.vtt ; do
      test -f "$sub" || continue

      dst_sub="${sub// /_}"
      dst_sub_base=$(basename "$dst_sub")

      sub_lang=${sub##*_}
      sub_lang=${sub_lang%.*}
      sub_lang=${sub_lang,,}

      subtitles_dir="$dst_dir/subtitles/$sub_lang"
      subtitles_playlist_m3u8="$subtitles_dir/playlist.m3u8"

      duration=${streams_stream_0_duration%.*}
      test "${streams_stream_0_duration#*.}" -gt 0 && duration=$(( duration + 1 ))

      test ! -d "$subtitles_dir" && { mkdir -p "$subtitles_dir" > /dev/null 2>&1 || Fail "Cannot create directory $subtitles_dir"; }

      echo "#EXTM3U" >> "$subtitles_playlist_m3u8"
      echo "#EXT-X-TARGETDURATION:${duration}" >> "$subtitles_playlist_m3u8"
      echo "#EXT-X-VERSION:3" >> "$subtitles_playlist_m3u8"
      echo "#EXT-X-MEDIA-SEQUENCE:0" >> "$subtitles_playlist_m3u8"
      echo "#EXT-X-PLAYLIST-TYPE:VOD" >> "$subtitles_playlist_m3u8"
      echo "#EXTINF:${duration}.000000," >> "$subtitles_playlist_m3u8"
      echo "$dst_sub_base" >> "$subtitles_playlist_m3u8"
      echo "#EXT-X-ENDLIST" >> "$subtitles_playlist_m3u8"

      echo "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"${sub_lang^^}\",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,LANGUAGE=\"${sub_lang}\",CHARACTERISTICS=\"public.accessibility.transcribes-spoken-dialog, public.accessibility.describes-music-and-sound\",URI=\"subtitles/${sub_lang}/playlist.m3u8\"" >> "$dst_master_m3u8"

      dst_master_subs=",SUBTITLES=\"subs\""

      cp "$sub" "$subtitles_dir/$dst_sub_base"
    done
###

    for qq in $qualities ; do
      qq_w="$(echo $qq | cut -d_ -f1)"
      test $streams_stream_0_width -lt $qq_w && continue

      qq_h="$(echo $qq | cut -d_ -f2)"
      test $streams_stream_0_height -lt $qq_h && continue

      qq_rate="$(echo $qq | cut -d_ -f3)"
      qq_name="${qq_w}x${qq_h}x${qq_rate}"

      dst_m3u8="$dst_dir/v_${qq_name}.m3u8"
      dst_ts="$dst_dir/v_${qq_name}_%04d.ts"

###
      bandwidth=${qq_rate/k/000}
###

      test -f "$dst_m3u8" && Log "From $src to $dst" "Processed" && continue

      Log "From $src to $dst_m3u8" "Converting"

      ffmpeg -loglevel panic -hide_banner -i "$src" -c:v libx264 -preset veryslow -profile:v high -g 50 -r 25 -keyint_min 50 -x264opts keyint=50:keyint_min=50:no-scenecut -b:v $qq_rate -vf scale=$qq_w:$qq_h -c:a aac -q:a 2 -movflags faststart -subq 2 -hls_time 4 -hls_playlist_type vod -hls_segment_filename "$dst_ts" "$dst_m3u8"

      test "$?" -ne "0" && Log "Convert '$src' to '$dst_m3u8' failed" "Error" && rm "${dst_dir}/*" && exit 1

###
      m3u8_line1="#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},RESOLUTION=${qq_w}x${qq_h}${dst_master_subs}"
      m3u8_line2=$(basename "$dst_m3u8")
      echo "$m3u8_line1" >> "$dst_master_m3u8"
      echo "$m3u8_line2" >> "$dst_master_m3u8"
###

      Log "From $src to $dst_m3u8" "Done"

    done

    Log "$src" "Done"

  done

) 9>$lock_file
