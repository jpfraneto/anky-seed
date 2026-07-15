#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REF="$(cd "$ROOT/../ios/references" && pwd)"
IOS_ROOT="$(cd "$ROOT/../ios" && pwd)"
OUT="$ROOT/public/anky-assets/landing"
ONBOARDING_FRAME=/tmp/anky-onboarding-write-before-scroll.png
FFMPEG=/opt/homebrew/bin/ffmpeg
FFPROBE=/opt/homebrew/bin/ffprobe
CWEBP=/opt/homebrew/bin/cwebp
SIPS=/usr/bin/sips

mkdir -p "$OUT"

"$FFMPEG" -y -ss 12 \
  -i "$IOS_ROOT/screenshots/paywall-review-recording-compressed.mp4" \
  -frames:v 1 -update 1 -map_metadata -1 \
  "$ONBOARDING_FRAME"

FILTER_COMPLEX="
[0:v]scale=760:1648:force_original_aspect_ratio=increase:flags=lanczos,crop=760:1648,zoompan=z='min(1.018,1+0.00024*on)':d=75:s=720x1560:fps=30:x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2',setsar=1,format=rgba,pad=764:1604:22:22:color=0x121014,split=2[p0][p5];
[1:v]scale=760:1648:force_original_aspect_ratio=increase:flags=lanczos,crop=760:1648,zoompan=z='min(1.018,1+0.00024*on)':d=75:s=720x1560:fps=30:x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2',setsar=1,format=rgba,pad=764:1604:22:22:color=0x121014[p1];
[2:v]scale=760:1648:force_original_aspect_ratio=increase:flags=lanczos,crop=706:1528:221:120,scale=760:1648:flags=lanczos,zoompan=z='min(1.018,1+0.00024*on)':d=75:s=720x1560:fps=30:x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2',setsar=1,format=rgba,pad=764:1604:22:22:color=0x121014[p2];
[3:v]scale=760:1648:force_original_aspect_ratio=increase:flags=lanczos,crop=706:1528:221:120,scale=760:1648:flags=lanczos,zoompan=z='min(1.018,1+0.00024*on)':d=75:s=720x1560:fps=30:x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2',setsar=1,format=rgba,pad=764:1604:22:22:color=0x121014[p3];
[4:v]scale=760:1648:force_original_aspect_ratio=increase:flags=lanczos,crop=760:1648,zoompan=z='min(1.018,1+0.00024*on)':d=75:s=720x1560:fps=30:x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2',setsar=1,format=rgba,pad=764:1604:22:22:color=0x121014[p4];
gradients=s=1080x1920:r=30:d=2.5:c0=0xF4A83D:c1=0xE96D4F:x0=120:y0=0:x1=960:y1=1920:speed=0,format=rgba,split=6[bg0][bg1][bg2][bg3][bg4][bg5];
[bg0][p0]overlay=x='if(lt(t,0.85),1080-922*sin((t/0.85)*PI/2),158)':y=158:shortest=1:format=auto,format=yuv420p,setpts=PTS-STARTPTS[s0];
[bg1][p1]overlay=x=158:y=158:shortest=1:format=auto,format=yuv420p,setpts=PTS-STARTPTS[s1];
[bg2][p2]overlay=x=158:y=158:shortest=1:format=auto,format=yuv420p,setpts=PTS-STARTPTS[s2];
[bg3][p3]overlay=x=158:y=158:shortest=1:format=auto,format=yuv420p,setpts=PTS-STARTPTS[s3];
[bg4][p4]overlay=x=158:y=158:shortest=1:format=auto,format=yuv420p,setpts=PTS-STARTPTS[s4];
[bg5][p5]overlay=x='if(lt(t,1.65),158,158+922*sin(((t-1.65)/0.8)*PI/2))':y=158:shortest=1:format=auto,format=yuv420p,setpts=PTS-STARTPTS[s5];
[s0][s1]xfade=transition=fade:duration=0.45:offset=2.05[x1];
[x1][s2]xfade=transition=fade:duration=0.45:offset=4.10[x2];
[x2][s3]xfade=transition=fade:duration=0.45:offset=6.15[x3];
[x3][s4]xfade=transition=fade:duration=0.45:offset=8.20[x4];
[x4][s5]xfade=transition=fade:duration=0.45:offset=10.25,trim=duration=12.75,setpts=PTS-STARTPTS,fps=30[v]
"

render() {
  "$FFMPEG" -y \
    -i "$REF/gate-screen.png" \
    -i "$ONBOARDING_FRAME" \
    -i "$REF/home-screen-2.jpeg" \
    -i "$REF/journey-screen.png" \
    -i "$REF/ceremony-screen.png" \
    -filter_complex "$FILTER_COMPLEX" \
    -map "[v]" -map_metadata -1 -an "$@"
}

render \
  -c:v libx264 -profile:v high -level 4.1 -preset slow -crf 26 \
  -pix_fmt yuv420p -movflags +faststart \
  "$OUT/anky-demo.mp4"

render \
  -c:v libvpx-vp9 -deadline good -cpu-used 3 -crf 35 -b:v 0 \
  -row-mt 1 -pix_fmt yuv420p \
  "$OUT/anky-demo.webm"

"$FFMPEG" -y -ss 1.05 -i "$OUT/anky-demo.mp4" \
  -frames:v 1 -update 1 -map_metadata -1 \
  /tmp/anky-demo-poster.png

"$CWEBP" -quiet -q 84 \
  /tmp/anky-demo-poster.png \
  -o "$OUT/anky-demo-poster.webp"

"$SIPS" -z 256 256 \
  "$IOS_ROOT/Anky/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" \
  --out "$OUT/app-icon.png" >/dev/null

for ASSET in "$OUT/anky-demo.mp4" "$OUT/anky-demo.webm"; do
  "$FFPROBE" -v error \
    -show_entries format=filename,duration,size \
    -of default=noprint_wrappers=1 \
    "$ASSET"
done
