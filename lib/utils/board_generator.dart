import 'dart:math';
import 'board_processor.dart';
import 'solver_logic.dart';
import 'storage_manager.dart';
import '../constants/region_colors.dart';

/// Generates N-Queens + Star-Battle boards whose region layout admits
/// **exactly one** valid queen placement.
///
/// The strategy is *constructive*: first build a queen layout that
/// already satisfies the king-move (Star-Battle) constraint, then grow
/// regions one cell at a time and reject any growth step that would
/// make the puzzle solvable in 0 or 2+ ways. The candidate board is
/// only accepted once the layout is filled and a final
/// `countSolutions` check confirms exactly one answer.
class BoardGenerator {
  /// Outer cap on seed attempts before we give up and return `null`.
  /// Each attempt now produces a board with much higher success
  /// probability than the previous random BFS, so 120 gives a wide
  /// safety margin even at N=12.
  static const int _kMaxAttempts = 120;

  /// Per-attempt cap on how many tentative cell placements the
  /// grower tries (successful + rejected combined). Acts as a
  /// fail-safe against pathological sizes where the per-step
  /// uniqueness check rejects every candidate.
  static const int _kMaxGrowerTries = 60000;

  /// Returns `true` if cell (aR, aC) attacks cell (bR, bC) under the
  /// Star-Battle king-move rule. Matches the constraint model in
  /// `NQueensSolver._applyMove`.
  static bool _attacks(int aR, int aC, int bR, int bC) {
    if (aR == bR && aC == bC) return false;
    final dr = (aR - bR).abs();
    final dc = (aC - bC).abs();
    return dr <= 1 && dc <= 1;
  }

  /// Backtracking seeder: produces a permutation `queenCols[row] = col`
  /// such that no two queens are within king-distance 1. Returns
  /// `null` if no valid placement is found within the budget.
  ///
  /// We try several random column orderings per row before giving up;
  /// for N up to 12 the search space is tiny because the king-move
  /// constraint is much stricter than the standard N-Queens diagonal.
  static List<int>? _seedQueens(int n, Random rng) {
    final queenCols = List<int?>.filled(n, null);
    final colsUsed = List<bool>.filled(n, false);

    bool place(int row) {
      if (row == n) return true;
      final order = List<int>.generate(n, (i) => i)..shuffle(rng);
      for (final c in order) {
        if (colsUsed[c]) continue;
        // King-move check against already-placed queens.
        bool ok = true;
        for (int pr = 0; pr < row; pr++) {
          final pc = queenCols[pr]!;
          if (_attacks(pr, pc, row, c)) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        queenCols[row] = c;
        colsUsed[c] = true;
        if (place(row + 1)) return true;
        queenCols[row] = null;
        colsUsed[c] = false;
      }
      return false;
    }

    if (!place(0)) return null;
    return queenCols.cast<int>();
  }

  /// Builds a `BoardData` snapshot from the current `regionIds` and the
  /// queen layout. Used to feed `countSolutions` during BFS growth.
  static BoardData _snapshotBoard(
    int size,
    List<List<int>> regionIds,
    List<int> queenCols,
  ) {
    final regions = <int, BoardRegion>{};
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        final id = regionIds[r][c];
        if (id == 0) continue;
        regions
            .putIfAbsent(
              id,
              () => BoardRegion(
                id: id,
                color: RegionColors.getRegionColor(id, size),
                coordinates: <Point>[],
              ),
            )
            .coordinates
            .add(Point(r + 1, c + 1));
      }
    }
    final solution = <int, Point>{};
    for (int r = 0; r < size; r++) {
      solution[r + 1] = Point(r + 1, queenCols[r] + 1);
    }
    return BoardData(
      size: size,
      regionIds: regionIds,
      regions: regions,
      rawResponse: 'AI Generated',
      solution: solution,
    );
  }

  /// Grows regions from the queen seeds outward. After every cell
  /// claim we re-verify that the partial board still has exactly one
  /// solution; if not, we revert that claim and try the next
  /// candidate. This is the per-step pruning that keeps the search
  /// tree small.
  ///
  /// Growth strategy:
  ///   * Maintain a frontier (perimeter) for each region — the set of
  ///     cells already in the region that have at least one
  ///     unassigned neighbour.
  ///   * In each iteration pick the region with the *smallest* current
  ///     cell count (ties broken randomly). This keeps regions
  ///     roughly balanced (close to N cells each on an N×N grid) so
  ///     the visual layout looks right and the uniqueness check
  ///     doesn't get starved on one side.
  ///   * Among that region's candidates, prefer cells that already
  ///     touch 2+ other cells in the same region ("ink-spot" growth)
  ///     over cells that would extend a snake-like tail.
  ///   * Each candidate is tentatively claimed and re-verified with
  ///     `countSolutions(maxCount: 2)`. The first candidate that
  ///     preserves uniqueness wins. If no candidate from any region
  ///     works, the attempt restarts with a fresh seeder.
  static bool _growRegions({
    required int size,
    required List<List<int>> regionIds,
    required List<int> queenCols,
    required Random rng,
  }) {
    final dirs = <List<int>>[
      [0, 1],
      [0, -1],
      [1, 0],
      [-1, 0],
    ];

    // Per-region frontier: list of (r, c) cells currently assigned
    // to this region and adjacent to at least one unassigned cell.
    final frontiers = <int, List<Point>>{
      for (int i = 1; i <= size; i++) i: <Point>[],
    };
    final sizes = <int, int>{for (int i = 1; i <= size; i++) i: 0};

    for (int r = 0; r < size; r++) {
      final id = r + 1;
      final seed = Point(r, queenCols[r]);
      frontiers[id]!.add(seed);
      sizes[id] = 1;
    }

    int assigned = size; // seeds already in place
    int tries = 0;
    final maxTries = _kMaxGrowerTries;

    /// Counts how many 4-neighbours of (r, c) are already in `id`.
    int sameRegionNeighbourCount(int r, int c, int id) {
      int n = 0;
      for (final d in dirs) {
        final nr = r + d[0];
        final nc = c + d[1];
        if (nr >= 0 && nr < size && nc >= 0 && nc < size) {
          if (regionIds[nr][nc] == id) n++;
        }
      }
      return n;
    }

    while (assigned < size * size) {
      if (tries++ > maxTries) return false;

      // Pick the smallest region (ties broken randomly).
      final ids = List<int>.generate(size, (i) => i + 1);
      ids.shuffle(rng);
      ids.sort((a, b) => sizes[a]!.compareTo(sizes[b]!));

      bool progressed = false;
      for (final id in ids) {
        if (sizes[id]! >= 2 * size) continue;
        final frontier = frontiers[id]!;
        if (frontier.isEmpty) continue;

        // Build the candidate list: every unassigned neighbour of
        // every frontier cell, deduplicated. Tag each candidate with
        // its same-region neighbour count for compactness ordering.
        final seen = <int>{};
        final candidates = <_Candidate>[];
        for (final cell in frontier) {
          for (final d in dirs) {
            final nr = cell.x + d[0];
            final nc = cell.y + d[1];
            if (nr < 0 || nr >= size || nc < 0 || nc >= size) continue;
            if (regionIds[nr][nc] != 0) continue;
            final key = nr * size + nc;
            if (seen.contains(key)) continue;
            seen.add(key);
            candidates.add(
              _Candidate(
                nr,
                nc,
                sameRegionNeighbourCount(nr, nc, id),
              ),
            );
          }
        }
        if (candidates.isEmpty) continue;

        // Compactness-first ordering with random tie-breaking so
        // distinct attempts produce distinct layouts.
        candidates.shuffle(rng);
        candidates.sort((a, b) => b.neighbours.compareTo(a.neighbours));

        for (final cand in candidates) {
          // Tentative claim.
          regionIds[cand.r][cand.c] = id;
          final snap = _snapshotBoard(size, regionIds, queenCols);
          final count = NQueensSolver(snap).countSolutions(maxCount: 2);
          if (count == 1) {
            sizes[id] = sizes[id]! + 1;
            assigned++;
            frontier.add(Point(cand.r, cand.c));
            progressed = true;
            break;
          } else {
            regionIds[cand.r][cand.c] = 0;
          }
        }
        if (progressed) break;
      }

      if (!progressed) return false;
    }

    return true;
  }

  /// Final orphan sweep: any cell still 0 (shouldn't normally happen
  /// after a successful grow, but be safe) gets attached to the region
  /// of the nearest non-zero neighbour.
  static void _fillOrphans(int size, List<List<int>> regionIds) {
    final dirs = <List<int>>[
      [0, 1],
      [0, -1],
      [1, 0],
      [-1, 0],
    ];
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (regionIds[r][c] != 0) continue;
        for (final d in dirs) {
          final nr = r + d[0];
          final nc = c + d[1];
          if (nr >= 0 && nr < size && nc >= 0 && nc < size && regionIds[nr][nc] != 0) {
            regionIds[r][c] = regionIds[nr][nc];
            break;
          }
        }
      }
    }
  }

  /// Generates a new board of the given size that is guaranteed to
  /// have **exactly one valid solution**. Returns `null` when the
  /// search is exhausted (rare; reported back to the user).
  static Future<BoardData?> generateUniqueBoard(int size) async {
    final existingBoards = await StorageManager.loadBoards();
    return generateUniqueBoardForTesting(size, existingBoards);
  }

  /// Test-friendly entry point: generate a unique board while
  /// treating [existingBoards] as the already-saved library. Skips
  /// the `StorageManager.loadBoards()` round-trip so unit tests can
  /// run without `path_provider`. Production callers should keep
  /// using [generateUniqueBoard].
  static Future<BoardData?> generateUniqueBoardForTesting(
    int size,
    List<Map<String, dynamic>> existingBoards,
  ) async {
    final rng = Random();

    for (int attempt = 0; attempt < _kMaxAttempts; attempt++) {
      // 1. Seed: find a king-move-respecting N-Queens placement.
      final queenCols = _seedQueens(size, rng);
      if (queenCols == null) continue;

      // 2. Initial region map: each queen cell is its own region.
      final regionIds = List.generate(
        size,
        (_) => List<int>.filled(size, 0),
      );
      for (int r = 0; r < size; r++) {
        regionIds[r][queenCols[r]] = r + 1;
      }

      // 3. Grow regions with uniqueness-preserving BFS.
      final grew = _growRegions(
        size: size,
        regionIds: regionIds,
        queenCols: queenCols,
        rng: rng,
      );
      if (!grew) {
        _fillOrphans(size, regionIds);
        continue;
      }
      _fillOrphans(size, regionIds);

      // 4. Sanity: every cell assigned.
      bool complete = true;
      for (int r = 0; r < size && complete; r++) {
        for (int c = 0; c < size; c++) {
          if (regionIds[r][c] == 0) complete = false;
        }
      }
      if (!complete) continue;

      final board = _snapshotBoard(size, regionIds, queenCols);

      // 5. Library uniqueness check.
      bool layoutExists = existingBoards.any((eb) {
        final eBoard = eb['board'] as BoardData;
        if (eBoard.size != size) return false;
        for (int r = 0; r < size; r++) {
          for (int c = 0; c < size; c++) {
            if (eBoard.regionIds[r][c] != regionIds[r][c]) return false;
          }
        }
        return true;
      });
      if (layoutExists) continue;

      // 6. Final uniqueness check (the safety net the rest of the app
      // already trusts).
      final solver = NQueensSolver(board);
      final solutionCount = solver.countSolutions(maxCount: 2);
      if (solutionCount != 1) continue;

      return board;
    }

    return null; // Could not generate a valid unique one in time
  }
}

/// A candidate cell to grow into, tagged with how many of its
/// 4-neighbours are already in the same region. Higher neighbour
/// count = more compact growth.
class _Candidate {
  final int r;
  final int c;
  final int neighbours;

  _Candidate(this.r, this.c, this.neighbours);
}
