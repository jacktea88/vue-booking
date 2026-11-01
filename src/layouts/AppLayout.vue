<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { useNotificationStore } from '@/stores/notifications'
import LanguageSwitcher from '@/components/LanguageSwitcher.vue'

const { t } = useI18n()
const auth = useAuthStore()
const notifications = useNotificationStore()
const route = useRoute()

interface NavItem { name: string; label: string; icon: string }

const clientNav: NavItem[] = [
  { name: 'home', label: 'nav.home', icon: '⌂' },
  { name: 'search', label: 'nav.search', icon: '⌕' },
  { name: 'bookings', label: 'nav.bookings', icon: '▤' },
  { name: 'profile', label: 'nav.profile', icon: '☻' },
]
const driverNav: NavItem[] = [
  { name: 'driver-home', label: 'nav.home', icon: '⌂' },
  { name: 'driver-trips', label: 'nav.trips', icon: '▤' },
  { name: 'driver-create-trip', label: 'nav.create', icon: '＋' },
  { name: 'profile', label: 'nav.profile', icon: '☻' },
]
const adminNav: NavItem[] = [
  { name: 'admin', label: 'nav.admin', icon: '⚙' },
  { name: 'notifications', label: 'nav.notifications', icon: '🔔' },
  { name: 'profile', label: 'nav.profile', icon: '☻' },
]

const nav = computed(() => (auth.isAdmin ? adminNav : auth.isDriver ? driverNav : clientNav))
const isActive = (name: string) => route.name === name
</script>

<template>
  <div class="d-flex flex-column min-h-dvh bg-light">
    <header class="sticky-top bg-white-95 border-bottom">
      <div class="container-xl d-flex align-items-center justify-content-between gap-3 py-2">
        <RouterLink :to="{ name: auth.isAdmin ? 'admin' : auth.isDriver ? 'driver-home' : 'home' }"
                    class="fs-5 fw-bold text-primary text-decoration-none">{{ t('app.name') }}</RouterLink>

        <nav class="nav nav-pills d-none d-md-flex align-items-center gap-1" :aria-label="t('nav.home')">
          <RouterLink v-for="item in nav" :key="item.name" :to="{ name: item.name }"
                      class="nav-link py-2 px-3 small fw-medium"
                      :class="{ active: isActive(item.name) }">
            {{ t(item.label) }}
          </RouterLink>
          <RouterLink v-if="!auth.isAdmin" :to="{ name: 'marketplace' }"
                      class="nav-link py-2 px-3 small fw-medium text-secondary">
            {{ t('nav.resale') }}
          </RouterLink>
        </nav>

        <div class="d-flex align-items-center gap-2">
          <RouterLink :to="{ name: 'notifications' }" class="btn btn-link position-relative p-2 lh-1 text-body text-decoration-none"
                      :aria-label="t('nav.notifications')">
            <span aria-hidden="true">🔔</span>
            <span v-if="notifications.unreadCount"
                  class="badge rounded-pill bg-danger fs-xxs fw-bold position-absolute top-0 start-100 translate-middle">
              {{ notifications.unreadCount }}
            </span>
          </RouterLink>
          <LanguageSwitcher />
          <button v-if="auth.isAuthenticated" class="btn btn-link text-secondary text-decoration-none d-none d-sm-inline-flex" @click="auth.signOut()">
            {{ t('common.logout') }}
          </button>
        </div>
      </div>
    </header>

    <main class="container-xl flex-grow-1 pt-3 pb-5 main-content"><slot /></main>

    <nav class="bottom-nav position-fixed bottom-0 start-0 end-0 d-md-none bg-white border-top" :aria-label="t('nav.home')">
      <ul class="mx-auto mw-md">
        <li v-for="item in nav" :key="item.name">
          <RouterLink :to="{ name: item.name }" :class="{ active: isActive(item.name) }">
            <span class="fs-5 lh-1" aria-hidden="true">{{ item.icon }}</span>
            {{ t(item.label) }}
          </RouterLink>
        </li>
      </ul>
    </nav>
  </div>
</template>
