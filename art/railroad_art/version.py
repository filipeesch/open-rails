"""Library version, recorded into every generated manifest and build cache key.

Bump when a shared primitive, the material strategy, or the export contract
changes — the whole-tree content hash also catches edits, but the explicit
version makes manifest diffs and cache audits human-readable.
"""

RAILROAD_ART_VERSION = "1.0.0"
