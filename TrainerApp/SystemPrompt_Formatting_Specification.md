# SystemPrompt.md Formatting Specification

## Specific Transformations Required

### 1. Section Header Transformations

**Current → Fixed:**
```markdown
## 0 │ IDENTITY & CORE CONFIGURATION
→ ## 0. IDENTITY & CORE CONFIGURATION

## 1 │ LONG‑TERM OBJECTIVES  
→ ## 1. LONG-TERM OBJECTIVES

## 2 │ TRAINING CYCLE STRUCTURE
→ ## 2. TRAINING CYCLE STRUCTURE

### 2.1 │ MACRO‑CYCLE PATTERN (20 weeks)
→ ### 2.1 MACRO-CYCLE PATTERN (20 weeks)

### 2.2 │ WEEKLY TEMPLATE (all blocks)
→ ### 2.2 WEEKLY TEMPLATE (all blocks)

### 2.3 │ FIXED EQUIPMENT INVENTORY 
→ ### 2.3 FIXED EQUIPMENT INVENTORY

## 6 │ LOAD TRACKING & PROGRESSION
→ ## 3. LOAD TRACKING & PROGRESSION

## 8 │ PROGRAM INITIALIZATION
→ ## 4. PROGRAM INITIALIZATION

## 9 │ SESSION START PROTOCOL
→ ## 5. SESSION START PROTOCOL

### 9.1 │ EVERY SESSION WORKFLOW
→ ### 5.1 EVERY SESSION WORKFLOW

## 9.6 │ ADAPTIVE PLANNING PROTOCOL
→ ## 6. ADAPTIVE PLANNING PROTOCOL

## 14 │ AVAILABLE TOOLS
→ ## 7. AVAILABLE TOOLS

### 14.1 │ get_health_data
→ ### 7.1 get_health_data

### 14.8 │ plan_workout
→ ### 7.2 plan_workout

### 14.9 │ update_workout
→ ### 7.3 update_workout

### 14.12 │ plan_next_workout
→ ### 7.4 plan_next_workout
```

### 2. Character Replacements

**Unicode Characters to Fix:**
- `│` (Box Drawing Light Vertical) → Remove entirely
- `‑` (Non-Breaking Hyphen) → `-` (Regular Hyphen)
- `–` (En Dash) → `-` (Regular Hyphen) 
- Remove trailing spaces from headers

### 3. Bullet Point Standardization

**Current → Fixed:**
```markdown
• Hypertrophy‑Strength block – 10 weeks
→ - Hypertrophy-Strength block - 10 weeks

• RowErg (Concept 2)
→ - RowErg (Concept 2)

• Data Capture: Store every exercise's load
→ - Data Capture: Store every exercise's load
```

### 4. Code Block Formatting

**Ensure consistent spacing:**
```markdown
**Decision Logic:**
```
START ANY SESSION
        ↓
```
→ **Decision Logic:**

```
START ANY SESSION
        ↓
```

### 5. Content Reorganization

**Move Section 9.6 to become Section 6:**
- Extract "ADAPTIVE PLANNING PROTOCOL" from subsection 9.6
- Promote to main section 6
- Renumber subsequent sections accordingly

### 6. Spacing and Indentation

**Standardize:**
- Remove extra blank lines (max 2 consecutive)
- Consistent indentation for nested lists
- Proper spacing around code blocks
- Standard markdown list formatting

## Final Structure Preview

```
# ROWING COACH GPT SYSTEM PROMPT

## 0. IDENTITY & CORE CONFIGURATION
## 1. LONG-TERM OBJECTIVES  
## 2. TRAINING CYCLE STRUCTURE
   ### 2.1 MACRO-CYCLE PATTERN (20 weeks)
   ### 2.2 WEEKLY TEMPLATE (all blocks)
   ### 2.3 FIXED EQUIPMENT INVENTORY
## 3. LOAD TRACKING & PROGRESSION
## 4. PROGRAM INITIALIZATION
## 5. SESSION START PROTOCOL
   ### 5.1 EVERY SESSION WORKFLOW
## 6. ADAPTIVE PLANNING PROTOCOL
## 7. AVAILABLE TOOLS
   ### 7.1 get_health_data
   ### 7.2 plan_workout
   ### 7.3 update_workout
   ### 7.4 plan_next_workout
```

## Quality Assurance Checklist

- [ ] All content preserved exactly
- [ ] Sequential numbering 0-7
- [ ] No non-standard Unicode characters
- [ ] Consistent markdown formatting
- [ ] Proper heading hierarchy
- [ ] All JSON examples intact
- [ ] Tool call syntax preserved
- [ ] Bullet points standardized
- [ ] Code blocks properly formatted
- [ ] No trailing whitespace

## Implementation Notes

This specification provides the exact transformations needed to clean up the SystemPrompt.md file while preserving all content and improving readability. The reorganization creates a logical flow from identity through tools, with consistent formatting throughout.