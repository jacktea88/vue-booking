import type { MapProvider } from './types'
import { OsmMapProvider } from './osmProvider'
import { GoogleMapProvider } from './googleProvider'

let instance: MapProvider | null = null

/** Single place where a provider is chosen. UI never imports a concrete provider. */
export function getMapProvider(): MapProvider {
  if (instance) return instance
  const name = (import.meta.env.VITE_MAP_PROVIDER as string) || 'osm'
  const key = (import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string) || ''
  instance = name === 'google' && key ? new GoogleMapProvider(key) : new OsmMapProvider()
  return instance
}

export function setMapProvider(provider: MapProvider): void { instance = provider }
export * from './types'
export * from './geo'
