<script setup lang="ts">
import LanguageSwitcher from '@/components/LanguageSwitcher.vue'
import { useI18n } from 'vue-i18n'
const { t } = useI18n()
</script>

<template>
  <div class="d-flex flex-column min-h-dvh bg-light">
    <header class="d-flex align-items-center justify-content-between p-3">
      <span class="fs-5 fw-bold text-primary">{{ t('app.name') }}</span>
      <LanguageSwitcher />
    </header>
    <main class="mx-auto w-100 mw-md flex-grow-1 px-3 pb-5">
      <slot />
    </main>
  </div>
</template>
