#!/bin/bash
# Script to create backup branch from current main

# Ensure we're in the correct directory
cd "$(dirname "$0")"

# Create backup branch from main
git branch backup main

# Push backup branch to origin
git push origin backup

echo "✅ Backup branch created successfully!"
echo "The backup branch is now available at: https://github.com/Jhon-Crow/godot-topdown-MVP/tree/backup"
