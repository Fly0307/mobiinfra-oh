import unittest
from unittest.mock import patch

import harmony_agent


class HarmonyAgentHdcTest(unittest.TestCase):
    def test_refresh_forwarding_skips_hdc_command_when_target_missing(self):
        with patch.object(harmony_agent, "get_hdc_target", return_value=""), \
                patch.object(harmony_agent, "_refresh_hdc_forwarding_for_target") as run_fport, \
                patch.object(harmony_agent, "print_hdc_manual_config_hint") as print_hint:
            result = harmony_agent._refresh_hdc_forwarding_impl(verbose=True)

        self.assertEqual(result, 1)
        run_fport.assert_not_called()
        print_hint.assert_called_once_with(force=True)


if __name__ == "__main__":
    unittest.main()
