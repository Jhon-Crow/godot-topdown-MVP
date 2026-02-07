#!/usr/bin/env python3
"""Assemble the final CityLevel.tscn with enterable buildings."""

import os

BASE = "/tmp/gh-issue-solver-1770476728419"

# Read generated parts
with open(f"{BASE}/experiments/building_sub_resources.txt") as f:
    building_subs = f.read().strip()

with open(f"{BASE}/experiments/building_nodes.txt") as f:
    building_nodes = f.read().strip()

# Count sub_resources for load_steps (ext_resources + sub_resources + 1)
# ext_resources: 5
# original sub_resources: wall_h, wall_v, cover, cover_occluder, nav_polygon = 5
# new building sub_resources: 24 (12 rects + 12 occluders)
# Total = 5 + 5 + 24 + 1 = 35
ext_resources = 5
orig_subs = 6  # wall_h, wall_v, wall_h_occ, wall_v_occ, cover, cover_occ, nav_polygon
# Actually counting: RectangleShape2D_wall_h, RectangleShape2D_wall_v,
# OccluderPolygon2D_wall_h, OccluderPolygon2D_wall_v,
# RectangleShape2D_cover, OccluderPolygon2D_cover, NavigationPolygon_city
orig_subs = 7
new_building_subs = building_subs.count("[sub_resource")
load_steps = ext_resources + orig_subs + new_building_subs + 1

tscn = f"""[gd_scene load_steps={load_steps} format=3 uid="uid://city_level_581"]

[ext_resource type="Script" path="res://scripts/levels/city_level.gd" id="1_city"]
[ext_resource type="PackedScene" uid="uid://dv8nq2vj5r7p2" path="res://scenes/characters/csharp/Player.tscn" id="2_player"]
[ext_resource type="PackedScene" uid="uid://dxqmk8f3nw5pe" path="res://scenes/ui/PauseMenu.tscn" id="3_pause_menu"]
[ext_resource type="PackedScene" uid="uid://cx5m8np6u3bwd" path="res://scenes/objects/Enemy.tscn" id="4_enemy"]
[ext_resource type="Script" path="res://Scripts/Components/LevelInitFallback.cs" id="5_fallback"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_wall_h"]
size = Vector2(6064, 32)

[sub_resource type="RectangleShape2D" id="RectangleShape2D_wall_v"]
size = Vector2(32, 5064)

[sub_resource type="OccluderPolygon2D" id="OccluderPolygon2D_wall_h"]
polygon = PackedVector2Array(-3032, -16, 3032, -16, 3032, 16, -3032, 16)

[sub_resource type="OccluderPolygon2D" id="OccluderPolygon2D_wall_v"]
polygon = PackedVector2Array(-16, -2532, 16, -2532, 16, 2532, -16, 2532)

[sub_resource type="RectangleShape2D" id="RectangleShape2D_cover"]
size = Vector2(80, 32)

[sub_resource type="OccluderPolygon2D" id="OccluderPolygon2D_cover"]
polygon = PackedVector2Array(-40, -16, 40, -16, 40, 16, -40, 16)

[sub_resource type="NavigationPolygon" id="NavigationPolygon_city"]
vertices = PackedVector2Array(64, 64, 6064, 64, 6064, 5064, 64, 5064)
polygons = [PackedInt32Array(0, 1, 2, 3)]
outlines = [PackedVector2Array(64, 64, 6064, 64, 6064, 5064, 64, 5064)]
parsed_geometry_type = 1
parsed_collision_mask = 4
source_geometry_mode = 0
source_geometry_group_name = &"navigation_source"
agent_radius = 24.0

{building_subs}

[node name="CityLevel" type="Node2D"]
script = ExtResource("1_city")

[node name="LevelInitFallback" type="Node" parent="."]
script = ExtResource("5_fallback")

[node name="Environment" type="Node2D" parent="."]

[node name="Background" type="ColorRect" parent="Environment"]
offset_right = 6128.0
offset_bottom = 5128.0
color = Color(0.12, 0.12, 0.14, 1)

[node name="Floor" type="ColorRect" parent="Environment"]
offset_left = 64.0
offset_top = 64.0
offset_right = 6064.0
offset_bottom = 5064.0
color = Color(0.25, 0.22, 0.2, 1)

[node name="Walls" type="Node2D" parent="Environment"]

[node name="WallTop" type="StaticBody2D" parent="Environment/Walls"]
position = Vector2(3064, 48)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Walls/WallTop"]
offset_left = -3032.0
offset_top = -16.0
offset_right = 3032.0
offset_bottom = 16.0
color = Color(0.35, 0.28, 0.22, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Walls/WallTop"]
shape = SubResource("RectangleShape2D_wall_h")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Walls/WallTop"]
occluder = SubResource("OccluderPolygon2D_wall_h")

[node name="WallBottom" type="StaticBody2D" parent="Environment/Walls"]
position = Vector2(3064, 5080)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Walls/WallBottom"]
offset_left = -3032.0
offset_top = -16.0
offset_right = 3032.0
offset_bottom = 16.0
color = Color(0.35, 0.28, 0.22, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Walls/WallBottom"]
shape = SubResource("RectangleShape2D_wall_h")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Walls/WallBottom"]
occluder = SubResource("OccluderPolygon2D_wall_h")

[node name="WallLeft" type="StaticBody2D" parent="Environment/Walls"]
position = Vector2(48, 2564)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Walls/WallLeft"]
offset_left = -16.0
offset_top = -2532.0
offset_right = 16.0
offset_bottom = 2532.0
color = Color(0.35, 0.28, 0.22, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Walls/WallLeft"]
shape = SubResource("RectangleShape2D_wall_v")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Walls/WallLeft"]
occluder = SubResource("OccluderPolygon2D_wall_v")

[node name="WallRight" type="StaticBody2D" parent="Environment/Walls"]
position = Vector2(6080, 2564)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Walls/WallRight"]
offset_left = -16.0
offset_top = -2532.0
offset_right = 16.0
offset_bottom = 2532.0
color = Color(0.35, 0.28, 0.22, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Walls/WallRight"]
shape = SubResource("RectangleShape2D_wall_v")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Walls/WallRight"]
occluder = SubResource("OccluderPolygon2D_wall_v")

[node name="Buildings" type="Node2D" parent="Environment"]

{building_nodes}

[node name="Cover" type="Node2D" parent="Environment"]

[node name="Cover1" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(500, 1300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover1"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover1"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover1"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Cover2" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(1400, 1300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover2"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover2"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover2"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Cover3" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(3000, 1300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover3"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover3"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover3"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Cover4" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(4600, 1300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover4"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover4"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover4"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Cover5" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(2200, 2300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover5"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover5"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover5"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Cover6" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(4000, 2300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover6"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover6"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover6"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Cover7" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(1000, 3300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover7"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover7"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover7"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Cover8" type="StaticBody2D" parent="Environment/Cover"]
position = Vector2(5000, 3300)
collision_layer = 4
collision_mask = 0

[node name="ColorRect" type="ColorRect" parent="Environment/Cover/Cover8"]
offset_left = -40.0
offset_top = -16.0
offset_right = 40.0
offset_bottom = 16.0
color = Color(0.4, 0.35, 0.3, 1)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Environment/Cover/Cover8"]
shape = SubResource("RectangleShape2D_cover")

[node name="LightOccluder2D" type="LightOccluder2D" parent="Environment/Cover/Cover8"]
occluder = SubResource("OccluderPolygon2D_cover")

[node name="Enemies" type="Node2D" parent="Environment"]

[node name="SniperEnemy1" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(5600, 400)
behavior_mode = 1
weapon_type = 3
detection_range = 0.0
fov_angle = 360.0
fov_enabled = false
destroy_on_death = true
min_health = 3
max_health = 5
enable_flanking = false
enable_cover = true

[node name="SniperEnemy2" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(5600, 4700)
behavior_mode = 1
weapon_type = 3
detection_range = 0.0
fov_angle = 360.0
fov_enabled = false
destroy_on_death = true
min_health = 3
max_health = 5
enable_flanking = false
enable_cover = true

[node name="GuardEnemy1" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(1200, 1200)
behavior_mode = 1
destroy_on_death = true
enable_flanking = true
enable_cover = true

[node name="GuardEnemy2" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(2400, 1200)
behavior_mode = 1
destroy_on_death = true
enable_flanking = true
enable_cover = true

[node name="GuardEnemy3" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(3600, 2300)
behavior_mode = 1
weapon_type = 1
destroy_on_death = true
enable_flanking = true
enable_cover = true

[node name="GuardEnemy4" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(4800, 2300)
behavior_mode = 1
weapon_type = 2
destroy_on_death = true
enable_flanking = true
enable_cover = true

[node name="PatrolEnemy1" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(2000, 3300)
behavior_mode = 0
destroy_on_death = true
enable_flanking = true
enable_cover = true
patrol_offsets = Array[Vector2]([Vector2(400, 0), Vector2(-400, 0)])

[node name="PatrolEnemy2" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(4000, 3300)
behavior_mode = 0
weapon_type = 2
destroy_on_death = true
enable_flanking = true
enable_cover = true
patrol_offsets = Array[Vector2]([Vector2(0, 300), Vector2(0, -300)])

[node name="GuardEnemy5" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(1400, 4200)
behavior_mode = 1
destroy_on_death = true
enable_flanking = true
enable_cover = true

[node name="GuardEnemy6" parent="Environment/Enemies" instance=ExtResource("4_enemy")]
position = Vector2(3400, 4200)
behavior_mode = 1
weapon_type = 1
destroy_on_death = true
enable_flanking = true
enable_cover = true

[node name="NavigationRegion2D" type="NavigationRegion2D" parent="."]
navigation_polygon = SubResource("NavigationPolygon_city")

[node name="Entities" type="Node2D" parent="."]

[node name="Player" parent="Entities" instance=ExtResource("2_player")]
position = Vector2(300, 2500)

[node name="CanvasLayer" type="CanvasLayer" parent="."]

[node name="UI" type="Control" parent="CanvasLayer"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="LevelLabel" type="Label" parent="CanvasLayer/UI"]
layout_mode = 0
offset_left = -200.0
offset_top = 10.0
offset_right = -10.0
offset_bottom = 40.0
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
grow_horizontal = 0
text = "CITY"
horizontal_alignment = 2

[node name="EnemyCountLabel" type="Label" parent="CanvasLayer/UI"]
layout_mode = 0
offset_left = -200.0
offset_top = 40.0
offset_right = -10.0
offset_bottom = 75.0
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
grow_horizontal = 0
text = "Enemies: 0"
horizontal_alignment = 2

[node name="AmmoLabel" type="Label" parent="CanvasLayer/UI"]
layout_mode = 0
offset_left = 10.0
offset_top = 10.0
offset_right = 200.0
offset_bottom = 40.0
text = "AMMO: -/-"

[node name="PauseMenu" parent="CanvasLayer" instance=ExtResource("3_pause_menu")]
visible = false
"""

with open(f"{BASE}/scenes/levels/CityLevel.tscn", "w") as f:
    f.write(tscn)

print(f"CityLevel.tscn written: {len(tscn)} chars")
print(f"load_steps = {load_steps}")
