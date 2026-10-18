import { randomUUID } from 'node:crypto';
import { SignJWT } from 'jose';

/**
 * Fire-and-forget reports of room and round events to the account API.
 * Never awaited by the simulation: a slow or offline API cannot delay a tick.
 * Disabled when API_URL is unset (tests, local runs without the API).
 */
export const processId = randomUUID().slice(0, 8);

export type IngestEvent = {
  type: 'room' | 'closed' | 'match' | 'use';
  room_id: string;
  phase?: string;
  players?: { account_id: string; name: string }[];
  max_players?: number;
  map_name?: string;
  map_id?: string;
  round?: number;
  duration_ms?: number;
  practice?: boolean;
  account_id?: string;
  item_id?: string;
  use_id?: string;
  results?: {
    account_id: string | null;
    is_bot?: boolean;
    name: string;
    placement: number;
    kills: number;
    bombs: number;
    survived_ms: number;
    winner: boolean;
  }[];
};

const RETRIES = [1000, 5000, 20000];

async function token(): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer('suni-arena')
    .setAudience('suni-ingest')
    .setIssuedAt()
    .setExpirationTime('1m')
    .sign(new TextEncoder().encode(process.env.JWT_SECRET));
}

async function send(event: IngestEvent, attempt: number): Promise<void> {
  const base = process.env.API_URL;
  if (!base) return;
  try {
    const response = await fetch(`${base}/internal/v1/arena/events`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${await token()}`,
      },
      body: JSON.stringify({ ...event, process_id: processId }),
      signal: AbortSignal.timeout(5000),
    });
    // 4xx means the payload itself is wrong; retrying will not help.
    if (response.status >= 500) throw new Error(`API ${response.status}`);
  } catch {
    const delay = RETRIES[attempt];
    if (delay !== undefined)
      setTimeout(() => void send(event, attempt + 1), delay).unref();
  }
}

export function report(event: IngestEvent): void {
  void send(event, 0);
}

/**
 * A player's quick slot stock and pet from the API (service token). Missing API,
 * timeouts or errors give an empty loadout: the round still plays, without items.
 */
export async function fetchLoadout(
  accountId: string,
): Promise<{ items: Record<string, number>; pet: string | null }> {
  const base = process.env.API_URL;
  const empty = { items: {}, pet: null };
  if (!base) return empty;
  try {
    const response = await fetch(
      `${base}/internal/v1/arena/loadout/${encodeURIComponent(accountId)}`,
      {
        headers: { Authorization: `Bearer ${await token()}` },
        signal: AbortSignal.timeout(4000),
      },
    );
    if (!response.ok) return empty;
    const body = (await response.json()) as {
      items?: Record<string, unknown>;
      pet?: unknown;
    };
    const items: Record<string, number> = {};
    for (const [k, v] of Object.entries(body.items ?? {}))
      if (typeof v === 'number') items[k] = v;
    return { items, pet: typeof body.pet === 'string' ? body.pet : null };
  } catch {
    return empty;
  }
}
