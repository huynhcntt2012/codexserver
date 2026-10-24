import { dateTime, KIND, number } from '@/lib/format';
import { Empty } from './ui';

export type Ledger = {
  id: number;
  currency: 'gold' | 'gem';
  delta: number;
  balance_after: number;
  kind: string;
  item_id: string | null;
  amount_vnd: number | null;
  note: string;
  actor: string;
  created_at: string;
};

export type LedgerRow = Ledger & { account_id?: string; account_name?: string };

export function LedgerTable({
  entries,
  showAccount = false,
}: {
  entries: LedgerRow[];
  showAccount?: boolean;
}) {
  if (entries.length === 0) return <Empty title="Chưa có giao dịch" />;
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Lúc</th>
            {showAccount && <th>Người chơi</th>}
            <th>Loại</th>
            <th>Biến động</th>
            <th>Số dư sau</th>
            <th>Nội dung</th>
            <th>Giá tham chiếu</th>
            <th>Bởi</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((e) => (
            <tr key={e.id}>
              <td>{dateTime(e.created_at)}</td>
              {showAccount && (
                <td>
                  <a href={`/admin/players/?id=${e.account_id}`}>
                    {e.account_name}
                  </a>
                </td>
              )}
              <td>
                <span className={`badge ${KIND[e.kind]?.[1] ?? ''}`}>
                  {KIND[e.kind]?.[0] ?? e.kind}
                </span>
              </td>
              <td className={e.delta > 0 ? 'plus' : 'minus'}>
                {e.delta > 0 ? '+' : ''}
                {number(e.delta)} {e.currency === 'gem' ? '💎' : '🪙'}
              </td>
              <td>{number(e.balance_after)}</td>
              <td>{e.note || e.item_id || '—'}</td>
              <td>
                {e.amount_vnd ? `${number(e.amount_vnd)} đ (sandbox)` : '—'}
              </td>
              <td>{e.actor}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
