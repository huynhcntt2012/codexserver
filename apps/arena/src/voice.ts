/**
 * Team voice relay (docs/VOICE.md). Clients send byte messages of type
 * VOICE_TYPE: [channel, ...audio] with 60 ms of 16 kHz mono mu-law audio. The
 * arena only forwards them: it never decodes or stores audio. It names the
 * speaker itself (the session id, never a value from the client), drops frames
 * that are malformed or too frequent, and sends each one on as
 * [channel, idLength, ...id, ...audio].
 */
export const VOICE_TYPE = 2;
export const VOICE_TEAM = 0;
export const VOICE_ALL = 1;
/** 60 ms at 16 kHz, one byte per sample. */
export const VOICE_SAMPLES = 960;
/** Frames per second one speaker may send (60 ms frames are ~17/s). */
export const VOICE_RATE = 24;

export type VoiceFrame = { channel: number; bytes: Uint8Array };

/** Wraps a client's frame with its speaker id; null when it is not a voice frame. */
export function voiceFrame(
  speaker: string,
  data: Uint8Array,
): VoiceFrame | null {
  if (!(data instanceof Uint8Array)) return null;
  const channel = data[0];
  if (channel !== VOICE_TEAM && channel !== VOICE_ALL) return null;
  const audio = data.subarray(1);
  if (audio.length === 0 || audio.length > VOICE_SAMPLES) return null;
  const id = Buffer.from(speaker, 'utf8');
  if (id.length > 64) return null;
  const bytes = new Uint8Array(2 + id.length + audio.length);
  bytes[0] = channel;
  bytes[1] = id.length;
  bytes.set(id, 2);
  bytes.set(audio, 2 + id.length);
  return { channel, bytes };
}

/** At most VOICE_RATE frames per speaker in any second. */
export class VoiceLimiter {
  private sent = new Map<string, number[]>();

  allow(speaker: string, now: number): boolean {
    const recent = (this.sent.get(speaker) ?? []).filter((t) => now - t < 1000);
    if (recent.length >= VOICE_RATE) {
      this.sent.set(speaker, recent);
      return false;
    }
    recent.push(now);
    this.sent.set(speaker, recent);
    return true;
  }

  forget(speaker: string): void {
    this.sent.delete(speaker);
  }
}
