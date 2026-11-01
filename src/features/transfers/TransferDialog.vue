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
  <div class="position-fixed top-0 start-0 end-0 bottom-0 z-50 bg-overlay d-flex align-items-end align-items-sm-center justify-content-center p-0 p-sm-3"
       role="dialog" aria-modal="true" :aria-label="t('transfer.compatible')">
    <div class="card card-body w-100 mw-md rounded-3 shadow border-0 overflow-auto" style="max-height: 85dvh">
      <h2 class="fs-5 fw-semibold mb-0">{{ t('transfer.compatible') }}</h2>
      <p class="mt-1 mb-0 fs-xs text-secondary">{{ t('transfer.priceUnchanged') }}</p>
      <p v-if="loading" class="mt-4 mb-0 small text-secondary">{{ t('common.loading') }}</p>
      <p v-else-if="!rows.length" class="mt-4 mb-0 small text-secondary">{{ t('transfer.none') }}</p>
      <ul v-else class="list-unstyled d-flex flex-column gap-2 mt-4 mb-0">
        <li v-for="r in rows" :key="r.trip_id" class="rounded-3 border p-3">
          <p class="small fw-medium mb-0">{{ r.pickup_name }} → {{ r.dropoff_name }}</p>
          <p class="mt-1 mb-0 fs-xs text-secondary">{{ formatDateTime(r.departure_at, locale) }} · {{ r.driver_name }}</p>
          <button class="btn btn-primary btn-sm mt-2" :disabled="busy" @click="request(r)">{{ t('transfer.request') }}</button>
        </li>
      </ul>
      <button class="btn btn-outline-secondary mt-4 w-100" @click="emit('close')">{{ t('common.close') }}</button>
    </div>
  </div>
</template>
