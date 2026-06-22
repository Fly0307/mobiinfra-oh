import {
  DIGITAL_AVATAR_MESSAGE_HEIGHT,
  DIGITAL_AVATAR_MESSAGE_WIDTH,
  DigitalAvatarSize,
  DigitalAvatarVisualState,
  TEXT_AVATAR_SIZE
} from './DigitalAvatarTypes';

@Component
export struct DigitalAvatarView {
  @Prop @Watch('onAvatarForegroundUriChanged') avatarForegroundUri: string = '';
  @Prop fallbackText: string = '助';
  @Prop fallbackColor: string = '#5968FF';
  @Prop avatarSize: DigitalAvatarSize = 'message';
  @Prop @Watch('onVisualStateChanged') visualState: DigitalAvatarVisualState = 'idle';
  @State imageLoadFailed: boolean = false;
  @State thinkingPulse: boolean = false;
  @State tapScale: number = 1;
  @State tapTranslateY: number = 0;
  @State tapShadowScale: number = 1;
  @State tapShadowOpacity: number = 0.22;
  private thinkingTimerId: number = -1;
  private tapUnlockTimerId: number = -1;
  private tapLocked: boolean = false;

  aboutToAppear(): void {
    this.syncThinkingTimer();
  }

  aboutToDisappear(): void {
    this.clearThinkingTimer();
    this.clearTapUnlockTimer();
    this.tapLocked = false;
  }

  private onAvatarForegroundUriChanged(): void {
    this.imageLoadFailed = false;
    this.syncThinkingTimer();
  }

  private onVisualStateChanged(): void {
    this.syncThinkingTimer();
  }

  private hasForegroundImage(): boolean {
    return this.avatarForegroundUri.length > 0 && !this.imageLoadFailed;
  }

  private containerWidth(): number {
    return this.hasForegroundImage() ? DIGITAL_AVATAR_MESSAGE_WIDTH : TEXT_AVATAR_SIZE;
  }

  private containerHeight(): number {
    return this.hasForegroundImage() ? DIGITAL_AVATAR_MESSAGE_HEIGHT : TEXT_AVATAR_SIZE;
  }

  private foregroundScale(): number {
    let pulseScale: number = this.visualState === 'thinking' && this.thinkingPulse ? 1.04 : 1;
    return this.tapScale * pulseScale;
  }

  private ringScale(): number {
    if (this.visualState !== 'thinking') {
      return 0.92;
    }
    return this.thinkingPulse ? 1.18 : 0.92;
  }

  private ringOpacity(): number {
    if (this.visualState !== 'thinking') {
      return 0.22;
    }
    return this.thinkingPulse ? 0.58 : 0.22;
  }

  private shadowScale(): number {
    let pulseScale: number = this.visualState === 'thinking' && this.thinkingPulse ? 0.92 : 1;
    return this.tapShadowScale * pulseScale;
  }

  // 思考态仅通过脉冲状态驱动 transform/opacity，避免频繁触发布局计算。
  private startThinkingTimer(): void {
    if (this.thinkingTimerId !== -1) {
      return;
    }
    this.thinkingTimerId = setInterval(() => {
      this.thinkingPulse = !this.thinkingPulse;
    }, 800);
  }

  private clearThinkingTimer(): void {
    if (this.thinkingTimerId === -1) {
      return;
    }
    clearInterval(this.thinkingTimerId);
    this.thinkingTimerId = -1;
  }

  private stopThinkingTimer(): void {
    this.clearThinkingTimer();
    this.thinkingPulse = false;
  }

  private clearTapUnlockTimer(): void {
    if (this.tapUnlockTimerId === -1) {
      return;
    }
    clearTimeout(this.tapUnlockTimerId);
    this.tapUnlockTimerId = -1;
  }

  private syncThinkingTimer(): void {
    if (this.visualState === 'thinking' && this.hasForegroundImage()) {
      this.startThinkingTimer();
      return;
    }
    this.stopThinkingTimer();
  }

  // 点击反馈用关键帧同步前景与投影，形成轻量 2.5D 弹跳效果。
  private triggerTapFeedback(): void {
    if (!this.hasForegroundImage() || this.tapLocked) {
      return;
    }
    this.tapLocked = true;
    this.getUIContext()?.keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: 120,
        event: () => {
          this.tapScale = 1.08;
          this.tapTranslateY = -5;
          this.tapShadowScale = 0.78;
          this.tapShadowOpacity = 0.14;
        }
      },
      {
        duration: 120,
        event: () => {
          this.tapScale = 0.98;
          this.tapTranslateY = 1;
          this.tapShadowScale = 1.08;
          this.tapShadowOpacity = 0.24;
        }
      },
      {
        duration: 180,
        event: () => {
          this.tapScale = 1;
          this.tapTranslateY = 0;
          this.tapShadowScale = 1;
          this.tapShadowOpacity = 0.22;
        }
      }
    ]);
    this.clearTapUnlockTimer();
    this.tapUnlockTimerId = setTimeout(() => {
      this.tapLocked = false;
      this.tapUnlockTimerId = -1;
    }, 460);
  }

  @Builder FallbackAvatar() {
    Text(this.fallbackText)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .width(TEXT_AVATAR_SIZE)
      .height(TEXT_AVATAR_SIZE)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.fallbackColor)
      .borderRadius(13);
  }

  @Builder ForegroundAvatar() {
    // 背景光圈、地面投影、透明前景图与高光分层叠加，保持头像尺寸稳定。
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(40)
        .height(40)
        .backgroundColor('#335968FF')
        .borderRadius(20)
        .opacity(this.ringOpacity())
        .scale({ x: this.ringScale(), y: this.ringScale() })
        .animation({ duration: 760, curve: Curve.EaseInOut });

      Row()
        .width(32)
        .height(8)
        .backgroundColor('#35222B46')
        .borderRadius(4)
        .translate({ x: 0, y: 19 })
        .opacity(this.tapShadowOpacity)
        .scale({ x: this.shadowScale(), y: 1 })
        .animation({ duration: 760, curve: Curve.EaseInOut });

      Image(this.avatarForegroundUri)
        .width(DIGITAL_AVATAR_MESSAGE_WIDTH)
        .height(DIGITAL_AVATAR_MESSAGE_HEIGHT)
        .objectFit(ImageFit.Contain)
        .translate({ x: 0, y: this.tapTranslateY })
        .scale({ x: this.foregroundScale(), y: this.foregroundScale() })
        .animation({ duration: 760, curve: Curve.EaseInOut })
        .onError(() => {
          this.imageLoadFailed = true;
          this.stopThinkingTimer();
        });

      Row()
        .width(10)
        .height(34)
        .backgroundColor('#33FFFFFF')
        .borderRadius(5)
        .translate({ x: 10, y: -2 })
        .opacity(0.32);
    }
    .width(DIGITAL_AVATAR_MESSAGE_WIDTH)
    .height(DIGITAL_AVATAR_MESSAGE_HEIGHT)
    .onClick(() => {
      this.triggerTapFeedback();
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.hasForegroundImage()) {
        this.ForegroundAvatar();
      } else {
        this.FallbackAvatar();
      }
    }
    .width(this.containerWidth())
    .height(this.containerHeight());
  }
}
