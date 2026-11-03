#!/bin/sh
# Installs local git hooks: pre-commit runs lint, pre-push blocks pushes to main.
set -e
cd "$(git rev-parse --show-toplevel)"
HOOKS_DIR="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOKS_DIR"

for hook in pre-push pre-commit; do
    [ -e "$HOOKS_DIR/$hook" ] && echo "overwriting existing $hook hook"
done

cat > "$HOOKS_DIR/pre-push" <<'HOOK'
#!/bin/sh
# Block any push whose destination ref is refs/heads/main.
while read -r local_ref local_sha remote_ref remote_sha; do
    if [ "$remote_ref" = "refs/heads/main" ]; then
        echo "direct push to main is blocked; open a PR"
        exit 1
    fi
done
exit 0
HOOK

cat > "$HOOKS_DIR/pre-commit" <<'HOOK'
#!/bin/sh
make lint
HOOK

chmod +x "$HOOKS_DIR/pre-push" "$HOOKS_DIR/pre-commit" scripts/install-hooks.sh
echo "git hooks installed"
