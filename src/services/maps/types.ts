import type { GeoPoint, PlaceResult } from '@/types'

export interface RouteLeg { from: GeoPoint; to: GeoPoint; distanceKm: number; durationMinutes: number }
export interface RouteResult { legs: RouteLeg[]; distanceKm: number; durationMinutes: number }

/** Provider-agnostic map contract. UI code depends on this interface only. */
export interface MapProvider {
  readonly id: string
  renderMap(container: HTMLElement, options?: { center?: GeoPoint; zoom?: number }): Promise<MapHandle>
  searchPlaces(query: string, limit?: number): Promise<PlaceResult[]>
  geocode(query: string): Promise<GeoPoint | null>
  reverseGeocode(point: GeoPoint): Promise<PlaceResult | null>
  getRoute(points: GeoPoint[]): Promise<RouteResult>
  getDistance(from: GeoPoint, to: GeoPoint): Promise<number>
}

export interface MapHandle {
  setMarkers(points: Array<GeoPoint & { label?: string }>): void
  onClick(handler: (point: GeoPoint) => void): void
  destroy(): void
}
