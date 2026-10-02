import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { notificationService } from '@/services/domain'
import type { AppNotification } from '@/types'

export const useNotificationStore = defineStore('notifications', () => {
  const items = ref<AppNotification[]>([])
  const loading = ref(false)
  let unsubscribe: (() => void) | null = null

  const unreadCount = computed(() => items.value.filter((n) => !n.read_at).length)

  async function load(userId: string): Promise<void> {
    loading.value = true
    try { items.value = await notificationService.list(userId) } finally { loading.value = false }
  }

  /** Realtime is used here because it has clear user value (live booking/payment updates). */
  function subscribe(userId: string): void {
    unsubscribe?.()
    unsubscribe = notificationService.subscribe(userId, (n) => { items.value = [n, ...items.value] })
  }

  function stop(): void { unsubscribe?.(); unsubscribe = null; items.value = [] }

  async function markRead(id: string): Promise<void> {
    await notificationService.markRead(id)
    const n = items.value.find((x) => x.id === id)
    if (n) n.read_at = new Date().toISOString()
  }

  async function markAllRead(userId: string): Promise<void> {
    await notificationService.markAllRead(userId)
    items.value = items.value.map((n) => ({ ...n, read_at: n.read_at ?? new Date().toISOString() }))
  }

  return { items, loading, unreadCount, load, subscribe, stop, markRead, markAllRead }
})
