import { supabase } from './client'
import { toAppError } from '@/types/errors'

/** Thin typed wrapper: every RPC failure becomes a typed AppError. */
export async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw toAppError(error)
  return data as T
}

/**
 * Runs a PostgREST builder and returns typed rows.
 * The builder's own generic inference is bypassed on purpose: embedded selects
 * (`a:table!fk(...)`) are shaped by our hand-written view interfaces.
 */
export async function query<T>(run: () => PromiseLike<{ data: unknown; error: unknown }>): Promise<T> {
  const { data, error } = await run()
  if (error) throw toAppError(error)
  return data as T
}
