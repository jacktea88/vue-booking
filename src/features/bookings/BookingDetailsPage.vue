<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AsyncSection from '@/components/AsyncSection.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import CreateResaleForm from '@/features/resale/CreateResaleForm.vue'
import RatingForm from '@/features/ratings/RatingForm.vue'
import { bookingService, ratingService, resaleService, transferService } from '@/services/domain'
import { useAsync } from '@/composables/useAsync'
import { useToast } from '@/composables/useToast'
import { useAuthStore } from '@/stores/auth'
import { formatDateTime, formatDzd } from '@/utils/format'
import { toAppError } from '@/types/errors'
import type { CancellationQuote, Rating, ResaleListing, TransferRequest } from '@/types'
import type { BookingWithTrip } from '@/services/domain/bookingService'

const props = defineProps<{ id: string }>()
const { t, locale } = useI18n()
const toast = useToast()
const auth = useAuthStore()

const transfers = ref<TransferRequest[]>([])
const listings = ref<ResaleListing[]>([])
const ratings = ref<Rating[]>([])
const cancelQuote = ref<CancellationQuote | null>(null)
const showCancel = ref(false)
const busy = ref(false)

const view = useAsync<BookingWithTrip>(async () => {
  const b = await bookingService.getBooking(props.id)
  transfers.value = await transferService.listForBooking(props.id)
  listings.value = (await resaleService.listForSeller(b.client_id)).filter((l) => l.booking_id === props.id)
  ratings.value = await ratingService.listForBooking(props.id)
  return b
}, (b) => !b)

const pendingTransfer = computed(() => transfers.value.find((x) => x.status === 'pending') ?? null)
const openListing = computed(() => listings.value.find((l) => l.status === 'open') ?? null)
const alreadyRated = computed(() => ratings.value.some((r) => r.from_user_id === auth.user?.id))
const canResell = computed(() => view.data.value?.status === 'confirmed' && !pendingTransfer.value && !openListing.value)

async function openCancel() {
  try {
    cancelQuote.value = await bookingService.cancellationQuote(props.id)
    if (!cancelQuote.value.eligible) { toast.error(t('errors.CANCELLATION_WINDOW_CLOSED')); return }
    showCancel.value = true
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

async function doCancel() {
  busy.value = true
  try {
    await bookingService.cancel(props.id)
    toast.success(t('booking.cancelled'))
    showCancel.value = false
    await view.run()
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}

async function respondTransfer(approve: boolean) {
  if (!pendingTransfer.value) return
  busy.value = true
  try {
    if (approve) await transferService.approve(pendingTransfer.value.id)
    else await transferService.reject(pendingTransfer.value.id)
    toast.success(t(approve ? 'transfer.approved' : 'transfer.reject'))
    await view.run()
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}

async function cancelListingNow(id: string) {
  try { await resaleService.cancelListing(id); await view.run() }
  catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

onMounted(() => view.run())
</script>

<template>
  <AsyncSection :state="view.state.value" :error="view.error.value" @retry="view.run()">
    <div v-if="view.data.value" class="d-flex flex-column gap-4">
      <section class="card card-body rounded-3 shadow-sm">
        <div class="d-flex align-items-start justify-content-between gap-3">
          <div>
            <h1 class="fs-5 fw-bold">{{ view.data.value.pickup?.name }} → {{ view.data.value.dropoff?.name }}</h1>
            <p class="mt-1 small text-secondary">{{ formatDateTime(view.data.value.trips?.departure_at, locale) }}</p>
          </div>
          <StatusBadge :status="view.data.value.status" :label="t(`booking.status.${view.data.value.status}`)" />
        </div>
        <dl class="row row-cols-2 g-3 small mt-3 mb-0">
          <div class="col"><dt class="text-secondary">{{ t('common.seats') }}</dt><dd class="fw-medium mb-0">{{ view.data.value.seats }}</dd></div>
          <div class="col"><dt class="text-secondary">{{ t('booking.pricePerSeat') }}</dt><dd class="fw-medium mb-0">{{ formatDzd(view.data.value.price_per_seat, locale) }}</dd></div>
          <div class="col"><dt class="text-secondary">{{ t('booking.totalAmount') }}</dt><dd class="fw-bold text-primary mb-0">{{ formatDzd(view.data.value.total_amount, locale) }}</dd></div>
        </dl>
        <p v-if="view.data.value.status === 'pending' && view.data.value.approval_expires_at"
           class="mt-2 mb-0 small text-warning-emphasis">
          {{ t('booking.expiresIn', { time: formatDateTime(view.data.value.approval_expires_at, locale) }) }}
        </p>

        <div class="mt-3 d-flex flex-wrap gap-2">
          <button v-if="['pending','confirmed'].includes(view.data.value.status)" class="btn btn-danger" @click="openCancel">
            {{ t('booking.cancel') }}
          </button>
        </div>
      </section>

      <section v-if="pendingTransfer" class="card card-body rounded-3 shadow-sm border-amber-300 bg-amber-light">
        <h2 class="small fw-semibold mb-0">{{ t('transfer.pending') }}</h2>
        <p class="mt-1 small text-secondary mb-0">{{ t('transfer.priceUnchanged') }}</p>
        <div class="mt-3 d-flex gap-2">
          <button class="btn btn-primary" :disabled="busy" @click="respondTransfer(true)">{{ t('transfer.approve') }}</button>
          <button class="btn btn-outline-secondary" :disabled="busy" @click="respondTransfer(false)">{{ t('transfer.reject') }}</button>
        </div>
      </section>

      <section v-if="openListing" class="card card-body rounded-3 shadow-sm">
        <h2 class="small fw-semibold mb-0">{{ t('resale.title') }}</h2>
        <p class="mt-1 small mb-0">{{ t('resale.sold', { sold: openListing.seats_sold, total: openListing.seats_for_sale }) }}
          · {{ formatDzd(openListing.price_per_seat, locale) }}</p>
        <button class="btn btn-outline-secondary mt-3" @click="cancelListingNow(openListing.id)">{{ t('resale.cancelListing') }}</button>
      </section>

      <CreateResaleForm v-else-if="canResell" :booking-id="id" :max-seats="view.data.value.seats"
                        :max-price="view.data.value.price_per_seat" @created="view.run()" />

      <RatingForm v-if="view.data.value.status === 'completed' && !alreadyRated"
                  :booking-id="id" :title="t('rating.rateDriver')" @rated="view.run()" />

      <ConfirmDialog :open="showCancel" :title="t('booking.cancel')" danger :busy="busy"
                     :message="t('booking.cancelConfirm')"
                     @close="showCancel = false" @confirm="doCancel" />
    </div>
  </AsyncSection>
</template>
