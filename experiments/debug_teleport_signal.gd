extends Node

# Test script to debug the teleport sound signal connection issue
# This simulates the player initialization process to find where it's failing

func _ready():
	print("=== Teleport Sound Debug Test ===")
	
	# Test 1: Check if ActiveItemManager exists
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager == null:
		print("❌ FAIL: ActiveItemManager not found")
		return
	else:
		print("✅ PASS: ActiveItemManager found")
	
	# Test 2: Check if it has the expected signal
	if not active_item_manager.has_signal("active_item_changed"):
		print("❌ FAIL: active_item_changed signal not found")
		return
	else:
		print("✅ PASS: active_item_changed signal found")
	
	# Test 3: Check if it has the required methods
	if not active_item_manager.has_method("has_teleport_bracers"):
		print("❌ FAIL: has_teleport_bracers method not found")
		return
	else:
		print("✅ PASS: has_teleport_bracers method found")
	
	if not active_item_manager.has_method("has_homing_bullets"):
		print("❌ FAIL: has_homing_bullets method not found")
		return
	else:
		print("✅ PASS: has_homing_bullets method found")
	
	# Test 4: Check current active item status
	print("Current active item status:")
	print("  Has flashlight: ", active_item_manager.call("has_flashlight") if active_item_manager.has_method("has_flashlight") else "method_missing")
	print("  Has homing bullets: ", active_item_manager.call("has_homing_bullets") if active_item_manager.has_method("has_homing_bullets") else "method_missing")
	print("  Has teleport bracers: ", active_item_manager.call("has_teleport_bracers") if active_item_manager.has_method("has_teleport_bracers") else "method_missing")
	print("  Has invisibility suit: ", active_item_manager.call("has_invisibility_suit") if active_item_manager.has_method("has_invisibility_suit") else "method_missing")
	
	# Test 5: Try to connect the signal
	if not active_item_manager.active_item_changed.is_connected(_on_test_active_item_changed):
		print("Attempting to connect to active_item_changed signal...")
		active_item_manager.active_item_changed.connect(_on_test_active_item_changed)
		print("✅ PASS: Signal connected successfully")
	else:
		print("⚠️  WARN: Signal already connected")
	
	# Test 6: Try to emit signal manually to test
	print("Testing signal emission...")
	active_item_manager.active_item_changed.emit(3)  # TELEPORT_BRACERS = 3
	print("Signal emission test completed")

func _on_test_active_item_changed(new_type: int):
	print("🎯 Signal received! Active item changed to: %d" % new_type)
	match new_type:
		1: print("  -> Flashlight selected")
		2: print("  -> Homing bullets selected")
		3: print("  -> Teleport bracers selected")
		4: print("  -> Invisibility suit selected")
		_: print("  -> Unknown/None selected")