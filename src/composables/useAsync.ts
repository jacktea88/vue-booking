import { ref, shallowRef } from 'vue'
import { AppError, toAppError } from '@/types/errors'
import type { AsyncState } from '@/types'

/** Standard loading / success / empty / error lifecycle for every data view. */
export function useAsync<T>(loader: () => Promise<T>, isEmpty?: (data: T) => boolean) {
  const data = shallowRef<T | null>(null)
  const error = ref<AppError | null>(null)
  const state = ref<AsyncState>('idle')

  async function run(): Promise<void> {
    state.value = 'loading'
    error.value = null
    try {
      const result = await loader()
      data.value = result
      const empty = isEmpty ? isEmpty(result)
        : Array.isArray(result) ? result.length === 0 : result === null || result === undefined
      state.value = empty ? 'empty' : 'success'
    } catch (e) {
      error.value = toAppError(e)
      state.value = 'error'
    }
  }

  return { data, error, state, run }
}
