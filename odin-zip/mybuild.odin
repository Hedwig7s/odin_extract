#+feature dynamic-literals
package nobuild
import "core:os"


when ODIN_OS == .Windows {
	LIBZIP :: "zip.lib"
} else {
	LIBZIP :: "libzip.a"
}


main :: proc() {
	if !os.exists("libzip") {
		run("git", "clone", "https://github.com/kuba--/zip", "libzip")
	}
	if !os.exists("libzip/" + LIBZIP) {
		cd("libzip")
		when ODIN_OS == .Linux {
			run("gcc", "-c", "src/zip.c", "-o", "zip.o")
			run("ar", "rcs", "libzip.a", "zip.o")
		} else {
			run("cl", "/c", "src/zip.c")
			run("lib", "zip.obj")
		}
		cd("..")
	}
}
