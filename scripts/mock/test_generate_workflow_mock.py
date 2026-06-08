import importlib.util
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT_DIR = Path(__file__).resolve().parent
GENERATOR_PATH = SCRIPT_DIR / "generate_workflow_mock.py"


def load_generator():
    spec = importlib.util.spec_from_file_location("generate_workflow_mock", GENERATOR_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("Cannot load generate_workflow_mock.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["generate_workflow_mock"] = module
    spec.loader.exec_module(module)
    return module


class WorkflowMockGeneratorTest(unittest.TestCase):
    def test_default_generation_contains_only_daily_log_sources(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "workflows-source"
            summary = generator.generate_mock(output_root, include_runs=False)

            self.assertGreaterEqual(summary["daily_log_files"], 12)
            self.assertGreaterEqual(summary["entry_count"], 40)
            self.assertEqual(summary["run_files"], 0)
            self.assertTrue((output_root / "daily-log").is_dir())
            self.assertFalse((output_root / "runs").exists())
            self.assertFalse((output_root / "profile-consolidation").exists())

            docs = sorted((output_root / "daily-log").glob("*/*.md"))
            self.assertEqual(len(docs), summary["daily_log_files"])
            for path in docs:
                content = path.read_text(encoding="utf-8")
                self.assertTrue(content.startswith("<!-- DAILY_LOG_METADATA\n"))
                self.assertIn('"workflow_metadata"', content)
                self.assertIn('"latest_entry_index"', content)
                self.assertRegex(content, re.compile(r"\n\n1\. .+", re.S))

            validation = generator.validate_mock(output_root)
            self.assertEqual(validation["errors"], [])

    def test_llm_endpoint_normalization_accepts_models_url_default(self):
        generator = load_generator()

        endpoint = generator.normalize_chat_completion_url("http://123.60.91.241:9003/v1/models")

        self.assertEqual(endpoint, "http://123.60.91.241:9003/v1/chat/completions")

    def test_default_llm_request_disables_qwen_thinking(self):
        generator = load_generator()
        captured = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, traceback):
                return False

            def read(self):
                return b'{"choices":[{"message":{"content":"{}"}}]}'

        def fake_urlopen(request, timeout):
            captured["request"] = request
            captured["timeout"] = timeout
            return FakeResponse()

        with patch.object(generator.urllib.request, "urlopen", fake_urlopen):
            generator.default_request_json(
                "http://123.60.91.241:9003/v1/chat/completions",
                "",
                "Qwen3.5-35B-A3B",
                [{"role": "user", "content": "生成一条 mock 数据"}],
                0.7,
                120,
            )

        payload = json.loads(captured["request"].data.decode("utf-8"))
        self.assertEqual(captured["timeout"], 120)
        self.assertEqual(payload["max_tokens"], 16384)
        self.assertEqual(payload["top_p"], 0.8)
        self.assertEqual(payload["presence_penalty"], 1.5)
        self.assertEqual(payload["top_k"], 20)
        self.assertFalse(payload["chat_template_kwargs"]["enable_thinking"])

    def test_llm_json_extractor_tolerates_extra_text_after_first_object(self):
        generator = load_generator()

        payload = generator.extract_json_object(
            "思考过程略。{\"entries\":[{\"domain\":\"takeout\",\"text\":\"一条日志\"}]} trailing {not-json}"
        )

        self.assertEqual(payload["entries"][0]["domain"], "takeout")

    def test_llm_generation_uses_requested_count_and_domains_without_network(self):
        generator = load_generator()
        requests = []

        def fake_request(endpoint, api_key, model, messages, temperature, timeout):
            requests.append({
                "endpoint": endpoint,
                "api_key": api_key,
                "model": model,
                "messages": messages,
                "temperature": temperature,
                "timeout": timeout,
            })
            return {
                "choices": [
                    {
                        "message": {
                            "content": """{
  "entries": [
    {"domain":"takeout","source_app":"饿了么","package_name":"me.ele.eleme","date":"2026-06-05","text":"当前页面显示一笔咖啡外卖订单，商家为Manner Coffee，包含拿铁和贝果，实付36元。"},
    {"domain":"travel","source_app":"携程","package_name":"com.ctrip.harmony","date":"2026-06-05","text":"当前携程页面显示一张上海到杭州的高铁票订单，二等座，订单状态为已出票。"},
    {"domain":"takeout","source_app":"饿了么","package_name":"me.ele.eleme","date":"2026-06-06","text":"当前页面显示一笔晚餐外卖订单，商家为桂满陇，包含东坡肉和米饭，实付58.8元。"}
  ]
}"""
                        }
                    }
                ]
            }

        fixtures = generator.generate_llm_fixtures(
            total_entries=3,
            domains=["takeout", "travel"],
            api_url="http://123.60.91.241:9003/v1/models",
            api_key="",
            model="Qwen3.5-35B-A3B",
            request_json=fake_request,
            batch_size=5,
        )

        self.assertEqual(sum(len(item.entries) for item in fixtures), 3)
        self.assertEqual(requests[0]["endpoint"], "http://123.60.91.241:9003/v1/chat/completions")
        self.assertEqual(requests[0]["api_key"], "")
        self.assertEqual(requests[0]["model"], "Qwen3.5-35B-A3B")
        self.assertTrue(any("takeout" in message["content"] for message in requests[0]["messages"]))
        self.assertTrue(any(item.file_name.startswith("me.ele.eleme__") for item in fixtures))

    def test_optional_runs_generation_adds_lightweight_run_summary(self):
        generator = load_generator()
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "workflows-source"
            summary = generator.generate_mock(output_root, include_runs=True)

            self.assertGreaterEqual(summary["run_files"], 1)
            run_summaries = sorted((output_root / "runs").glob("*/run_summary.json"))
            self.assertEqual(len(run_summaries), summary["run_files"])
            for path in run_summaries:
                content = path.read_text(encoding="utf-8")
                self.assertEqual(path.name, "run_summary.json")
                self.assertIn('"daily_log_path"', content)
                self.assertNotIn("/9j/", content)


if __name__ == "__main__":
    unittest.main()
