BUILD_MODE=${1:-watch}

flutter pub run build_runner $BUILD_MODE --delete-conflicting-outputs