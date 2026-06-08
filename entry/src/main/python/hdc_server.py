import json
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
import os
import argparse
import time
import threading

try:
    import harmony_agent
except Exception as ex:
    harmony_agent = None
    print(f">> [警告] 无法导入 harmony_agent workflow bridge 能力: {ex}")

NO_REASON_MODE = False
LEGACY_LOOP_ENABLED = True
HDC_HEALTH_CACHE_TTL = 2.0
HDC_COMMAND_TIMEOUT = 20
SERVER_PORT = 9124
APP_AGENT_PORT = 9126
APP_REVERSE_HDC_PORT = 19124
APP_REVERSE_HDC_URL = f"http://127.0.0.1:{APP_REVERSE_HDC_PORT}"
HDC_TARGET_OVERRIDE = os.environ.get("HDC_TARGET", "").strip()

_hdc_health_checked_at = 0.0
_hdc_health_connected = False
_hdc_health_target = ""
_hdc_tunnel_checked_at = 0.0
_hdc_tunnel_status = {
    "status": "unknown",
    "message": "HDC tunnel has not been checked",
    "target": "",
    "tunnel_ready": False,
    "fport_ready": False,
    "rport_ready": False,
}

# PC 侧 HTTP 控制服务：手机 App 通过 /api/run_cmd 触发 HDC 命令，
# workflow bridge 直接通过 /api/workflow 执行动作；9126 轮询 Agent 默认启动，
# 供 App 端本地/云端智能体按钮取任务使用，可用 --workflow_only 关闭。
class HDCServerHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            self.handle_health_request()
            return
        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"Not Found")

    def do_POST(self):
        if self.path == '/api/workflow':
            self.handle_workflow_request()
        elif self.path == '/api/agent_loop/ensure':
            self.handle_agent_loop_ensure()
        elif self.path == '/api/hdc/connect':
            self.handle_hdc_connect()
        elif self.path == '/api/run_cmd':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data)
                cmd = data.get('cmd', '')
                if cmd:
                    print(f">> 正在执行远程指令: {cmd}")
                    # App 端只发送受控调试命令；这里保留 shell=True 以兼容 hdc/tconn 等复合命令。
                    result = run_remote_command(cmd)
                    
                    # 确保 9126 轮询 Agent 处于运行状态；workflow bridge 不依赖它。
                    if LEGACY_LOOP_ENABLED and is_hdc_connected(force=True):
                        ensure_hdc_tunnels(force=True, reset_reverse=True)
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

    def handle_health_request(self):
        try:
            result = hdc_health_payload(force=False)
            self.write_json(200, result)
        except Exception as e:
            print(f">> [HdcHealthError] {e}")
            self.write_json(500, {
                'status': 'error',
                'message': str(e),
                'hdc_connected': False,
                'tunnel_ready': False,
                'app_server_url': APP_REVERSE_HDC_URL
            })

    def handle_hdc_connect(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try:
            request = json.loads(post_data or b'{}')
            target = str(request.get('target', '')).strip()
            kill_others = bool(request.get('kill_others', True))
            prefer_wired = bool(request.get('prefer_wired', True))
            result = connect_hdc_target(target, kill_others=kill_others, prefer_wired=prefer_wired)
            status_code = 200 if result.get('status') == 'ok' else 500
            self.write_json(status_code, result)
        except Exception as e:
            print(f">> [HdcConnectError] {e}")
            self.write_json(500, {
                'status': 'error',
                'message': str(e),
                'hdc_connected': False,
                'tunnel_ready': False,
                'app_server_url': APP_REVERSE_HDC_URL
            })

    def handle_agent_loop_ensure(self):
        try:
            result = ensure_agent_loop_ready()
            status_code = 200 if result.get('status') == 'ok' else 500
            self.write_json(status_code, result)
        except Exception as e:
            print(f">> [AgentLoopEnsure错误] {e}")
            self.write_json(500, {
                'status': 'error',
                'message': str(e)
            })

agent_thread = None
agent_stop_event = threading.Event()
hdc_control_lock = threading.RLock()

def run_process(args, check=False):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=HDC_COMMAND_TIMEOUT)
    except subprocess.TimeoutExpired as ex:
        stderr = f"command timed out after {HDC_COMMAND_TIMEOUT}s: {' '.join(args)}"
        result = subprocess.CompletedProcess(args, 124, ex.stdout or "", stderr)
    if check and result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or f"command failed: {' '.join(args)}"
        raise RuntimeError(message)
    return result

def hdc_args(target=""):
    args = ["hdc"]
    if target:
        args.extend(["-t", target])
    return args

def is_wireless_hdc_target(target):
    return ":" in target

def parse_hdc_targets(output):
    targets = []
    for line in output.splitlines():
        text = line.strip()
        if not text or "[Empty]" in text:
            continue
        lower = text.lower()
        if "not found" in lower or "list targets" in lower:
            continue
        target = text.split()[0].strip()
        if target and target not in targets:
            targets.append(target)
    return targets

def list_hdc_targets():
    result = run_process(["hdc", "list", "targets"])
    if result.returncode != 0:
        return [], result.stderr.strip() or result.stdout.strip()
    return parse_hdc_targets(result.stdout), ""

def choose_hdc_target(targets, preferred_target=""):
    if not targets:
        return ""
    if HDC_TARGET_OVERRIDE:
        if HDC_TARGET_OVERRIDE in targets:
            return HDC_TARGET_OVERRIDE
        print(f">> [HDC] HDC_TARGET is set but not connected: {HDC_TARGET_OVERRIDE}")
        return ""
    wired_targets = [target for target in targets if not is_wireless_hdc_target(target)]
    if wired_targets:
        return wired_targets[0]
    if preferred_target and preferred_target in targets:
        return preferred_target
    wireless_targets = [target for target in targets if is_wireless_hdc_target(target)]
    if wireless_targets:
        return wireless_targets[0]
    return targets[0]

def set_harmony_agent_target(target):
    global _hdc_health_target
    _hdc_health_target = target
    if harmony_agent is not None:
        if hasattr(harmony_agent, "set_hdc_target"):
            harmony_agent.set_hdc_target(target)
        else:
            harmony_agent.HDC_TARGET = target

def run_with_hdc_control(operation_name, operation):
    if harmony_agent is not None and hasattr(harmony_agent, 'run_with_device_control'):
        return harmony_agent.run_with_device_control(operation_name, operation)
    with hdc_control_lock:
        return operation()

def get_active_hdc_target(force=False):
    global _hdc_health_checked_at, _hdc_health_connected, _hdc_health_target
    now = time.monotonic()
    if (not force and _hdc_health_checked_at > 0 and
            now - _hdc_health_checked_at < HDC_HEALTH_CACHE_TTL):
        return _hdc_health_target if _hdc_health_connected else ""

    targets, error = list_hdc_targets()
    if not targets:
        _hdc_health_checked_at = now
        _hdc_health_connected = False
        set_harmony_agent_target("")
        if error:
            print(f">> [HDC] list targets failed: {error}")
        return ""

    target = choose_hdc_target(targets, _hdc_health_target)
    if not target:
        _hdc_health_checked_at = now
        _hdc_health_connected = False
        set_harmony_agent_target("")
        return ""
    set_harmony_agent_target(target)
    _hdc_health_checked_at = now
    _hdc_health_connected = True
    return target

def reset_hdc_tunnel_cache():
    global _hdc_tunnel_checked_at, _hdc_tunnel_status
    _hdc_tunnel_checked_at = 0.0
    _hdc_tunnel_status = {
        "status": "unknown",
        "message": "HDC tunnel has not been checked",
        "target": "",
        "tunnel_ready": False,
        "fport_ready": False,
        "rport_ready": False,
    }

def hdc_port_error_is_existing_mapping(message):
    lower = message.lower()
    return "exist" in lower or "already" in lower or "duplicate" in lower or "存在" in message

def ensure_hdc_tunnels(force=False, reset_reverse=False):
    return run_with_hdc_control(
        "ensure_hdc_tunnels",
        lambda: _ensure_hdc_tunnels_impl(force=force, reset_reverse=reset_reverse)
    )

def run_hdc_tunnel_commands(target, reset_reverse=False):
    fport_errors = []
    rport_errors = []
    commands = [
        (hdc_args(target) + ["fport", "rm", f"tcp:{APP_AGENT_PORT}", f"tcp:{APP_AGENT_PORT}"], False),
        (hdc_args(target) + ["fport", f"tcp:{APP_AGENT_PORT}", f"tcp:{APP_AGENT_PORT}"], True),
    ]
    if reset_reverse:
        commands.append((hdc_args(target) + ["rport", "rm", f"tcp:{APP_REVERSE_HDC_PORT}", f"tcp:{SERVER_PORT}"], False))
    commands.append((hdc_args(target) + ["rport", f"tcp:{APP_REVERSE_HDC_PORT}", f"tcp:{SERVER_PORT}"], True))
    for args, required in commands:
        result = run_process(args)
        if required and result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or " ".join(args)
            if hdc_port_error_is_existing_mapping(message):
                continue
            if "rport" in args:
                rport_errors.append(message)
            else:
                fport_errors.append(message)

    errors = fport_errors + rport_errors
    fport_ready = len(fport_errors) == 0
    rport_ready = len(rport_errors) == 0
    if errors:
        return {
            "status": "error",
            "message": "; ".join(errors),
            "target": target,
            "tunnel_ready": fport_ready and rport_ready,
            "fport_ready": fport_ready,
            "rport_ready": rport_ready,
        }
    return {
        "status": "ok",
        "message": (
            f"HDC tunnel ready: fport tcp:{APP_AGENT_PORT}->tcp:{APP_AGENT_PORT}, "
            f"rport tcp:{APP_REVERSE_HDC_PORT}->tcp:{SERVER_PORT}"
        ),
        "target": target,
        "tunnel_ready": True,
        "fport_ready": True,
        "rport_ready": True,
    }

def choose_fallback_hdc_target(failed_target):
    targets, _ = list_hdc_targets()
    candidates = [target for target in targets if target != failed_target]
    return choose_hdc_target(candidates)

def store_hdc_tunnel_status(status):
    global _hdc_tunnel_checked_at, _hdc_tunnel_status
    _hdc_tunnel_checked_at = time.monotonic()
    _hdc_tunnel_status = status
    return dict(_hdc_tunnel_status)

def refresh_hdc_tunnels_for_target(target, reset_reverse=False, allow_fallback=True):
    return run_with_hdc_control(
        "refresh_hdc_tunnels_for_target",
        lambda: _refresh_hdc_tunnels_for_target_impl(target, reset_reverse, allow_fallback)
    )

def _refresh_hdc_tunnels_for_target_impl(target, reset_reverse=False, allow_fallback=True):
    if not target:
        return store_hdc_tunnel_status({
            "status": "error",
            "message": "HDC target is not connected",
            "target": "",
            "tunnel_ready": False,
            "fport_ready": False,
            "rport_ready": False,
        })

    set_harmony_agent_target(target)
    status = run_hdc_tunnel_commands(target, reset_reverse=reset_reverse)
    if allow_fallback and not status.get("fport_ready"):
        fallback = choose_fallback_hdc_target(target)
        if fallback:
            print(f">> [HDC] target {target} fport failed; retry with {fallback}")
            set_harmony_agent_target(fallback)
            status = run_hdc_tunnel_commands(fallback, reset_reverse=True)
    return store_hdc_tunnel_status(status)

def _ensure_hdc_tunnels_impl(force=False, reset_reverse=False):
    global _hdc_tunnel_checked_at, _hdc_tunnel_status
    now = time.monotonic()
    if (not force and _hdc_tunnel_checked_at > 0 and
            now - _hdc_tunnel_checked_at < HDC_HEALTH_CACHE_TTL):
        return dict(_hdc_tunnel_status)

    target = get_active_hdc_target(force=force)
    if not target:
        return store_hdc_tunnel_status({
            "status": "error",
            "message": "HDC target is not connected",
            "target": "",
            "tunnel_ready": False,
            "fport_ready": False,
            "rport_ready": False,
        })

    return _refresh_hdc_tunnels_for_target_impl(target, reset_reverse=reset_reverse, allow_fallback=True)

def build_hdc_health_payload(target, tunnel):
    active_target = str(tunnel.get("target", "")) or target
    hdc_connected = bool(active_target)
    tunnel_ready = bool(tunnel.get("tunnel_ready"))
    fport_ready = bool(tunnel.get("fport_ready"))
    rport_ready = bool(tunnel.get("rport_ready"))
    return {
        "status": "ok" if hdc_connected and tunnel_ready else "error",
        "message": tunnel.get("message", ""),
        "hdc_connected": hdc_connected,
        "target": active_target,
        "tunnel_ready": tunnel_ready,
        "fport_ready": fport_ready,
        "rport_ready": rport_ready,
        "app_server_url": APP_REVERSE_HDC_URL,
        "server_port": SERVER_PORT,
        "agent_router_port": APP_AGENT_PORT,
        "reverse_server_port": APP_REVERSE_HDC_PORT,
        "loop_enabled": LEGACY_LOOP_ENABLED,
        "loop_alive": agent_thread is not None and agent_thread.is_alive(),
    }

def hdc_health_payload(force=False):
    target = get_active_hdc_target(force=force)
    tunnel = ensure_hdc_tunnels(force=force) if target else {
        "status": "error",
        "message": "HDC target is not connected",
        "target": "",
        "tunnel_ready": False,
        "fport_ready": False,
        "rport_ready": False,
    }
    return build_hdc_health_payload(target, tunnel)

def health_payload_after_target_selected(selected_target, message_prefix="", requested_target=""):
    tunnel = refresh_hdc_tunnels_for_target(selected_target, reset_reverse=True, allow_fallback=True)
    if LEGACY_LOOP_ENABLED and tunnel.get("fport_ready"):
        start_harmony_agent()
    payload = build_hdc_health_payload(str(tunnel.get("target", "")) or selected_target, tunnel)
    if payload.get("hdc_connected") and payload.get("fport_ready"):
        payload["status"] = "ok"
        if not payload.get("tunnel_ready"):
            payload["message"] = (
                "HDC target connected and fport ready; reverse rport is unavailable, "
                "so keep using the manual PC HDC Server URL."
            )
    if message_prefix:
        payload["message"] = message_prefix + " " + str(payload.get("message", "")).strip()
    if requested_target:
        payload["requested_target"] = requested_target
    return payload

def first_wired_target(targets):
    wired_targets = [target for target in targets if not is_wireless_hdc_target(target)]
    return wired_targets[0] if wired_targets else ""

def cleanup_other_wireless_targets(active_target):
    targets, _ = list_hdc_targets()
    for old_target in targets:
        if old_target != active_target and is_wireless_hdc_target(old_target):
            run_process(["hdc", "kill", old_target])

def connect_hdc_target(target, kill_others=True, prefer_wired=True):
    if not target:
        return {
            "status": "error",
            "message": "target is required, for example 192.168.x.x:port",
            "hdc_connected": False,
            "tunnel_ready": False,
            "app_server_url": APP_REVERSE_HDC_URL,
        }

    targets, _ = list_hdc_targets()
    wired_target = first_wired_target(targets)
    if prefer_wired and wired_target and not HDC_TARGET_OVERRIDE:
        invalidate_hdc_health_cache()
        set_harmony_agent_target(wired_target)
        reset_hdc_tunnel_cache()
        return health_payload_after_target_selected(
            wired_target,
            "Using wired HDC target; wireless tconn skipped.",
            requested_target=target
        )

    if target in targets:
        result = subprocess.CompletedProcess(["hdc", "tconn", target], 0, "", "")
    else:
        result = run_process(["hdc", "tconn", target])
    invalidate_hdc_health_cache()
    reset_hdc_tunnel_cache()
    if result.returncode != 0:
        fallback = choose_hdc_target(targets)
        if fallback and fallback != target:
            set_harmony_agent_target(fallback)
            return health_payload_after_target_selected(
                fallback,
                "Wireless tconn failed; using existing HDC target.",
                requested_target=target
            )
        return {
            "status": "error",
            "message": result.stderr.strip() or result.stdout.strip() or f"hdc tconn failed: {target}",
            "hdc_connected": False,
            "target": target,
            "tunnel_ready": False,
            "app_server_url": APP_REVERSE_HDC_URL,
        }

    set_harmony_agent_target(target)
    if kill_others:
        cleanup_other_wireless_targets(target)
    return health_payload_after_target_selected(target, requested_target=target)

def ensure_workflow_agent_ready():
    if harmony_agent is None:
        raise RuntimeError('harmony_agent.py is unavailable')
    if not is_hdc_connected():
        raise RuntimeError('HDC target is not connected')

def run_remote_command(cmd):
    def execute():
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if harmony_agent is not None and 'hdc' in cmd.lower():
            invalidate_hdc_health_cache()
        return result

    if harmony_agent is not None and hasattr(harmony_agent, 'run_with_device_control'):
        return harmony_agent.run_with_device_control('run_cmd', execute)
    return execute()

def run_hdc_command(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'command failed: {cmd}')
    return result.stdout.strip()

def hdc_prefix():
    if harmony_agent is not None:
        return harmony_agent.hdc_prefix()
    return 'hdc'

def payload_bool(payload, key, default):
    value = payload.get(key, default)
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() not in ('false', '0', 'no', 'off')
    return bool(value)

def workflow_gui_action(payload):
    ensure_workflow_agent_ready()
    return harmony_agent.run_with_device_control(
        'workflow_gui_action',
        lambda: _workflow_gui_action_impl(payload)
    )

def _workflow_gui_action_impl(payload):
    action = str(payload.get('action', '')).lower()
    driver = getattr(harmony_agent, 'd', None) if harmony_agent is not None else None

    if action == 'click':
        x = int(payload.get('x', 0))
        y = int(payload.get('y', 0))
        if driver:
            harmony_agent.run_driver_call("Driver.click", lambda d: d.click(x, y))
        else:
            run_hdc_command(f"{hdc_prefix()} shell uitest uiInput click {x} {y}")
        return {'status': 'ok', 'message': f'click {x},{y}'}

    if action == 'input':
        text = str(payload.get('text', ''))
        if driver:
            harmony_agent.run_driver_call("Driver.shell(clear_input)", lambda d: d.shell('uitest uiInput keyEvent 2072 2017'))
            harmony_agent.run_driver_call("Driver.press_key(2071)", lambda d: d.press_key(2071))
            harmony_agent.run_driver_call("Driver.input_text", lambda d: d.input_text(text))
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
                harmony_agent.run_driver_call("Driver.swipe(up)", lambda d: d.swipe(0.5, harmony_agent.SWIPE_V_END, 0.5, harmony_agent.SWIPE_V_START, speed=1000))
            elif direction == 'down':
                harmony_agent.run_driver_call("Driver.swipe(down)", lambda d: d.swipe(0.5, harmony_agent.SWIPE_V_START, 0.5, harmony_agent.SWIPE_V_END, speed=1000))
            elif direction == 'left':
                harmony_agent.run_driver_call("Driver.swipe(left)", lambda d: d.swipe(harmony_agent.SWIPE_H_END, 0.5, harmony_agent.SWIPE_H_START, 0.5, speed=1000))
            elif direction == 'right':
                harmony_agent.run_driver_call("Driver.swipe(right)", lambda d: d.swipe(harmony_agent.SWIPE_H_START, 0.5, harmony_agent.SWIPE_H_END, 0.5, speed=1000))
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
        reset_first = payload_bool(payload, 'reset_first', True)
        if not package_name:
            raise RuntimeError('app_start requires package_name')
        if not harmony_agent.launch_app(package_name, reset_first=reset_first):
            raise RuntimeError(f'app_start failed: {package_name}')
        return {'status': 'ok', 'message': f'app_start {package_name}', 'package_name': package_name}

    if action == 'app_stop':
        package_name = str(payload.get('package_name', ''))
        if not package_name:
            raise RuntimeError('app_stop requires package_name')
        if driver:
            harmony_agent.run_driver_call("Driver.stop_app", lambda d: d.stop_app(package_name))
        else:
            run_hdc_command(f"{hdc_prefix()} shell aa force-stop {package_name}")
        return {'status': 'ok', 'message': f'app_stop {package_name}', 'package_name': package_name}

    raise RuntimeError(f'Unsupported gui_action: {action}')

def handle_workflow_action(action, payload):
    action = str(action or '')
    payload = payload or {}

    if action == 'health':
        return hdc_health_payload(force=True)

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
        reset_first = payload_bool(payload, 'reset_first', True)
        target = app_name or package_name
        if not target:
            raise RuntimeError('app_start requires app_name or package_name')
        ok = harmony_agent.launch_app(target, reset_first=reset_first)
        if not ok and package_name and package_name != target:
            ok = harmony_agent.launch_app(package_name, reset_first=reset_first)
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

def invalidate_hdc_health_cache():
    global _hdc_health_checked_at, _hdc_health_connected, _hdc_health_target
    _hdc_health_checked_at = 0.0
    _hdc_health_connected = False
    set_harmony_agent_target("")
    reset_hdc_tunnel_cache()

def is_hdc_connected(force=False):
    return bool(get_active_hdc_target(force=force))

def _run_harmony_agent_thread(stop_event):
    try:
        harmony_agent.set_no_reason_mode(NO_REASON_MODE)
        harmony_agent.run_agent_loop(stop_event)
    except Exception as ex:
        print(f">> [AgentThread错误] harmony_agent loop exited unexpectedly: {ex}")

def start_harmony_agent():
    global agent_thread, agent_stop_event
    if not LEGACY_LOOP_ENABLED:
        return
    if harmony_agent is None:
        print(">> [警告] harmony_agent.py is unavailable; agent loop will not start.")
        return
    if agent_thread is not None and agent_thread.is_alive():
        return

    agent_stop_event = threading.Event()
    harmony_agent.set_no_reason_mode(NO_REASON_MODE)
    print(">> 正在后台启动任务代理线程: harmony_agent.run_agent_loop")
    agent_thread = threading.Thread(
        target=_run_harmony_agent_thread,
        args=(agent_stop_event,),
        name="harmony-agent-loop",
        daemon=True
    )
    agent_thread.start()

def ensure_agent_loop_ready():
    if not LEGACY_LOOP_ENABLED:
        return {
            'status': 'error',
            'message': '9126 polling loop is disabled by --workflow_only'
        }
    if harmony_agent is None:
        return {
            'status': 'error',
            'message': 'harmony_agent.py is unavailable'
        }

    if not is_hdc_connected(force=True):
        return {
            'status': 'error',
            'message': 'HDC target is not connected',
            'hdc_connected': False,
            'tunnel_ready': False,
            'app_server_url': APP_REVERSE_HDC_URL
        }

    tunnel = ensure_hdc_tunnels(force=True)
    if not tunnel.get("fport_ready"):
        return {
            'status': 'error',
            'message': tunnel.get("message", "HDC fport refresh failed"),
            'hdc_connected': True,
            'target': tunnel.get("target", ""),
            'tunnel_ready': bool(tunnel.get("tunnel_ready")),
            'fport_ready': False,
            'rport_ready': bool(tunnel.get("rport_ready")),
            'app_server_url': APP_REVERSE_HDC_URL
        }

    start_harmony_agent()
    message = 'agent loop is running and HDC fport/rport refreshed'
    if not tunnel.get("rport_ready"):
        message = 'agent loop is running and HDC fport refreshed; reverse rport is unavailable'
    return {
        'status': 'ok',
        'message': message,
        'hdc_connected': True,
        'target': tunnel.get("target", ""),
        'tunnel_ready': bool(tunnel.get("tunnel_ready")),
        'fport_ready': True,
        'rport_ready': bool(tunnel.get("rport_ready")),
        'app_server_url': APP_REVERSE_HDC_URL,
        'loop_alive': agent_thread is not None and agent_thread.is_alive()
    }

def cleanup():
    global agent_thread
    agent_stop_event.set()
    if harmony_agent is not None and hasattr(harmony_agent, 'stop_agent_loop'):
        harmony_agent.stop_agent_loop()
    if agent_thread is not None and agent_thread.is_alive():
        print("\n>> 正在关闭 harmony_agent 后台线程...")
        agent_thread.join(timeout=5)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--no_reason", action="store_true", help="Use prompts without reasoning")
    parser.add_argument("--legacy_loop", action="store_true",
                        help="Compatibility flag; the 9126 polling harmony_agent loop is enabled by default")
    parser.add_argument("--workflow_only", action="store_true",
                        help="Do not start the 9126 polling harmony_agent loop; only expose /api/workflow")
    args = parser.parse_args()
    
    if args.no_reason:
        NO_REASON_MODE = True
    LEGACY_LOOP_ENABLED = not args.workflow_only
    if args.legacy_loop:
        LEGACY_LOOP_ENABLED = True

    # 9126 轮询同时服务 App 端“本地/云端智能体执行”按钮；workflow bridge 仍然按请求直接控制设备。
    if LEGACY_LOOP_ENABLED:
        start_harmony_agent()
        if not is_hdc_connected(force=True):
            print(">> 未检测到 HDC 设备连接；轮询 Agent loop 已启动，将在连接恢复后继续尝试。")
    else:
        print(">> 旧版 harmony_agent 轮询未启用；workflow bridge 将按请求直接控制设备。")
        
    # 监听在独立端口：9123 是模型文件服务，9126 是 App 内 TCP Agent 服务。
    PORT = SERVER_PORT
    server = HTTPServer(('0.0.0.0', PORT), HDCServerHandler)
    if is_hdc_connected(force=True):
        tunnel = ensure_hdc_tunnels(force=True, reset_reverse=True)
        print(f">> [HDC] {tunnel.get('message', '')}")
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
