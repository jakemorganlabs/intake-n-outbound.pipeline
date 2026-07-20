/**
 * Confidence-aware tier router. Tier assignment is a pure function of
 * (composite, confidence, inference_failed). A high composite with low
 * confidence caps at WARM, never auto-fires to HOT. MANUAL is reserved for
 * validation-gate failures (double repair or no output). Thresholds are
 * fixed here, not config-driven.
 */
export type Tier = 'HOT' | 'WARM' | 'COLD' | 'MANUAL';

export interface RoutingResult {
  tier: Tier;
  actions: string[];
}

export interface RouterInput {
  composite: number;
  confidence: number;
  inference_failed?: boolean;
}

export function router(input: RouterInput): RoutingResult {
  // gate exhausted -> MANUAL, never auto-fire
  if (input.inference_failed) {
    return { tier: 'MANUAL', actions: ['dlq', 'alert'] };
  }

  if (input.composite >= 70 && input.confidence >= 0.6) {
    return { tier: 'HOT', actions: ['chat', 'crm'] };
  }

  if (input.composite >= 40) {
    return { tier: 'WARM', actions: ['sheet'] };
  }

  return { tier: 'COLD', actions: ['log'] };
}