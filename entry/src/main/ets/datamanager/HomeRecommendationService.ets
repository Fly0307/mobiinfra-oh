import { DataManagerPaths } from './DataManagerPaths';
import { DataManagerStorage } from './DataManagerStorage';
import { DataPipelineModelClient } from './DataPipelineModelClient';
import { IndexService } from './IndexService';
import { dataManagerError, dataManagerInfo } from './DataManagerLog';
import {
  DataManagerModelConfig,
  DataManagerProgressCallback,
  HomeRecommendationPlannerEvent,
  HomeRecommendationsDocument,
  HomeRecommendationState,
  IndexedEvent,
  createDataManagerProgress
} from './DataManagerTypes';
import {
  isIsoDate,
  normalizeDomains,
  normalizeFreeText,
  nowIsoLocal,
  stableUnique
} from './DataManagerUtils';

export interface HomeRecommendationBuildResult {
  totalEvents: number;
  recommendationCount: number;
  reused: boolean;
}

interface HomeRecommendationPlanningContext {
  plannerEvents: HomeRecommendationPlannerEvent[];
  events: Record<string, IndexedEvent>;
  candidateEventIds: string[];
  today: string;
}

const HOME_TODO_NO_DEADLINE_LIMIT: number = 80;

export function isFutureTodoDeadline(deadline: string, today: string): boolean {
  return isIsoDate(deadline) && isIsoDate(today) && deadline > today;
}

export function recommendationTodoDeadlineMeta(deadline: string): string {
  if (!isIsoDate(deadline)) {
    return '';
  }
  let month = Number(deadline.substring(5, 7));
  let day = Number(deadline.substring(8, 10));
  return `${month}月${day}日截止`;
}

export function emptyHomeRecommendationsDocument(): HomeRecommendationsDocument {
  return {
    generated_at: '',
    input_hash: '',
    total_events: 0,
    recommendations: []
  };
}

export class HomeRecommendationService {
  private paths: DataManagerPaths;
  private storage: DataManagerStorage;
  private modelClient: DataPipelineModelClient;
  private indexService: IndexService;

  constructor(paths: DataManagerPaths, storage: DataManagerStorage, modelClient: DataPipelineModelClient, indexService: IndexService) {
    this.paths = paths;
    this.storage = storage;
    this.modelClient = modelClient;
    this.indexService = indexService;
  }

  async build(modelConfig: DataManagerModelConfig, progress?: DataManagerProgressCallback, forceWhenEmpty: boolean = false): Promise<HomeRecommendationBuildResult> {
    this.paths.ensureBaseDirs();
    this.emitProgress(progress, '索引', '正在生成待办推荐', 0, 100, 99);
    let context = this.planningContext();
    let inputHash = this.inputHash(context, modelConfig);
    let previous = this.loadDocument();
    let previousGenerated = normalizeFreeText(previous.generated_at).length > 0;
    let previousHasInputHash = normalizeFreeText(previous.input_hash).length > 0;
    let previousEmptyButMissing = (previous.recommendations || []).length === 0 && (!previousGenerated || !previousHasInputHash);
    let shouldRebuildEmpty = forceWhenEmpty && context.candidateEventIds.length > 0 && previousEmptyButMissing;
    if (previous.input_hash === inputHash && !shouldRebuildEmpty) {
      dataManagerInfo(`Home recommendations reused: events=${context.candidateEventIds.length}, recommendations=${previous.recommendations.length}`);
      return {
        totalEvents: context.candidateEventIds.length,
        recommendationCount: previous.recommendations.length,
        reused: true
      };
    }
    if (shouldRebuildEmpty) {
      dataManagerInfo(`Home recommendations empty, rebuild requested: events=${context.candidateEventIds.length}`);
    }
    let recommendations: HomeRecommendationState[] = [];
    if (modelConfig.enabled && context.plannerEvents.length > 0) {
      try {
        let planned = await this.modelClient.planHomeRecommendations(context.plannerEvents, context.today, modelConfig);
        recommendations = this.normalizeRecommendations(planned, context);
      } catch (e) {
        let err = e as Error;
        dataManagerError(`Home recommendation planner failed: ${err.message}`);
      }
    }
    let document: HomeRecommendationsDocument = {
      generated_at: nowIsoLocal(),
      input_hash: inputHash,
      total_events: context.candidateEventIds.length,
      recommendations: recommendations
    };
    this.storage.writeJsonAtomic(this.paths.homeRecommendationsPath(), document as Object);
    dataManagerInfo(`Home recommendations built: events=${context.candidateEventIds.length}, recommendations=${recommendations.length}`);
    return {
      totalEvents: context.candidateEventIds.length,
      recommendationCount: recommendations.length,
      reused: false
    };
  }

  loadDocument(): HomeRecommendationsDocument {
    return this.storage.readJson<HomeRecommendationsDocument>(this.paths.homeRecommendationsPath(), emptyHomeRecommendationsDocument());
  }

  private planningContext(): HomeRecommendationPlanningContext {
    let today = this.currentDateKey();
    let todoEvents = this.indexService.loadHomeTodoCandidateEvents(today, HOME_TODO_NO_DEADLINE_LIMIT);
    let candidates: IndexedEvent[] = [];
    Object.keys(todoEvents).forEach((eventId: string) => {
      let event = todoEvents[eventId];
      let todoType = normalizeFreeText(event.todo.type);
      let deadline = normalizeFreeText(event.todo.deadline);
      let hasFutureDeadline = isFutureTodoDeadline(deadline, today);
      let hasNoDeadlineAction = deadline.length === 0 && todoType.length > 0;
      if (hasFutureDeadline || hasNoDeadlineAction) {
        candidates.push(event);
      }
    });
    candidates.sort((left: IndexedEvent, right: IndexedEvent) => {
      let leftDeadline = normalizeFreeText(left.todo.deadline);
      let rightDeadline = normalizeFreeText(right.todo.deadline);
      if (leftDeadline.length > 0 && rightDeadline.length === 0) {
        return -1;
      }
      if (leftDeadline.length === 0 && rightDeadline.length > 0) {
        return 1;
      }
      if (leftDeadline !== rightDeadline) {
        return leftDeadline.localeCompare(rightDeadline);
      }
      if (left.event_date !== right.event_date) {
        return right.event_date.localeCompare(left.event_date);
      }
      return left.event_id.localeCompare(right.event_id);
    });
    let eventMap: Record<string, IndexedEvent> = new Object() as Record<string, IndexedEvent>;
    let plannerEvents: HomeRecommendationPlannerEvent[] = [];
    candidates.forEach((event: IndexedEvent) => {
      eventMap[event.event_id] = event;
      let plannerEvent: HomeRecommendationPlannerEvent = {
        event_id: event.event_id,
        date: event.event_date,
        todo_type: event.todo.type,
        todo_deadline: event.todo.deadline,
        todo_text: event.todo.text,
        summary: normalizeFreeText(event.summary),
        normalized_fact: normalizeFreeText(event.normalized_fact),
        sources: (event.sources || []).slice(),
        domains: (event.domains || []).slice(),
        keywords: (event.keywords || []).slice(),
        image_paths: (event.image_paths || []).slice()
      };
      plannerEvents.push(plannerEvent);
    });
    return {
      plannerEvents: plannerEvents,
      events: eventMap,
      candidateEventIds: candidates.map((event: IndexedEvent): string => event.event_id),
      today: today
    };
  }

  private inputHash(context: HomeRecommendationPlanningContext, modelConfig: DataManagerModelConfig): string {
    let parts: string[] = [
      'home_recommendations_todo',
      context.today,
      modelConfig.enabled ? 'model' : 'disabled',
      modelConfig.enabled ? modelConfig.baseUrl : ''
    ];
    context.plannerEvents.forEach((event: HomeRecommendationPlannerEvent) => {
      parts.push([
        event.event_id,
        event.date,
        event.todo_type,
        event.todo_deadline,
        event.todo_text,
        event.summary,
        event.normalized_fact,
        event.sources.join(','),
        event.domains.join(','),
        event.keywords.join(','),
        event.image_paths.join(',')
      ].join('\u001f'));
    });
    return this.storage.sha256Text(parts.join('\u001e'));
  }

  private currentDateKey(): string {
    return nowIsoLocal().substring(0, 10);
  }

  private normalizeRecommendations(planned: HomeRecommendationState[], context: HomeRecommendationPlanningContext): HomeRecommendationState[] {
    let result: HomeRecommendationState[] = [];
    let allowed: Record<string, boolean> = new Object() as Record<string, boolean>;
    context.candidateEventIds.forEach((id: string) => allowed[id] = true);
    planned.forEach((item: HomeRecommendationState) => {
      let eventIds = stableUnique((item.source_event_ids || []).filter((id: string): boolean => allowed[id] === true));
      if (eventIds.length === 0) {
        return;
      }
      let title = this.recommendationTitle(item, eventIds, context.events);
      if (title.length === 0) {
        return;
      }
      let domains = normalizeDomains([normalizeFreeText(item.domain)]);
      let domain = domains.length > 0 ? domains[0] : this.firstEventDomain(eventIds, context.events);
      let recommendation: HomeRecommendationState = {
        id: 'todo-' + String(result.length + 1),
        tag: this.normalizeRecommendationTag(item.tag, eventIds, context.events),
        title: title,
        desc: this.recommendationDesc(item, eventIds, context.events),
        meta: this.deadlineMeta(eventIds, context.events),
        domain: domain,
        source_event_ids: eventIds
      };
      result.push(recommendation);
    });
    this.appendMissingRecommendations(result, allowed, context);
    return result;
  }

  private recommendationTitle(item: HomeRecommendationState, eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    return normalizeFreeText(item.title) || this.firstTodoText(eventIds, eventMap) || this.firstEventText(eventIds, eventMap);
  }

  private recommendationDesc(item: HomeRecommendationState, eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    return normalizeFreeText(item.desc) || this.firstTodoText(eventIds, eventMap) || this.firstEventText(eventIds, eventMap);
  }

  private appendMissingRecommendations(result: HomeRecommendationState[], allowed: Record<string, boolean>, context: HomeRecommendationPlanningContext): void {
    let covered: Record<string, boolean> = new Object() as Record<string, boolean>;
    result.forEach((item: HomeRecommendationState) => {
      (item.source_event_ids || []).forEach((id: string) => covered[id] = true);
    });
    context.candidateEventIds.forEach((eventId: string) => {
      if (allowed[eventId] !== true || covered[eventId] === true) {
        return;
      }
      let event = context.events[eventId];
      if (!event) {
        return;
      }
      let eventIds = [eventId];
      let todoText = this.firstTodoText(eventIds, context.events);
      let title = todoText || normalizeFreeText(event.summary || event.normalized_fact);
      if (title.length === 0) {
        return;
      }
      let recommendation: HomeRecommendationState = {
        id: 'todo-' + String(result.length + 1),
        tag: this.todoTypeTag(normalizeFreeText(event.todo.type), isIsoDate(event.todo.deadline)),
        title: title,
        desc: todoText || normalizeFreeText(event.normalized_fact || event.summary),
        meta: this.deadlineMeta(eventIds, context.events),
        domain: event.domains.length > 0 ? event.domains[0] : 'other',
        source_event_ids: eventIds
      };
      result.push(recommendation);
    });
  }

  private normalizeRecommendationTag(value: string, eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    let tag = normalizeFreeText(value);
    if (tag.length >= 2 && tag.length <= 6) {
      return tag;
    }
    return this.todoTypeTag(this.firstTodoType(eventIds, eventMap), this.hasDeadline(eventIds, eventMap));
  }

  private firstTodoType(eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    for (let id of eventIds) {
      let event = eventMap[id];
      let type = event ? normalizeFreeText(event.todo.type) : '';
      if (type.length > 0) {
        return type;
      }
    }
    return '';
  }

  private firstTodoText(eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    for (let id of eventIds) {
      let event = eventMap[id];
      let text = event ? normalizeFreeText(event.todo.text) : '';
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  private todoTypeTag(type: string, hasDeadline: boolean): string {
    if (type === 'buy') {
      return '待购买';
    }
    if (type === 'compare') {
      return '待比价';
    }
    if (type === 'pay') {
      return '待付款';
    }
    if (type === 'refund') {
      return '待退款';
    }
    if (type === 'pickup') {
      return '待取件';
    }
    if (type === 'after_sale') {
      return '售后跟进';
    }
    if (type === 'order') {
      return '待下单';
    }
    if (type === 'reorder') {
      return '待复购';
    }
    if (type === 'complain') {
      return '待反馈';
    }
    if (type === 'watch') {
      return '待观看';
    }
    if (type === 'renew') {
      return '待续费';
    }
    if (type === 'book') {
      return '待预订';
    }
    if (type === 'join') {
      return '待参与';
    }
    if (type === 'repair') {
      return '待维修';
    }
    if (type === 'appointment') {
      return '待预约';
    }
    if (type === 'prepare') {
      return '待准备';
    }
    if (type === 'contact') {
      return '待联系';
    }
    if (type === 'gift') {
      return '待送礼';
    }
    if (type === 'plan') {
      return '待安排';
    }
    if (type === 'attend') {
      return '待出席';
    }
    if (type === 'depart') {
      return '待出发';
    }
    if (type === 'check_in') {
      return '待入住';
    }
    if (type === 'reimburse') {
      return '待报销';
    }
    if (type === 'follow_up') {
      return '待跟进';
    }
    if (hasDeadline) {
      return '日程提醒';
    }
    return '待处理';
  }

  private hasDeadline(eventIds: string[], eventMap: Record<string, IndexedEvent>): boolean {
    for (let id of eventIds) {
      let event = eventMap[id];
      if (event && isIsoDate(event.todo.deadline)) {
        return true;
      }
    }
    return false;
  }

  private deadlineMeta(eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    let deadlines: string[] = [];
    eventIds.forEach((id: string) => {
      let event = eventMap[id];
      if (event && isIsoDate(event.todo.deadline)) {
        let deadline = event.todo.deadline;
        deadlines.push(deadline);
      }
    });
    deadlines = stableUnique(deadlines).sort();
    return deadlines.length > 0 ? recommendationTodoDeadlineMeta(deadlines[0]) : '';
  }

  private firstEventText(eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    for (let id of eventIds) {
      let event = eventMap[id];
      if (event) {
        return normalizeFreeText(event.summary || event.normalized_fact);
      }
    }
    return '';
  }

  private firstEventDomain(eventIds: string[], eventMap: Record<string, IndexedEvent>): string {
    for (let id of eventIds) {
      let event = eventMap[id];
      if (event && event.domains.length > 0) {
        return event.domains[0];
      }
    }
    return 'other';
  }

  private emitProgress(progress: DataManagerProgressCallback | undefined, stage: string, message: string, current: number, total: number, percent: number): void {
    if (!progress) {
      return;
    }
    progress(createDataManagerProgress(stage, message, current, total, percent));
  }
}
