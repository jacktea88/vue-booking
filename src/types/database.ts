/** Database entity & enum types (kept in sync with supabase/migrations). */
export type UserRole = 'client' | 'driver' | 'admin'
export type IdentityStatus = 'pending' | 'verified' | 'rejected'
export type DocumentType = 'identity_card' | 'driving_license' | 'vehicle_registration' | 'insurance'
export type DocumentStatus = 'pending' | 'verified' | 'rejected'
export type PlaceType = 'wilaya' | 'commune' | 'station' | 'place' | 'custom'
export type TripStatus = 'draft' | 'published' | 'boarding' | 'in_progress' | 'completed' | 'cancelled'
export type BookingMode = 'auto_confirm' | 'driver_approval'
export type BookingStatus = 'pending' | 'confirmed' | 'rejected' | 'cancelled' | 'completed' | 'no_show'
export type BookingSource = 'direct' | 'resale'
export type PaymentStatus =
  | 'requires_payment' | 'authorized' | 'paid' | 'failed' | 'expired' | 'refunded' | 'partially_refunded'
export type ResaleStatus = 'open' | 'closed' | 'cancelled'
export type TransferStatus = 'pending' | 'approved' | 'rejected' | 'cancelled'

export interface Profile {
  id: string
  role: UserRole
  full_name: string
  phone: string | null
  photo_url: string | null
  identity_status: IdentityStatus
  rating_avg: number
  rating_count: number
  created_at: string
  updated_at: string
}

export interface DriverProfile {
  id: string
  license_number: string | null
  overall_verified: boolean
  verified_at: string | null
}

export interface Vehicle {
  id: string
  driver_id: string
  brand: string
  model: string
  color: string
  plate_number: string
  capacity: number
  created_at: string
  updated_at: string
}

export interface VerificationDocument {
  id: string
  user_id: string
  type: DocumentType
  storage_path: string
  status: DocumentStatus
  rejection_reason: string | null
  reviewed_by: string | null
  reviewed_at: string | null
  created_at: string
}

export interface Place {
  id: string
  name: string
  type: PlaceType
  wilaya: string | null
  commune: string | null
  is_custom: boolean
  created_at: string
}

export interface Trip {
  id: string
  driver_id: string
  vehicle_id: string
  departure_at: string
  status: TripStatus
  booking_mode: BookingMode
  published_at: string | null
  started_at: string | null
  completed_at: string | null
  cancelled_at: string | null
  created_at: string
  updated_at: string
}

export interface TripCheckpoint {
  id: string
  name: string
  sequence: number
  estimated_arrival: string | null
  lat: number
  lng: number
}

export interface TripSegment {
  id: string
  sequence: number
  from_checkpoint_id: string
  to_checkpoint_id: string
  distance_km: number
  estimated_minutes: number
  reference_price: number
  driver_price: number
  capacity: number
  reserved_seats: number
}

export interface TripDetails {
  trip: Omit<Trip, 'driver_id'>
  driver: { id: string; full_name: string; photo_url: string | null; rating_avg: number; rating_count: number }
  vehicle: { brand: string; model: string; color: string; capacity: number }
  checkpoints: TripCheckpoint[]
  segments: TripSegment[]
}

export interface Booking {
  id: string
  client_id: string
  trip_id: string
  pickup_checkpoint_id: string
  dropoff_checkpoint_id: string
  seats: number
  price_per_seat: number
  total_amount: number
  status: BookingStatus
  source: BookingSource
  approval_expires_at: string | null
  created_at: string
  updated_at: string
}

export interface BookingPayment {
  id: string
  booking_id: string
  amount: number
  currency: string
  status: PaymentStatus
  provider: string
  provider_reference: string | null
  paid_at: string | null
  refunded_amount: number
  created_at: string
  updated_at: string
}

export interface ResaleListing {
  id: string
  booking_id: string
  seller_id: string
  seats_for_sale: number
  seats_sold: number
  price_per_seat: number
  status: ResaleStatus
  created_at: string
  closed_at: string | null
}

export interface TransferRequest {
  id: string
  booking_id: string
  from_trip_id: string
  to_trip_id: string
  to_pickup_checkpoint_id: string | null
  to_dropoff_checkpoint_id: string | null
  requested_by: string
  status: TransferStatus
  created_at: string
  responded_at: string | null
}

export interface AppNotification {
  id: string
  user_id: string
  type: string
  title: string
  body: string
  data: Record<string, unknown>
  read_at: string | null
  created_at: string
}

export interface Rating {
  id: string
  booking_id: string
  from_user_id: string
  to_user_id: string
  rating: number
  comment: string | null
  created_at: string
}

export interface Setting { key: string; value: unknown; updated_by: string | null; updated_at: string }

export interface AuditLog {
  id: string
  actor_id: string | null
  action: string
  entity_type: string
  entity_id: string | null
  metadata: Record<string, unknown>
  created_at: string
}

/** RPC payloads */
export interface SearchTripRow {
  trip_id: string
  driver_id: string
  driver_name: string
  driver_rating: number
  vehicle_brand: string
  vehicle_model: string
  vehicle_color: string
  departure_at: string
  booking_mode: BookingMode
  pickup_checkpoint_id: string
  pickup_name: string
  pickup_eta: string | null
  dropoff_checkpoint_id: string
  dropoff_name: string
  dropoff_eta: string | null
  price_per_seat: number
  available_seats: number
  total_distance_km: number
}

export interface CreateBookingResult {
  booking_id: string
  payment_id: string
  amount: number
  price_per_seat: number
  booking_mode: BookingMode
  status: BookingStatus
}

export interface BookingQuote {
  price_per_seat: number
  total_amount: number
  available_seats: number
  currency: string
}

export interface CancellationQuote {
  eligible: boolean
  refund_percentage: number
  refund_amount: number
  paid_amount: number
}

export interface CompatibleTripRow {
  trip_id: string
  departure_at: string
  driver_name: string
  pickup_checkpoint_id: string
  pickup_name: string
  dropoff_checkpoint_id: string
  dropoff_name: string
  available_seats: number
}

export interface AdminStats {
  pending_verifications: number
  active_trips: number
  upcoming_trips: number
  bookings_today: number
  paid_amount_today: number
  refunded_amount_today: number
  pending_transfers: number
  open_resales: number
}
