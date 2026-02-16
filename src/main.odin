package odin_extract
import "core:bufio"
import "core:encoding/json"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "zip:zip"

longest_path := 0
path_buf: [44]u8 // First 2 hex bytes + / + 40 sha sha-1 + null terminator
progress_buf: [512]u8
extract :: proc(
	file: json.Object,
	zipf: ^zip.Zip,
	subdir: string,
	filename: string,
	created_dirs: ^map[string]bool,
) {
	out := fmt.tprintf("%s/%s", subdir, filename)

	flags, flags_is_float := file["flags"].(json.Float)
	if !flags_is_float {
		fmt.printfln("\nFlags on %s is not a float.", filename)
		os.exit(-2)
	}
	if f64(i64(flags)) != flags {
		fmt.printfln("\nFlags on %s have a decimal: %f %d", flags, i64(flags))
		os.exit(-3)
	}
	if i64(flags) & 64 == 64 {
		os.make_directory_all(out)
		return
	}
	chunks, is_array := file["chunks"].(json.Array)
	if !is_array {
		fmt.printfln("\nInvalid chunk list in %s", filename)
		os.exit(-4)
	}
	cur := 0
	dir_path := filepath.dir(out)
	if !(dir_path in created_dirs) {
		os.make_directory_all(dir_path)
		created_dirs[dir_path] = true
	}
	outf, err := os.open(out, {.Write, .Create})
	if err != nil {
		fmt.printfln("\nFailed to create output file %s: %v", out, err)
		os.exit(-9)
	}
	defer os.close(outf)

	writer: bufio.Writer

	bufio.writer_init(&writer, os.to_stream(outf))
	defer bufio.writer_flush(&writer)

	fmt.print("\r", flush = false)
	for _ in 0 ..< longest_path {
		fmt.print(" ", flush = false)
	}
	progress := fmt.tprintf("\r%s", filename)
	fmt.print(progress)
	longest_path = longest_path < len(progress) ? len(progress) : longest_path
	for c in chunks {
		chunk, is_str := c.(json.String)
		if !is_str {
			fmt.printfln("Chunk in %s is not a string", filename)
			os.exit(-5)
		}
		cur += 1
		if chunk == "0000000000000000000000000000000000000000" do break

		chunk_path := fmt.bprintf(path_buf[:], "%s/%s", chunk[0:2], chunk)
		zerr := zip.entry_open(zipf, chunk_path)
		if zerr != .ENONE {
			fmt.printfln(
				"\nError opening chunk %s of file %s: %s",
				chunk,
				filename,
				zip.strerror(zerr),
			)
			os.exit(-6)
		}
		data: []u8
		data, zerr = zip.entry_read(zipf)
		if zerr != .ENONE {
			fmt.printfln(
				"\nError reading chunk %s of file %s: %s",
				chunk,
				filename,
				zip.strerror(zerr),
			)
			os.exit(-7)
		}
		_, w_err := bufio.writer_write(&writer, data)
		delete(data)
		if w_err != nil {
			fmt.printfln("\nError writing chunk data %s to file %s: %v", chunk, filename, w_err)
			os.exit(-8)
		}
	}
	free_all(context.temp_allocator)
}

main :: proc() {
	if (len(os.args) < 4 || len(os.args) > 6) {
		fmt.printfln(
			`Usage: %s archive_name depot_id manifest_id [path_filter] [output_path]
Examples:
	%s tf2 441 5 tf/maps/ tf2_maps
	%s engine 216 0`,
			os.args[0],
			os.args[0],
			os.args[0],
		)
		os.exit(1)
	}

	archive: string = os.args[1]
	depot_id, manifest_id: int
	ok: bool
	depot_id, ok = strconv.parse_int(os.args[2])
	if (!ok) {
		fmt.println("depot_id must be an integer")
		os.exit(2)
	}
	manifest_id, ok = strconv.parse_int(os.args[3])
	if (!ok) {
		fmt.println("manifest_id must be an integer")
		os.exit(3)
	}

	root := len(os.args) > 4 ? os.args[4] : ""
	path: string
	if len(os.args) > 5 {
		path = os.args[5]
	} else {
		path = fmt.aprintf("%d/%d", depot_id, manifest_id)
	}
	manifest_zip := zip.open(fmt.tprintf("manifests_%s.zip", archive), 0, zip.OpenMode.Read)
	if manifest_zip == nil {
		fmt.println("Failed to open manifest zip")
		os.exit(4)
	}
	err := zip.entry_open(manifest_zip, fmt.tprintf("%d/%d.json", depot_id, manifest_id))
	if err != .ENONE {
		fmt.printfln("Failed to find manifest: %s", zip.strerror(err))
		os.exit(5)
	}
	json_buf: []u8
	json_buf, err = zip.entry_read(manifest_zip)
	if err != .ENONE {
		fmt.printfln("Failed to read manifest: %s", zip.strerror(err))
		os.exit(6)
	}
	defer delete(json_buf)
	zip.close(manifest_zip)

	val, jerr := json.parse(json_buf)
	if jerr != nil {
		fmt.println("Failed to parse manifest: ", jerr)
		os.exit(7)
	}
	defer json.destroy_value(val)
	json_root, root_ok := val.(json.Object)
	if !root_ok {
		fmt.println("Root is not an object")
		os.exit(8)
	}

	if name, ok := json_root["name"]; ok {
		fmt.printfln("Extracting from %s v%d", name, manifest_id)
	}

	chunks := zip.open(fmt.tprintf("chunks_%s.zip", archive), 0, zip.OpenMode.Read)

	if chunks == nil {
		fmt.println("Failed to open chunks zip")
	}

	arena: virtual.Arena
	arena_buffer := make([]byte, 1024 * 1024)
	defer delete(arena_buffer)
	aerr := virtual.arena_init_buffer(&arena, arena_buffer)
	if aerr != .None {
		fmt.printfln("Failed to allocate arena buffer: %v", aerr)
	}
	arena_allocator := virtual.arena_allocator(&arena)

	created_dirs: map[string]bool = {}
	created_dirs.allocator = arena_allocator
	defer delete(created_dirs)

	if files_val, ok := json_root["files"]; ok {
		if files_obj, is_obj := files_val.(json.Object); is_obj {
			for filename in files_obj {
				if !strings.has_prefix(filename, root) {
					continue
				}
				if file_obj, is_obj := files_obj[filename].(json.Object); is_obj {
					extract(file_obj, chunks, path, filename, &created_dirs)
				} else {
					fmt.printfln("Warning: %s's value is not an Object", filename)
				}
			}
		} else {
			fmt.println("'files' exists but is not an object")
			os.exit(10)
		}
	} else {
		fmt.println("Key 'files' not found")
		os.exit(11)
	}
	free_all(context.temp_allocator)
}
