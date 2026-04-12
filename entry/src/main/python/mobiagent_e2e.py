from openai import OpenAI
import uiautomator2 as u2
import base64
from PIL import Image #pillow已有
import json
import io
import logging
from abc import ABC, abstractmethod
import time
import re
import os
import shutil
import argparse
from PIL import Image, ImageDraw, ImageFont
import textwrap

from pathlib import Path
import sys

from pathlib import Path
import requests
import tempfile



MAX_STEPS = 35

# SINGLETASK_STORAGE_DIR = Path(__file__).resolve().parent.parent.parent / "utils" / "experience" / "singletask_storage"

LOCAL_LLM_SERVER_URL = "http://127.0.0.1:8080/generate"

def local_llm_generate(prompt: str, image_path: str = None) -> str:
    """
    调用本地 LLM 服务，支持嵌入 <img> 标签。
    Args:
        prompt (str): 文本 prompt
        image_path (str, optional): 本地图片路径
    Returns:
        str: LLM 返回的原始响应字符串（JSON 格式）
    """
    if image_path:
        full_prompt = f"<img>{image_path}</img>{prompt}"
    else:
        full_prompt = prompt

    try:
        response = requests.post(
            LOCAL_LLM_SERVER_URL,
            data={"prompt": full_prompt},
            timeout=180
        )
        response.raise_for_status()
        result = response.json()
        return result.get("response", "")
    except Exception as e:
        logging.error(f"Local LLM request failed: {e}")
        raise RuntimeError(f"LLM inference failed: {e}")

def local_llm_generate_v2(prompt_before_img: str, image_path: str, prompt_after_img: str) -> str:
    """
    调用本地 LLM 服务，支持图像嵌入在两段文本中间的格式。
    Args:
        prompt_before_img (str): 图像前的文本
        image_path (str): 本地图片路径
        prompt_after_img (str): 图像后的文本
    Returns:
        str: LLM 返回的原始响应字符串（JSON 格式）
    """
    full_prompt = f"{prompt_before_img}<img>{image_path}</img>{prompt_after_img}"
    
    try:
        response = requests.post(
            LOCAL_LLM_SERVER_URL,
            data={"prompt": full_prompt},
            timeout=180
        )
        response.raise_for_status()
        result = response.json()
        return result.get("response", "")
    except Exception as e:
        logging.error(f"Local LLM request failed: {e}")
        raise RuntimeError(f"LLM inference failed: {e}")

def invalidate_singletask_storage():
    """Remove cached single-task experience so each run starts clean."""
    if SINGLETASK_STORAGE_DIR.exists():
        shutil.rmtree(SINGLETASK_STORAGE_DIR)
        print(f"Cleared singletask storage at: {SINGLETASK_STORAGE_DIR}")
    else:
        print(f"No singletask storage found at: {SINGLETASK_STORAGE_DIR}")
    SINGLETASK_STORAGE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Initialized empty singletask storage at: {SINGLETASK_STORAGE_DIR}")

class Device(ABC):
    @abstractmethod
    def start_app(self, app):
        pass
    
    @abstractmethod
    def app_stop(self, package_name):
        pass

    @abstractmethod
    def screenshot(self, path):
        pass

    @abstractmethod
    def click(self, x, y):
        pass

    @abstractmethod
    def input(self, text):
        pass

    @abstractmethod
    def swipe(self, direction):
        pass
    
    @abstractmethod
    def swipe_with_coords(self, start_x, start_y, end_x, end_y):
        pass

    @abstractmethod
    def keyevent(self, key):
        pass

    @abstractmethod
    def dump_hierarchy(self):
        pass

class AndroidDevice(Device):
    def __init__(self, adb_endpoint=None):
        super().__init__()
        if adb_endpoint:
            self.d = u2.connect(adb_endpoint)
        else:
            self.d = u2.connect()
        self.app_package_names = {
            "携程": "ctrip.android.view",
            "同城": "com.tongcheng.android",
            "飞猪": "com.taobao.trip",
            "去哪儿": "com.Qunar",
            "华住会": "com.htinns",
            "饿了么": "me.ele",
            "支付宝": "com.eg.android.AlipayGphone",
            "淘宝": "com.taobao.taobao",
            "京东": "com.jingdong.app.mall",
            "美团": "com.sankuai.meituan",
            "滴滴出行": "com.sdu.didi.psnger",
            "微信": "com.tencent.mm",
            "微博": "com.sina.weibo",
            "携程": "ctrip.android.view",
            "华为商城": "com.vmall.client",
            "华为视频": "com.huawei.himovie",
            "华为音乐": "com.huawei.music",
            "华为应用市场": "com.huawei.appmarket",
            "拼多多": "com.xunmeng.pinduoduo",
            "大众点评": "com.dianping.v1",
            "小红书": "com.xingin.xhs",
            "浏览器": "com.microsoft.emmx"
        }

    def start_app(self, app):
        package_name = self.app_package_names.get(app)
        if not package_name:
            raise ValueError(f"App '{app}' is not registered with a package name.")
        self.d.app_start(package_name, stop=True)
        time.sleep(1)
        if not self.d.app_wait(package_name, timeout=20):
            raise RuntimeError(f"Failed to start app '{app}' with package '{package_name}'")
    
    def app_start(self, package_name):
        self.d.app_start(package_name, stop=True)
        time.sleep(2)
        if not self.d.app_wait(package_name, timeout=10):
            raise RuntimeError(f"Failed to start package '{package_name}'")

    def app_stop(self, package_name):
        self.d.app_stop(package_name)

    def screenshot(self, path):
        self.d.screenshot(path)

    def click(self, x, y):
        self.d.click(x, y)
        time.sleep(0.5)

    def clear_input(self):
    # 按下全选（需要 Android 支持 keyevent META_CTRL_ON）
        self.d.shell(['input', 'keyevent', 'KEYCODE_MOVE_END'])
        self.d.shell(['input', 'keyevent', 'KEYCODE_MOVE_HOME'])
        self.d.shell(['input', 'keyevent', 'KEYCODE_DEL'])

    def input(self, text):
        current_ime = self.d.current_ime()
        self.d.shell(['settings', 'put', 'secure', 'default_input_method', 'com.android.adbkeyboard/.AdbIME'])
        time.sleep(0.5)
        # add clear text command, depending on 'ADB Keyboard'
        self.d.shell(['am', 'broadcast', '-a', 'ADB_CLEAR_TEXT'])
        time.sleep(0.2)
        charsb64 = base64.b64encode(text.encode('utf-8')).decode('utf-8')
        self.d.shell(['am', 'broadcast', '-a', 'ADB_INPUT_B64', '--es', 'msg', charsb64])
        time.sleep(0.5)
        self.d.shell(['settings', 'put', 'secure', 'default_input_method', current_ime])
        # time.sleep(0.5)
        # self.d.press("back")
        # time.sleep(0.2)
        self.d.shell(['input', 'keyevent', 'KEYCODE_ENTER'])

    def swipe(self, direction, scale=0.5):
        # self.d.swipe_ext(direction, scale)
        # self.d.swipe_ext(direction=direction, scale=scale)
        if direction.lower() == "up":
            self.d.swipe(0.5,0.7,0.5,0.3)
        elif direction.lower() == "down":
            self.d.swipe(0.5,0.3,0.5,0.7)
        elif direction.lower() == "left":
            self.d.swipe(0.7,0.5,0.3,0.5)
        elif direction.lower() == "right":
            self.d.swipe(0.3,0.5,0.7,0.5)
    def swipe_with_coords(self, start_x, start_y, end_x, end_y):
        """Swipe from (start_x, start_y) to (end_x, end_y)"""
        self.d.swipe(start_x, start_y, end_x, end_y)
    def keyevent(self, key):
        self.d.keyevent(key)

    def dump_hierarchy(self):
        return self.d.dump_hierarchy()



decider_client = None
grounder_client = None
planner_client = None

# planner_model = "gemini-2.5-flash"
planner_model = ""
decider_model = ""
grounder_model = ""

# experience_rr: ExperienceRR = None

# 全局偏好提取器
# preference_extractor = None


use_local_llm_planner = False
use_local_llm_grounder = False
use_local_llm_decider = False
def init(service_ip, decider_port, grounder_port, planner_port, enable_user_profile=False, use_graphrag=False, use_experience_rr=False, use_local_planner=False, use_local_grounder=False, use_local_decider=False):
    global decider_client, grounder_client, planner_client, use_local_llm_planner, use_local_llm_grounder, use_local_llm_decider
    use_local_llm_planner = use_local_planner
    use_local_llm_grounder = use_local_grounder
    use_local_llm_decider = use_local_decider
    # , general_client, general_model, apps, preference_extractor, experience_rr
    
    # 加载环境变量
    env_path = Path(__file__).parent / ".env"
    # # load_dotenv(env_path) 
    if not use_local_llm_decider:
        decider_client = OpenAI(
            api_key="mobiagent-key",
            base_url=f"http://{service_ip}:{decider_port}/v1",
        )
    if not use_local_llm_grounder:
        grounder_client = OpenAI(
            api_key="mobiagent-key",
            base_url=f"http://{service_ip}:{grounder_port}/v1",
        )
    if not use_local_llm_planner:
        planner_client = OpenAI(
            api_key="mobiagent-key",
            base_url=f"http://{service_ip}:{planner_port}/v1",
        )


    
# 截图缩放比例
factor = 0.5


from pydantic import BaseModel, Field
from typing import Any, Literal, Dict, Optional, Union
from enum import Enum

# 1. 使用 Enum 定义固定的动作类型
class ActionType(str, Enum):
    """
    定义了所有可能的用户界面动作。
    """
    CLICK = "click"
    INPUT = "input"
    SWIPE = "swipe"
    DONE = "done"
    STOP = "stop"
    TERMINATE = "terminate"
    WAIT = "wait"

# 2. 编写 ActionPlan 模型
class ActionPlan(BaseModel):
    """
    定义一个包含推理、动作和参数的结构化计划。
    """
    reasoning: str = Field(
        description="描述执行此动作的思考过程和理由。"
    )
    
    action: ActionType = Field(
        description="要执行的下一个动作。"
    )
    
    parameters: Dict[str, str] = Field(
        description="执行动作所需要的参数，以键值对形式提供。",
        default_factory=dict  # 如果没有参数，默认为空字典
    )


# 2. 从 Pydantic 模型生成 JSON Schema
json_schema = ActionPlan.model_json_schema()

class GroundResponse(BaseModel):
    coordinates: list[int] = Field(
        description="点击坐标 [x, y]",
        default=None
    )
    bbox: list[int] = Field(
        description="边界框 [x1, y1, x2, y2]",
        default=None
    )
    bbox_2d: list[int] = Field(description="边界框 [x1, y1, x2, y2]",
        default=None
    )

json_schema_ground = GroundResponse.model_json_schema()


def parse_json_response(response_str: str) -> dict:
    """解析JSON响应
    
    Args:
        response_str: 模型返回的响应字符串
        
    Returns:
        解析后的JSON对象
    """
    print("Parsing JSON response...")
    import re
    # 清理开头多余的 {"} 这种错误输出
    response_str = re.sub(r'^\{"\}\s*', '', response_str.strip())
    
    try:
        # 尝试直接解析JSON
        return json.loads(response_str)
    except json.JSONDecodeError:
        # 如果直接解析失败，尝试提取JSON部分
        try:
            # 查找JSON代码块
            json_match = re.search(r'```json\s*(\{.*?\})\s*```', response_str, re.DOTALL)
            if json_match:
                return json.loads(json_match.group(1))
            
            # 查找花括号包围的JSON
            json_match = re.search(r'(\{.*?\})', response_str, re.DOTALL)
            if json_match:
                return json.loads(json_match.group(1))
            
            raise ValueError("无法在响应中找到有效的JSON")
        except Exception as e:
            logging.error(f"JSON解析失败: {e}")
            logging.error(f"原始响应: {response_str}")
            raise ValueError(f"无法解析JSON响应: {e}")

def get_screenshot(device, device_type="Android"):
    """
    获取设备截图并编码为base64
    
    Args:
        device: 设备对象
        device_type: 设备类型，"Android" 或 "Harmony"
        
    Returns:
        Base64编码的截图字符串
    """
    # 根据设备类型使用不同的截图路径，避免冲突
    if device_type == "Android":
        screenshot_path = "screenshot-Android.jpg"
    else:
        screenshot_path = "screenshot-Harmony.jpg"
    device.screenshot(screenshot_path)
    # resize the screenshot to reduce the size for processing
    img = Image.open(screenshot_path)
    img = img.resize((int(img.width * factor), int(img.height * factor)), Image.Resampling.LANCZOS)
    buffered = io.BytesIO()
    img.save(buffered, format="JPEG")
    screenshot = base64.b64encode(buffered.getvalue()).decode("utf-8")
    return screenshot

def convert_qwen3_coordinates_to_absolute(bbox_or_coords, img_width, img_height, is_bbox=True):
    """
    将 Qwen3 模型返回的相对坐标（0-1000范围）转换为绝对坐标
    
    Args:
        bbox_or_coords: 相对坐标或边界框，范围为 0-1000
        img_width: 图像宽度
        img_height: 图像高度
        is_bbox: 是否为边界框（True）或坐标点（False）
        
    Returns:
        转换后的绝对坐标或边界框
    """
    if is_bbox:
        # bbox: [x1, y1, x2, y2]
        x1, y1, x2, y2 = bbox_or_coords
        x1 = int(x1 / 1000 * img_width)
        x2 = int(x2 / 1000 * img_width)
        y1 = int(y1 / 1000 * img_height)
        y2 = int(y2 / 1000 * img_height)
        return [x1, y1, x2, y2]
    else:
        # coordinates: [x, y]
        x, y = bbox_or_coords
        x = int(x / 1000 * img_width)
        y = int(y / 1000 * img_height)
        return [x, y]

def create_swipe_visualization(data_dir, image_index, direction):
    """为滑动动作创建可视化图像"""
    try:
        # 读取原始截图
        img_path = os.path.join(data_dir, f"{image_index}.jpg")
        if not os.path.exists(img_path):
            return
            
        img = cv2.imread(img_path)
        if img is None:
            return
            
        height, width = img.shape[:2]
        
        # 根据方向计算箭头起点和终点
        center_x, center_y = width // 2, height // 2
        arrow_length = min(width, height) // 4
        
        if direction == "up":
            start_point = (center_x, center_y + arrow_length // 2)
            end_point = (center_x, center_y - arrow_length // 2)
        elif direction == "down":
            start_point = (center_x, center_y - arrow_length // 2)
            end_point = (center_x, center_y + arrow_length // 2)
        elif direction == "left":
            start_point = (center_x + arrow_length // 2, center_y)
            end_point = (center_x - arrow_length // 2, center_y)
        elif direction == "right":
            start_point = (center_x - arrow_length // 2, center_y)
            end_point = (center_x + arrow_length // 2, center_y)
        else:
            return
            
        # 绘制箭头
        cv2.arrowedLine(img, start_point, end_point, (255, 0, 0), 8, tipLength=0.3)  # 蓝色箭头
        
        # 添加文字说明
        font = cv2.FONT_HERSHEY_SIMPLEX
        text = f"SWIPE {direction.upper()}"
        text_size = cv2.getTextSize(text, font, 1.5, 3)[0]
        text_x = (width - text_size[0]) // 2
        text_y = 50
        cv2.putText(img, text, (text_x, text_y), font, 1.5, (255, 0, 0), 3)  # 蓝色文字
        
        # 保存可视化图像
        swipe_path = os.path.join(data_dir, f"{image_index}_swipe.jpg")
        cv2.imwrite(swipe_path, img)
        
    except Exception as e:
        logging.warning(f"Failed to create swipe visualization: {e}")



# 预处理增强健壮性
def robust_json_loads(s):
    import re
    s = s.strip()
    
    # 清理开头多余的 {"} 这种错误输出
    s = re.sub(r'^\{"\}\s*', '', s)
    
    # 提取 ```json ... ``` 代码块
    codeblock = re.search(r"```json(.*?)```", s, re.DOTALL)
    if codeblock:
        s = codeblock.group(1).strip()
    s = s.replace("…", "...").replace("\r", "").replace("\n", " ")

    # 修复数组中数字之间漏掉逗号的问题，如 [818, 119, 96 131]
    s = re.sub(r'(\d+)\s+(\d+)', r'\1, \2', s)

    try:
        return json.loads(s)
    except json.decoder.JSONDecodeError as e:
        if "Expecting ',' delimiter" in str(e):
            # 定义我们关心的字段名（按可能出现的顺序）
            fields = ["reasoning", "thought", "action", "step", "parameters", "target_element"]
            field_pattern = '|'.join(re.escape(f) for f in fields)
            
            # 模式1：字段值未闭合（缺少 "）
            # 例如: "reasoning": "内容  "action":

            str_lit = r'"(?:[^"\\]|\\.)*"'

            # 模式1：字段值未闭合（缺少结尾 "）
            # 匹配: "field": "内容...（未闭合）  "next_field":
            pattern1 = rf'("({field_pattern})"\s*:\s*"((?:[^"\\]|\\.)*)?)(\s*"({field_pattern})"\s*:)'
            fixed_s1 = re.sub(pattern1, r'\1",\4', s)  # 补 " 和 ,

            # 模式2：字段值已闭合，但缺逗号
            # 匹配: "field": "完整内容"  "next_field":
            pattern2 = rf'("({field_pattern})"\s*:\s*{str_lit})(\s*"({field_pattern})"\s*:)'
            fixed_s2 = re.sub(pattern2, r'\1,\3', s)   # 只补 ,
            
            # 尝试：先用模式1（更严重），再用模式2
            for candidate in [fixed_s1, fixed_s2]:
                if candidate != s:  # 确实做了修改
                    try:
                        return json.loads(candidate)
                    except json.JSONDecodeError:
                        continue

            # 如果都不行，再尝试更激进的通用逗号修复（谨慎使用）
            # 例如：匹配 "xxx"  后跟 "yyy": 且中间无逗号
            generic_pattern = r'("[^"]*?")(\s*"[a-zA-Z_][a-zA-Z0-9_]*"\s*:)'
            generic_fixed = re.sub(generic_pattern, r'\1,\2', s)
            if generic_fixed != s:
                try:
                    return json.loads(generic_fixed)
                except:
                    pass


        # === 修复 2：多余内容（包括多余 }、文字等）===
        if "Extra data" in str(e):
            try:
                decoder = json.JSONDecoder()
                obj, end = decoder.raw_decode(s)
                logging.warning(f"Extra data detected. Parsed valid JSON up to position {end}.")
                return obj
            except Exception:
                pass
        
        # 所有修复失败，报错
        logging.error(f"解析 decider_response_str 失败: {e}\n原始内容: {s}")
        raise
    
    except Exception as e:
        logging.error(f"解析 decider_response_str 失败: {e}\n原始内容: {s}")
        raise

def load_prompt(md_name):
    """从markdown文件加载应用选择prompt模板"""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    prompt_file = os.path.join(current_dir, "prompts", md_name)

    with open(prompt_file, "r", encoding="utf-8") as f:
        content = f.read()
    content = content.replace("````markdown", "").replace("````", "")
    return content.strip()


import xml.etree.ElementTree as ET
from collections import Counter

def load_and_parse_xml(xml_path):
    with open(xml_path, 'r', encoding='utf-8') as f:
        content = f.read()
    # 修复可能的 XML 声明缺失
    if not content.strip().startswith('<'):
        # 找到第一个 < 开始截取
        start = content.find('<')
        if start != -1:
            content = content[start:]
    return ET.fromstring(content)

def char_overlap_score(s1, s2):
    """计算两个字符串的字符交集数量（不考虑顺序，重复字符按最小频次计）"""
    c1, c2 = Counter(s1), Counter(s2)
    intersection = (c1 & c2).elements()
    return sum(1 for _ in intersection)

def is_likely_garbled(text):
    """
    判断 text 是否很可能是“乱码”（如图标字体）。
    规则：
      - 非空
      - 所有字符都在 Private Use Area (U+E000–U+F8FF) 或其他非常用区
      - 且不含中文、英文、数字、常见标点
    """
    if not text:
        return False  # 空不算乱码，只是无文本

    # 常见有效字符的判断（白名单）
    def is_useful_char(ch):
        # 中文
        if '\u4e00' <= ch <= '\u9fff':
            return True
        # 英文字母
        if ch.isalpha() and ord(ch) < 128:
            return True
        # 数字
        if ch.isdigit():
            return True
        # 常见中文标点、英文标点、空格
        if ch in '，。！？；：""''（）【】《》〈〉、,.!?;:"\'()[]{}<> \t\n':
            return True
        # 其他常见符号如 @ # $ % & * + - = / 等
        if ch in '@#$%&*+-=/_':
            return True
        return False

    # 如果**至少有一个字符是有意义的**，就认为不是乱码
    if any(is_useful_char(ch) for ch in text):
        return False

    # 否则，很可能是 PUA 图标或无意义字符
    return True

flag = False
def find_best_match_node(root, target_element):
    global flag
    candidates = []
    target_clean = target_element.strip()
    if not target_clean:
        return None

    # 遍历所有节点
    for node in root.iter():

        text = node.get('text', '').strip()
        if not text:
            text = node.get('content-desc', '').strip()
            if not text:
                continue
        if is_likely_garbled(text):
            text = node.get('content-desc', '').strip()
            if not text:
                continue
        
        text1 = node.get('content-desc', '').strip()
        id = node.get('resource-id', '').strip()
        
        score = char_overlap_score(target_clean, text)
        
        if score > 1:
            bounds_str = node.get('bounds', '')
            if not bounds_str:
                continue
            # 解析 bounds: "[x1,y1][x2,y2]" → [x1, y1, x2, y2]
            try:
                coords = bounds_str.strip('[]').replace('][', ',').split(',')
                x1, y1, x2, y2 = map(int, coords)
                if ("搜索栏" in text) and flag == False:
                    flag = True
                    bounds = [x1, y1, x2, y2]
                    search_bar_node = bounds  # 记录第一个或最后一个均可，通常只有一个
                    print("11111111111111")
                    return bounds
                
                candidates.append({
                    'text': text,
                    'content-desc': text1,
                    'score': score,
                    'length': len(text),
                    'bounds': [x1, y1, x2, y2]
                })
            except Exception:
                continue
        else:
            bounds_str = node.get('bounds', '')
            if not bounds_str:
                continue
            if ((("搜索栏" in target_clean) or ("搜索框" in target_clean)) and (id == "com.taobao.taobao:id/searchEdit")):
                print(id)
                flag = True
                coords = bounds_str.strip('[]').replace('][', ',').split(',')
                x1, y1, x2, y2 = map(int, coords)
                bounds = [x1, y1, x2, y2]
                search_bar_node = bounds  # 记录第一个或最后一个均可，通常只有一个
                print("222222222222")
                return bounds
            
            

    if not candidates:
        return None

    # 排序：先按 score 降序，再按 text 长度升序
    candidates.sort(key=lambda x: (-x['score'], x['length']))
    print("candidates")
    print(candidates)
    flag = False
    return candidates[0]['bounds']
def task_in_app(app, old_task, task,  device, data_dir, bbox_flag=True, use_qwen3=True, device_type="Android", use_e2e=False, use_e2e_v2=False):
    history = []
    actions = []
    reacts = []
    global use_local_llm_planner
    global use_local_llm_grounder
    global use_local_llm_decider

    # full history for experience record
    # if experience_rr is not enabled, full_history is the same as history
    # otherwise, history only contains partial history in current subtask
    full_history = []


    if use_e2e_v2 and use_local_llm_decider:
        # Use e2e_v2.md for the new e2e_v2 mode
        decider_prompt_template = load_prompt("e2e_v2.md")
        grounder_prompt_template_bbox = load_prompt("grounder_qwen3_bbox.md")
        grounder_prompt_template_no_bbox = load_prompt("grounder_qwen3_coordinates.md")
        logging.info("Using e2e_v2 mode with e2e_v2.md")
    elif use_e2e_v2:
        # Use e2e_v2.md for the new e2e_v2 mode
        decider_prompt_template = load_prompt("e2e_v2_old.md")
        grounder_prompt_template_bbox = load_prompt("grounder_qwen3_bbox.md")
        grounder_prompt_template_no_bbox = load_prompt("grounder_qwen3_coordinates.md")
        logging.info("Using e2e_v2 mode with e2e_v2.md")
    elif use_e2e:
        # 在e2e模式下使用e2e_qwen3.md，否则使用decider_v2.md
        decider_prompt_template = load_prompt("e2e_qwen3.md")
        grounder_prompt_template_bbox = load_prompt("grounder_qwen3_bbox.md")
        grounder_prompt_template_no_bbox = load_prompt("grounder_qwen3_coordinates.md")
        logging.info("Using e2e mode with e2e_qwen3.md")
    elif use_qwen3:
        grounder_prompt_template_bbox = load_prompt("grounder_qwen3_bbox.md")
        grounder_prompt_template_no_bbox = load_prompt("grounder_qwen3_coordinates.md")
        # decider_prompt_template = load_prompt("decider_qwen3.md")
        decider_prompt_template = load_prompt("decider_v2.md")
    else:
        grounder_prompt_template_bbox = load_prompt("grounder_bbox.md")
        grounder_prompt_template_no_bbox = load_prompt("grounder_coordinates.md")
        decider_prompt_template = load_prompt("decider_v2.md")
    
    # only for experience rr
    # store original task description since `task` can be modified during execution
    orig_task = task
    executing_subtask = False
    replay_idx = 0
    
    while True:
        if len(actions) >= MAX_STEPS:
            print("Reached maximum steps, stopping the task.")
            break
        
        replay_this_step = False
        replay_grounder_bbox = None
        

        if len(history) == 0:
            history_str = "(No history)"
        else:
            history_str = "\n".join(f"{idx}. {h}" for idx, h in enumerate(history, 1))
        screenshot_resize = get_screenshot(device, device_type)

        if not replay_this_step:
            # For e2e_v2 mode, we need to construct the prompt dynamically with actual screenshot info
            if use_e2e_v2 and use_local_llm_decider:
                # Get actual screenshot path and hardware info
                if device_type == "Android":
                    actual_screenshot_path = "screenshot-Android.jpg"
                else:
                    actual_screenshot_path = "screenshot-Harmony.jpg"
                
                # Get image dimensions for hardware info
                img_temp = Image.open(actual_screenshot_path)
                hw_info = f"<hw>600,270</hw>"
                
                # Load the base template without the image line
                base_template = decider_prompt_template.format(
                    task=task,
                    history=history_str
                )
                # Remove the placeholder image line and everything after it
                if "<img>" in base_template:
                    img_start_idx = base_template.find("<img>")
                    prompt_before_img = base_template[:img_start_idx].rstrip()
                else:
                    prompt_before_img = base_template
                
                # Construct the full prompt with actual screenshot and hw info
                prompt_after_img = "\n   \nPlease provide the next action based on the screenshot and your action history. You should do careful reasoning before providing the action."
                image_tag = f"<img>{actual_screenshot_path}{hw_info}</img>"
                decider_prompt = f"{prompt_before_img}\n\n{image_tag}{prompt_after_img}"
            elif use_e2e_v2:
                decider_prompt = decider_prompt_template.format(
                    task=task,
                    history=history_str
                )

            else:
                decider_prompt = decider_prompt_template.format(
                    task=task,
                    history=history_str
                )
            print(f"Decider prompt: \n{decider_prompt}")

            decider_start_time = time.time()

            if use_local_llm_decider:
                with tempfile.NamedTemporaryFile(suffix=".png", delete=False, dir=".") as tmp_img:
                    tmp_img_path = tmp_img.name
                    src_path = "screenshot-Android.jpg" if device_type == "Android" else "screenshot-Harmony.jpg"
                    img = Image.open(src_path)
                    img.save(tmp_img_path, "PNG")
                
                try:
                    # For e2e_v2 mode, we already constructed the full prompt above
                    if use_e2e_v2:
                        # Since we already have the full prompt with actual screenshot path,
                        # we just need to replace the screenshot path with the temp file path
                        # that contains the actual image data
                        final_prompt = decider_prompt.replace(actual_screenshot_path, tmp_img_path)
                        decider_response_str = local_llm_generate(final_prompt)
                    else:
                        decider_response_str = local_llm_generate(decider_prompt, tmp_img_path)
                finally:
                    if os.path.exists(tmp_img_path):
                        os.remove(tmp_img_path)
            else:
                # For OpenAI client, we still use the original format with base64 image
                decider_response_obj = decider_client.chat.completions.create(
                    model=decider_model,
                    messages=[{
                        "role": "user",
                        "content": [
                            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{screenshot_resize}"}},
                            {"type": "text", "text": decider_prompt},
                        ]
                    }],
                    temperature=0,
                    response_format={"type": "json_object", "schema": json_schema}
                )
                decider_response_str = decider_response_obj.choices[0].message.content
            
            

            decider_end_time = time.time()
            print(f"Decider time taken: {decider_end_time - decider_start_time} seconds")
            print(f"Decider response: \n{decider_response_str}")

        decider_response = robust_json_loads(decider_response_str)
        action = decider_response["action"]

        # ignore `done` action of subtasks in persistant execution logs and full_history
        if not (executing_subtask and action == "done"):
            converted_item = {
                "reasoning": decider_response["reasoning"],
                "function": {
                    "name": decider_response["action"],
                    "parameters": decider_response["parameters"]
                }
            }
            reacts.append(converted_item)

            # compute image index for this loop iteration (1-based)
            image_index = len(actions) + 1
            current_dir = os.getcwd()
            current_image = ""
            if device_type == "Android":
                img_path = os.path.join(current_dir, f"screenshot-Android.jpg")
                save_path = os.path.join(data_dir, f"{image_index}.jpg")
                current_image = f"screenshot-Android.jpg"
            else:
                img_path = os.path.join(current_dir, f"screenshot-Harmony.jpg")
                save_path = os.path.join(data_dir, f"{image_index}.jpg")
                current_image = f"screenshot-Harmony.jpg"
            img = Image.open(img_path)
            img.save(save_path)

            # attach index to the most recent react (reasoning)
            if reacts:
                try:
                    reacts[-1]["action_index"] = image_index
                except Exception:
                    pass

            # 根据设备类型保存hierarchy
            hierarchy = device.dump_hierarchy()
            # print(hierarchy)
            
            if device_type == "Android":
                # Android设备保存为XML格式
                hierarchy_path = os.path.join(data_dir, f"{image_index}.xml")
                with open(hierarchy_path, "w", encoding="utf-8") as f:
                    f.write(hierarchy)
            else:
                # Harmony设备保存为JSON格式
                hierarchy_path = os.path.join(data_dir, f"{image_index}.json")
                try:
                    # 尝试将hierarchy解析为JSON（如果已是JSON字符串）
                    if isinstance(hierarchy, str):
                        hierarchy_json = json.loads(hierarchy)
                    else:
                        hierarchy_json = hierarchy
                    with open(hierarchy_path, "w", encoding="utf-8") as f:
                        json.dump(hierarchy_json, f, ensure_ascii=False, indent=2)
                except (json.JSONDecodeError, TypeError):
                    # 如果解析失败，直接保存为字符串
                    logging.warning(f"Failed to parse hierarchy as JSON, saving as plain text")
                    with open(hierarchy_path, "w", encoding="utf-8") as f:
                        f.write(str(hierarchy))
            full_history.append(decider_response_str)




        history.append(json.dumps(decider_response, ensure_ascii=False))

        if action == "done":
            
            print("Task completed.")
            status = decider_response["parameters"]["status"]
            actions.append({
                "type": "done",
                "status": status,
                "action_index": image_index
            })
            break
        elif action == "click":
            if replay_grounder_bbox is None:
                reasoning = decider_response["reasoning"]
                target_element = decider_response["parameters"]["target_element"]
                grounder_prompt = (grounder_prompt_template_bbox if bbox_flag else grounder_prompt_template_no_bbox).format(reasoning=reasoning, description=target_element)
                # print(f"Grounder prompt: \n{grounder_prompt}")
                
            if bbox_flag:

                reasoning = decider_response["reasoning"]
                target_element = decider_response["parameters"]["target_element"]
                
                # e2e_v2 mode: directly get bbox from decider, don't call grounder
                if use_e2e_v2:
                    bbox = decider_response["parameters"]["bbox"]
                    if bbox is None:
                        logging.error("E2E_V2 mode: bbox not found in decider response")
                        raise ValueError("E2E_V2 mode requires bbox in decider response")
                    
                    logging.info(f"E2E_V2 mode: Using bbox directly from decider: {bbox}")
                    # 使用 Qwen3 模型进行坐标转换
                    if use_qwen3:
                        bbox = convert_qwen3_coordinates_to_absolute(bbox, img.width, img.height, is_bbox=True)
                    x1, y1, x2, y2 = bbox

                # e2e模式：直接从decider获取bbox，不调用grounder
                elif use_e2e:
                    bbox = decider_response["parameters"]["bbox"]
                    if bbox is None:
                        logging.error("E2E mode: bbox not found in decider response")
                        raise ValueError("E2E mode requires bbox in decider response")
                    
                    logging.info(f"E2E mode: Using bbox directly from decider: {bbox}")
                    # 使用 Qwen3 模型进行坐标转换
                    if use_qwen3:
                        bbox = convert_qwen3_coordinates_to_absolute(bbox, img.width, img.height, is_bbox=True)
                    x1, y1, x2, y2 = bbox

                elif replay_grounder_bbox is None:
                    reasoning = decider_response["reasoning"]
                    target_element = decider_response["parameters"]["target_element"]

                    # 👇 新逻辑：从 XML 中查找最佳匹配节点
                    xml_path = os.path.join(data_dir, f"{image_index}.xml")
                    try:
                        root = load_and_parse_xml(xml_path)
                        bbox = find_best_match_node(root, target_element)
                        bbox = None
                        if bbox is None:
                            print("gggggggggggggggggggggggggggggggggg")
                            grounder_start_time = time.time()
                            if use_local_llm_grounder:
                                with tempfile.NamedTemporaryFile(suffix=".png", delete=False, dir=".") as tmp_img:
                                    tmp_grounder_img_path = tmp_img.name
                                    src_path = "screenshot-Android.jpg" if device_type == "Android" else "screenshot-Harmony.jpg"
                                    img = Image.open(src_path)
                                    img.save(tmp_grounder_img_path, "PNG")
                                try:
                                    grounder_response_str = local_llm_generate(grounder_prompt, tmp_grounder_img_path)
                                finally:
                                    if os.path.exists(tmp_grounder_img_path):
                                        os.remove(tmp_grounder_img_path)
                            else:
                                grounder_response_obj = grounder_client.chat.completions.create(
                                    model=grounder_model,
                                    messages=[{
                                        "role": "user",
                                        "content": [
                                            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{screenshot_resize}"}},
                                            {"type": "text", "text": grounder_prompt},
                                        ]
                                    }],
                                    temperature=0,
                                )
                                grounder_response_str = grounder_response_obj.choices[0].message.content


                            grounder_end_time = time.time()
                            print(f"Grounder time taken: {grounder_end_time - grounder_start_time} seconds")
                            print(f"Grounder response: \n{grounder_response_str}")
                            # grounder_response = json.loads(grounder_response_str)
                            grounder_response = parse_json_response(grounder_response_str)
                            bbox = grounder_response["bbox"] if "bbox" in grounder_response else None
                            bbox_2d = grounder_response["bbox_2d"] if "bbox_2d" in grounder_response else None
                            bbox_2d_ = grounder_response.get("bbox-2d", None)
                            bbox_2D = grounder_response.get("bbox_2D", None)
                            if bbox_2D is not None:
                                bbox = bbox_2D
                            if bbox_2d_ is not None:
                                bbox = bbox_2d_
                            if bbox_2d is not None:
                                bbox = bbox_2d

                            # 如果使用 Qwen3 模型，进行坐标转换
                            if use_qwen3:
                                bbox = convert_qwen3_coordinates_to_absolute(bbox, img.width, img.height, is_bbox=True)
                                x1, y1, x2, y2 = bbox
                            else:
                                x1, y1, x2, y2 = [int(coord/factor) for coord in bbox]
                            # raise ValueError("No matching text node found in XML for target_element")
                        x1, y1, x2, y2 = bbox
                        print(f"Matched UI element via XML: text='{target_element}' → bounds={bbox}")
                    except Exception as e:
                        print(f"Failed to find element via XML, falling back to grounder (if needed): {e}")
                        # 可选：保留原 grounder 作为 fallback，或直接报错
                        # 这里我们按你的要求完全替换，所以不 fallback
                        raise e
                else:
                    print(f"Using replayed grounder bbox: {replay_grounder_bbox}")
                    x1, y1, x2, y2 = replay_grounder_bbox

                print(f"Clicking on bbox: [{x1}, {y1}, {x2}, {y2}]")
                print(f"Image size: width={img.width}, height={img.height}")
                print(f"Adjusted bbox: [{x1}, {y1}, {x2}, {y2}]")
                position_x = (x1 + x2) // 2
                position_y = (y1 + y2) // 2
                device.click(position_x, position_y)
                # save action (record index only)
                actions.append({
                    "type": "click",
                    "position_x": position_x,
                    "position_y": position_y,
                    "bounds": [x1, y1, x2, y2],
                    "action_index": image_index
                })

                current_dir = os.getcwd()
                img_path = os.path.join(current_dir, current_image)
                save_path = os.path.join(data_dir, f"{image_index}_highlighted.jpg")
                img = Image.open(img_path)
                draw = ImageDraw.Draw(img)
                # font = ImageFont.truetype("msyh.ttf", 40)
                text = f"CLICK [{position_x}, {position_y}]"
                text = textwrap.fill(text, width=20)
                text_width, text_height = draw.textbbox((0, 0), text)[2:]
                draw.text((img.width / 2 - text_width / 2, 0), text, fill="red")
                img.save(save_path)

                # 拉框
                bounds_path = os.path.join(data_dir, f"{image_index}_bounds.jpg")
                img_bounds = Image.open(save_path)
                draw_bounds = ImageDraw.Draw(img_bounds)
                draw_bounds.rectangle([x1, y1, x2, y2], outline='red', width=5)
                img_bounds.save(bounds_path)

                # # 画点
                # cv2image = cv2.imread(bounds_path)
                # if cv2image is not None:
                #     # 在点击位置画圆点
                #     cv2.circle(cv2image, (position_x, position_y), 15, (0, 255, 0), -1)  # 绿色实心圆
                #     # 保存带点击点的图像
                #     click_point_path = os.path.join(data_dir, f"{image_index}_click_point.jpg")
                #     cv2.imwrite(click_point_path, cv2image)

                # 3. 用 PIL 画绿色实心圆（替代 cv2.circle）
                click_point_path = os.path.join(data_dir, f"{image_index}_click_point.jpg")
                img_click = Image.open(bounds_path)  # 从 bounds 图开始
                draw_click = ImageDraw.Draw(img_click)

                # 定义圆的外接矩形：(x - r, y - r, x + r, y + r)
                radius = 15
                draw_click.ellipse(
                    [position_x - radius, position_y - radius, position_x + radius, position_y + radius],
                    fill=(0, 255, 0),      # 绿色 (R, G, B)
                    outline=None
                )
                img_click.save(click_point_path)

            else:
                coordinates = grounder_response["coordinates"]
                if use_qwen3:
                    coordinates = convert_qwen3_coordinates_to_absolute(coordinates, img.width, img.height, is_bbox=False)
                    x, y = coordinates
                else:
                    x, y = [int(coord / factor) for coord in coordinates]
                device.click(x, y)
                actions.append({
                    "type": "click",
                    "position_x": x,
                    "position_y": y,
                    "action_index": image_index
                })   

                

        elif action == "click_input":
            reasoning = decider_response["reasoning"]
            target_element = decider_response["parameters"]["target_element"]
            text = decider_response["parameters"]["text"]
            bbox = decider_response["parameters"]["bbox"]
            bbox = convert_qwen3_coordinates_to_absolute(bbox, img.width, img.height, is_bbox=True)
            x1, y1, x2, y2 = bbox
            position_x = (x1 + x2) // 2
            position_y = (y1 + y2) // 2

            device.click(position_x, position_y)
            actions.append({
                "type": "click_input",
                "position_x": position_x,
                "position_y": position_y,
                "bounds": [x1, y1, x2, y2],
                "text": f"{text}",
                "action_index": image_index
            })

            device.input(text)

            current_dir = os.getcwd()
            img_path = os.path.join(current_dir, current_image)
            save_path = os.path.join(data_dir, f"{image_index}_highlighted.jpg")
            img = Image.open(img_path)
            draw = ImageDraw.Draw(img)
            # font = ImageFont.truetype("msyh.ttf", 40)
            text = f"CLICK [{position_x}, {position_y}]"
            text = textwrap.fill(text, width=20)
            text_width, text_height = draw.textbbox((0, 0), text)[2:]
            draw.text((img.width / 2 - text_width / 2, 0), text, fill="red")
            img.save(save_path)

            # 拉框
            bounds_path = os.path.join(data_dir, f"{image_index}_bounds.jpg")
            img_bounds = Image.open(save_path)
            draw_bounds = ImageDraw.Draw(img_bounds)
            draw_bounds.rectangle([x1, y1, x2, y2], outline='red', width=5)
            img_bounds.save(bounds_path)

            # # 画点
            # cv2image = cv2.imread(bounds_path)
            # if cv2image is not None:
            #     # 在点击位置画圆点
            #     cv2.circle(cv2image, (position_x, position_y), 15, (0, 255, 0), -1)  # 绿色实心圆
            #     # 保存带点击点的图像
            #     click_point_path = os.path.join(data_dir, f"{image_index}_click_point.jpg")
            #     cv2.imwrite(click_point_path, cv2image)

            # 3. 用 PIL 画绿色实心圆（替代 cv2.circle）
            click_point_path = os.path.join(data_dir, f"{image_index}_click_point.jpg")
            img_click = Image.open(bounds_path)  # 从 bounds 图开始
            draw_click = ImageDraw.Draw(img_click)

            # 定义圆的外接矩形：(x - r, y - r, x + r, y + r)
            radius = 15
            draw_click.ellipse(
                [position_x - radius, position_y - radius, position_x + radius, position_y + radius],
                fill=(0, 255, 0),      # 绿色 (R, G, B)
                outline=None
            )
            img_click.save(click_point_path)
        elif action == "input":
            text = decider_response["parameters"]["text"]
            device.input(text)
            actions.append({
                "type": "input",
                "text": text,
                "action_index": image_index
            })

        elif action == "swipe":
            direction = decider_response["parameters"]["direction"]
            direction = direction.upper()
            
            if direction not in ["UP", "DOWN", "LEFT", "RIGHT"]:
                raise ValueError(f"Invalid swipe direction: {direction}")
            # e2e_v2 mode: try to get start and end coordinates
            if use_e2e_v2:
                start_coords = decider_response["parameters"].get("start_coords")
                end_coords = decider_response["parameters"].get("end_coords")
                
                if start_coords and end_coords:
                    # 进行坐标转换（如果需要）
                    if use_qwen3:
                        start_coords = convert_qwen3_coordinates_to_absolute(start_coords, img.width, img.height, is_bbox=False)
                        end_coords = convert_qwen3_coordinates_to_absolute(end_coords, img.width, img.height, is_bbox=False)
                    
                    start_x, start_y = start_coords
                    end_x, end_y = end_coords
                    
                    logging.info(f"E2E_V2 mode: swipe from [{start_x}, {start_y}] to [{end_x}, {end_y}]")
                    device.swipe_with_coords(start_x, start_y, end_x, end_y)
                    
                    actions.append({
                        "type": "swipe",
                        "press_position_x": start_x,
                        "press_position_y": start_y,
                        "release_position_x": end_x,
                        "release_position_y": end_y,
                        "direction": direction.lower(),
                        "action_index": image_index
                    })
                    create_swipe_visualization(data_dir, image_index, direction.lower(), start_x, start_y, end_x, end_y)
                else:
                    logging.warning("E2E_V2 mode: start_coords or end_coords not found, falling back to direction-based swipe")
                    # 回退到方向based swipe
                    if direction == "DOWN":
                        device.swipe(direction.lower(), 0.4)
                        press_position_x = img.width * 0.3
                        press_position_y = img.height * 0.5
                        release_position_x = img.width * 0.7
                        release_position_y = img.height * 0.5
                    elif direction in ["UP", "LEFT", "RIGHT"]:
                        device.swipe(direction.lower(), 0.4)

                    else:
                        raise ValueError(f"Unknown swipe direction: {direction}")
                    
                    actions.append({
                        "type": "swipe",
                        "press_position_x": None,
                        "press_position_y": None,
                        "release_position_x": None,
                        "release_position_y": None,
                        "direction": direction.lower(),
                        "action_index": image_index
                    })
                    create_swipe_visualization(data_dir, image_index, direction.lower())
            # e2e模式：尝试获取起始和结束坐标
            elif use_e2e:
                start_coords = decider_response["parameters"].get("start_coords")
                end_coords = decider_response["parameters"].get("end_coords")
                
                if start_coords and end_coords:
                    # 进行坐标转换（如果需要）
                    if use_qwen3:
                        start_coords = convert_qwen3_coordinates_to_absolute(start_coords, img.width, img.height, is_bbox=False)
                        end_coords = convert_qwen3_coordinates_to_absolute(end_coords, img.width, img.height, is_bbox=False)
                    
                    start_x, start_y = start_coords
                    end_x, end_y = end_coords
                    
                    logging.info(f"E2E mode: swipe from [{start_x}, {start_y}] to [{end_x}, {end_y}]")
                    device.swipe_with_coords(start_x, start_y, end_x, end_y)
                    
                    actions.append({
                        "type": "swipe",
                        "press_position_x": start_x,
                        "press_position_y": start_y,
                        "release_position_x": end_x,
                        "release_position_y": end_y,
                        "direction": direction.lower(),
                        "action_index": image_index
                    })
                    create_swipe_visualization(data_dir, image_index, direction.lower(), start_x, start_y, end_x, end_y)
                else:
                    logging.warning("E2E mode: start_coords or end_coords not found, falling back to direction-based swipe")
                    # 回退到方向based swipe
                    if direction == "DOWN":
                        device.swipe(direction.lower(), 0.4)
                        press_position_x = img.width * 0.3
                        press_position_y = img.height * 0.5
                        release_position_x = img.width * 0.7
                        release_position_y = img.height * 0.5
                    elif direction in ["UP", "LEFT", "RIGHT"]:
                        device.swipe(direction.lower(), 0.4)

                    else:
                        raise ValueError(f"Unknown swipe direction: {direction}")
                    
                    actions.append({
                        "type": "swipe",
                        "press_position_x": None,
                        "press_position_y": None,
                        "release_position_x": None,
                        "release_position_y": None,
                        "direction": direction.lower(),
                        "action_index": image_index
                    })
                    create_swipe_visualization(data_dir, image_index, direction.lower())
            else:
                if direction in ["DOWN", "UP", "LEFT", "RIGHT"]:
                    device.swipe(direction.lower(), 0.6)
                    actions.append({
                        "type": "swipe",
                        "press_position_x": None,
                        "press_position_y": None,
                        "release_position_x": None,
                        "release_position_y": None,
                        "direction": direction.lower(),
                        "action_index": image_index
                    })
                    
                    # 为滑动创建可视化
                    create_swipe_visualization(data_dir, image_index, direction.lower())
        elif action == "wait":
            print("Waiting for a while...")
            actions.append({
                "type": "wait",
                "action_index": image_index
            })

            tmp = """{"reasoning": "初始界面已经加载完成，请重头继续开始执行任务，忽略已经执行的操作，无需继续wait。"}"""
            history.append(tmp)
        else:
            raise ValueError(f"Unknown action: {action}")
        
        time.sleep(1)
        
    # always restore task description
    task = orig_task
    
    # data = {
    #     "app_name": app,
    #     "task_type": None,
    #     "old_task_description": old_task,
    #     "task_description": task,
    #     "action_count": len(actions),
    #     "actions": actions
    # }

    # with open(os.path.join(data_dir, "actions.json"), "w", encoding='utf-8') as f:
    #     json.dump(data, f, ensure_ascii=False, indent=4)
    # with open(os.path.join(data_dir, "react.json"), "w", encoding='utf-8') as f:
    #     json.dump(reacts, f, ensure_ascii=False, indent=4)
    




def parse_planner_response(response_str: str):

    # 尝试匹配 ```json ... ``` 代码块
    import re
    # 清理开头多余的 {"} 这种错误输出
    response_str = re.sub(r'^\{"\}\s*', '', response_str.strip())
    
    pattern = re.compile(r"```json\s*(.*?)\s*```", re.DOTALL)
    match = pattern.search(response_str)

    json_str = None
    if match:
        json_str = match.group(1)
    else:
        # 如果没有代码块，直接当成 JSON
        json_str = response_str.strip()

    try:
        data = json.loads(json_str)
        return data
    except json.JSONDecodeError as e:
        logging.error(f"解析 JSON 失败: {e}\n内容为:\n{json_str}")
        return None

def get_app_package_name(task_description, use_graphrag=False, device_type="Android",  use_local=False):
    """单阶段：本地检索经验，调用模型完成应用选择和任务描述生成。"""
    current_file_path = Path(__file__).resolve()

    planner_prompt_template = '''
    ## 角色定义
你是一个任务规划专家，负责理解用户意图，选择最合适的应用，并生成一个结构化、可执行的最终任务描述。

## 已知输入
1. 原始用户任务描述："{task_description}"
2. 相关的经验/模板：
```
"{experience_content}"
```

## 可用应用列表
以下是可用的应用及其包名：
- 支付宝: com.eg.android.AlipayGphone
- 微信: com.tencent.mm
- QQ: com.tencent.mobileqq
- 新浪微博: com.sina.weibo
- 饿了么: me.ele
- 美团: com.sankuai.meituan
- bilibili: tv.danmaku.bili
- 爱奇艺: com.qiyi.video
- 腾讯视频: com.tencent.qqlive
- 优酷: com.youku.phone
- 淘宝: com.taobao.taobao
- 京东: com.jingdong.app.mall
- 携程: ctrip.android.view
- 同城: com.tongcheng.android
- 飞猪: com.taobao.trip
- 去哪儿: com.Qunar
- 华住会: com.htinns
- 知乎: com.zhihu.android
- 小红书: com.xingin.xhs
- QQ音乐: com.tencent.qqmusic
- 网易云音乐: com.netease.cloudmusic
- 酷狗音乐: com.kugou.android
- 抖音: com.ss.android.ugc.aweme
- 高德地图: com.autonavi.minimap
- 咸鱼: com.taobao.idlefish
- 华为商城：com.vmall.client
- 华为音乐: com.huawei.music
- 华为视频：com.huawei.himovie
- 华为应用市场：com.huawei.appmarket
- 拼多多：com.xunmeng.pinduoduo
- 大众点评: com.dianping.v1
- 浏览器: com.microsoft.emmx

## 任务要求
1.  **选择应用**：根据用户任务描述，从“可用应用列表”中选择最合适的应用。
2.  **生成最终任务描述**：参考最合适的“相关的经验/模板”，将用户的原始任务描述转化为一个详细、完整、结构化的任务描述。
    - **语义保持一致**：最终描述必须与用户原始意图完全相同。
    - **填充与裁剪**：
        - 如果经验/模板和原始用户任务描述不相关，根据任务对应APP的真实使用方式**简要**完善任务详细步骤
        - 仅填充模板中与用户需求直接相关的步骤,保留原始用户任务描述。
        - 处理“可选”步骤：仅当原始任务描述中显式要求时才填充 “可选”步骤且去除“可选：”标识，原始任务未显示要求则移除对应步骤。
        - 模板里未被原始任务隐含或显式提及的步骤不能增加，多余步骤移除。
        - 若模板中的占位符（如 `{{城市/类型}}`）在用户描述中未提供具体信息，则移除。
    - **自然表达**：输出的描述应符合中文自然语言习惯，避免冗余。

## 输出格式
请严格按照以下JSON格式输出，不要包含任何额外内容或注释：
```json
{{
  "reasoning": "简要说明你为什么选择这个应用，以及你是如何结合用户需求和模板生成最终任务描述的。",
  "app_name": "选择的应用名称",
  "package_name": "所选应用的包名",
  "final_task_description": "最终生成的完整、结构化的任务描述文本。"
}}
```
'''
    
    

    # 构建Prompt
    prompt = planner_prompt_template.format(
        task_description=task_description,
        experience_content= "" # enhanced_context 现在暂时没用经验检索
    )

    if use_local:
        # 本地 LLM 不需要图片，纯文本
        response_str = local_llm_generate(prompt)
    else:
        response_str = planner_client.chat.completions.create(
            model=planner_model,
            messages=[{"role": "user", "content": [{"type": "text", "text": prompt}]}],
        ).choices[0].message.content
    print(f"Planner 响应: \n{response_str}")
    response_json = parse_planner_response(response_str)
    if response_json is None:
        logging.error("无法解析模型响应为 JSON。")
        logging.error(f"原始响应内容: {response_str}")
        raise ValueError("无法解析模型响应为 JSON。")
    app_name = response_json.get("app_name")
    package_name = response_json.get("package_name")
    final_desc = response_json.get("final_task_description", task_description)
    return app_name, package_name, final_desc #, experience_content

# for testing purposes
if __name__ == "__main__":

    # 解析命令行参数
    parser = argparse.ArgumentParser(description="MobiMind Agent")
    parser.add_argument("--service_ip", type=str, default="localhost", help="Ip for the services (default: localhost)")
    parser.add_argument("--decider_port", type=int, default=8000, help="Port for decider service (default: 8000)")
    parser.add_argument("--grounder_port", type=int, default=8001, help="Port for grounder service (default: 8001)")
    parser.add_argument("--planner_port", type=int, default=8002, help="Port for planner service (default: 8002)")
    parser.add_argument("--user_profile", choices=["on", "off"], default="off", help="Enable user profile memory (on/off). Default: off")
    parser.add_argument("--use_graphrag", choices=["on", "off"], default="off", help="Use GraphRAG for user profile preference memory (on/off). Default: off")
    parser.add_argument("--clear_memory", action="store_true", help="Force clear all stored user memories and exit")
    parser.add_argument("--device", type=str, default="Android", choices=["Android", "Harmony"], help="Device type: Android or Harmony (default: Android)")
    parser.add_argument("--device_endpoint", type=str, default=None, help="Device endpoint for connecting with adb/hdc (default: None)")
    parser.add_argument("--use_qwen3", action="store_true", default=True, help="Whether to use Qwen3 model (default: False)")
    parser.add_argument("--use_experience", action="store_true", default=False, help="Whether to use experience (use planner for task rewriting) (default: False)")
    parser.add_argument("--use_experience_rr", action="store_true", default=False, help="Whether to use experience-based record & replay (default: False)")
    parser.add_argument("--data_dir", type=str, default=None, help="Directory to save data (default: ./data relative to script location)")
    parser.add_argument("--task_file", type=str, default=None, help="Path to task.json file (default: ./task.json relative to script location)")
    parser.add_argument("--local_planner", action="store_true", help="Use local LLM via local_llm_generate instead of OpenAI clients")
    parser.add_argument("--local_grounder", action="store_true", help="Use local LLM via local_llm_generate instead of OpenAI clients")
    parser.add_argument("--local_decider", action="store_true", help="Use local LLM via local_llm_generate instead of OpenAI clients")
    parser.add_argument("--e2e", action="store_true", default=False, help="Enable e2e mode: use e2e_qwen3.md as decider prompt and return coordinates directly from decider (default: False)")
    parser.add_argument("--e2e_v2", action="store_true", default=False, help="Enable e2e_v2 mode: use e2e_v2.md as decider prompt with enhanced action space (default: False)")

    #parser.add_argument("--invalidate_singletask_storage", action="store_true", help="Delete utils/experience/singletask_storage before starting tasks")
    args = parser.parse_args()

    use_experience_rr = args.use_experience_rr
    if use_experience_rr and (not args.use_experience):
        logging.warning("use_experience_rr is enabled but use_experience is disabled; disabling use_experience_rr.")
        use_experience_rr = False

    # 使用命令行参数初始化
    enable_user_profile = (args.user_profile == "on")
    use_graphrag = (args.use_graphrag == "on")
    init(
        args.service_ip, 
        args.decider_port, 
        args.grounder_port, 
        args.planner_port,
        enable_user_profile=enable_user_profile, 
        use_graphrag=use_graphrag, 
        use_experience_rr=use_experience_rr,
        use_local_planner=args.local_planner,
        use_local_grounder=args.local_grounder,
        use_local_decider=args.local_decider,
    ) 
    
    device = AndroidDevice(args.device_endpoint)
        
    
    print(f"Connected to device: {args.device}")
    use_qwen3_model = args.use_qwen3
    use_experience = args.use_experience
    current_device_type = args.device  # 保存设备类型用于后续使用
    print(f"Use Qwen3 model: {use_qwen3_model}")
    print(f"Use experience (planner task rewriting): {use_experience}")
    print(f"Device type: {current_device_type}")
    
    print(f"Use E2E mode: {args.e2e}")
    print(f"Use E2E_V2 mode: {args.e2e_v2}")

    # 配置数据保存目录
    if args.data_dir:
        data_base_dir = args.data_dir
        print(f"Using custom data directory: {data_base_dir}")
    else:
        data_base_dir = os.path.join(os.path.dirname(__file__), 'data')
        print(f"Using default data directory: {data_base_dir}")
    
    if not os.path.exists(data_base_dir):
        os.makedirs(data_base_dir)
        print(f"Created data directory: {data_base_dir}")

    # 读取任务列表
    if args.task_file:
        task_json_path = args.task_file
        print(f"Using custom task file: {task_json_path}")
    else:
        task_json_path = os.path.join(os.path.dirname(__file__), "task.json")
    # with open(task_json_path, "r", encoding="utf-8") as f:
    #     task_list = json.load(f)
    task_list = [
    "帮我去淘宝买华为畅享90手机",
    "帮我去淘宝买耐克运动鞋",
    "去知乎搜索如何找女朋友的攻略并点开浏览",
    "去小红书搜索如何找丘成桐的瓜",
    "去小红书搜索如何小米汽车的内幕并浏览",
    "去知乎搜索如何找女朋友的攻略",
    "去小红书搜索如何找女朋友",
    "去淘宝买雨伞",
    "帮我去淘宝买华为Mate80手机",
    "去淘宝买草莓",
    "去饿了么买香蕉",
    "去淘宝买荣耀手机",
    "去淘宝买草莓",
    "去淘宝买香蕉",
    "去淘宝买草莓",
    "去淘宝买一箱橙汁",    
    "去淘宝买张小泉剪刀",
    "去淘宝买围巾",
    "去淘宝买手套",
    "去淘宝买苹果17promax,颜色要白色,内存512G"
    "去淘宝买华为mate80手机",
    "去淘宝买剪刀",
    "去淘宝买雨伞",
    "去淘宝买荣耀手机",
    "去淘宝买华为mate80手机",
    "去淘宝买荣耀手机",
    "去淘宝买苹果17promax,颜色要白色,内存512G"
    "去淘宝买荣耀手机",
    "用携程帮我查询北京的汉庭酒店价格",
    "帮我用携程查询上海的汉庭酒店价格",

]
    
    # print(task_list)
    print("dddd") 
    for task in task_list:
        existing_dirs = [d for d in os.listdir(data_base_dir) if os.path.isdir(os.path.join(data_base_dir, d)) and d.isdigit()]
        if existing_dirs:
            data_index = max(int(d) for d in existing_dirs) + 1
        else:
            data_index = 1
        data_dir = os.path.join(data_base_dir, str(data_index))
        os.makedirs(data_dir)

        task_description = task
        
        # 调用 planner 获取应用名称和包名
        print(f"Calling planner to get app_name and package_name")
        # app_name, package_name, planner_task_description, template = get_app_package_name(task_description, use_graphrag=use_graphrag, device_type=current_device_type)
        app_name, package_name, planner_task_description = get_app_package_name(task_description, use_graphrag=use_graphrag, device_type=current_device_type, use_local=args.local_planner)
        print(f"Planner result - App: {app_name}, Package: {package_name}")

        # 根据 use_experience 参数决定是否使用 planner 改写的任务描述
        if use_experience == True:
            print(f"Using experience: using planner-rewritten task description")
            new_task_description = planner_task_description
            print(f"New task description: {new_task_description}")
        else:
            print(f"Not using experience: using original task description")
            new_task_description = task_description
            
        print(f"Starting task in app: {app_name} (package: {package_name})")
        device.app_start(package_name)
        task_in_app(app_name, task_description, new_task_description, device, data_dir, True, use_qwen3_model, current_device_type, args.e2e, args.e2e_v2)
        print(f"Stopping app: {app_name} (package: {package_name})")
        # device.app_stop(package_name)
        
    # 等待所有偏好提取任务完成
    # if preference_extractor and hasattr(preference_extractor, 'executor'):
    #     print("Waiting for all preference extraction tasks to complete...")
    #     preference_extractor.executor.shutdown(wait=True)
    #     print("All preference extraction tasks completed")
