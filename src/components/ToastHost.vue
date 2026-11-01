<script setup lang="ts">
import { useToast } from '@/composables/useToast'
const { toasts, dismiss } = useToast()
</script>

<template>
  <div class="toast-host d-flex flex-column align-items-center gap-2 px-3" aria-live="polite">
    <div
      v-for="t in toasts" :key="t.id"
      class="pe-auto w-100 mw-sm rounded-3 px-3 py-2 small shadow"
      :class="t.tone === 'error' ? 'bg-danger text-white' : t.tone === 'success' ? 'bg-success text-white' : 'bg-dark text-white'"
      role="status"
      @click="dismiss(t.id)"
    >{{ t.message }}</div>
  </div>
</template>
