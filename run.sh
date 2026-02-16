#!/usr/bin/env bash
set -e
./build.sh
./odin_extract "$@"
rm odin_extract
