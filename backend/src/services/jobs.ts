import type { FastifyBaseLogger } from 'fastify';
import type { AppConfig } from '../config.js';
import type { Db, JobType, Prisma } from '../db.js';
import { isUniqueViolation } from '../lib/errors.js';

export interface JobContext {
  db: Db;
  config: AppConfig;
  log: FastifyBaseLogger | Console;
  jobId: string;
  progress: (done: number, total: number, message?: string) => Promise<void>;
  isCancelled: () => Promise<boolean>;
}

export type JobHandler = (payload: Record<string, unknown>, ctx: JobContext) => Promise<unknown>;

/**
 * Einfache, datenbankgestützte Auftragswarteschlange mit begrenzter Parallelität je Typ.
 * Aufträge überleben Neustarts (beim Start werden hängende RUNNING-Aufträge zurückgesetzt).
 */
export class JobQueue {
  private handlers = new Map<JobType, JobHandler>();
  private running = new Map<JobType, number>();
  private timer: NodeJS.Timeout | null = null;
  private stopped = false;
  private active = new Set<Promise<void>>();

  constructor(
    private db: Db,
    private config: AppConfig,
    private log: FastifyBaseLogger | Console,
    private limits: Partial<Record<JobType, number>>,
  ) {}

  register(type: JobType, handler: JobHandler) {
    this.handlers.set(type, handler);
  }

  async enqueue(type: JobType, payload: Record<string, unknown>, opts: { dedupeKey?: string; createdById?: string } = {}) {
    try {
      const job = await this.db.job.create({
        data: { type, payload: payload as Prisma.InputJsonValue, dedupeKey: opts.dedupeKey, createdById: opts.createdById },
      });
      this.kick();
      return job;
    } catch (e) {
      if (opts.dedupeKey && isUniqueViolation(e)) {
        const existing = await this.db.job.findFirst({
          where: { dedupeKey: opts.dedupeKey, status: { in: ['QUEUED', 'RUNNING'] } },
        });
        if (existing) return existing;
      }
      throw e;
    }
  }

  async start() {
    await this.db.job.updateMany({
      where: { status: 'RUNNING' },
      data: { status: 'FAILED', error: 'Durch Serverneustart unterbrochen.', finishedAt: new Date() },
    });
    this.timer = setInterval(() => this.kick(), 3000);
    this.timer.unref();
    this.kick();
  }

  async stop() {
    this.stopped = true;
    if (this.timer) clearInterval(this.timer);
    await Promise.allSettled([...this.active]);
  }

  kick() {
    if (this.stopped) return;
    void this.pump().catch((e) => this.log.error({ err: e }, 'Auftragswarteschlange: Fehler'));
  }

  private async pump() {
    for (const [type] of this.handlers) {
      const limit = this.limits[type] ?? 1;
      while ((this.running.get(type) ?? 0) < limit && !this.stopped) {
        const job = await this.claim(type);
        if (!job) break;
        this.running.set(type, (this.running.get(type) ?? 0) + 1);
        const p = this.execute(job.id, type, job.payload as Record<string, unknown>).finally(() => {
          this.running.set(type, (this.running.get(type) ?? 1) - 1);
          this.active.delete(p);
          this.kick();
        });
        this.active.add(p);
      }
    }
  }

  private async claim(type: JobType) {
    const rows = await this.db.$queryRaw<Array<{ id: string; payload: unknown }>>`
      UPDATE "Job" SET status = 'RUNNING', "startedAt" = now()
      WHERE id = (
        SELECT id FROM "Job" WHERE status = 'QUEUED' AND type = ${type}::"JobType"
        ORDER BY "createdAt" ASC FOR UPDATE SKIP LOCKED LIMIT 1
      )
      RETURNING id, payload`;
    return rows[0] ?? null;
  }

  async runInline(jobId: string, type: JobType, payload: Record<string, unknown>) {
    await this.db.job.update({ where: { id: jobId }, data: { status: 'RUNNING', startedAt: new Date() } });
    await this.execute(jobId, type, payload);
  }

  private async execute(jobId: string, type: JobType, payload: Record<string, unknown>) {
    const handler = this.handlers.get(type);
    if (!handler) return;
    let lastWrite = 0;
    const ctx: JobContext = {
      db: this.db,
      config: this.config,
      log: this.log,
      jobId,
      progress: async (done, total, message) => {
        const now = Date.now();
        if (now - lastWrite < 500 && done < total) return;
        lastWrite = now;
        await this.db.job.update({
          where: { id: jobId },
          data: { done, total, progress: total > 0 ? Math.min(1, done / total) : 0, message },
        });
      },
      isCancelled: async () => {
        const j = await this.db.job.findUnique({ where: { id: jobId }, select: { status: true } });
        return j?.status === 'CANCELLED';
      },
    };
    try {
      const result = await handler(payload, ctx);
      await this.db.job.updateMany({
        where: { id: jobId, status: 'RUNNING' },
        data: { status: 'SUCCEEDED', progress: 1, finishedAt: new Date(), result: (result ?? null) as Prisma.InputJsonValue },
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.log.error({ err: e, jobId, type }, 'Auftrag fehlgeschlagen');
      await this.db.job.updateMany({
        where: { id: jobId, status: 'RUNNING' },
        data: { status: 'FAILED', error: msg.slice(0, 2000), finishedAt: new Date() },
      });
    }
  }
}

export function toJobDto(j: {
  id: string;
  type: string;
  status: string;
  progress: number;
  total: number;
  done: number;
  message: string | null;
  error: string | null;
  result: unknown;
  payload: unknown;
  createdAt: Date;
  startedAt: Date | null;
  finishedAt: Date | null;
}) {
  return {
    id: j.id,
    type: j.type,
    status: j.status,
    progress: j.progress,
    total: j.total,
    done: j.done,
    message: j.message,
    error: j.error,
    result: j.result,
    payload: j.payload,
    createdAt: j.createdAt.toISOString(),
    startedAt: j.startedAt?.toISOString() ?? null,
    finishedAt: j.finishedAt?.toISOString() ?? null,
  };
}
