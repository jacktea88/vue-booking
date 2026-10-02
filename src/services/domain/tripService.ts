import { supabase } from '@/services/supabase/client'
import { query, rpc } from '@/services/supabase/rpc'
import type { BookingMode, GeoPoint, SearchTripRow, Trip, TripDetails } from '@/types'

export interface CheckpointInput { name: string; lat: number; lng: number; place_id?: string | null }

export interface SearchParams {
  from: GeoPoint
  to: GeoPoint
  date: string
  seats: number
  limit?: number
  offset?: number
}

export const tripService = {
  /** Creates trip + checkpoints + segments + reference prices in ONE transaction. */
  async createTrip(departureAt: string, mode: BookingMode, checkpoints: CheckpointInput[]): Promise<string> {
    return rpc<string>('create_trip', {
      p_departure_at: departureAt,
      p_booking_mode: mode,
      p_checkpoints: checkpoints.map((c) => ({ name: c.name, lat: c.lat, lng: c.lng, place_id: c.place_id ?? null })),
    })
  },

  setSegmentPrice(segmentId: string, price: number): Promise<void> {
    return rpc<void>('set_segment_price', { p_segment: segmentId, p_price: price })
  },

  publishTrip(tripId: string): Promise<void> { return rpc<void>('publish_trip', { p_trip: tripId }) },
  startTrip(tripId: string): Promise<void> { return rpc<void>('start_trip', { p_trip: tripId }) },
  completeTrip(tripId: string): Promise<void> { return rpc<void>('complete_trip', { p_trip: tripId }) },
  cancelTrip(tripId: string, reason?: string): Promise<void> {
    return rpc<void>('cancel_trip', { p_trip: tripId, p_reason: reason ?? null })
  },

  getDetails(tripId: string): Promise<TripDetails> { return rpc<TripDetails>('get_trip_details', { p_trip: tripId }) },

  /** Server-side route matching (PostGIS). Never filter trips in the browser. */
  search(p: SearchParams): Promise<SearchTripRow[]> {
    return rpc<SearchTripRow[]>('search_trips', {
      p_from_lat: p.from.lat, p_from_lng: p.from.lng,
      p_to_lat: p.to.lat, p_to_lng: p.to.lng,
      p_date: p.date, p_seats: p.seats,
      p_limit: p.limit ?? 20, p_offset: p.offset ?? 0,
    })
  },

  async listDriverTrips(driverId: string, limit = 20, offset = 0): Promise<Trip[]> {
    return query<Trip[]>(() =>
      supabase.from('trips').select('*').eq('driver_id', driverId)
        .order('departure_at', { ascending: false }).range(offset, offset + limit - 1))
  },
}
