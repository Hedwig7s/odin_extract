#!/usr/bin/env bash
set -e
cd odin-zip
./build.sh
cd ..

odin build ./src -collection:zip=odin-zip/src -collection:libzip=odin-zip/libzip -out:./odin_extract -o:aggressive
