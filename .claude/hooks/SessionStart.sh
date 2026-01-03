#!/bin/bash

# Only run in remote Claude environments
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0
fi

set -e

echo "Setting up development environment..."

# Install pre-commit if not available
if ! command -v pre-commit &> /dev/null; then
  echo "Installing pre-commit..."
  if command -v pip3 &> /dev/null; then
    pip3 install pre-commit
  elif command -v pip &> /dev/null; then
    pip install pre-commit
  else
    echo "Error: pip not found, cannot install pre-commit"
    exit 1
  fi
fi

# Install Docker if not available (required for shellcheck pre-commit hook)
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get install -y docker.io
  else
    echo "Warning: Could not install Docker - no supported package manager found"
  fi
fi

# Install pre-commit hooks if .pre-commit-config.yaml exists
if [ -f "$CLAUDE_PROJECT_DIR/.pre-commit-config.yaml" ]; then
  echo "Installing pre-commit hooks..."
  pre-commit install
  pre-commit install --hook-type commit-msg
fi

# Install shellcheck if not available
if ! command -v shellcheck &> /dev/null; then
  echo "Installing shellcheck..."
  if command -v apt-get &> /dev/null; then
    apt-get install -y shellcheck
  else
    echo "Warning: Could not install shellcheck - no supported package manager found"
  fi
fi

# Install bats if not available (for running shell script tests)
if ! command -v bats &> /dev/null; then
  echo "Installing bats..."
  if command -v apt-get &> /dev/null; then
    apt-get install -y bats
  else
    echo "Warning: Could not install bats - no supported package manager found"
  fi
fi

# Initialize git submodules (for BATS test helpers)
if [ -f "$CLAUDE_PROJECT_DIR/.gitmodules" ]; then
  echo "Initializing git submodules..."
  git -C "$CLAUDE_PROJECT_DIR" submodule update --init --recursive
fi

# Install actionlint if not available
if ! command -v actionlint &> /dev/null; then
  echo "Installing actionlint..."
  ACTIONLINT_VERSION="1.7.9"
  curl -sL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/actionlint /usr/local/bin/
  sudo chmod +x /usr/local/bin/actionlint
fi

echo "Development environment setup complete!"
echo "Available tools:"
command -v pre-commit && echo "  - pre-commit: $(pre-commit --version)"
command -v docker && echo "  - docker: $(docker --version)"
command -v shellcheck && echo "  - shellcheck: $(shellcheck --version | head -2 | tail -1)"
command -v bats && echo "  - bats: $(bats --version)"
command -v actionlint && echo "  - actionlint: $(actionlint --version)"
