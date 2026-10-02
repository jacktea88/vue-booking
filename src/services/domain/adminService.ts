import { supabase } from '@/services/supabase/client'
import { query, rpc } from '@/services/supabase/rpc'
import type {
  AdminStats, AuditLog, Booking, BookingPayment, DocumentStatus, Profile, Rating,
  ResaleListing, Setting, TransferRequest, Trip, UserRole, Vehicle, VerificationDocument,
} from '@/types'

export interface Page<T> { rows: T[]; count: number }

async function paged<T>(table: string, select: string, limit: number, offset: number,
                        order: string, filters?: (q: any) => any): Promise<Page<T>> {
  let q = supabase.from(table).select(select, { count: 'exact' }).order(order, { ascending: false })
  if (filters) q = filters(q)
  const { data, error, count } = await q.range(offset, offset + limit - 1)
  if (error) throw error
  return { rows: (data ?? []) as T[], count: count ?? 0 }
}

export const adminService = {
  stats(): Promise<AdminStats> { return rpc<AdminStats>('admin_stats') },

  users(limit = 20, offset = 0, search = ''): Promise<Page<Profile>> {
    return paged<Profile>('profiles', '*', limit, offset, 'created_at',
      search ? (q) => q.ilike('full_name', `%${search}%`) : undefined)
  },
  setRole(userId: string, role: UserRole): Promise<void> {
    return rpc<void>('admin_set_role', { p_user: userId, p_role: role })
  },

  documents(status: DocumentStatus | 'all' = 'pending', limit = 20, offset = 0): Promise<Page<VerificationDocument>> {
    return paged<VerificationDocument>('verification_documents', '*', limit, offset, 'created_at',
      status === 'all' ? undefined : (q) => q.eq('status', status))
  },
  reviewDocument(docId: string, status: DocumentStatus, reason?: string): Promise<void> {
    return rpc<void>('review_document', { p_doc: docId, p_status: status, p_reason: reason ?? null })
  },

  vehicles(limit = 20, offset = 0) { return paged<Vehicle>('vehicles', '*', limit, offset, 'created_at') },
  trips(limit = 20, offset = 0) { return paged<Trip>('trips', '*', limit, offset, 'departure_at') },
  bookings(limit = 20, offset = 0) { return paged<Booking>('bookings', '*', limit, offset, 'created_at') },
  payments(limit = 20, offset = 0) { return paged<BookingPayment>('booking_payments', '*', limit, offset, 'created_at') },
  resales(limit = 20, offset = 0) { return paged<ResaleListing>('resale_listings', '*', limit, offset, 'created_at') },
  transfers(limit = 20, offset = 0) { return paged<TransferRequest>('transfer_requests', '*', limit, offset, 'created_at') },
  ratings(limit = 20, offset = 0) { return paged<Rating>('ratings', '*', limit, offset, 'created_at') },
  auditLogs(limit = 30, offset = 0) { return paged<AuditLog>('audit_logs', '*', limit, offset, 'created_at') },

  async settings(): Promise<Setting[]> {
    return query<Setting[]>(() => supabase.from('settings').select('*').order('key'))
  },
  setSetting(key: string, value: unknown): Promise<void> {
    return rpc<void>('admin_set_setting', { p_key: key, p_value: value })
  },
}
