// The parts of a screen's top edge that lead nowhere: the bar peeks over a fullscreen window when the pointer is pushed
// against them. A part another screen's bottom edge touches is the way up to that screen, and has no barrier, as
// GNOME's hot corners leave an edge with a neighbour alone. Plain arithmetic on {x, y, width, height}, with no import,
// so that it can be checked on its own (node build_files/shared/test-bars-edge.mjs).

// The [x1, x2) spans of `monitor`'s top edge that no monitor of `monitors` sits right above
export function freeTopEdge(monitor, monitors) {
    let spans = [[monitor.x, monitor.x + monitor.width]];
    for (const other of monitors) {
        if (other === monitor || other.y + other.height !== monitor.y)
            continue;
        const [a, b] = [other.x, other.x + other.width];
        spans = spans.flatMap(([x1, x2]) => {
            if (b <= x1 || a >= x2)
                return [[x1, x2]];
            const left = a > x1 ? [[x1, a]] : [];
            const right = b < x2 ? [[b, x2]] : [];
            return [...left, ...right];
        });
    }
    return spans.filter(([x1, x2]) => x2 > x1);
}
