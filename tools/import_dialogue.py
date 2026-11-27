"""Import authored dialogue verbatim, preserving original customer indices for old saves."""
import argparse
import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'customers', 'rules', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--story', type=Path, required=True, help='Unified authored text catalog (updated together with rules)')
    args = parser.parse_args()
    rules = json.loads(args.rules.read_text(encoding='utf-8'))
    old = json.loads(args.customers.read_text(encoding='utf-8'))
    story = json.loads(args.story.read_text(encoding='utf-8'))
    prose_fields = ('request_text', 'topic', 'answers', 'reply', 'rumor', 'opening', 'closing', 'header', 'order_note')
    for item in old:
        item.update(story['customers'][item['story_id']])
    with zipfile.ZipFile(args.source) as archive:
        root = ET.fromstring(archive.read('word/document.xml'))
    lines = [''.join(p.itertext()) for p in root.findall('.//{http://schemas.openxmlformats.org/wordprocessingml/2006/main}p')]
    groups, current, enabled = [], None, False
    for line in lines:
        if line.startswith('9　'):
            enabled = True
        elif line.startswith('10　'):
            enabled = False
        if not enabled:
            continue
        if ' · ' in line and not line.startswith(('9　', '·')):
            current = {'header': line, 'choices': []}
            groups.append(current)
        elif current is not None:
            if line.startswith('段一　'): current['opening'] = line.split('　', 1)[1].strip('「」')
            elif line.startswith('点单：'): current['order_note'] = line.removeprefix('点单：')
            elif line.startswith('段二　'): current['topic'] = line.split('　', 1)[1].strip('「」')
            elif line.startswith('段三　'): current['rumor'] = line.split('　', 1)[1].strip('「」')
            elif line.startswith('收尾　'): current['closing'] = line.split('　', 1)[1].strip('「」')
            else:
                match = re.match(r'^([ABC])\s+(.+?)\s*→\s*(.+)$', line)
                if match:
                    effect = dict(rules['default_choice'])
                    text = match[3]
                    effect.update(answer='cold' if '跑题' in text else 'valid', style=text.split('｜')[0], text=match[2], source_effect=text)
                    if effect['answer'] == 'cold': effect.update(rules['cold_choice'])
                    for pattern, key in ((r'口碑\s*\+([\d.]+)', 'reputation'), (r'小费\s*×([\d.]+)', 'tip'), (r'成本\s*\+([\d.]+)', 'cost'), (r'耗时\s*\+([\d.]+)', 'seconds'), (r'次日客流\s*\+([\d.]+)', 'traffic')):
                        value = re.search(pattern, text)
                        if value: effect[key] = float(value[1])
                    value = re.search(r'收益\s*−([\d.]+)%', text)
                    if value: effect['revenue'] = 1 - float(value[1]) / 100
                    effect['leak'] = '配方外流' in text
                    value = re.search(r'延后\s*([\d.]+)\s*天', text)
                    if value: effect['opponent_delay'] = int(float(value[1]))
                    current['choices'].append(effect)
    imported = {}
    for group in groups:
        name, role = group['header'].split(' · ', 1)
        entry = rules['default_customer'].copy()
        previous = next((item for item in old if item['name'] == name), {})
        if name in rules['legacy_customer_ids']:
            entry.update({key: previous[key] for key in ('color', 'favorite', 'initial') if key in previous})
        entry.update(group)
        entry.update(name=name, role=role.split('（')[0], id=name, race=next((race for race in rules['races'] if race in role), None))
        if name == groups[0]['header'].split(' · ')[0]: entry['race'] = '人类'
        entry['specials'] = list(dict.fromkeys(re.findall(r'S-\d+', group['header'])))
        entry['answers'] = [item['text'] for item in entry['choices']]
        entry['good_answer'] = next(i for i, item in enumerate(entry['choices']) if item['answer'] == 'valid' and not item['leak'])
        entry['reply'] = ''
        entry['order_recipe_id'] = next(iter(re.findall(r'[SMH]-\d+', entry.get('order_note', ''))), '')
        entry['order_spec'] = rules['orders'].get(name, {})
        if len(entry['choices']) != 3: raise ValueError(group)
        imported[name] = entry
    # Existing unnamed-in-this-version characters stay available, without invented dialogue.
    result = [imported.pop(item['name'], item) for item in old]
    result.extend(imported.values())
    for item in result:
        key = item.get('story_id', item.get('id', item['name']))
        item['story_id'] = key
        prose = {field: item.pop(field) for field in prose_fields if field in item}
        for choice in item.get('choices', []):
            choice.pop('text', None)
        story['customers'][key] = prose
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    args.story.write_text(json.dumps(story, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Imported {len(groups)} authored customers; {len(result)} total')


if __name__ == '__main__':
    main()
