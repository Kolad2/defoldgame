"""Extract GLB node trees into adjacent <model>.hierarchy.json files."""

import argparse
import json
import struct
from pathlib import Path


def extract_hierarchy(scene):
    """Return root nodes; leaves are names, parents are {name: children}."""
    nodes = scene.get("nodes", [])
    scenes = scene.get("scenes", [])
    if scenes:
        roots = scenes[scene.get("scene", 0)].get("nodes", [])
    else:
        children = {child for node in nodes for child in node.get("children", [])}
        roots = [index for index in range(len(nodes)) if index not in children]
        if nodes and not roots:
            raise ValueError("Node hierarchy has no roots")

    visiting = set()

    def visit(index):
        if not isinstance(index, int) or not 0 <= index < len(nodes):
            raise ValueError(f"Invalid node index: {index}")
        if index in visiting:
            raise ValueError(f"Cycle in node hierarchy at node {index}")
        visiting.add(index)
        node = nodes[index]
        name = node.get("name") or f"node_{index}"
        children = [visit(child) for child in node.get("children", [])]
        visiting.remove(index)
        return {name: children} if children else name

    return [visit(index) for index in roots]


def generate_glb_hierarchy(model_path):
    """Read a GLB, save only its hierarchy beside it, and return the JSON path."""
    model_path = Path(model_path)
    with model_path.open("rb") as source:
        header = source.read(20)
        if len(header) != 20:
            raise ValueError(f"{model_path}: truncated GLB header")
        magic, version, total, length, kind = struct.unpack("<4sIIII", header)
        if magic != b"glTF" or version != 2 or kind != 0x4E4F534A:
            raise ValueError(f"{model_path}: expected a glTF 2.0 JSON chunk")
        if total != model_path.stat().st_size or length > total - 20:
            raise ValueError(f"{model_path}: invalid GLB size")
        scene = json.loads(source.read(length))

    hierarchy = extract_hierarchy(scene)
    output = model_path.with_suffix(".hierarchy.json")
    content = json.dumps(hierarchy, ensure_ascii=False, indent=4) + "\n"
    if not output.exists() or output.read_text(encoding="utf-8") != content:
        output.write_text(content, encoding="utf-8", newline="\n")
        print(f"Updated {output}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", nargs="*", type=Path, help="GLB files; defaults to all GLBs in assets")
    args = parser.parse_args()
    assets = Path(__file__).resolve().parent.parent / "assets"
    models = args.models or sorted(path for path in assets.rglob("*") if path.suffix.lower() == ".glb")
    for path in models:
        generate_glb_hierarchy(path)


if __name__ == "__main__":
    main()
