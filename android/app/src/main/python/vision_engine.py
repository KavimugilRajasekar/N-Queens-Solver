import cv2
import numpy as np
from collections import defaultdict, deque

def process_image(image_path: str):
    """Detect the N‑Queens board, return its size and region mapping.

    Returns a dict:
        {
            "size": int,                     # detected N (grid dimension)
            "regions": {                     # region id → list of [col, row]
                "1": [[c, r], ...],
                ...
            }
        }
    """
    # ---------- STEP 1 : LOAD ----------
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Unable to read image at {image_path}")
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # ---------- STEP 2 : FIND BOARD ----------
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blur, 50, 150)
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    board_cnt = max(contours, key=cv2.contourArea)
    peri = cv2.arcLength(board_cnt, True)
    approx = cv2.approxPolyDP(board_cnt, 0.02 * peri, True)
    pts = approx.reshape(4, 2)

    # order points (top‑left, top‑right, bottom‑right, bottom‑left)
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1)
    tl = pts[np.argmin(s)]
    br = pts[np.argmax(s)]
    tr = pts[np.argmin(diff)]
    bl = pts[np.argmax(diff)]

    # ---------- STEP 3 : WARP ----------
    side = 900
    dst = np.array([[0, 0], [side, 0], [side, side], [0, side]], dtype="float32")
    M = cv2.getPerspectiveTransform(np.float32([tl, tr, br, bl]), dst)
    warp = cv2.warpPerspective(img, M, (side, side))

    # ---------- STEP 4 : DETECT GRID SIZE (N) ----------
    wgray = cv2.cvtColor(warp, cv2.COLOR_BGR2GRAY)
    th = cv2.adaptiveThreshold(
        wgray, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY_INV, 15, 4)
    # detect vertical lines
    vertical = cv2.morphologyEx(
        th, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 50)))
    proj = np.sum(vertical, axis=0)
    lines = np.where(proj > np.max(proj) * 0.5)[0]
    line_pos = []
    for x in lines:
        if not line_pos or x - line_pos[-1] > 10:
            line_pos.append(x)
    N = max(len(line_pos) - 1, 1)
    cell = side // N

    # ---------- STEP 5 : BUILD CELL COLOR GRID ----------
    def cell_color(r, c):
        y1, y2 = r * cell, (r + 1) * cell
        x1, x2 = c * cell, (c + 1) * cell
        patch = warp[y1:y2, x1:x2]
        avg = np.mean(patch.reshape(-1, 3), axis=0)
        return avg
    color_grid = [[cell_color(r, c) for c in range(N)] for r in range(N)]

    # ---------- STEP 6 : FLOOD FILL ON CELLS ----------
    visited = [[False] * N for _ in range(N)]
    regions = []
    THRESH = 30
    def similar(a, b):
        return np.linalg.norm(a - b) < THRESH
    for r in range(N):
        for c in range(N):
            if visited[r][c]:
                continue
            queue = deque([(r, c)])
            visited[r][c] = True
            base = color_grid[r][c]
            region = []
            while queue:
                x, y = queue.popleft()
                region.append([y + 1, x + 1])  # store as [col, row]
                for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < N and 0 <= ny < N and not visited[nx][ny]:
                        if similar(base, color_grid[nx][ny]):
                            visited[nx][ny] = True
                            queue.append((nx, ny))
            regions.append(region)

    # ---------- STEP 7 : RETURN ----------
    region_map = {str(i + 1): regions[i] for i in range(len(regions))}
    return {"size": N, "regions": region_map}
