<script setup lang="ts">
import { useLocaleStore } from '@/stores/locale'
import { LOCALE_LABELS, SUPPORTED_LOCALES, type AppLocale } from '@/i18n'
import { useI18n } from 'vue-i18n'

const locale = useLocaleStore()
const { t } = useI18n()
</script>

<template>
  <label class="d-inline-flex align-items-center gap-2 mb-0">
    <span class="visually-hidden">{{ t('common.language') }}</span>
    <select
      class="form-select form-select-sm w-auto"
      :value="locale.current"
      @change="locale.set(($event.target as HTMLSelectElement).value as AppLocale)"
    >
      <option v-for="l in SUPPORTED_LOCALES" :key="l" :value="l">{{ LOCALE_LABELS[l] }}</option>
    </select>
  </label>
</template>
