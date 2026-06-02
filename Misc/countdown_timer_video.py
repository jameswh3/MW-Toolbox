#!/usr/bin/env python3
"""Generate a simple countdown timer video (dark background + mm:ss text)."""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import imageio.v2 as imageio
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def parse_duration(value: str) -> int:
    """Parse duration from seconds, mm:ss, or hh:mm:ss into total seconds."""
    value = value.strip()

    if value.isdigit():
        seconds = int(value)
        if seconds < 0:
            raise argparse.ArgumentTypeError("Duration must be non-negative.")
        return seconds

    parts = value.split(":")
    if len(parts) not in (2, 3):
        raise argparse.ArgumentTypeError(
            "Duration must be seconds, mm:ss, or hh:mm:ss (example: 90 or 01:30)."
        )

    if not all(part.isdigit() for part in parts):
        raise argparse.ArgumentTypeError("Duration contains non-numeric values.")

    if len(parts) == 2:
        minutes, seconds = map(int, parts)
        hours = 0
    else:
        hours, minutes, seconds = map(int, parts)

    if minutes >= 60 or seconds >= 60:
        raise argparse.ArgumentTypeError("Minutes and seconds must be between 0 and 59.")

    total_seconds = hours * 3600 + minutes * 60 + seconds
    return total_seconds


def format_mmss(total_seconds: int) -> str:
    """Format seconds as mm:ss (minutes can exceed 59)."""
    minutes = total_seconds // 60
    seconds = total_seconds % 60
    return f"{minutes:02d}:{seconds:02d}"


def parse_hex_color(value: str) -> tuple[int, int, int]:
    """Parse a hex color string (RRGGBB or #RRGGBB) into BGR tuple."""
    color = value.strip().lstrip("#")
    if len(color) != 6:
        raise argparse.ArgumentTypeError(
            "Color must be 6 hex characters, e.g. 0056a2 or #0056a2."
        )

    try:
        r = int(color[0:2], 16)
        g = int(color[2:4], 16)
        b = int(color[4:6], 16)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "Color must be valid hex, e.g. 000000 or ffffff."
        ) from exc

    return (b, g, r)


def compute_max_text_style(text: str, frame_size: int, font: int) -> tuple[float, int]:
    """Find the largest text scale/thickness that fits in the square frame."""
    padding = int(frame_size * 0.06)
    max_w = frame_size - (padding * 2)
    max_h = frame_size - (padding * 2)

    low = 0.1
    high = max(1.0, frame_size / 20.0)
    best_scale = low
    best_thickness = 2

    for _ in range(36):
        scale = (low + high) / 2.0
        thickness = max(2, int(scale * 2.6))
        (text_w, text_h), _ = cv2.getTextSize(text, font, scale, thickness)

        if text_w <= max_w and text_h <= max_h:
            best_scale = scale
            best_thickness = thickness
            low = scale
        else:
            high = scale

    return best_scale, best_thickness


def resolve_font_path(font_path: Path | None) -> Path | None:
    """Resolve a TrueType font path, preferring crisp Windows UI fonts."""
    if font_path is not None:
        candidate = Path(font_path)
        if candidate.exists():
            return candidate
        raise ValueError(f"Font file not found: {font_path}")

    windows_fonts = Path("C:/Windows/Fonts")
    candidates = [
        windows_fonts / "segoeuib.ttf",
        windows_fonts / "segoeui.ttf",
        windows_fonts / "arialbd.ttf",
        windows_fonts / "arial.ttf",
    ]

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return None


def compute_max_ttf_font_size(text: str, frame_size: int, font_path: Path) -> int:
    """Find the largest TrueType font size that fits in the square frame."""
    padding = int(frame_size * 0.06)
    max_w = frame_size - (padding * 2)
    max_h = frame_size - (padding * 2)

    probe = Image.new("RGB", (1, 1), (0, 0, 0))
    draw = ImageDraw.Draw(probe)

    low = 8
    high = frame_size
    best_size = low

    while low <= high:
        size = (low + high) // 2
        font = ImageFont.truetype(str(font_path), size=size)
        left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
        text_w = right - left
        text_h = bottom - top

        if text_w <= max_w and text_h <= max_h:
            best_size = size
            low = size + 1
        else:
            high = size - 1

    return best_size


def render_text_frame_ttf(
    text: str,
    size: int,
    font: ImageFont.FreeTypeFont,
    background_rgb: tuple[int, int, int],
    text_rgb: tuple[int, int, int],
) -> np.ndarray:
    """Render a single frame using Pillow for sharper TrueType text."""
    image = Image.new("RGB", (size, size), background_rgb)
    draw = ImageDraw.Draw(image)

    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    text_w = right - left
    text_h = bottom - top
    x = (size - text_w) // 2 - left
    y = (size - text_h) // 2 - top

    draw.text((x, y), text, font=font, fill=text_rgb)
    return np.asarray(image, dtype=np.uint8)


def generate_countdown_video(
    duration_seconds: int,
    output_path: Path,
    size: int,
    fps: int,
    font_path: Path | None = None,
    background_bgr: tuple[int, int, int] = (15, 15, 15),
    text_bgr: tuple[int, int, int] = (240, 240, 240),
) -> None:
    """Create a countdown timer video file."""
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Include one full second showing 00:00 at the end.
    total_frames = (duration_seconds + 1) * fps

    font = cv2.FONT_HERSHEY_SIMPLEX
    max_text = format_mmss(duration_seconds)
    resolved_font_path = resolve_font_path(font_path)

    use_ttf = resolved_font_path is not None
    if use_ttf:
        font_size = compute_max_ttf_font_size(max_text, size, resolved_font_path)
        ttf_font = ImageFont.truetype(str(resolved_font_path), size=font_size)
        background_rgb = (background_bgr[2], background_bgr[1], background_bgr[0])
        text_rgb = (text_bgr[2], text_bgr[1], text_bgr[0])
    else:
        scale, thickness = compute_max_text_style(max_text, size, font)

    frame_cache: dict[str, np.ndarray] = {}

    with imageio.get_writer(
        str(output_path),
        fps=fps,
        codec="libx264",
        pixelformat="yuv420p",
    ) as writer:
        for frame_idx in range(total_frames):
            elapsed_whole_seconds = frame_idx // fps
            remaining_seconds = max(duration_seconds - elapsed_whole_seconds, 0)
            text = format_mmss(remaining_seconds)

            if text not in frame_cache:
                if use_ttf:
                    frame_cache[text] = render_text_frame_ttf(
                        text=text,
                        size=size,
                        font=ttf_font,
                        background_rgb=background_rgb,
                        text_rgb=text_rgb,
                    )
                else:
                    frame = np.full((size, size, 3), background_bgr, dtype=np.uint8)

                    text_size, baseline = cv2.getTextSize(text, font, scale, thickness)
                    text_w, text_h = text_size
                    x = (size - text_w) // 2
                    y = (size + text_h) // 2

                    cv2.putText(
                        frame,
                        text,
                        (x, y),
                        font,
                        scale,
                        text_bgr,
                        thickness,
                        cv2.LINE_AA,
                    )
                    frame_cache[text] = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

            writer.append_data(frame_cache[text])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate a square countdown timer video with mm:ss text."
    )
    parser.add_argument(
        "--duration",
        required=True,
        type=parse_duration,
        help="Countdown length: seconds, mm:ss, or hh:mm:ss (examples: 90, 01:30, 00:10:00).",
    )
    parser.add_argument(
        "--output",
        default="countdown.mp4",
        type=Path,
        help="Output video path (default: countdown.mp4).",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=1080,
        help="Square video size in pixels (default: 1080 gives 1080x1080).",
    )
    parser.add_argument(
        "--fps",
        type=int,
        default=30,
        help="Frames per second (default: 30).",
    )
    parser.add_argument(
        "--font-path",
        type=Path,
        default=None,
        help=(
            "Optional path to a .ttf/.otf font file. "
            "If omitted, the script will try common Windows fonts for sharper text."
        ),
    )
    parser.add_argument(
        "--background-color",
        type=parse_hex_color,
        default=(0, 0, 0),
        help="Background color as hex (RRGGBB or #RRGGBB). Default: 000000.",
    )
    parser.add_argument(
        "--font-color",
        type=parse_hex_color,
        default=(255, 255, 255),
        help="Font color as hex (RRGGBB or #RRGGBB). Default: ffffff.",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if args.duration < 0:
        parser.error("Duration must be non-negative.")
    if args.size <= 0:
        parser.error("Size must be a positive integer.")
    if args.size % 2 != 0:
        parser.error("Size must be an even number for MP4 compatibility.")
    if args.fps <= 0:
        parser.error("FPS must be a positive integer.")

    generate_countdown_video(
        duration_seconds=args.duration,
        output_path=args.output,
        size=args.size,
        fps=args.fps,
        font_path=args.font_path,
        background_bgr=args.background_color,
        text_bgr=args.font_color,
    )

    print(f"Created countdown video: {args.output}")


if __name__ == "__main__":
    main()
