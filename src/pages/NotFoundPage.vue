<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
const { t } = useI18n()
</script>
<template>
  <section class="card mt-10 text-center">
    <p class="text-4xl font-bold text-brand-700">404</p>
    <p class="mt-2 text-sm text-slate-600">{{ t('errors.NOT_FOUND') }}</p>
    <RouterLink class="btn-primary mt-4 inline-flex" :to="{ name: 'home' }">{{ t('nav.home') }}</RouterLink>
  </section>
</template>
