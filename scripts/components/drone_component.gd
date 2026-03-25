class_name DroneComponent
extends Node
## Minimal stub for DroneComponent — kept for backwards compatibility.
##
## All drone AI logic has been moved into drone.gd (Issue #1417 fix).
## This stub exists so that any code referencing DroneComponent by class_name
## does not break. The drone entity (drone.gd) now handles all behavior directly.

## Health points of the drone (kept as constant for any external references).
const DRONE_HP: int = 2
