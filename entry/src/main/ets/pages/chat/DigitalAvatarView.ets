import {
  digitalAvatarContainerHeight,
  digitalAvatarContainerWidth,
  digitalAvatarFallbackSize,
  digitalAvatarFrameHeight,
  digitalAvatarFrameWidth,
  DigitalAvatarSize,
  DigitalAvatarVisualState
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
  @State tapHaloScale: number = 0.86;
  @State tapHaloOpacity: number = 0;
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

  private hasAvatarFrame(): boolean {
    return this.avatarForegroundUri.length > 0;
  }

  private containerWidth(): number {
    return digitalAvatarContainerWidth(this.avatarSize, this.hasAvatarFrame());
  }

  private containerHeight(): number {
    return digitalAvatarContainerHeight(this.avatarSize, this.hasAvatarFrame());
  }

  private frameWidth(): number {
    return digitalAvatarFrameWidth(this.avatarSize);
  }

  private frameHeight(): number {
    return digitalAvatarFrameHeight(this.avatarSize);
  }

  private fallbackSize(): number {
    return digitalAvatarFallbackSize(this.avatarSize);
  }

  private fallbackFontSize(): number {
    return this.avatarSize === 'hero' ? 20 : 13;
  }

  private fallbackRadius(): number {
    return this.avatarSize === 'hero' ? 18 : 13;
  }

  private ringSize(): number {
    return this.avatarSize === 'hero' ? 104 : 40;
  }

  private ringRadius(): number {
    return this.avatarSize === 'hero' ? 52 : 20;
  }

  private shadowWidth(): number {
    return this.avatarSize === 'hero' ? 92 : 32;
  }

  private shadowHeight(): number {
    return this.avatarSize === 'hero' ? 16 : 8;
  }

  private shadowRadius(): number {
    return this.avatarSize === 'hero' ? 8 : 4;
  }

  private shadowTranslateY(): number {
    return this.avatarSize === 'hero' ? 57 : 19;
  }

  private highlightWidth(): number {
    return this.avatarSize === 'hero' ? 22 : 10;
  }

  private highlightHeight(): number {
    return this.avatarSize === 'hero' ? 86 : 34;
  }

  private highlightRadius(): number {
    return this.avatarSize === 'hero' ? 11 : 5;
  }

  private highlightTranslateX(): number {
    return this.avatarSize === 'hero' ? 28 : 10;
  }

  private highlightTranslateY(): number {
    return this.avatarSize === 'hero' ? -12 : -2;
  }

  private tapLiftY(): number {
    return this.avatarSize === 'hero' ? -12 : -7;
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
    if (!this.hasAvatarFrame() && this.fallbackText.length === 0) {
      return;
    }
    if (this.tapLocked) {
      return;
    }
    this.tapLocked = true;
    this.getUIContext()?.keyframeAnimateTo({ iterations: 1 }, [
      {
        duration: 120,
        event: () => {
          this.tapScale = 1.14;
          this.tapTranslateY = this.tapLiftY();
          this.tapShadowScale = 0.78;
          this.tapShadowOpacity = 0.14;
          this.tapHaloScale = 1.24;
          this.tapHaloOpacity = 0.46;
        }
      },
      {
        duration: 120,
        event: () => {
          this.tapScale = 0.98;
          this.tapTranslateY = 1;
          this.tapShadowScale = 1.08;
          this.tapShadowOpacity = 0.24;
          this.tapHaloScale = 1.08;
          this.tapHaloOpacity = 0.22;
        }
      },
      {
        duration: 180,
        event: () => {
          this.tapScale = 1;
          this.tapTranslateY = 0;
          this.tapShadowScale = 1;
          this.tapShadowOpacity = 0.22;
          this.tapHaloScale = 1.42;
          this.tapHaloOpacity = 0;
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
      .fontSize(this.fallbackFontSize())
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .width(this.fallbackSize())
      .height(this.fallbackSize())
      .textAlign(TextAlign.Center)
      .backgroundColor(this.fallbackColor)
      .borderRadius(this.fallbackRadius())
      .translate({ x: 0, y: this.tapTranslateY })
      .scale({ x: this.tapScale, y: this.tapScale })
      .animation({ duration: 180, curve: Curve.EaseOut });
  }

  @Builder ForegroundAvatar() {
    // 背景光圈、地面投影、透明前景图与高光分层叠加，保持头像尺寸稳定。
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(this.ringSize())
        .height(this.ringSize())
        .backgroundColor('#445968FF')
        .borderRadius(this.ringRadius())
        .opacity(this.tapHaloOpacity)
        .scale({ x: this.tapHaloScale, y: this.tapHaloScale })
        .animation({ duration: 180, curve: Curve.EaseOut });

      Row()
        .width(this.ringSize())
        .height(this.ringSize())
        .backgroundColor('#335968FF')
        .borderRadius(this.ringRadius())
        .opacity(this.ringOpacity())
        .scale({ x: this.ringScale(), y: this.ringScale() })
        .animation({ duration: 760, curve: Curve.EaseInOut });

      Row()
        .width(this.shadowWidth())
        .height(this.shadowHeight())
        .backgroundColor('#35222B46')
        .borderRadius(this.shadowRadius())
        .translate({ x: 0, y: this.shadowTranslateY() })
        .opacity(this.tapShadowOpacity)
        .scale({ x: this.shadowScale(), y: 1 })
        .animation({ duration: 760, curve: Curve.EaseInOut });

      Image(this.avatarForegroundUri)
        .width(this.frameWidth())
        .height(this.frameHeight())
        .objectFit(ImageFit.Contain)
        .translate({ x: 0, y: this.tapTranslateY })
        .scale({ x: this.foregroundScale(), y: this.foregroundScale() })
        .animation({ duration: 760, curve: Curve.EaseInOut })
        .onError(() => {
          this.imageLoadFailed = true;
          this.stopThinkingTimer();
        });

      Row()
        .width(this.highlightWidth())
        .height(this.highlightHeight())
        .backgroundColor('#33FFFFFF')
        .borderRadius(this.highlightRadius())
        .translate({ x: this.highlightTranslateX(), y: this.highlightTranslateY() })
        .opacity(0.32);
    }
    .width(this.frameWidth())
    .height(this.frameHeight());
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
    .height(this.containerHeight())
    .onClick(() => {
      this.triggerTapFeedback();
    });
  }
}
