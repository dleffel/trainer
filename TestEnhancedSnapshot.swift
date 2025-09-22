//
//  TestEnhancedSnapshot.swift
//  Enhanced Schedule Snapshot Test
//
//  Test script to demonstrate the enhanced schedule snapshot functionality
//

import Foundation

// Test script to verify enhanced schedule snapshot generation
func testEnhancedScheduleSnapshot() {
    print("🧪 Testing Enhanced Schedule Snapshot Generation")
    print("=" * 60)
    
    // This would be run within the TrainerApp context
    let manager = TrainingScheduleManager.shared
    
    // Generate the enhanced snapshot
    let enhancedSnapshot = manager.generateScheduleSnapshot()
    
    print("📋 ENHANCED SCHEDULE SNAPSHOT OUTPUT:")
    print("-" * 40)
    print(enhancedSnapshot)
    print("-" * 40)
    
    // Verify key sections are present
    let expectedSections = [
        "## CURRENT SCHEDULE SNAPSHOT",
        "### TODAY'S FOCUS", 
        "### THIS WEEK PROGRESSION",
        "### BLOCK PROGRESSION CONTEXT",
        "### RECENT PERFORMANCE INDICATORS"
    ]
    
    var sectionsFound = 0
    for section in expectedSections {
        if enhancedSnapshot.contains(section) {
            print("✅ Found section: \(section)")
            sectionsFound += 1
        } else {
            print("❌ Missing section: \(section)")
        }
    }
    
    print("\n📊 ENHANCEMENT VERIFICATION:")
    print("- Sections found: \(sectionsFound)/\(expectedSections.count)")
    
    // Check for rich content indicators
    let richContentIndicators = [
        "**Duration**:",
        "**Focus**:",
        "**Intensity**:", 
        "**Status**:",
        "**Planned**:",
        "Week \\d+ Focus:", // regex pattern
        "Volume Completion:",
        "Block Adherence:"
    ]
    
    var richContentFound = 0
    for indicator in richContentIndicators {
        if enhancedSnapshot.range(of: indicator, options: .regularExpression) != nil {
            print("✅ Found rich content: \(indicator)")
            richContentFound += 1
        }
    }
    
    print("- Rich content indicators: \(richContentFound)/\(richContentIndicators.count)")
    
    // Calculate enhancement score
    let enhancementScore = (sectionsFound + richContentFound) / (expectedSections.count + richContentIndicators.count)
    print("- Enhancement score: \(Int(enhancementScore * 100))%")
    
    if enhancementScore >= 0.8 {
        print("\n🎉 SUCCESS: Enhanced schedule snapshot is working correctly!")
    } else {
        print("\n⚠️ WARNING: Enhanced schedule snapshot may need additional work")
    }
    
    // Show character count comparison
    print("\n📈 SNAPSHOT METRICS:")
    print("- Enhanced snapshot length: \(enhancedSnapshot.count) characters")
    print("- Previous minimal length: ~50-100 characters")
    print("- Enhancement factor: ~\(enhancedSnapshot.count / 75)x more detailed")
}

// MARK: - Comparison Demo

func demonstrateEnhancement() {
    print("\n🔍 BEFORE vs AFTER COMPARISON:")
    print("=" * 60)
    
    print("❌ OLD MINIMAL OUTPUT:")
    print("- **Tuesday**: Workout scheduled")
    print("- **Wednesday (TODAY)**: Workout planned ⚡")
    print("- **Thursday**: No workout")
    
    print("\n✅ NEW ENHANCED OUTPUT INCLUDES:")
    print("✓ Today's Focus - Detailed workout info, duration, focus, intensity")
    print("✓ Weekly Progression - All 7 days with status and workout details")
    print("✓ Block Context - Training goals, volume expectations, week focus")
    print("✓ Performance Indicators - Completion rates, adherence metrics")
    print("✓ Template Comparison - Expected vs planned workout details")
    print("✓ Smart Status Icons - ✅ ⚡ 📋 ❌ ⚪ for different workout states")
}

// Example output format
func showExpectedOutput() {
    print("\n📋 EXPECTED ENHANCED OUTPUT FORMAT:")
    print("=" * 60)
    
    let exampleOutput = """
    ## CURRENT SCHEDULE SNAPSHOT
    **Generated**: Oct 16, 2025 at 4:15 PM
    **Program**: Week 1 of 20 - Hypertrophy-Strength Block (Week 1 of 10)

    ### TODAY'S FOCUS
    **Thursday**: Strength - Upper + Z2
    - **Planned**: Upper body strength (press/pull) → 30-40' Z2 spin
    - **Duration**: 90 minutes
    - **Focus**: Hypertrophy (upper body); easy aerobic
    - **Intensity**: Strength + Z2
    - **Status**: Workout planned ⚡

    ### THIS WEEK PROGRESSION
    - **Monday**: Rest Day - Mobility + core (20') ✅ Completed
    - **Tuesday**: Lower + Z2 - Squat/hinge → erg Z2 (90') ✅ Completed
    - **Wednesday**: RowErg Z2 + Technique (60') ✅ Completed
    - **Thursday (TODAY)**: Upper + Z2 - Press/pull → bike Z2 (90') ⚡ PLANNED
    - **Friday**: Planned - Long Workout ❌ NEEDS PLANNING
    - **Saturday**: Planned - Long Workout ❌ NEEDS PLANNING
    - **Sunday**: Planned - Long Workout ❌ NEEDS PLANNING

    ### BLOCK PROGRESSION CONTEXT
    **Hypertrophy-Strength Block Goals**:
    - Primary: Build muscle mass and base strength
    - Volume: High training volume with moderate intensity
    - Expected: 5-6 sessions/week, 2-3 strength + 3-4 aerobic
    - Week 1 Focus: Establishing movement patterns and baseline loads

    ### RECENT PERFORMANCE INDICATORS
    - **Volume Completion**: 3/4 sessions completed this week
    - **Block Adherence**: On track with Hypertrophy-Strength block expectations
    - **Planning Needed**: 3 workouts still need planning
    """
    
    print(exampleOutput)
}

// Main test execution
if CommandLine.argc > 1 && CommandLine.arguments[1] == "test" {
    testEnhancedScheduleSnapshot()
    demonstrateEnhancement()
    showExpectedOutput()
}