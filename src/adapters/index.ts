// Adapter index
// Re-exports all outbound adapters and the DLQ writer for a single import site.
// Traces to: §10.9 Outbound Adapters, §10.11 Error Workflow

export { dispatchChatAlert, type ChatDispatchInput } from './chat.js';
export { dispatchCRM, type CRMDispatchInput } from './crm.js';
export { dispatchSheet, type SheetDispatchInput } from './sheet.js';
export { writeDeadLetter, type DeadLetterInput, type AdapterResult } from './dlq.js';
export { withRetry, isRetryableHttp, DEFAULT_RETRY } from './retry.js';
