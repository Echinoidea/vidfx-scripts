#!/bin/bash

# Exit on any error
set -e

# Check for the correct arguments
if [ $# -lt 3 ]; then
    echo "Usage: $0 <input_video> <output_video> <imgfx_command_chain>"
    echo "Example: $0 input.mp4 output.mp4 'imgfx -i {} left 1 | imgfx and ff0000 | imgfx bloom 1 30 100'"
    exit 1
fi

INPUT_VIDEO="$1"
OUTPUT_VIDEO="$2"
IMGFX_CHAIN="$3"
FRAME_DIR="frames"
PROCESSED_DIR="processed_frames"

# Create temporary directories for frames
mkdir -p "$FRAME_DIR" "$PROCESSED_DIR"

# Extract frames from the video
echo "Extracting frames from $INPUT_VIDEO..."
ffmpeg -i "$INPUT_VIDEO" "$FRAME_DIR/frame_%04d.png"

# Process each frame using the imgfx command chain
echo "Processing frames..."
for FRAME in "$FRAME_DIR"/*.png; do
    FRAME_NAME=$(basename "$FRAME")
    OUTPUT_FRAME="$PROCESSED_DIR/$FRAME_NAME"

    # Replace `{}` in the imgfx chain with the current frame path
    IMGFX_CMD=$(echo "$IMGFX_CHAIN" | sed "s|{}|$FRAME|g")

    # Execute the imgfx command chain
    eval "$IMGFX_CMD > $OUTPUT_FRAME"

    # Check for errors in processing
    if [ $? -ne 0 ]; then
        echo "Error processing $FRAME"
        exit 1
    fi
done

# Rebundle processed frames into a video
echo "Rebundling processed frames into $OUTPUT_VIDEO..."
ffmpeg -framerate 15 -i "$PROCESSED_DIR/frame_%04d.png" -c:v libx264 -pix_fmt yuv420p "$OUTPUT_VIDEO"

# Cleanup temporary directories
echo "Cleaning up..."
rm -rf "$FRAME_DIR" "$PROCESSED_DIR"

echo "Done! Processed video saved as $OUTPUT_VIDEO"
