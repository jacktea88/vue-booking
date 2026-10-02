import { supabase } from '@/services/supabase/client'
import { query } from '@/services/supabase/rpc'
import type { AppNotification } from '@/types'

export const notificationService = {
  async list(userId: string, limit = 30, offset = 0): Promise<AppNotification[]> {
    return query<AppNotification[]>(() =>
      supabase.from('notifications').select('*').eq('user_id', userId)
        .order('created_at', { ascending: false }).range(offset, offset + limit - 1))
  },
  async markRead(id: string): Promise<void> {
    await supabase.from('notifications').update({ read_at: new Date().toISOString() }).eq('id', id)
  },
  async markAllRead(userId: string): Promise<void> {
    await supabase.from('notifications').update({ read_at: new Date().toISOString() })
      .eq('user_id', userId).is('read_at', null)
  },
  /** Push abstraction: token registration only; delivery is server-side. */
  async registerPushToken(userId: string, token: string, platform = 'web'): Promise<void> {
    await supabase.from('push_subscriptions').upsert({ user_id: userId, token, platform }, { onConflict: 'user_id,token' })
  },
  subscribe(userId: string, onInsert: (n: AppNotification) => void) {
    const channel = supabase
      .channel(`notifications:${userId}`)
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
        (payload) => onInsert(payload.new as AppNotification))
      .subscribe()
    return () => { void supabase.removeChannel(channel) }
  },
}
