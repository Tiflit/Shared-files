from collections import Counter

with open("combined.txt", "r", encoding="utf-8", errors="ignore") as f:
    lines = f.read().splitlines()

counter = Counter()
in_section = False
last_nonempty = None

for line in lines:
    if line.startswith("MTRL"):
        in_section = True
        last_nonempty = None
        continue

    stripped = line.strip()

    if stripped and set(stripped) == {"="} and len(stripped) >= 10:
        if in_section and last_nonempty:
            counter[last_nonempty] += 1

        in_section = False
        last_nonempty = None
        continue

    if in_section and stripped:
        last_nonempty = stripped

if in_section and last_nonempty:
    counter[last_nonempty] += 1

ranked = [
    (name, count)
    for name, count in counter.items()
    if count >= 3
]

ranked.sort(key=lambda x: (-x[1], x[0]))

with open("item_frequency.txt", "w", encoding="utf-8") as f:
    for name, count in ranked:
        f.write(f"{count}\t{name}\n")

print(f"Found {len(ranked)} items appearing 3+ times.")
print("Results saved to item_frequency.txt")