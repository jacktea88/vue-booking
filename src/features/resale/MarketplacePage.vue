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
  <div class="space-y-4">
    <h1 class="text-xl font-bold">{{ t('resale.marketplace') }}</h1>
    <AsyncSection :state="listings.state.value" :error="listings.error.value"
                  :empty-text="t('resale.none')" @retry="listings.run()">
      <ul class="grid gap-3 sm:grid-cols-2">
        <li v-for="l in listings.data.value ?? []" :key="l.id" class="card">
          <p class="font-medium">{{ l.bookings?.pickup?.name }} → {{ l.bookings?.dropoff?.name }}</p>
          <p class="mt-1 text-xs text-slate-500">{{ formatDateTime(l.bookings?.trips?.departure_at ?? null, locale) }}</p>
          <div class="mt-2 flex items-center justify-between">
            <span class="text-sm text-slate-600">{{ t('resale.sold', { sold: l.seats_sold, total: l.seats_for_sale }) }}</span>
            <span class="text-base font-bold text-brand-700">{{ formatDzd(l.price_per_seat, locale) }}</span>
          </div>
          <div class="mt-3 flex items-end gap-2">
            <div class="flex-1">
              <label class="label" :for="`q-${l.id}`">{{ t('resale.buySeats') }}</label>
              <input :id="`q-${l.id}`" v-model.number="qty[l.id]" class="field" type="number" min="1"
                     :max="l.seats_for_sale - l.seats_sold" :placeholder="'1'" />
            </div>
            <button class="btn-primary" :disabled="buying === l.id" @click="buy(l.id, l.seats_for_sale - l.seats_sold)">
              {{ t('resale.buy') }}
            </button>
          </div>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
