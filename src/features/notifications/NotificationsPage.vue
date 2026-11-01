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
  <div class="d-flex flex-column gap-4">
    <div class="d-flex align-items-center justify-content-between gap-2">
      <h1 class="fs-4 fw-bold mb-0">{{ t('notifications.title') }}</h1>
      <button v-if="store.unreadCount" class="btn btn-outline-secondary" @click="auth.user && store.markAllRead(auth.user.id)">
        {{ t('notifications.markAllRead') }}
      </button>
    </div>
    <p v-if="!store.items.length" class="card card-body rounded-3 shadow-sm text-center small text-secondary mb-0">{{ t('notifications.empty') }}</p>
    <ul v-else class="list-unstyled d-flex flex-column gap-2 mb-0">
      <li v-for="n in store.items" :key="n.id">
        <button class="card card-body rounded-3 shadow-sm w-100 text-start hover-border-primary"
                :class="!n.read_at ? 'border-primary bg-brand-light' : ''"
                @click="store.markRead(n.id)">
          <div class="d-flex align-items-start justify-content-between gap-3">
            <div>
              <p class="small fw-semibold mb-0">{{ label(n.title) }}</p>
              <p class="mt-1 small text-secondary mb-0">{{ label(n.body) }}</p>
            </div>
            <span class="flex-shrink-0 fs-xs text-secondary">{{ formatDateTime(n.created_at, locale) }}</span>
          </div>
        </button>
      </li>
    </ul>
  </div>
</template>
