"""Conservative offline checks for omitted concrete nouns in machine translation."""
import re
STOP = {"a","an","the","of","to","be","one","someone","something","person","thing","etc","or","and","for","with","as","in","on","at"}

def english_stems(text):
    return {word[:5] for word in re.findall(r"[a-z]+", text.lower()) if len(word)>2 and word not in STOP}

def translation_issues(lines):
    issues=[]
    for index,line in enumerate(lines):
        nouns=[]
        for token in line["tokens"]:
            if token.get("pos")!="noun":continue
            glosses=" ".join(token.get("definitions") or [])
            stems=english_stems(glosses)
            if stems:nouns.append((token["surface"],stems))
        # A single omitted subject may be implicit in Japanese/English. With two
        # concrete nouns, omission is often an object/destination mistranslation.
        if len(nouns)<2:continue
        actual=english_stems(line["translation"])
        missing=[surface for surface,stems in nouns if not stems&actual]
        if missing:issues.append({"lineIndex":index,"reason":"Check omitted source nouns", "sourceNouns":missing})
    return issues
