<script setup lang="ts">
import { onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { useNotificationStore } from '@/stores/notifications'
import { formatDateTime } from '@/utils/format'

const { t, te, locale } = useI18n()
const auth = useAuthStore()
const store = useNotificationStore()

/** Notification titles/bodies are stored as i18n keys so every user reads them in their language. */
const label = (key: string) => (te(key) ? t(key) : key)

onMounted(() => { if (auth.user) void store.load(auth.user.id) })
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="text-xl font-bold">{{ t('notifications.title') }}</h1>
      <button v-if="store.unreadCount" class="btn-secondary" @click="auth.user && store.markAllRead(auth.user.id)">
        {{ t('notifications.markAllRead') }}
      </button>
    </div>
    <p v-if="!store.items.length" class="card text-center text-sm text-slate-500">{{ t('notifications.empty') }}</p>
    <ul v-else class="space-y-2">
      <li v-for="n in store.items" :key="n.id">
        <button class="card block w-full text-start" :class="!n.read_at ? 'border-brand-600 bg-brand-50/40' : ''"
                @click="store.markRead(n.id)">
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="text-sm font-semibold">{{ label(n.title) }}</p>
              <p class="mt-0.5 text-sm text-slate-600">{{ label(n.body) }}</p>
            </div>
            <span class="shrink-0 text-[11px] text-slate-400">{{ formatDateTime(n.created_at, locale) }}</span>
          </div>
        </button>
      </li>
    </ul>
  </div>
</template>
