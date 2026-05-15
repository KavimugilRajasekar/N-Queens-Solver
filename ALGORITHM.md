# Region-Constrained Non-Adjacent Queens
> **Algorithm:** Constraint Satisfaction Problem (CSP) with Region Reduction

---

## 🎯 Goal
Place exactly one queen in each region on an $N \times N$ board such that:

*   **No two queens** share the same row.
*   **No two queens** share the same column.
*   **No queens touch** in 8-neighbour cells (King's move).
*   **Diagonals are allowed** (unlike standard N-Queens, unless they touch).
*   **Exactly one queen per region.**

---

## 🏗️ Data Structures

### Input
*   `regions_input`: `Map<String, List<(row, col)>>`

### Derived
*   `N`: Number of regions.
*   `regions`: `Map<String, Set<(r, c)>>` (converted to 0-index).
*   `regionKeys`: `List<String>`

### State Variables
*   `rowMask`: Integer bitmask.
*   `colMask`: Integer bitmask.
*   `blocked`: `Set<(r, c)>`
*   `regionCells`: `Map<String, Set<(r, c)>>`
*   `solution`: `Map<String, (r, c)>`

### Precomputed
*   `adjMask`: `Map<(r, c), Set<(r, c)>>`

---

## ⚙️ Core Functions

### 1. Build Adjacency Masks
```pseudocode
FUNCTION buildAdjacencyMasks()
    FOR r from 0 to N-1
        FOR c from 0 to N-1
            adj = empty set
            FOR dr in [-1, 0, 1]
                FOR dc in [-1, 0, 1]
                    IF dr == 0 AND dc == 0
                        CONTINUE
                    nr = r + dr
                    nc = c + dc
                    IF nr,nc inside board
                        add (nr,nc) to adj
            add (r,c) to adj
            adjMask[(r,c)] = adj
END
```

### 2. Validation
```pseudocode
FUNCTION isValid(r, c)
    IF rowMask has bit r set
        RETURN false
    IF colMask has bit c set
        RETURN false
    IF (r,c) in blocked
        RETURN false
    RETURN true
END
```

### 3. State Management
```pseudocode
FUNCTION applyMove(regionKey, r, c) RETURNS (removedMap, newBlocks)
    set bit r in rowMask
    set bit c in colMask

    newBlocks = adjMask[(r,c)]
    add all newBlocks into blocked

    removedMap = empty map

    FOR each key in regionCells
        IF key == regionKey
            CONTINUE

        toRemove = empty set

        FOR each (rr,cc) in regionCells[key]
            IF rr == r OR cc == c OR (rr,cc) in newBlocks
                add (rr,cc) to toRemove

        IF toRemove not empty
            remove all toRemove from regionCells[key]
            removedMap[key] = toRemove

    RETURN (removedMap, newBlocks)
END

FUNCTION undoMove(regionKey, r, c, removedMap, newBlocks)
    clear bit r from rowMask
    clear bit c from colMask

    FOR each key in removedMap
        add all removedMap[key] back into regionCells[key]

    FOR each cell in newBlocks
        remove cell from blocked
END
```

### 4. Heuristics
```pseudocode
FUNCTION selectRegionMRV() RETURNS String
    remaining = all keys in regionCells not in solution
    choose key with minimum size of regionCells[key]
    RETURN key
END
```

---

## 🧠 Solver Logic

```pseudocode
FUNCTION solve() RETURNS boolean
    IF size of solution == number of regions
        RETURN true

    key = selectRegionMRV()

    FOR each (r,c) in regionCells[key]
        IF isValid(r,c) == false
            CONTINUE

        solution[key] = (r,c)

        (removedMap, newBlocks) = applyMove(key, r, c)

        IF solve() == true
            RETURN true

        undoMove(key, r, c, removedMap, newBlocks)
        remove key from solution

    RETURN false
END
```

---

## 🚀 Execution Flow

### Main Procedure
1.  **Convert** `regions_input` to 0-index and store in `regions`.
2.  **Initialize** `regionCells` = deep copy of `regions` as sets.
3.  **Initialize** `rowMask = 0`, `colMask = 0`, `blocked = empty set`.
4.  **Build** adjacency masks using `buildAdjacencyMasks()`.
5.  **Call** `solve()`.

### Result Handling
*   **IF `solve()` is true**: `solution` contains one queen position per region.
*   **ELSE**: No solution exists.

---

## 📤 Output
*   **solution**: `Map<String, (row, col)>` representing queen placement.

---

## 🛠️ Optimization Techniques
*   **MRV (Minimum Remaining Values)**: Heuristic to choose the most constrained region first.
*   **Forward Checking (Region Reduction)**: Dynamically prune impossible cells in other regions.
*   **Bitmask Pruning**: Fast row and column conflict detection.
*   **Precomputed Adjacency**: Efficient King-move conflict checking.
*   **Backtracking with Undo Stack**: Optimized state restoration.

---
**END PROGRAM**