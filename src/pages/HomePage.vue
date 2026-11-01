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
  <div class="d-flex flex-column gap-4">
    <section class="rounded-4 bg-primary text-white p-4">
      <h1 class="fs-5 fw-semibold">{{ t('home.greeting', { name: auth.profile?.full_name || '…' }) }}</h1>
      <p class="mt-1 small text-white-50">{{ t('app.tagline') }}</p>
      <RouterLink class="btn btn-light mt-3 fw-semibold text-primary"
                  :to="{ name: 'search' }">{{ t('home.searchTrip') }}</RouterLink>
    </section>

    <section>
      <h2 class="mb-2 small fw-semibold text-secondary">{{ t('home.upcoming') }}</h2>
      <AsyncSection :state="bookings.state.value" :error="bookings.error.value"
                    :empty-text="t('home.noUpcoming')" @retry="bookings.run()">
        <RouterLink v-if="upcoming" :to="{ name: 'booking-details', params: { id: upcoming.id } }"
                    class="card card-body rounded-3 shadow-sm text-body text-decoration-none hover-border-primary">
          <div class="d-flex align-items-start justify-content-between gap-3">
            <div>
              <p class="fw-medium mb-0">{{ upcoming.pickup?.name }} → {{ upcoming.dropoff?.name }}</p>
              <p class="mt-1 small text-secondary mb-0">{{ formatDateTime(upcoming.trips?.departure_at, locale) }}</p>
            </div>
            <StatusBadge :status="upcoming.status" :label="t(`booking.status.${upcoming.status}`)" />
          </div>
          <p class="mt-2 mb-0 fw-semibold text-primary">{{ formatDzd(upcoming.total_amount, locale) }}</p>
        </RouterLink>
        <div v-else class="card card-body rounded-3 shadow-sm small text-secondary">{{ t('home.noUpcoming') }}</div>
      </AsyncSection>
    </section>

    <section>
      <h2 class="mb-2 small fw-semibold text-secondary">{{ t('home.quickActions') }}</h2>
      <div class="row row-cols-2 row-cols-sm-4 g-3">
        <div class="col">
          <RouterLink class="card card-body rounded-3 shadow-sm text-center small fw-medium text-body text-decoration-none hover-border-primary" :to="{ name: 'search' }">{{ t('nav.search') }}</RouterLink>
        </div>
        <div class="col">
          <RouterLink class="card card-body rounded-3 shadow-sm text-center small fw-medium text-body text-decoration-none hover-border-primary" :to="{ name: 'bookings' }">{{ t('home.myBookings') }}</RouterLink>
        </div>
        <div class="col">
          <RouterLink class="card card-body rounded-3 shadow-sm text-center small fw-medium text-body text-decoration-none hover-border-primary" :to="{ name: 'marketplace' }">{{ t('home.marketplace') }}</RouterLink>
        </div>
        <div class="col">
          <RouterLink class="card card-body rounded-3 shadow-sm text-center small fw-medium text-body text-decoration-none hover-border-primary" :to="{ name: 'profile' }">{{ t('home.completeProfile') }}</RouterLink>
        </div>
      </div>
    </section>
  </div>
</template>
