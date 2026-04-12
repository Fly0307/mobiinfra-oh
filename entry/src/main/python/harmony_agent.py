import os
import time
import json
import base64
import socket
import subprocess
from PIL import Image
import io
import re

PORT = 9126
HOST = '127.0.0.1'

def run_cmd(cmd):
    return subprocess.check_output(cmd, shell=True, text=True)

def capture_screen():
    print(">> Capturing screen via hdc...")
    local_path = "screen.jpeg"
    
    # 截取屏幕并提取鸿蒙实际为你随机生成的文件名
    output = subprocess.check_output("hdc shell snapshot_display", shell=True, text=True)
    match = re.search(r'write to\s+(/\S+\.jpeg)', output)
    
    if match:
        device_path = match.group(1)
    else:
        device_path = "/data/local/tmp/screen.jpeg"
        os.system(f"hdc shell snapshot_display {device_path}")
        
    # 下拉截图到电脑（使用跨平台无输出模式，解决 Linux/zsh/win 下的 >nul 问题）
    subprocess.run(f"hdc file recv {device_path} {local_path}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # 拉取后顺手把手机里的临时文件删掉，防止手机空间爆满
    subprocess.run(f"hdc shell rm \"{device_path}\"", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    img = Image.open(local_path)
    w, h = img.size
    
    # 为了减少网络传输压力和内存占用，进行缩小
    factor = 0.25
    new_w, new_h = int(w * factor), int(h * factor)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    buffered = io.BytesIO()
    img.save(buffered, format="JPEG")
    b64 = base64.b64encode(buffered.getvalue()).decode("utf-8")
    
    return b64, new_w, new_h

def send_request(req):
    payload = json.dumps(req) + "<<EOF>>"
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect((HOST, PORT))
    except Exception as e:
        print(">> 【错误】无法连接到手机 App端，请检查: \n1. 是否在手机App上点击了'启动 PC 控制后端(HDC)'\n2. HDC 是否正常工作")
        raise e
        
    s.sendall(payload.encode('utf-8'))
    
    buffer = ""
    while True:
        data = s.recv(4096)
        if not data:
            break
        buffer += data.decode('utf-8')
        if "<<EOF>>" in buffer:
            break
            
    s.close()
    res = buffer.split("<<EOF>>")[0]
    return res

def poll_task():
    try:
        res = send_request({"type": "poll"})
        data = json.loads(res)
        return data.get("task", "")
    except:
        return ""

def step(goal):
    b64, w, h = capture_screen()
    prompt = f"任务目标: {goal}\n请分析当前屏幕，按照要求严格输出JSON，包含reasoning, action (click/swipe/input/done), parameters。"
    
    print(">> 发送任务到手机 MNN VLM 正在思考...")
    res = send_request({
        "type": "action",
        "prompt": prompt,
        "image_b64": b64,
        "width": w,
        "height": h
    })
    print(f">> MNN VLM 返回:\n{res}")
    
    action = execute_action(res)
    return action

def execute_action(plan):
    import re
    json_str = plan.strip()
    
    # 尝试抽取大模型回复中的 JSON 节点
    match = re.search(r'```json\s*(\{.*?\})\s*```', json_str, re.DOTALL)
    if match: 
        json_str = match.group(1)
    else:
        match = re.search(r'(\{.*?\})', json_str, re.DOTALL)
        if match: 
            json_str = match.group(1)
        
    try:
        data = json.loads(json_str)
    except Exception as e:
        print(f"JSON解析失败: {plan}")
        return "error"
        
    action = data.get("action")
    params = data.get("parameters", data.get("coordinates", {}))
    
    print(f">> [Agent] Action: {action}, Params: {params}")
    
    if action == "click":
        if isinstance(params, list):
            x, y = params[0], params[1]
        else:
            x, y = params.get("x", 0), params.get("y", 0)
        # Uitest 注入点击
        os.system(f"hdc shell uitest uiInput click {int(x)} {int(y)}")
        
    elif action == "swipe":
        direction = params.get("direction")
        if direction:
            print(f"Swipe {direction} 暂未处理坐标")
        else:
            sx, sy = params.get("startX", 0), params.get("startY", 0)
            ex, ey = params.get("endX", 0), params.get("endY", 0)
            os.system(f"hdc shell uitest uiInput swipe {int(sx)} {int(sy)} {int(ex)} {int(ey)}")
            
    elif action == "input":
        text = params.get("text", "")
        print(f">> Input Text: {text}")
        os.system(f"hdc shell uitest uiInput inputText '{text}'")

    return action

if __name__ == "__main__":
    print("初始化 HDC 端口转发...")
    os.system(f"hdc fport tcp:{PORT} tcp:{PORT}")
    
    print(">> 监听模式已启动。等待手机 APP 端派发任务...")
    
    max_steps = 15
    current_step = 0
    active_task = ""
    
    while True:
        task = poll_task()
        if not task:
            # 没任务时清理步数，休眠2秒继续轮询
            if active_task:
                print(">> 任务被结束或重置。")
                active_task = ""
                current_step = 0
            time.sleep(2)
            continue
            
        if task != active_task:
            print(f"\n>>>>>>>> 检测到新任务: {task} <<<<<<<<")
            active_task = task
            current_step = 0
            
        if current_step >= max_steps:
             print(">> 达到最大步数，停止当前任务。强制清除手机端任务。")
             send_request({"type": "clear"})
             active_task = ""
             current_step = 0
             time.sleep(3)
             continue
             
        print(f"\n--- 步骤 {current_step+1}/{max_steps} ---")
        action = step(task)
        if action in ["done", "stop", "terminate"]:
            print(">> 任务执行完毕！通知手机端清除任务。")
            send_request({"type": "clear"})
            active_task = ""
            current_step = 0
        elif action == "error":
            print(">> 解析出错，终止。通知手机端清除任务。")
            send_request({"type": "clear"})
            active_task = ""
            current_step = 0
            
        current_step += 1
        # 等待界面动画完毕
        time.sleep(3)
