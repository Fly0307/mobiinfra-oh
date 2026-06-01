import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AppHeader } from '../../components/AppHeader';
import { WorkflowStorage } from '../../utils/WorkflowStorage';
import { WorkflowFileStats, WorkflowManagedFile, WorkflowTask } from '../../utils/WorkflowTypes';

// 定时任务页：新版不再使用静态样例任务，而是从 App 沙箱中的 workflow JSON
// 加载任务配置，并提供编辑、运行、daily-log/运行文件查看和清理能力。
@Component
export struct TaskPage {
  @Link taskScene: number;
  onRunWorkflow: (task: WorkflowTask) => Promise<void> = async (task: WorkflowTask) => {};
  onOpenCloudLog: () => void = () => {};

  @State tasks: WorkflowTask[] = [];
  @State editorOpen: boolean = false;
  @State editorText: string = '';
  @State editingTaskId: string = '';
  @State runningTaskId: string = '';
  @State fileStatsText: string = '正在统计 workflow 文件...';
  @State fileViewerOpen: boolean = false;
  @State fileViewerTitle: string = '';
  @State fileViewerFiles: WorkflowManagedFile[] = [];
  @State fileViewerSelectedName: string = '';
  @State fileViewerText: string = '';

  private filesDir: string = '';

  aboutToAppear(): void {
    // workflow 配置和运行产物都保存在应用沙箱，进入页面时先定位 filesDir 再加载。
    let ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    this.reloadTasks();
  }

  private reloadTasks(): void {
    // WorkflowStorage 会在无配置时生成默认示例任务，页面只负责刷新状态。
    if (this.filesDir.length === 0) {
      return;
    }
    this.tasks = WorkflowStorage.loadTasks(this.filesDir);
    this.refreshStatsText();
  }

  private refreshStatsText(): void {
    let stats: WorkflowFileStats = WorkflowStorage.getStats(this.filesDir);
    this.fileStatsText = '配置 ' + stats.configCount + ' 个，daily-log ' + stats.dailyLogCount +
      ' 个，运行文件 ' + stats.runCount + ' 个，共 ' + WorkflowStorage.formatSize(stats.totalBytes);
  }

  private sceneTasks(): WorkflowTask[] {
    // 任务按购物/外卖/娱乐/聊天场景分组，taskScene 由 Index.ets 通过 @Link 管理。
    let filtered: WorkflowTask[] = [];
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].sceneId === this.taskScene) {
        filtered.push(this.tasks[i]);
      }
    }
    return filtered;
  }

  private openCreateEditor(): void {
    this.editingTaskId = '';
    this.editorText = WorkflowStorage.defaultWorkflowForScene(this.taskScene);
    this.editorOpen = true;
  }

  private openEditEditor(task: WorkflowTask): void {
    this.editingTaskId = task.id;
    this.editorText = task.workflowJson;
    this.editorOpen = true;
  }

  private saveEditor(): void {
    // 编辑已有任务时保留启停状态和最近运行结果，只替换 workflow JSON 派生出的配置字段。
    try {
      let task = WorkflowStorage.createTaskFromJson(this.filesDir, this.taskScene, this.editorText, this.editingTaskId);
      if (this.editingTaskId.length > 0) {
        let existing = this.findTask(this.editingTaskId);
        if (existing) {
          task.enabled = existing.enabled;
          task.lastStatus = existing.lastStatus;
          task.lastRun = existing.lastRun;
          task.lastMessage = existing.lastMessage;
        }
      }
      this.tasks = WorkflowStorage.upsertTask(this.filesDir, task);
      this.editorOpen = false;
      promptAction.showToast({ message: 'Workflow 配置已保存', duration: 1500 });
      this.refreshStatsText();
    } catch (e) {
      let err = e as Error;
      promptAction.showToast({ message: '保存失败：' + err.message, duration: 2500 });
    }
  }

  private findTask(taskId: string): WorkflowTask | null {
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === taskId) {
        return this.tasks[i];
      }
    }
    return null;
  }

  private setTaskEnabled(task: WorkflowTask, enabled: boolean): void {
    let next: WorkflowTask = task;
    next.enabled = enabled;
    this.tasks = WorkflowStorage.upsertTask(this.filesDir, next);
    this.refreshStatsText();
  }

  private async runTask(task: WorkflowTask): Promise<void> {
    // 真实执行由 Index.ets 注入 onRunWorkflow；本页负责运行态、防重复点击和任务结果刷新。
    if (!task.enabled) {
      promptAction.showToast({ message: '任务已停用，请先打开开关', duration: 1500 });
      return;
    }
    if (this.runningTaskId.length > 0) {
      promptAction.showToast({ message: '已有 workflow 正在执行', duration: 1500 });
      return;
    }
    this.runningTaskId = task.id;
    WorkflowStorage.updateTaskRun(this.filesDir, task.id, '运行中', 'Workflow 正在执行');
    this.reloadTasks();
    try {
      await this.onRunWorkflow(task);
      this.reloadTasks();
    } finally {
      this.runningTaskId = '';
      this.reloadTasks();
    }
  }

  private deleteWorkflowConfigs(): void {
    promptAction.showDialog({
      title: '删除 workflow 配置',
      message: '将删除所有沙箱 workflow 配置，并重新生成默认示例任务。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 1) {
        let count = WorkflowStorage.deleteConfigs(this.filesDir);
        this.reloadTasks();
        promptAction.showToast({ message: '已删除配置项：' + count, duration: 1500 });
      }
    }).catch(() => {});
  }

  private deleteDailyLogs(): void {
    promptAction.showDialog({
      title: '删除 daily-log',
      message: '将删除 workflow 生成的所有 daily-log Markdown 文件。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 1) {
        let count = WorkflowStorage.deleteDailyLogs(this.filesDir);
        this.refreshStatsText();
        promptAction.showToast({ message: '已删除 daily-log 项：' + count, duration: 1500 });
      }
    }).catch(() => {});
  }

  private deleteRunFiles(): void {
    promptAction.showDialog({
      title: '删除运行文件',
      message: '将删除 workflow 生成的所有运行摘要和步骤输出文件。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then((data: promptAction.ShowDialogSuccessResponse) => {
      if (data.index === 1) {
        let count = WorkflowStorage.deleteRunFiles(this.filesDir);
        this.refreshStatsText();
        promptAction.showToast({ message: '已删除运行文件项：' + count, duration: 1500 });
      }
    }).catch(() => {});
  }

  private openConfigFileViewer(): void {
    this.fileViewerTitle = 'Workflow 配置文件';
    this.fileViewerFiles = WorkflowStorage.listConfigFiles(this.filesDir);
    this.fileViewerOpen = true;
    if (this.fileViewerFiles.length > 0) {
      this.openManagedFile(this.fileViewerFiles[0]);
    } else {
      this.fileViewerSelectedName = '';
      this.fileViewerText = '暂无 workflow 配置文件';
    }
  }

  private openDailyLogFileViewer(): void {
    this.fileViewerTitle = 'daily-log 文件';
    this.fileViewerFiles = WorkflowStorage.listDailyLogFiles(this.filesDir);
    this.fileViewerOpen = true;
    if (this.fileViewerFiles.length > 0) {
      this.openManagedFile(this.fileViewerFiles[0]);
    } else {
      this.fileViewerSelectedName = '';
      this.fileViewerText = '暂无 daily-log 文件';
    }
  }

  private openRunFileViewer(): void {
    this.fileViewerTitle = '运行文件';
    this.fileViewerFiles = WorkflowStorage.listRunFiles(this.filesDir);
    this.fileViewerOpen = true;
    if (this.fileViewerFiles.length > 0) {
      this.openManagedFile(this.fileViewerFiles[0]);
    } else {
      this.fileViewerSelectedName = '';
      this.fileViewerText = '暂无运行文件';
    }
  }

  private openManagedFile(file: WorkflowManagedFile): void {
    // 文件查看器只读沙箱内受控目录，避免把任意路径暴露给 UI。
    this.fileViewerSelectedName = file.name;
    try {
      this.fileViewerText = WorkflowStorage.readText(file.path);
    } catch (e) {
      let err = e as Error;
      this.fileViewerText = '读取失败：' + (err.message || String(e));
    }
  }

  @Builder TaskCard(task: WorkflowTask) {
    // 单个 workflow 任务卡片，展示运行状态、来源、最近消息，并提供运行/编辑入口。
    Column() {
      Row() {
        Text(task.icon).fontSize(17).fontColor(task.iconColor).fontWeight(FontWeight.Bold).width(58).height(58).textAlign(TextAlign.Center).backgroundColor(task.enabled ? '#F1F5FF' : '#F4F5F8').borderRadius(16)
        Column() {
          Row() {
            Text(task.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#11182F').layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Row().width(7).height(7).backgroundColor(task.enabled ? '#39BFA3' : '#A8AFBC').borderRadius(4).margin({ left: 8, right: 5 })
            Text(task.enabled ? task.lastStatus : '已暂停').fontSize(12).fontColor(task.enabled ? '#66707E' : '#8E95A3').maxLines(1)
          }.width('100%')
          Text('最近运行：' + task.lastRun).fontSize(12).fontColor('#7B8290').margin({ top: 8 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('来源模块：' + task.source).fontSize(12).fontColor('#7B8290').margin({ top: 4 }).maxLines(1)
          Text(task.lastMessage).fontSize(11).fontColor('#9AA2B1').margin({ top: 4 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 14, right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: task.enabled }).selectedColor('#6B5CFF').width(44).height(26)
          .onChange((value: boolean) => { this.setTaskEnabled(task, value); })
      }.width('100%')
      Row() {
        Button(this.runningTaskId === task.id ? '执行中' : '运行')
          .height(36)
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor(this.runningTaskId === task.id ? '#A9B7E9' : '#765BFF')
          .borderRadius(12)
          .onClick(() => { this.runTask(task); })
        Button('编辑 JSON')
          .height(36)
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor('#EEF4FF')
          .fontColor('#4F68FF')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.openEditEditor(task); })
      }.width('100%').margin({ top: 14 })
    }
    .width('86%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(18)
    .shadow({ radius: 12, color: '#10000000', offsetX: 0, offsetY: 6 })
    .margin({ bottom: 18 })
  }

  @Builder TaskSceneTab(label: string, index: number) {
    // 横向场景筛选器：购物/外卖/娱乐/聊天。
    Text(label)
      .fontSize(14)
      .fontWeight(this.taskScene === index ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.taskScene === index ? Color.White : '#6D7481')
      .height(42)
      .padding({ left: 18, right: 18 })
      .textAlign(TextAlign.Center)
      .backgroundColor(this.taskScene === index ? '#765BFF' : Color.White)
      .borderRadius(21)
      .onClick(() => {
        this.taskScene = index;
      })
  }

  @Builder EditorPanel() {
    // JSON 编辑器直接编辑 workflow 原文，保存时由 WorkflowStorage 做结构校验和归档。
    if (this.editorOpen) {
      Column() {
        Row() {
          Text(this.editingTaskId.length > 0 ? '编辑 Workflow JSON' : '新建 Workflow JSON')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
            .layoutWeight(1)
          Text('关闭')
            .fontSize(13)
            .fontColor('#7B8290')
            .onClick(() => { this.editorOpen = false; })
        }.width('100%')
        TextArea({ placeholder: '请输入 workflow JSON', text: this.editorText })
          .width('100%')
          .height(280)
          .fontSize(12)
          .fontFamily('monospace')
          .backgroundColor('#F7F9FE')
          .borderRadius(14)
          .padding(12)
          .margin({ top: 12 })
          .onChange((val: string) => { this.editorText = val; })
        Row() {
          Button('保存配置')
            .height(42)
            .layoutWeight(1)
            .backgroundColor('#765BFF')
            .borderRadius(12)
            .onClick(() => { this.saveEditor(); })
          Button('查看日志')
            .height(42)
            .layoutWeight(1)
            .backgroundColor('#607D8B')
            .borderRadius(12)
            .margin({ left: 10 })
            .onClick(() => { this.onOpenCloudLog(); })
        }.width('100%').margin({ top: 12 })
      }
      .width('86%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(20)
      .margin({ bottom: 18 })
    }
  }

  @Builder TaskSceneList() {
    // 根据当前场景渲染沙箱中的 workflow 任务；空状态提示用户新建 JSON 配置。
    if (this.sceneTasks().length === 0) {
      Column() {
        Text('当前场景暂无任务').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#11182F')
        Text('点击上方新建任务，使用 JSON 配置 workflow。').fontSize(12).fontColor('#7B8290').margin({ top: 8 })
      }
      .width('86%')
      .padding(22)
      .backgroundColor(Color.White)
      .borderRadius(18)
      .margin({ bottom: 18 })
    } else {
      ForEach(this.sceneTasks(), (task: WorkflowTask) => {
        this.TaskCard(task)
      }, (task: WorkflowTask) => task.id)
    }
  }

  @Builder FileManagerPanel() {
    // workflow 运行会生成配置、daily-log 和步骤输出，这里集中提供查看/清理入口。
    Column() {
      Text('Workflow 文件管理').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#11182F').width('100%')
      Text(this.fileStatsText).fontSize(12).fontColor('#6F7584').margin({ top: 7 }).width('100%')
      Row() {
        Button('删除配置')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#FF6B4A')
          .borderRadius(12)
          .onClick(() => { this.deleteWorkflowConfigs(); })
        Button('删除 daily-log')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#F59E0B')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.deleteDailyLogs(); })
        Button('删除运行文件')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#D97706')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.deleteRunFiles(); })
      }.width('100%').margin({ top: 14 })
      Row() {
        Button('查看配置')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#EEF4FF')
          .fontColor('#4F68FF')
          .borderRadius(12)
          .onClick(() => { this.openConfigFileViewer(); })
        Button('查看 daily-log')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#EFFBF7')
          .fontColor('#279C83')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.openDailyLogFileViewer(); })
        Button('查看运行文件')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#FFF3E8')
          .fontColor('#C76A00')
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => { this.openRunFileViewer(); })
      }.width('100%').margin({ top: 10 })
      Row() {
        Button('刷新')
          .height(40)
          .layoutWeight(1)
          .fontSize(12)
          .backgroundColor('#607D8B')
          .borderRadius(12)
          .onClick(() => { this.reloadTasks(); })
      }.width('100%').margin({ top: 10 })
    }
    .width('86%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ bottom: 18 })
  }

  @Builder FileViewerPanel() {
    // 轻量只读文件查看器，用于快速确认 daily-log 或运行摘要内容。
    if (this.fileViewerOpen) {
      Column() {
        Row() {
          Text(this.fileViewerTitle)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#11182F')
            .layoutWeight(1)
          Text('关闭')
            .fontSize(13)
            .fontColor('#7B8290')
            .onClick(() => { this.fileViewerOpen = false; })
        }.width('100%')
        if (this.fileViewerFiles.length > 0) {
          Scroll() {
            Row() {
              ForEach(this.fileViewerFiles, (file: WorkflowManagedFile) => {
                Button(file.name + ' (' + WorkflowStorage.formatSize(file.size) + ')')
                  .height(34)
                  .fontSize(11)
                  .backgroundColor(this.fileViewerSelectedName === file.name ? '#765BFF' : '#F3F5FA')
                  .fontColor(this.fileViewerSelectedName === file.name ? Color.White : '#4E5666')
                  .borderRadius(11)
                  .margin({ right: 8 })
                  .onClick(() => { this.openManagedFile(file); })
              }, (file: WorkflowManagedFile) => file.path)
            }
          }
          .width('100%')
          .height(42)
          .scrollable(ScrollDirection.Horizontal)
          .margin({ top: 12 })
          Text('当前文件：' + this.fileViewerSelectedName)
            .fontSize(12)
            .fontColor('#6F7584')
            .margin({ top: 10 })
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Scroll() {
            Text(this.fileViewerText)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor('#2F3645')
              .width('100%')
          }
          .width('100%')
          .height(280)
          .padding(12)
          .backgroundColor('#F7F9FE')
          .borderRadius(14)
          .margin({ top: 8 })
        } else {
          Text(this.fileViewerText)
            .fontSize(13)
            .fontColor('#7B8290')
            .margin({ top: 14 })
            .width('100%')
        }
      }
      .width('86%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(20)
      .margin({ bottom: 18 })
    }
  }

  build() {
    Scroll() {
      Column() {
        AppHeader({ title: '定时任务', subtitle: '自定义采集 workflow' })
        Column() {
          Row() {
            Column() {
              Row() {
                Text('新建任务').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#11182F')
                Text('JSON 编排').fontSize(11).fontColor('#765BFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#F0ECFF').borderRadius(10).margin({ left: 10 })
              }
              Text('选择场景，使用 workflow JSON 采集并整理数据').fontSize(12).fontColor('#6F7584').margin({ top: 7 }).maxLines(1)
              Scroll() {
                Row() {
                  Text('购物').fontSize(11).fontColor('#6B5CFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#F8F5FF').borderRadius(10)
                  Text('外卖').fontSize(11).fontColor('#39BFA3').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#EFFBF7').borderRadius(10).margin({ left: 8 })
                  Text('娱乐').fontSize(11).fontColor('#8066FF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#F2EEFF').borderRadius(10).margin({ left: 8 })
                  Text('聊天').fontSize(11).fontColor('#4B8BFF').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#EFF5FF').borderRadius(10).margin({ left: 8 })
                  Text('生活').fontSize(11).fontColor('#D97706').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#FFF7ED').borderRadius(10).margin({ left: 8 })
                  Text('社交').fontSize(11).fontColor('#D9467D').padding({ left: 8, right: 8, top: 4, bottom: 4 }).backgroundColor('#FFF1F5').borderRadius(10).margin({ left: 8 })
                }
              }
              .width('100%')
              .height(28)
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .margin({ top: 12 })
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Column() {
              Text('+').fontSize(28).fontColor(Color.White).fontWeight(FontWeight.Regular)
              Text('创建').fontSize(11).fontColor('#F2EEFF').margin({ top: 1 })
            }
            .justifyContent(FlexAlign.Center)
            .width(58)
            .height(58)
            .backgroundColor('#765BFF')
            .borderRadius(20)
          }.width('100%')
        }
        .width('86%')
        .height(136)
        .padding(22)
        .backgroundColor('#F3EEFF')
        .borderRadius(20)
        .margin({ top: 24 })
        .onClick(() => { this.openCreateEditor(); })

        this.EditorPanel()

        Scroll() {
          Row() {
            this.TaskSceneTab('购物', 0)
            Blank().width(10)
            this.TaskSceneTab('外卖', 1)
            Blank().width(10)
            this.TaskSceneTab('娱乐', 2)
            Blank().width(10)
            this.TaskSceneTab('聊天', 3)
            Blank().width(10)
            this.TaskSceneTab('生活', 4)
            Blank().width(10)
            this.TaskSceneTab('社交', 5)
          }.padding({ left: 24, right: 24 })
        }
        .width('100%')
        .height(46)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .margin({ top: 22, bottom: 18 })

        this.TaskSceneList()
        this.FileManagerPanel()
        this.FileViewerPanel()
        Blank().height(110)
      }.width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F8FF')
  }
}
