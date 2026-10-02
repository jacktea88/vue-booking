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
  <div class="space-y-5">
    <section class="rounded-2xl bg-brand-700 p-5 text-white">
      <h1 class="text-lg font-semibold">{{ t('home.greeting', { name: auth.profile?.full_name || '…' }) }}</h1>
      <p v-if="!auth.isVerifiedDriver" class="mt-2 rounded-lg bg-white/15 p-2 text-sm">{{ t('profile.driverNotVerified') }}</p>
      <RouterLink class="mt-4 inline-flex rounded-lg bg-white px-4 py-2.5 text-sm font-semibold text-brand-700"
                  :to="{ name: 'driver-create-trip' }">{{ t('home.createTrip') }}</RouterLink>
    </section>

    <AsyncSection :state="trips.state.value" :error="trips.error.value" :empty-text="t('trip.noTrips')" @retry="trips.run()">
      <section v-if="current" class="space-y-2">
        <h2 class="text-sm font-semibold text-slate-700">{{ t('home.currentTrip') }}</h2>
        <RouterLink class="card block" :to="{ name: 'driver-trip-details', params: { id: current.id } }">
          <div class="flex justify-between">
            <span>{{ formatDateTime(current.departure_at, locale) }}</span>
            <StatusBadge :status="current.status" :label="t(`trip.status.${current.status}`)" />
          </div>
        </RouterLink>
      </section>

      <section class="mt-4 space-y-2">
        <h2 class="text-sm font-semibold text-slate-700">{{ t('home.driverToday') }}</h2>
        <p v-if="!today.length" class="card text-sm text-slate-500">{{ t('states.empty') }}</p>
        <RouterLink v-for="trip in today" :key="trip.id" class="card block"
                    :to="{ name: 'driver-trip-details', params: { id: trip.id } }">
          <div class="flex justify-between">
            <span>{{ formatDateTime(trip.departure_at, locale) }}</span>
            <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
          </div>
        </RouterLink>
      </section>

      <section class="mt-4 space-y-2">
        <h2 class="text-sm font-semibold text-slate-700">{{ t('home.driverUpcoming') }}</h2>
        <p v-if="!upcoming.length" class="card text-sm text-slate-500">{{ t('states.empty') }}</p>
        <RouterLink v-for="trip in upcoming" :key="trip.id" class="card block"
                    :to="{ name: 'driver-trip-details', params: { id: trip.id } }">
          <div class="flex justify-between">
            <span>{{ formatDateTime(trip.departure_at, locale) }}</span>
            <StatusBadge :status="trip.status" :label="t(`trip.status.${trip.status}`)" />
          </div>
        </RouterLink>
      </section>
    </AsyncSection>
  </div>
</template>
