#!/usr/bin/env bash
# Mock functions for unit tests.
#
# Replaces external commands (docker, lncli, etc.) with stubs so that
# tests can exercise flag-parsing logic without Docker or a running node.
#
# Usage:
#   source tests/lib/mocks.sh
#   setup_mocks          # create a temp bin dir and prepend it to PATH
#   mock_docker_ps TEXT  # make `docker ps` return TEXT
#   teardown_mocks       # remove the temp dir and restore PATH

_MOCK_DIR=""
_ORIG_PATH=""

# setup_mocks creates a temporary directory for mock executables and
# prepends it to PATH so they shadow the real binaries.
setup_mocks() {
    _MOCK_DIR="$(mktemp -d)"
    _ORIG_PATH="$PATH"
    export PATH="$_MOCK_DIR:$PATH"

    # Default docker mock: succeed for any command but produce no output.
    _write_mock "docker" '#!/usr/bin/env bash
# Default docker mock — exits 0 silently.
# Overridden per-test via mock_docker_ps, etc.
exit 0
'

    # Default docker-compose mock.
    _write_mock "docker-compose" '#!/usr/bin/env bash
exit 0
'

    # lncli mock — the test scripts never call lncli directly during
    # flag parsing, but some scripts probe for it.
    _write_mock "lncli" '#!/usr/bin/env bash
echo "mock lncli"
exit 0
'
}

# teardown_mocks removes the mock directory and restores PATH.
teardown_mocks() {
    if [ -n "$_MOCK_DIR" ] && [ -d "$_MOCK_DIR" ]; then
        rm -rf "$_MOCK_DIR"
    fi
    if [ -n "$_ORIG_PATH" ]; then
        export PATH="$_ORIG_PATH"
    fi
}

# mock_docker_ps configures the docker mock so that `docker ps` returns
# the given text. Other docker subcommands still exit 0 silently.
mock_docker_ps() {
    local output="$1"
    _write_mock "docker" "#!/usr/bin/env bash
if [[ \"\$1\" == \"ps\" ]]; then
    echo '$output'
    exit 0
fi
# For 'docker port', return empty (no running containers).
if [[ \"\$1\" == \"port\" ]]; then
    exit 0
fi
# For 'docker pull', 'docker run', etc. — succeed silently.
exit 0
"
}

# _write_mock writes a mock script to the mock directory.
_write_mock() {
    local name="$1"
    local body="$2"
    local path="$_MOCK_DIR/$name"
    echo "$body" > "$path"
    chmod +x "$path"
}
