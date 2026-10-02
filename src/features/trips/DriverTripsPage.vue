<script setup lang="ts">
import { onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import AsyncSection from '@/components/AsyncSection.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { tripService } from '@/services/domain'
import { useAuthStore } from '@/stores/auth'
import { useAsync } from '@/composables/useAsync'
import { formatDateTime } from '@/utils/format'

const { t, locale } = useI18n()
const auth = useAuthStore()
const trips = useAsync(async () => (auth.user ? tripService.listDriverTrips(auth.user.id, 50) : []))
onMounted(() => trips.run())
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="text-xl font-bold">{{ t('nav.trips') }}</h1>
      <RouterLink class="btn-primary" :to="{ name: 'driver-create-trip' }">{{ t('nav.create') }}</RouterLink>
    </div>
    <AsyncSection :state="trips.state.value" :error="trips.error.value" :empty-text="t('trip.noTrips')" @retry="trips.run()">
      <ul class="space-y-3">
        <li v-for="trip in trips.data.value ?? []" :key="trip.id">
          <RouterLink class="card block hover:border-brand-600" :to="{ name: 'driver-trip-details', params: { id: trip.id } }">
            <div class="flex items-center justify-between gap-3">
              <span class="text-sm">{{ formatDateTime(trip.departure_at, locale) }}</span>
              <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
            </div>
            <p class="mt-1 text-xs text-slate-500">{{ t(`search.bookingMode.${trip.booking_mode}`) }}</p>
          </RouterLink>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
