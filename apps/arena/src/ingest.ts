import { randomUUID } from 'node:crypto';
import { SignJWT } from 'jose';

/**
 * Fire-and-forget reports of room and round events to the account API.
 * Never awaited by the simulation: a slow or offline API cannot delay a tick.
 * Disabled when API_URL is unset (tests, local runs without the API).
 */
export const processId = randomUUID().slice(0, 8);

export type IngestEvent = {
  type: 'room' | 'closed' | 'match';
  room_id: string;
  phase?: string;
  players?: { account_id: string; name: string }[];
  max_players?: number;
  map_name?: string;
  map_id?: string;
  round?: number;
  duration_ms?: number;
  practice?: boolean;
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
