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
import type { BookingPayment, CancellationQuote, Rating, ResaleListing, TransferRequest } from '@/types'
import type { BookingWithTrip } from '@/services/domain/bookingService'

const props = defineProps<{ id: string }>()
const { t, locale } = useI18n()
const toast = useToast()
const auth = useAuthStore()

const payment = ref<BookingPayment | null>(null)
const transfers = ref<TransferRequest[]>([])
const listings = ref<ResaleListing[]>([])
const ratings = ref<Rating[]>([])
const cancelQuote = ref<CancellationQuote | null>(null)
const showCancel = ref(false)
const busy = ref(false)

const view = useAsync<BookingWithTrip>(async () => {
  const b = await bookingService.getBooking(props.id)
  payment.value = await bookingService.getPayment(props.id)
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
  try { cancelQuote.value = await bookingService.cancellationQuote(props.id); showCancel.value = true }
  catch (e) { toast.error(t(toAppError(e).i18nKey)) }
}

async function doCancel() {
  busy.value = true
  try {
    const res = await bookingService.cancel(props.id)
    toast.success(res.refund_amount > 0 ? t('payment.refunded', { amount: res.refund_amount }) : t('common.confirm'))
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
    <div v-if="view.data.value" class="space-y-4">
      <section class="card">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h1 class="text-lg font-bold">{{ view.data.value.pickup?.name }} → {{ view.data.value.dropoff?.name }}</h1>
            <p class="mt-1 text-sm text-slate-500">{{ formatDateTime(view.data.value.trips?.departure_at, locale) }}</p>
          </div>
          <StatusBadge :status="view.data.value.status" :label="t(`booking.status.${view.data.value.status}`)" />
        </div>
        <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
          <div><dt class="text-slate-500">{{ t('common.seats') }}</dt><dd class="font-medium">{{ view.data.value.seats }}</dd></div>
          <div><dt class="text-slate-500">{{ t('booking.pricePerSeat') }}</dt><dd class="font-medium">{{ formatDzd(view.data.value.price_per_seat, locale) }}</dd></div>
          <div><dt class="text-slate-500">{{ t('booking.totalAmount') }}</dt><dd class="font-bold text-brand-700">{{ formatDzd(view.data.value.total_amount, locale) }}</dd></div>
          <div v-if="payment"><dt class="text-slate-500">{{ t('payment.title') }}</dt>
            <dd><StatusBadge :status="payment.status" :label="t(`payment.status.${payment.status}`)" /></dd></div>
        </dl>
        <p v-if="payment && payment.refunded_amount > 0" class="mt-2 text-sm text-violet-700">
          {{ t('payment.refunded', { amount: payment.refunded_amount }) }}
        </p>
        <p v-if="view.data.value.status === 'pending' && view.data.value.approval_expires_at"
           class="mt-2 text-xs text-amber-700">
          {{ t('booking.expiresIn', { time: formatDateTime(view.data.value.approval_expires_at, locale) }) }}
        </p>

        <div class="mt-4 flex flex-wrap gap-2">
          <RouterLink v-if="payment && ['requires_payment','failed','expired'].includes(payment.status) && ['pending'].includes(view.data.value.status)"
                      class="btn-primary" :to="{ name: 'checkout', params: { bookingId: id } }">{{ t('booking.payNow') }}</RouterLink>
          <button v-if="['pending','confirmed'].includes(view.data.value.status)" class="btn-danger" @click="openCancel">
            {{ t('booking.cancel') }}
          </button>
        </div>
      </section>

      <section v-if="pendingTransfer" class="card border-amber-300 bg-amber-50/50">
        <h2 class="text-sm font-semibold">{{ t('transfer.pending') }}</h2>
        <p class="mt-1 text-sm text-slate-600">{{ t('transfer.priceUnchanged') }}</p>
        <div class="mt-3 flex gap-2">
          <button class="btn-primary" :disabled="busy" @click="respondTransfer(true)">{{ t('transfer.approve') }}</button>
          <button class="btn-secondary" :disabled="busy" @click="respondTransfer(false)">{{ t('transfer.reject') }}</button>
        </div>
      </section>

      <section v-if="openListing" class="card">
        <h2 class="text-sm font-semibold">{{ t('resale.title') }}</h2>
        <p class="mt-1 text-sm">{{ t('resale.sold', { sold: openListing.seats_sold, total: openListing.seats_for_sale }) }}
          · {{ formatDzd(openListing.price_per_seat, locale) }}</p>
        <button class="btn-secondary mt-3" @click="cancelListingNow(openListing.id)">{{ t('resale.cancelListing') }}</button>
      </section>

      <CreateResaleForm v-else-if="canResell" :booking-id="id" :max-seats="view.data.value.seats"
                        :max-price="view.data.value.price_per_seat" @created="view.run()" />

      <RatingForm v-if="view.data.value.status === 'completed' && !alreadyRated"
                  :booking-id="id" :title="t('rating.rateDriver')" @rated="view.run()" />

      <ConfirmDialog :open="showCancel" :title="t('booking.cancel')" danger :busy="busy"
                     :message="cancelQuote?.eligible
                       ? t('booking.cancelRefund', { amount: cancelQuote.refund_amount, pct: cancelQuote.refund_percentage })
                       : t('booking.cancelNoRefund')"
                     @close="showCancel = false" @confirm="doCancel" />
    </div>
  </AsyncSection>
</template>
