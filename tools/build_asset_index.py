"""Refresh the current PNG index from external labels and original canvas metadata."""
import argparse
import json
import struct
from pathlib import Path


def build(project, registry_path, labels_path, output):
    registry = json.loads(registry_path.read_text(encoding='utf-8'))
    labels = json.loads(labels_path.read_text(encoding='utf-8'))
    entries = dict(labels['files'])
    for group, description in labels['groups'].items():
        for name, path in registry[group].items():
            entries[path.removeprefix('res://')] = dict(description, name=name)
    rows = []
    for index, target in enumerate(sorted(entries), 1):
        info = entries[target]
        size = '×'.join(str(value) for value in info['logical_size'])
        with (project / target).open('rb') as stream:
            header = stream.read(24)
        if header[:8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError(f'Invalid PNG: {target}')
        width, height = struct.unpack('>II', header[16:24])
        rows.append(f"| {index:02} | {info['category']} | {info['name']} | `{target}` | {size} | {width}×{height} | {info['usage']} | {info['note']} |")
    header, marker, _ = output.read_text(encoding='utf-8').partition('<!-- asset-table -->')
    if not marker:
        raise ValueError('Missing asset-table marker in output document')
    output.write_text(header + marker + '\n\n'
                      '| 编号 | 类别 | 资源名称 | 替换 PNG 路径 | 逻辑尺寸 | 当前 PNG 像素 | 使用位置 | 美术约束 |\n'
                      '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
                      + '\n'.join(rows) + '\n', encoding='utf-8')
    print(f'Indexed {len(rows)} PNG assets: {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'registry', 'labels', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    build(args.project.resolve(), args.registry,
          args.labels, args.output)
