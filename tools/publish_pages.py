#!/usr/bin/env python3
"""Validate and publish the generated asset catalog to the gh-pages branch."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from mushi.validation import validate


def git(*args, cwd=ROOT, capture=False):
    return subprocess.run(["git", *args], cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=ROOT / "build/catalog")
    args = parser.parse_args()
    catalog = args.catalog.resolve()
    remote = git("remote", "get-url", "origin", capture=True).stdout.strip()
    exists = bool(git("ls-remote", "--heads", "origin", "refs/heads/gh-pages",
                      capture=True).stdout.strip())
    with tempfile.TemporaryDirectory(prefix="mushi-pages-") as temporary:
        checkout = Path(temporary) / "site"
        if exists:
            git("clone", "--depth", "1", "--single-branch", "--branch", "gh-pages",
                remote, str(checkout))
            # This disposable checkout holds generated site files only.
            for child in checkout.iterdir():
                if child.name == ".git":
                    continue
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child)
                else:
                    child.unlink()
        else:
            git("init", "--initial-branch=gh-pages", str(checkout))
            git("remote", "add", "origin", remote, cwd=checkout)
        shutil.copytree(catalog, checkout, dirs_exist_ok=True)
        for name in ("index.html", "catalog.css", "catalog.js"):
            shutil.copyfile(ROOT / "mushi/web" / name, checkout / name)
        (checkout / ".nojekyll").touch()
        validate(checkout)
        subprocess.run(["node", "--check", str(checkout / "catalog.js")], check=True)
        subprocess.run(["node", "--check", str(checkout / "catalog-data.js")], check=True)
        git("add", "--all", cwd=checkout)
        changes = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=checkout)
        if changes.returncode == 0:
            print("The published catalog already matches this build.")
            return
        if changes.returncode != 1:
            raise SystemExit("Could not inspect the prepared catalog commit")
        git("commit", "--quiet", "-m", "Publish validated Futari asset catalog", cwd=checkout)
        git("-c", "http.version=HTTP/1.1", "-c", "http.postBuffer=524288000",
            "push", "origin", "HEAD:refs/heads/gh-pages", cwd=checkout)
        print("Catalog pushed. GitHub Pages will publish https://coldnightwarmth.github.io/mushi/")


if __name__ == "__main__":
    main()
