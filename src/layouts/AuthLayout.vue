<script setup lang="ts">
import LanguageSwitcher from '@/components/LanguageSwitcher.vue'
import { useI18n } from 'vue-i18n'
const { t } = useI18n()
</script>

<template>
  <div class="flex min-h-dvh flex-col bg-slate-50">
    <header class="flex items-center justify-between p-4">
      <span class="text-lg font-bold text-brand-700">{{ t('app.name') }}</span>
      <LanguageSwitcher />
    </header>
    <main class="mx-auto w-full max-w-md flex-1 px-4 pb-10">
      <slot />
    </main>
  </div>
</template>
