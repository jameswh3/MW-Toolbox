#!/usr/bin/env python3
"""
Icon Generator using Fluent UI System Icons
Generates square PNG images with circular backgrounds and icons from Microsoft's
Fluent UI System Icons library. Fetches icons on-demand from GitHub in real-time.

Usage:
    python icon_generator.py --icon home settings --size 256 --circle-color "#0078d4"
    python icon_generator.py --list
    python icon_generator.py --icon star --size 512 --circle-color "#1f883d" --icon-style filled
"""

import argparse
import sys
import json
import urllib.parse
from pathlib import Path
from typing import Optional, List, Tuple
from io import BytesIO
import urllib.request
import urllib.error

from PIL import Image, ImageDraw

# GitHub raw content URL for Fluent UI System Icons
GITHUB_BASE_URL = "https://raw.githubusercontent.com/microsoft/fluentui-system-icons/main"
ICON_ASSETS_URL = f"{GITHUB_BASE_URL}/assets"

# Available icon sizes from Fluent UI
ICON_SIZES = [16, 20, 24, 32, 48]
ICON_STYLES = ["regular", "filled"]


class FluentIconGenerator:
    """Generates icons with circular backgrounds using Fluent UI System Icons."""

    def __init__(
        self,
        output_size: int = 256,
        circle_color: str = "#0078d4",
        background_color: str = "transparent",
        icon_size: int = 24,
        icon_style: str = "regular",
        use_cache: bool = True,
    ):
        """
        Initialize the icon generator.

        Args:
            output_size: Output image size in pixels (width and height)
            circle_color: Hex color for the circular background
            background_color: Hex color for canvas background ('transparent' for RGBA)
            icon_size: Icon size from Fluent UI (16, 20, 24, 32, or 48)
            icon_style: Icon style ('regular' or 'filled')
            use_cache: Whether to cache downloaded icons locally
        """
        self.output_size = output_size
        self.circle_color = circle_color
        self.background_color = background_color
        self.icon_size = icon_size if icon_size in ICON_SIZES else 24
        self.icon_style = icon_style if icon_style in ICON_STYLES else "regular"
        self.use_cache = use_cache

        # Setup cache directory
        self.cache_dir = Path.home() / ".icon_generator_cache" / "fluent-ui"
        if self.use_cache:
            self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _get_cache_path(self, icon_name: str) -> Path:
        """Get the cache file path for an icon."""
        filename = f"{icon_name}_{self.icon_size}_{self.icon_style}.svg"
        return self.cache_dir / filename

    def _fetch_icon_svg(self, icon_name: str) -> Optional[str]:
        """
        Fetch an icon SVG from GitHub or cache.

        Args:
            icon_name: Icon name (e.g., 'Agents', 'Apps', 'Archive')

        Returns:
            SVG content as string, or None if not found
        """
        # Normalize icon name: URL encode spaces
        normalized_name = urllib.parse.quote(icon_name.strip())

        # Try cache first
        if self.use_cache:
            cache_path = self._get_cache_path(icon_name)
            if cache_path.exists():
                try:
                    return cache_path.read_text()
                except Exception:
                    pass

        # Construct filename: ic_fluent_{icon_name_lowercase}_{size}_{style}.svg
        icon_name_lower = icon_name.lower().replace(' ', '_')
        filename = f"ic_fluent_{icon_name_lower}_{self.icon_size}_{self.icon_style}.svg"

        # Fetch from GitHub (uppercase SVG folder)
        url = f"{ICON_ASSETS_URL}/{normalized_name}/SVG/{filename}"

        try:
            with urllib.request.urlopen(url, timeout=10) as response:
                svg_content = response.read().decode("utf-8")

            # Cache it
            if self.use_cache:
                cache_path = self._get_cache_path(icon_name)
                cache_path.write_text(svg_content)

            return svg_content
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise
        except Exception as e:
            print(f"Error fetching icon '{icon_name}': {e}", file=sys.stderr)
            return None

    def _svg_to_pil_image(self, svg_content: str, size: int) -> Optional[Image.Image]:
        """
        Convert SVG content to PIL Image.

        Args:
            svg_content: SVG file content as string
            size: Target size in pixels

        Returns:
            PIL Image object, or None if conversion fails
        """
        try:
            try:
                from svglib.svglib import svg2rlg
                from reportlab.graphics import renderPM
            except ImportError:
                print(
                    "Error: svglib and reportlab not installed. Install with:\n"
                    "    pip install svglib reportlab",
                    file=sys.stderr,
                )
                return None

            from io import StringIO

            # Convert SVG string to ReportLab drawing
            svg_file = StringIO(svg_content)
            drawing = svg2rlg(svg_file)

            if not drawing:
                return None

            # Render to PNG
            png_data = renderPM.drawToString(drawing, fmt="PNG", width=size, height=size)

            # Open as PIL Image
            return Image.open(BytesIO(png_data)).convert("RGBA")

        except Exception as e:
            print(f"Error converting SVG to image: {e}", file=sys.stderr)
            return None

    def _hex_to_rgb(self, hex_color: str) -> Tuple[int, int, int]:
        """Convert hex color to RGB tuple."""
        hex_color = hex_color.lstrip("#")
        return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))

    def generate_icon(self, icon_name: str) -> Optional[Image.Image]:
        """
        Generate an icon with circular background.

        Args:
            icon_name: Icon name (must be available in Fluent UI)

        Returns:
            PIL Image object with RGBA, or None if failed
        """
        # Fetch SVG
        svg_content = self._fetch_icon_svg(icon_name)
        if not svg_content:
            print(f"Icon '{icon_name}' not found in Fluent UI System Icons", file=sys.stderr)
            return None

        # Convert SVG to PIL Image
        icon_image = self._svg_to_pil_image(svg_content, self.icon_size)
        if not icon_image:
            return None

        # Create output image with transparent background
        output_img = Image.new("RGBA", (self.output_size, self.output_size), (0, 0, 0, 0))

        # Draw circular background
        draw = ImageDraw.Draw(output_img)
        circle_color_rgb = self._hex_to_rgb(self.circle_color)
        circle_color_rgba = (*circle_color_rgb, 255)

        # Calculate circle position (fill most of the canvas with some padding)
        padding = int(self.output_size * 0.1)
        circle_bbox = [padding, padding, self.output_size - padding, self.output_size - padding]
        draw.ellipse(circle_bbox, fill=circle_color_rgba)

        # Scale icon to fit nicely in the circle (80% of circle diameter)
        circle_diameter = self.output_size - 2 * padding
        icon_display_size = int(circle_diameter * 0.8)
        icon_scaled = icon_image.resize((icon_display_size, icon_display_size), Image.Resampling.LANCZOS)

        # Center the icon
        icon_x = (self.output_size - icon_display_size) // 2
        icon_y = (self.output_size - icon_display_size) // 2

        # Composite icon onto the circular background
        output_img.paste(icon_scaled, (icon_x, icon_y), icon_scaled)

        return output_img

    def save_icon(self, icon_name: str, output_path: Path) -> bool:
        """
        Generate and save an icon.

        Args:
            icon_name: Icon name
            output_path: Path to save the PNG file

        Returns:
            True if successful, False otherwise
        """
        img = self.generate_icon(icon_name)
        if not img:
            return False

        output_path.parent.mkdir(parents=True, exist_ok=True)
        img.save(output_path, "PNG")
        print(f"[OK] Generated {icon_name}: {output_path}")
        return True

    @staticmethod
    def list_available_icons() -> bool:
        """
        List available icons from Fluent UI System Icons repository.

        Returns:
            True if successful, False otherwise
        """
        try:
            # Fetch the list of available icons from GitHub API
            api_url = "https://api.github.com/repos/microsoft/fluentui-system-icons/contents/assets"

            with urllib.request.urlopen(api_url, timeout=10) as response:
                icons_data = json.loads(response.read().decode("utf-8"))

            # Filter for directories only
            icon_names = sorted([icon["name"] for icon in icons_data if icon["type"] == "dir"])

            print(f"Available Fluent UI System Icons ({len(icon_names)} total):")
            print()

            # Print in columns
            cols = 3
            for i in range(0, len(icon_names), cols):
                row = icon_names[i : i + cols]
                print("  " + "  |  ".join(f"{name:<30}" for name in row))

            print()
            print(f"Icon Sizes: {', '.join(str(s) for s in ICON_SIZES)} px")
            print(f"Icon Styles: {', '.join(ICON_STYLES)}")
            print()
            print("Examples: --icon 'Agents' 'Archive' 'Apps'")

            return True

        except Exception as e:
            print(f"Error fetching icon list: {e}", file=sys.stderr)
            print("You can still generate icons, but icon list is unavailable.", file=sys.stderr)
            return False


def main():
    """Main entry point for CLI."""
    parser = argparse.ArgumentParser(
        description="Generate icons with circular backgrounds using Fluent UI System Icons",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python icon_generator.py --list
  python icon_generator.py --icon home settings search --size 256
  python icon_generator.py --icon star --size 512 --circle-color "#1f883d"
  python icon_generator.py --icon heart --size 128 --icon-size 32 --icon-style filled
  python icon_generator.py --icon settings --size 256 --circle-color "#0078d4" --icon-style filled
        """,
    )

    parser.add_argument(
        "--icon",
        nargs="+",
        help="Icon(s) to generate (space-separated). If omitted, generates a sample of common icons.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("./icons"),
        help="Output directory for generated icons (default: ./icons)",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=256,
        help="Output image size in pixels (default: 256)",
    )
    parser.add_argument(
        "--circle-color",
        type=str,
        default="#0078d4",
        help="Hex color for circle background (default: #0078d4 - Microsoft Blue)",
    )
    parser.add_argument(
        "--icon-size",
        type=int,
        default=24,
        choices=ICON_SIZES,
        help=f"Fluent UI icon size in pixels (default: 24). Options: {', '.join(str(s) for s in ICON_SIZES)}",
    )
    parser.add_argument(
        "--icon-style",
        type=str,
        default="regular",
        choices=ICON_STYLES,
        help=f"Icon style (default: regular). Options: {', '.join(ICON_STYLES)}",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Disable icon caching (always fetch from GitHub)",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all available icons and exit",
    )

    args = parser.parse_args()

    # Handle --list
    if args.list:
        FluentIconGenerator.list_available_icons()
        return 0

    # Initialize generator
    generator = FluentIconGenerator(
        output_size=args.size,
        circle_color=args.circle_color,
        icon_size=args.icon_size,
        icon_style=args.icon_style,
        use_cache=not args.no_cache,
    )

    # Determine which icons to generate
    if args.icon:
        icons_to_generate = args.icon
    else:
        # Generate a sample of common icons from Fluent UI
        icons_to_generate = [
            "Agents",
            "Alert",
            "Apps",
            "Archive",
            "Backspace",
            "Badge",
        ]

    print(f"Generating {len(icons_to_generate)} icon(s) to {args.output.absolute()}")
    print(f"Output size: {args.size}px | Circle color: {args.circle_color}")
    print(f"Icon size: {args.icon_size}px | Icon style: {args.icon_style}")
    print()

    successful = 0
    failed = 0

    for icon_name in icons_to_generate:
        output_file = args.output / f"{icon_name}.png"
        if generator.save_icon(icon_name, output_file):
            successful += 1
        else:
            failed += 1

    print()
    print(f"Generated {successful} icon(s) successfully!", end="")
    if failed > 0:
        print(f" ({failed} failed)")
    else:
        print()

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
