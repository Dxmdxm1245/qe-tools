#!/usr/bin/env python3
"""Create dependency-free SVG plots for QE convergence tests."""

from __future__ import annotations

import csv
import html
import re
import sys
from collections import defaultdict
from pathlib import Path

RECOMMENDED_ECUT = 80


def duration_seconds(text: str) -> float:
    units = {"h": 3600.0, "m": 60.0, "s": 1.0}
    return sum(float(value) * units[unit] for value, unit in re.findall(r"([\d.]+)\s*([hms])", text))


def read_groups(csv_path: Path) -> dict[str, list[tuple[int, float, float]]]:
    groups: dict[str, list[tuple[int, float, float]]] = defaultdict(list)
    pattern = re.compile(r"^(primitive|supercell)_(ecut|k)(\d+)$")
    with csv_path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            match = pattern.match(row["case"])
            if not match or row["job_done"] != "yes" or not row["total_energy_Ry"]:
                continue
            cell, mode, x_value = match.groups()
            groups[f"{cell}_{mode}"].append(
                (int(x_value), float(row["total_energy_Ry"]), duration_seconds(row["wall_time"]))
            )
    return groups


def padded_range(values: list[float]) -> tuple[float, float]:
    low, high = min(values), max(values)
    span = high - low
    pad = span * 0.12 if span else max(abs(high) * 0.01, 1.0)
    return low - pad, high + pad


def tick_values(low: float, high: float, count: int = 5) -> list[float]:
    return [low + index * (high - low) / count for index in range(count + 1)]


def draw(group: str, values: list[tuple[int, float, float]], output_dir: Path) -> Path:
    cell, mode = group.split("_")
    values.sort()
    x_values = [float(value[0]) for value in values]
    energies = [value[1] for value in values]
    times = [value[2] for value in values]

    width, height = 1100, 760
    left, right, top, bottom = 155, 940, 90, 620
    x_low, x_high = padded_range(x_values)
    energy_low, energy_high = padded_range(energies)
    time_low, time_high = 0.0, max(times) * 1.12 if max(times) else 1.0

    def x_pos(value: float) -> float:
        return left + (value - x_low) * (right - left) / (x_high - x_low)

    def energy_y(value: float) -> float:
        return bottom - (value - energy_low) * (bottom - top) / (energy_high - energy_low)

    def time_y(value: float) -> float:
        return bottom - (value - time_low) * (bottom - top) / (time_high - time_low)

    energy_points = " ".join(f"{x_pos(x):.2f},{energy_y(y):.2f}" for x, y in zip(x_values, energies))
    time_points = " ".join(f"{x_pos(x):.2f},{time_y(y):.2f}" for x, y in zip(x_values, times))
    x_label = "ecutwfc (Ry)" if mode == "ecut" else "k-point mesh (N x N x N)"

    svg: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<g font-family="Times New Roman, serif" fill="black">',
        f'<text x="{(left + right) / 2:.1f}" y="45" text-anchor="middle" font-size="28">Si {html.escape(cell)} convergence</text>',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{bottom}" stroke="black" stroke-width="2"/>',
        f'<line x1="{left}" y1="{bottom}" x2="{right}" y2="{bottom}" stroke="black" stroke-width="2"/>',
        f'<line x1="{right}" y1="{top}" x2="{right}" y2="{bottom}" stroke="black" stroke-width="2"/>',
    ]

    for value in tick_values(energy_low, energy_high):
        y = energy_y(value)
        svg.extend(
            [
                f'<line x1="{left - 9}" y1="{y:.2f}" x2="{left}" y2="{y:.2f}" stroke="black" stroke-width="2"/>',
                f'<text x="{left - 18}" y="{y + 7:.2f}" text-anchor="end" font-size="20">{value:.6f}</text>',
            ]
        )

    for value in tick_values(time_low, time_high):
        y = time_y(value)
        svg.extend(
            [
                f'<line x1="{right}" y1="{y:.2f}" x2="{right + 9}" y2="{y:.2f}" stroke="black" stroke-width="2"/>',
                f'<text x="{right + 18}" y="{y + 7:.2f}" font-size="20">{value:.0f}</text>',
            ]
        )

    for value in x_values:
        x = x_pos(value)
        svg.extend(
            [
                f'<line x1="{x:.2f}" y1="{bottom}" x2="{x:.2f}" y2="{bottom + 9}" stroke="black" stroke-width="2"/>',
                f'<text x="{x:.2f}" y="{bottom + 38}" text-anchor="middle" font-size="20">{value:g}</text>',
            ]
        )

    svg.extend(
        [
            f'<polyline points="{energy_points}" fill="none" stroke="black" stroke-width="2"/>',
            f'<polyline points="{time_points}" fill="none" stroke="#2448d8" stroke-width="2"/>',
        ]
    )

    for x, energy in zip(x_values, energies):
        color = "#d62728" if mode == "ecut" and x == RECOMMENDED_ECUT else "black"
        svg.append(f'<rect x="{x_pos(x) - 5:.2f}" y="{energy_y(energy) - 5:.2f}" width="10" height="10" fill="{color}"/>')

    if mode == "ecut" and RECOMMENDED_ECUT in x_values:
        recommended_index = x_values.index(RECOMMENDED_ECUT)
        recommended_energy = energies[recommended_index]
        svg.append(
            f'<text x="{x_pos(RECOMMENDED_ECUT) - 8:.2f}" y="{energy_y(recommended_energy) - 14:.2f}" '
            f'text-anchor="end" font-size="18" fill="#d62728">recommended: {RECOMMENDED_ECUT} Ry</text>'
        )

    svg.extend(
        [
            f'<text x="{(left + right) / 2:.1f}" y="700" text-anchor="middle" font-size="25">{html.escape(x_label)}</text>',
            f'<text x="42" y="{(top + bottom) / 2:.1f}" text-anchor="middle" font-size="25" transform="rotate(-90 42 {(top + bottom) / 2:.1f})">Total Energy (Ry)</text>',
            f'<text x="1070" y="{(top + bottom) / 2:.1f}" text-anchor="middle" font-size="25" transform="rotate(90 1070 {(top + bottom) / 2:.1f})">time (s)</text>',
            '<line x1="700" y1="78" x2="755" y2="78" stroke="black" stroke-width="2"/>',
            '<rect x="722" y="73" width="10" height="10" fill="black"/>',
            '<text x="770" y="86" font-size="23">Total Energy</text>',
            '<line x1="700" y1="112" x2="755" y2="112" stroke="#2448d8" stroke-width="2"/>',
            '<text x="770" y="120" font-size="23">time</text>',
            "</g>",
            "</svg>",
        ]
    )

    output = output_dir / f"{group}_convergence.svg"
    output.write_text("\n".join(svg) + "\n", encoding="utf-8")
    return output


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 qe_plot_convergence.py convergence/ecut/summary.csv")
    csv_path = Path(sys.argv[1]).resolve()
    for group, values in read_groups(csv_path).items():
        print(f"Plot: {draw(group, values, csv_path.parent)}")


if __name__ == "__main__":
    main()
