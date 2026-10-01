#!/usr/bin/env python3
"""Generate docs/api/*.rst from the ``## name args -- summary`` doc-comments
that sit directly above each ``proc`` in lib/*.tcl. This keeps the API
reference honest: it can't drift from the real signatures and comments,
because it *is* them, re-flowed into reStructuredText.

Comment convention this parser understands (see any lib/*.tcl file):

    ## procname arg1 arg2 -- one-line summary
    proc ::aa::module::procname {arg1 arg2} { ... }

or, for a longer explanation, a '##' signature line followed by a run of
plain '#' comment lines (blank '#' lines become paragraph breaks) directly
above the proc, with no blank *code* line in between:

    ## procname arg
    #
    # Longer explanation, possibly several paragraphs.
    #
    proc ::aa::module::procname {arg} { ... }

Run with no arguments; writes into docs/api/ next to this script.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
LIBDIR = os.path.join(os.path.dirname(HERE), "lib")
OUTDIR = os.path.join(HERE, "api")

MODULES = [
    ("complex", "complex.tcl", "Complex-number arithmetic.", "::aa::complex"),
    ("dsp", "dsp.tcl", "Phasor extraction (software lock-in).", "::aa::dsp"),
    ("calib", "calib.tcl", "SOL calibration, Gamma conversions, dataset export.", "::aa::calib"),
    ("scpi", "scpi.tcl", "Transport-agnostic SCPI client.", "::aa::scpi"),
    ("driver", "driver.tcl", "Semantic instrument operations + mnemonic profile.", "::aa::driver"),
    ("sweep", "sweep.tcl", "Measurement / calibration / sweep orchestration.", "::aa::sweep"),
]

PROC_HEAD_RE = re.compile(r'^proc\s+(\S+)\s*(.*)$')


def match_proc_header(line):
    """Return (name, raw_arglist) if `line` starts a proc definition, else
    None. Hand-rolled instead of a single regex because Tcl arg lists can
    nest braces for default values (e.g. '{gamma {z0 {}}}'), which a
    '[^}]*' regex truncates at the *first* inner '}'.
    """
    m = PROC_HEAD_RE.match(line)
    if not m:
        return None
    name, rest = m.group(1), m.group(2).lstrip()
    if not rest.startswith("{"):
        return None
    depth = 0
    for i, ch in enumerate(rest):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return name, rest[1:i]
    return None


def split_tcl_list(s):
    """Top-level whitespace split, respecting brace nesting. Good enough for
    our own arg-list and simple-value strings (no quoted/escaped elements)."""
    tokens, cur, depth = [], "", 0
    for ch in s:
        if ch == "{":
            depth += 1
            cur += ch
        elif ch == "}":
            depth -= 1
            cur += ch
        elif ch.isspace() and depth == 0:
            if cur:
                tokens.append(cur)
                cur = ""
        else:
            cur += ch
    if cur:
        tokens.append(cur)
    return tokens


def format_sig_args(arglist):
    """'gamma {z0 {}}' -> 'gamma ?z0?' -- Tcl's own convention for marking an
    optional/defaulted argument, which reads far better in docs than the raw
    brace syntax."""
    out = []
    for tok in split_tcl_list(arglist):
        if tok.startswith("{") and tok.endswith("}"):
            inner = split_tcl_list(tok[1:-1])
            out.append(f"?{inner[0]}?" if inner else "?arg?")
        else:
            out.append(tok)
    return " ".join(out)


def parse_module(path):
    """Return a list of (name, display_args, summary, body_paragraphs) in file order."""
    with open(path) as f:
        lines = f.readlines()

    entries = []
    i, n = 0, len(lines)
    while i < n:
        hdr = match_proc_header(lines[i])
        if not hdr:
            i += 1
            continue
        fq_name, argstr = hdr
        # walk backward over the contiguous '#' comment block directly above
        j = i - 1
        block = []
        while j >= 0 and lines[j].lstrip().startswith("#"):
            block.append(lines[j].rstrip("\n"))
            j -= 1
        block.reverse()
        summary = None
        body_lines = []
        if block and block[0].lstrip().startswith("##"):
            sig_line = block[0].lstrip().lstrip("#").strip()
            if "--" in sig_line:
                _sig, summary = sig_line.split("--", 1)
                summary = summary.strip()
            else:
                summary = sig_line
            for b in block[1:]:
                # strip *all* leading '#' markers -- continuation lines in
                # this codebase are themselves '##...' or '# ...', and
                # stripping only one '#' left a stray '#' glued into the
                # middle of the rendered paragraph.
                body_lines.append(b.lstrip().lstrip("#").strip())
        if summary is not None:
            entries.append((fq_name, format_sig_args(argstr), summary, body_lines))
        i += 1
    return entries


def paragraphs(body_lines):
    paras, cur = [], []
    for l in body_lines:
        if l == "":
            if cur:
                paras.append(" ".join(cur))
                cur = []
        else:
            cur.append(l)
    if cur:
        paras.append(" ".join(cur))
    return paras


def rst_escape(s):
    # '*' starts RST emphasis and '|' starts a substitution reference; both
    # show up constantly in these comments ('*IDN?', '*OPC?', bitwise-looking
    # text) and need escaping to render as literal characters rather than
    # being parsed as markup (or, worse, an "undefined substitution" error).
    return s.replace("*", r"\*").replace("|", r"\|")


# Sphinx has no built-in Tcl domain. Rather than pull in a custom Sphinx
# extension for one directive, each proc is emitted as a 'py:function'
# signature (':noindex:' since these aren't really Python) -- it's just a
# convenient built-in directive that renders a monospaced, anchored
# signature block, with zero extra Sphinx dependencies beyond what this
# project already uses.
def write_module_rst(slug, filename, blurb, nsprefix, entries):
    out_path = os.path.join(OUTDIR, f"{slug}.rst")
    title = f"``{filename}``"
    with open(out_path, "w") as f:
        f.write(f"{title}\n{'=' * len(title)}\n\n")
        f.write(f"{blurb} Namespace: ``{nsprefix}``. Source: ``lib/{filename}``.\n\n")
        if not entries:
            f.write("*(no documented procs found)*\n")
            return
        for fq_name, argstr, summary, body_lines in entries:
            short = fq_name.split("::")[-1]
            sig = f"{short} {argstr}".strip() if argstr else short
            f.write(f".. py:function:: {sig}\n   :noindex:\n\n")
            f.write(f"   {rst_escape(summary)}\n\n")
            for p in paragraphs(body_lines):
                f.write(f"   {rst_escape(p)}\n\n")
    print("wrote", out_path)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    index_lines = [
        "API Reference",
        "==============",
        "",
        "Generated directly from the ``## name args -- summary`` doc-comments",
        "in ``lib/*.tcl`` by ``docs/gen_api.py`` -- it cannot drift from the",
        "real procs because it is their comments, re-flowed into this page.",
        "Re-run that script after editing any ``lib/`` module to refresh it.",
        "",
        ".. toctree::",
        "   :maxdepth: 1",
        "",
    ]
    total = 0
    for slug, filename, blurb, nsprefix in MODULES:
        path = os.path.join(LIBDIR, filename)
        entries = parse_module(path)
        total += len(entries)
        write_module_rst(slug, filename, blurb, nsprefix, entries)
        index_lines.append(f"   {slug}")
    index_lines.append("")
    with open(os.path.join(OUTDIR, "index.rst"), "w") as f:
        f.write("\n".join(index_lines))
    print("wrote", os.path.join(OUTDIR, "index.rst"))
    print(f"total documented procs: {total}")


if __name__ == "__main__":
    main()
