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

/** Books then goes to checkout. Seats are reserved atomically server-side. */
async function book() {
  booking.value = true
  try {
    const res = await bookingService.createBooking(props.id, pickupId.value, dropoffId.value, seats.value)
    await router.push({ name: 'checkout', params: { bookingId: res.booking_id } })
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
    <div v-if="details.data.value" class="space-y-5 lg:grid lg:grid-cols-3 lg:gap-6 lg:space-y-0">
      <div class="space-y-5 lg:col-span-2">
        <section class="card">
          <h1 class="text-lg font-bold">{{ t('trip.details') }}</h1>
          <p class="mt-1 text-sm text-slate-600">{{ formatDateTime(details.data.value.trip.departure_at, locale) }}</p>
          <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
            <span class="badge bg-brand-50 text-brand-700">{{ t(`search.bookingMode.${details.data.value.trip.booking_mode}`) }}</span>
            <span class="badge bg-slate-100 text-slate-700">{{ t(`trip.status.${details.data.value.trip.status}`) }}</span>
          </div>
          <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
            <div><dt class="text-slate-500">{{ t('trip.driver') }}</dt>
              <dd class="font-medium">{{ details.data.value.driver.full_name }} ★ {{ Number(details.data.value.driver.rating_avg).toFixed(1) }}</dd></div>
            <div><dt class="text-slate-500">{{ t('trip.vehicle') }}</dt>
              <dd class="font-medium">{{ details.data.value.vehicle.brand }} {{ details.data.value.vehicle.model }} · {{ details.data.value.vehicle.color }}</dd></div>
          </dl>
        </section>

        <section class="card">
          <h2 class="text-sm font-semibold text-slate-700">{{ t('trip.checkpoints') }}</h2>
          <ol class="mt-3 space-y-2">
            <li v-for="c in checkpoints" :key="c.id" class="flex items-center gap-3 text-sm">
              <span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-brand-50 text-xs font-bold text-brand-700">
                {{ c.sequence + 1 }}</span>
              <span class="flex-1">{{ c.name }}</span>
              <span class="text-xs text-slate-500">{{ formatDateTime(c.estimated_arrival, locale) }}</span>
            </li>
          </ol>
          <MapView class="mt-4" :markers="markers" :center="markers[0]" />
        </section>
      </div>

      <aside class="lg:col-span-1">
        <section class="card lg:sticky lg:top-20">
          <h2 class="text-sm font-semibold text-slate-700">{{ t('trip.book') }}</h2>
          <div class="mt-3 space-y-3">
            <div>
              <label class="label" for="pickup">{{ t('trip.pickup') }}</label>
              <select id="pickup" v-model="pickupId" class="field">
                <option v-for="c in checkpoints" :key="c.id" :value="c.id">{{ c.sequence + 1 }}. {{ c.name }}</option>
              </select>
            </div>
            <div>
              <label class="label" for="dropoff">{{ t('trip.dropoff') }}</label>
              <select id="dropoff" v-model="dropoffId" class="field">
                <option v-for="c in checkpoints" :key="c.id" :value="c.id">{{ c.sequence + 1 }}. {{ c.name }}</option>
              </select>
            </div>
            <SeatStepper v-model="seats" :max="Math.max(1, quote?.available_seats ?? 1)" :label="t('common.seats')" />
            <div v-if="quote" class="rounded-lg bg-slate-50 p-3 text-sm">
              <div class="flex justify-between"><span>{{ t('booking.pricePerSeat') }}</span><span class="font-medium">{{ formatDzd(quote.price_per_seat, locale) }}</span></div>
              <div class="mt-1 flex justify-between"><span>{{ t('booking.totalAmount') }}</span><span class="font-bold text-brand-700">{{ formatDzd(quote.total_amount, locale) }}</span></div>
              <p class="mt-2 text-xs text-slate-500">{{ t('search.availableSeats', { n: quote.available_seats }) }}</p>
            </div>
            <p class="text-xs text-slate-500">{{ t('booking.onlineOnly') }}</p>
            <button class="btn-primary w-full" :disabled="booking || !quote || quote.available_seats < seats" @click="book">
              {{ t('trip.book') }}
            </button>
          </div>
        </section>
      </aside>
    </div>
  </AsyncSection>
</template>
