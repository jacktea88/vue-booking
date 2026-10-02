<script setup lang="ts">
import { useI18n } from 'vue-i18n'
defineProps<{ open: boolean; title: string; message?: string; confirmLabel?: string; danger?: boolean; busy?: boolean }>()
const emit = defineEmits<{ confirm: []; close: [] }>()
const { t } = useI18n()
</script>

<template>
  <div v-if="open" class="fixed inset-0 z-50 flex items-end justify-center bg-slate-900/50 p-0 sm:items-center sm:p-4"
       role="dialog" aria-modal="true" :aria-label="title" @keydown.esc="emit('close')">
    <div class="w-full max-w-md rounded-t-2xl bg-white p-5 shadow-xl sm:rounded-2xl">
      <h2 class="text-base font-semibold text-slate-900">{{ title }}</h2>
      <p v-if="message" class="mt-2 text-sm text-slate-600">{{ message }}</p>
      <slot />
      <div class="mt-5 flex justify-end gap-2">
        <button class="btn-secondary" @click="emit('close')">{{ t('common.cancel') }}</button>
        <button :class="danger ? 'btn-danger' : 'btn-primary'" :disabled="busy" @click="emit('confirm')">
          {{ confirmLabel ?? t('common.confirm') }}
        </button>
      </div>
    </div>
  </div>
</template>
