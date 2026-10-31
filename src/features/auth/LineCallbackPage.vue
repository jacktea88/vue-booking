<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { parseLineCallback } from '@/services/auth/line'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const error = ref<string | null>(null)

onMounted(async () => {
  const params = parseLineCallback(window.location.search)
  if (params.error) {
    error.value = params.error === 'access_denied' ? t('auth.lineLoginCancelled') : t('auth.lineLoginFailed')
    return
  }
  if (!params.code || !params.state) {
    error.value = t('auth.lineLoginFailed')
    return
  }
  try {
    const redirectPath = await auth.signInWithLine(params.code, params.state)
    await router.replace(redirectPath ?? { name: auth.isAdmin ? 'admin' : auth.isDriver ? 'driver-home' : 'home' })
  } catch {
    error.value = t('auth.lineLoginFailed')
  }
})
</script>

<template>
  <section class="card mt-6 text-center">
    <p v-if="!error" class="text-sm text-slate-600" role="status">{{ t('auth.lineSigningIn') }}</p>
    <template v-else>
      <p class="text-sm text-red-700" role="alert">{{ error }}</p>
      <RouterLink class="btn-primary mt-4 inline-block" :to="{ name: 'login' }">{{ t('auth.login') }}</RouterLink>
    </template>
  </section>
</template>
