cd odin-zip
build.bat
cd ..

odin build ./src -collection:zip=odin-zip/src -collection:libzip=odin-zip/libzip -out:./odin_extract.exe -o:aggressive
