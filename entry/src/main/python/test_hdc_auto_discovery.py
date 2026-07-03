import unittest
from unittest.mock import patch

import hdc_server


def seed(target, source="cache-history"):
    entry = hdc_server.seed_entry_from_target(target, source)
    if entry is None:
        raise AssertionError(f"invalid seed target: {target}")
    return entry


class HdcAutoDiscoveryScanTest(unittest.TestCase):
    def test_recent_history_scan_seeds_limits_to_five_targets(self):
        cache_targets = [
            {"target": f"192.168.{idx}.12:33117", "last_success_at": 100 - idx}
            for idx in range(1, 8)
        ]
        cache = {
            "last_target": "192.168.99.9:33117",
            "targets": cache_targets,
        }

        with patch.object(hdc_server, "load_auto_discovery_cache", return_value=cache):
            seeds = hdc_server.recent_history_scan_seeds(limit=5)

        self.assertEqual(5, len(seeds))
        self.assertEqual(
            [
                "192.168.99.9:33117",
                "192.168.1.12:33117",
                "192.168.2.12:33117",
                "192.168.3.12:33117",
                "192.168.4.12:33117",
            ],
            [item["target"] for item in seeds],
        )

    def test_scan_plans_try_local_subnet_before_history_subnets(self):
        history = [
            seed("192.168.43.12:33117", "cache-last"),
            seed("192.168.44.13:33117", "cache-history"),
        ]

        with patch.object(hdc_server, "get_local_ipv4_addresses", return_value=["192.168.137.8"]):
            plans = hdc_server.build_auto_discovery_scan_plans(history)

        self.assertEqual(
            [
                ("192.168.137", 33117, "local-subnet:192.168.137.8"),
                ("192.168.43", 33117, "cache-last"),
                ("192.168.44", 33117, "cache-history"),
            ],
            [(plan["prefix3"], plan["port"], plan["source"]) for plan in plans],
        )

    def test_discover_scans_history_subnet_after_local_subnet_misses(self):
        plans = [
            {
                "prefix2": "192.168",
                "third_octet": 137,
                "prefix3": "192.168.137",
                "port": 33117,
                "source": "local-subnet:192.168.137.8",
                "seeds": [],
            },
            {
                "prefix2": "192.168",
                "third_octet": 43,
                "prefix3": "192.168.43",
                "port": 33117,
                "source": "cache-history",
                "seeds": [seed("192.168.43.12:33117")],
            },
        ]
        scanned = []

        def fake_scan(prefix3, port, host_order, deadline):
            scanned.append(prefix3)
            if prefix3 == "192.168.43":
                return ["192.168.43.88:33117"]
            return []

        def fake_tconn(target, source, precheck=False):
            return {"target": target, "source": source}

        with patch.object(hdc_server, "build_auto_discovery_seeds", return_value=[]), \
                patch.object(hdc_server, "discover_hdc_candidates_from_hdc", return_value=[]), \
                patch.object(hdc_server, "recent_history_scan_seeds", return_value=[seed("192.168.43.12:33117")]), \
                patch.object(hdc_server, "build_auto_discovery_scan_plans", return_value=plans), \
                patch.object(hdc_server, "scan_subnet_for_hdc_port", side_effect=fake_scan), \
                patch.object(hdc_server, "try_hdc_tconn_target", side_effect=fake_tconn):
            candidates = hdc_server.discover_hdc_candidates()

        self.assertEqual(["192.168.137", "192.168.43"], scanned)
        self.assertEqual([{"target": "192.168.43.88:33117", "source": "lan-scan:cache-history"}], candidates)


if __name__ == "__main__":
    unittest.main()
