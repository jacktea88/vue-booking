import { ref } from 'vue'
import type { GeoPoint } from '@/types'

/** One-shot current position only — no continuous tracking by design. */
export function useGeolocation() {
  const position = ref<GeoPoint | null>(null)
  const denied = ref(false)
  const loading = ref(false)

  function locate(): Promise<GeoPoint | null> {
    loading.value = true
    return new Promise((resolve) => {
      if (!('geolocation' in navigator)) { denied.value = true; loading.value = false; resolve(null); return }
      navigator.geolocation.getCurrentPosition(
        (p) => {
          position.value = { lat: p.coords.latitude, lng: p.coords.longitude }
          loading.value = false
          resolve(position.value)
        },
        () => { denied.value = true; loading.value = false; resolve(null) },
        { timeout: 10_000, enableHighAccuracy: false },
      )
    })
  }

  return { position, denied, loading, locate }
}
