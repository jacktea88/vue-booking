<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { AsyncState } from '@/types'
import type { AppError } from '@/types/errors'

defineProps<{ state: AsyncState; error?: AppError | null; emptyText?: string }>()
defineEmits<{ retry: [] }>()
const { t } = useI18n()
</script>

<template>
  <div v-if="state === 'loading'" class="space-y-3" role="status" :aria-label="t('states.loading')">
    <div v-for="i in 3" :key="i" class="h-20 animate-pulse rounded-xl bg-slate-200/70" />
  </div>
  <div v-else-if="state === 'error'" class="card text-center">
    <p class="text-sm text-red-700">{{ error ? t(error.i18nKey) : t('states.error') }}</p>
    <button class="btn-secondary mt-3" @click="$emit('retry')">{{ t('common.retry') }}</button>
  </div>
  <div v-else-if="state === 'empty'" class="card text-center text-sm text-slate-500">
    {{ emptyText ?? t('states.empty') }}
  </div>
  <slot v-else />
</template>
