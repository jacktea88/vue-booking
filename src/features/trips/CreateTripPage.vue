<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PlaceAutocomplete from '@/components/PlaceAutocomplete.vue'
import MapView from '@/components/MapView.vue'
import { tripService } from '@/services/domain'
import { useToast } from '@/composables/useToast'
import { useAuthStore } from '@/stores/auth'
import { toLocalDatetimeInput } from '@/utils/format'
import { toAppError } from '@/types/errors'
import type { BookingMode, PlaceResult } from '@/types'

const { t } = useI18n()
const router = useRouter()
const toast = useToast()
const auth = useAuthStore()

interface Row { id: number; place: PlaceResult | null }
let seq = 0
const rows = ref<Row[]>([{ id: ++seq, place: null }, { id: ++seq, place: null }])
const departureAt = ref(toLocalDatetimeInput())
const mode = ref<BookingMode>('auto_confirm')
const busy = ref(false)

const add = () => rows.value.push({ id: ++seq, place: null })
const remove = (i: number) => { if (rows.value.length > 2) rows.value.splice(i, 1) }
function move(i: number, d: number) {
  const j = i + d
  if (j < 0 || j >= rows.value.length) return
  const [item] = rows.value.splice(i, 1)
  rows.value.splice(j, 0, item)
}

/** Custom map point: checkpoints do not have to exist in the global places table. */
function pickOnMap(point: { lat: number; lng: number }) {
  const empty = rows.value.find((r) => !r.place)
  const place: PlaceResult = { name: `${t('trip.mapPoint')} (${point.lat.toFixed(3)}, ${point.lng.toFixed(3)})`, point, isCustom: true }
  if (empty) empty.place = place
  else rows.value.push({ id: ++seq, place })
}

async function submit() {
  const checkpoints = rows.value.filter((r) => r.place).map((r) => ({
    name: r.place!.name, lat: r.place!.point.lat, lng: r.place!.point.lng, place_id: r.place!.id ?? null,
  }))
  if (checkpoints.length < 2) { toast.error(t('errors.AT_LEAST_TWO_CHECKPOINTS')); return }
  busy.value = true
  try {
    const tripId = await tripService.createTrip(new Date(departureAt.value).toISOString(), mode.value, checkpoints)
    toast.success(t('trip.created'))
    await router.push({ name: 'driver-trip-details', params: { id: tripId } })
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}
</script>

<template>
  <form class="space-y-4" @submit.prevent="submit">
    <h1 class="text-xl font-bold">{{ t('home.createTrip') }}</h1>
    <p v-if="!auth.isVerifiedDriver" class="card border-amber-300 bg-amber-50 text-sm text-amber-800">
      {{ t('profile.driverNotVerified') }}
    </p>

    <section class="card space-y-4">
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="label" for="dep">{{ t('trip.departureAt') }}</label>
          <input id="dep" v-model="departureAt" class="field" type="datetime-local" required />
        </div>
        <div>
          <label class="label" for="mode">{{ t('trip.mode') }}</label>
          <select id="mode" v-model="mode" class="field">
            <option value="auto_confirm">{{ t('search.bookingMode.auto_confirm') }}</option>
            <option value="driver_approval">{{ t('search.bookingMode.driver_approval') }}</option>
          </select>
        </div>
      </div>
    </section>

    <section class="card space-y-4">
      <h2 class="text-sm font-semibold text-slate-700">{{ t('trip.checkpoints') }}</h2>
      <div v-for="(row, i) in rows" :key="row.id" class="rounded-lg border border-slate-200 p-3">
        <div class="flex items-start gap-2">
          <span class="mt-7 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-brand-50 text-xs font-bold text-brand-700">
            {{ i + 1 }}
          </span>
          <div class="flex-1">
            <PlaceAutocomplete v-model="row.place" :label="`${t('trip.checkpoints')} ${i + 1}`"
                               :allow-current-location="i === 0" />
          </div>
        </div>
        <div class="mt-2 flex gap-2 text-xs">
          <button type="button" class="btn-ghost px-2 py-1" :disabled="i === 0" @click="move(i, -1)">{{ t('trip.moveUp') }}</button>
          <button type="button" class="btn-ghost px-2 py-1" :disabled="i === rows.length - 1" @click="move(i, 1)">{{ t('trip.moveDown') }}</button>
          <button type="button" class="btn-ghost px-2 py-1 text-red-600" :disabled="rows.length <= 2" @click="remove(i)">{{ t('trip.removeCheckpoint') }}</button>
        </div>
      </div>
      <button type="button" class="btn-secondary" @click="add">{{ t('trip.addCheckpoint') }}</button>
      <div>
        <p class="label">{{ t('trip.pickOnMap') }}</p>
        <MapView
          :markers="rows.filter(r => r.place).map(r => ({ lat: r.place!.point.lat, lng: r.place!.point.lng }))"
          @pick="pickOnMap" />
      </div>
    </section>

    <p class="text-xs text-slate-500">{{ t('trip.pricingHint') }}</p>
    <button class="btn-primary w-full" type="submit" :disabled="busy">{{ t('common.next') }}</button>
  </form>
</template>
