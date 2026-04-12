import re

p = 'd:/fdh/BaiduSyncdisk/MnnLlmChat/MnnLlmChat/entry/src/main/python/harmony_agent.py'
with open(p, 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(
    r'if current_step >= max_steps:.*?(?=\n\s*print\(f"\\n---)',
    '''if current_step >= max_steps:
            print(">> 达到最大步数，停止当前任务。强制清除手机端任务。")
            send_request({"type": "clear"})
            active_task = ""
            current_step = 0
            time.sleep(3)
            continue''',
    text,
    flags=re.DOTALL
)

text = re.sub(
    r'if action in \["done", "stop", "terminate"\]:\s*print\([^)]+\)\s*active_task = ""\s*current_step = 0',
    '''if action in ["done", "stop", "terminate"]:
            print(">> 任务执行完毕，通知手机端清空任务...")
            send_request({"type": "clear"})
            active_task = ""
            current_step = 0''',
    text
)

text = re.sub(
    r'elif action == "error":\s*print\([^)]+\)\s*active_task = ""\s*current_step = 0',
    '''elif action == "error":
            print(">> 解析出错，终止。")
            send_request({"type": "clear"})
            active_task = ""
            current_step = 0''',
    text
)

with open(p, 'w', encoding='utf-8') as f:
    f.write(text)
