import { useEffect, useRef, useState } from 'react';

export interface Crop {
  left: number;
  top: number;
  width: number;
  height: number;
}

/**
 * Quadratischer Zuschnitt für Künstlerprofilbilder: Bild verschieben (Maus/Touch) und zoomen.
 * Liefert Pixelkoordinaten im Originalbild; der Server schneidet zu (sharp).
 */
export function ImageCropper({ file, onChange }: { file: File; onChange: (c: Crop) => void }) {
  const [url, setUrl] = useState<string | null>(null);
  const [nat, setNat] = useState<{ w: number; h: number } | null>(null);
  const [zoom, setZoom] = useState(1);
  const [pos, setPos] = useState({ x: 0, y: 0 });
  const box = useRef<HTMLDivElement>(null);
  const drag = useRef<{ x: number; y: number; px: number; py: number } | null>(null);
  const [boxSize, setBoxSize] = useState(360);

  useEffect(() => {
    const u = URL.createObjectURL(file);
    setUrl(u);
    const img = new Image();
    img.onload = () => {
      setNat({ w: img.naturalWidth, h: img.naturalHeight });
      setZoom(1);
      setPos({ x: 0, y: 0 });
    };
    img.src = u;
    return () => URL.revokeObjectURL(u);
  }, [file]);

  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setBoxSize(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Basismaßstab: kürzere Seite füllt den Rahmen
  const base = nat ? boxSize / Math.min(nat.w, nat.h) : 1;
  const scale = base * zoom;
  const clamp = (p: { x: number; y: number }) => {
    if (!nat) return p;
    const maxX = 0;
    const minX = boxSize - nat.w * scale;
    const maxY = 0;
    const minY = boxSize - nat.h * scale;
    return { x: Math.min(maxX, Math.max(minX, p.x)), y: Math.min(maxY, Math.max(minY, p.y)) };
  };

  useEffect(() => {
    if (!nat) return;
    // Beim ersten Laden zentrieren
    setPos((p) => (p.x === 0 && p.y === 0 ? clamp({ x: (boxSize - nat.w * scale) / 2, y: (boxSize - nat.h * scale) / 2 }) : clamp(p)));
  }, [nat, zoom, boxSize]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!nat) return;
    const size = Math.floor(boxSize / scale);
    const left = Math.max(0, Math.round(-pos.x / scale));
    const top = Math.max(0, Math.round(-pos.y / scale));
    onChange({ left: Math.min(left, nat.w - size), top: Math.min(top, nat.h - size), width: Math.min(size, nat.w), height: Math.min(size, nat.h) });
  }, [pos, scale, nat, boxSize]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="stack">
      <div
        ref={box}
        className="crop-area"
        onPointerDown={(e) => {
          (e.target as HTMLElement).setPointerCapture(e.pointerId);
          drag.current = { x: e.clientX, y: e.clientY, px: pos.x, py: pos.y };
        }}
        onPointerMove={(e) => {
          if (!drag.current) return;
          setPos(clamp({ x: drag.current.px + e.clientX - drag.current.x, y: drag.current.py + e.clientY - drag.current.y }));
        }}
        onPointerUp={() => (drag.current = null)}
      >
        {url && nat && <img src={url} alt="" style={{ width: nat.w * scale, height: nat.h * scale, left: pos.x, top: pos.y }} />}
        <div className="mask" />
      </div>
      <label className="field">
        Zoom
        <input type="range" min={1} max={4} step={0.01} value={zoom} onChange={(e) => setZoom(Number(e.target.value))} />
      </label>
    </div>
  );
}
