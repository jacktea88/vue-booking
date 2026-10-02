import { supabase } from '@/services/supabase/client'
import { query, rpc } from '@/services/supabase/rpc'
import { bookingService } from './bookingService'
import type { ResaleListing } from '@/types'

export interface ResaleListingView extends ResaleListing {
  bookings: {
    trip_id: string; seats: number; price_per_seat: number
    trips: { departure_at: string; status: string; booking_mode: string } | null
    pickup: { name: string } | null
    dropoff: { name: string } | null
  } | null
}

const SELECT =
  '*, bookings!inner(trip_id,seats,price_per_seat,trips!inner(departure_at,status,booking_mode),' +
  'pickup:trip_checkpoints!bookings_pickup_checkpoint_id_fkey(name),' +
  'dropoff:trip_checkpoints!bookings_dropoff_checkpoint_id_fkey(name))'

export const resaleService = {
  createListing(bookingId: string, seats: number, pricePerSeat: number): Promise<string> {
    return rpc<string>('create_resale', { p_booking: bookingId, p_seats: seats, p_price: pricePerSeat })
  },
  cancelListing(listingId: string): Promise<void> { return rpc<void>('cancel_resale', { p_listing: listingId }) },

  async listOpen(limit = 20, offset = 0): Promise<ResaleListingView[]> {
    return query<ResaleListingView[]>(() =>
      supabase.from('resale_listings').select(SELECT).eq('status', 'open')
        .order('created_at', { ascending: false }).range(offset, offset + limit - 1))
  },

  async listForSeller(sellerId: string): Promise<ResaleListingView[]> {
    return query<ResaleListingView[]>(() =>
      supabase.from('resale_listings').select(SELECT).eq('seller_id', sellerId).order('created_at', { ascending: false }))
  },

  /** Atomic purchase, then pay the newly created buyer booking. */
  async buy(listingId: string, seats: number) {
    const res = await rpc<{ booking_id: string; payment_id: string; amount: number; booking_mode: 'auto_confirm' | 'driver_approval' }>(
      'buy_resale', { p_listing: listingId, p_seats: seats })
    await bookingService.payBooking(res)
    return res
  },
}
