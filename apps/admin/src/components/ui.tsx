import { ReactNode, useEffect, useRef, useState } from 'react';
import { iconUrl, PHASE, RARITY } from '@/lib/format';

export function Card({
  title,
  action,
  children,
  className = '',
}: {
  title?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`card ${className}`}>
      {(title || action) && (
        <div className="card-head">
          <h2>{title}</h2>
          {action}
        </div>
      )}
      {children}
    </section>
  );
}

export function Stat({
  icon,
  tone,
  value,
  label,
}: {
  icon: string;
  tone: 'sky' | 'sun' | 'coral' | 'mint' | 'violet';
  value: ReactNode;
  label: string;
}) {
  return (
    <section className="card stat">
      <div className={`bubble ${tone}`} aria-hidden>
        {icon}
      </div>
      <div>
        <b>{value}</b>
        <span>{label}</span>
      </div>
    </section>
  );
}

export function Phase({ value }: { value: string }) {
  const [label, tone] = PHASE[value] ?? [value, ''];
  return <span className={`badge ${tone}`}>{label}</span>;
}

export function Rarity({ value }: { value: string | null }) {
  if (!value) return null;
  const [label, tone] = RARITY[value] ?? [value, ''];
  return <span className={`badge ${tone}`}>{label}</span>;
}

export function Thumb({
  icon,
  sha,
}: {
  icon: string | null | undefined;
  sha?: string | null;
}) {
  const url = iconUrl(icon, sha);
  return url ? (
    <img className="thumb" src={url} alt="" loading="lazy" />
  ) : (
    <span className="thumb" aria-hidden />
  );
}

export function Empty({
  title,
  children,
}: {
  title: string;
  children?: ReactNode;
}) {
  return (
    <div className="empty">
      <b>{title}</b>
      {children}
    </div>
  );
}

export function Loading({ error }: { error?: string | null }) {
  return error ? (
    <div className="notice">{error}</div>
  ) : (
    <div className="empty">Đang tải…</div>
  );
}

export function Modal({
  title,
  onClose,
  children,
  wide = false,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  wide?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    // Only the top-most popup closes on Escape.
    const onKey = (event: KeyboardEvent) => {
      const overlays = document.querySelectorAll('.overlay');
      if (
        event.key === 'Escape' &&
        overlays[overlays.length - 1] === ref.current
      )
        onClose();
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div
      ref={ref}
      className="overlay"
      onMouseDown={(event) => event.target === event.currentTarget && onClose()}
    >
      <div
        className={`modal${wide ? ' wide' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="modal-head">
          <h2>{title}</h2>
          <button className="close" onClick={onClose} aria-label="Đóng">
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function Field({
  label,
  hint,
  children,
  full = false,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
  full?: boolean;
}) {
  return (
    <label className={`field${full ? ' full' : ''}`}>
      <span>{label}</span>
      {children}
      {hint && <small>{hint}</small>}
    </label>
  );
}

/** Modal asking for the reason every audited moderation action must carry. */
export function useReason(): [
  ReactNode,
  (question: string, confirm?: string) => Promise<string | null>,
] {
  const [ask, setAsk] = useState<{
    question: string;
    confirm: string;
    resolve: (value: string | null) => void;
  } | null>(null);
  const [text, setText] = useState('');
  const finish = (value: string | null) => {
    ask?.resolve(value);
    setAsk(null);
    setText('');
  };
  const node = ask ? (
    <Modal title={ask.question} onClose={() => finish(null)}>
      <Field
        label="Lý do"
        hint="Ít nhất 5 ký tự. Lý do được lưu vào nhật ký audit."
      >
        <textarea
          className="input"
          autoFocus
          value={text}
          maxLength={500}
          onChange={(event) => setText(event.target.value)}
        />
      </Field>
      <div className="modal-actions">
        <button className="btn ghost" onClick={() => finish(null)}>
          Hủy
        </button>
        <button
          className="btn danger"
          disabled={text.trim().length < 5}
          onClick={() => finish(text.trim())}
        >
          {ask.confirm}
        </button>
      </div>
    </Modal>
  ) : null;
  return [
    node,
    (question, confirm = 'Xác nhận') =>
      new Promise((resolve) => setAsk({ question, confirm, resolve })),
  ];
}
