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
  <div class="d-flex flex-column gap-4">
    <h1 class="fs-4 fw-bold">{{ t('search.title') }}</h1>

    <form class="card card-body rounded-3 shadow-sm d-flex flex-column gap-3" @submit.prevent="submit">
      <PlaceAutocomplete v-model="from" :label="t('common.from')" :placeholder="t('search.fromPlaceholder')" allow-current-location />
      <PlaceAutocomplete v-model="to" :label="t('common.to')" :placeholder="t('search.toPlaceholder')" />
      <div class="row g-3">
        <div class="col-sm-6">
          <label class="form-label" for="date">{{ t('common.date') }}</label>
          <input id="date" v-model="date" class="form-control" type="date" :min="todayIso()" required />
        </div>
        <div class="col-sm-6">
          <SeatStepper v-model="seats" :max="MAX_SEATS_PER_BOOKING" :label="t('common.seats')" />
        </div>
      </div>
      <button class="btn btn-primary w-100" type="submit">{{ t('common.search') }}</button>
    </form>

    <AsyncSection v-if="submitted" :state="results.state.value" :error="results.error.value"
                  :empty-text="t('search.noResults')" @retry="results.run()">
      <p class="mb-2 small text-secondary">{{ t('search.results', { count: results.data.value?.length ?? 0 }) }}</p>
      <ul class="list-unstyled d-flex flex-column gap-3 mb-0">
        <li v-for="r in results.data.value ?? []" :key="r.trip_id">
          <RouterLink class="card card-body rounded-3 shadow-sm text-body text-decoration-none hover-border-primary d-block"
            :to="{ name: 'trip-details', params: { id: r.trip_id },
                   query: { pickup: r.pickup_checkpoint_id, dropoff: r.dropoff_checkpoint_id, seats } }">
            <div class="d-flex align-items-start justify-content-between gap-3">
              <div class="min-w-0">
                <p class="text-truncate fw-medium mb-0">{{ r.pickup_name }} → {{ r.dropoff_name }}</p>
                <p class="mt-1 small text-secondary mb-0">
                  {{ formatDateTime(r.departure_at, locale) }} · {{ r.total_distance_km }} {{ t('common.km') }}
                </p>
                <p class="mt-1 small text-secondary mb-0">
                  {{ r.driver_name }} ★ {{ Number(r.driver_rating).toFixed(1) }} ·
                  {{ r.vehicle_brand }} {{ r.vehicle_model }}
                </p>
              </div>
              <div class="text-end flex-shrink-0">
                <p class="fs-6 fw-bold text-primary mb-0">{{ formatDzd(r.price_per_seat, locale) }}</p>
                <p class="fs-xs text-secondary mb-0">{{ t('common.perSeat') }}</p>
              </div>
            </div>
            <div class="mt-3 d-flex flex-wrap align-items-center gap-2 fs-xs">
              <span class="badge rounded-pill bg-secondary-subtle text-secondary-emphasis fw-medium">{{ t('search.availableSeats', { n: r.available_seats }) }}</span>
              <span class="badge rounded-pill bg-brand-light text-primary fw-medium">{{ t(`search.bookingMode.${r.booking_mode}`) }}</span>
            </div>
          </RouterLink>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
