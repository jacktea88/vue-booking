<script setup lang="ts">
import { computed, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useLocaleStore } from '@/stores/locale'
import { useNotificationStore } from '@/stores/notifications'
import AppLayout from '@/layouts/AppLayout.vue'
import AuthLayout from '@/layouts/AuthLayout.vue'
import ToastHost from '@/components/ToastHost.vue'

const route = useRoute()
const auth = useAuthStore()
const locale = useLocaleStore()
const notifications = useNotificationStore()

const layout = computed(() => (route.meta.layout === 'auth' ? AuthLayout : AppLayout))

onMounted(async () => { await auth.init() })

watch(() => auth.user?.id, (id) => {
  if (id) { void notifications.load(id); notifications.subscribe(id) } else { notifications.stop() }
}, { immediate: true })
</script>

<template>
  <div :dir="locale.rtl ? 'rtl' : 'ltr'" class="min-h-dvh">
    <component :is="layout">
      <RouterView v-slot="{ Component }">
        <component :is="Component" />
      </RouterView>
    </component>
    <ToastHost />
  </div>
</template>
