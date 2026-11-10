#!/usr/bin/env python3
"""Rewrites the status table of README.md / README.it.md from docs/features.json (the same shape as a ztOS device page:
Category, Feature, Status, Notes; working = 100% of the feature). Run from the repository root."""
import json, re

D = json.load(open("docs/features.json"))
F = D["features"]
# GitHub strips colours from tables, so the colour is a coloured circle in front of the word
ST = {"en": {"working": "\U0001F7E2 Working", "partial": "\U0001F7E1 Partial", "broken": "\U0001F534 Broken", "untested": "\u26AA Untested"},
      "it": {"working": "\U0001F7E2 Funziona", "partial": "\U0001F7E1 Parziale", "broken": "\U0001F534 Non funziona", "untested": "\u26AA Non provato"}}
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
    # drop the count/legend lines an earlier run left above the table (they used to pile up: one more block per run)
    head = s[i:j + 1]
    head = re.sub(r"(?m)^\*\*\d+ (working|funzionano) .*\n\n?", "", head)
    head = re.sub(r"(?m)^\*(Working|Funziona)\* (means|vuol dire) .*\n\n?", "", head)
    s = s[:i] + head + s[j + 1:]
    j = i + len(head) - 1
    k = s.index("\n\n", s.index("\n|", j) if False else j)
    # the table ends at the first blank line after it starts
    end = s.index("\n\n", j + 1)
    s = s[:j + 1] + block(lang) + s[end:]
    open(fn, "w").write(s)
print(count)
