import { useState } from 'react';
import Layout from '@/components/Layout';
import { LedgerTable, type LedgerRow } from '@/components/Ledger';
import { Card, Loading, Stat } from '@/components/ui';
import { api } from '@/lib/api';
import { KIND, number } from '@/lib/format';
import { useLoad } from '@/lib/session';

type Transactions = {
  items: LedgerRow[];
  total: number;
  page: number;
  size: number;
  summary: {
    topups: number;
    gem_topped_up: number;
    sandbox_vnd: number;
    gold_exchanged: number;
    purchases: number;
    wallets: number;
    gold_total: number;
    gem_total: number;
  };
};

export default function EconomyPage() {
  const [kind, setKind] = useState('');
  const [currency, setCurrency] = useState('');
  const [page, setPage] = useState(1);
  const data = useLoad(
    () =>
      api<Transactions>(
        `/transactions?kind=${kind}&currency=${currency}&page=${page}&size=30`,
      ),
    [kind, currency, page],
  );
  const d = data.data;
  const pages = d ? Math.max(1, Math.ceil(d.total / d.size)) : 1;
  return (
    <Layout
      title="Giao dịch & kinh tế"
      subtitle="Sổ ví vàng/kim cương: nạp, đổi, mua vật phẩm, điều chỉnh của admin."
    >
      <div className="notice">
        Giai đoạn này chưa có cổng thanh toán: gói nạp là <b>sandbox</b>, không
        thu tiền. Cột “Giá tham chiếu” là giá niêm yết của gói để đối soát sau
        này.
      </div>
      {!d ? (
        <Loading error={data.error} />
      ) : (
        <>
          <div className="grid stats">
            <Stat
              icon="💎"
              tone="sky"
              value={number(d.summary.gem_topped_up)}
              label={`Kim cương đã nạp (${number(d.summary.topups)} lần)`}
            />
            <Stat
              icon="🧾"
              tone="sun"
              value={`${number(d.summary.sandbox_vnd)} đ`}
              label="Giá trị nạp sandbox (không thu)"
            />
            <Stat
              icon="🪙"
              tone="mint"
              value={number(d.summary.gold_exchanged)}
              label="Vàng đổi từ kim cương"
            />
            <Stat
              icon="🛒"
              tone="violet"
              value={number(d.summary.purchases)}
              label="Lượt mua vật phẩm"
            />
            <Stat
              icon="👛"
              tone="coral"
              value={number(d.summary.wallets)}
              label={`Ví · ${number(d.summary.gold_total)} vàng · ${number(d.summary.gem_total)} KC`}
            />
          </div>
          <Card
            title={`${number(d.total)} giao dịch`}
            action={
              <div className="toolbar">
                <select
                  className="input"
                  value={kind}
                  onChange={(e) => {
                    setPage(1);
                    setKind(e.target.value);
                  }}
                  aria-label="Loại giao dịch"
                >
                  <option value="">Mọi loại</option>
                  {Object.entries(KIND).map(([key, [label]]) => (
                    <option key={key} value={key}>
                      {label}
                    </option>
                  ))}
                </select>
                <select
                  className="input"
                  value={currency}
                  onChange={(e) => {
                    setPage(1);
                    setCurrency(e.target.value);
                  }}
                  aria-label="Loại tiền"
                >
                  <option value="">Vàng & kim cương</option>
                  <option value="gem">Kim cương</option>
                  <option value="gold">Vàng</option>
                </select>
              </div>
            }
          >
            <LedgerTable entries={d.items} showAccount />
            <div className="pager">
              <button
                className="btn small ghost"
                disabled={page <= 1}
                onClick={() => setPage(page - 1)}
              >
                ‹ Trước
              </button>
              <span>
                Trang {page}/{pages}
              </span>
              <button
                className="btn small ghost"
                disabled={page >= pages}
                onClick={() => setPage(page + 1)}
              >
                Sau ›
              </button>
            </div>
          </Card>
        </>
      )}
    </Layout>
  );
}
