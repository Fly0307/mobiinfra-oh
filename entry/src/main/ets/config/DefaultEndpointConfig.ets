export interface EndpointDefaultConfig {
  /**
   * 手机无线 HDC 调试目标，格式为 ip:port。
   */
  wirelessHdcTarget: string;
  /**
   * 模型下载服务地址，格式为 http://ip:port。
   */
  modelDownloadServerUrl: string;
  /**
   * PC 端 HDC bridge 服务地址，格式为 http://ip:port。
   */
  hdcServerUrl: string;
  /**
   * 云端 planner 服务地址，格式为 http://ip:port。
   */
  cloudPlannerBaseUrl: string;
  /**
   * 云端 decider 服务地址，格式为 http://ip:port。
   */
  cloudDeciderBaseUrl: string;
  cloudApiKey: string;
  /**
   * 留空时不向 decider 请求传 model 字段。
   */
  cloudDeciderModel: string;
  /**
   * App 内部给 PC 控制端连接的 TCP 端口。
   */
  agentRouterPort: number;
}

export interface LegacyEndpointConfig {
  wirelessHdcTargets: string[];
  modelDownloadServerUrls: string[];
  hdcServerUrls: string[];
  cloudPlannerBaseUrls: string[];
  cloudDeciderBaseUrls: string[];
  cloudApiKeys: string[];
  cloudDeciderModels: string[];
}

export const DEFAULT_ENDPOINT_CONFIG: EndpointDefaultConfig = {
  wirelessHdcTarget: '192.168.137.205:33117',
  modelDownloadServerUrl: 'http://166.111.53.96:9123',
  hdcServerUrl: 'http://192.168.137.1:9124',
  cloudPlannerBaseUrl: 'http://166.111.53.96:7003',
  cloudDeciderBaseUrl: 'http://166.111.53.96:7003',
  cloudApiKey: 'mobiagent-key',
  cloudDeciderModel: '',
  agentRouterPort: 9126
};

export const LEGACY_ENDPOINT_CONFIG: LegacyEndpointConfig = {
  wirelessHdcTargets: [
    '192.168.137.195:33117',
    '101.5.155.98:35729',
    '192.168.137.172:35963',
    '192.168.137.55:35963',
    '192.168.137.55:33117'
  ],
  modelDownloadServerUrls: [
    'http://166.111.53.96:9123'
  ],
  hdcServerUrls: [
    'http://192.168.137.1:9124',
    'http://166.111.53.96:9124'
  ],
  cloudPlannerBaseUrls: [
    'http://166.111.53.96:7003',
    'http://166.111.53.96:8001'
  ],
  cloudDeciderBaseUrls: [
    'http://166.111.53.96:7003',
    'http://166.111.53.96:8000'
  ],
  cloudApiKeys: [
    'mobiagent-key'
  ],
  cloudDeciderModels: [
    'decider',
    'decider_model'
  ]
};
