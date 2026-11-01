<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AsyncSection from '@/components/AsyncSection.vue'
import { resaleService } from '@/services/domain'
import { useAsync } from '@/composables/useAsync'
import { useToast } from '@/composables/useToast'
import { formatDateTime, formatDzd } from '@/utils/format'
import { toAppError } from '@/types/errors'

const { t, locale } = useI18n()
const toast = useToast()
const listings = useAsync(() => resaleService.listOpen(50))
const buying = ref<string | null>(null)
const qty = ref<Record<string, number>>({})

async function buy(id: string, available: number) {
  const seats = Math.min(qty.value[id] ?? 1, available)
  buying.value = id
  try {
    await resaleService.buy(id, seats)
    toast.success(t('resale.purchased'))
    await listings.run()
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { buying.value = null }
}

onMounted(() => listings.run())
</script>

<template>
  <div class="d-flex flex-column gap-3">
    <h1 class="fs-4 fw-bold">{{ t('resale.marketplace') }}</h1>
    <AsyncSection :state="listings.state.value" :error="listings.error.value"
                  :empty-text="t('resale.none')" @retry="listings.run()">
      <ul class="row row-cols-1 row-cols-sm-2 g-3 list-unstyled mb-0">
        <li v-for="l in listings.data.value ?? []" :key="l.id" class="col">
          <div class="card card-body rounded-3 shadow-sm h-100">
            <p class="fw-medium mb-0">{{ l.bookings?.pickup?.name }} → {{ l.bookings?.dropoff?.name }}</p>
            <p class="mt-1 fs-xs text-secondary mb-0">{{ formatDateTime(l.bookings?.trips?.departure_at ?? null, locale) }}</p>
            <div class="mt-2 d-flex align-items-center justify-content-between">
              <span class="small text-secondary">{{ t('resale.sold', { sold: l.seats_sold, total: l.seats_for_sale }) }}</span>
              <span class="fs-6 fw-bold text-primary">{{ formatDzd(l.price_per_seat, locale) }}</span>
            </div>
            <div class="mt-3 d-flex align-items-end gap-2">
              <div class="flex-grow-1">
                <label class="form-label" :for="`q-${l.id}`">{{ t('resale.buySeats') }}</label>
                <input :id="`q-${l.id}`" v-model.number="qty[l.id]" class="form-control" type="number" min="1"
                       :max="l.seats_for_sale - l.seats_sold" :placeholder="'1'" />
              </div>
              <button class="btn btn-primary" :disabled="buying === l.id" @click="buy(l.id, l.seats_for_sale - l.seats_sold)">
                {{ t('resale.buy') }}
              </button>
            </div>
          </div>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
