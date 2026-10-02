<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { bookingService } from '@/services/domain'
import { useAsync } from '@/composables/useAsync'
import AsyncSection from '@/components/AsyncSection.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { formatDateTime, formatDzd } from '@/utils/format'

const { t, locale } = useI18n()
const auth = useAuthStore()
const router = useRouter()

const bookings = useAsync(async () => (auth.user ? bookingService.listClientBookings(auth.user.id, 5) : []))

const upcoming = computed(() =>
  (bookings.data.value ?? []).filter((b) => ['pending', 'confirmed'].includes(b.status))[0] ?? null)

onMounted(async () => {
  if (auth.isDriver) { await router.replace({ name: 'driver-home' }); return }
  if (auth.isAdmin) { await router.replace({ name: 'admin' }); return }
  await bookings.run()
})
</script>

<template>
  <div class="space-y-5">
    <section class="rounded-2xl bg-brand-700 p-5 text-white">
      <h1 class="text-lg font-semibold">{{ t('home.greeting', { name: auth.profile?.full_name || '…' }) }}</h1>
      <p class="mt-1 text-sm text-brand-100">{{ t('app.tagline') }}</p>
      <RouterLink class="mt-4 inline-flex rounded-lg bg-white px-4 py-2.5 text-sm font-semibold text-brand-700"
                  :to="{ name: 'search' }">{{ t('home.searchTrip') }}</RouterLink>
    </section>

    <section>
      <h2 class="mb-2 text-sm font-semibold text-slate-700">{{ t('home.upcoming') }}</h2>
      <AsyncSection :state="bookings.state.value" :error="bookings.error.value"
                    :empty-text="t('home.noUpcoming')" @retry="bookings.run()">
        <RouterLink v-if="upcoming" :to="{ name: 'booking-details', params: { id: upcoming.id } }" class="card block">
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="font-medium">{{ upcoming.pickup?.name }} → {{ upcoming.dropoff?.name }}</p>
              <p class="mt-1 text-xs text-slate-500">{{ formatDateTime(upcoming.trips?.departure_at, locale) }}</p>
            </div>
            <StatusBadge :status="upcoming.status" :label="t(`booking.status.${upcoming.status}`)" />
          </div>
          <p class="mt-2 text-sm font-semibold text-brand-700">{{ formatDzd(upcoming.total_amount, locale) }}</p>
        </RouterLink>
        <div v-else class="card text-sm text-slate-500">{{ t('home.noUpcoming') }}</div>
      </AsyncSection>
    </section>

    <section>
      <h2 class="mb-2 text-sm font-semibold text-slate-700">{{ t('home.quickActions') }}</h2>
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <RouterLink class="card text-center text-sm font-medium" :to="{ name: 'search' }">{{ t('nav.search') }}</RouterLink>
        <RouterLink class="card text-center text-sm font-medium" :to="{ name: 'bookings' }">{{ t('home.myBookings') }}</RouterLink>
        <RouterLink class="card text-center text-sm font-medium" :to="{ name: 'marketplace' }">{{ t('home.marketplace') }}</RouterLink>
        <RouterLink class="card text-center text-sm font-medium" :to="{ name: 'profile' }">{{ t('home.completeProfile') }}</RouterLink>
      </div>
    </section>
  </div>
</template>
