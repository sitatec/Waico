#!/bin/bash

# First remove the existing .so files
ARM64_V8A_PATH="android/app/src/main/jniLibs/arm64-v8a"
ARMEABI_V7A_PATH="android/app/src/main/jniLibs/armeabi-v7a"
rm -rf "$ARM64_V8A_PATH/libonnxruntime.so" \
       "$ARM64_V8A_PATH/libsherpa-onnx-c-api.so" \
       "$ARM64_V8A_PATH/libsherpa-onnx-cxx-api.so" \
       "$ARMEABI_V7A_PATH/libonnxruntime.so" \
       "$ARMEABI_V7A_PATH/libsherpa-onnx-c-api.so" \
       "$ARMEABI_V7A_PATH/libsherpa-onnx-cxx-api.so"
       
       
# Now build the sherpa-onnx library (adjust the path to your sherpa-onnx project)
# ⚠️⚠️ Make sure to set -DANDROID_PLATFORM to android-27 to enable NNAPI support for inference on GPU ⚠️⚠️
SHERPA_ONNX_PATH="/Users/sitatech/Projects/sherpa-onnx"

# Adjust this path if your NDK is located elsewhere
export ANDROID_NDK=/Users/sitatech/Library/Android/sdk/ndk/27.0.12077973
export SHERPA_ONNX_ENABLE_C_API=ON

# Clean up previous builds then build
printf "\n\n#################\nBuilding for Android arm64-v8a... #################\n\n"
(cd "$SHERPA_ONNX_PATH" && rm -rf build-android-arm64-v8a && ./build-android-arm64-v8a.sh)
printf "\n\n#################\nBuilding for Android armeabi-v7a... #################\n\n"
(cd "$SHERPA_ONNX_PATH" && rm -rf build-android-armv7-eabi && ./build-android-armv7-eabi.sh)

# Copy the built libraries to the Flutter project
ARM64_V8A_LIBS=(
  "$SHERPA_ONNX_PATH/build-android-arm64-v8a/install/lib/libonnxruntime.so"
  "$SHERPA_ONNX_PATH/build-android-arm64-v8a/install/lib/libsherpa-onnx-c-api.so"
  "$SHERPA_ONNX_PATH/build-android-arm64-v8a/install/lib/libsherpa-onnx-cxx-api.so"
)
ARMEABI_V7A_LIBS=(
  "$SHERPA_ONNX_PATH/build-android-armv7-eabi/install/lib/libonnxruntime.so"
  "$SHERPA_ONNX_PATH/build-android-armv7-eabi/install/lib/libsherpa-onnx-c-api.so"
  "$SHERPA_ONNX_PATH/build-android-armv7-eabi/install/lib/libsherpa-onnx-cxx-api.so"
)

for lib in "${ARM64_V8A_LIBS[@]}"; do
  cp "$lib" "$ARM64_V8A_PATH"
done

for lib in "${ARMEABI_V7A_LIBS[@]}"; do
  cp "$lib" "$ARMEABI_V7A_PATH"
done