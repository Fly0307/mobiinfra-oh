import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// Built-in fallbacks mirror the legacy prompt files. Model directories can override
// Agent prompts with standardized markdown files beside config.json.

const PLANNER_ONESHOT_HARMONY_PROMPT: string = `## 角色定义
你是一个任务规划专家，负责理解用户意图，选择最合适的应用，并生成一个结构化、可执行的最终任务描述。

## 已知输入
1. 原始用户任务描述："{task_description}"
2. 相关的经验/模板：
\`\`\`
"{experience_content}"
\`\`\`

## 可用应用列表
以下是可用的应用及其包名：
- IntelliOS: ohos.hongmeng.intellios
- 携程: com.ctrip.harmonynext
- 飞猪: com.fliggy.hmos
- 饿了么: me.ele.eleme
- 知乎: com.zhihu.hmos
- 哔哩哔哩: yylx.danmaku.bili
- 微信: com.tencent.wechat
- 小红书: com.xingin.xhs_hos
- QQ音乐: com.tencent.hm.qqmusic
- 高德地图: com.amap.hmapp
- 淘宝: com.taobao.taobao4hmos
- 微博: com.sina.weibo.stage
- 京东: com.jd.hm.mall
- 飞猪旅行: com.fliggy.hmos
- 天气: com.huawei.hmsapp.totemweather
- 什么值得买: com.smzdm.client.hmos
- 闲鱼: com.taobao.idlefish4ohos
- 慧通差旅: com.smartcom.itravelhm
- PowerAgent: com.example.osagent
- 航旅纵横: com.umetrip.hm.app
- 滴滴出行: com.sdu.didi.hmos.psnger
- 电子邮件: com.huawei.hmos.email
- 图库: com.huawei.hmos.photos
- 日历: com.huawei.hmos.calendar
- 心声社区: com.huawei.it.hmxinsheng
- 信息: com.ohos.mms
- 文件管理: com.huawei.hmos.files
- 运动健康: com.huawei.hmos.health
- 智慧生活: com.huawei.hmos.ailife
- 豆包: com.larus.nova.hm
- WeLink: com.huawei.it.welink
- 设置: com.huawei.hmos.settings
- 懂车帝: com.ss.dcar.auto
- 美团外卖: com.meituan.takeaway
- 大众点评: com.sankuai.dianping
- 美团: com.sankuai.hmeituan
- 浏览器: com.huawei.hmos.browser
- 拼多多: com.xunmeng.pinduoduo.hos
- 同程旅行：com.tongcheng.hmos
- 华为商城: com.huawei.hmos.vmall
- 华为阅读：com.huawei.hmsapp.books
- 支付宝:com.alipay.mobile.client
- 爱奇艺  com.qiyi.video.hmy
- 唯品会:com.vip.hosapp
- 千问:com.aliyun.tongyi4ohos
- 12306:com.chinarailway.ticketingHM
- 去哪旅行:com.qunar.hos
- 钉钉:com.dingtalk.hmos
- 今日头条:com.ss.hm.article.news
- 喜马拉雅:com.ximalaya.ting.xmharmony
- 百度:com.baidu.baiduapp
- 手机管家:com.huawei.hmos.systemmanagerform
- 腾讯视频: com.tencent.videohm
- 交我办: edu.sjtu.jwb

## 任务要求
1.  **选择应用**：根据用户任务描述，从“可用应用列表”中选择最合适的应用。
2.  **生成最终任务描述**：参考最合适的“相关的经验/模板”，将用户的原始任务描述转化为一个详细、完整、结构化的任务描述。
    - **语义保持一致**：最终描述必须与用户原始意图完全相同。
    - **填充与裁剪**：
        - 如果经验/模板和原始用户任务描述不相关，根据任务对应APP的真实使用方式**简要**完善任务详细步骤
        - 仅填充模板中与用户需求直接相关的步骤,保留原始用户任务描述。
        - 处理“可选”步骤：仅当原始任务描述中显式要求时才填充 “可选”步骤且去除“可选：”标识，原始任务未显示要求则移除对应步骤。
        - 模板里未被原始任务隐含或显式提及的步骤不能增加，多余步骤移除。
        - 若模板中的占位符（如 \`{{城市/类型}}\`）在用户描述中未提供具体信息，则移除。
    - **自然表达**：输出的描述应符合中文自然语言习惯，避免冗余。

## 输出格式
请严格按照以下JSON格式输出，不要包含任何额外内容或注释：
\`\`\`json
{
  "reasoning": "简要说明你为什么选择这个应用，以及你是如何结合用户需求和模板生成最终任务描述的。",
  "app_name": "选择的应用名称",
  "package_name": "所选应用的包名",
  "final_task_description": "最终生成的完整、结构化的任务描述文本。"
}
\`\`\``;

const PLANNER_PROMPT: string = `## 角色定义
你是一个任务描述优化专家和智能手机应用选择助手。你需要根据用户的任务描述选择最合适的应用，并同时生成一个更准确、更贴合用户日常使用习惯、语义必须完全相同的任务描述。

## 任务描述
用户想要完成的任务是："{task_description}"

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

## 任务要求
1. 分析任务描述，选择最合适的应用来完成该任务
2. 生成一个更准确、更贴合用户日常使用习惯、语义必须完全相同的任务描述

## 任务描述优化要求
1. **语义必须完全相同** - 任务的目标、操作、内容都不能改变
2. **表达自然** - 改写后的描述应该自然、符合中文日常表达习惯
3. **不改变具体内容** - 搜索关键词、目标对象、操作步骤等具体内容不能改变

## 任务模板列表
下面是系统当前支持的任务模板(模板文件名: 模板简要用途)：
"{task_templates}"

如果任务不需要使用其中任何模板，请返回 \`"template_name": null\`。

## 阶段1输出格式
请严格按照以下JSON格式输出 (仅做应用与模板选择 + 轻度任务描述优化，不做模板填充)：
\`\`\`json
{{
    "reasoning": "分析任务内容，说明为什么选择这个应用最合适，并说明所选模板理由。若不适用模板也需说明",
    "app_name": "选择的应用名称",
    "package_name": "选择的应用包名",
    "template_name": "建议使用的模板文件名或 null",
    "task_description": "优化后的任务描述（保持语义完全一致，仅自然表达，不做模板字段扩展）"
}}
\`\`\`

## 重要规则
1. 只能从上述可用应用列表中选择
2. 必须选择最符合任务需求的应用
3. 如果任务涉及多个可能的应用，选择最主要和最常用的那个
4. 包名必须完全匹配列表中的包名，不能修改
5. 如果选择了模板，不在此阶段展开模板中的各步骤占位符，只进行自然化改写
`;

const E2E_AGENT_PREFIX_PROMPT: string = `<|im_start|>user You are a phone-use AI agent.

### Action Space
Your action space includes:
- Name: click, Parameters: target_element (a high-level description of the UI element to click), bbox (an bounding box of the target element,[x1, y1, x2, y2]).
- Name: swipe, Parameters: direction (one of UP, DOWN, LEFT, RIGHT), start_coords (the starting coordinate [x, y]), end_coords (the ending coordinate [x, y]).
- Name: click_input, Parameters: target_element (a high-level description of the UI element to click), text (the text to input), bbox (an bounding box of the target element,[x1, y1, x2, y2]).
- Name: input, Parameters: text (the text to input).
- Name: wait, Parameters: (no parameters, will wait for 1 second).
- Name: done, Parameters: status (the completion status of the current task, one of \`success\`, \`suspended\` and \`failed\`).

### Response Format
Your output should be a JSON object with the following format:
{"reasoning": "Your reasoning here", "action": "The next action (one of click, click_input, input, swipe, wait, done)", "parameters": {"param1": "value1","param2": "value2", ...}}

### Current Task
{task}

### Constraints
- If the screen has not changed after your last action, do not repeat the exact same action. Try a different method or slightly adjust coordinates.
- If the task is completed, verify the result before outputting 'done'.

`;

const E2E_AGENT_PREFIX_NOREASON_PROMPT: string = `<|im_start|>user You are a phone-use AI agent.

### Action Space
Your action space includes:
- Name: click, Parameters: target_element (a high-level description of the UI element to click), bbox (an bounding box of the target element,[x1, y1, x2, y2]).
- Name: swipe, Parameters: direction (one of UP, DOWN, LEFT, RIGHT), start_coords (the starting coordinate [x, y]), end_coords (the ending coordinate [x, y]).
- Name: click_input, Parameters: target_element (a high-level description of the UI element to click), text (the text to input), bbox (an bounding box of the target element,[x1, y1, x2, y2]).
- Name: input, Parameters: text (the text to input).
- Name: wait, Parameters: (no parameters, will wait for 1 second).
- Name: done, Parameters: status (the completion status of the current task, one of \`success\`, \`suspended\` and \`failed\`).

### Response Format
Your output should be a JSON object with the following format:
{"action": "The next action (one of click, click_input, input, swipe, wait, done)", "parameters": {"param1": "value1","param2": "value2", ...}}

### Constraints
- If the screen has not changed after your last action, do not repeat the exact same action. Try a different method or slightly adjust coordinates.
- If the task is completed, verify the result before outputting 'done'.

### Current Task
{task}

`;

const E2E_AGENT_VARIABLE_PROMPT: string = `### Action History
The sequence of actions you have already taken:
{history}

<image_placeholder>

Please provide the next action based on the screenshot and your action history. You should do careful reasoning before providing the action.'
<|im_end|><|im_start|>assistant`;

const E2E_AGENT_VARIABLE_NOREASON_PROMPT: string = `### Action History
The sequence of actions you have already taken:
{history}

<image_placeholder>


Please provide the next action based on the screenshot and your action history. You should do careful reasoning before providing the action.'

<|im_end|><|im_start|>assistant`;

const E2E_PROMPT: string = `You are a phone-use AI agent.

### Action Space
Your action space includes:
- Name: click, Parameters: target_element (a high-level description of the UI element to click), bbox (an bounding box of the target element,[x1, y1, x2, y2]).
- Name: swipe, Parameters: direction (one of UP, DOWN, LEFT, RIGHT), start_coords (the starting coordinate [x, y]), end_coords (the ending coordinate [x, y]).
- Name: click_input, Parameters: target_element (a high-level description of the UI element to click), text (the text to input), bbox (an bounding box of the target element,[x1, y1, x2, y2]).
- Name: input, Parameters: text (the text to input).
- Name: wait, Parameters: (no parameters, will wait for 1 second).
- Name: done, Parameters: status (the completion status of the current task, one of \`success\`, \`suspended\` and \`failed\`).

### Response Format
Your output should be a JSON object with the following format:
{"reasoning": "Your reasoning here", "action": "The next action (one of click, click_input, input, swipe, wait, done)", "parameters": {"param1": "value1","param2": "value2", ...}}

### Current Task
{task}

### Action History
The sequence of actions you have already taken:
{history}

<image_placeholder>

### Constraints
- If the screen has not changed after your last action, do not repeat the exact same action. Try a different method or slightly adjust coordinates.
- If the task is completed, verify the result before outputting 'done'.
`;

export const AGENT_PROMPT_PREFIX_FILE: string = 'agent_prompt_prefix.md';
export const AGENT_PROMPT_VARIABLE_FILE: string = 'agent_prompt_variable.md';
export const AGENT_PROMPT_PREFIX_NOREASON_FILE: string = 'agent_prompt_prefix_noreason.md';
export const AGENT_PROMPT_VARIABLE_NOREASON_FILE: string = 'agent_prompt_variable_noreason.md';

export class AgentPromptTemplates {
  static loadFromModelDir(modelDir: string, name: string): string {
    let fileName = AgentPromptTemplates.modelPromptFileName(name);
    if (modelDir.length > 0 && fileName.length > 0) {
      let text = AgentPromptTemplates.readModelPrompt(modelDir + '/' + fileName);
      if (text.trim().length > 0) {
        return AgentPromptTemplates.normalize(text);
      }
    }
    return AgentPromptTemplates.load(name);
  }

  static hasModelPrompt(modelDir: string, name: string): boolean {
    let fileName = AgentPromptTemplates.modelPromptFileName(name);
    if (modelDir.length === 0 || fileName.length === 0) {
      return false;
    }
    return AgentPromptTemplates.readModelPrompt(modelDir + '/' + fileName).trim().length > 0;
  }

  static load(name: string): string {
    if (name === 'planner_oneshot_harmony.md') {
      return AgentPromptTemplates.normalize(PLANNER_ONESHOT_HARMONY_PROMPT);
    }
    if (name === 'planner.md') {
      return AgentPromptTemplates.normalize(PLANNER_PROMPT);
    }
    if (name === 'e2e_v2_agent_prefix.md') {
      return AgentPromptTemplates.normalize(E2E_AGENT_PREFIX_PROMPT);
    }
    if (name === 'e2e_v2_agent_prefix_noreason.md') {
      return AgentPromptTemplates.normalize(E2E_AGENT_PREFIX_NOREASON_PROMPT);
    }
    if (name === 'e2e_v2_agent_variable.md') {
      return AgentPromptTemplates.normalize(E2E_AGENT_VARIABLE_PROMPT);
    }
    if (name === 'e2e_v2_agent_variable_noreason.md') {
      return AgentPromptTemplates.normalize(E2E_AGENT_VARIABLE_NOREASON_PROMPT);
    }
    if (name === 'e2e_v2.md') {
      return AgentPromptTemplates.normalize(E2E_PROMPT);
    }
    return '';
  }

  private static modelPromptFileName(name: string): string {
    if (name === 'e2e_v2_agent_prefix.md') {
      return AGENT_PROMPT_PREFIX_FILE;
    }
    if (name === 'e2e_v2_agent_prefix_noreason.md') {
      return AGENT_PROMPT_PREFIX_NOREASON_FILE;
    }
    if (name === 'e2e_v2_agent_variable.md') {
      return AGENT_PROMPT_VARIABLE_FILE;
    }
    if (name === 'e2e_v2_agent_variable_noreason.md') {
      return AGENT_PROMPT_VARIABLE_NOREASON_FILE;
    }
    return '';
  }

  private static readModelPrompt(path: string): string {
    let file: fs.File | null = null;
    try {
      if (!fs.accessSync(path)) {
        return '';
      }
      let stat = fs.statSync(path);
      if (stat.size <= 0) {
        return '';
      }
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      return util.TextDecoder.create('utf-8').decodeWithStream(new Uint8Array(buf));
    } catch (e) {
      return '';
    } finally {
      if (file !== null) {
        try { fs.closeSync(file); } catch (e) {}
      }
    }
  }

  private static normalize(text: string): string {
    return text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }
}
