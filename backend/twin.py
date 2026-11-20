"""Digital twin planning model for Hail — simulation only, not official tower inventory.

Towers are a planning scaffold over QUALITY bounds, enriched by real measurement
cells so scenarios (outage / add site) reflect observed coverage quality.
"""
from __future__ import annotations

import math
from typing import Any

from backend.core import QUALITY, cell_bounds, cell_id, classify


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def sector_label(lat: float, lon: float) -> str:
    """Coarse Arabic sector name from position inside Hail bounds."""
    west, south, east, north = QUALITY['bounds']
    if not (south <= lat <= north and west <= lon <= east):
        return 'خارج حدود حائل'
    v = (lat - south) / max(north - south, 1e-9)
    h = (lon - west) / max(east - west, 1e-9)
    ns = 'شمال' if v >= 0.66 else 'وسط' if v >= 0.33 else 'جنوب'
    ew = 'شرق' if h >= 0.66 else 'وسط' if h >= 0.33 else 'غرب'
    if ns == 'وسط' and ew == 'وسط':
        return 'وسط حائل'
    if ns == 'وسط':
        return f'{ew} حائل'
    if ew == 'وسط':
        return f'{ns} حائل'
    return f'{ns} {ew} حائل'


def build_planning_towers(measurement_cells: list[dict] | None = None) -> list[dict]:
    """Grid of planning sites + optional towers anchored near measured cells."""
    west, south, east, north = QUALITY['bounds']
    towers: list[dict] = []
    rows, cols = 3, 3
    for iy in range(rows):
        for ix in range(cols):
            lat = south + (iy + 0.5) / rows * (north - south)
            lon = west + (ix + 0.5) / cols * (east - west)
            tid = f'T-{iy + 1}{ix + 1}'
            towers.append(
                {
                    'id': tid,
                    'name': f'برج تخطيطي {tid}',
                    'lat': round(lat, 5),
                    'lon': round(lon, 5),
                    'sector': sector_label(lat, lon),
                    'capacity': 1.0,
                    'radius_km': 6.5,
                    'kind': 'planning',
                    'active': True,
                }
            )

    # Extra sites near dense/weak measured cells so the twin tracks real pain points.
    for i, cell in enumerate((measurement_cells or [])[:8]):
        b = cell['bounds']
        lat = (b[1] + b[3]) / 2
        lon = (b[0] + b[2]) / 2
        # Skip if already close to an existing planning tower.
        if any(_haversine_km(lat, lon, t['lat'], t['lon']) < 2.2 for t in towers):
            continue
        q = (cell.get('quality') or {}).get('download') or cell.get('status')
        capacity = 1.15 if q in ('poor', 'very_poor') else 0.95
        tid = f'M-{i + 1:02d}'
        towers.append(
            {
                'id': tid,
                'name': f'موقع مُستنبط {tid}',
                'lat': round(lat, 5),
                'lon': round(lon, 5),
                'sector': sector_label(lat, lon),
                'capacity': capacity,
                'radius_km': 5.5,
                'kind': 'measured',
                'active': True,
                'source_cell': cell.get('id'),
            }
        )
    return towers


def coverage_at(lat: float, lon: float, towers: list[dict]) -> dict[str, Any]:
    score = 0.0
    best = None
    best_w = 0.0
    contributors = []
    for t in towers:
        if not t.get('active', True):
            continue
        d = _haversine_km(lat, lon, t['lat'], t['lon'])
        r = float(t.get('radius_km') or 6.0)
        w = float(t.get('capacity') or 1.0) * math.exp(-d / max(r, 0.5))
        if w < 0.04:
            continue
        score += w
        contributors.append({'tower_id': t['id'], 'weight': round(w, 3), 'km': round(d, 2)})
        if w > best_w:
            best_w = w
            best = t['id']
    contributors.sort(key=lambda x: -x['weight'])
    return {
        'score': round(score, 3),
        'primary_tower': best,
        'contributors': contributors[:4],
    }


def quality_to_base(q: str | None) -> float:
    return {
        'good': 0.92,
        'moderate': 0.68,
        'poor': 0.38,
        'very_poor': 0.18,
        'stale': 0.45,
        'insufficient': 0.4,
        'ready': 0.55,
        'personal': 0.55,
    }.get(q or '', 0.5)


def cells_from_measurements(rows) -> list[dict]:
    """Aggregate raw measurement rows into twin cells with observed quality."""
    groups: dict[tuple[int, int], list] = {}
    for row in rows:
        key = (row['cell_y'], row['cell_x'])
        groups.setdefault(key, []).append(row)
    cells = []
    for (y, x), items in groups.items():
        dls = [float(r['download_mbps']) for r in items]
        pings = [float(r['ping_ms']) for r in items]
        med_dl = sorted(dls)[len(dls) // 2]
        med_ping = sorted(pings)[len(pings) // 2]
        q = classify(med_dl, 'download')
        b = cell_bounds(y, x)
        lat = (b[1] + b[3]) / 2
        lon = (b[0] + b[2]) / 2
        cells.append(
            {
                'id': cell_id(y, x),
                'bounds': b,
                'lat': lat,
                'lon': lon,
                'sector': sector_label(lat, lon),
                'sample_count': len(items),
                'avg_download_mbps': round(sum(dls) / len(dls), 2),
                'avg_ping_ms': round(sum(pings) / len(pings), 1),
                'quality': {'download': q, 'ping': classify(med_ping, 'ping')},
                'observed_base': quality_to_base(q),
            }
        )
    return cells


def enrich_cells(cells: list[dict], towers: list[dict]) -> list[dict]:
    out = []
    for cell in cells:
        cov = coverage_at(cell['lat'], cell['lon'], towers)
        # Blend geometric coverage with observed quality so the twin stays data-grounded.
        health = round(0.55 * cell['observed_base'] + 0.45 * min(1.0, cov['score'] / 1.6), 3)
        item = {
            **cell,
            'coverage_score': cov['score'],
            'primary_tower': cov['primary_tower'],
            'contributors': cov['contributors'],
            'health': health,
            'health_label': (
                'good' if health >= 0.72 else 'moderate' if health >= 0.5 else 'poor' if health >= 0.32 else 'very_poor'
            ),
        }
        out.append(item)
    return out


def ensure_grid_cells(existing: list[dict], step_factor: int = 2) -> list[dict]:
    """Fill a coarse grid so the twin has geography even with few measurements."""
    west, south, east, north = QUALITY['bounds']
    step = QUALITY['cell_degrees'] * step_factor
    have = {c['id'] for c in existing}
    filled = list(existing)
    lat = south + step / 2
    while lat < north:
        lon = west + step / 2
        while lon < east:
            # Snap to quality cell grid
            from backend.core import cell_for

            y, x = cell_for(lat, lon)
            cid = cell_id(y, x)
            if cid not in have:
                b = cell_bounds(y, x)
                clat = (b[1] + b[3]) / 2
                clon = (b[0] + b[2]) / 2
                filled.append(
                    {
                        'id': cid,
                        'bounds': b,
                        'lat': clat,
                        'lon': clon,
                        'sector': sector_label(clat, clon),
                        'sample_count': 0,
                        'avg_download_mbps': None,
                        'avg_ping_ms': None,
                        'quality': {'download': 'insufficient', 'ping': 'insufficient'},
                        'observed_base': 0.42,
                        'synthetic': True,
                    }
                )
                have.add(cid)
            lon += step
        lat += step
    return filled


def _normalize_tower(raw: dict, *, default_kind: str = 'proposed') -> dict:
    lat = float(raw['lat'])
    lon = float(raw['lon'])
    tid = str(raw.get('id') or 'NEW').strip()[:40] or 'NEW'
    radius = float(raw.get('radius_km') or 6.5)
    capacity = float(raw.get('capacity') or 1.0)
    radius = max(2.0, min(18.0, radius))
    capacity = max(0.35, min(2.5, capacity))
    return {
        'id': tid,
        'name': (str(raw.get('name') or f'برج {tid}')).strip()[:60] or f'برج {tid}',
        'lat': round(lat, 5),
        'lon': round(lon, 5),
        'sector': sector_label(lat, lon),
        'capacity': round(capacity, 3),
        'radius_km': round(radius, 2),
        'kind': str(raw.get('kind') or default_kind)[:24],
        'active': bool(raw.get('active', True)),
    }


def compare_tower_sets(
    cells: list[dict],
    baseline_towers: list[dict],
    working_towers: list[dict],
) -> dict:
    """Compare network health: baseline towers vs an editable working set."""
    base_towers = [_normalize_tower(t, default_kind=str(t.get('kind') or 'planning')) for t in baseline_towers]
    after_towers = [_normalize_tower(t, default_kind=str(t.get('kind') or 'proposed')) for t in working_towers]
    # Keep at most 40 towers in a sandbox run.
    after_towers = after_towers[:40]

    before = enrich_cells(cells, base_towers)
    after = enrich_cells(cells, after_towers)

    before_map = {c['id']: c for c in before}
    impacted = []
    improved = []
    for cell in after:
        prev = before_map[cell['id']]
        delta = round(cell['health'] - prev['health'], 3)
        row = {
            'id': cell['id'],
            'sector': cell['sector'],
            'bounds': cell['bounds'],
            'health_before': prev['health'],
            'health_after': cell['health'],
            'delta': delta,
            'primary_tower_before': prev.get('primary_tower'),
            'primary_tower_after': cell.get('primary_tower'),
            'sample_count': cell.get('sample_count') or 0,
        }
        if delta <= -0.06:
            impacted.append(row)
        elif delta >= 0.06:
            improved.append(row)

    impacted.sort(key=lambda r: r['delta'])
    improved.sort(key=lambda r: -r['delta'])

    avg_before = sum(c['health'] for c in before) / max(len(before), 1)
    avg_after = sum(c['health'] for c in after) / max(len(after), 1)

    base_ids = {t['id'] for t in base_towers}
    work_ids = {t['id'] for t in after_towers}
    removed_ids = sorted(base_ids - work_ids)
    added = [t for t in after_towers if t['id'] not in base_ids]
    disabled_ids = sorted(
        t['id'] for t in after_towers if t['id'] in base_ids and not t.get('active', True)
    )
    # Also count baseline towers that were removed as disabled/removed impact
    active_before = sum(1 for t in base_towers if t.get('active', True))
    active_after = sum(1 for t in after_towers if t.get('active', True))

    recommendations = []
    if removed_ids or disabled_ids:
        worst = impacted[:5]
        if worst:
            recommendations.append(
                'الأحياء الأكثر تأثرًا: '
                + '، '.join(f"{w['sector']} ({w['delta']:+.0%})" for w in worst)
            )
            recommendations.append(
                'الحل المقترح: أعد تشغيل أقرب برج، أو ازرع موقعًا بديلًا '
                f"قرب {worst[0]['sector']} وراقب موجة الأثر فورًا."
            )
        else:
            recommendations.append('إزالة/تعطيل الأبراج لم يُظهر فراغًا كبيرًا — التغطية البديلة كافية في النموذج.')
    if added:
        if improved:
            recommendations.append(
                f"الأبراج المضافة تحسّن "
                + '، '.join(f"{w['sector']} ({w['delta']:+.0%})" for w in improved[:4])
            )
            recommendations.append('جرّب سحب نصف القطر أو السعة للبرج الجديد لضبط تغطية الحي بدقة.')
        else:
            recommendations.append('الموقع الجديد لا يغيّر الصحة كثيرًا — اقترب من الخلايا الحمراء/الصفراء.')
    if not recommendations:
        recommendations.append('حرّك الأبراج أو عطّل موقعًا أو أضف برجًا على الخريطة لرؤية أثر حي على المنطقة.')

    return {
        'before_avg_health': round(avg_before, 3),
        'after_avg_health': round(avg_after, 3),
        'delta_avg_health': round(avg_after - avg_before, 3),
        'impacted_cells': impacted[:20],
        'improved_cells': improved[:20],
        'cells_after': after,
        'towers_after': after_towers,
        'added_towers': added,
        'added_tower': added[0] if added else None,
        'removed_ids': removed_ids,
        'disabled_ids': disabled_ids,
        'active_towers_before': active_before,
        'active_towers_after': active_after,
        'recommendations': recommendations,
    }


def simulate_scenario(
    cells: list[dict],
    towers: list[dict],
    *,
    disable_ids: list[str] | None = None,
    remove_ids: list[str] | None = None,
    add_tower: dict | None = None,
    add_towers: list[dict] | None = None,
) -> dict:
    base_towers = [_normalize_tower(t, default_kind=str(t.get('kind') or 'planning')) for t in towers]
    after_towers = [dict(t) for t in base_towers]

    removed = set(str(x) for x in (remove_ids or []))
    if removed:
        after_towers = [t for t in after_towers if t['id'] not in removed]

    disabled = set(str(x) for x in (disable_ids or []))
    for t in after_towers:
        if t['id'] in disabled:
            t['active'] = False

    extras: list[dict] = []
    if add_tower:
        extras.append(add_tower)
    if add_towers:
        extras.extend(add_towers)
    for i, raw in enumerate(extras[:12]):
        tid = str(raw.get('id') or f'NEW-{i + 1}')
        extras_norm = _normalize_tower({**raw, 'id': tid}, default_kind='proposed')
        after_towers.append(extras_norm)

    result = compare_tower_sets(cells, base_towers, after_towers)
    return result
