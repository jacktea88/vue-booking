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
  <div class="flex min-h-dvh flex-col bg-slate-50">
    <header class="sticky top-0 z-30 border-b border-slate-200 bg-white/95 backdrop-blur">
      <div class="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3">
        <RouterLink :to="{ name: auth.isAdmin ? 'admin' : auth.isDriver ? 'driver-home' : 'home' }"
                    class="text-lg font-bold text-brand-700">{{ t('app.name') }}</RouterLink>

        <nav class="hidden items-center gap-1 md:flex" :aria-label="t('nav.home')">
          <RouterLink v-for="item in nav" :key="item.name" :to="{ name: item.name }"
                      class="rounded-lg px-3 py-2 text-sm font-medium"
                      :class="isActive(item.name) ? 'bg-brand-50 text-brand-700' : 'text-slate-600 hover:bg-slate-100'">
            {{ t(item.label) }}
          </RouterLink>
          <RouterLink v-if="!auth.isAdmin" :to="{ name: 'marketplace' }"
                      class="rounded-lg px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">
            {{ t('nav.resale') }}
          </RouterLink>
        </nav>

        <div class="flex items-center gap-2">
          <RouterLink :to="{ name: 'notifications' }" class="relative rounded-lg p-2 hover:bg-slate-100"
                      :aria-label="t('nav.notifications')">
            <span aria-hidden="true">🔔</span>
            <span v-if="notifications.unreadCount"
                  class="absolute -top-0.5 -end-0.5 min-w-4 rounded-full bg-red-600 px-1 text-[10px] font-bold text-white">
              {{ notifications.unreadCount }}
            </span>
          </RouterLink>
          <LanguageSwitcher />
          <button v-if="auth.isAuthenticated" class="btn-ghost hidden sm:inline-flex" @click="auth.signOut()">
            {{ t('common.logout') }}
          </button>
        </div>
      </div>
    </header>

    <main class="mx-auto w-full max-w-6xl flex-1 px-4 pb-24 pt-4 md:pb-10"><slot /></main>

    <nav class="fixed inset-x-0 bottom-0 z-30 border-t border-slate-200 bg-white md:hidden" :aria-label="t('nav.home')">
      <ul class="mx-auto flex max-w-md">
        <li v-for="item in nav" :key="item.name" class="flex-1">
          <RouterLink :to="{ name: item.name }"
                      class="flex flex-col items-center gap-0.5 py-2.5 text-[11px] font-medium"
                      :class="isActive(item.name) ? 'text-brand-700' : 'text-slate-500'">
            <span class="text-lg leading-none" aria-hidden="true">{{ item.icon }}</span>
            {{ t(item.label) }}
          </RouterLink>
        </li>
      </ul>
    </nav>
  </div>
</template>
