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
    return subprocess.run(["git", "-c", "http.version=HTTP/1.1",
                           "-c", "http.lowSpeedLimit=1024", "-c", "http.lowSpeedTime=60",
                           *args], cwd=cwd, check=True, text=True,
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
            # Reuse the local object store: the catalog has tens of thousands
            # of images, and downloading it again is unnecessary on each update.
            git("fetch", "origin", "refs/heads/gh-pages:refs/remotes/origin/gh-pages")
            revision = git("rev-parse", "refs/remotes/origin/gh-pages", capture=True).stdout.strip()
            git("clone", "--shared", "--no-checkout", str(ROOT), str(checkout))
            git("remote", "set-url", "origin", remote, cwd=checkout)
            # Seed the branch and index without checking out its 300k+ files.
            # The generated catalog below is the entire intended working tree;
            # git add --all will also remove any obsolete indexed site files.
            git("branch", "gh-pages", revision, cwd=checkout)
            git("symbolic-ref", "HEAD", "refs/heads/gh-pages", cwd=checkout)
            git("read-tree", "HEAD", cwd=checkout)
        else:
            git("init", "--initial-branch=gh-pages", str(checkout))
            git("remote", "add", "origin", remote, cwd=checkout)
        print("Copying generated catalog into publication checkout", flush=True)
        shutil.copytree(catalog, checkout, dirs_exist_ok=True)
        for name in ("index.html", "catalog.css", "catalog.js"):
            shutil.copyfile(ROOT / "mushi/web" / name, checkout / name)
        (checkout / ".nojekyll").touch()
        print("Validating all published pixels, provenance and sequence links", flush=True)
        validate(checkout)
        for script in sorted(checkout.rglob('*.js')):
            subprocess.run(["node", "--check", str(script)], check=True)
        print("Preparing validated catalog commit", flush=True)
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
        # Keep generated objects locally before the temporary checkout is
        # removed. The next publication should not download its own last build.
        git("fetch", "--no-tags", str(checkout),
            "+HEAD:refs/remotes/origin/gh-pages")
        print("Catalog pushed. GitHub Pages will publish https://coldnightwarmth.github.io/mushi/")


if __name__ == "__main__":
    main()
