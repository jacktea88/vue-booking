<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { transferService } from '@/services/domain'
import { useToast } from '@/composables/useToast'
import { formatDateTime } from '@/utils/format'
import { toAppError } from '@/types/errors'
import type { CompatibleTripRow } from '@/types'

const props = defineProps<{ bookingId: string }>()
const emit = defineEmits<{ close: []; requested: [] }>()
const { t, locale } = useI18n()
const toast = useToast()
const rows = ref<CompatibleTripRow[]>([])
const loading = ref(true)
const busy = ref(false)

async function request(r: CompatibleTripRow) {
  busy.value = true
  try {
    await transferService.requestTransfer(props.bookingId, r.trip_id, r.pickup_checkpoint_id, r.dropoff_checkpoint_id)
    toast.success(t('transfer.requested'))
    emit('requested')
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}

onMounted(async () => {
  try { rows.value = await transferService.findCompatibleTrips(props.bookingId) }
  catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { loading.value = false }
})
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-end justify-center bg-slate-900/50 sm:items-center sm:p-4"
       role="dialog" aria-modal="true" :aria-label="t('transfer.compatible')">
    <div class="max-h-[85dvh] w-full max-w-lg overflow-auto rounded-t-2xl bg-white p-5 sm:rounded-2xl">
      <h2 class="text-base font-semibold">{{ t('transfer.compatible') }}</h2>
      <p class="mt-1 text-xs text-slate-500">{{ t('transfer.priceUnchanged') }}</p>
      <p v-if="loading" class="mt-4 text-sm text-slate-500">{{ t('common.loading') }}</p>
      <p v-else-if="!rows.length" class="mt-4 text-sm text-slate-500">{{ t('transfer.none') }}</p>
      <ul v-else class="mt-4 space-y-2">
        <li v-for="r in rows" :key="r.trip_id" class="rounded-lg border border-slate-200 p-3">
          <p class="text-sm font-medium">{{ r.pickup_name }} → {{ r.dropoff_name }}</p>
          <p class="mt-0.5 text-xs text-slate-500">{{ formatDateTime(r.departure_at, locale) }} · {{ r.driver_name }}</p>
          <button class="btn-primary mt-2" :disabled="busy" @click="request(r)">{{ t('transfer.request') }}</button>
        </li>
      </ul>
      <button class="btn-secondary mt-5 w-full" @click="emit('close')">{{ t('common.close') }}</button>
    </div>
  </div>
</template>
