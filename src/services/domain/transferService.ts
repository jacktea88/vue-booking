import { supabase } from '@/services/supabase/client'
import { query, rpc } from '@/services/supabase/rpc'
import type { CompatibleTripRow, TransferRequest } from '@/types'

export const transferService = {
  findCompatibleTrips(bookingId: string): Promise<CompatibleTripRow[]> {
    return rpc<CompatibleTripRow[]>('find_compatible_trips', { p_booking: bookingId })
  },
  requestTransfer(bookingId: string, toTripId: string, toPickupId: string, toDropoffId: string): Promise<string> {
    return rpc<string>('request_transfer', {
      p_booking: bookingId, p_to_trip: toTripId, p_to_pickup: toPickupId, p_to_dropoff: toDropoffId,
    })
  },
  approve(transferId: string): Promise<void> { return rpc<void>('approve_transfer', { p_transfer: transferId }) },
  reject(transferId: string): Promise<void> { return rpc<void>('reject_transfer', { p_transfer: transferId }) },

  async listForBooking(bookingId: string): Promise<TransferRequest[]> {
    return query<TransferRequest[]>(() =>
      supabase.from('transfer_requests').select('*').eq('booking_id', bookingId).order('created_at', { ascending: false }))
  },
  async listPendingForClient(): Promise<TransferRequest[]> {
    return query<TransferRequest[]>(() =>
      supabase.from('transfer_requests').select('*').eq('status', 'pending').order('created_at', { ascending: false }))
  },
}
