#!/usr/bin/env python3
"""Compare per-atom QE forces against the highest completed ecut calculation."""

from __future__ import annotations

import csv
import math
import re
import sys
from pathlib import Path


FORCE_RE = re.compile(
    r"atom\s+(\d+)\s+type\s+\d+\s+force\s*=\s*"
    r"([-+\d.Ee]+)\s+([-+\d.Ee]+)\s+([-+\d.Ee]+)"
)
ECUT_RE = re.compile(r"supercell_ecut(\d+)\.pw\.out$")


def read_forces(output: Path) -> list[tuple[float, float, float]]:
    forces: dict[int, tuple[float, float, float]] = {}
    for line in output.read_text(encoding="utf-8", errors="replace").splitlines():
        match = FORCE_RE.search(line)
        if match:
            atom = int(match.group(1))
            forces[atom] = tuple(float(match.group(index)) for index in range(2, 5))
    if not forces:
        raise ValueError(f"No per-atom forces found in {output}")
    return [forces[index] for index in sorted(forces)]


def max_force_difference(
    forces: list[tuple[float, float, float]],
    reference: list[tuple[float, float, float]],
) -> float:
    if len(forces) != len(reference):
        raise ValueError("Compared calculations contain different atom counts")
    return max(
        math.sqrt(sum((component - ref_component) ** 2 for component, ref_component in zip(force, ref)))
        for force, ref in zip(forces, reference)
    )


def write_svg(rows: list[tuple[int, float]], output: Path, reference_ecut: int) -> None:
    width, height = 1060, 720
    left, right, top, bottom = 155, 930, 90, 590
    x_values = [row[0] for row in rows]
    y_values = [row[1] for row in rows]
    x_low, x_high = min(x_values), max(x_values)
    x_pad = max((x_high - x_low) * 0.08, 1.0)
    x_low, x_high = x_low - x_pad, x_high + x_pad
    y_high = max(max(y_values) * 1.14, 1.0e-8)

    def x_pos(value: float) -> float:
        return left + (value - x_low) * (right - left) / (x_high - x_low)

    def y_pos(value: float) -> float:
        return bottom - value * (bottom - top) / y_high

    points = " ".join(f"{x_pos(x):.2f},{y_pos(y):.2f}" for x, y in rows)
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<g font-family="Times New Roman, serif" fill="black">',
        f'<text x="{(left + right) / 2:.1f}" y="45" text-anchor="middle" font-size="27">Si supercell force convergence</text>',
        f'<text x="{(left + right) / 2:.1f}" y="75" text-anchor="middle" font-size="18">Reference: ecutwfc = {reference_ecut} Ry</text>',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{bottom}" stroke="black" stroke-width="2"/>',
        f'<line x1="{left}" y1="{bottom}" x2="{right}" y2="{bottom}" stroke="black" stroke-width="2"/>',
    ]
    for index in range(6):
        value = y_high * index / 5
        y = y_pos(value)
        svg.extend(
            [
                f'<line x1="{left - 9}" y1="{y:.2f}" x2="{left}" y2="{y:.2f}" stroke="black" stroke-width="2"/>',
                f'<text x="{left - 18}" y="{y + 7:.2f}" text-anchor="end" font-size="19">{value:.2e}</text>',
            ]
        )
    for value in x_values:
        x = x_pos(value)
        svg.extend(
            [
                f'<line x1="{x:.2f}" y1="{bottom}" x2="{x:.2f}" y2="{bottom + 9}" stroke="black" stroke-width="2"/>',
                f'<text x="{x:.2f}" y="{bottom + 36}" text-anchor="middle" font-size="19">{value}</text>',
            ]
        )
    svg.extend(
        [
            f'<polyline points="{points}" fill="none" stroke="#2448d8" stroke-width="2"/>',
            f'<text x="{(left + right) / 2:.1f}" y="665" text-anchor="middle" font-size="24">ecutwfc (Ry)</text>',
            f'<text x="38" y="{(top + bottom) / 2:.1f}" text-anchor="middle" font-size="23" transform="rotate(-90 38 {(top + bottom) / 2:.1f})">max force difference (Ry/Bohr)</text>',
        ]
    )
    for x, y in rows:
        svg.append(f'<circle cx="{x_pos(x):.2f}" cy="{y_pos(y):.2f}" r="5" fill="#2448d8"/>')
    svg.extend(["</g>", "</svg>"])
    output.write_text("\n".join(svg) + "\n", encoding="utf-8")


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "convergence/ecut").resolve()
    calculations: dict[int, Path] = {}
    for output in root.glob("supercell_ecut*/supercell_ecut*.pw.out"):
        match = ECUT_RE.search(output.name)
        if match and "JOB DONE" in output.read_text(encoding="utf-8", errors="replace"):
            calculations[int(match.group(1))] = output
    if len(calculations) < 2:
        raise SystemExit("Need at least two completed supercell ecut calculations")

    reference_ecut = max(calculations)
    reference = read_forces(calculations[reference_ecut])
    rows = [(ecut, max_force_difference(read_forces(output), reference)) for ecut, output in sorted(calculations.items())]
    reference_max_force = max(math.sqrt(sum(component**2 for component in force)) for force in reference)

    csv_path = root / "supercell_force_convergence.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["ecutwfc_Ry", "reference_ecutwfc_Ry", "max_force_difference_Ry_Bohr"])
        writer.writerows((ecut, reference_ecut, f"{difference:.10e}") for ecut, difference in rows)

    svg_path = root / "supercell_force_convergence.svg"
    write_svg(rows, svg_path, reference_ecut)
    print(f"CSV:  {csv_path}")
    print(f"Plot: {svg_path}")
    if reference_max_force < 1.0e-5:
        print(
            "WARNING: reference forces are nearly zero. This equilibrium high-symmetry "
            "cell is not suitable for quantitative force-convergence testing. "
            "Use a displaced supercell instead."
        )
    for ecut, difference in rows:
        print(f"{ecut:>3} Ry  {difference:.10e} Ry/Bohr")


if __name__ == "__main__":
    main()
