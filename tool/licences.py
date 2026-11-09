#!/usr/bin/env python3
"""Turns `cargo about generate --format json` (stdin) into the compact file
the Licences page reads (stdout): the distinct licence texts once, and per
crate its name, version, declared licence expression and text indexes.
The output is deterministic so CI can diff it."""
import json
import sys

data = json.load(sys.stdin)
crates = {}
for lic in data["licenses"]:
    for use in lic["used_by"]:
        c = use["crate"]
        entry = crates.setdefault(
            (c["name"], c["version"]),
            {"name": c["name"], "version": c["version"],
             "license": c.get("license") or "", "texts": set()},
        )
        entry["texts"].add(lic["text"])
texts = sorted({t for e in crates.values() for t in e["texts"]})
index = {t: i for i, t in enumerate(texts)}
out = {
    "texts": texts,
    "crates": [
        {**e, "texts": sorted(index[t] for t in e["texts"])}
        for _, e in sorted(crates.items())
    ],
}
json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
sys.stdout.write("\n")
