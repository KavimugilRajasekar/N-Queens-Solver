import 'dart:ui';
import 'package:flutter/material.dart';
import 'board_processor.dart';

class SolverStep {
  final Map<int, Point> queenPositions;
  final Map<int, Set<Point>> domains; // Tracks valid cells per region
  final String message;
  final bool isBacktrack;
  final bool isConflict;

  SolverStep({
    required this.queenPositions,
    required this.domains,
    required this.message,
    this.isBacktrack = false,
    this.isConflict = false,
  });
}

class NQueensSolver {
  final BoardData boardData;
  final int n;
  
  // State Variables
  int _rowMask = 0;
  int _colMask = 0;
  final Set<String> _blocked = {};
  final Map<int, Set<Point>> _regionCells = {};
  final Map<int, Point> _solution = {};

  NQueensSolver(this.boardData) : n = boardData.size {
    boardData.regions.forEach((id, region) {
      _regionCells[id] = region.coordinates.toSet();
    });
  }

  Stream<SolverStep> solve() async* {
    yield SolverStep(
      queenPositions: {},
      domains: _cloneDomains(),
      message: "Initializing board. Every region has its full domain available.",
    );

    bool solved = false;
    await for (final step in _solveRecursiveStream()) {
      yield step;
      if (step.message == "Valid configuration found!") {
        solved = true;
      }
    }

    if (solved) {
      yield SolverStep(
        queenPositions: Map.from(_solution),
        domains: _cloneDomains(),
        message: "SUCCESS: All regions satisfied!",
      );
    } else {
      yield SolverStep(
        queenPositions: {},
        domains: _cloneDomains(),
        message: "FAILURE: Domain emptied. No solution possible.",
        isBacktrack: true,
      );
    }
  }

  Stream<SolverStep> _solveRecursiveStream() async* {
    if (_solution.length == n) {
      yield SolverStep(queenPositions: Map.from(_solution), domains: _cloneDomains(), message: "Valid configuration found!");
      return;
    }

    int? currentRegionId = _selectRegionMRV();
    if (currentRegionId == null) return;

    int candidateCount = _regionCells[currentRegionId]!.length;
    yield SolverStep(
      queenPositions: Map.from(_solution),
      domains: _cloneDomains(),
      message: "Selected Region $currentRegionId (Most constrained: $candidateCount cells left).",
    );

    final candidateCells = List<Point>.from(_regionCells[currentRegionId]!);
    
    for (var cell in candidateCells) {
      int r = cell.x - 1;
      int c = cell.y - 1;

      // Check Constraints
      if (!_isValid(r, c)) {
        // We don't yield every single conflict here to avoid bloat, 
        // but we show the confinement in the main steps.
        continue;
      }

      // Apply Move
      _solution[currentRegionId] = cell;
      final savedState = _applyMove(currentRegionId, r, c);
      
      int totalRemoved = savedState.removedCount;
      String confinementMsg = "";
      _regionCells.forEach((id, cells) {
        if (!_solution.containsKey(id) && cells.length == 1) {
          confinementMsg = "Region $id is now confined to 1 cell!";
        }
      });

      yield SolverStep(
        queenPositions: Map.from(_solution),
        domains: _cloneDomains(),
        message: "Placed Queen $currentRegionId at (${cell.x}, ${cell.y}). Reduced $totalRemoved cells from other regions.$confinementMsg",
      );

      // Recursive Call
      bool solved = false;
      await for (final subStep in _solveRecursiveStream()) {
        yield subStep;
        if (subStep.message == "Valid configuration found!") {
          solved = true;
          break;
        }
      }

      if (solved) return;

      // Undo Move
      _undoMove(currentRegionId, r, c, savedState);
      _solution.remove(currentRegionId);
      
      yield SolverStep(
        queenPositions: Map.from(_solution),
        domains: _cloneDomains(),
        message: "Backtracking from Region $currentRegionId (${cell.x}, ${cell.y}). Restoring $totalRemoved cells.",
        isBacktrack: true,
      );
    }
  }

  bool _isValid(int r, int c) {
    if ((_rowMask & (1 << r)) != 0) return false;
    if ((_colMask & (1 << c)) != 0) return false;
    if (_blocked.contains("$r,$c")) return false;
    return true;
  }

  Map<int, Set<Point>> _cloneDomains() {
    return _regionCells.map((key, value) => MapEntry(key, value.toSet()));
  }

  int? _selectRegionMRV() {
    int? bestId;
    int minSize = 100000;
    _regionCells.forEach((id, cells) {
      if (_solution.containsKey(id)) return;
      if (cells.length < minSize) {
        minSize = cells.length;
        bestId = id;
      }
    });
    return bestId;
  }

  _SavedMoveState _applyMove(int regionId, int r, int c) {
    _rowMask |= (1 << r);
    _colMask |= (1 << c);
    final List<String> newBlocks = [];
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        int nr = r + dr;
        int nc = c + dc;
        if (nr >= 0 && nr < n && nc >= 0 && nc < n) {
          String key = "$nr,$nc";
          if (!_blocked.contains(key)) {
            _blocked.add(key);
            newBlocks.add(key);
          }
        }
      }
    }

    int removedCount = 0;
    final Map<int, List<Point>> removedFromRegions = {};
    
    // 1. Clear the rest of the CURRENT region (as it's now satisfied)
    final currentRegionPoints = _regionCells[regionId]!;
    final restOfCurrent = currentRegionPoints.where((p) => p.x - 1 != r || p.y - 1 != c).toList();
    if (restOfCurrent.isNotEmpty) {
      removedFromRegions[regionId] = restOfCurrent;
      for (var p in restOfCurrent) currentRegionPoints.remove(p);
    }

    // 2. Remove invalid cells from OTHER regions
    _regionCells.forEach((id, cells) {
      if (id == regionId) return;
      final toRemove = cells.where((p) {
        int pr = p.x - 1;
        int pc = p.y - 1;
        // Standard N-Queens + Star Battle constraints
        return pr == r || pc == c || (pr - r).abs() <= 1 && (pc - c).abs() <= 1;
      }).toList();
      if (toRemove.isNotEmpty) {
        removedCount += toRemove.length;
        if (removedFromRegions.containsKey(id)) {
          removedFromRegions[id]!.addAll(toRemove);
        } else {
          removedFromRegions[id] = toRemove;
        }
        for (var p in toRemove) cells.remove(p);
      }
    });
    return _SavedMoveState(newBlocks, removedFromRegions, removedCount);
  }

  void _undoMove(int regionId, int r, int c, _SavedMoveState state) {
    _rowMask &= ~(1 << r);
    _colMask &= ~(1 << c);
    for (var key in state.newBlocks) _blocked.remove(key);
    state.removedFromRegions.forEach((id, cells) {
      _regionCells[id]!.addAll(cells);
    });
  }
}

class _SavedMoveState {
  final List<String> newBlocks;
  final Map<int, List<Point>> removedFromRegions;
  final int removedCount;
  _SavedMoveState(this.newBlocks, this.removedFromRegions, this.removedCount);
}
