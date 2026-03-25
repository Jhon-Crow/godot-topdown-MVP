class_name DroneComponent
extends Node
## Minimal stub for DroneComponent — kept for class registry compliance.
##
## All drone AI logic has been moved into drone.gd (Issue #1417 fix).
## The Drone.tscn scene no longer instantiates this as a child node — the
## class_name registration conflict (same-scene loading) has been eliminated
## by removing the DroneComponent node from Drone.tscn.
##
## class_name is kept here to satisfy the architecture check requirement that
## all scripts in scripts/components/ declare a class_name.
