<script setup lang="ts">
import { computed, onMounted } from 'vue'
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

const isToday = (iso: string) => new Date(iso).toDateString() === new Date().toDateString()
const current = computed(() => (trips.data.value ?? []).find((x) => x.status === 'in_progress' || x.status === 'boarding') ?? null)
const today = computed(() => (trips.data.value ?? []).filter((x) => isToday(x.departure_at) && x.status === 'published'))
const upcoming = computed(() => (trips.data.value ?? [])
  .filter((x) => new Date(x.departure_at) > new Date() && !isToday(x.departure_at) && ['published', 'draft'].includes(x.status)))

onMounted(() => trips.run())
</script>

<template>
  <div class="d-flex flex-column gap-4">
    <section class="rounded-4 bg-primary text-white p-4">
      <h1 class="fs-5 fw-semibold mb-0">{{ t('home.greeting', { name: auth.profile?.full_name || '…' }) }}</h1>
      <p v-if="!auth.isVerifiedDriver" class="mt-2 mb-0 rounded-3 bg-white-15 p-2 small">{{ t('profile.driverNotVerified') }}</p>
      <RouterLink class="btn btn-light mt-3 fw-semibold text-primary"
                  :to="{ name: 'driver-create-trip' }">{{ t('home.createTrip') }}</RouterLink>
    </section>

    <AsyncSection :state="trips.state.value" :error="trips.error.value" :empty-text="t('trip.noTrips')" @retry="trips.run()">
      <section v-if="current" class="d-flex flex-column gap-2">
        <h2 class="small fw-semibold text-secondary mb-0">{{ t('home.currentTrip') }}</h2>
        <RouterLink class="card card-body rounded-3 shadow-sm d-block text-body text-decoration-none hover-border-primary"
                    :to="{ name: 'driver-trip-details', params: { id: current.id } }">
          <div class="d-flex justify-content-between align-items-center gap-2">
            <span>{{ formatDateTime(current.departure_at, locale) }}</span>
            <StatusBadge :status="current.status" :label="t(`trip.status.${current.status}`)" />
          </div>
        </RouterLink>
      </section>

      <section class="mt-4 d-flex flex-column gap-2">
        <h2 class="small fw-semibold text-secondary mb-0">{{ t('home.driverToday') }}</h2>
        <p v-if="!today.length" class="card card-body rounded-3 shadow-sm small text-secondary mb-0">{{ t('states.empty') }}</p>
        <RouterLink v-for="trip in today" :key="trip.id"
                    class="card card-body rounded-3 shadow-sm d-block text-body text-decoration-none hover-border-primary"
                    :to="{ name: 'driver-trip-details', params: { id: trip.id } }">
          <div class="d-flex justify-content-between align-items-center gap-2">
            <span>{{ formatDateTime(trip.departure_at, locale) }}</span>
            <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
          </div>
        </RouterLink>
      </section>

      <section class="mt-4 d-flex flex-column gap-2">
        <h2 class="small fw-semibold text-secondary mb-0">{{ t('home.driverUpcoming') }}</h2>
        <p v-if="!upcoming.length" class="card card-body rounded-3 shadow-sm small text-secondary mb-0">{{ t('states.empty') }}</p>
        <RouterLink v-for="trip in upcoming" :key="trip.id"
                    class="card card-body rounded-3 shadow-sm d-block text-body text-decoration-none hover-border-primary"
                    :to="{ name: 'driver-trip-details', params: { id: trip.id } }">
          <div class="d-flex justify-content-between align-items-center gap-2">
            <span>{{ formatDateTime(trip.departure_at, locale) }}</span>
            <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
          </div>
        </RouterLink>
      </section>
    </AsyncSection>
  </div>
</template>
