# SystemPrompt.md Reorganization Plan

## Current Structure Analysis

### Existing Sections:
- Section 0: IDENTITY & CORE CONFIGURATION ✓
- Section 1: LONG-TERM OBJECTIVES ✓
- Section 2: TRAINING CYCLE STRUCTURE ✓
  - 2.1: MACRO-CYCLE PATTERN ✓
  - 2.2: WEEKLY TEMPLATE ✓
  - 2.3: FIXED EQUIPMENT INVENTORY ✓
- **MISSING: Sections 3, 4, 5**
- Section 6: LOAD TRACKING & PROGRESSION ✓
- **MISSING: Section 7**
- Section 8: PROGRAM INITIALIZATION ✓
- Section 9: SESSION START PROTOCOL ✓
  - 9.1: EVERY SESSION WORKFLOW ✓
  - 9.6: ADAPTIVE PLANNING PROTOCOL ✓ (should be own section)
- **MISSING: Sections 10, 11, 12, 13**
- Section 14: AVAILABLE TOOLS ✓
  - 14.1: get_health_data ✓
  - 14.8: plan_workout ✓ (missing 14.2-14.7)
  - 14.9: update_workout ✓
  - 14.12: plan_next_workout ✓ (missing 14.10, 14.11)

## Proposed New Structure

### Sequential Renumbering Plan:
```
0. IDENTITY & CORE CONFIGURATION
1. LONG-TERM OBJECTIVES
2. TRAINING CYCLE STRUCTURE
   2.1 MACRO-CYCLE PATTERN (20 weeks)
   2.2 WEEKLY TEMPLATE (all blocks)
   2.3 FIXED EQUIPMENT INVENTORY
3. LOAD TRACKING & PROGRESSION (currently section 6)
4. PROGRAM INITIALIZATION (currently section 8)
5. SESSION START PROTOCOL (currently section 9)
   5.1 EVERY SESSION WORKFLOW (currently 9.1)
6. ADAPTIVE PLANNING PROTOCOL (currently 9.6, promote to main section)
7. AVAILABLE TOOLS (currently section 14)
   7.1 get_health_data (currently 14.1)
   7.2 plan_workout (currently 14.8)
   7.3 update_workout (currently 14.9)
   7.4 plan_next_workout (currently 14.12)
```

## Formatting Fixes Required

### 1. Replace Non-Standard Characters
- Replace all `│` with standard markdown formatting
- Use consistent `##` and `###` heading levels

### 2. Standardize Indentation
- Use standard markdown bullet points (`•` → `-`)
- Consistent spacing for code blocks and examples
- Proper nesting for subsections

### 3. Heading Hierarchy
- Section headers: `## N. SECTION NAME`
- Subsection headers: `### N.N SUBSECTION NAME`
- Remove decorative characters from headers

## Content Preservation Rules

1. **No content deletion** - All existing information must be preserved
2. **Maintain examples** - All JSON examples and tool usage samples stay intact
3. **Preserve formatting** - Code blocks, bullet points, and emphasis remain
4. **Keep structure** - Logical flow and relationships between sections maintained

## Implementation Steps

1. Create new properly numbered structure
2. Copy all content to appropriate sections
3. Fix all formatting inconsistencies
4. Validate all examples and tool calls are intact
5. Ensure markdown renders correctly

## Expected Outcome

- Clean, sequential section numbering (0-7)
- Consistent markdown formatting throughout
- Preserved content with improved readability
- Logical document structure for coaching system