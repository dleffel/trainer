import Foundation

/// Manages training block generation and scheduling logic
/// Extracted from TrainingScheduleManager for better separation of concerns
class TrainingBlockScheduler {
    
    // MARK: - Block Generation
    
    /// Generate all training blocks for a macro-cycle
    func generateBlocks(from startDate: Date, macroCycle: Int) -> [TrainingBlock] {
        let calendar = Calendar.current
        
        // Start with Hypertrophy-Strength as per System Prompt
        let blockDurations: [(BlockType, Int)] = [
            (.hypertrophyStrength, 10),
            (.deload, 1),
            (.aerobicCapacity, 8),
            (.deload, 1)
        ]
        
        var blocks: [TrainingBlock] = []
        var currentStartDate = startDate
        
        for (blockType, duration) in blockDurations {
            let endDate = calendar.date(byAdding: .weekOfYear, value: duration, to: currentStartDate)!
            
            let block = TrainingBlock(
                type: blockType,
                startDate: currentStartDate,
                endDate: endDate,
                weekNumber: blocks.count + 1
            )
            blocks.append(block)
            
            currentStartDate = endDate
        }
        
        return blocks
    }
    
    // MARK: - Block Lookup
    
    /// Find the current block and week within that block for a given date
    func getCurrentBlock(for date: Date, in blocks: [TrainingBlock]) -> (block: TrainingBlock, weekInBlock: Int)? {
        for block in blocks {
            if block.contains(date: date) {
                // Calculate week within block
                let calendar = Calendar.current
                let weeksSinceBlockStart = calendar.dateComponents([.weekOfYear],
                                                                   from: block.startDate,
                                                                   to: date).weekOfYear ?? 0
                let weekInBlock = weeksSinceBlockStart + 1
                
                return (block, weekInBlock)
            }
        }
        
        return nil
    }
    
    /// Get block for a specific date
    func getBlock(for date: Date, in blocks: [TrainingBlock]) -> TrainingBlock? {
        return blocks.first(where: { $0.contains(date: date) })
    }
    
    /// Get block information for a given week number (1-20)
    func getBlockInfo(for weekNumber: Int) -> (type: BlockType, weekInBlock: Int) {
        if weekNumber <= 10 {
            return (.hypertrophyStrength, weekNumber)
        } else if weekNumber == 11 {
            return (.deload, 1)
        } else if weekNumber <= 19 {
            return (.aerobicCapacity, weekNumber - 11)
        } else {
            return (.deload, 1)
        }
    }
}