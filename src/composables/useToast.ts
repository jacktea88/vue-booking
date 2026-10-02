import { ref } from 'vue'

export interface Toast { id: number; message: string; tone: 'success' | 'error' | 'info' }

const toasts = ref<Toast[]>([])
let seq = 0

export function useToast() {
  function push(message: string, tone: Toast['tone'] = 'info'): void {
    const id = ++seq
    toasts.value = [...toasts.value, { id, message, tone }]
    setTimeout(() => { toasts.value = toasts.value.filter((t) => t.id !== id) }, 4500)
  }
  return {
    toasts,
    success: (m: string) => push(m, 'success'),
    error: (m: string) => push(m, 'error'),
    info: (m: string) => push(m, 'info'),
    dismiss: (id: number) => { toasts.value = toasts.value.filter((t) => t.id !== id) },
  }
}
