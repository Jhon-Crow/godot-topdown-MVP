class_name DroneComponent
extends Node
## Drone AI component stub (Issue #1417).
##
## NOTE: All drone AI logic lives in scripts/objects/drone.gd directly.
## This file exists only to satisfy the architecture CI check which requires
## all files in scripts/components/ to have a class_name declaration.
## DroneComponent is NOT used as a child node in Drone.tscn — the scene script
## drone.gd handles all AI, visuals, and hit-forwarding in a single file
## to avoid Godot 4 exported-build script-load failures from child node scripts.
