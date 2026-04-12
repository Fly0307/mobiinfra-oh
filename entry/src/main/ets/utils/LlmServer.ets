import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';

export class LlmServer {
  private server: socket.TCPSocketServer | null = null;
  private isRunning: boolean = false;
  public currentTask: string = "";

  start(port: number, filesDir: string, mnnllm: Record<string, Function>, onLog: (msg: string) => void, onRequireApproval?: (response: string) => Promise<boolean>) {
    if (this.isRunning) {
      onLog("服务已经运行中");
      return;
    }

    this.server = socket.constructTCPSocketServerInstance();
    let ipAddress: socket.NetAddress = { address: '0.0.0.0', port: port, family: 1 };
    
    this.server.listen(ipAddress, (err) => {
      if (err) {
        onLog(`【ERROR】服务启动失败，请检查端口是否被占用: ${JSON.stringify(err)}`);
        return;
      }
      this.isRunning = true;
      onLog(`====== PC 投屏控制端后台开启 ======\n监听端口：TCP ${port}，可使用 hdc fport 打通！\n现在可以在 APP 端输入任务并开始了。`);
    });

    this.server.on('connect', (client: socket.TCPSocketConnection) => {
      let bufferStr = "";
      
      client.on('message', async (data) => {
        let textDecoder = util.TextDecoder.create('utf-8');
        let str = textDecoder.decodeWithStream(new Uint8Array(data.message));
        bufferStr += str;
        
        // 我们以 <<EOF>> 作为通信帧截断符
        let eofIdx = bufferStr.indexOf("<<EOF>>");
        if (eofIdx !== -1) {
          let payload = bufferStr.substring(0, eofIdx);
          bufferStr = bufferStr.substring(eofIdx + 7);
          
          try {
            let req: Record<string, Object> = JSON.parse(payload);
            let reqType = req['type'] as string;

            if (reqType === "poll") {
              // PC 端轮询获取任务
              client.send({ data: JSON.stringify({ task: this.currentTask }) + "<<EOF>>" });
              return;
            } else if (reqType === "clear") {
               // PC 端要求清除任务（达到步数或手动终止）
               this.currentTask = "";
               if (mnnllm && typeof mnnllm['reset'] === 'function') {
                 mnnllm['reset']();
               }
               onLog(`>> [任务被PC端终止] 当前任务已清空，并已重置大模型上下文。`);
               client.send({ data: `{"status": "ok"}` + "<<EOF>>" });
               return;
            } else if (reqType === "action") {
              // PC 端发来截图，要求推理
              let prompt = req['prompt'] as string;
              if (req['image_b64']) {
                let imgPath = filesDir + '/agent_snapshot.jpg';
                let base64Helper = new util.Base64Helper();
                let imgBuffer = base64Helper.decodeSync(req['image_b64'] as string);
                let file = fs.openSync(imgPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
                fs.writeSync(file.fd, imgBuffer.buffer);
                fs.closeSync(file);
                
                let w = req['width'];
                let h = req['height'];
                onLog(`>> [Debug] req['width']: ${w}, req['height']: ${h}`);
                prompt = `<img>${imgPath}<hw>${h},${w}</hw></img>\n` + prompt;
              }
              
              onLog(`>> [接收到 PC 发来的推理请求(含图片)]\n原始文本任务: ${req['prompt'] as string}\n构造给大模型的完整 Prompt:\n${prompt}`);
              let response = await mnnllm.chat(prompt) as string;
              onLog(`>> [模型推理返回结果]: \n${response}`);

              if (onRequireApproval) {
                 onLog(`>> [等待用户确认] 弹窗已展现...`);
                 let isApproved = await onRequireApproval(response);
                 if (!isApproved) {
                    onLog(`>> [用户拒绝] 已丢弃该动作并通知 PC 端终止。`);
                    this.currentTask = "";
                    client.send({ data: `{"action": "error", "reason": "User rejected"}` + "<<EOF>>" });
                    return;
                 }
                 onLog(`>> [用户同意] 动作已放行。`);
              }

              // 简单的正则检查，如果是 done 或者 stop，就自动清空任务停止
              if (response.indexOf('"done"') !== -1 || response.indexOf('"stop"') !== -1) {
                 this.currentTask = "";
                 onLog(`>> [任务完成] Agent 停止。`);
              }
              
              onLog(`>> [下发至 PC]: \n${response}`);
              client.send({ data: response + "<<EOF>>" });
            }
          } catch(e) {
            onLog(`【ERROR】处理请求失败: ${e}`);
            client.send({ data: `{"error": "Failed"}` + "<<EOF>>" });
          }
        }
      });
    });
  }
}
