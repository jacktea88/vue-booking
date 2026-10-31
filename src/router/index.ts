import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

/** All pages are lazy-loaded (mobile network friendly). */
const routes: RouteRecordRaw[] = [
  { path: '/login', name: 'login', component: () => import('@/features/auth/LoginPage.vue'), meta: { public: true, layout: 'auth' } },
  { path: '/register', name: 'register', component: () => import('@/features/auth/RegisterPage.vue'), meta: { public: true, layout: 'auth' } },
  { path: '/forgot-password', name: 'forgot', component: () => import('@/features/auth/ForgotPasswordPage.vue'), meta: { public: true, layout: 'auth' } },
  { path: '/reset-password', name: 'reset', component: () => import('@/features/auth/ResetPasswordPage.vue'), meta: { public: true, layout: 'auth' } },
  { path: '/auth/line-callback', name: 'line-callback', component: () => import('@/features/auth/LineCallbackPage.vue'), meta: { public: true, layout: 'auth' } },

  { path: '/', name: 'home', component: () => import('@/pages/HomePage.vue') },
  { path: '/search', name: 'search', component: () => import('@/features/trips/SearchPage.vue') },
  { path: '/trips/:id', name: 'trip-details', component: () => import('@/features/trips/TripDetailsPage.vue'), props: true },
  { path: '/checkout/:bookingId', name: 'checkout', component: () => import('@/features/payments/CheckoutPage.vue'), props: true },
  { path: '/bookings', name: 'bookings', component: () => import('@/features/bookings/BookingsPage.vue') },
  { path: '/bookings/:id', name: 'booking-details', component: () => import('@/features/bookings/BookingDetailsPage.vue'), props: true },
  { path: '/marketplace', name: 'marketplace', component: () => import('@/features/resale/MarketplacePage.vue') },
  { path: '/notifications', name: 'notifications', component: () => import('@/features/notifications/NotificationsPage.vue') },
  { path: '/profile', name: 'profile', component: () => import('@/features/profile/ProfilePage.vue') },

  { path: '/driver', name: 'driver-home', component: () => import('@/features/trips/DriverHomePage.vue'), meta: { roles: ['driver'] } },
  { path: '/driver/trips', name: 'driver-trips', component: () => import('@/features/trips/DriverTripsPage.vue'), meta: { roles: ['driver'] } },
  { path: '/driver/trips/new', name: 'driver-create-trip', component: () => import('@/features/trips/CreateTripPage.vue'), meta: { roles: ['driver'] } },
  { path: '/driver/trips/:id', name: 'driver-trip-details', component: () => import('@/features/trips/DriverTripDetailsPage.vue'), props: true, meta: { roles: ['driver'] } },

  { path: '/admin', name: 'admin', component: () => import('@/features/admin/AdminPage.vue'), meta: { roles: ['admin'] } },

  { path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/pages/NotFoundPage.vue'), meta: { public: true } },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
})

/** Route protection is a UX guard only — authorization is enforced by RLS + RPCs. */
router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()
  if (to.meta.public) {
    if (auth.isAuthenticated && ['login', 'register'].includes(String(to.name))) return { name: 'home' }
    return true
  }
  if (!auth.isAuthenticated) return { name: 'login', query: { redirect: to.fullPath } }
  const roles = to.meta.roles as string[] | undefined
  if (roles && auth.role && !roles.includes(auth.role)) return { name: 'home' }
  return true
})
