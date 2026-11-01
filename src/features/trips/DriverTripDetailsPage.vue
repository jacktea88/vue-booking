<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AsyncSection from '@/components/AsyncSection.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import TransferDialog from '@/features/transfers/TransferDialog.vue'
import RatingForm from '@/features/ratings/RatingForm.vue'
import { bookingService, tripService } from '@/services/domain'
import { useAsync } from '@/composables/useAsync'
import { useToast } from '@/composables/useToast'
import { formatDateTime, formatDzd } from '@/utils/format'
import { toAppError } from '@/types/errors'
import type { TripDetails } from '@/types'
import type { BookingWithTrip } from '@/services/domain/bookingService'

const props = defineProps<{ id: string }>()
const { t, locale } = useI18n()
const toast = useToast()

const bookings = ref<BookingWithTrip[]>([])
const prices = ref<Record<string, number>>({})
const busy = ref(false)
const transferFor = ref<string | null>(null)

const view = useAsync<TripDetails>(async () => {
  const d = await tripService.getDetails(props.id)
  bookings.value = await bookingService.listTripBookings(props.id)
  prices.value = Object.fromEntries(d.segments.map((s) => [s.id, Number(s.driver_price)]))
  return d
}, (d) => !d)

const trip = computed(() => view.data.value?.trip ?? null)
const checkpointName = (id: string) => view.data.value?.checkpoints.find((c) => c.id === id)?.name ?? '—'
const pendingRequests = computed(() => bookings.value.filter((b) => b.status === 'pending'))

async function savePrice(segmentId: string) {
  try { await tripService.setSegmentPrice(segmentId, prices.value[segmentId]); toast.success(t('profile.saved')) }
  catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

async function act(fn: () => Promise<unknown>) {
  busy.value = true
  try { await fn(); await view.run() }
  catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}

onMounted(() => view.run())
</script>

<template>
  <AsyncSection :state="view.state.value" :error="view.error.value" @retry="view.run()">
    <div v-if="view.data.value && trip" class="d-flex flex-column gap-4">
      <section class="card card-body rounded-3 shadow-sm">
        <div class="d-flex align-items-start justify-content-between gap-3">
          <div>
            <h1 class="fs-5 fw-bold mb-0">{{ t('trip.details') }}</h1>
            <p class="mt-1 mb-0 small text-secondary">{{ formatDateTime(trip.departure_at, locale) }}</p>
          </div>
          <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
        </div>
        <div class="mt-3 d-flex flex-wrap gap-2">
          <button v-if="trip.status === 'draft'" class="btn btn-primary" :disabled="busy" @click="act(() => tripService.publishTrip(id))">{{ t('trip.publish') }}</button>
          <button v-if="trip.status === 'published'" class="btn btn-primary" :disabled="busy" @click="act(() => tripService.startTrip(id))">{{ t('trip.start') }}</button>
          <button v-if="trip.status === 'in_progress'" class="btn btn-primary" :disabled="busy" @click="act(() => tripService.completeTrip(id))">{{ t('trip.complete') }}</button>
          <button v-if="['draft','published','boarding'].includes(trip.status)" class="btn btn-danger" :disabled="busy" @click="act(() => tripService.cancelTrip(id))">{{ t('trip.cancelTrip') }}</button>
        </div>
      </section>

      <section class="card card-body rounded-3 shadow-sm">
        <h2 class="fs-6 fw-semibold mb-0">{{ t('trip.segments') }}</h2>
        <p class="mt-1 mb-0 small text-secondary">{{ t('trip.pricingHint') }}</p>
        <div class="mt-3 d-flex flex-column gap-3">
          <div v-for="s in view.data.value.segments" :key="s.id" class="rounded-3 border p-3">
            <p class="small fw-medium mb-0">{{ checkpointName(s.from_checkpoint_id) }} → {{ checkpointName(s.to_checkpoint_id) }}</p>
            <p class="mt-1 mb-0 small text-secondary">
              {{ s.distance_km }} {{ t('common.km') }} · {{ s.estimated_minutes }} {{ t('common.min') }} ·
              {{ t('trip.referencePrice') }} {{ formatDzd(s.reference_price, locale) }} ·
              {{ s.reserved_seats }}/{{ s.capacity }} {{ t('common.seats') }}
            </p>
            <div class="mt-2 d-flex align-items-end gap-2">
              <div class="flex-grow-1">
                <label class="form-label" :for="`p-${s.id}`">{{ t('trip.yourPrice') }}</label>
                <input :id="`p-${s.id}`" v-model.number="prices[s.id]" class="form-control" type="number" min="0" step="50"
                       :disabled="trip.status !== 'draft'" />
              </div>
              <button class="btn btn-outline-secondary" :disabled="trip.status !== 'draft'" @click="savePrice(s.id)">{{ t('common.save') }}</button>
            </div>
          </div>
        </div>
      </section>

      <section class="card card-body rounded-3 shadow-sm">
        <h2 class="fs-6 fw-semibold mb-0">{{ t('booking.requests') }}</h2>
        <p v-if="!bookings.length" class="mt-2 mb-0 small text-secondary">{{ t('states.empty') }}</p>
        <ul class="list-unstyled d-flex flex-column gap-3 mt-3 mb-0">
          <li v-for="b in bookings" :key="b.id" class="rounded-3 border p-3">
            <div class="d-flex align-items-start justify-content-between gap-3">
              <div>
                <p class="small fw-medium mb-0">{{ b.pickup?.name }} → {{ b.dropoff?.name }}</p>
                <p class="mt-1 mb-0 small text-secondary">
                  {{ t('booking.seatsLabel', { n: b.seats }) }} · {{ formatDzd(b.total_amount, locale) }} ·
                  {{ t(`booking.source.${b.source}`) }}
                </p>
              </div>
              <StatusBadge :status="b.status" :label="t(`booking.status.${b.status}`)" />
            </div>
            <div class="mt-2 d-flex flex-wrap gap-2">
              <template v-if="b.status === 'pending'">
                <button class="btn btn-primary btn-sm" :disabled="busy" @click="act(() => bookingService.confirm(b.id))">{{ t('booking.accept') }}</button>
                <button class="btn btn-outline-secondary btn-sm" :disabled="busy" @click="act(() => bookingService.reject(b.id))">{{ t('booking.reject') }}</button>
              </template>
              <template v-if="b.status === 'confirmed'">
                <button class="btn btn-outline-secondary btn-sm" @click="transferFor = b.id">{{ t('transfer.request') }}</button>
                <button class="btn btn-link btn-sm text-danger text-decoration-none" :disabled="busy" @click="act(() => bookingService.markNoShow(b.id))">{{ t('booking.noShow') }}</button>
              </template>
            </div>
            <RatingForm v-if="b.status === 'completed'" class="mt-3" :booking-id="b.id" :title="t('rating.rateClient')" @rated="view.run()" />
          </li>
        </ul>
      </section>

      <TransferDialog v-if="transferFor" :booking-id="transferFor"
                      @close="transferFor = null" @requested="transferFor = null; view.run()" />
    </div>
  </AsyncSection>
</template>
