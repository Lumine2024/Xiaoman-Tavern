"""Build Decimal pricing cases for an explicitly supplied revised recipe set."""
import argparse
import copy
import itertools
import json
from pathlib import Path
from pricing import load_catalog, calculate_price


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("catalog", "recipes", "rulings", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    args = parser.parse_args()
    catalog = load_catalog(args.catalog)
    recipes = json.loads(args.recipes.read_text(encoding="utf-8"))
    rulings = json.loads(args.rulings.read_text(encoding="utf-8"))
    rows = []
    for unified in (False, True):
        for source in recipes:
            recipe = copy.deepcopy(source)
            recipe["difficulty"] = recipe["id"].split("-")[0]
            if unified:
                for portion in recipe["ingredients"]:
                    if portion["name"] in rulings["rum"]["names"]:
                        portion["name"] = rulings["rum"]["canonical"]
            families = sorted({catalog["ingredients"][x["name"]]["family"] for x in recipe["ingredients"] + recipe["topup"]} - {None})
            for values in itertools.product(*(range(1, len(catalog["base_families"][family]["tiers"]) + 1) for family in families)):
                tiers = dict(zip(families, values))
                result = calculate_price(recipe, catalog, tiers=tiers)
                rows.append({"id": recipe["id"], "unified": unified, "tiers": {key: value - 1 for key, value in tiers.items()}, "price": result["price"], "cost": result["cost"]})
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(rows)} revised independent Decimal cases")


if __name__ == "__main__":
    main()
