<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { AsyncState } from '@/types'
import type { AppError } from '@/types/errors'

defineProps<{ state: AsyncState; error?: AppError | null; emptyText?: string }>()
defineEmits<{ retry: [] }>()
const { t } = useI18n()
</script>

<template>
  <div v-if="state === 'loading'" class="d-flex flex-column gap-3" role="status" :aria-label="t('states.loading')">
    <div v-for="i in 3" :key="i" class="placeholder-glow">
      <span class="placeholder w-100 rounded-3" style="height: 5rem" />
    </div>
  </div>
  <div v-else-if="state === 'error'" class="card card-body rounded-3 shadow-sm text-center">
    <p class="small text-danger mb-0">{{ error ? t(error.i18nKey) : t('states.error') }}</p>
    <button class="btn btn-outline-secondary mt-3" @click="$emit('retry')">{{ t('common.retry') }}</button>
  </div>
  <div v-else-if="state === 'empty'" class="card card-body rounded-3 shadow-sm text-center small text-secondary">
    {{ emptyText ?? t('states.empty') }}
  </div>
  <slot v-else />
</template>
