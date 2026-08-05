sizes=(48 55 58 87 80 88 100 172 196 216 1024 66 88 90 100 102 92 108 234 258 )

for s in "${sizes[@]}"; do
  ffmpeg -i AppIconResize.png -vf "scale=${s}:${s}" "icon-${s}.png"
done
