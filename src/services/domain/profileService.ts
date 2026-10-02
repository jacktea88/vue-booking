import { supabase } from '@/services/supabase/client'
import { query, rpc } from '@/services/supabase/rpc'
import type { DocumentType, DriverProfile, Profile, VerificationDocument, Vehicle } from '@/types'

export const profileService = {
  async getProfile(userId: string): Promise<Profile> {
    return query<Profile>(() => supabase.from('profiles').select('*').eq('id', userId).single())
  },

  async getDriverProfile(userId: string): Promise<DriverProfile | null> {
    const { data } = await supabase.from('driver_profiles').select('*').eq('id', userId).maybeSingle()
    return (data as DriverProfile) ?? null
  },

  /** Role & identity_status are intentionally not updatable here (DB trigger blocks it). */
  async updateProfile(userId: string, patch: Pick<Partial<Profile>, 'full_name' | 'phone' | 'photo_url'>): Promise<Profile> {
    return query<Profile>(() => supabase.from('profiles').update(patch).eq('id', userId).select().single())
  },

  async uploadAvatar(userId: string, file: File): Promise<string> {
    const path = `${userId}/avatar_${Date.now()}.${file.name.split('.').pop() ?? 'jpg'}`
    const { error } = await supabase.storage.from('avatars').upload(path, file, { upsert: true })
    if (error) throw error
    const { data } = supabase.storage.from('avatars').getPublicUrl(path)
    return data.publicUrl
  },

  async listDocuments(userId: string): Promise<VerificationDocument[]> {
    return query<VerificationDocument[]>(() =>
      supabase.from('verification_documents').select('*').eq('user_id', userId).order('created_at', { ascending: false }))
  },

  /** Uploads to the PRIVATE bucket then registers the document for review. */
  async submitDocument(userId: string, type: DocumentType, file: File): Promise<string> {
    const path = `${userId}/${type}_${Date.now()}.${file.name.split('.').pop() ?? 'jpg'}`
    const { error } = await supabase.storage.from('verification-documents').upload(path, file)
    if (error) throw error
    return rpc<string>('submit_verification_document', { p_type: type, p_path: path })
  },

  async signedDocumentUrl(path: string, seconds = 120): Promise<string | null> {
    const { data } = await supabase.storage.from('verification-documents').createSignedUrl(path, seconds)
    return data?.signedUrl ?? null
  },

  async getVehicle(driverId: string): Promise<Vehicle | null> {
    const { data } = await supabase.from('vehicles').select('*').eq('driver_id', driverId).maybeSingle()
    return (data as Vehicle) ?? null
  },

  async upsertVehicle(driverId: string, v: Omit<Vehicle, 'id' | 'driver_id' | 'created_at' | 'updated_at'>): Promise<Vehicle> {
    return query<Vehicle>(() =>
      supabase.from('vehicles').upsert({ ...v, driver_id: driverId }, { onConflict: 'driver_id' }).select().single())
  },
}
