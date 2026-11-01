<script setup lang="ts">
import { onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import AsyncSection from '@/components/AsyncSection.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { bookingService } from '@/services/domain'
import { useAuthStore } from '@/stores/auth'
import { useAsync } from '@/composables/useAsync'
import { formatDateTime, formatDzd } from '@/utils/format'

const { t, locale } = useI18n()
const auth = useAuthStore()
const bookings = useAsync(async () => (auth.user ? bookingService.listClientBookings(auth.user.id, 50) : []))
onMounted(() => bookings.run())
</script>

<template>
  <div class="d-flex flex-column gap-3">
    <h1 class="fs-4 fw-bold">{{ t('booking.myBookings') }}</h1>
    <AsyncSection :state="bookings.state.value" :error="bookings.error.value"
                  :empty-text="t('booking.none')" @retry="bookings.run()">
      <ul class="list-unstyled d-flex flex-column gap-3 mb-0">
        <li v-for="b in bookings.data.value ?? []" :key="b.id">
          <RouterLink class="card card-body rounded-3 shadow-sm text-body text-decoration-none hover-border-primary d-block" :to="{ name: 'booking-details', params: { id: b.id } }">
            <div class="d-flex align-items-start justify-content-between gap-3">
              <div class="min-w-0">
                <p class="text-truncate fw-medium mb-0">{{ b.pickup?.name }} → {{ b.dropoff?.name }}</p>
                <p class="mt-1 small text-secondary mb-0">{{ formatDateTime(b.trips?.departure_at, locale) }}</p>
                <p class="mt-1 small text-secondary mb-0">
                  {{ t('booking.seatsLabel', { n: b.seats }) }} · {{ t(`booking.source.${b.source}`) }}
                </p>
              </div>
              <div class="text-end flex-shrink-0">
                <StatusBadge :status="b.status" :label="t(`booking.status.${b.status}`)" />
                <p class="mt-2 mb-0 fw-bold text-primary">{{ formatDzd(b.total_amount, locale) }}</p>
              </div>
            </div>
          </RouterLink>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
