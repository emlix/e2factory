#! /bin/sh

# This tool is __unused__ since e2-2.2pre14. Its presence is still checked for
# up until e2factory-2.3.12.  It must therefore be present until
# e2factory-2.3.12 is not supported anymore.

# This tool should never be called by any version of e2factory that is still
# supported. Always signal an error.

echo "e2-su is not supported! It exists for backwards compatibility only." >&2
exit 1
