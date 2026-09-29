class_name Tuning
## Every number that decides how ships fly and handle, in one place (spec §8).
## Block stats start from spec §4.4.

## Block types, with mass in kg and hit points.
const BLOCKS := {
	"frame": {"mass": 60.0, "hp": 100},
	"deck": {"mass": 40.0, "hp": 80},
	"iron": {"mass": 180.0, "hp": 300},
	"alloy": {"mass": 110.0, "hp": 260},
	"balloon": {"mass": 8.0, "hp": 30},
	"lift_stone": {"mass": 250.0, "hp": 400},
	"engine": {"mass": 300.0, "hp": 200},
	"propeller": {"mass": 50.0, "hp": 60},
	"rudder": {"mass": 30.0, "hp": 60},
	"sail": {"mass": 20.0, "hp": 40},
	"fuel_tank": {"mass": 80.0, "hp": 120},
	"ballast_tank": {"mass": 60.0, "hp": 100},
	"helm": {"mass": 80.0, "hp": 150},
	"cannon": {"mass": 220.0, "hp": 200},
	"cargo_bay": {"mass": 50.0, "hp": 100},
	"bunk": {"mass": 40.0, "hp": 60},
	"ladder": {"mass": 15.0, "hp": 40},
}

const ROIL_ALTITUDE := 200.0      ## m. The air is densest here and below.
const AIR_SCALE_HEIGHT := 2500.0  ## m. Air thins by a factor of e over this height.
const AIR_DENSITY := 1.2          ## kg/m³ at the Roil.
const BALLOON_LIFT := 900.0       ## N per balloon cell in the densest air, at trim 1.
const LIFT_STONE_LIFT := 6000.0   ## N per lift stone, at any altitude.
const PROPELLER_THRUST := 2500.0  ## N per propeller at full throttle and full power.
const PROPELLERS_PER_ENGINE := 2  ## Propellers one engine drives at full power.
const DRAG_COEFFICIENT := 0.45    ## Cd of every exposed face.
const HULL_LIFT := 8.0            ## How hard the hull resists slipping sideways at speed, as a keel does. Without it ships skid instead of turning.
const RUDDER_FORCE := 8.0         ## Side force per rudder, in N per (m/s)² of airspeed, at full deflection and density.
const ANGULAR_DAMPING := 0.5      ## 1/s. Air damping of the ship's spin, on top of face drag.
const TRIM_MIN := 0.8             ## Balloon trim limits: lift is 900 N × density × trim per balloon.
const TRIM_MAX := 1.1

const THROTTLE_MIN := -0.5        ## Full astern.
const THROTTLE_RATE := 0.5        ## Throttle change per second while W or S is held.
const TRIM_RATE := 0.05           ## Trim change per second while climbing or descending.

const AUTOPILOT_TURN_RATE := 0.25       ## rad/s the autopilot's heading turns while A or D is held.
const AUTOPILOT_CLIMB_RATE := 10.0      ## m/s its altitude changes while climbing or descending.
const AUTOPILOT_HEADING_GAIN := 3.0     ## Rudder per radian off course.
const AUTOPILOT_YAW_DAMPING := 6.0      ## Rudder per rad/s of turning.
const AUTOPILOT_ALTITUDE_GAIN := 0.002  ## Trim per metre off altitude.
const AUTOPILOT_CLIMB_DAMPING := 0.03   ## Trim per m/s of climb.
