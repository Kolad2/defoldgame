"""Export each glTF/GLB hierarchy to a JSON file beside its source model."""

import json
import math
import struct
from pathlib import Path


def read_scene(path):
    if path.suffix.lower() == ".gltf":
        return json.loads(path.read_text(encoding="utf-8"))
    with path.open("rb") as source:
        header = source.read(20)
        if len(header) != 20:
            raise ValueError(f"{path}: truncated GLB header")
        magic, version, total, length, kind = struct.unpack("<4sIIII", header)
        if magic != b"glTF" or version != 2 or kind != 0x4E4F534A:
            raise ValueError(f"{path}: expected a glTF 2.0 JSON chunk")
        if length > total - 20:
            raise ValueError(f"{path}: invalid JSON chunk size")
        data = source.read(length)
        if len(data) != length:
            raise ValueError(f"{path}: truncated JSON chunk")
        return json.loads(data)


def collect_groups(scene, visibility=None):
    nodes = scene.get("nodes", [])
    scenes = scene.get("scenes", [])
    roots = scenes[scene.get("scene", 0)].get("nodes", []) if scenes else [
        i for i in range(len(nodes))
        if not any(i in node.get("children", []) for node in nodes)
    ]
    groups, names, mesh_names, visiting = {}, {}, set(), set()

    def visit(index, parent):
        if index in visiting:
            raise ValueError("Cycle in the node hierarchy")
        visiting.add(index)
        node = nodes[index]
        name = node.get("name") or f"node_{index}"
        path = f"{parent}/{name}" if parent else name
        if path in groups:
            raise ValueError(f"Ambiguous node path: {path}")
        groups[path] = []
        meshes = []
        if "mesh" in node:
            # Defold identifies scene mesh instances by NODE name, not mesh name.
            if not node.get("name"):
                raise ValueError(f"Name the mesh object at {path} before exporting")
            if name in mesh_names:
                raise ValueError(f"Mesh object names must be unique: {name}")
            mesh_names.add(name)
            meshes.append(name)
        children = node.get("children", [])
        for child in children:
            meshes.extend(visit(child, path))
        groups[path] = meshes
        names.setdefault(name, []).append((path, bool(children)))
        visiting.remove(index)
        return meshes

    for root in roots:
        visit(root, "")

    aliases = {}
    for name, candidates in names.items():
        # A Blender collection and its panel may share a name; prefer the parent.
        parents = [path for path, has_children in candidates if has_children]
        choices = parents or [path for path, _ in candidates]
        if len(choices) == 1:
            aliases[name] = choices[0]
    if visibility is not None and not isinstance(visibility, dict):
        raise ValueError("Visibility metadata must map node names to directions")
    rules, links = {}, {}
    for name, rule in (visibility or {}).items():
        path = aliases.get(name, name)
        if path not in groups:
            raise ValueError(f"Unknown or ambiguous visibility node: {name}")
        directions = rule
        if isinstance(rule, dict):
            if not rule or set(rule) - {"normals", "visible_with"}:
                raise ValueError(f"Expected normals or visible_with for {name}")
            directions = rule.get("normals")
            if "visible_with" in rule:
                neighbors = rule["visible_with"]
                if not isinstance(neighbors, list) or not neighbors or not all(
                    isinstance(neighbor, str) for neighbor in neighbors
                ):
                    raise ValueError(f"visible_with must list neighboring node names: {name}")
                resolved = [aliases.get(neighbor, neighbor) for neighbor in neighbors]
                for neighbor in resolved:
                    if neighbor not in groups:
                        raise ValueError(f"Unknown or ambiguous neighbor of {name}: {neighbor}")
                links[path] = resolved
            if directions is None:
                continue
        if not isinstance(directions, list):
            raise ValueError(f"Expected a direction or a list of directions for {name}")
        if len(directions) == 3 and all(isinstance(x, (int, float)) for x in directions):
            directions = [directions]
        normals = []
        for direction in directions:
            if not isinstance(direction, list) or len(direction) != 3 or not all(
                isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)
                for x in direction
            ):
                raise ValueError(f"Expected a finite 3D direction for {name}")
            length = math.hypot(*direction)
            if not math.isfinite(length) or length < 0.000001:
                raise ValueError(f"Visibility direction must have a finite nonzero length: {name}")
            normals.append([x / length for x in direction])
        if not normals:
            raise ValueError(f"Visibility node has no directions: {name}")
        rules[path] = normals

    # Inherited visibility also creates dependencies; reject cycles before runtime.
    checked, pending = set(), set()

    def check_dependencies(path):
        if path in pending:
            raise ValueError(f"Cyclic visibility dependency: {path}")
        if path in checked:
            return
        pending.add(path)
        parent = path.rpartition("/")[0]
        if parent in groups:
            check_dependencies(parent)
        for neighbor in links.get(path, []):
            check_dependencies(neighbor)
        pending.remove(path)
        checked.add(path)

    for path in groups:
        check_dependencies(path)
    return {"groups": groups, "aliases": aliases, "visibility": rules, "visibility_links": links}


def export_scene(path):
    metadata = path.with_suffix(".visibility.json")
    visibility = json.loads(metadata.read_text(encoding="utf-8")) if metadata.exists() else {}
    scene = collect_groups(read_scene(path), visibility)
    output = path.with_suffix(".json")
    content = json.dumps(scene, ensure_ascii=False, indent=4, sort_keys=True, allow_nan=False) + "\n"
    if not output.exists() or output.read_text(encoding="utf-8") != content:
        output.write_text(content, encoding="utf-8", newline="\n")
        print(f"Updated {output.name}")
    return output


def main():
    project = Path(__file__).resolve().parent.parent
    for path in sorted((project / "assets/locations").rglob("*")):
        if path.suffix.lower() not in (".glb", ".gltf"):
            continue
        resource = "/" + path.relative_to(project).as_posix()
        try:
            export_scene(path)
        except (ValueError, KeyError, IndexError) as error:
            raise ValueError(f"{resource}: {error}") from error


if __name__ == "__main__":
    main()
