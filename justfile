import 'plugin-dev/release.just'

# Checks that run before every commit.
precommit:
    jq . .claude-plugin/plugin.json > /dev/null

# Checks that run before a release. Add slow or paid checks here.
prerelease: precommit
