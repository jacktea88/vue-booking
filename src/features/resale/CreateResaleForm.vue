<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { resaleService } from '@/services/domain'
import { useToast } from '@/composables/useToast'
import { toAppError } from '@/types/errors'
import { formatDzd } from '@/utils/format'

const props = defineProps<{ bookingId: string; maxSeats: number; maxPrice: number }>()
const emit = defineEmits<{ created: [] }>()
const { t, locale } = useI18n()
const toast = useToast()
const seats = ref(1)
const price = ref(props.maxPrice)
const busy = ref(false)

async function submit() {
  busy.value = true
  try {
    await resaleService.createListing(props.bookingId, seats.value, price.value)
    toast.success(t('resale.created'))
    emit('created')
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}
</script>

<template>
  <form class="card card-body rounded-3 shadow-sm" @submit.prevent="submit">
    <h2 class="fs-6 fw-semibold mb-0">{{ t('resale.create') }}</h2>
    <div class="mt-3 row g-3">
      <div class="col-sm-6">
        <label class="form-label" for="rs-seats">{{ t('resale.seatsForSale') }}</label>
        <input id="rs-seats" v-model.number="seats" class="form-control" type="number" min="1" :max="maxSeats" required />
      </div>
      <div class="col-sm-6">
        <label class="form-label" for="rs-price">{{ t('resale.pricePerSeat') }}</label>
        <input id="rs-price" v-model.number="price" class="form-control" type="number" min="0" :max="maxPrice" step="50" required />
        <p class="mt-1 mb-0 fs-xs text-secondary">{{ t('resale.maxPrice', { amount: formatDzd(maxPrice, locale) }) }}</p>
      </div>
    </div>
    <button class="btn btn-primary mt-3" type="submit" :disabled="busy">{{ t('common.submit') }}</button>
  </form>
</template>
