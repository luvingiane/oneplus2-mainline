#!/usr/bin/env python3
"""Rewrites the status table of README.md / README.it.md from docs/features.json (the same shape as a ztOS device page:
Category, Feature, Status, Notes; working = 100% of the feature). Run from the repository root."""
import json, re

D = json.load(open("docs/features.json"))
F = D["features"]
ST = {"en": {"working": "Working", "partial": "Partial", "broken": "Broken", "untested": "Untested"},
      "it": {"working": "Funziona", "partial": "Parziale", "broken": "Non funziona", "untested": "Non provato"}}
HEAD = {"en": ("Category", "Feature", "Status", "Notes"), "it": ("Categoria", "Funzione", "Stato", "Note")}
CNT = {"en": "**{working} working · {partial} partial · {broken} broken · {untested} untested**",
       "it": "**{working} funzionano · {partial} parziali · {broken} non funzionano · {untested} non provati**"}
LEG = {"en": "*Working* means 100% of the feature, tried on the phone; *Partial* says in the notes what is missing. Same wording as the ztOS device pages ([devices.ztos.online](https://devices.ztos.online)).",
       "it": "*Funziona* vuol dire il 100% della funzione, provata sul telefono; *Parziale* dice nelle note cosa manca. Stesse parole delle pagine dispositivo di ztOS ([devices.ztos.online](https://devices.ztos.online))."}
count = {k: sum(1 for f in F if f["status"] == k) for k in ST["en"]}

def block(lang):
    h = HEAD[lang]
    out = [CNT[lang].format(**count), "", LEG[lang], "", "| %s | %s | %s | %s |" % h, "|---|---|---|---|"]
    for f in F:
        out.append("| %s | %s | %s | %s |" % (f["category"], f["feature"], ST[lang][f["status"]], f[lang]))
    return "\n".join(out)

for fn, lang, start in (("README.md", "en", "## Status (short)"), ("README.it.md", "it", "## Stato (in breve)")):
    s = open(fn).read()
    i = s.index(start)
    # keep the milestone sentence under the heading, replace the table up to the "Full per-component" paragraph
    j = s.index("\n| ", i)
    k = s.index("\n\n", s.index("\n|", j) if False else j)
    # the table ends at the first blank line after it starts
    end = s.index("\n\n", j + 1)
    s = s[:j + 1] + block(lang) + s[end:]
    open(fn, "w").write(s)
print(count)
