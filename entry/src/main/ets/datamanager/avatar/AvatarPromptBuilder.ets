import { JSON as ArkJSON } from '@kit.ArkTS';
import { DataManagerStorage } from '../DataManagerStorage';
import {
  DOMAIN_DISPLAY_NAMES,
  ProfileClaim,
  ProfileDomainState,
  ProfileState
} from '../DataManagerTypes';
import { normalizeFreeText } from '../DataManagerUtils';
import {
  AvatarDomainSnapshot,
  AvatarProfileSnapshot
} from './AvatarTypes';

export class AvatarPromptBuilder {
  private storage: DataManagerStorage;

  constructor(storage: DataManagerStorage) {
    this.storage = storage;
  }

  buildSnapshot(profile: ProfileState, completeness: number): AvatarProfileSnapshot {
    let domains: AvatarDomainSnapshot[] = [];
    ['eat', 'wear', 'live', 'travel'].forEach((domain: string) => {
      let doc = profile.domains[domain];
      domains.push(this.domainSnapshot(domain, doc));
    });
    let snapshot: AvatarProfileSnapshot = {
      generated_at: normalizeFreeText(profile.generated_at),
      event_count: profile.event_count,
      completeness: completeness,
      domains: domains,
      prompt_profile_text: this.promptProfileText(domains)
    };
    return snapshot;
  }

  snapshotHash(snapshot: AvatarProfileSnapshot): string {
    return this.storage.sha256Text(ArkJSON.stringify(snapshot));
  }

  buildPrompt(snapshot: AvatarProfileSnapshot): string {
    let lines: string[] = [
      'Create a warm, trustworthy personal digital avatar for a mobile life-assistant home page.',
      'The image should be a clean vertical half-body portrait, simple soft background, no text, no watermark, no logo, suitable for a top home-page avatar area.',
      'Use the following evidence-based lifestyle profile as subtle visual inspiration. Do not infer income, job, health, identity, sensitive demographics, or personality traits not supported by the profile.',
      snapshot.prompt_profile_text,
      'Style: vivid but realistic, friendly, polished, modern, light futuristic assistant feeling, balanced colors, clear face and upper body, high quality.'
    ];
    return lines.join('\n');
  }

  private domainSnapshot(domain: string, doc: ProfileDomainState | undefined): AvatarDomainSnapshot {
    let claims: string[] = [];
    if (doc) {
      (doc.claims || []).forEach((claim: ProfileClaim) => {
        let statement = normalizeFreeText(claim.statement);
        if (statement.length > 0 && claims.length < 3) {
          claims.push(statement);
        }
      });
    }
    return {
      domain: domain,
      display_name: DOMAIN_DISPLAY_NAMES[domain] || domain,
      short_summary: doc ? normalizeFreeText(doc.short_summary) : '',
      summary: doc ? normalizeFreeText(doc.summary) : '',
      claims: claims,
      event_count: doc ? doc.event_count : 0
    };
  }

  private promptProfileText(domains: AvatarDomainSnapshot[]): string {
    let lines: string[] = [];
    domains.forEach((domain: AvatarDomainSnapshot) => {
      let parts: string[] = [];
      if (domain.short_summary.length > 0) {
        parts.push(domain.short_summary);
      }
      if (domain.summary.length > 0) {
        parts.push(domain.summary);
      }
      if (domain.claims.length > 0) {
        parts.push(domain.claims.join('；'));
      }
      lines.push(`${domain.display_name}: ${parts.join('；') || '暂无稳定画像'}`);
    });
    return lines.join('\n');
  }
}
