<script setup lang="ts">
import { useToast } from '@/composables/useToast'
const { toasts, dismiss } = useToast()
</script>

<template>
  <div class="pointer-events-none fixed inset-x-0 bottom-20 z-50 flex flex-col items-center gap-2 px-4 sm:bottom-6" aria-live="polite">
    <div
      v-for="t in toasts" :key="t.id"
      class="pointer-events-auto w-full max-w-sm rounded-lg px-4 py-3 text-sm shadow-lg"
      :class="t.tone === 'error' ? 'bg-red-600 text-white' : t.tone === 'success' ? 'bg-emerald-600 text-white' : 'bg-slate-900 text-white'"
      role="status"
      @click="dismiss(t.id)"
    >{{ t.message }}</div>
  </div>
</template>
