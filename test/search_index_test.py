import importlib.util
import json
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "scripts" / "build_shymkent_search_index.py"
SPEC = importlib.util.spec_from_file_location("search_index", MODULE_PATH)
search_index = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(search_index)


class ShymkentSearchIndexTests(unittest.TestCase):
    def test_address_entrance_keeps_entrance_coordinates(self):
        feature = {
            "geometry": {"type": "Point", "coordinates": [69.58, 42.34]},
            "properties": {
                "entrance": "main",
                "addr:street": "Тауке хана",
                "addr:housenumber": "15",
                "addr:city": "Шымкент",
            },
        }
        record = search_index.make_record(feature)
        self.assertIsNotNone(record)
        self.assertEqual(record["kind"], "entrance")
        self.assertEqual(record["house"], "15")
        self.assertEqual(record["lon"], 69.58)
        self.assertIn("подъезд", record["search"])

    def test_house_address_is_not_replaced_by_poi_brand(self):
        feature = {
            "geometry": {"type": "Point", "coordinates": [69.58, 42.34]},
            "properties": {
                "name": "Торговый объект",
                "brand": "Mega",
                "addr:street": "Тауке хана",
                "addr:housenumber": "15",
            },
        }
        record = search_index.make_record(feature)
        self.assertEqual(record["label"], "Тауке хана, 15")
        self.assertEqual(record["kind"], "address")

    def test_unnumbered_building_without_street_is_excluded(self):
        feature = {
            "geometry": {"type": "Point", "coordinates": [69.58, 42.34]},
            "properties": {"building": "yes", "addr:housenumber": "7"},
        }
        self.assertIsNone(search_index.make_record(feature))


if __name__ == "__main__":
    unittest.main()
