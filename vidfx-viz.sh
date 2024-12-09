#!/bin/bash
set -e

# Inputs
INPUT_VIDEO="$1"
MUSIC_AUDIO="$2"
OUTPUT_VIDEO="$3"

# Project-specific directories
PROJECT_DIR="./video_processing"
FRAME_DIR="$PROJECT_DIR/frames"
PROCESSED_DIR="$PROJECT_DIR/processed_frames"
AUDIO_DIR="$PROJECT_DIR/audio"
DATA_DIR="$PROJECT_DIR/data"

# Configurations
FRAME_RATE=30

# Create directories
mkdir -p "$FRAME_DIR" "$PROCESSED_DIR" "$AUDIO_DIR" "$DATA_DIR"

##############################################
# Step 1: Extract frames
##############################################

echo "Extracting frames from $INPUT_VIDEO..."
ffmpeg -i "$INPUT_VIDEO" -vf "fps=$FRAME_RATE,pad=width=ceil(iw/2)*2:height=ceil(ih/2)*2" "$FRAME_DIR/frame_%04d.png"

# Verify frames were extracted
TOTAL_FRAMES=$(ls "$FRAME_DIR"/*.png 2>/dev/null | wc -l)
if [ "$TOTAL_FRAMES" -eq 0 ]; then
    echo "Error: No frames extracted from the video!"
    exit 1
fi
echo "Extracted $TOTAL_FRAMES frames."

##############################################
# Step 2: Validate extracted frames
##############################################

echo "Validating extracted frames..."
for FRAME in "$FRAME_DIR"/*.png; do
    if ! file "$FRAME" | grep -q 'PNG image data'; then
        echo "Warning: Invalid frame detected: $FRAME"
        rm "$FRAME"
    fi
done

TOTAL_FRAMES=$(ls "$FRAME_DIR"/*.png 2>/dev/null | wc -l)
if [ "$TOTAL_FRAMES" -eq 0 ]; then
    echo "Error: All frames were invalid. Aborting!"
    exit 1
fi

##############################################
# Step 3: Extract and filter audio
##############################################

echo "Extracting and filtering audio for kick drum frequencies (50-200 Hz)..."
ffmpeg -y -i "$MUSIC_AUDIO" \
-af "highpass=f=200,lowpass=f=1000,volume=30dB,loudnorm,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=$DATA_DIR/volumes.txt" \
    "$AUDIO_DIR/kick_filtered_audio.wav"

if [ ! -s "$DATA_DIR/volumes.txt" ]; then
    echo "Error: No valid amplitude data extracted. Check the audio file and filter settings."
    exit 1
fi

##############################################
# Step 4: Normalize amplitude data
##############################################

echo "Normalizing and transforming amplitude data..."
awk '
BEGIN {
    max = -999999;
    count = 0;
}
/lavfi.astats.Overall.RMS_level=/ {
    value = substr($0, index($0, "=") + 1);
    value = value < 0 ? -value : value;
    if (value > max) max = value;
    data[count++] = value;
}
END {
    if (max > 0) {
        for (i = 0; i < count; i++) {
            normalized = data[i] / max;
            transformed = normalized ** 0.2;
            threshold = 0.1;  # Lower threshold to increase sensitivity
            if (transformed < threshold) transformed = 0;
            else transformed = (transformed - threshold) / (1 - threshold);
            print transformed > "'$DATA_DIR'/normalized.txt";
        }
    } else {
        print "Error: Max RMS value is zero or invalid.";
        exit 1;
    }
}
' "$DATA_DIR/volumes.txt"

if [ ! -s "$DATA_DIR/normalized.txt" ]; then
    echo "Error: No valid normalized data extracted."
    exit 1
fi

##############################################
# Step 5: Apply visual effects
##############################################

echo "Applying visual effects..."
mapfile -t NORMALIZED_INTENSITIES < "$DATA_DIR/normalized.txt"

for ((i = 1; i < TOTAL_FRAMES; i++)); do
    FRAME=$(printf "$FRAME_DIR/frame_%04d.png" "$i")
    OUTPUT_FRAME=$(printf "$PROCESSED_DIR/frame_%04d.png" "$i")
    INTENSITY=${NORMALIZED_INTENSITIES[i]:-0}

    if (( $(echo "$INTENSITY > 0" | bc -l) )); then
        RED=$(echo "255 * ($INTENSITY^2)" | bc | awk '{print int($1)}')
        [ "$RED" -gt 255 ] && RED=255
        [ "$RED" -lt 0 ] && RED=0

        COLOR=$(printf "00%02x%02x" 0 $RED_INTENSITY)  # Convert to hex color (00XXff)
        # COLOR=$(printf "%02x0000" "$RED")
        imgfx -i "$FRAME" screen "$COLOR" > "$OUTPUT_FRAME" || cp "$FRAME" "$OUTPUT_FRAME"
    else
        cp "$FRAME" "$OUTPUT_FRAME"
    fi
done

##############################################
# Step 6: Reassemble video
##############################################

echo "Reassembling video..."
ffmpeg -y -framerate "$FRAME_RATE" \
    -probesize 50M -analyzeduration 100M \
    -i "$PROCESSED_DIR/frame_%04d.png" \
    -i "$MUSIC_AUDIO" \
    -map 0:v:0 -map 1:a:0 \
    -c:v libx264 -crf 23 -preset medium -pix_fmt yuv420p \
    -c:a aac -b:a 192k -movflags +faststart \
    "$OUTPUT_VIDEO"

echo "Done! Output saved to $OUTPUT_VIDEO"
