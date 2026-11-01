<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
const { t } = useI18n()
</script>
<template>
  <section class="card card-body rounded-3 shadow-sm mt-5 text-center">
    <p class="fs-1 fw-bold text-primary mb-0">404</p>
    <p class="mt-2 small text-secondary">{{ t('errors.NOT_FOUND') }}</p>
    <RouterLink class="btn btn-primary mt-3" :to="{ name: 'home' }">{{ t('nav.home') }}</RouterLink>
  </section>
</template>
