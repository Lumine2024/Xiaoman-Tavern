"""Create independent Decimal reference cases for all used-family level combinations."""
import argparse
import itertools
import json
from pathlib import Path
from pricing import load_catalog, calculate_price


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    catalog = load_catalog(args.catalog)
    rows = []
    for recipe in catalog['recipes'].values():
        families = sorted({catalog['ingredients'][item['name']]['family'] for item in recipe['ingredients'] + recipe['topup']} - {None})
        levels = [range(1, len(catalog['base_families'][family]['tiers']) + 1) for family in families]
        for values in itertools.product(*levels):
            tiers = dict(zip(families, values))
            calculated = calculate_price(recipe, catalog, tiers=tiers)
            rows.append({'id': recipe['id'], 'tiers': {key: value-1 for key, value in tiers.items()}, 'price': calculated['price'], 'cost': calculated['cost']})
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Wrote {len(rows)} independent reference cases')


if __name__ == '__main__':
    main()
