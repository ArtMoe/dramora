#!/usr/bin/env bash
# Keep Flutter, Dart, Gradle and Java scratch data inside the repository.
# The caller must define ROOT as the repository root before sourcing this file.

: "${ROOT:?ROOT must be set before sourcing _project_tmp_env.sh}"

mkdir -p \
  "$ROOT/.tmp/flutter" \
  "$ROOT/.tmp/pub-cache" \
  "$ROOT/.tmp/xdg-cache" \
  "$ROOT/.tmp/gradle-home" \
  "$ROOT/.tmp/android-user" \
  "$ROOT/.tmp/java" \
  "$ROOT/.tmp/tmp"

export TMPDIR="$ROOT/.tmp/flutter"
export PUB_CACHE="$ROOT/.tmp/pub-cache"
export XDG_CACHE_HOME="$ROOT/.tmp/xdg-cache"
export GRADLE_USER_HOME="$ROOT/.tmp/gradle-home"
export ANDROID_USER_HOME="$ROOT/.tmp/android-user"
export JAVA_HOME="${JAVA_HOME:-/www/.toolchains/jdk17}"
export ANDROID_HOME="${ANDROID_HOME:-/www/.toolchains/android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }-Djava.io.tmpdir=$ROOT/.tmp/java"
export PATH="/www/.toolchains/ninja/root/usr/bin:$JAVA_HOME/bin:$PATH"
