<script setup lang="ts">
import { useLocaleStore } from '@/stores/locale'
import { LOCALE_LABELS, SUPPORTED_LOCALES, type AppLocale } from '@/i18n'
import { useI18n } from 'vue-i18n'

const locale = useLocaleStore()
const { t } = useI18n()
</script>

<template>
  <label class="inline-flex items-center gap-2">
    <span class="sr-only">{{ t('common.language') }}</span>
    <select
      class="rounded-lg border border-slate-300 bg-white px-2 py-1.5 text-sm"
      :value="locale.current"
      @change="locale.set(($event.target as HTMLSelectElement).value as AppLocale)"
    >
      <option v-for="l in SUPPORTED_LOCALES" :key="l" :value="l">{{ LOCALE_LABELS[l] }}</option>
    </select>
  </label>
</template>
