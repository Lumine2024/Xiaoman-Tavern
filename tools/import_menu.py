"""Import the planning DOCX catalogue without third-party dependencies."""
import argparse
import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree
from pricing import load_catalog, calculate_price


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--settings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.settings.read_text(encoding="utf-8"))
    catalog = load_catalog(args.catalog)
    with zipfile.ZipFile(args.source) as doc:
        root = ElementTree.fromstring(doc.read("word/document.xml"))
    namespace = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    paragraphs = ["".join(p.itertext()) for p in root.findall(".//w:p", namespace)]

    def parse_portions(text):
        result = []
        for portion in text.strip().split("・"):
            match = re.fullmatch(r"(.+?)\s+(\d+)\s*(叶)?", portion.strip())
            if not match:
                raise ValueError(f"Unrecognized ingredient: {portion!r}")
            result.append(dict(name=match[1], amount=int(match[2]), unit="叶" if match[3] else "ml"))
        return result

    recipes = []
    for line in paragraphs:
        if not re.match(r"[SMH]-\d+", line):
            continue
        ident, name, body = re.split(r"\s+", line, maxsplit=2)
        quantities, method, vessel, garnish = body.split("｜")
        portions = quantities.split("＋后注")
        ingredients = parse_portions(portions[0])
        solids = [item for item in ingredients if item["unit"] == "叶"]
        ingredients = [item for item in ingredients if item["unit"] == "ml"]
        ingredients.sort(key=lambda item: item["name"] not in config["base_names"])
        cup, ice = vessel.split("·")
        if not cup.endswith("杯"):
            cup += "杯"
        recipes.append(dict(id=ident, name=name, difficulty=config["difficulty_names"][ident[0]],
                            ingredients=ingredients, pre_solids=solids,
                            topup=parse_portions(portions[1]) if len(portions) > 1 else [],
                            method=method, cup=cup, ice=ice,
                            garnish=[] if garnish == "无" else garnish.split("＋"),
                            price=0))
        recipes[-1]['price'] = calculate_price(dict(recipes[-1], difficulty=ident[0]), catalog)['price']
    if not recipes:
        raise ValueError("No recipes found")
    args.output.write_text(json.dumps(recipes, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported {len(recipes)} recipes")


if __name__ == "__main__":
    main()
