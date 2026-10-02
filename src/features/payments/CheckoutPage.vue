<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import AsyncSection from '@/components/AsyncSection.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { bookingService } from '@/services/domain'
import { useAsync } from '@/composables/useAsync'
import { useToast } from '@/composables/useToast'
import { formatDzd } from '@/utils/format'
import { toAppError } from '@/types/errors'
import type { BookingPayment } from '@/types'
import type { BookingWithTrip } from '@/services/domain/bookingService'

const props = defineProps<{ bookingId: string }>()
const { t, locale } = useI18n()
const router = useRouter()
const toast = useToast()

const payment = ref<BookingPayment | null>(null)
const paying = ref(false)

const booking = useAsync<BookingWithTrip>(async () => {
  const b = await bookingService.getBooking(props.bookingId)
  payment.value = await bookingService.getPayment(props.bookingId)
  return b
}, (b) => !b)

/** Payment is executed through the provider adapter; state transition is server-side. */
async function pay() {
  if (!booking.data.value || !payment.value) return
  paying.value = true
  try {
    await bookingService.payBooking({
      payment_id: payment.value.id,
      booking_id: booking.data.value.id,
      amount: payment.value.amount,
      booking_mode: (booking.data.value.trips?.booking_mode as 'auto_confirm' | 'driver_approval') ?? 'auto_confirm',
    })
    toast.success(t('booking.paid'))
    await router.replace({ name: 'booking-details', params: { id: props.bookingId } })
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { paying.value = false }
}

onMounted(() => booking.run())
</script>

<template>
  <AsyncSection :state="booking.state.value" :error="booking.error.value" @retry="booking.run()">
    <section v-if="booking.data.value" class="card mx-auto max-w-md">
      <h1 class="text-lg font-bold">{{ t('payment.title') }}</h1>
      <div class="mt-4 space-y-2 text-sm">
        <div class="flex justify-between"><span class="text-slate-500">{{ t('trip.pickup') }}</span><span>{{ booking.data.value.pickup?.name }}</span></div>
        <div class="flex justify-between"><span class="text-slate-500">{{ t('trip.dropoff') }}</span><span>{{ booking.data.value.dropoff?.name }}</span></div>
        <div class="flex justify-between"><span class="text-slate-500">{{ t('common.seats') }}</span><span>{{ booking.data.value.seats }}</span></div>
        <div class="flex justify-between"><span class="text-slate-500">{{ t('booking.pricePerSeat') }}</span><span>{{ formatDzd(booking.data.value.price_per_seat, locale) }}</span></div>
        <div class="flex justify-between border-t border-slate-100 pt-2 text-base font-bold">
          <span>{{ t('booking.totalAmount') }}</span><span class="text-brand-700">{{ formatDzd(booking.data.value.total_amount, locale) }}</span>
        </div>
      </div>

      <div v-if="payment" class="mt-4 flex items-center justify-between rounded-lg bg-slate-50 p-3 text-sm">
        <span>{{ t('common.status') }}</span>
        <StatusBadge :status="payment.status" :label="t(`payment.status.${payment.status}`)" />
      </div>

      <p class="mt-3 text-xs text-slate-500">{{ t('booking.onlineOnly') }}</p>
      <p class="text-xs text-slate-400">{{ t('payment.mockNotice') }}</p>

      <button v-if="payment && ['requires_payment', 'failed', 'expired'].includes(payment.status)"
              class="btn-primary mt-4 w-full" :disabled="paying" @click="pay">
        {{ paying ? t('booking.paying') : t('booking.payNow') }}
      </button>
      <RouterLink v-else class="btn-secondary mt-4 w-full" :to="{ name: 'booking-details', params: { id: bookingId } }">
        {{ t('common.details') }}
      </RouterLink>
    </section>
  </AsyncSection>
</template>
