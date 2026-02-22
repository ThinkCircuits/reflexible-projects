#!/usr/bin/env python3
"""
Render Jinja2 device-library templates into project-specific SystemVerilog.

Usage:
    python3 render_template.py <template.sv.j2> <output.sv> [key=value ...]

Example:
    python3 render_template.py \\
        ../../reflexible-platforms/device-lib/fpga/adc_reader/adc_reader.sv.j2 \\
        generated/adc_4ch.sv \\
        instance_name=adc_4ch channels=4 sclk_div=6 sclk_div_bits=3 \\
        sample_period=2400 sample_period_bits=12
"""

import sys
import os
import json

try:
    from jinja2 import Environment, FileSystemLoader
except ImportError:
    print("ERROR: jinja2 not installed. Run: pip install jinja2", file=sys.stderr)
    sys.exit(1)


def parse_value(s):
    """Parse a string value into int, float, bool, list, or string."""
    if s.lower() == "true":
        return True
    if s.lower() == "false":
        return False
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        pass
    # JSON list/dict
    if s.startswith("[") or s.startswith("{"):
        try:
            return json.loads(s)
        except json.JSONDecodeError:
            pass
    return s


def render_template(template_path, output_path, params):
    template_dir = os.path.dirname(os.path.abspath(template_path))
    template_name = os.path.basename(template_path)

    env = Environment(
        loader=FileSystemLoader(template_dir),
        keep_trailing_newline=True,
    )
    template = env.get_template(template_name)
    rendered = template.render(**params)

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w") as f:
        f.write(rendered)

    print(f"Rendered {template_path} -> {output_path}")


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    template_path = sys.argv[1]
    output_path = sys.argv[2]

    params = {}
    for arg in sys.argv[3:]:
        if "=" not in arg:
            print(f"WARNING: ignoring argument without '=': {arg}", file=sys.stderr)
            continue
        key, val = arg.split("=", 1)
        params[key] = parse_value(val)

    render_template(template_path, output_path, params)


if __name__ == "__main__":
    main()
