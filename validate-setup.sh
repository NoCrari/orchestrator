#!/bin/bash
# Quick validation of the setup

echo "Checking project files..."
missing=0

# Check main files
files=(
    "orchestrator.sh"
    "Vagrantfile"
    "README.md"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file missing"
        ((missing++))
    fi
done

# Check directories
dirs=(
    "Manifests"
    "Scripts"
    "Dockerfiles"
)

for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir/"
    else
        echo "  ✗ $dir/ missing"
        ((missing++))
    fi
done

if [ $missing -eq 0 ]; then
    echo ""
    echo "✓ All files present!"
else
    echo ""
    echo "⚠ $missing files/directories missing"
fi
