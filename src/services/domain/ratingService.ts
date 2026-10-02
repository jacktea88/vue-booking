import { supabase } from '@/services/supabase/client'
import { query, rpc } from '@/services/supabase/rpc'
import type { Rating } from '@/types'

export const ratingService = {
  rate(bookingId: string, rating: number, comment?: string): Promise<string> {
    return rpc<string>('rate_booking', { p_booking: bookingId, p_rating: rating, p_comment: comment ?? null })
  },
  async listForBooking(bookingId: string): Promise<Rating[]> {
    return query<Rating[]>(() => supabase.from('ratings').select('*').eq('booking_id', bookingId))
  },
}
