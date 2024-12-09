#!/bin/bash

# Exit on error
set -e

# Usage: pulsing_effect.sh <input_video> <music_audio> <output_video>
if [ $# -ne 3 ]; then
    echo "Usage: $0 <input_video> <music_audio> <output_video>"
    exit 1
fi

INPUT_VIDEO="$1"
MUSIC_AUDIO="$2"
OUTPUT_VIDEO="$3"

FRAME_DIR="frames"
PROCESSED_DIR="processed_frames"
FRAME_RATE=30  # Frame rate of the video
BPM=220      # Beats per minute
BEAT_DURATION=$(awk "BEGIN {print 60 / $BPM}")  # Seconds per beat

# Create temporary directories
mkdir -p "$FRAME_DIR" "$PROCESSED_DIR"

# Extract frames from the input video
echo "Extracting frames from $INPUT_VIDEO..."
ffmpeg -i "$INPUT_VIDEO" -vf fps=$FRAME_RATE "$FRAME_DIR/frame_%04d.png"

# Process each frame to create the pulsing effect
echo "Applying pulsing effect..."
TOTAL_FRAMES=$(ls "$FRAME_DIR" | wc -l)
CURRENT_TIME=0

for FRAME_PATH in "$FRAME_DIR"/*.png; do
    FRAME_NAME=$(basename "$FRAME_PATH")
    OUTPUT_FRAME="$PROCESSED_DIR/$FRAME_NAME"

    # Calculate beat progress
    BEAT_PROGRESS=$(awk "BEGIN {print ($CURRENT_TIME % $BEAT_DURATION) / $BEAT_DURATION}")

    # Interpolate intensity from 1.0 (red) to 0.0 (black)
    SCALE_FACTOR=$(awk "BEGIN {print 1 - $BEAT_PROGRESS}")

    # Calculate the red intensity (scale 0 to 255)
    # RED_INTENSITY=$(awk "BEGIN {print int(255 * $EFFECT_INTENSITY)}")
    RED=140
    BLUE=100
    GREEN=200

    SCALED_RED=$(echo "$RED * $SCALE_FACTOR" | bc | awk '{printf "%.0f", $0}')
    SCALED_GREEN=$(echo "$GREEN * $SCALE_FACTOR" | bc | awk '{printf "%.0f", $0}')
    SCALED_BLUE=$(echo "$BLUE * $SCALE_FACTOR" | bc | awk '{printf "%.0f", $0}')

    # Convert scaled values to hex
    HEX_COLOR=$(printf "%02x%02x%02x" $SCALED_RED $SCALED_GREEN $SCALED_BLUE)

    BLOOM_INTENSITY=1 
    BLOOM_RADIUS=20
    BLOOM_THRESHOLD=100
    BLOOM_SCALED=$(echo "$BLOOM_INTENSITY * $SCALE_FACTOR" | bc | awk '{printf "%.0f", $0}')
    # HEX_COLOR=$(printf "%02x%02x%02x" $RED $GREEN $BLUE)  # Convert to hex color (00XXff)

    # Apply the imgfx "screen" effect with the calculated intensity
    # imgfx -i "$FRAME_PATH" overlay "$HEX_COLOR" > "$OUTPUT_FRAME"
    imgfx -i "$FRAME_PATH" bloom $BLOOM_SCALED $BLOOM_RADIUS $BLOOM_THRESHOLD > "$OUTPUT_FRAME"

    # Update the current time
    CURRENT_TIME=$(awk "BEGIN {print $CURRENT_TIME + 1 / $FRAME_RATE}")
done

# Reassemble the frames into a video
echo "Reassembling video..."
ffmpeg -framerate $FRAME_RATE -i "$PROCESSED_DIR/frame_%04d.png" -i "$MUSIC_AUDIO" -c:v libx264 -pix_fmt yuv420p -shortest "$OUTPUT_VIDEO"

# Cleanup
echo "Cleaning up..."
rm -rf "$FRAME_DIR" "$PROCESSED_DIR"

echo "Done! Output saved to $OUTPUT_VIDEO"
