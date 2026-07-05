import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Input, OnInit, OnChanges, SimpleChanges } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { ApiService } from '../services/api.service';
import { AuthService } from '../services/auth.service';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';
import { Dialog } from '@angular/cdk/dialog';
import { AccessLevel, Membership, PickableUser } from '../models';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

@Component({
  selector: 'app-members-panel',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective,
    TranslatePipe,
  ],
  template: `
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">group</app-icon>
        <p class="cg-panel-title">{{ 'members.title' | translate }}</p>
        <span class="spacer"></span>
        <button *ngIf="canManage" class="cg-btn" (click)="showAdd = !showAdd" style="font-size:13px;">
          <app-icon>person_add</app-icon> {{ 'members.add' | translate }}
        </button>
      </div>

      <!-- Add member form -->
      <div *ngIf="showAdd && canManage" class="add-form">
        <div class="cg-field" style="flex:1;">
          <label class="cg-label">{{ 'members.user' | translate }}</label>
          <select class="cg-select" [(ngModel)]="addUserId">
            <option [ngValue]="null" disabled>—</option>
            <option *ngFor="let u of availableUsers" [ngValue]="u.id">
              {{ u.name }} ({{ u.email }})
            </option>
          </select>
        </div>
        <div class="cg-field" style="width:180px;">
          <label class="cg-label">{{ 'members.level' | translate }}</label>
          <select class="cg-select" [(ngModel)]="addLevel">
            <option [ngValue]="null" disabled>—</option>
            <option *ngFor="let l of levels" [ngValue]="l.value">
              {{ l.name }}
            </option>
          </select>
        </div>
        <button class="cg-btn cg-btn-primary" (click)="addMember()" [disabled]="!addUserId || !addLevel">
          {{ 'common.save' | translate }}
        </button>
        <button class="cg-btn" (click)="showAdd = false; addUserId = null; addLevel = null">
          {{ 'common.cancel' | translate }}
        </button>
      </div>

      <div class="cg-panel-body">
        <div *ngIf="members.length === 0" class="cg-empty">{{ 'members.empty' | translate }}</div>
        <div *ngFor="let m of members" class="list-row" style="cursor:default;">
          <app-icon style="opacity:.5;flex-shrink:0;">person</app-icon>
          <div class="row-main">
            <span class="row-title">{{ m.user?.name ?? ('members.unknownUser' | translate:{ id: m.userId }) }}</span>
            <span class="row-desc">{{ m.user?.email }}</span>
          </div>
          <span class="level-badge" [class]="levelClass(m.accessLevel)">{{ m.levelName }}</span>
          <button *ngIf="canManage" class="cg-icon-btn" (click)="removeMember(m)"
            [cgTooltip]="'members.removeTooltip' | translate" style="width:32px;height:32px;">
            <app-icon style="font-size:16px;width:16px;height:16px;">person_remove</app-icon>
          </button>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .add-form {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px 18px;
      border-bottom: 1px solid var(--cg-border);
      flex-wrap: wrap;
    }
    .spacer { flex: 1 1 auto; }
    .level-badge {
      font-size: 11px;
      font-weight: 600;
      padding: 2px 10px;
      border-radius: 12px;
      white-space: nowrap;
      &.l10 { background: #37415133; color: #9ca3af; }
      &.l20 { background: #065f4633; color: #34d399; }
      &.l30 { background: #1e3a8a33; color: #60a5fa; }
      &.l40 { background: #4c1d9533; color: #a78bfa; }
      &.l50 { background: #7f1d1d33; color: #f87171; }
    }
  `],
})
export class MembersPanelComponent implements OnInit, OnChanges {
  @Input() subjectType!: 'group' | 'project' | 'task';
  @Input() subjectId!: number;

  members: Membership[] = [];
  availableUsers: PickableUser[] = [];
  allLevels: AccessLevel[] = [];
  myLevel = 0;
  showAdd = false;
  addUserId: number | null = null;
  addLevel: number | null = null;

  // A member grant maxes out at Navigator (40); Cartographer (50) is the global
  // admin flag, managed separately in user administration.
  get levels(): AccessLevel[] {
    const cap = this.auth.isAdmin ? 40 : this.myLevel;
    return this.allLevels.filter(l => l.value <= 40 && l.value <= cap);
  }

  // Navigator (40) or a global admin can manage members of this resource.
  get canManage(): boolean {
    return this.auth.isAdmin || this.myLevel >= 40;
  }

  constructor(private api: ApiService, public auth: AuthService, private dialog: Dialog, private i18n: TranslationService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    this.load();
    this.api.listPickableUsers().subscribe(u => { this.availableUsers = u; this.cdr.markForCheck(); });
    this.api.getAccessLevels().subscribe(l => { this.allLevels = l; this.cdr.markForCheck(); });
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['subjectId'] && !changes['subjectId'].firstChange) {
      this.members = [];
      this.myLevel = 0;
      this.showAdd = false;
      this.load();
    }
  }

  load(): void {
    const obs = this.subjectType === 'group'
      ? this.api.getGroupMembers(this.subjectId)
      : this.subjectType === 'project'
        ? this.api.getProjectMembers(this.subjectId)
        : this.api.getTaskMembers(this.subjectId);
    obs.subscribe(res => { this.members = res.members; this.myLevel = res.myLevel; this.cdr.markForCheck(); });
  }

  addMember(): void {
    if (!this.addUserId || !this.addLevel) return;
    const obs = this.subjectType === 'group'
      ? this.api.addGroupMember(this.subjectId, { userId: this.addUserId, accessLevel: this.addLevel })
      : this.subjectType === 'project'
        ? this.api.addProjectMember(this.subjectId, { userId: this.addUserId, accessLevel: this.addLevel })
        : this.api.addTaskMember(this.subjectId, { userId: this.addUserId, accessLevel: this.addLevel });
    obs.subscribe(() => { this.load(); this.showAdd = false; this.addUserId = null; this.addLevel = null; this.cdr.markForCheck(); });
  }

  removeMember(m: Membership): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: m.user?.name ?? String(m.userId), kind: this.i18n.t('common.member') }, width: '460px',
    });
    ref.closed.subscribe(ok => {
      if (!ok) return;
      const obs = this.subjectType === 'group'
        ? this.api.removeGroupMember(this.subjectId, m.userId)
        : this.subjectType === 'project'
          ? this.api.removeProjectMember(this.subjectId, m.userId)
          : this.api.removeTaskMember(this.subjectId, m.userId);
      obs.subscribe(() => this.load());
    });
  }

  levelClass(level: number): string {
    return 'l' + level;
  }
}
