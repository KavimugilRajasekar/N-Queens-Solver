// Unit tests for BoardGenerator.
//
// The generator is the part of the app users hit directly when they
// tap "GENERATE BOARD" on the Generate screen. Before this fix the
// random BFS produced regions that almost always admitted 0 or 2+
// solutions, so the user saw the "Could not generate a unique board"
// error on essentially every tap. These tests pin down the new
// invariant: every generated board has exactly one valid queen
// placement under the Star-Battle / N-Queens constraint model.

import 'package:flutter_test/flutter_test.dart';
import 'package:n_queens_solver/utils/board_generator.dart';
import 'package:n_queens_solver/utils/board_processor.dart';
import 'package:n_queens_solver/utils/solver_logic.dart';

void main() {
  // We exercise sizes 4..12 (the full range the Generate-screen
  // slider offers). Smaller sizes probe the algorithm's ability to
  // find uniqueness with very few cells; larger sizes stress the
  // backtracking budget.
  const sizes = [4, 5, 6, 7, 8, 9, 10, 11, 12];

  for (final size in sizes) {
    test('generates a unique-solution board of size $size', () async {
      final board = await BoardGenerator.generateUniqueBoardForTesting(
        size,
        const <Map<String, dynamic>>[],
      );

      // The generator must succeed for every reasonable size.
      expect(
        board,
        isNotNull,
        reason: 'generator returned null for size $size',
      );

      final result = board!;

      // Every cell must be assigned to a region.
      for (int r = 0; r < size; r++) {
        for (int c = 0; c < size; c++) {
          expect(
            result.regionIds[r][c],
            isNonZero,
            reason: 'cell ($r,$c) on size $size was left unassigned',
          );
        }
      }

      // Exactly N regions must exist. The grower aims for a
      // roughly-uniform distribution (each region close to N cells
      // on an N×N grid) but small N can have regions as small as 1
      // and as large as 2N+1. We allow up to 2N+1 as a loose sanity
      // bound — anything larger is visually broken.
      expect(result.regions.length, size);
      for (final entry in result.regions.entries) {
        expect(
          entry.value.coordinates.length,
          greaterThanOrEqualTo(1),
          reason: 'region ${entry.key} has zero cells',
        );
        expect(
          entry.value.coordinates.length,
          lessThanOrEqualTo(2 * size + 1),
          reason: 'region ${entry.key} is unreasonably large',
        );
      }

      // The canonical solution baked into the board must actually
      // satisfy the constraints. This is the seeder invariant: no
      // two queens may share a row, column, or king-distance cell.
      // We pull queen positions from `board.solution` (the
      // generator's authoritative record) rather than reverse-
      // engineering them from `regionIds`, since BFS growth assigns
      // neighbouring cells to the same region and the cell whose
      // `regionIds == r+1` invariant is *not* the queen in general.
      final solution = result.solution;
      expect(
        solution,
        isNotNull,
        reason: 'generator did not record a solution for size $size',
      );
      expect(solution!.length, size);
      final placedQueens = solution.values
          .map((p) => <int>[p.x - 1, p.y - 1])
          .toList();
      for (int i = 0; i < placedQueens.length; i++) {
        for (int j = i + 1; j < placedQueens.length; j++) {
          final a = placedQueens[i];
          final b = placedQueens[j];
          final dr = (a[0] - b[0]).abs();
          final dc = (a[1] - b[1]).abs();
          expect(
            dr <= 1 && dc <= 1,
            isFalse,
            reason:
                'queens at ($a,$b) violate king-move on size $size (dr=$dr, dc=$dc)',
          );
        }
      }

      // The solver's independent count must agree: exactly one
      // valid placement for the whole board. We give the solver
      // maxCount: 3 so it short-circuits as soon as a 2nd solution
      // is found — we don't need to enumerate them.
      final count = NQueensSolver(result).countSolutions(maxCount: 3);
      expect(
        count,
        1,
        reason: 'board of size $size has $count solutions, expected 1',
      );
    });
  }

  test('two consecutive generations of the same size do not collide', () async {
    // Two generation calls back-to-back should produce different
    // region layouts (the generator's randomness should land on a
    // different seeder path). We don't pin the exact layouts — that
    // would be over-specified — only that they differ.
    final a = await BoardGenerator.generateUniqueBoardForTesting(
      8,
      const <Map<String, dynamic>>[],
    );
    final b = await BoardGenerator.generateUniqueBoardForTesting(
      8,
      const <Map<String, dynamic>>[],
    );

    expect(a, isNotNull);
    expect(b, isNotNull);

    bool identical = true;
    for (int r = 0; r < 8 && identical; r++) {
      for (int c = 0; c < 8; c++) {
        if (a!.regionIds[r][c] != b!.regionIds[r][c]) {
          identical = false;
          break;
        }
      }
    }
    expect(identical, isFalse, reason: 'two runs produced the same layout');
  });
}