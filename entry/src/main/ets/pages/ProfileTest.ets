import native from 'libentry.so';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const PROFILE_MODEL_CONFIG_PATH_KEY: string = 'profileModelConfigPath';
const MODEL_SCOPE_ROOT_DIR_NAME: string = 'modelscope';
const LEGACY_MODEL_DIRS: string[] = ['model', 'modelv2', 'modelv3', 'modelv4', 'model_omc'];

@Entry
@Component
struct ProfileTest {
  @State modelConfigPath: string = '';
  @State prompt: string = '你好，简单介绍一下你自己。';
  @State topK: string = '30';
  @State running: boolean = false;
  @State loaded: boolean = false;
  @State result: string = 'Load a model, then run profile.';

  aboutToAppear() {
    const ctx = getContext(this) as common.UIAbilityContext;
    let configured = AppStorage.get(PROFILE_MODEL_CONFIG_PATH_KEY) as string;
    if (this.isConfigUsable(configured)) {
      this.modelConfigPath = configured;
      return;
    }
    this.modelConfigPath = this.defaultModelConfigPath(ctx.filesDir);
    AppStorage.setOrCreate(PROFILE_MODEL_CONFIG_PATH_KEY, this.modelConfigPath);
  }

  private isConfigUsable(path: string): boolean {
    if (path === undefined || path === null || path.length === 0) {
      return false;
    }
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  private hasModelWeightFile(path: string, depth: number = 0): boolean {
    if (depth > 4) {
      return false;
    }
    try {
      let stat = fs.statSync(path);
      if (stat.isFile()) {
        let lower = path.toLowerCase();
        return stat.size > 0 && (lower.endsWith('.mnn') || lower.endsWith('.om') ||
          lower.endsWith('.safetensors') || lower.endsWith('.weight'));
      }
      if (!stat.isDirectory()) {
        return false;
      }
      let children = fs.listFileSync(path);
      for (let child of children) {
        if (this.hasModelWeightFile(path + '/' + child, depth + 1)) {
          return true;
        }
      }
    } catch (e) {
    }
    return false;
  }

  private firstUsableConfigInDir(path: string): string {
    let config = path + '/config.json';
    if (this.isConfigUsable(config) && this.hasModelWeightFile(path)) {
      return config;
    }
    return '';
  }

  private defaultModelConfigPath(filesDir: string): string {
    for (let name of LEGACY_MODEL_DIRS) {
      let config = this.firstUsableConfigInDir(filesDir + '/' + name);
      if (config.length > 0) {
        return config;
      }
    }
    let root = filesDir + '/' + MODEL_SCOPE_ROOT_DIR_NAME;
    try {
      let dirs = fs.listFileSync(root);
      dirs.sort();
      for (let dir of dirs) {
        let config = this.firstUsableConfigInDir(root + '/' + dir);
        if (config.length > 0) {
          return config;
        }
      }
    } catch (e) {
    }
    return filesDir + '/model/config.json';
  }

  private loadModel() {
    if (this.running) {
      return;
    }
    this.running = true;
    this.result = 'Loading model...\n' + this.modelConfigPath;
    native.loadModel(this.modelConfigPath)
      .then((res: string) => {
        this.loaded = true;
        this.result = 'loadModel: ' + res;
        this.running = false;
      })
      .catch((e: Error) => {
        this.loaded = false;
        this.result = 'loadModel error: ' + e.message;
        this.running = false;
      });
  }

  private runProfile() {
    if (this.running) {
      return;
    }
    const k = Math.max(1, parseInt(this.topK || '30') || 30);
    this.running = true;
    this.result = 'Profiling...';
    native.profileGenerate(this.prompt, k)
      .then((res: string) => {
        this.result = res;
        this.running = false;
      })
      .catch((e: Error) => {
        this.result = 'profileGenerate error: ' + e.message;
        this.running = false;
      });
  }

  build() {
    Scroll() {
      Column() {
        Text('LLM Op Profile')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 16, bottom: 6 })

        Text('Profile real generate path with MNN Executor callbacks.')
          .fontSize(13)
          .fontColor('#666666')
          .margin({ bottom: 12 })

        Text('Model config path')
          .fontSize(12)
          .fontColor('#666666')
          .alignSelf(ItemAlign.Start)
          .margin({ left: '5%', bottom: 4 })
        TextInput({ text: this.modelConfigPath, placeholder: '/data/storage/el2/base/files/model/config.json' })
          .width('90%')
          .height(42)
          .backgroundColor('#F0F0F0')
          .borderRadius(8)
          .enabled(!this.running)
          .onChange((value: string) => { this.modelConfigPath = value; })

        Text('Prompt')
          .fontSize(12)
          .fontColor('#666666')
          .alignSelf(ItemAlign.Start)
          .margin({ left: '5%', top: 12, bottom: 4 })
        TextArea({ text: this.prompt, placeholder: 'Prompt for profiling' })
          .width('90%')
          .height(96)
          .backgroundColor('#F0F0F0')
          .borderRadius(8)
          .enabled(!this.running)
          .onChange((value: string) => { this.prompt = value; })

        Row() {
          Text('Top ops')
            .fontSize(12)
            .fontColor('#666666')
          TextInput({ text: this.topK, placeholder: '30' })
            .width(90)
            .height(36)
            .type(InputType.Number)
            .backgroundColor('#F0F0F0')
            .borderRadius(8)
            .enabled(!this.running)
            .onChange((value: string) => { this.topK = value; })
        }
        .width('90%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: 12, bottom: 12 })

        Row() {
          Button(this.running ? 'Running...' : 'Load Model')
            .height(42)
            .layoutWeight(1)
            .fontSize(14)
            .backgroundColor('#1565C0')
            .borderRadius(8)
            .enabled(!this.running)
            .onClick(() => { this.loadModel(); })
          Button(this.running ? 'Running...' : 'Run Profile')
            .height(42)
            .layoutWeight(1)
            .fontSize(14)
            .backgroundColor(this.loaded ? '#2E7D32' : '#78909C')
            .borderRadius(8)
            .margin({ left: 10 })
            .enabled(!this.running)
            .onClick(() => { this.runProfile(); })
        }
        .width('90%')
        .margin({ bottom: 12 })

        Text(this.result)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor('#263238')
          .width('94%')
          .padding(10)
          .backgroundColor('#ECEFF1')
          .borderRadius(6)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }
}
