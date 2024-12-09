#!/bin/bash

# Exit on any error
set -e

# Usage: pulsing_effect.sh <input_video> <music_audio> <output_video> <imgfx_command_chain>
if [ $# -lt 4 ]; then
    echo "Usage: $0 <input_video> <music_audio> <output_video> <imgfx_command_chain>"
    echo "Example: $0 input.mp4 music.mp3 output.mp4 'imgfx -i {} screen {color} | imgfx bloom 1 30 100'"
    exit 1
fi

INPUT_VIDEO="$1"
MUSIC_AUDIO="$2"
OUTPUT_VIDEO="$3"
IMGFX_CHAIN="$4"

FRAME_DIR="frames"
PROCESSED_DIR="processed_frames"
FRAME_RATE=30  # Frame rate of the video
BPM=144        # Beats per minute
BEAT_DURATION=$(awk "BEGIN {print 60 / $BPM}")  # Seconds per beat
SECONDS_PER_FRAME=$(awk "BEGIN {print 1 / $FRAME_RATE}")

# Create temporary directories
mkdir -p "$FRAME_DIR" "$PROCESSED_DIR"

# Extract frames from the input video
echo "Extracting frames from $INPUT_VIDEO..."
ffmpeg -i "$INPUT_VIDEO" -vf fps=$FRAME_RATE "$FRAME_DIR/frame_%04d.png"

# Process each frame to apply the imgfx commands with pulsing effect
echo "Processing frames..."
FRAME_INDEX=0

for FRAME_PATH in "$FRAME_DIR"/*.png; do
    FRAME_NAME=$(basename "$FRAME_PATH")
    OUTPUT_FRAME="$PROCESSED_DIR/$FRAME_NAME"

    # Calculate the current time in the video
    CURRENT_TIME=$(awk "BEGIN {print $FRAME_INDEX * $SECONDS_PER_FRAME}")

    # Calculate beat progress (oscillation within one beat duration)
    BEAT_PROGRESS=$(awk "BEGIN {print ($CURRENT_TIME % $BEAT_DURATION) / $BEAT_DURATION}")

    # Oscillate intensity using a sine wave for smooth pulsing
    EFFECT_INTENSITY=$(awk "BEGIN {print 0.5 * (1 + sin(2 * 3.14159 * $BEAT_PROGRESS))}")

    # Scale the color intensity (example: red channel modulated by intensity)
    RED_INTENSITY=$(awk "BEGIN {print int(255 * $EFFECT_INTENSITY)}")
    HEX_COLOR=$(printf "ff%02x%02x" 0 $RED_INTENSITY)  # Convert to hex color (00XXff)

    # Replace {} in the imgfx chain with the current frame path and {color} with the calculated hex color
    IMGFX_CMD=$(echo "$IMGFX_CHAIN" | sed "s|{}|$FRAME_PATH|g" | sed "s|{color}|$HEX_COLOR|g")

    # Execute the imgfx command chain
    eval "$IMGFX_CMD > $OUTPUT_FRAME"

    # Move to the next frame
    FRAME_INDEX=$((FRAME_INDEX + 1))
done

# Reassemble the processed frames into a video
echo "Reassembling video..."
ffmpeg -framerate $FRAME_RATE -i "$PROCESSED_DIR/frame_%04d.png" -i "$MUSIC_AUDIO" -c:v libx264 -pix_fmt yuv420p -shortest "$OUTPUT_VIDEO"

# Cleanup
echo "Cleaning up..."
rm -rf "$FRAME_DIR" "$PROCESSED_DIR"

echo "Done! Output saved to $OUTPUT_VIDEO"
