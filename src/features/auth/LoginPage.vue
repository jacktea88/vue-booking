<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { toAppError } from '@/types/errors'
import { isLineLoginEnabled, startLineLogin } from '@/services/auth/line'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref<string | null>(null)
const lineEnabled = isLineLoginEnabled()

function loginWithLine() {
  error.value = null
  try {
    window.location.assign(startLineLogin((route.query.redirect as string) || null))
  } catch { error.value = t('auth.lineLoginFailed') }
}

async function submit() {
  error.value = null
  try {
    await auth.signIn(email.value, password.value)
    const redirect = (route.query.redirect as string) || null
    if (redirect) await router.push(redirect)
    else await router.push({ name: auth.isAdmin ? 'admin' : auth.isDriver ? 'driver-home' : 'home' })
  } catch (e) { error.value = t(toAppError(e).i18nKey) }
}
</script>

<template>
  <section class="card card-body mt-4 rounded-3 shadow-sm">
    <h1 class="fs-4 fw-bold">{{ t('auth.login') }}</h1>
    <p class="mt-1 small text-secondary">{{ t('app.tagline') }}</p>
    <form class="d-flex flex-column gap-3 mt-3" @submit.prevent="submit">
      <div>
        <label class="form-label" for="email">{{ t('auth.email') }}</label>
        <input id="email" v-model="email" class="form-control" type="email" required autocomplete="email" />
      </div>
      <div>
        <label class="form-label" for="password">{{ t('auth.password') }}</label>
        <input id="password" v-model="password" class="form-control" type="password" required autocomplete="current-password" />
      </div>
      <p v-if="error" class="small text-danger mb-0" role="alert">{{ error }}</p>
      <button class="btn btn-primary w-100" :disabled="auth.loading" type="submit">
        {{ auth.loading ? t('auth.signingIn') : t('auth.login') }}
      </button>
    </form>
    <template v-if="lineEnabled">
      <div class="my-3 d-flex align-items-center gap-3 small text-muted">
        <span class="flex-grow-1 border-top"></span>{{ t('auth.lineOr') }}<span class="flex-grow-1 border-top"></span>
      </div>
      <button class="btn btn-outline-secondary w-100" type="button" :disabled="auth.loading" @click="loginWithLine">
        {{ t('auth.lineLogin') }}
      </button>
    </template>
    <div class="mt-3 d-flex align-items-center justify-content-between small">
      <RouterLink class="text-primary" :to="{ name: 'forgot' }">{{ t('auth.forgot') }}</RouterLink>
      <RouterLink class="text-primary" :to="{ name: 'register' }">{{ t('auth.register') }}</RouterLink>
    </div>
  </section>
</template>
