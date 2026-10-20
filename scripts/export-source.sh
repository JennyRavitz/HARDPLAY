#!/bin/zsh
# Export both native and web sources without personal data or nested Git metadata.
set -euo pipefail
cd "${0:A:h:h}"
target="$PWD/build/github-project"
mkdir -p "$target"
for entry in Package.swift README.md VALIDATION.md .gitignore Sources scripts docs .github; do
    rsync -a "$entry" "$target/"
done
mkdir -p "$target/web"
rsync -a --exclude='.git/' --exclude='dist/' --exclude='.fixtures/' --exclude='node_modules/' --exclude='*.tar.gz' --exclude='.openai/local/' --exclude='.DS_Store' web/ "$target/web/"
print "Source checkout: $target"
