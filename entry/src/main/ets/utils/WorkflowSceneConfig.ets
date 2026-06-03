export interface WorkflowSceneConfig {
  sceneId: number;
  tabId: string;
  label: string;
  color: string;
}

const WORKFLOW_SCENES: WorkflowSceneConfig[] = [
  { sceneId: 0, tabId: 'shopping', label: '购物', color: '#765BFF' },
  { sceneId: 1, tabId: 'takeout', label: '外卖', color: '#39BFA3' },
  { sceneId: 2, tabId: 'entertainment', label: '娱乐', color: '#8066FF' },
  { sceneId: 3, tabId: 'chat', label: '聊天', color: '#4B8BFF' },
  { sceneId: 4, tabId: 'life', label: '生活', color: '#D97706' },
  { sceneId: 5, tabId: 'social', label: '社交', color: '#D9467D' },
  { sceneId: 6, tabId: 'travel', label: '差旅', color: '#0EA5E9' }
];

export function workflowSceneConfigs(): WorkflowSceneConfig[] {
  return WORKFLOW_SCENES.slice();
}

export function workflowSceneById(sceneId: number): WorkflowSceneConfig {
  for (let scene of WORKFLOW_SCENES) {
    if (scene.sceneId === sceneId) {
      return scene;
    }
  }
  return WORKFLOW_SCENES[0];
}

export function workflowSceneByIndex(index: number): WorkflowSceneConfig {
  if (index >= 0 && index < WORKFLOW_SCENES.length) {
    return WORKFLOW_SCENES[index];
  }
  return WORKFLOW_SCENES[0];
}

export function workflowSceneLabel(sceneId: number): string {
  return workflowSceneById(sceneId).label;
}
