import { maskSensitiveSettingValue, SettingsActionKind } from './SettingsCenterTypes';
import {
  SETTINGS_ACTION_GAP,
  SETTINGS_BUTTON_HEIGHT,
  SETTINGS_CARD_BACKGROUND_COLOR,
  SETTINGS_CARD_PADDING,
  SETTINGS_CARD_RADIUS,
  SETTINGS_CONTROL_RADIUS,
  SETTINGS_FIELD_HEIGHT,
  SETTINGS_GROUP_GAP,
  SETTINGS_INPUT_BACKGROUND_COLOR,
  SETTINGS_INPUT_DISABLED_BACKGROUND_COLOR,
  SETTINGS_MUTED_TEXT_COLOR,
  SETTINGS_PANEL_BACKGROUND_COLOR,
  SETTINGS_PANEL_BORDER_COLOR,
  SETTINGS_SECONDARY_TEXT_COLOR,
  SETTINGS_TITLE_COLOR,
  settingsActionColor
} from './SettingsCenterTheme';

// 设置分组卡片负责统一分组标题、间距和卡片外观，业务内容通过 Builder 注入。
@Component
export struct SettingsGroupCard {
  title: string = '';
  subtitle: string = '';
  @BuilderParam contentBuilder: () => void = this.EmptyContent;

  @Builder EmptyContent() {}

  build() {
    Column() {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(SETTINGS_TITLE_COLOR)
        .width('100%')
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(12)
          .fontColor(SETTINGS_SECONDARY_TEXT_COLOR)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      Column() {
        this.contentBuilder()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(SETTINGS_CARD_PADDING)
    .backgroundColor(SETTINGS_CARD_BACKGROUND_COLOR)
    .borderRadius(SETTINGS_CARD_RADIUS)
    .border({ width: 1, color: '#F0F2F7' })
    .margin({ top: 12 })
  }
}

// 设置项输入框只转发用户输入，配置读写由父组件维护。
@Component
export struct SettingInput {
  label: string = '';
  value: string = '';
  placeholder: string = '';
  inputEnabled: boolean = true;
  inputType: InputType = InputType.Normal;
  onValueChange: (value: string) => void = (value: string) => {};
  onInputBlur: () => void = () => {};

  build() {
    Column() {
      Text(this.label)
        .fontSize(13)
        .fontColor(SETTINGS_MUTED_TEXT_COLOR)
        .width('100%')
        .margin({ bottom: 6 })
      TextInput({ placeholder: this.placeholder, text: this.value })
        .type(this.inputType)
        .height(SETTINGS_FIELD_HEIGHT)
        .width('100%')
        .fontSize(13)
        .fontColor(this.inputEnabled ? SETTINGS_TITLE_COLOR : SETTINGS_SECONDARY_TEXT_COLOR)
        .backgroundColor(this.inputEnabled ? SETTINGS_INPUT_BACKGROUND_COLOR : SETTINGS_INPUT_DISABLED_BACKGROUND_COLOR)
        .borderRadius(SETTINGS_CONTROL_RADIUS)
        .padding({ left: 12, right: 12 })
        .enabled(this.inputEnabled)
        .onChange((value: string) => { this.onValueChange(value); })
        .onBlur(() => { this.onInputBlur(); })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 8 })
  }
}

// 敏感输入默认遮罩展示，显示后才允许编辑原始值，避免把遮罩值写回配置。
@Component
export struct SensitiveSettingInput {
  label: string = '';
  value: string = '';
  placeholder: string = '';
  onValueChange: (value: string) => void = (value: string) => {};
  @State private visible: boolean = false;

  build() {
    Column() {
      Text(this.label)
        .fontSize(13)
        .fontColor(SETTINGS_MUTED_TEXT_COLOR)
        .width('100%')
        .margin({ bottom: 6 })
      Row() {
        if (this.visible) {
          TextInput({ placeholder: this.placeholder, text: this.value })
            .height(SETTINGS_FIELD_HEIGHT)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor(SETTINGS_TITLE_COLOR)
            .backgroundColor(SETTINGS_INPUT_BACKGROUND_COLOR)
            .borderRadius(SETTINGS_CONTROL_RADIUS)
            .padding({ left: 12, right: 12 })
            .enabled(true)
            .onChange((value: string) => { this.onValueChange(value); })
        } else {
          TextInput({ placeholder: this.placeholder, text: maskSensitiveSettingValue(this.value) })
            .height(SETTINGS_FIELD_HEIGHT)
            .layoutWeight(1)
            .fontSize(13)
            .fontColor(SETTINGS_SECONDARY_TEXT_COLOR)
            .backgroundColor(SETTINGS_INPUT_DISABLED_BACKGROUND_COLOR)
            .borderRadius(SETTINGS_CONTROL_RADIUS)
            .padding({ left: 12, right: 12 })
            .enabled(false)
        }
        Button(this.visible ? '隐藏' : '显示')
          .height(SETTINGS_FIELD_HEIGHT)
          .width(64)
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor(settingsActionColor(this.visible ? SettingsActionKind.Secondary : SettingsActionKind.Primary))
          .borderRadius(SETTINGS_CONTROL_RADIUS)
          .margin({ left: 8 })
          .onClick(() => { this.visible = !this.visible; })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 8 })
  }
}

// 设置开关行统一复选框、标题和说明布局。
@Component
export struct SettingToggle {
  label: string = '';
  desc: string = '';
  selected: boolean = false;
  onValueChange: (value: boolean) => void = (value: boolean) => {};

  build() {
    Row() {
      Checkbox({ name: this.label, group: 'settingsCenter' })
        .select(this.selected)
        .selectedColor(settingsActionColor(SettingsActionKind.Primary))
        .onChange((value: boolean) => { this.onValueChange(value); })
      Column() {
        Text(this.label)
          .fontSize(14)
          .fontColor(SETTINGS_TITLE_COLOR)
          .width('100%')
        Text(this.desc)
          .fontSize(12)
          .fontColor(SETTINGS_SECONDARY_TEXT_COLOR)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }
}

// 设置操作按钮只负责语义色、禁用态和点击事件转发。
@Component
export struct SettingsActionButton {
  label: string = '';
  kind: SettingsActionKind = SettingsActionKind.Primary;
  actionEnabled: boolean = true;
  onActionClick: () => void = () => {};

  build() {
    Button(this.label)
      .height(SETTINGS_BUTTON_HEIGHT)
      .layoutWeight(1)
      .fontSize(12)
      .fontColor(Color.White)
      .backgroundColor(this.actionEnabled ? settingsActionColor(this.kind) : '#A9B0BE')
      .borderRadius(SETTINGS_CONTROL_RADIUS)
      .enabled(this.actionEnabled)
      .onClick(() => { this.onActionClick(); })
  }
}

// 设置操作行统一横向按钮间距，支持单个按钮自动占满宽度。
@Component
export struct SettingsActionRow {
  @BuilderParam contentBuilder: () => void = this.EmptyContent;

  @Builder EmptyContent() {}

  build() {
    Row({ space: SETTINGS_ACTION_GAP }) {
      this.contentBuilder()
    }
    .width('100%')
    .margin({ top: SETTINGS_ACTION_GAP })
  }
}

// 设置输出面板用于本地/云端日志和配置 JSON 等只读长文本。
@Component
export struct SettingsOutputPanel {
  title: string = '';
  content: string = '';

  build() {
    Column() {
      Text(this.title)
        .fontSize(13)
        .fontColor(SETTINGS_MUTED_TEXT_COLOR)
        .width('100%')
      Scroll() {
        Text(this.content.length > 0 ? this.content : '暂无输出')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor('#333333')
          .width('100%')
          .padding(12)
      }
      .constraintSize({ minHeight: 72, maxHeight: 130 })
      .width('100%')
      .backgroundColor(SETTINGS_PANEL_BACKGROUND_COLOR)
      .borderRadius(SETTINGS_CONTROL_RADIUS)
      .margin({ top: 6 })
      .border({ width: 1, color: SETTINGS_PANEL_BORDER_COLOR })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: SETTINGS_GROUP_GAP })
  }
}
