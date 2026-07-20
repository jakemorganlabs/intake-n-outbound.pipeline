// Re-export hub for outbound adapters and the DLQ writer.

export { dispatchChatAlert, type ChatDispatchInput } from './chat.js';
export { dispatchCRM, type CRMDispatchInput } from './crm.js';
export { dispatchSheet, type SheetDispatchInput } from './sheet.js';
export { writeDeadLetter, type DeadLetterInput, type AdapterResult } from './dlq.js';
export { withRetry, isRetryableHttp, DEFAULT_RETRY } from './retry.js';