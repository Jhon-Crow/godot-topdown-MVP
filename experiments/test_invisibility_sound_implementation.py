#!/usr/bin/env python3
"""
Test script to verify invisibility sound implementation.
This script checks that the invisibility effect file has the correct audio integration.
"""

import os
import sys
import re

def check_invisibility_suit_effect():
    """Check that invisibility_suit_effect.gd has the correct audio integration."""
    
    script_path = "scripts/effects/invisibility_suit_effect.gd"
    
    if not os.path.exists(script_path):
        print(f"ERROR: {script_path} not found")
        return False
    
    with open(script_path, 'r') as f:
        content = f.read()
    
    # Check for audio constants
    required_constants = [
        "ACTIVATION_SOUND_PATH",
        "DEACTIVATION_SOUND_PATH"
    ]
    
    for const in required_constants:
        if const not in content:
            print(f"ERROR: Missing constant {const}")
            return False
    
    # Check for audio player variables
    required_variables = [
        "_activation_audio_player",
        "_deactivation_audio_player"
    ]
    
    for var in required_variables:
        if var not in content:
            print(f"ERROR: Missing variable {var}")
            return False
    
    # Check for audio setup function
    if "_setup_audio()" not in content:
        print("ERROR: Missing _setup_audio() call")
        return False
    
    # Check for audio play functions
    required_functions = [
        "_play_activation_sound()",
        "_play_deactivation_sound()"
    ]
    
    for func in required_functions:
        if func not in content:
            print(f"ERROR: Missing function {func}")
            return False
    
    # Check that activation sound is played in activate()
    if "_play_activation_sound()" not in content.split("func activate()")[1].split("func")[0]:
        print("ERROR: Activation sound not played in activate() function")
        return False
    
    # Check that deactivation sound is played in deactivate()
    if "_play_deactivation_sound()" not in content.split("func deactivate()")[1].split("func")[0]:
        print("ERROR: Deactivation sound not played in deactivate() function")
        return False
    
    # Check that deactivation sound is played in force_stop()
    if "_play_deactivation_sound()" not in content.split("func force_stop()")[1].split("func")[0]:
        print("ERROR: Deactivation sound not played in force_stop() function")
        return False
    
    # Check for correct sound paths
    if "res://assets/audio/invisibility_activation.wav" not in content:
        print("ERROR: Incorrect activation sound path")
        return False
    
    if "res://assets/audio/invisibility_deactivation.wav" not in content:
        print("ERROR: Incorrect deactivation sound path")
        return False
    
    print("SUCCESS: All audio integration checks passed")
    return True

def check_audio_files():
    """Check that the audio files exist."""
    
    required_files = [
        "assets/audio/invisibility_activation.wav",
        "assets/audio/invisibility_deactivation.wav"
    ]
    
    for file_path in required_files:
        if not os.path.exists(file_path):
            print(f"ERROR: Audio file {file_path} not found")
            return False
        print(f"FOUND: {file_path}")
    
    return True

def main():
    """Main test function."""
    print("Testing invisibility sound implementation...")
    print("=" * 50)
    
    # Check audio files exist
    print("Checking audio files...")
    if not check_audio_files():
        sys.exit(1)
    
    print()
    print("Checking script integration...")
    if not check_invisibility_suit_effect():
        sys.exit(1)
    
    print()
    print("All tests passed! 🎉")
    print("The invisibility suit should now play:")
    print("- Activation sound when cloak is engaged")
    print("- Deactivation sound when cloak is disengaged (fade out or force stop)")

if __name__ == "__main__":
    main()