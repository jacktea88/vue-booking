export * from './database'
export * from './errors'
export interface GeoPoint { lat: number; lng: number }
export interface PlaceResult { id?: string; name: string; point: GeoPoint; wilaya?: string | null; isCustom?: boolean }
export type AsyncState = 'idle' | 'loading' | 'success' | 'empty' | 'error'
