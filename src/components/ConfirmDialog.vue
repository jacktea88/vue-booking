<script setup lang="ts">
import { useI18n } from 'vue-i18n'
defineProps<{ open: boolean; title: string; message?: string; confirmLabel?: string; danger?: boolean; busy?: boolean }>()
const emit = defineEmits<{ confirm: []; close: [] }>()
const { t } = useI18n()
</script>

<template>
  <div v-if="open" class="position-fixed top-0 start-0 end-0 bottom-0 z-50 bg-overlay d-flex align-items-end align-items-sm-center justify-content-center p-0 p-sm-3"
       role="dialog" aria-modal="true" :aria-label="title" @keydown.esc="emit('close')">
    <div class="card card-body w-100 mw-md rounded-3 shadow border-0">
      <h2 class="fs-6 fw-semibold mb-0">{{ title }}</h2>
      <p v-if="message" class="mt-2 small text-secondary mb-0">{{ message }}</p>
      <slot />
      <div class="mt-4 d-flex justify-content-end gap-2">
        <button class="btn btn-outline-secondary" @click="emit('close')">{{ t('common.cancel') }}</button>
        <button class="btn" :class="danger ? 'btn-danger' : 'btn-primary'" :disabled="busy" @click="emit('confirm')">
          {{ confirmLabel ?? t('common.confirm') }}
        </button>
      </div>
    </div>
  </div>
</template>
