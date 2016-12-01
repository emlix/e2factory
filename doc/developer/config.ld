project = "e2factory"
title = "e2factory Developer Documentation"
dir = "e2factory"
all = true
file = { "../../generic",
	"../../local",
	"../../global",
	"../../plugins",
	exclude = {
		"../../generic/le2lib.c",
		"../../generic/leio.c",
		"../../generic/lsha.c",
		"../../generic/sha1.c",
		"../../generic/sha2.c",
		"../../global/e2-su-2.2.c",
		"../../local/linux32.c",
	}
}
