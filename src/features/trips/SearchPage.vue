<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import PlaceAutocomplete from '@/components/PlaceAutocomplete.vue'
import SeatStepper from '@/components/SeatStepper.vue'
import AsyncSection from '@/components/AsyncSection.vue'
import { tripService } from '@/services/domain'
import { useAsync } from '@/composables/useAsync'
import { formatDateTime, formatDzd, todayIso } from '@/utils/format'
import { MAX_SEATS_PER_BOOKING } from '@/utils/constants'
import type { PlaceResult, SearchTripRow } from '@/types'

const { t, locale } = useI18n()
const from = ref<PlaceResult | null>(null)
const to = ref<PlaceResult | null>(null)
const date = ref(todayIso())
const seats = ref(1)
const submitted = ref(false)

/** Matching happens entirely in PostgreSQL/PostGIS. Location is optional. */
const results = useAsync<SearchTripRow[]>(async () => {
  return tripService.search({ 
    from: from.value?.point ?? null, 
    to: to.value?.point ?? null, 
    date: date.value, 
    seats: seats.value 
  })
})

async function submit() { submitted.value = true; await results.run() }
</script>

<template>
  <div class="space-y-5">
    <h1 class="text-xl font-bold">{{ t('search.title') }}</h1>

    <form class="card space-y-4" @submit.prevent="submit">
      <PlaceAutocomplete v-model="from" :label="t('common.from')" :placeholder="t('search.fromPlaceholder')" allow-current-location />
      <PlaceAutocomplete v-model="to" :label="t('common.to')" :placeholder="t('search.toPlaceholder')" />
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="label" for="date">{{ t('common.date') }}</label>
          <input id="date" v-model="date" class="field" type="date" :min="todayIso()" required />
        </div>
        <SeatStepper v-model="seats" :max="MAX_SEATS_PER_BOOKING" :label="t('common.seats')" />
      </div>
      <button class="btn-primary w-full" type="submit">{{ t('common.search') }}</button>
    </form>

    <AsyncSection v-if="submitted" :state="results.state.value" :error="results.error.value"
                  :empty-text="t('search.noResults')" @retry="results.run()">
      <p class="mb-2 text-sm text-slate-600">{{ t('search.results', { count: results.data.value?.length ?? 0 }) }}</p>
      <ul class="space-y-3">
        <li v-for="r in results.data.value ?? []" :key="r.trip_id">
          <RouterLink class="card block hover:border-brand-600"
            :to="{ name: 'trip-details', params: { id: r.trip_id },
                   query: { pickup: r.pickup_checkpoint_id, dropoff: r.dropoff_checkpoint_id, seats } }">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="truncate font-medium">{{ r.pickup_name }} → {{ r.dropoff_name }}</p>
                <p class="mt-1 text-xs text-slate-500">
                  {{ formatDateTime(r.departure_at, locale) }} · {{ r.total_distance_km }} {{ t('common.km') }}
                </p>
                <p class="mt-1 text-xs text-slate-500">
                  {{ r.driver_name }} ★ {{ Number(r.driver_rating).toFixed(1) }} ·
                  {{ r.vehicle_brand }} {{ r.vehicle_model }}
                </p>
              </div>
              <div class="text-end">
                <p class="text-base font-bold text-brand-700">{{ formatDzd(r.price_per_seat, locale) }}</p>
                <p class="text-[11px] text-slate-500">{{ t('common.perSeat') }}</p>
              </div>
            </div>
            <div class="mt-3 flex flex-wrap items-center gap-2 text-[11px]">
              <span class="badge bg-slate-100 text-slate-700">{{ t('search.availableSeats', { n: r.available_seats }) }}</span>
              <span class="badge bg-brand-50 text-brand-700">{{ t(`search.bookingMode.${r.booking_mode}`) }}</span>
            </div>
          </RouterLink>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
