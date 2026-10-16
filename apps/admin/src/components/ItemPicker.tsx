import { api } from '@/lib/api';
import { useLoad } from '@/lib/session';
import type { Item } from '@/pages/items';
import { Thumb } from './ui';

/** Checkbox grid of catalog items used as rewards. */
export default function ItemPicker({
  value,
  onChange,
}: {
  value: string[];
  onChange: (ids: string[]) => void;
}) {
  const catalog = useLoad(() => api<{ items: Item[] }>('/items'));
  const items = catalog.data?.items ?? [];
  return (
    <div className="check-grid">
      {items.length === 0 && (
        <span className="muted">Chưa có vật phẩm trong danh mục.</span>
      )}
      {items.map((item) => (
        <label key={item.id} className="check">
          <input
            type="checkbox"
            checked={value.includes(item.id)}
            onChange={(e) =>
              onChange(
                e.target.checked
                  ? [...value, item.id]
                  : value.filter((id) => id !== item.id),
              )
            }
          />
          <Thumb icon={item.icon} />
          <span>{item.name}</span>
        </label>
      ))}
    </div>
  );
}
