/** UI-side constants. Business parameters live in the DB `settings` table. */
export const MAX_SEATS_PER_BOOKING = 8
export const SEARCH_DEBOUNCE_MS = 350
export const PAGE_SIZE = 20
export const DEFAULT_MAP_CENTER = { lat: 36.7538, lng: 3.0588 }
export const REQUIRED_DRIVER_DOCUMENTS = ['identity_card', 'driving_license', 'vehicle_registration', 'insurance'] as const
export const REQUIRED_CLIENT_DOCUMENTS = ['identity_card'] as const
