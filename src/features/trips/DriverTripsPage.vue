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
  <div class="d-flex flex-column gap-4">
    <div class="d-flex align-items-center justify-content-between gap-2">
      <h1 class="fs-4 fw-bold mb-0">{{ t('nav.trips') }}</h1>
      <RouterLink class="btn btn-primary" :to="{ name: 'driver-create-trip' }">{{ t('nav.create') }}</RouterLink>
    </div>
    <AsyncSection :state="trips.state.value" :error="trips.error.value" :empty-text="t('trip.noTrips')" @retry="trips.run()">
      <ul class="list-unstyled d-flex flex-column gap-3 mb-0">
        <li v-for="trip in trips.data.value ?? []" :key="trip.id">
          <RouterLink class="card card-body rounded-3 shadow-sm d-block text-body text-decoration-none hover-border-primary"
                      :to="{ name: 'driver-trip-details', params: { id: trip.id } }">
            <div class="d-flex align-items-center justify-content-between gap-3">
              <span class="small">{{ formatDateTime(trip.departure_at, locale) }}</span>
              <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
            </div>
            <p class="mt-1 mb-0 small text-secondary">{{ t(`search.bookingMode.${trip.booking_mode}`) }}</p>
          </RouterLink>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
