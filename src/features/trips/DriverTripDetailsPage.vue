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
    <div v-if="view.data.value && trip" class="space-y-4">
      <section class="card">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h1 class="text-lg font-bold">{{ t('trip.details') }}</h1>
            <p class="mt-1 text-sm text-slate-500">{{ formatDateTime(trip.departure_at, locale) }}</p>
          </div>
          <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
        </div>
        <div class="mt-4 flex flex-wrap gap-2">
          <button v-if="trip.status === 'draft'" class="btn-primary" :disabled="busy" @click="act(() => tripService.publishTrip(id))">{{ t('trip.publish') }}</button>
          <button v-if="trip.status === 'published'" class="btn-primary" :disabled="busy" @click="act(() => tripService.startTrip(id))">{{ t('trip.start') }}</button>
          <button v-if="trip.status === 'in_progress'" class="btn-primary" :disabled="busy" @click="act(() => tripService.completeTrip(id))">{{ t('trip.complete') }}</button>
          <button v-if="['draft','published','boarding'].includes(trip.status)" class="btn-danger" :disabled="busy" @click="act(() => tripService.cancelTrip(id))">{{ t('trip.cancelTrip') }}</button>
        </div>
      </section>

      <section class="card">
        <h2 class="text-sm font-semibold text-slate-700">{{ t('trip.segments') }}</h2>
        <p class="mt-1 text-xs text-slate-500">{{ t('trip.pricingHint') }}</p>
        <div class="mt-3 space-y-3">
          <div v-for="s in view.data.value.segments" :key="s.id" class="rounded-lg border border-slate-200 p-3">
            <p class="text-sm font-medium">{{ checkpointName(s.from_checkpoint_id) }} → {{ checkpointName(s.to_checkpoint_id) }}</p>
            <p class="mt-1 text-xs text-slate-500">
              {{ s.distance_km }} {{ t('common.km') }} · {{ s.estimated_minutes }} {{ t('common.min') }} ·
              {{ t('trip.referencePrice') }} {{ formatDzd(s.reference_price, locale) }} ·
              {{ s.reserved_seats }}/{{ s.capacity }} {{ t('common.seats') }}
            </p>
            <div class="mt-2 flex items-end gap-2">
              <div class="flex-1">
                <label class="label" :for="`p-${s.id}`">{{ t('trip.yourPrice') }}</label>
                <input :id="`p-${s.id}`" v-model.number="prices[s.id]" class="field" type="number" min="0" step="50"
                       :disabled="trip.status !== 'draft'" />
              </div>
              <button class="btn-secondary" :disabled="trip.status !== 'draft'" @click="savePrice(s.id)">{{ t('common.save') }}</button>
            </div>
          </div>
        </div>
      </section>

      <section class="card">
        <h2 class="text-sm font-semibold text-slate-700">{{ t('booking.requests') }}</h2>
        <p v-if="!bookings.length" class="mt-2 text-sm text-slate-500">{{ t('states.empty') }}</p>
        <ul class="mt-3 space-y-3">
          <li v-for="b in bookings" :key="b.id" class="rounded-lg border border-slate-200 p-3">
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-sm font-medium">{{ b.pickup?.name }} → {{ b.dropoff?.name }}</p>
                <p class="mt-0.5 text-xs text-slate-500">
                  {{ t('booking.seatsLabel', { n: b.seats }) }} · {{ formatDzd(b.total_amount, locale) }} ·
                  {{ t(`booking.source.${b.source}`) }}
                </p>
              </div>
              <StatusBadge :status="b.status" :label="t(`booking.status.${b.status}`)" />
            </div>
            <div class="mt-2 flex flex-wrap gap-2">
              <template v-if="b.status === 'pending'">
                <button class="btn-primary px-3 py-1.5" :disabled="busy" @click="act(() => bookingService.confirm(b.id))">{{ t('booking.accept') }}</button>
                <button class="btn-secondary px-3 py-1.5" :disabled="busy" @click="act(() => bookingService.reject(b.id))">{{ t('booking.reject') }}</button>
              </template>
              <template v-if="b.status === 'confirmed'">
                <button class="btn-secondary px-3 py-1.5" @click="transferFor = b.id">{{ t('transfer.request') }}</button>
                <button class="btn-ghost px-3 py-1.5 text-red-600" :disabled="busy" @click="act(() => bookingService.markNoShow(b.id))">{{ t('booking.noShow') }}</button>
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
