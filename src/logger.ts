// Structured logger. One JSON line per pipeline execution with per-stage timings.

export interface StageTiming {
  name: string;
  ms: number;
}

export interface ExecutionLog {
  execution_id: string;
  lead_id: string;
  idempotency_key: string;
  stages: StageTiming[];
  model_id?: string;
  token_counts?: { input: number; output: number };
  composite?: number;
  tier?: string;
  status: string;
  repair_used?: boolean;
  degraded?: boolean;
  timestamp: string;
}

export function logExecution(log: ExecutionLog): void {
  process.stdout.write(JSON.stringify(log) + '\n');
}

export function generateExecutionId(): string {
  return `exec_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}