<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import AsyncSection from '@/components/AsyncSection.vue'
import SeatStepper from '@/components/SeatStepper.vue'
import MapView from '@/components/MapView.vue'
import { bookingService, tripService } from '@/services/domain'
import { useAsync } from '@/composables/useAsync'
import { useToast } from '@/composables/useToast'
import { formatDateTime, formatDzd } from '@/utils/format'
import { toAppError } from '@/types/errors'
import type { BookingQuote, TripDetails } from '@/types'

const props = defineProps<{ id: string }>()
const { t, locale } = useI18n()
const route = useRoute()
const router = useRouter()
const toast = useToast()

const details = useAsync<TripDetails>(() => tripService.getDetails(props.id), (d) => !d)
const pickupId = ref<string>((route.query.pickup as string) || '')
const dropoffId = ref<string>((route.query.dropoff as string) || '')
const seats = ref(Number(route.query.seats ?? 1))
const quote = ref<BookingQuote | null>(null)
const booking = ref(false)

const checkpoints = computed(() => details.data.value?.checkpoints ?? [])
const markers = computed(() => checkpoints.value.map((c) => ({ lat: c.lat, lng: c.lng, label: String(c.sequence + 1) })))

async function refreshQuote() {
  quote.value = null
  if (!pickupId.value || !dropoffId.value) return
  try { quote.value = await bookingService.quote(props.id, pickupId.value, dropoffId.value, seats.value) }
  catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

/** Books the trip. Seats are reserved atomically server-side; status depends on the trip's booking mode. */
async function book() {
  booking.value = true
  try {
    const res = await bookingService.createBooking(props.id, pickupId.value, dropoffId.value, seats.value)
    toast.success(t(res.status === 'confirmed' ? 'booking.confirmed' : 'booking.pendingApproval'))
    await router.push({ name: 'booking-details', params: { id: res.booking_id } })
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { booking.value = false }
}

onMounted(async () => {
  await details.run()
  const cps = details.data.value?.checkpoints ?? []
  if (!pickupId.value && cps.length) pickupId.value = cps[0].id
  if (!dropoffId.value && cps.length > 1) dropoffId.value = cps[cps.length - 1].id
  await refreshQuote()
})
watch([pickupId, dropoffId, seats], refreshQuote)
</script>

<template>
  <AsyncSection :state="details.state.value" :error="details.error.value" @retry="details.run()">
    <div v-if="details.data.value" class="row g-4">
      <div class="col-lg-8 d-flex flex-column gap-4">
        <section class="card card-body rounded-3 shadow-sm">
          <h1 class="fs-5 fw-bold">{{ t('trip.details') }}</h1>
          <p class="mt-1 small text-secondary">{{ formatDateTime(details.data.value.trip.departure_at, locale) }}</p>
          <div class="mt-3 d-flex flex-wrap align-items-center gap-2 fs-xs">
            <span class="badge rounded-pill bg-brand-light text-primary fw-medium">{{ t(`search.bookingMode.${details.data.value.trip.booking_mode}`) }}</span>
            <span class="badge rounded-pill bg-secondary-subtle text-secondary-emphasis fw-medium">{{ t(`trip.status.${details.data.value.trip.status}`) }}</span>
          </div>
          <dl class="row row-cols-2 g-3 small mt-3 mb-0">
            <div class="col"><dt class="text-secondary">{{ t('trip.driver') }}</dt>
              <dd class="fw-medium mb-0">{{ details.data.value.driver.full_name }} ★ {{ Number(details.data.value.driver.rating_avg).toFixed(1) }}</dd></div>
            <div class="col"><dt class="text-secondary">{{ t('trip.vehicle') }}</dt>
              <dd class="fw-medium mb-0">{{ details.data.value.vehicle.brand }} {{ details.data.value.vehicle.model }} · {{ details.data.value.vehicle.color }}</dd></div>
          </dl>
        </section>

        <section class="card card-body rounded-3 shadow-sm">
          <h2 class="fs-6 fw-semibold mb-0">{{ t('trip.checkpoints') }}</h2>
          <ol class="list-unstyled d-flex flex-column gap-2 mt-3 mb-0">
            <li v-for="c in checkpoints" :key="c.id" class="d-flex align-items-center gap-3 small">
              <span class="d-inline-flex align-items-center justify-content-center flex-shrink-0 rounded-circle bg-brand-light text-primary fw-bold fs-xs"
                    style="width: 1.5rem; height: 1.5rem">
                {{ c.sequence + 1 }}</span>
              <span class="flex-grow-1">{{ c.name }}</span>
              <span class="fs-xs text-secondary">{{ formatDateTime(c.estimated_arrival, locale) }}</span>
            </li>
          </ol>
          <MapView class="mt-3" :markers="markers" :center="markers[0]" />
        </section>
      </div>

      <aside class="col-lg-4">
        <section class="card card-body rounded-3 shadow-sm position-sticky" style="top: 5rem">
          <h2 class="fs-6 fw-semibold mb-0">{{ t('trip.book') }}</h2>
          <div class="mt-3 d-flex flex-column gap-3">
            <div>
              <label class="form-label" for="pickup">{{ t('trip.pickup') }}</label>
              <select id="pickup" v-model="pickupId" class="form-select">
                <option v-for="c in checkpoints" :key="c.id" :value="c.id">{{ c.sequence + 1 }}. {{ c.name }}</option>
              </select>
            </div>
            <div>
              <label class="form-label" for="dropoff">{{ t('trip.dropoff') }}</label>
              <select id="dropoff" v-model="dropoffId" class="form-select">
                <option v-for="c in checkpoints" :key="c.id" :value="c.id">{{ c.sequence + 1 }}. {{ c.name }}</option>
              </select>
            </div>
            <SeatStepper v-model="seats" :max="Math.max(1, quote?.available_seats ?? 1)" :label="t('common.seats')" />
            <div v-if="quote" class="rounded-3 bg-light p-3 small">
              <div class="d-flex justify-content-between"><span>{{ t('booking.pricePerSeat') }}</span><span class="fw-medium">{{ formatDzd(quote.price_per_seat, locale) }}</span></div>
              <div class="mt-1 d-flex justify-content-between"><span>{{ t('booking.totalAmount') }}</span><span class="fw-bold text-primary">{{ formatDzd(quote.total_amount, locale) }}</span></div>
              <p class="mt-2 mb-0 fs-xs text-secondary">{{ t('search.availableSeats', { n: quote.available_seats }) }}</p>
            </div>
            <p class="small text-secondary mb-0">{{ t('booking.onlineOnly') }}</p>
            <button class="btn btn-primary w-100" :disabled="booking || !quote || quote.available_seats < seats" @click="book">
              {{ t('trip.book') }}
            </button>
          </div>
        </section>
      </aside>
    </div>
  </AsyncSection>
</template>
