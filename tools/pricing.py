"""小酒馆定价 API；仅依赖 Python 3.10+ 标准库，无导入副作用。

    catalog = load_catalog()  # 默认工程 data/prices.json，也可传路径
    result = calculate_price(catalog["recipes"]["S-01"], catalog)
    result = calculate_price(new_recipe, catalog, tiers={"金酒": 2})

金额用 Decimal 计算，返回可直接 JSON 序列化的 dict。价格参数全部来自 JSON。
本模块只计算挂牌价，不修改目录、不扣库存、不计算店长与小费收入。
"""
from __future__ import annotations

import argparse
from decimal import Decimal, InvalidOperation, ROUND_CEILING, localcontext
import json
from pathlib import Path
from typing import Any, Mapping

DEFAULT_CATALOG = Path(__file__).resolve().parents[1] / "data" / "prices.json"


class PricingError(ValueError):
    """无效的配置、配方或等级。调用方可捕获此异常反馈给策划。"""


def _number(value: Any, label: str, *, minimum: str = "0", positive: bool = False) -> Decimal:
    if isinstance(value, bool):
        raise PricingError(f"{label} 必须是有限数值")
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError):
        raise PricingError(f"{label} 必须是有限数值") from None
    if not number.is_finite() or number < Decimal(minimum) or (positive and number <= 0):
        raise PricingError(f"{label} 超出合法范围")
    return number


def _count(value: Any, label: str) -> int:
    number = _number(value, label)
    if number != number.to_integral_value():
        raise PricingError(f"{label} 必须为非负整数")
    return int(number)


def load_catalog(path: str | Path = DEFAULT_CATALOG) -> dict:
    """读取并校验物价配置；调用方可缓存返回值，更新 JSON 后主动重载。"""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        raise PricingError(f"无法读取物价 JSON：{exc}") from exc
    validate_catalog(data)
    return data


def validate_catalog(catalog: Mapping[str, Any]) -> None:
    """校验计算所必需的配置；不要求菜单缓存已刷新。"""
    try:
        if catalog["schema_version"] != "1.0":
            raise PricingError("不支持的 schema_version")
        rule = catalog["pricing_rules"]
        for key in ("round_to", "max_cost_ratio"):
            _number(rule[key], key, positive=True)
        if _number(rule["max_cost_ratio"], "max_cost_ratio") > 1:
            raise PricingError("max_cost_ratio 不得超过1")
        for key in ("consumables_per_drink", "cost_value_multiplier"):
            _number(rule[key], key)
        if not rule["difficulty_base"] or not rule["methods"]:
            raise PricingError("必须提供难度与技法配置")
        for value in rule["difficulty_base"].values():
            _number(value, "difficulty_base")
        for value in rule["methods"].values():
            _number(value["extra_value"], "method.extra_value")
        for key in ("included_liquid_portions", "included_garnishes"):
            _count(rule["work"][key], key)
        for key in ("per_extra_liquid", "per_extra_garnish", "per_pre_solid"):
            _number(rule["work"][key], key)
        if not catalog["ingredients"]:
            raise PricingError("原料表不能为空")
        for name, item in catalog["ingredients"].items():
            if item["unit"] != "ml":
                raise PricingError(f"{name} 的采购单位必须是ml")
            _number(item["pack_ml"], f"{name}.pack_ml", positive=True)
            _number(item["pack_price"], f"{name}.pack_price")
            if item.get("family"):
                levels = catalog["base_families"][item["family"]]["tiers"]
                if len(levels) != 3:
                    raise PricingError("基酒模板必须有三级")
                values = [_number(x["pack_price"], "tier.pack_price") for x in levels]
                if values != sorted(values):
                    raise PricingError("三级基酒模板进货价必须递增或相等")
    except (KeyError, TypeError, AttributeError) as exc:
        raise PricingError(f"物价 JSON 缺少字段或结构错误：{exc}") from exc


def _output(number: Decimal) -> float:
    # 中间过程不取整；输出仅截为六位小数，供展示和传输。
    return float(round(number, 6))


def calculate_price(recipe: Mapping[str, Any], catalog: Mapping[str, Any], *,
                    tiers: Mapping[str, int] | None = None) -> dict:
    """计算标准或升级挂牌价。

    recipe: difficulty(S/M/H), method, ingredients[{name,amount}], topup[],
            garnish[str], pre_solids[{name,amount,unit}]；id/name可选。
    tiers: 基酒家族 -> 1/2/3，未提供家族默认1；同一家族所有风格同步升级。
    返回 cost、standard_cost、price、standard_price、breakdown 等。
    未知原料、技法、难度、非正用量等一律报错，不静默使用兜底价。
    """
    validate_catalog(catalog)
    if not isinstance(recipe, Mapping):
        raise PricingError("recipe 必须是对象")
    try:
        with localcontext() as ctx:
            ctx.prec = 40
            return _calculate(recipe, catalog, {} if tiers is None else tiers)
    except (KeyError, TypeError, AttributeError) as exc:
        raise PricingError(f"配方缺少字段或结构错误：{exc}") from exc
    except (InvalidOperation, OverflowError) as exc:
        raise PricingError("数值过大或精度不合法") from exc


def _calculate(recipe, catalog, tiers):
    rule = catalog["pricing_rules"]
    difficulty, method = recipe["difficulty"], recipe["method"]
    if difficulty not in rule["difficulty_base"]:
        raise PricingError(f"未知难度：{difficulty}")
    if method not in rule["methods"]:
        raise PricingError(f"未知技法：{method}")
    if not isinstance(tiers, Mapping):
        raise PricingError("tiers 必须是家族到等级的对象")
    for family, tier in tiers.items():
        if family not in catalog["base_families"] or isinstance(tier, bool) or tier not in (1, 2, 3):
            raise PricingError(f"无效家族或等级：{family}={tier}")
    ingredients, topup = recipe["ingredients"], recipe.get("topup", [])
    garnish, solids = recipe.get("garnish", []), recipe.get("pre_solids", [])
    if any(not isinstance(x, list) for x in (ingredients, topup, garnish, solids)):
        raise PricingError("ingredients、topup、garnish、pre_solids 必须是数组")
    if not ingredients and not topup:
        raise PricingError("至少需要一项液体原料")
    if any(not isinstance(x, str) or not x.strip() for x in garnish) or len(set(garnish)) != len(garnish):
        raise PricingError("装饰必须为非空且不重复的名称")
    for solid in solids:
        if not isinstance(solid, Mapping) or not isinstance(solid.get("name"), str) or not solid["name"].strip():
            raise PricingError("前置固体必须有名称")
        _number(solid.get("amount"), "固体用量", positive=True)
    cost0 = cost = _number(rule["consumables_per_drink"], "consumables")
    breakdown = []
    for stage, items in (("ingredients", ingredients), ("topup", topup)):
        for item in items:
            name = item["name"]
            if name not in catalog["ingredients"]:
                raise PricingError(f"原料未定价：{name}，请先添加至prices.json")
            if item.get("unit", "ml") != "ml":
                raise PricingError("液体用量只支持ml")
            amount = _number(item["amount"], f"{name}用量", positive=True)
            entry = catalog["ingredients"][name]
            pack_ml = _number(entry["pack_ml"], "pack_ml", positive=True)
            pack0 = _number(entry["pack_price"], "pack_price")
            tier, pack = 1, pack0
            if entry.get("family"):
                family = entry["family"]
                tier = int(tiers.get(family, 1))
                template = catalog["base_families"][family]["tiers"]
                pack += _number(template[tier - 1]["pack_price"], "tier.price") - _number(template[0]["pack_price"], "tier.price")
            line0, line = amount * pack0 / pack_ml, amount * pack / pack_ml
            cost0 += line0
            cost += line
            breakdown.append(dict(name=name, stage=stage, amount=_output(amount), unit="ml", tier=tier,
                                  pack_ml=_output(pack_ml), pack_price=_output(pack),
                                  standard_cost=_output(line0), cost=_output(line)))
    work = rule["work"]
    work_parts = {
        "extra_liquids": Decimal(max(0, len(ingredients)+len(topup)-work["included_liquid_portions"])) * _number(work["per_extra_liquid"], "work"),
        "extra_garnishes": Decimal(max(0, len(garnish)-work["included_garnishes"])) * _number(work["per_extra_garnish"], "work"),
        "pre_solids": Decimal(len(solids)) * _number(work["per_pre_solid"], "work"),
        "method": _number(rule["methods"][method]["extra_value"], "method.extra_value"),
    }
    extra = sum(work_parts.values(), Decimal(0))
    base = _number(rule["difficulty_base"][difficulty], "difficulty_base")
    multiplier = _number(rule["cost_value_multiplier"], "cost_value_multiplier")
    ratio = _number(rule["max_cost_ratio"], "max_cost_ratio", positive=True)
    step = _number(rule["round_to"], "round_to", positive=True)

    def round_up(value):
        return (value / step).to_integral_value(rounding=ROUND_CEILING) * step

    floor0, value0 = cost0 / ratio, base + multiplier * cost0 + extra
    standard_price = round_up(max(floor0, value0))
    floor, value = cost / ratio, standard_price + multiplier * (cost-cost0)
    price = round_up(max(floor, value))
    return dict(recipe_id=recipe.get("id"), name=recipe.get("name", "未命名酒品"), currency=catalog["currency"],
                difficulty=difficulty, method=method, standard_cost=_output(cost0), cost=_output(cost),
                consumables=_output(_number(rule["consumables_per_drink"], "consumables")),
                work_value=_output(extra), work_breakdown={k: _output(v) for k, v in work_parts.items()},
                cost_floor=_output(floor), value_price=_output(value0), upgrade_value_price=_output(value),
                standard_price=_output(standard_price), price=_output(price),
                cost_ratio=_output(cost/price) if price else 0,
                contribution=_output(price-cost), breakdown=breakdown)


def calculate_menu(catalog: Mapping[str, Any], *, tiers: Mapping[str, int] | None = None) -> dict:
    """批量重算菜单；始终按原料和规则重算，不依赖保存的prices缓存。"""
    return {key: calculate_price(recipe, catalog, tiers=tiers) for key, recipe in catalog["recipes"].items()}


def main(argv=None) -> int:
    """仅供联调的 JSON 输入输出 CLI；API 是推荐集成方式。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--recipe", help="已有酒品ID，例如S-01")
    source.add_argument("--input", type=Path, help="新增酒品JSON对象路径")
    parser.add_argument("--tiers", default="{}", help='家族等级JSON，例如 {"金酒":2}')
    args = parser.parse_args(argv)
    try:
        catalog = load_catalog(args.catalog)
        tiers = json.loads(args.tiers)
        if args.recipe:
            if args.recipe not in catalog["recipes"]:
                raise PricingError(f"未知酒品ID：{args.recipe}")
            result = calculate_price(catalog["recipes"][args.recipe], catalog, tiers=tiers)
        elif args.input:
            recipe = json.loads(args.input.read_text(encoding="utf-8-sig"))
            result = calculate_price(recipe, catalog, tiers=tiers)
        else:
            result = calculate_menu(catalog, tiers=tiers)
        print(json.dumps(result, ensure_ascii=False, allow_nan=False, indent=2))
        return 0
    except (PricingError, OSError, ValueError) as exc:
        import sys
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
