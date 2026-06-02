import json
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
import os
import sys
import argparse
import time
import os

try:
    import harmony_agent
except Exception as ex:
    harmony_agent = None
    print(f">> [警告] 无法导入 harmony_agent workflow bridge 能力: {ex}")

NO_REASON_MODE = False

# PC 侧 HTTP 控制服务：手机 App 通过 /api/run_cmd 触发 HDC 命令，
# 服务端在确认设备已连接后自动拉起 harmony_agent.py。
class HDCServerHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/workflow':
            self.handle_workflow_request()
        elif self.path == '/api/run_cmd':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data)
                cmd = data.get('cmd', '')
                if cmd:
                    print(f">> 正在执行远程指令: {cmd}")
                    # App 端只发送受控调试命令；这里保留 shell=True 以兼容 hdc/tconn 等复合命令。
                    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                    
                    # 检查是否成功连接了 HDC，并在需要时启动 Agent 轮询 9126。
                    if is_hdc_connected():
                        start_harmony_agent()

                    # 将 stdout 和 stderr 合并返回给手机 App，便于用户在 App 内直接诊断连接问题。
                    output = f"【标准输出】\n{result.stdout}\n【标准错误】\n{result.stderr}"
                    
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/plain; charset=utf-8')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(output.encode('utf-8'))
                else:
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(b"No cmd provided")
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(f"Error: {str(e)}".encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")

    def write_json(self, status_code, payload):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(payload, ensure_ascii=False).encode('utf-8'))

    def handle_workflow_request(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try:
            request = json.loads(post_data or b'{}')
            action = request.get('action', '')
            payload = request.get('payload', {}) or {}
            result = handle_workflow_action(action, payload)
            self.write_json(200, result)
        except Exception as e:
            print(f">> [WorkflowBridge错误] {e}")
            self.write_json(500, {
                'status': 'error',
                'message': str(e)
            })

agent_process = None

def ensure_workflow_agent_ready():
    if harmony_agent is None:
        raise RuntimeError('harmony_agent.py is unavailable')
    if not is_hdc_connected():
        raise RuntimeError('HDC target is not connected')
    harmony_agent.refresh_hdc_forwarding()
    if getattr(harmony_agent, 'd', None) is None:
        harmony_agent.reset_driver()

def run_hdc_command(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'command failed: {cmd}')
    return result.stdout.strip()

def hdc_prefix():
    if harmony_agent is not None:
        return harmony_agent.hdc_prefix()
    return 'hdc'

def workflow_gui_action(payload):
    ensure_workflow_agent_ready()
    action = str(payload.get('action', '')).lower()
    driver = getattr(harmony_agent, 'd', None) if harmony_agent is not None else None

    if action == 'click':
        x = int(payload.get('x', 0))
        y = int(payload.get('y', 0))
        if driver:
            driver.click(x, y)
        else:
            run_hdc_command(f"{hdc_prefix()} shell uitest uiInput click {x} {y}")
        return {'status': 'ok', 'message': f'click {x},{y}'}

    if action == 'input':
        text = str(payload.get('text', ''))
        if driver:
            driver.shell('uitest uiInput keyEvent 2072 2017')
            driver.press_key(2071)
            driver.input_text(text)
            harmony_agent.press_harmony_key('ENTER', 2054)
        else:
            run_hdc_command(f"{hdc_prefix()} shell uitest uiInput inputText '{text}'")
        return {'status': 'ok', 'message': 'input'}

    if action == 'swipe_with_coords':
        sx = int(payload.get('start_x', 0))
        sy = int(payload.get('start_y', 0))
        ex = int(payload.get('end_x', 0))
        ey = int(payload.get('end_y', 0))
        # Use hdc absolute-coordinate input for workflow-defined swipes. hmdriver2 swipe
        # can interpret values as normalized ratios on some versions, so pixel coords may
        # become no-ops even though the API call succeeds.
        run_hdc_command(f"{hdc_prefix()} shell uitest uiInput swipe {sx} {sy} {ex} {ey}")
        return {'status': 'ok', 'message': f'swipe {sx},{sy}->{ex},{ey}'}

    if action == 'swipe':
        direction = str(payload.get('direction', 'up')).lower()
        if driver:
            if direction == 'up':
                driver.swipe(0.5, harmony_agent.SWIPE_V_END, 0.5, harmony_agent.SWIPE_V_START, speed=1000)
            elif direction == 'down':
                driver.swipe(0.5, harmony_agent.SWIPE_V_START, 0.5, harmony_agent.SWIPE_V_END, speed=1000)
            elif direction == 'left':
                driver.swipe(harmony_agent.SWIPE_H_END, 0.5, harmony_agent.SWIPE_H_START, 0.5, speed=1000)
            elif direction == 'right':
                driver.swipe(harmony_agent.SWIPE_H_START, 0.5, harmony_agent.SWIPE_H_END, 0.5, speed=1000)
            else:
                raise RuntimeError(f'unknown swipe direction: {direction}')
        else:
            raise RuntimeError('direction swipe requires hmdriver2 driver')
        return {'status': 'ok', 'message': f'swipe {direction}'}

    if action == 'keyevent':
        key = str(payload.get('key', 'BACK')).upper()
        if key == 'BACK':
            harmony_agent.press_harmony_key('BACK', 2)
        elif key == 'HOME':
            harmony_agent.press_harmony_key('HOME', 1)
        elif key == 'ENTER':
            harmony_agent.press_harmony_key('ENTER', 2054)
        else:
            run_hdc_command(f"{hdc_prefix()} shell uitest uiInput keyEvent {key}")
        return {'status': 'ok', 'message': f'keyevent {key}'}

    if action == 'sleep':
        seconds = float(payload.get('seconds', 1.0))
        time.sleep(seconds)
        return {'status': 'ok', 'message': f'sleep {seconds}'}

    if action == 'app_start':
        package_name = str(payload.get('package_name', ''))
        if not package_name:
            raise RuntimeError('app_start requires package_name')
        harmony_agent.launch_app(package_name)
        return {'status': 'ok', 'message': f'app_start {package_name}', 'package_name': package_name}

    if action == 'app_stop':
        package_name = str(payload.get('package_name', ''))
        if not package_name:
            raise RuntimeError('app_stop requires package_name')
        if driver:
            driver.stop_app(package_name)
        else:
            run_hdc_command(f"{hdc_prefix()} shell aa force-stop {package_name}")
        return {'status': 'ok', 'message': f'app_stop {package_name}', 'package_name': package_name}

    raise RuntimeError(f'Unsupported gui_action: {action}')

def handle_workflow_action(action, payload):
    action = str(action or '')
    payload = payload or {}

    if action == 'health':
        if not is_hdc_connected():
            return {'status': 'error', 'message': 'HDC target is not connected'}
        return {'status': 'ok', 'message': 'HDC connected'}

    if action == 'load_prompt_template':
        if harmony_agent is None:
            raise RuntimeError('harmony_agent.py is unavailable')
        prompt_name = os.path.basename(str(payload.get('prompt_name', '')).strip())
        if not prompt_name:
            raise RuntimeError('prompt_name is required')
        template = harmony_agent.load_prompt(prompt_name)
        if not template:
            raise RuntimeError(f'prompt template not found: {prompt_name}')
        return {
            'status': 'ok',
            'message': f'loaded prompt template: {prompt_name}',
            'result': template
        }

    if action == 'screenshot':
        ensure_workflow_agent_ready()
        factor = float(payload.get('factor', 0.5))
        image_b64, width, height = harmony_agent.capture_screen_mobiagent_style(factor)
        return {
            'status': 'ok',
            'image_b64': image_b64,
            'width': width,
            'height': height,
            'message': f'screenshot {width}x{height}'
        }

    if action == 'app_start':
        ensure_workflow_agent_ready()
        app_name = str(payload.get('app_name', ''))
        package_name = str(payload.get('package_name', ''))
        target = app_name or package_name
        if not target:
            raise RuntimeError('app_start requires app_name or package_name')
        ok = harmony_agent.launch_app(target)
        if not ok and package_name and package_name != target:
            ok = harmony_agent.launch_app(package_name)
        return {
            'status': 'ok' if ok else 'error',
            'message': f'app_start {target}',
            'package_name': package_name
        }

    if action == 'execute_decider_action':
        ensure_workflow_agent_ready()
        response = str(payload.get('response', ''))
        width = int(payload.get('width', 1000))
        height = int(payload.get('height', 1000))
        executed_action, params = harmony_agent.execute_action_and_get_details(response, img_size=(width, height))
        return {
            'status': 'ok',
            'message': f'executed {executed_action}',
            'action': executed_action,
            'result': json.dumps(params, ensure_ascii=False)
        }

    if action == 'gui_action':
        return workflow_gui_action(payload)

    raise RuntimeError(f'Unsupported workflow action: {action}')

def is_hdc_connected():
    try:
        # 当只有一行 [Empty] 时表示空，正常应该输出设备 IP 或者序列号。
        result = subprocess.run("hdc list targets", shell=True, capture_output=True, text=True)
        output = result.stdout.strip()
        if not output or "[Empty]" in output or "not found" in output:
            return False
        return True
    except Exception as e:
        print(f">> [警告] 检查 HDC 连接失败: {e}")
        return False

def start_harmony_agent():
    global agent_process
    # 如果已经在运行中且没有退出，就不重复启动，避免多个 Agent 同时操作同一台设备。
    if agent_process is not None:
        ret_code = agent_process.poll()
        if ret_code is None:
            # 仍在运行
            return
        else:
            print(f">> [提示] harmony_agent.py 之前已退出（退出码: {ret_code}），现在准备重新拉起...")

    agent_script = os.path.join(os.path.dirname(__file__), "harmony_agent.py")
    print(f">> 正在后台自动启动任务代理: {agent_script}")
    try:
        # 使用当前运行 hdc_server 的 Python 环境，避免 hmdriver2/Pillow 安装在另一个解释器里。
        # 共享 stdout/stderr，使 Agent 的执行日志直接打印在这个控制台里。
        cmd = [sys.executable, agent_script]
        if NO_REASON_MODE:
            cmd.append("--no_reason")

        agent_process = subprocess.Popen(
            cmd,
            stdout=sys.stdout,
            stderr=sys.stderr
        )
    except Exception as e:
        print(f">> [错误] 无法启动 harmony_agent.py: {e}")

def cleanup():
    global agent_process
    if agent_process and agent_process.poll() is None:
        print("\n>> 正在关闭 harmony_agent.py...")
        agent_process.terminate()
        agent_process.wait()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--no_reason", action="store_true", help="Use prompts without reasoning")
    args = parser.parse_args()
    
    if args.no_reason:
        NO_REASON_MODE = True

    # 启动代理（如果 HDC 已经挂载）；否则等 App 发起无线连接测试后再拉起。
    if is_hdc_connected():
        start_harmony_agent()
    else:
        print(">> 未检测到 HDC 设备连接，将延后到 App 端发起连接指令后再启动...")
        
    # 监听在独立端口：9123 是模型文件服务，9126 是 App 内 TCP Agent 服务。
    PORT = 9124
    server = HTTPServer(('0.0.0.0', PORT), HDCServerHandler)
    print(f"HDC 远程控制服务端已启动，监听端口: {PORT}...")
    print(f"等待手机 App 发送连接指令...")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        cleanup()
        server.server_close()
        print(">> 服务已退出。")
