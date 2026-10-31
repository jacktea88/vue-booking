import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/services/supabase/client'
import { profileService } from '@/services/domain'
import { AppError, toAppError } from '@/types/errors'
import { lineRedirectUri, takeLineAttempt } from '@/services/auth/line'
import type { DriverProfile, Profile, UserRole } from '@/types'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const session = ref<Session | null>(null)
  const profile = ref<Profile | null>(null)
  const driverProfile = ref<DriverProfile | null>(null)
  const initialized = ref(false)
  const loading = ref(false)

  const isAuthenticated = computed(() => Boolean(user.value))
  const role = computed<UserRole | null>(() => profile.value?.role ?? null)
  const isDriver = computed(() => role.value === 'driver')
  const isAdmin = computed(() => role.value === 'admin')
  const isVerifiedDriver = computed(() => Boolean(driverProfile.value?.overall_verified))

  async function loadProfile(): Promise<void> {
    if (!user.value) { profile.value = null; driverProfile.value = null; return }
    profile.value = await profileService.getProfile(user.value.id)
    driverProfile.value = profile.value.role === 'driver'
      ? await profileService.getDriverProfile(user.value.id)
      : null
  }

  async function init(): Promise<void> {
    if (initialized.value) return
    const { data } = await supabase.auth.getSession()
    session.value = data.session
    user.value = data.session?.user ?? null
    if (user.value) { try { await loadProfile() } catch { /* profile row may lag behind signup */ } }
    supabase.auth.onAuthStateChange(async (_event, s) => {
      session.value = s
      user.value = s?.user ?? null
      if (user.value) { try { await loadProfile() } catch { /* ignore */ } }
      else { profile.value = null; driverProfile.value = null }
    })
    initialized.value = true
  }

  async function signIn(email: string, password: string): Promise<void> {
    loading.value = true
    try {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) throw toAppError(error)
      user.value = data.user; session.value = data.session
      await loadProfile()
    } finally { loading.value = false }
  }

  /** Only `client` | `driver` can ever be requested; the DB trigger enforces it. */
  async function signUp(email: string, password: string, fullName: string, phone: string, wantedRole: 'client' | 'driver'): Promise<void> {
    loading.value = true
    try {
      const { data, error } = await supabase.auth.signUp({
        email, password,
        options: { data: { full_name: fullName, phone, role: wantedRole } },
      })
      if (error) throw toAppError(error)
      user.value = data.user; session.value = data.session
      if (data.session) await loadProfile()
    } finally { loading.value = false }
  }

  /**
   * LINE Web login, step 2 (callback page). The Edge Function `line-auth` exchanges the code,
   * verifies the ID token and returns a single-use token_hash, which is then exchanged for a session.
   * Returns the internal post-login path (or null).
   */
  async function signInWithLine(code: string, state: string): Promise<string | null> {
    const attempt = takeLineAttempt(state)
    if (!attempt) throw new AppError('UNKNOWN')
    loading.value = true
    try {
      const { data, error } = await supabase.functions.invoke<{ tokenHash?: string }>('line-auth', {
        body: { code, nonce: attempt.nonce, redirectUri: lineRedirectUri() },
      })
      if (error || !data?.tokenHash) throw new AppError('UNKNOWN', error)
      const { data: otp, error: otpError } = await supabase.auth.verifyOtp({
        token_hash: data.tokenHash, type: 'magiclink',
      })
      if (otpError) throw toAppError(otpError)
      user.value = otp.user; session.value = otp.session
      await loadProfile()
      return attempt.redirectPath
    } finally { loading.value = false }
  }

  async function signOut(): Promise<void> {
    await supabase.auth.signOut()
    user.value = null; session.value = null; profile.value = null; driverProfile.value = null
  }

  async function requestPasswordReset(email: string): Promise<void> {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    if (error) throw toAppError(error)
  }

  async function updatePassword(password: string): Promise<void> {
    const { error } = await supabase.auth.updateUser({ password })
    if (error) throw toAppError(error)
  }

  return {
    user, session, profile, driverProfile, initialized, loading,
    isAuthenticated, role, isDriver, isAdmin, isVerifiedDriver,
    init, loadProfile, signIn, signInWithLine, signUp, signOut, requestPasswordReset, updatePassword,
  }
})
