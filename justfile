import 'plugin-dev/release.just'
import 'plugin-dev/gates.just'

# Tool versions the precommit hash folds in: no lockfile pins them.
export PLUGIN_DEV_GATE_TOOLS := "shellcheck --version\njq --version\ngit --version\nbash --version"

# Checks that run before every commit.
precommit: check-refs
    #!{{ plugin_dev_gate_prolog }}
    # The memory/ tier is a gitlink the hash cannot see, and this test reads
    # memory/ddaanet/shared-claude.md: it runs here, uncached, ahead of the
    # guard, and the loop below skips it.
    bash tests/deny-volatile-memory-state-test.sh
    sentinel-guard precommit .claude-plugin hooks scripts tests
    jq empty .claude-plugin/plugin.json
    jq empty hooks/hooks.json
    shellcheck scripts/*.sh scripts/lib/*.sh tests/*.sh
    bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
    for f in tests/*-test.sh; do
        [ "$f" = tests/deny-volatile-memory-state-test.sh ] || bash "$f"
    done
    record-sentinel

# Checks that run before a release. Add slow or paid checks here.
prerelease: precommit
