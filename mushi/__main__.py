import argparse
import json
from pathlib import Path
from .rom import load_roms


def main():
    parser = argparse.ArgumentParser(description="Futari 1.5 reconstruction tools")
    sub = parser.add_subparsers(dest="command", required=True)
    verify = sub.add_parser("verify", help="Verify the exact supported ROM revision")
    verify.add_argument("rom", type=Path)
    catalog = sub.add_parser("catalog", help="Build the complete resource-sheet inventory")
    catalog.add_argument("rom", type=Path)
    catalog.add_argument("--output", type=Path, default=Path("build/catalog"))
    observe = sub.add_parser("observe", help="Map captured draw rectangles to byte-exact ROM sheets")
    observe.add_argument("captures", type=Path, nargs="+")
    observe.add_argument("--catalog", type=Path, default=Path("build/catalog"))
    validate = sub.add_parser("validate", help="Check every image, metadata file, and exact source crop")
    validate.add_argument("--catalog", type=Path, default=Path("build/catalog"))
    args = parser.parse_args()
    if args.command == "verify":
        _, manifest = load_roms(args.rom)
        print(json.dumps(manifest, indent=2))
    elif args.command == "catalog":
        from .catalog import build
        build(args.rom, args.output)
    elif args.command == "observe":
        from .observations import export
        export(args.catalog, args.captures)
    elif args.command == "validate":
        from .validation import validate
        validate(args.catalog)


if __name__ == "__main__":
    main()
