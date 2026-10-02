import type { GeoPoint, PlaceResult } from '@/types'
import type { MapHandle, MapProvider, RouteResult } from './types'
import { estimateMinutes, haversineKm, ROAD_FACTOR } from './geo'

/**
 * Google provider stub wired to the same contract. Enable with VITE_MAP_PROVIDER=google
 * and a key; it lazy-loads the SDK so no Google code ships unless selected.
 */
export class GoogleMapProvider implements MapProvider {
  readonly id = 'google'
  constructor(private apiKey: string) {}

  private async sdk(): Promise<any> {
    const w = window as unknown as { google?: any }
    if (w.google?.maps) return w.google
    await new Promise<void>((resolve, reject) => {
      const s = document.createElement('script')
      s.src = `https://maps.googleapis.com/maps/api/js?key=${this.apiKey}&libraries=places`
      s.async = true
      s.onload = () => resolve()
      s.onerror = () => reject(new Error('MAP_SDK_LOAD_FAILED'))
      document.head.appendChild(s)
    })
    return (window as unknown as { google: any }).google
  }

  async renderMap(container: HTMLElement, options?: { center?: GeoPoint; zoom?: number }): Promise<MapHandle> {
    const google = await this.sdk()
    const map = new google.maps.Map(container, {
      center: options?.center ?? { lat: 36.7538, lng: 3.0588 },
      zoom: options?.zoom ?? 6,
      disableDefaultUI: true,
    })
    let markers: any[] = []
    return {
      setMarkers(points) {
        markers.forEach((m) => m.setMap(null))
        markers = points.map((p) => new google.maps.Marker({ position: p, map, label: p.label }))
      },
      onClick(handler) {
        map.addListener('click', (e: any) => handler({ lat: e.latLng.lat(), lng: e.latLng.lng() }))
      },
      destroy() { markers.forEach((m) => m.setMap(null)); markers = [] },
    }
  }

  async searchPlaces(query: string, limit = 8): Promise<PlaceResult[]> {
    const google = await this.sdk()
    const svc = new google.maps.places.AutocompleteService()
    const geocoder = new google.maps.Geocoder()
    const preds: any[] = await new Promise((resolve) =>
      svc.getPlacePredictions({ input: query, componentRestrictions: { country: 'dz' } },
        (r: any[] | null) => resolve(r ?? [])))
    const out: PlaceResult[] = []
    for (const p of preds.slice(0, limit)) {
      const res: any = await new Promise((resolve) => geocoder.geocode({ placeId: p.place_id }, (r: any) => resolve(r?.[0])))
      if (res) out.push({ name: p.description, point: { lat: res.geometry.location.lat(), lng: res.geometry.location.lng() }, isCustom: true })
    }
    return out
  }

  async geocode(query: string): Promise<GeoPoint | null> { return (await this.searchPlaces(query, 1))[0]?.point ?? null }

  async reverseGeocode(point: GeoPoint): Promise<PlaceResult | null> {
    const google = await this.sdk()
    const geocoder = new google.maps.Geocoder()
    const res: any = await new Promise((resolve) => geocoder.geocode({ location: point }, (r: any) => resolve(r?.[0])))
    return res ? { name: res.formatted_address, point, isCustom: true } : null
  }

  async getRoute(points: GeoPoint[]): Promise<RouteResult> {
    const legs = points.slice(1).map((to, i) => {
      const from = points[i]
      const distanceKm = Number((haversineKm(from, to) * ROAD_FACTOR).toFixed(2))
      return { from, to, distanceKm, durationMinutes: estimateMinutes(distanceKm) }
    })
    return { legs, distanceKm: legs.reduce((s, l) => s + l.distanceKm, 0), durationMinutes: legs.reduce((s, l) => s + l.durationMinutes, 0) }
  }

  async getDistance(from: GeoPoint, to: GeoPoint): Promise<number> { return Number((haversineKm(from, to) * ROAD_FACTOR).toFixed(2)) }
}
