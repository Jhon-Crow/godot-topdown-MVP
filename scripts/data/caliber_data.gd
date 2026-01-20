extends Resource
class_name CaliberData
## Resource class containing caliber/ammunition configuration data.
##
## Defines ballistic properties for different ammunition types including:
## - Basic properties (name, diameter, mass)
## - Ricochet behavior (probability, angle thresholds, energy retention)
## - Damage characteristics
##
## This allows for extensibility when adding new weapon calibers in the future.
## Reference: Ricochet mechanics inspired by Arma 3 ballistics.

## Display name of the caliber (e.g., "5.45x39mm", "7.62x51mm").
@export var caliber_name: String = "5.45x39mm"

## Bullet diameter in millimeters (for display/reference).
@export var diameter_mm: float = 5.45

## Bullet mass in grams (affects energy calculations).
@export var mass_grams: float = 3.4

## Base velocity in pixels per second (game units).
## This is used for energy calculations when the bullet doesn't have velocity set.
@export var base_velocity: float = 2500.0

# ============================================================================
# Ricochet Properties
# ============================================================================

## Whether this caliber can ricochet off surfaces.
@export var can_ricochet: bool = true

## Maximum number of ricochets allowed before bullet is destroyed.
## Set to -1 for unlimited ricochets.
## Real bullets can ricochet multiple times in rare cases.
@export var max_ricochets: int = -1

## Maximum angle (in degrees) from surface at which ricochet is possible.
## Shallow angles (close to parallel with surface) are more likely to ricochet.
## Example: 30 degrees means bullets hitting at angles < 30 from surface can ricochet.
## Bullets hitting at steeper angles (closer to perpendicular) will not ricochet.
@export_range(5.0, 60.0, 1.0) var max_ricochet_angle: float = 30.0

## Base probability of ricochet when hitting at the optimal angle (very shallow).
## The actual probability is scaled based on impact angle.
## 0.0 = never ricochets, 1.0 = always ricochets at optimal angle.
@export_range(0.0, 1.0, 0.05) var base_ricochet_probability: float = 0.7

## Velocity retention factor after ricochet (0.0 to 1.0).
## How much of the original velocity is retained after bouncing.
## Real bullets lose significant energy on ricochet.
@export_range(0.1, 0.9, 0.05) var velocity_retention: float = 0.6

## Damage multiplier after each ricochet.
## Ricocheted bullets deal reduced damage due to deformation and energy loss.
@export_range(0.1, 0.9, 0.05) var ricochet_damage_multiplier: float = 0.5

## Random angle deviation (in degrees) added to reflected direction.
## Simulates imperfect surface reflections and bullet deformation.
@export_range(0.0, 30.0, 1.0) var ricochet_angle_deviation: float = 10.0

# ============================================================================
# Surface Interaction (for future extensibility)
# ============================================================================

## Penetration power rating (arbitrary units, higher = more penetration).
## Can be used to determine if bullet penetrates thin surfaces vs ricochets.
@export_range(0.0, 100.0, 1.0) var penetration_power: float = 30.0

## Minimum surface hardness that allows ricochet (0 = soft, 100 = hardest).
## Softer surfaces absorb bullets, harder surfaces can cause ricochets.
## For now, walls are assumed to be hard enough (concrete/metal).
@export_range(0.0, 100.0, 1.0) var min_surface_hardness_for_ricochet: float = 50.0


## Calculates the ricochet probability based on impact angle.
## Uses quadratic interpolation so angles close to 90° (perpendicular) are much less likely.
## @param impact_angle_degrees: Angle between bullet direction and surface (0 = parallel).
## @return: Probability of ricochet (0.0 to 1.0).
func calculate_ricochet_probability(impact_angle_degrees: float) -> float:
	if not can_ricochet:
		return 0.0

	if impact_angle_degrees > max_ricochet_angle:
		return 0.0

	# Quadratic interpolation: shallow angles (0°) have HIGH probability,
	# angles approaching max_ricochet_angle have MUCH LOWER probability.
	# At 0 degrees (parallel/grazing): full base probability
	# At max_ricochet_angle: 0 probability
	var normalized_angle := impact_angle_degrees / max_ricochet_angle
	# Quadratic curve: (1 - x)^2 drops off faster than linear
	var angle_factor := (1.0 - normalized_angle) * (1.0 - normalized_angle)
	return base_ricochet_probability * angle_factor


## Calculates the new velocity after ricochet.
## @param current_velocity: Current velocity in pixels per second.
## @return: New velocity after energy loss from ricochet.
func calculate_post_ricochet_velocity(current_velocity: float) -> float:
	return current_velocity * velocity_retention


## Generates a random angle deviation for ricochet direction.
## @return: Random angle in radians to add to reflection direction.
func get_random_ricochet_deviation() -> float:
	var deviation_radians := deg_to_rad(ricochet_angle_deviation)
	return randf_range(-deviation_radians, deviation_radians)
