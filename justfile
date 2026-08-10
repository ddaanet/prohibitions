import 'plugin-dev/release.just'

# Checks that run before every commit.
precommit:
    jq empty .claude-plugin/plugin.json
    jq empty hooks/hooks.json
    shellcheck scripts/*.sh tests/*.sh
    bash -n scripts/*.sh tests/*.sh
    bash tests/deny-ask-user-question-test.sh

# Checks that run before a release. Add slow or paid checks here.
prerelease: precommit
