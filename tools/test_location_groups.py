import json
import struct
import tempfile
import unittest
from pathlib import Path

from generate_location_groups import collect_groups, export_scene


class LocationGroupTests(unittest.TestCase):
    def test_each_model_exports_its_own_adjacent_json(self):
        scene = {"nodes": [{"name": "wall", "children": [1]},
                           {"name": "panel", "mesh": 0}]}
        metadata = {"wall": [2, 0, 0]}
        with tempfile.TemporaryDirectory() as directory:
            for extension in (".glb", ".gltf"):
                with self.subTest(extension=extension):
                    source = Path(directory) / extension[1:] / ("room" + extension)
                    source.parent.mkdir()
                    data = json.dumps(scene).encode("utf-8")
                    if extension == ".glb":
                        data += b" " * (-len(data) % 4)
                        data = struct.pack("<4sIIII", b"glTF", 2, len(data) + 20,
                                           len(data), 0x4E4F534A) + data
                    source.write_bytes(data)
                    source.with_suffix(".visibility.json").write_text(json.dumps(metadata))
                    output = export_scene(source)
                    self.assertEqual(output, source.with_suffix(".json"))
                    self.assertEqual(json.loads(output.read_text(encoding="utf-8")),
                                     collect_groups(scene, metadata))
                    self.assertEqual(source.read_bytes(), data)
                    previous_mtime = output.stat().st_mtime_ns
                    export_scene(source)
                    self.assertEqual(output.stat().st_mtime_ns, previous_mtime)

    def test_new_nested_parts_are_included_without_naming_rules(self):
        scene = {
            "scenes": [{"nodes": [0]}],
            "nodes": [
                {"name": "west_wall", "children": [1, 2]},
                {"name": "Plaster", "mesh": 0},
                {"name": "Decorations", "children": [3]},
                {"name": "New_Lamp", "mesh": 1},
            ],
            "meshes": [{"name": "DifferentGeometryName"}, {}],
        }
        result = collect_groups(scene)
        wall = result["aliases"]["west_wall"]
        self.assertEqual(result["groups"][wall], ["Plaster", "New_Lamp"])
        scene["nodes"].append({"name": "Arbitrary_New_Beam", "mesh": 2})
        scene["nodes"][2]["children"].append(4)
        result = collect_groups(scene)
        self.assertIn("Arbitrary_New_Beam", result["groups"][wall])

    def test_panel_and_parent_with_same_name_resolve_to_parent(self):
        result = collect_groups({"nodes": [
            {"name": "wall", "children": [1, 2]},
            {"name": "wall", "mesh": 0},
            {"name": "beam", "mesh": 1},
        ]})
        self.assertEqual(result["groups"][result["aliases"]["wall"]], ["wall", "beam"])

    def test_duplicate_group_names_use_full_paths(self):
        result = collect_groups({"nodes": [
            {"name": "RoomA", "children": [1]},
            {"name": "wall", "children": [2]},
            {"name": "PanelA", "mesh": 0},
            {"name": "RoomB", "children": [4]},
            {"name": "wall", "children": [5]},
            {"name": "PanelB", "mesh": 1},
        ]})
        self.assertNotIn("wall", result["aliases"])
        self.assertEqual(result["groups"]["RoomA/wall"], ["PanelA"])
        self.assertEqual(result["groups"]["RoomB/wall"], ["PanelB"])

    def test_duplicate_mesh_object_names_fail_instead_of_hiding_wrong_parts(self):
        with self.assertRaises(ValueError):
            collect_groups({"nodes": [
                {"name": "A", "children": [1]},
                {"name": "Panel", "mesh": 0},
                {"name": "B", "children": [3]},
                {"name": "Panel", "mesh": 1},
            ]})

    def test_visibility_rules_resolve_groups_and_normalize_directions(self):
        result = collect_groups({"nodes": [
            {"name": "wall", "children": [1]},
            {"name": "panel", "mesh": 0},
        ]}, {"wall": [2, 0, 0], "panel": [[0, 0, -3], [4, 0, 0]]})
        self.assertEqual(result["visibility"]["wall"], [[1, 0, 0]])
        self.assertEqual(result["visibility"]["wall/panel"], [[0, 0, -1], [1, 0, 0]])

    def test_invalid_visibility_rules_fail_instead_of_silently_hiding(self):
        scene = {"nodes": [{"name": "wall", "mesh": 0}]}
        for rules in ({"missing": [1, 0, 0]}, {"wall": [0, 0, 0]},
                      {"wall": []}, {"wall": [float("nan"), 0, 0]},
                      {"wall": 1}, {"wall": [True, 0, 0]}):
            with self.subTest(rules=rules), self.assertRaises(ValueError):
                collect_groups(scene, rules)

    def test_corner_neighbors_resolve_to_parent_groups(self):
        result = collect_groups({"nodes": [
            {"name": "left", "children": [1]},
            {"name": "left", "mesh": 0},
            {"name": "top", "mesh": 1},
            {"name": "corner", "mesh": 2},
        ]}, {"corner": {"visible_with": ["left", "top"]}})
        self.assertEqual(result["visibility_links"]["corner"], ["left", "top"])
        self.assertNotIn("corner", result["visibility"])

    def test_invalid_neighbors_and_dependency_cycles_are_rejected(self):
        scene = {"nodes": [
            {"name": "wall", "children": [1]},
            {"name": "panel", "mesh": 0},
            {"name": "corner", "mesh": 1},
        ]}
        for rules in (
            {"corner": {"visible_with": ["missing"]}},
            {"corner": {"visible_with": []}},
            {"corner": {"visible_with": ["corner"]}},
            {"corner": {"visible_with": ["wall"]}, "wall": {"visible_with": ["corner"]}},
            {"wall": {"visible_with": ["panel"]}},
        ):
            with self.subTest(rules=rules), self.assertRaises(ValueError):
                collect_groups(scene, rules)


if __name__ == "__main__":
    unittest.main()
