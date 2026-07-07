/**
 * Confidence-aware tier router.
 * Invariant: Tier assignment is a pure function of (composite, confidence, inference_failed).
 * A high composite paired with low model confidence is capped at WARM, never auto-fired to HOT.
 * MANUAL tier is reserved for validation-gate failures (double repair or no output).
 * This module deliberately does NOT adapt thresholds per customer; config-driven only.
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
  // MANUAL override for exhausted inference repair
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
