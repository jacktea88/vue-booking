import type { GeoPoint, PlaceResult } from '@/types'
import type { MapHandle, MapProvider, RouteResult } from './types'
import { estimateMinutes, haversineKm, ROAD_FACTOR } from './geo'
import { supabase } from '@/services/supabase/client'

const NOMINATIM = 'https://nominatim.openstreetmap.org'

/**
 * Default provider: OpenStreetMap tiles (static, no SDK) + Nominatim geocoding,
 * with the Algerian `places` table as the primary, offline-friendly search source.
 */
export class OsmMapProvider implements MapProvider {
  readonly id = 'osm'

  async renderMap(container: HTMLElement, options?: { center?: GeoPoint; zoom?: number }): Promise<MapHandle> {
    const center = options?.center ?? { lat: 36.7538, lng: 3.0588 }
    const zoom = options?.zoom ?? 6
    container.innerHTML = ''
    const frame = document.createElement('div')
    frame.className = 'position-relative h-100 w-100 overflow-hidden rounded-3 bg-secondary-subtle'
    const img = document.createElement('iframe')
    img.title = 'map'
    img.className = 'h-100 w-100 border-0'
    img.loading = 'lazy'
    const d = 2.5
    img.src = `${'https://www.openstreetmap.org/export/embed.html'}?bbox=${center.lng - d}%2C${center.lat - d}%2C${
      center.lng + d}%2C${center.lat + d}&layer=mapnik&marker=${center.lat}%2C${center.lng}&zoom=${zoom}`
    frame.appendChild(img)
    container.appendChild(frame)
    let clickHandler: ((p: GeoPoint) => void) | null = null
    return {
      setMarkers() { /* static embed: markers are rendered by the list UI */ },
      onClick(handler) { clickHandler = handler },
      destroy() { clickHandler = null; container.innerHTML = '' },
    }
  }

  async searchPlaces(q: string, limit = 8): Promise<PlaceResult[]> {
    const term = q.trim()
    if (term.length < 2) return []
    const { data } = await supabase
      .from('places')
      .select('id,name,wilaya,is_custom,location')
      .ilike('name', `%${term}%`)
      .limit(limit)
    const local: PlaceResult[] = (data ?? []).map((p) => {
      const point = parseGeo((p as { location: unknown }).location)
      return { id: p.id as string, name: p.name as string, wilaya: (p.wilaya as string) ?? null, point: point ?? { lat: 0, lng: 0 } }
    }).filter((p) => p.point.lat !== 0 || p.point.lng !== 0)
    if (local.length >= 3) return local
    const remote = await this.nominatim(term, limit - local.length)
    return [...local, ...remote]
  }

  private async nominatim(term: string, limit: number): Promise<PlaceResult[]> {
    try {
      const res = await fetch(`${NOMINATIM}/search?format=json&countrycodes=dz&limit=${limit}&q=${encodeURIComponent(term)}`)
      if (!res.ok) return []
      const rows = (await res.json()) as Array<{ display_name: string; lat: string; lon: string }>
      return rows.map((r) => ({
        name: r.display_name.split(',').slice(0, 2).join(','),
        point: { lat: Number(r.lat), lng: Number(r.lon) },
        isCustom: true,
      }))
    } catch { return [] }
  }

  async geocode(q: string): Promise<GeoPoint | null> {
    const [first] = await this.searchPlaces(q, 1)
    return first?.point ?? null
  }

  async reverseGeocode(point: GeoPoint): Promise<PlaceResult | null> {
    try {
      const res = await fetch(`${NOMINATIM}/reverse?format=json&lat=${point.lat}&lon=${point.lng}`)
      if (!res.ok) return null
      const j = (await res.json()) as { display_name?: string }
      return { name: j.display_name?.split(',').slice(0, 2).join(',') ?? `${point.lat.toFixed(4)}, ${point.lng.toFixed(4)}`, point, isCustom: true }
    } catch {
      return { name: `${point.lat.toFixed(4)}, ${point.lng.toFixed(4)}`, point, isCustom: true }
    }
  }

  async getRoute(points: GeoPoint[]): Promise<RouteResult> {
    const legs = points.slice(1).map((to, i) => {
      const from = points[i]
      const distanceKm = Number((haversineKm(from, to) * ROAD_FACTOR).toFixed(2))
      return { from, to, distanceKm, durationMinutes: estimateMinutes(distanceKm) }
    })
    return {
      legs,
      distanceKm: Number(legs.reduce((s, l) => s + l.distanceKm, 0).toFixed(2)),
      durationMinutes: legs.reduce((s, l) => s + l.durationMinutes, 0),
    }
  }

  async getDistance(from: GeoPoint, to: GeoPoint): Promise<number> {
    return Number((haversineKm(from, to) * ROAD_FACTOR).toFixed(2))
  }
}

export function parseGeo(value: unknown): GeoPoint | null {
  if (!value) return null
  if (typeof value === 'object' && value !== null && 'coordinates' in (value as Record<string, unknown>)) {
    const c = (value as { coordinates: number[] }).coordinates
    return { lng: c[0], lat: c[1] }
  }
  if (typeof value === 'string' && value.startsWith('POINT')) {
    const m = value.match(/POINT\s*\(([-\d.]+)\s+([-\d.]+)\)/)
    if (m) return { lng: Number(m[1]), lat: Number(m[2]) }
  }
  return null
}
