<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { getMapProvider } from '@/services/maps'
import { debounce } from '@/composables/useDebounce'
import { SEARCH_DEBOUNCE_MS } from '@/utils/constants'
import { useGeolocation } from '@/composables/useGeolocation'
import type { PlaceResult } from '@/types'

const props = defineProps<{ modelValue: PlaceResult | null; label: string; placeholder?: string; allowCurrentLocation?: boolean }>()
const emit = defineEmits<{ 'update:modelValue': [PlaceResult | null] }>()

const { t } = useI18n()
const provider = getMapProvider()
const geo = useGeolocation()
const term = ref(props.modelValue?.name ?? '')
const results = ref<PlaceResult[]>([])
const open = ref(false)
const busy = ref(false)

/** Debounced, server-side search — never loads all places into the browser. */
const search = debounce(async (q: string) => {
  busy.value = true
  try { results.value = await provider.searchPlaces(q) } finally { busy.value = false; open.value = true }
}, SEARCH_DEBOUNCE_MS)

function onInput(e: Event) {
  term.value = (e.target as HTMLInputElement).value
  if (term.value.trim().length < 2) { results.value = []; open.value = false; return }
  search(term.value)
}

function select(p: PlaceResult) {
  term.value = p.name
  open.value = false
  emit('update:modelValue', p)
}

async function useCurrent() {
  const point = await geo.locate()
  if (!point) return
  const place = await provider.reverseGeocode(point)
  if (place) select(place)
}
</script>

<template>
  <div class="position-relative">
    <label class="form-label" :for="`place-${label}`">{{ label }}</label>
    <input
      :id="`place-${label}`" class="form-control" type="text" autocomplete="off"
      :placeholder="placeholder" :value="term"
      role="combobox" :aria-expanded="open" aria-autocomplete="list"
      @input="onInput" @focus="open = results.length > 0"
    />
    <button v-if="allowCurrentLocation" type="button" class="btn btn-link btn-sm p-0 mt-1 small fw-medium text-primary text-decoration-none" @click="useCurrent">
      {{ geo.loading.value ? t('common.loading') : t('search.useMyLocation') }}
    </button>
    <p v-if="geo.denied.value" class="mt-1 small text-danger mb-0">{{ t('search.locationDenied') }}</p>

    <ul v-if="open && results.length" class="position-absolute z-3 mt-1 w-100 max-h-60 overflow-auto list-unstyled rounded-3 border bg-white shadow-sm p-1" role="listbox">
      <li v-for="(r, i) in results" :key="`${r.name}-${i}`">
        <button type="button" class="dropdown-item text-wrap small" role="option" @click="select(r)">
          <span class="fw-medium">{{ r.name }}</span>
          <span v-if="r.wilaya" class="ms-2 small text-secondary">{{ r.wilaya }}</span>
        </button>
      </li>
    </ul>
    <p v-if="busy" class="mt-1 small text-muted mb-0">{{ t('common.loading') }}</p>
  </div>
</template>
