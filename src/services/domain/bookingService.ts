import { supabase } from '@/services/supabase/client'
import { query, rpc } from '@/services/supabase/rpc'
import type {
  Booking, BookingQuote, CancellationQuote, CreateBookingResult,
} from '@/types'

export interface BookingWithTrip extends Booking {
  trips: { id: string; departure_at: string; status: string; booking_mode: string; driver_id: string } | null
  pickup: { name: string } | null
  dropoff: { name: string } | null
}

const SELECT_WITH_TRIP =
  '*, trips!inner(id,departure_at,status,booking_mode,driver_id),' +
  'pickup:trip_checkpoints!bookings_pickup_checkpoint_id_fkey(name),' +
  'dropoff:trip_checkpoints!bookings_dropoff_checkpoint_id_fkey(name)'

export const bookingService = {
  quote(tripId: string, pickupId: string, dropoffId: string, seats: number): Promise<BookingQuote> {
    return rpc<BookingQuote>('quote_booking', {
      p_trip: tripId, p_pickup: pickupId, p_dropoff: dropoffId, p_seats: seats,
    })
  },

  /** Atomic: seat lock + reservation + price snapshot. auto_confirm → confirmed; driver_approval → pending. */
  createBooking(tripId: string, pickupId: string, dropoffId: string, seats: number): Promise<CreateBookingResult> {
    return rpc<CreateBookingResult>('create_booking', {
      p_trip: tripId, p_pickup: pickupId, p_dropoff: dropoffId, p_seats: seats, p_source: 'direct',
    })
  },

  async listClientBookings(clientId: string, limit = 20, offset = 0): Promise<BookingWithTrip[]> {
    return query<BookingWithTrip[]>(() =>
      supabase.from('bookings').select(SELECT_WITH_TRIP).eq('client_id', clientId)
        .order('created_at', { ascending: false }).range(offset, offset + limit - 1))
  },

  async listTripBookings(tripId: string): Promise<BookingWithTrip[]> {
    return query<BookingWithTrip[]>(() =>
      supabase.from('bookings').select(SELECT_WITH_TRIP).eq('trip_id', tripId).order('created_at', { ascending: false }))
  },

  async getBooking(id: string): Promise<BookingWithTrip> {
    return query<BookingWithTrip>(() => supabase.from('bookings').select(SELECT_WITH_TRIP).eq('id', id).single())
  },

  confirm(bookingId: string): Promise<void> { return rpc<void>('confirm_booking', { p_booking: bookingId }) },
  reject(bookingId: string, reason?: string): Promise<void> {
    return rpc<void>('reject_booking', { p_booking: bookingId, p_reason: reason ?? null })
  },
  cancellationQuote(bookingId: string): Promise<CancellationQuote> {
    return rpc<CancellationQuote>('cancellation_quote', { p_booking: bookingId })
  },
  cancel(bookingId: string): Promise<{ cancelled: boolean }> {
    return rpc('cancel_booking', { p_booking: bookingId })
  },
  markNoShow(bookingId: string): Promise<void> { return rpc<void>('mark_no_show', { p_booking: bookingId }) },
}
