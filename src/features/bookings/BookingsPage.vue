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
  <div class="space-y-4">
    <h1 class="text-xl font-bold">{{ t('booking.myBookings') }}</h1>
    <AsyncSection :state="bookings.state.value" :error="bookings.error.value"
                  :empty-text="t('booking.none')" @retry="bookings.run()">
      <ul class="space-y-3">
        <li v-for="b in bookings.data.value ?? []" :key="b.id">
          <RouterLink class="card block hover:border-brand-600" :to="{ name: 'booking-details', params: { id: b.id } }">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="truncate font-medium">{{ b.pickup?.name }} → {{ b.dropoff?.name }}</p>
                <p class="mt-1 text-xs text-slate-500">{{ formatDateTime(b.trips?.departure_at, locale) }}</p>
                <p class="mt-1 text-xs text-slate-500">
                  {{ t('booking.seatsLabel', { n: b.seats }) }} · {{ t(`booking.source.${b.source}`) }}
                </p>
              </div>
              <div class="text-end">
                <StatusBadge :status="b.status" :label="t(`booking.status.${b.status}`)" />
                <p class="mt-2 text-sm font-bold text-brand-700">{{ formatDzd(b.total_amount, locale) }}</p>
              </div>
            </div>
          </RouterLink>
        </li>
      </ul>
    </AsyncSection>
  </div>
</template>
