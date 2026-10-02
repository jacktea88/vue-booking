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
  <div class="relative">
    <label class="label" :for="`place-${label}`">{{ label }}</label>
    <input
      :id="`place-${label}`" class="field" type="text" autocomplete="off"
      :placeholder="placeholder" :value="term"
      role="combobox" :aria-expanded="open" aria-autocomplete="list"
      @input="onInput" @focus="open = results.length > 0"
    />
    <button v-if="allowCurrentLocation" type="button" class="mt-1 text-xs font-medium text-brand-700 hover:underline" @click="useCurrent">
      {{ geo.loading.value ? t('common.loading') : t('search.useMyLocation') }}
    </button>
    <p v-if="geo.denied.value" class="mt-1 text-xs text-red-600">{{ t('search.locationDenied') }}</p>

    <ul v-if="open && results.length" class="absolute z-20 mt-1 max-h-60 w-full overflow-auto rounded-lg border border-slate-200 bg-white shadow-lg" role="listbox">
      <li v-for="(r, i) in results" :key="`${r.name}-${i}`">
        <button type="button" class="block w-full px-3 py-2 text-start text-sm hover:bg-slate-50" role="option" @click="select(r)">
          <span class="font-medium">{{ r.name }}</span>
          <span v-if="r.wilaya" class="ms-2 text-xs text-slate-500">{{ r.wilaya }}</span>
        </button>
      </li>
    </ul>
    <p v-if="busy" class="mt-1 text-xs text-slate-400">{{ t('common.loading') }}</p>
  </div>
</template>
